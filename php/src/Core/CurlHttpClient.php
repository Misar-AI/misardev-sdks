<?php

declare(strict_types=1);

namespace MisarDev\Core;

/**
 * Default HTTP client: ext-curl, nothing else.
 *
 * Streams use curl_multi so the body can be handed out chunk by chunk as a
 * Generator, instead of buffering a whole build log or completion in memory.
 */
final class CurlHttpClient implements HttpClient
{
    public function __construct(private readonly float $connectTimeout = 10.0)
    {
    }

    public function send(HttpRequest $request): HttpResponse
    {
        $state = new CurlState();
        $ch = $this->handle($request, $state);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

        $body = curl_exec($ch);
        $errno = curl_errno($ch);
        $error = curl_error($ch);
        if ($errno !== 0) {
            throw new \RuntimeException("cURL error ({$errno}): {$error}");
        }
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

        return new HttpResponse($status, $state->headers, is_string($body) ? $body : '', $state->reason);
    }

    public function stream(HttpRequest $request): StreamResponse
    {
        $state = new CurlState();
        $ch = $this->handle($request, $state);
        curl_setopt($ch, CURLOPT_WRITEFUNCTION, static function ($_ch, string $chunk) use ($state): int {
            $state->chunks[] = $chunk;
            return strlen($chunk);
        });

        $mh = curl_multi_init();
        curl_multi_add_handle($mh, $ch);
        $running = true;

        $pump = static function () use ($mh, $state, &$running): void {
            do {
                $code = curl_multi_exec($mh, $active);
            } while ($code === CURLM_CALL_MULTI_PERFORM);
            while (($info = curl_multi_info_read($mh)) !== false) {
                if ($info['result'] !== CURLE_OK) {
                    $state->error = 'cURL error (' . $info['result'] . '): ' . curl_strerror($info['result']);
                }
            }
            $running = $active > 0 && $code === CURLM_OK;
            if ($running && $state->chunks === [] && curl_multi_select($mh, 0.5) === -1) {
                usleep(1000); // no socket to wait on yet
            }
        };

        $close = static function () use ($mh, $ch): void {
            curl_multi_remove_handle($mh, $ch);
            curl_multi_close($mh);
        };

        // Run until the status line and headers are in, so the caller can map
        // an error status before reading any body.
        while (!$state->headersDone && $running) {
            $pump();
        }
        if ($state->error !== null || !$state->headersDone) {
            $close();
            throw new \RuntimeException($state->error ?? 'connection closed before a response arrived');
        }

        $chunks = (static function () use ($state, $pump, $close, &$running): \Generator {
            try {
                while (true) {
                    while ($state->chunks !== []) {
                        yield array_shift($state->chunks);
                    }
                    if (!$running) {
                        break;
                    }
                    $pump();
                }
                if ($state->error !== null) {
                    throw new \RuntimeException($state->error);
                }
            } finally {
                $close();
            }
        })();

        return new StreamResponse($state->status, $state->headers, $chunks, $state->reason);
    }

    /** @return \CurlHandle */
    private function handle(HttpRequest $request, CurlState $state)
    {
        $headers = [];
        foreach ($request->headers as $name => $value) {
            $headers[] = "{$name}: {$value}";
        }
        // Without this, cURL adds `Expect: 100-continue` to larger bodies.
        $headers[] = 'Expect:';

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $request->url,
            CURLOPT_CUSTOMREQUEST => $request->method,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT_MS => (int) round($this->connectTimeout * 1000),
            CURLOPT_TIMEOUT_MS => (int) round($request->timeout * 1000),
            CURLOPT_HEADERFUNCTION => static function ($_ch, string $line) use ($state): int {
                $trimmed = trim($line);
                if (preg_match('~^HTTP/[\d.]+\s+(\d{3})\s*(.*)$~', $trimmed, $m) === 1) {
                    $state->status = (int) $m[1];
                    $state->reason = $m[2];
                    $state->headers = [];
                } elseif ($trimmed === '') {
                    // End of a header block; a 1xx block is followed by the real one.
                    if ($state->status >= 200) {
                        $state->headersDone = true;
                    }
                } else {
                    $parts = explode(':', $trimmed, 2);
                    if (count($parts) === 2) {
                        $state->headers[strtolower(trim($parts[0]))] = trim($parts[1]);
                    }
                }
                return strlen($line);
            },
        ]);
        if ($request->body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $request->body);
        }
        return $ch;
    }
}

