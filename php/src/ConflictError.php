<?php

declare(strict_types=1);

namespace MisarDev;

/** 409 — conflicts with current state (e.g. a build already running). */
class ConflictError extends MisarDevError
{
}
