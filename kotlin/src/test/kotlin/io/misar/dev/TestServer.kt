package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.ArrayDeque
import java.util.Collections

/**
 * A real local HTTP server that records every request and answers from a queue.
 *
 * The JDK's own [HttpServer] rather than a mocking library: the client is built
 * on java.net.http, so a real socket tests the transport that actually ships —
 * and the SSE tests need a server that flushes a body in pieces, which is where
 * frame-boundary bugs live. Nothing leaves 127.0.0.1.
 */
class TestServer : AutoCloseable {

    data class Call(
        val method: String,
        val path: String,
        val query: String?,
        val headers: Map<String, String>,
        val body: String,
    ) {
        val url: String get() = path + (query?.let { "?$it" } ?: "")
        fun header(name: String): String? = headers[name.lowercase()]
        val json: JsonNode? get() = if (body.isEmpty()) null else Transport.parse(body)
    }

    class Reply private constructor(
        val status: Int,
        val body: String?,
        val ssePieces: List<String>?,
    ) {
        val headers = linkedMapOf<String, String>()
        fun header(name: String, value: String) = apply { headers[name] = value }

        companion object {
            fun json(body: String, status: Int = 200) = Reply(status, body, null).header("Content-Type", "application/json")
            fun text(body: String, status: Int = 200) = Reply(status, body, null).header("Content-Type", "text/plain")
            fun empty(status: Int) = Reply(status, null, null)
            fun sse(vararg pieces: String) = Reply(200, null, pieces.toList()).header("Content-Type", "text/event-stream")
        }
    }

    val calls: MutableList<Call> = Collections.synchronizedList(mutableListOf())
    private val queue = ArrayDeque<Reply>()
    private val server: HttpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)

    init {
        server.createContext("/") { handle(it) }
        server.start()
    }

    /** Queue replies; the last one keeps answering once the others are used. */
    fun reply(vararg replies: Reply) = apply { synchronized(queue) { queue.addAll(replies) } }

    val base: String get() = "http://127.0.0.1:${server.address.port}/dev"

    fun client(maxRetries: Int = 3) = MisarDevClient("mdk_test_key", base, maxRetries)

    private fun handle(ex: HttpExchange) {
        val headers = ex.requestHeaders.entries.associate { (k, v) -> k.lowercase() to v.joinToString(",") }
        val body = String(ex.requestBody.readAllBytes(), Charsets.UTF_8)
        val path = ex.requestURI.rawPath.removePrefix("/dev")
        calls.add(Call(ex.requestMethod, path, ex.requestURI.rawQuery, headers, body))

        val r = synchronized(queue) { if (queue.size > 1) queue.poll() else queue.peek() } ?: Reply.json("""{"ok":true}""")
        r.headers.forEach { (k, v) -> ex.responseHeaders.add(k, v) }
        when {
            r.ssePieces != null -> {
                ex.sendResponseHeaders(r.status, 0)
                ex.responseBody.use { out ->
                    r.ssePieces.forEach { piece ->
                        out.write(piece.toByteArray())
                        out.flush()
                    }
                }
            }
            r.body == null -> {
                ex.sendResponseHeaders(r.status, -1)
                ex.close()
            }
            else -> {
                val bytes = r.body.toByteArray()
                ex.sendResponseHeaders(r.status, bytes.size.toLong())
                ex.responseBody.use { it.write(bytes) }
            }
        }
    }

    override fun close() = server.stop(0)

    companion object {
        const val PLAN_LIMIT_BODY =
            """{"error":"API access requires the Pro plan or higher.","code":"plan_limit_exceeded","requiredPlan":"pro",""" +
                """"upgrade":{"product":"dev","product_name":"Misar.Dev","reason":"feature_locked","feature":"api_access",""" +
                """"feature_label":"API access","headline":"API access isn't included in your Starter plan.","usage":null,""" +
                """"current_plan":{"slug":"starter","name":"Starter"},"recommended_plan":"pro","plans":[],"topup":null,""" +
                """"overage":null,"trial":null,"cross_sell":[],""" +
                """"urls":{"pricing":"https://www.misar.dev/pricing","billing":"https://www.misar.dev/settings/billing",""" +
                """"docs":"https://docs.misar.io/dev/api","compare":"https://www.misar.dev/pricing#compare"},""" +
                """"cta":"Upgrade to Pro to continue."}}"""

        val QUOTA_BODY = PLAN_LIMIT_BODY.replace("\"feature_locked\"", "\"quota_exhausted\"")
    }
}
