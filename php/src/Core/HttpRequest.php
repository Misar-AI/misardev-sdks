<?php

declare(strict_types=1);

namespace MisarDev\Core;

/** One outgoing HTTP request, as handed to an {@see HttpClient}. */
final class HttpRequest
{
    /**
     * @param array<string,string> $headers
     * @param float                $timeout Seconds for the whole exchange; 0 means no limit (streams).
     */
    public function __construct(
        public readonly string $method,
        public readonly string $url,
        public readonly array $headers,
        public readonly ?string $body,
        public readonly float $timeout,
    ) {
    }
}
