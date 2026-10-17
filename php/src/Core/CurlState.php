<?php

declare(strict_types=1);

namespace MisarDev\Core;

/** @internal Mutable state shared between cURL callbacks. */
final class CurlState
{
    public int $status = 0;
    public string $reason = '';
    /** @var array<string,string> */
    public array $headers = [];
    public bool $headersDone = false;
    /** @var list<string> */
    public array $chunks = [];
    public ?string $error = null;
}
