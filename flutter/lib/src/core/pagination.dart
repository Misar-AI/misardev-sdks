/// Offset pagination.
///
/// List endpoints that take `limit` / `offset` (templates, gallery, API keys…)
/// return one page at a time. [paginate] walks every page for you: it calls
/// `fetchPage(offset, limit)`, yields each item, and stops on a short page.
/// Items are read from the response itself when it is a list, otherwise from
/// its first list-valued field (`templates`, `items`, `keys`, …).
///
/// ```dart
/// await for (final t in paginate((offset, limit) =>
///     dev.templates.list({'offset': offset, 'limit': limit}))) {
///   print(t);
/// }
/// ```
library;

/// The items of one page: the page itself when it is a list, else its first
/// list-valued field, else empty.
List<dynamic> itemsOf(Object? page) {
  if (page is List) return page;
  if (page is Map) {
    for (final value in page.values) {
      if (value is List) return value;
    }
  }
  return const [];
}

/// Walk every page of an offset-paginated list, yielding each item.
///
/// [pageSize] is passed to `fetchPage` as `limit`; [maxItems] caps the total
/// number of items yielded.
Stream<dynamic> paginate(
  Future<Object?> Function(int offset, int limit) fetchPage, {
  int pageSize = 50,
  int? maxItems,
}) async* {
  var offset = 0;
  var yielded = 0;
  while (maxItems == null || yielded < maxItems) {
    final items = itemsOf(await fetchPage(offset, pageSize));
    for (final item in items) {
      if (maxItems != null && yielded >= maxItems) return;
      yield item;
      yielded++;
    }
    if (items.length < pageSize) return;
    offset += items.length;
  }
}
