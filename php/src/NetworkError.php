<?php

declare(strict_types=1);

namespace MisarDev;

/** The request never got an HTTP answer (DNS, TLS, reset, timeout). `$status` is 0. */
class NetworkError extends MisarDevError
{
    public function __construct(string $message, ?\Throwable $previous = null)
    {
        parent::__construct(0, $message, 'network_error', null, null, $previous);
    }
}
