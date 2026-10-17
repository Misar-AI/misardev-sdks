<?php

declare(strict_types=1);

namespace MisarDev\Core;

use MisarDev\AuthenticationError;
use MisarDev\ConflictError;
use MisarDev\MisarDevError;
use MisarDev\NetworkError;
use MisarDev\NotFoundError;
use MisarDev\PermissionDeniedError;
use MisarDev\PlanLimitError;
use MisarDev\RateLimitError;
use MisarDev\ServerError;
use MisarDev\StreamEvent;
use MisarDev\ValidationError;

/**
 * HTTP transport shared by the generated resource layer.
 *
 * Everything the SDK does goes through here, and it authenticates exactly one
 * way: the account API key (`mdk_…`), sent as a bearer token. There is no
 * second credential path. What a key may do — and how much of it — is decided
 * server-side from the subscription behind that key; the SDK carries the key
 * and surfaces the answer rather than deciding locally what a plan allows.
 */
final class Transport
{
    public const DEFAULT_BASE_URL = 'https://api.misar.io/dev';
    public const SDK_VERSION = '1.0.0';

    /** Statuses worth retrying. 429 only when it is NOT a plan limit. */
    private const RETRYABLE = [429, 500, 502, 503, 504];

    /**
     * A 5xx or a dropped connection on a POST may already have done its work —
     * started a build, charged an allowance. Only requests that are safe to
     * repeat are retried on those; a 429 is always safe because the server
     * refused it before doing anything.
     */
    private const IDEMPOTENT = ['GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'];

    private const MAX_BACKOFF = 60.0;

    public readonly string $baseUrl;
    public readonly int $maxRetries;
    public readonly float $timeout;
    private readonly string $apiKey;
    private readonly HttpClient $http;

    /**
     * @param array<string,string> $headers Extra headers sent with every request.
     */
    public function __construct(
        ?string $apiKey = null,
        ?string $baseUrl = null,
        int $maxRetries = 3,
        float $timeout = 60.0,
        ?HttpClient $httpClient = null,
        private readonly array $headers = [],
    ) {
        $key = ($apiKey !== null && $apiKey !== '') ? $apiKey : self::env('MISARDEV_API_KEY');
        if ($key === null || $key === '') {
            throw new MisarDevError(
                0,
                'A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. '
                . 'Create one at https://www.misar.dev/settings/api-keys.',
                'missing_api_key',
            );
        }
        $this->apiKey = $key;
        $base = ($baseUrl !== null && $baseUrl !== '') ? $baseUrl : (self::env('MISARDEV_BASE_URL') ?? self::DEFAULT_BASE_URL);
        $this->baseUrl = rtrim($base, '/');
        $this->maxRetries = max(1, $maxRetries);
        $this->timeout = $timeout;
        $this->http = $httpClient ?? new CurlHttpClient();
    }

