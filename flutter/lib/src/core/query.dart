/// Query-string and path encoding shared by every generated method.
library;

/// Encode a query map as `?k=v&…`.
///
/// Null values are dropped, booleans are sent as `true` / `false`, everything
/// else is stringified, and keys and values are URL-encoded. Returns `''` for
/// an empty (or all-null) map so a call site can always append it.
String encodeQuery(Map<String, Object?>? query) {
  if (query == null || query.isEmpty) return '';
  final pairs = <String>[];
  query.forEach((key, value) {
    if (value == null) return;
    pairs.add('${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(_stringify(value))}');
  });
  return pairs.isEmpty ? '' : '?${pairs.join('&')}';
}

String _stringify(Object value) {
  if (value is bool) return value ? 'true' : 'false';
  return value.toString();
}

/// Encode one path parameter as a single path segment: `a b/c` → `a%20b%2Fc`.
String encodePathSegment(Object value) => Uri.encodeComponent(value.toString());
