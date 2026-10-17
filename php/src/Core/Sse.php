<?php

declare(strict_types=1);

namespace MisarDev\Core;

use MisarDev\StreamEvent;

/**
 * Server-Sent Events parsing.
 *
 * Frames are separated by a blank line (`\n\n` or `\r\n\r\n`) and may span
 * several `data:` lines, which are joined with newlines per the SSE spec.
 * Comment lines (`:`) are keep-alives and are skipped. The terminator payload —
 * `[DONE]` on the OpenAI-compatible `/v1/chat/completions` stream — ends
 * iteration and is never yielded. A null terminator reads to EOF.
 */
final class Sse
{
    /**
     * Parse one complete frame (the text between blank lines).
     *
     * @return array{event: ?string, data: ?string, id: ?string}
     */
    public static function parseFrame(string $frame): array
    {
        $event = null;
        $id = null;
        $data = [];
        foreach (preg_split('~\r?\n~', $frame) ?: [] as $line) {
            if ($line === '' || $line[0] === ':') {
                continue;
            }
            $idx = strpos($line, ':');
            $field = $idx === false ? $line : substr($line, 0, $idx);
            $value = $idx === false ? '' : substr($line, $idx + 1);
            if (str_starts_with($value, ' ')) {
                $value = substr($value, 1);
            }
            if ($field === 'data') {
                $data[] = $value;
            } elseif ($field === 'event') {
                $event = $value;
            } elseif ($field === 'id') {
                $id = $value;
            }
        }
        return ['event' => $event, 'data' => $data === [] ? null : implode("\n", $data), 'id' => $id];
    }

    /** JSON-decode a payload when possible, else hand back the raw string. */
    public static function decode(string $raw): mixed
    {
        try {
            return json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return $raw;
        }
    }

    /**
     * Iterate the events of a `text/event-stream` body.
     *
     * @param iterable<string> $chunks
     * @return \Generator<int, StreamEvent>
     */
    public static function parse(iterable $chunks, ?string $terminator = '[DONE]'): \Generator
    {
        $buffer = '';
        foreach ($chunks as $chunk) {
            $buffer .= $chunk;
            while (preg_match('~\r?\n\r?\n~', $buffer, $m, PREG_OFFSET_CAPTURE) === 1) {
                $at = $m[0][1];
                $frame = substr($buffer, 0, $at);
                $buffer = substr($buffer, $at + strlen($m[0][0]));
                $parsed = self::parseFrame($frame);
                if ($parsed['data'] === null) {
                    continue;
                }
                if ($terminator !== null && trim($parsed['data']) === $terminator) {
                    return;
                }
                yield new StreamEvent($parsed['event'], self::decode($parsed['data']), $parsed['id']);
            }
        }
        // A trailing frame the server never terminated with a blank line.
        $parsed = self::parseFrame($buffer);
        if ($parsed['data'] !== null && !($terminator !== null && trim($parsed['data']) === $terminator)) {
            yield new StreamEvent($parsed['event'], self::decode($parsed['data']), $parsed['id']);
        }
    }
}
