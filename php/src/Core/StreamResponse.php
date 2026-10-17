<?php

declare(strict_types=1);

namespace MisarDev\Core;

/**
 * An HTTP response whose body arrives in pieces. Status and headers are known
 * up front; `$chunks` yields the body as it is read off the wire.
 */
final class StreamResponse
{
    /**
     * @param array<string,string> $headers Lower-cased header names.
     * @param iterable<string>     $chunks
     */
    public function __construct(
        public readonly int $status,
        public readonly array $headers,
        public readonly iterable $chunks,
        public readonly string $reason = '',
    ) {
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    /** Read whatever is left of the body into one string. */
    public function readAll(): string
    {
        $out = '';
        foreach ($this->chunks as $chunk) {
            $out .= $chunk;
        }
        return $out;
    }
}
