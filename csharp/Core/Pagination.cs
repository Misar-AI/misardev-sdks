using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace MisarDev;

/// <summary>
/// Offset pagination.
/// </summary>
/// <remarks>
/// List endpoints that take <c>limit</c>/<c>offset</c> (templates, gallery, API
/// keys…) return one page at a time. <see cref="Paginate"/> walks every page:
/// it calls <c>fetchPage(offset, limit)</c>, yields each item, and stops on a
/// short page. Items are read from the response itself when it is an array,
/// otherwise from its first array-valued field (<c>templates</c>, <c>items</c>,
/// <c>keys</c>, …).
/// <code>
/// await foreach (var t in Pagination.Paginate((offset, limit) =>
///     dev.Templates.List(query: new { offset, limit })))
///     Console.WriteLine(t?["name"]);
/// </code>
/// </remarks>
public static class Pagination
{
    /// <summary>The items of one page: the page itself when it is an array, else its first array-valued field.</summary>
    public static IReadOnlyList<JsonNode?> ItemsOf(JsonNode? page)
    {
        if (page is JsonArray array) return array.ToList();
        if (page is JsonObject obj)
        {
            foreach (var (_, value) in obj)
                if (value is JsonArray inner) return inner.ToList();
        }
        return Array.Empty<JsonNode?>();
    }

    /// <summary>Yield every item across pages until a short page, or <paramref name="maxItems"/>.</summary>
    public static async IAsyncEnumerable<JsonNode?> Paginate(
        Func<int, int, Task<JsonNode?>> fetchPage,
        int pageSize = 50,
        int? maxItems = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        if (pageSize <= 0) throw new ArgumentOutOfRangeException(nameof(pageSize));
        int max = maxItems ?? int.MaxValue;
        int offset = 0;
        int yielded = 0;
        while (yielded < max)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var items = ItemsOf(await fetchPage(offset, pageSize).ConfigureAwait(false));
            foreach (var item in items)
            {
                if (yielded >= max) yield break;
                yield return item;
                yielded++;
            }
            if (items.Count < pageSize) yield break;
            offset += items.Count;
        }
    }
}
