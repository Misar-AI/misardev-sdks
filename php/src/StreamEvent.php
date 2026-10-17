<?php

declare(strict_types=1);

namespace MisarDev;

/**
 * One Server-Sent Event.
 *
 * `$data` is the JSON-decoded `data:` payload (associative arrays), or the raw
 * string when the payload is not JSON. `$event` and `$id` are the `event:` and
 * `id:` fields, when the server sends them.
 */
final class StreamEvent
{
    public function __construct(
        public readonly ?string $event,
        public readonly mixed $data,
        public readonly ?string $id,
    ) {
    }
}
