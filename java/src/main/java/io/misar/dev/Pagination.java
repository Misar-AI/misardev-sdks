package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * Offset pagination.
 *
 * <p>List endpoints that take {@code limit}/{@code offset} (templates, gallery,
 * API keys…) return one page at a time. {@link #paginate} walks every page for
 * you: it calls {@code fetchPage(offset, limit)}, yields each item, and stops
 * on a short page. Items are read from the response itself when it is an
 * array, otherwise from its first array-valued field ({@code templates},
 * {@code items}, {@code keys}, …).
 *
 * <pre>{@code
 * for (JsonNode t : dev.paginate((offset, limit) ->
 *         dev.templates.list(Map.of("offset", offset, "limit", limit)))) {
 *     System.out.println(t.get("name").asText());
 * }
 * }</pre>
 */
public final class Pagination {

    private Pagination() {
    }

    /** Fetches one page. */
    @FunctionalInterface
    public interface PageFetcher {
        JsonNode fetch(int offset, int limit);
    }

    /** The items on one page: the page itself when it is an array, else its first array-valued field. */
    public static List<JsonNode> itemsOf(JsonNode page) {
        if (page == null) return Collections.emptyList();
        List<JsonNode> out = new ArrayList<>();
        if (page.isArray()) {
            page.forEach(out::add);
            return out;
        }
        if (page.isObject()) {
            Iterator<JsonNode> values = page.elements();
            while (values.hasNext()) {
                JsonNode v = values.next();
                if (v.isArray()) {
                    v.forEach(out::add);
                    return out;
                }
            }
        }
        return out;
    }

    /** Walk every page, 50 items at a time, with no item cap. */
    public static Iterable<JsonNode> paginate(PageFetcher fetchPage) {
        return paginate(fetchPage, 50, Long.MAX_VALUE);
    }

    /**
     * Walk every page lazily: a page is only fetched when the previous one is used up.
     *
     * @param pageSize items requested per page
     * @param maxItems stop after this many items
     */
    public static Iterable<JsonNode> paginate(PageFetcher fetchPage, int pageSize, long maxItems) {
        if (pageSize < 1) throw new IllegalArgumentException("pageSize must be at least 1");
        return () -> new Iterator<JsonNode>() {
            private int offset = 0;
            private long yielded = 0;
            private Iterator<JsonNode> page = Collections.emptyIterator();
            private boolean last = false;

            @Override
            public boolean hasNext() {
                if (yielded >= maxItems) return false;
                while (!page.hasNext()) {
                    if (last) return false;
                    List<JsonNode> items = itemsOf(fetchPage.fetch(offset, pageSize));
                    if (items.size() < pageSize) last = true;
                    offset += items.size();
                    page = items.iterator();
                    if (items.isEmpty()) return false;
                }
                return true;
            }

            @Override
            public JsonNode next() {
                if (!hasNext()) throw new NoSuchElementException();
                yielded++;
                return page.next();
            }
        };
    }
}
