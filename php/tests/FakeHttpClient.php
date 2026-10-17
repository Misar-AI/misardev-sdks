<?php

declare(strict_types=1);

namespace MisarDev\Tests;

use MisarDev\Core\HttpClient;
use MisarDev\Core\HttpRequest;
use MisarDev\Core\HttpResponse;
use MisarDev\Core\StreamResponse;
use MisarDev\MisarDev;

/**
 * Records every request and answers from a queue. The last queued answer is
 * repeated once the queue runs dry, so "always 429" is a one-element queue.
 */
final class FakeHttpClient implements HttpClient
{
    /** @var list<HttpRequest> */
    public array $requests = [];

    /** @param list<HttpResponse|StreamResponse|\Throwable> $responses */
    public function __construct(private array $responses = [])
    {
    }

    private function next(): HttpResponse|StreamResponse|\Throwable
    {
        if ($this->responses === []) {
            return self::json(['ok' => true]);
        }
        return count($this->responses) > 1 ? array_shift($this->responses) : $this->responses[0];
    }

    public function send(HttpRequest $request): HttpResponse
    {
        $this->requests[] = $request;
        $next = $this->next();
        if ($next instanceof \Throwable) {
            throw $next;
        }
        if ($next instanceof StreamResponse) {
            return new HttpResponse($next->status, $next->headers, $next->readAll());
        }
        return $next;
    }

    public function stream(HttpRequest $request): StreamResponse
    {
        $this->requests[] = $request;
        $next = $this->next();
        if ($next instanceof \Throwable) {
            throw $next;
        }
        if ($next instanceof HttpResponse) {
            return new StreamResponse($next->status, $next->headers, [$next->body], $next->reason);
        }
        return $next;
    }

    /** The decoded JSON body of request $i. */
    public function body(int $i = 0): mixed
    {
        $raw = $this->requests[$i]->body;
        return $raw === null ? null : json_decode($raw, true);
    }

    /** @param array<string,string> $headers */
    public static function json(mixed $body, int $status = 200, array $headers = []): HttpResponse
    {
        return new HttpResponse($status, array_change_key_case($headers + ['content-type' => 'application/json']), json_encode($body));
    }

    /** @param list<string> $frames Each one is delivered as its own chunk. */
    public static function sse(array $frames, int $status = 200): StreamResponse
    {
        return new StreamResponse($status, ['content-type' => 'text/event-stream'], $frames);
    }

    /**
     * @param list<HttpResponse|StreamResponse|\Throwable> $responses
     * @return array{0: MisarDev, 1: FakeHttpClient}
     */
    public static function client(array $responses = [], int $maxRetries = 3): array
    {
        $http = new self($responses);
        return [new MisarDev('mdk_test_key', baseUrl: 'https://api.test/dev', maxRetries: $maxRetries, httpClient: $http), $http];
    }

    /** @return array<string,mixed> */
    public static function planLimitBody(): array
    {
        return json_decode(<<<'JSON'
        {"error":"API access requires the Pro plan or higher.","code":"plan_limit_exceeded","requiredPlan":"pro",
         "upgrade":{"product":"dev","product_name":"Misar.Dev","reason":"feature_locked","feature":"api_access",
         "feature_label":"API access","headline":"API access isn't included in your Starter plan.","usage":null,
         "current_plan":{"slug":"starter","name":"Starter"},"recommended_plan":"pro","plans":[],"topup":null,
         "overage":null,"trial":null,"cross_sell":[],
         "urls":{"pricing":"https://www.misar.dev/pricing","billing":"https://www.misar.dev/settings/billing",
         "docs":"https://docs.misar.io/dev/api","compare":"https://www.misar.dev/pricing#compare"},
         "cta":"Upgrade to Pro to continue."}}
        JSON, true, 512, JSON_THROW_ON_ERROR);
    }
}
