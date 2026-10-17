package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode
import io.misar.dev.generated.MisarDevResources
import kotlinx.coroutines.flow.Flow
import java.net.http.HttpClient
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * The MisarDev API client.
 *
 * Every resource (`projects`, `templates`, `chat`, …) is a property generated
 * from the API's route tree, so it always matches what the server exposes.
 * Every call is a `suspend fun`; the three streams return a cold
 * `Flow<SseEvent>`. The client authenticates with your account API key
 * (`mdk_…`) and nothing else.
 *
 * ```kotlin
 * val dev = MisarDevClient()                     // reads MISARDEV_API_KEY
 * val projects = dev.projects.list()
 * ```
 *
 * Thread-safe: share one instance.
 *
 * @param apiKey The `mdk_…` key. Falls back to `MISARDEV_API_KEY` when null or empty.
 * @param baseUrl Defaults to `MISARDEV_BASE_URL`, else `https://api.misar.io/dev`.
 * @param maxRetries Total attempts for a retryable failure. Default 3.
 * @param timeout Per-attempt timeout. Default 60 seconds — builds and AI calls are slow.
 * @param httpClient Your own [HttpClient] (proxies, custom TLS, tests).
 * @param headers Extra headers sent with every request.
 */
class MisarDevClient private constructor(
    /** The underlying transport. */
    val transport: Transport,
) : MisarDevResources(transport) {

    constructor(
        apiKey: String? = null,
        baseUrl: String? = null,
        maxRetries: Int = 3,
        timeout: Duration = 60.seconds,
        httpClient: HttpClient? = null,
        headers: Map<String, String> = emptyMap(),
    ) : this(Transport(apiKey, baseUrl, maxRetries, timeout, httpClient, headers, System::getenv))

    /** Environment lookup replaceable in tests. */
    internal constructor(
        apiKey: String?,
        baseUrl: String?,
        maxRetries: Int = 3,
        env: (String) -> String?,
    ) : this(Transport(apiKey, baseUrl, maxRetries, 60.seconds, null, emptyMap(), env))

    /** The base URL every request goes to. */
    val baseUrl: String get() = transport.baseUrl

    /** Call any route directly, for anything the SDK does not wrap yet: `dev.request("GET", "/usage")`. */
    suspend fun request(
        method: String,
        path: String,
        query: Map<String, Any?>? = null,
        body: Any? = null,
    ): JsonNode? = transport.request(method, path, query, body)

    /** Open any SSE route directly. [terminator] is `"[DONE]"`, or null to read to EOF. */
    fun stream(
        method: String,
        path: String,
        query: Map<String, Any?>? = null,
        body: Any? = null,
        terminator: String? = null,
    ): Flow<SseEvent> = transport.stream(method, path, query, body, terminator)

    /** Walk every page of an offset-paginated list. See [io.misar.dev.paginate]. */
    fun paginate(
        pageSize: Int = 50,
        maxItems: Long = Long.MAX_VALUE,
        fetchPage: suspend (offset: Int, limit: Int) -> JsonNode?,
    ): Flow<JsonNode> = io.misar.dev.paginate(pageSize, maxItems, fetchPage)
}
