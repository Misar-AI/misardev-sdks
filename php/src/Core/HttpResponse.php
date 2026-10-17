<?php

declare(strict_types=1);

namespace MisarDev\Core;

/** A complete HTTP response. Header names are lower-cased. */
final class HttpResponse
{
    /**
     * @param array<string,string> $headers
     */
    public function __construct(
        public readonly int $status,
        public readonly array $headers = [],
        public readonly string $body = '',
        public readonly string $reason = '',
    ) {
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }
}
