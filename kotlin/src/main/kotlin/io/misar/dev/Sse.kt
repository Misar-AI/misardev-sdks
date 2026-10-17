package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode
import java.io.BufferedReader

/**
 * One Server-Sent Event.
 *
 * @property event The `event:` name, or null when the server sent none.
 * @property data The JSON-decoded `data:` payload, or a text node holding the raw string when it is not JSON.
 * @property id The `id:` field, or null.
 */
data class SseEvent(
    val event: String?,
    val data: JsonNode,
    val id: String?,
)

/**
 * Server-Sent Events parsing.
 *
 * Frames are separated by a blank line and may span several `data:` lines,
 * which are joined with newlines. Comment lines (`:`) are keep-alives and are
 * skipped. The terminator payload — `[DONE]` on the OpenAI-compatible chat
 * completions stream — ends the stream and is never returned. A final frame
 * with no closing blank line is still delivered.
 */
internal class SseParser(private val reader: BufferedReader, private val terminator: String?) {
    private var done = false

    /** The next event, or null at the end of the stream (EOF or terminator). */
    fun next(): SseEvent? {
        if (done) return null
        var event: String? = null
        var id: String? = null
        val data = mutableListOf<String>()
        while (true) {
            val line = reader.readLine()
            if (line == null || line.isEmpty()) {
                if (data.isNotEmpty()) {
                    if (line == null) done = true
                    val raw = data.joinToString("\n")
                    if (terminator != null && raw.trim() == terminator) {
                        done = true
                        return null
                    }
                    return SseEvent(event, Transport.parse(raw), id)
                }
                if (line == null) {
                    done = true
                    return null
                }
                event = null
                id = null
                continue
            }
            if (line.startsWith(":")) continue
            val idx = line.indexOf(':')
            val field = if (idx == -1) line else line.substring(0, idx)
            var value = if (idx == -1) "" else line.substring(idx + 1)
            if (value.startsWith(" ")) value = value.substring(1)
            when (field) {
                "data" -> data.add(value)
                "event" -> event = value
                "id" -> id = value
            }
        }
    }
}
