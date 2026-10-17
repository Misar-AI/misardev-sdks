import Foundation

/// Offset pagination.
///
/// List endpoints that take `limit`/`offset` (templates, gallery, API keys…)
/// return one page at a time. ``paginate(pageSize:maxItems:_:)`` walks every
/// page: it calls `fetchPage(offset, limit)`, yields each item, and stops on a
/// short page. Items are read from the response itself when it is an array,
/// otherwise from its first array-valued field (`templates`, `items`, `keys`, …).
///
/// ```swift
/// for try await template in paginate(pageSize: 50, { offset, limit in
///     try await dev.templates.list(query: ["offset": .init(offset), "limit": .init(limit)])
/// }) {
///     print(template["name"]?.stringValue ?? "")
/// }
/// ```
public enum Pagination {
    /// The items of one page: the page itself when it is an array, else its first array-valued field.
    public static func items(of page: JSONValue) -> [JSONValue] {
        switch page {
        case .array(let items):
            return items
        case .object(let object):
            // Dictionary order is unspecified; take the first array by key order
            // so the choice is stable when a page has more than one.
            for key in object.keys.sorted() {
                if case .array(let items)? = object[key] { return items }
            }
            return []
        default:
            return []
        }
    }
}

/// Yield every item across offset pages until a short page, or `maxItems`.
public func paginate(
    pageSize: Int = 50,
    maxItems: Int? = nil,
    _ fetchPage: @escaping @Sendable (_ offset: Int, _ limit: Int) async throws -> JSONValue
) -> AsyncThrowingStream<JSONValue, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let max = maxItems ?? Int.max
                var offset = 0
                var yielded = 0
                pages: while yielded < max {
                    try Task.checkCancellation()
                    let items = Pagination.items(of: try await fetchPage(offset, pageSize))
                    for item in items {
                        if yielded >= max { break pages }
                        continuation.yield(item)
                        yielded += 1
                    }
                    if items.count < pageSize { break }
                    offset += items.count
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
