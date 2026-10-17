<?php

declare(strict_types=1);

namespace MisarDev\Core;

/**
 * Offset pagination.
 *
 * List endpoints that take `limit`/`offset` (templates, gallery, API keys…)
 * return one page at a time. {@see Pagination::paginate()} walks every page:
 * it calls `$fetchPage($offset, $limit)`, yields each item, and stops on a
 * short page. Items are read from the response itself when it is a list,
 * otherwise from its first list-valued field (`templates`, `items`, `keys`, …).
 *
 *     foreach ($dev->paginate(fn ($offset, $limit) =>
 *         $dev->templates->list(['offset' => $offset, 'limit' => $limit])) as $t) { … }
 */
final class Pagination
{
    /** @return list<mixed> */
    public static function itemsOf(mixed $page): array
    {
        if (is_array($page)) {
            if (array_is_list($page)) {
                return $page;
            }
            foreach ($page as $value) {
                if (is_array($value) && array_is_list($value)) {
                    return $value;
                }
            }
        }
        return [];
    }

    /**
     * @param callable(int, int): mixed $fetchPage
     * @return \Generator<int, mixed>
     */
    public static function paginate(callable $fetchPage, int $pageSize = 50, ?int $maxItems = null): \Generator
    {
        $offset = 0;
        $yielded = 0;
        while ($maxItems === null || $yielded < $maxItems) {
            $items = self::itemsOf($fetchPage($offset, $pageSize));
            foreach ($items as $item) {
                if ($maxItems !== null && $yielded >= $maxItems) {
                    return;
                }
                yield $item;
                $yielded++;
            }
            if (count($items) < $pageSize) {
                return;
            }
            $offset += count($items);
        }
    }
}
