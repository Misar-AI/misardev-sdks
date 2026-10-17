package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * The items on one page: the page itself when it is an array, otherwise its
 * first array-valued field (`templates`, `items`, `keys`, …).
 */
fun itemsOf(page: JsonNode?): List<JsonNode> {
    if (page == null) return emptyList()
    if (page.isArray) return page.toList()
    if (page.isObject) {
        for (value in page.elements()) if (value.isArray) return value.toList()
    }
    return emptyList()
}

/**
 * Offset pagination.
 *
 * List endpoints that take `limit`/`offset` (templates, gallery, API keys…)
 * return one page at a time. This walks every page for you: it calls
 * `fetchPage(offset, limit)`, emits each item, and stops on a short page. A
 * page is only fetched when the previous one is used up.
 *
 * ```kotlin
 * paginate { offset, limit -> dev.templates.list(mapOf("offset" to offset, "limit" to limit)) }
 *     .collect { println(it["name"].asText()) }
 * ```
 */
fun paginate(
    pageSize: Int = 50,
    maxItems: Long = Long.MAX_VALUE,
    fetchPage: suspend (offset: Int, limit: Int) -> JsonNode?,
): Flow<JsonNode> = flow {
    require(pageSize >= 1) { "pageSize must be at least 1" }
    var offset = 0
    var yielded = 0L
    while (yielded < maxItems) {
        val items = itemsOf(fetchPage(offset, pageSize))
        for (item in items) {
            if (yielded >= maxItems) return@flow
            emit(item)
            yielded++
        }
        if (items.size < pageSize) return@flow
        offset += items.size
    }
}
