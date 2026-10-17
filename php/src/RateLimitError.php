<?php

declare(strict_types=1);

namespace MisarDev;

/**
 * 429 that is an ordinary throttle (identical for every user).
 *
 * Wait $retryAfter seconds and try again — the transport already did so
 * `maxRetries` times before throwing this.
 */
class RateLimitError extends MisarDevError
{
    /**
     * @param float|null $retryAfter Seconds the server asked us to wait, when it said.
     */
    public function __construct(
        int $status,
        string $message,
        ?string $errorCode = null,
        mixed $body = null,
        ?string $requestId = null,
        public readonly ?float $retryAfter = null,
    ) {
        parent::__construct($status, $message, $errorCode, $body, $requestId);
    }
}
