/**
 * Offset pagination.
 *
 * List endpoints that take `limit`/`offset` (templates, gallery, API keys…)
 * return one page at a time. {@link paginate} walks every page for you: it
 * calls `fetchPage(offset, limit)`, yields each item, and stops on a short
 * page. Items are read from the response itself when it is an array, otherwise
 * from its first array-valued field (`templates`, `items`, `keys`, …).
 *
 * @example
 * for await (const t of paginate((offset, limit) => dev.templates.list({ offset, limit }))) {
 *   console.log(t);
 * }
 */

export function itemsOf<T = unknown>(page: unknown): T[] {
  if (Array.isArray(page)) return page as T[];
  if (page && typeof page === "object") {
    for (const value of Object.values(page as Record<string, unknown>)) {
      if (Array.isArray(value)) return value as T[];
    }
  }
  return [];
}

export async function* paginate<T = unknown>(
  fetchPage: (offset: number, limit: number) => Promise<unknown>,
  options: { pageSize?: number; maxItems?: number } = {},
): AsyncGenerator<T, void, unknown> {
  const pageSize = options.pageSize ?? 50;
  const max = options.maxItems ?? Infinity;
  let offset = 0;
  let yielded = 0;
  while (yielded < max) {
    const items = itemsOf<T>(await fetchPage(offset, pageSize));
    for (const item of items) {
      if (yielded >= max) return;
      yield item;
      yielded++;
    }
    if (items.length < pageSize) return;
    offset += items.length;
  }
}
