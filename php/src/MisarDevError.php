<?php

declare(strict_types=1);

namespace MisarDev;

/**
 * Base class for every error the SDK throws.
 *
 * Every non-2xx answer becomes a MisarDevError; the subclasses let a caller
 * branch on the kind of failure without parsing strings. `catch (MisarDevError $e)`
 * catches everything the SDK throws.
 */
class MisarDevError extends \RuntimeException
{
    /**
     * @param int         $status    HTTP status, or 0 when the request never got an answer.
     * @param string|null $errorCode Machine-readable error code from the body, when the API sends one.
     * @param mixed       $body      The decoded error body, for anything this class does not surface.
     * @param string|null $requestId The `x-request-id` header, for support requests.
     */
    public function __construct(
        public readonly int $status,
        string $message,
        public readonly ?string $errorCode = null,
        public readonly mixed $body = null,
        public readonly ?string $requestId = null,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $status, $previous);
    }

    /** Worth retrying as-is: a throttle or a transient server condition. */
    public function isRetryable(): bool
    {
        return $this->status === 429 || ($this->status >= 500 && $this->status < 600);
    }
}