    private static function env(string $name): ?string
    {
        $v = getenv($name);
        if (is_string($v) && $v !== '') {
            return $v;
        }
        $v = $_ENV[$name] ?? $_SERVER[$name] ?? null;
        return is_string($v) && $v !== '' ? $v : null;
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    /** Path-segment encoding: `a b/c` → `a%20b%2Fc`. */
    public static function segment(string|int $value): string
    {
        return rawurlencode((string) $value);
    }

    /**
     * Build a query string. Null values are dropped, booleans are sent as
     * `true`/`false`, a list value repeats the key.
     *
     * @param array<string,mixed>|null $query
     */
    public static function buildQuery(?array $query): string
    {
        if ($query === null || $query === []) {
            return '';
        }
        $pairs = [];
        foreach ($query as $key => $value) {
            foreach (is_array($value) ? $value : [$value] as $v) {
                if ($v === null) {
                    continue;
                }
                $s = is_bool($v) ? ($v ? 'true' : 'false') : (string) $v;
                $pairs[] = rawurlencode((string) $key) . '=' . rawurlencode($s);
            }
        }
        return $pairs === [] ? '' : '?' . implode('&', $pairs);
    }

    /** Seconds to wait before attempt `$attempt + 1`: Retry-After when sent, else exponential with jitter. */
    public static function backoff(int $attempt, ?string $retryAfter = null): float
    {
        $hinted = self::retryAfterSeconds($retryAfter);
        if ($hinted !== null) {
            return min($hinted, self::MAX_BACKOFF);
        }
        $base = 0.25 * (2 ** $attempt);
        return min($base + (mt_rand() / mt_getrandmax()) * $base * 0.25, self::MAX_BACKOFF);
    }

    /** Parse a Retry-After header — delta seconds or an HTTP-date — into seconds. */
    public static function retryAfterSeconds(?string $value): ?float
    {
        if ($value === null || trim($value) === '') {
            return null;
        }
        $value = trim($value);
        if (is_numeric($value)) {
            $n = (float) $value;
            return $n >= 0 ? $n : null;
        }
        $ts = strtotime($value);
        return $ts === false ? null : (float) max(0, $ts - time());
    }

    /** True when a body is the plan-limit refusal. */
    public static function isPlanLimitBody(mixed $body): bool
    {
        return is_array($body) && ($body['code'] ?? null) === 'plan_limit_exceeded';
    }

    /** Pull a human message out of the API's several error shapes. */
    private static function messageOf(mixed $body, string $fallback): string
    {
        if (is_array($body)) {
            if (is_string($body['error'] ?? null)) {
                return $body['error'];
            }
            // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
            if (is_array($body['error'] ?? null) && is_string($body['error']['message'] ?? null)) {
                return $body['error']['message'];
            }
            if (is_string($body['message'] ?? null)) {
                return $body['message'];
            }
        }
        if (is_string($body) && trim($body) !== '') {
            return substr(trim($body), 0, 500);
        }
        return $fallback;
    }

    private static function codeOf(mixed $body): ?string
    {
        if (!is_array($body)) {
            return null;
        }
        if (is_string($body['code'] ?? null)) {
            return $body['code'];
        }
        if (is_array($body['error'] ?? null) && is_string($body['error']['code'] ?? null)) {
            return $body['error']['code'];
        }
        return null;
    }

    /**
     * Map an error response to the right typed error. Plan limits first, by `code`.
     *
     * @param array<string,string> $headers Lower-cased header names.
     */
    public static function errorFor(int $status, array $headers, mixed $body, string $reason = ''): MisarDevError
    {
        $requestId = $headers['x-request-id'] ?? null;
        $message = self::messageOf($body, $reason !== '' ? $reason : "HTTP {$status}");
        $code = self::codeOf($body);

        if (self::isPlanLimitBody($body)) {
            $offer = is_array($body['upgrade'] ?? null) ? $body['upgrade'] : null;
            return new PlanLimitError(
                $status,
                $message,
                $body,
                $requestId,
                $offer,
                self::retryAfterSeconds($headers['retry-after'] ?? null),
            );
        }
        return match (true) {
            $status === 400 || $status === 422 => new ValidationError($status, $message, $code, $body, $requestId),
            $status === 401 => new AuthenticationError($status, $message, $code, $body, $requestId),
            $status === 403 => new PermissionDeniedError($status, $message, $code, $body, $requestId),
            $status === 404 => new NotFoundError($status, $message, $code, $body, $requestId),
            $status === 409 => new ConflictError($status, $message, $code, $body, $requestId),
            $status === 429 => new RateLimitError(
                $status,
                $message,
                $code,
                $body,
                $requestId,
                self::retryAfterSeconds($headers['retry-after'] ?? null),
            ),
            $status >= 500 => new ServerError($status, $message, $code, $body, $requestId),
            default => new MisarDevError($status, $message, $code, $body, $requestId),
        };
    }

    /** 204/empty → null; JSON → decoded (associative arrays); anything else → the raw string. */
    public static function decodeBody(int $status, string $text): mixed
    {
        if ($status === 204 || $text === '') {
            return null;
        }
        try {
            return json_decode($text, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return $text;
        }
    }

    /** @param array<mixed>|null $body */
    private static function encodeBody(?array $body): ?string
    {
        if ($body === null) {
            return null;
        }
        // An empty PHP array would encode as `[]`; the API expects an object.
        return $body === [] ? '{}' : json_encode($body, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
    }

    /**
     * @param array<string,string> $extra
     * @return array<string,string>
     */
    private function headersFor(string $accept, array $extra): array
    {
        return array_merge([
            'Authorization' => 'Bearer ' . $this->apiKey,
            'Accept' => $accept,
            'Content-Type' => 'application/json',
            'X-Misar-SDK' => 'misardev-php/' . self::SDK_VERSION,
        ], $this->headers, $extra);
    }

    private static function sleep(float $seconds): void
    {
        if ($seconds > 0) {
            usleep((int) round($seconds * 1_000_000));
        }
    }

    // ── Requests ────────────────────────────────────────────────────────────

    /**
     * Send one request, retrying throttles and (for idempotent verbs) transient failures.
     *
     * @param array<string,mixed>|null $query
     * @param array<mixed>|null        $body    Sent as JSON when not null.
     * @param array<string,string>     $headers Extra headers for this call only.
     * @return mixed Decoded JSON (associative arrays), a raw string, or null for an empty answer.
     * @throws MisarDevError
     */
    public function request(
        string $method,
        string $path,
        ?array $query = null,
        ?array $body = null,
        array $headers = [],
    ): mixed {
        $verb = strtoupper($method);
        $req = new HttpRequest(
            $verb,
            $this->baseUrl . $path . self::buildQuery($query),
            $this->headersFor('application/json', $headers),
            self::encodeBody($body),
            $this->timeout,
        );

        for ($attempt = 0;; $attempt++) {
            $last = $attempt >= $this->maxRetries - 1;
            try {
                $res = $this->http->send($req);
            } catch (MisarDevError $e) {
                throw $e;
            } catch (\Throwable $e) {
                if (!$last && in_array($verb, self::IDEMPOTENT, true)) {
                    self::sleep(self::backoff($attempt));
                    continue;
                }
                throw new NetworkError($e->getMessage() !== '' ? $e->getMessage() : 'Network error', $e);
            }

            $decoded = self::decodeBody($res->status, $res->body);
            if ($res->status >= 200 && $res->status < 300) {
                return $decoded;
            }

            // Read the body BEFORE deciding to retry: a 429 from the rate
            // limiter and a 429 from a spent plan allowance share a status, and
            // only the first is worth retrying.
            $error = self::errorFor($res->status, $res->headers, $decoded, $res->reason);
            if ($error instanceof PlanLimitError) {
                throw $error;
            }
            $retryable = in_array($res->status, self::RETRYABLE, true)
                && ($res->status === 429 || in_array($verb, self::IDEMPOTENT, true));
            if ($retryable && !$last) {
                self::sleep(self::backoff($attempt, $res->header('retry-after')));
                continue;
            }
            throw $error;
        }
    }

    /**
     * Open a Server-Sent Events stream and yield each event.
     *
     * Never retried: a stream that fails mid-flight cannot be replayed without
     * duplicating what the caller already consumed. A
     * `{type:"error", code:"plan_limit_exceeded", upgrade}` frame is raised as
     * a PlanLimitError, exactly as the same refusal on a plain request would be.
     *
     * @param array<string,mixed>|null $query
     * @param array<mixed>|null        $body
     * @param string|null              $terminator Data payload that ends the stream; null reads to EOF.
     * @param array<string,string>     $headers
     * @return \Generator<int, StreamEvent>
     * @throws MisarDevError
     */
    public function stream(
        string $method,
        string $path,
        ?array $query = null,
        ?array $body = null,
        ?string $terminator = '[DONE]',
        array $headers = [],
    ): \Generator {
        $req = new HttpRequest(
            strtoupper($method),
            $this->baseUrl . $path . self::buildQuery($query),
            $this->headersFor('text/event-stream', $headers),
            self::encodeBody($body),
            0.0, // a stream has no fixed duration
        );
        try {
            $res = $this->http->stream($req);
        } catch (MisarDevError $e) {
            throw $e;
        } catch (\Throwable $e) {
            throw new NetworkError($e->getMessage() !== '' ? $e->getMessage() : 'Network error', $e);
        }

        if ($res->status < 200 || $res->status >= 300) {
            $decoded = self::decodeBody($res->status, $res->readAll());
            throw self::errorFor($res->status, $res->headers, $decoded, $res->reason);
        }

        try {
            foreach (Sse::parse($res->chunks, $terminator) as $event) {
                // Other error frames are the stream's own business (the build
                // stream reports a failed step and carries on), so only the plan
                // refusal — which no amount of reading further will fix — is raised.
                if (self::isPlanLimitBody($event->data)) {
                    throw self::errorFor(402, $res->headers, $event->data);
                }
                yield $event;
            }
        } catch (MisarDevError $e) {
            throw $e;
        } catch (\Throwable $e) {
            throw new NetworkError($e->getMessage() !== '' ? $e->getMessage() : 'Network error', $e);
        }
    }
}
