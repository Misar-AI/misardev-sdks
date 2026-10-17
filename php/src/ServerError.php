<?php

declare(strict_types=1);

namespace MisarDev;

/** 5xx — the API failed. Retried automatically for idempotent requests. */
class ServerError extends MisarDevError
{
}
