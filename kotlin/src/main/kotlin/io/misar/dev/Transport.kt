package io.misar.dev

import com.fasterxml.jackson.core.JsonProcessingException
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.TextNode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.future.await
import kotlinx.coroutines.withContext
import java.io.IOException
import java.io.InputStream
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpHeaders
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random
import kotlin.time.Duration

/**
 * HTTP transport shared by the generated resource layer.
 *
 * Everything the SDK does goes through here, and it authenticates exactly one
 * way: the account API key (`mdk_…`), sent as `Authorization: Bearer <key>`.
 * There is no second credential path. What a key may do — and how much of it —
 * is decided server-side from the subscription behind that key; the SDK carries
 * the key and surfaces the answer rather than deciding locally what a plan
 * allows.
 */
class Transport internal constructor(
    apiKey: String?,
    baseUrl: String?,
    maxRetries: Int,
    /** Per-attempt timeout. */
    val timeout: Duration,
    httpClient: HttpClient?,
    headers: Map<String, String>,
    env: (String) -> String?,
) {
    private val apiKey: String
    /** The base URL every request goes to, without a trailing slash. */
    val baseUrl: String
    /** Total attempts for a retryable failure. */
    val maxRetries: Int = max(1, maxRetries)
    private val http: HttpClient =
        httpClient ?: HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(10)).build()
    private val extraHeaders: Map<String, String> = headers.toMap()

    init {
        val key = apiKey?.takeIf { it.isNotBlank() } ?: env("MISARDEV_API_KEY")?.takeIf { it.isNotBlank() }
            ?: throw MisarDevException(
                0,
                "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. " +
                    "Create one at $API_KEYS_URL.",
                "missing_api_key",
            )
        this.apiKey = key.trim()
        this.baseUrl = (
            baseUrl?.takeIf { it.isNotBlank() }
                ?: env("MISARDEV_BASE_URL")?.takeIf { it.isNotBlank() }
                ?: DEFAULT_BASE_URL
            ).trimEnd('/')
    }

    /**
     * Send one request, retrying throttles and (for idempotent verbs) transient failures.
     *
     * @return the decoded JSON, a text node for a non-JSON body, or null for 204 / empty.
     */
    suspend fun request(method: String, path: String, query: Map<String, Any?>? = null, body: Any? = null): JsonNode? {
        val verb = method.uppercase()
        val uri = URI.create(baseUrl + path + buildQuery(query))
        val payload = serialize(body)

        var attempt = 0
        while (true) {
            val last = attempt >= maxRetries - 1
            val req = build(verb, uri, payload, "application/json")

            val res: HttpResponse<String> = try {
                http.sendAsync(req, HttpResponse.BodyHandlers.ofString(Charsets.UTF_8)).await()
            } catch (e: IOException) {
                if (!last && verb in IDEMPOTENT) {
                    delay(backoffMs(attempt, null))
                    attempt++
                    continue
                }
                throw NetworkException(e.message ?: e.javaClass.simpleName, e)
            }

            val status = res.statusCode()
            if (status in 200..299) return decode(status, res.body())

            // Read the body BEFORE deciding to retry: a 429 from the rate limiter
            // and a 429 from a spent plan allowance share a status, and only the
            // first is worth retrying.
            val error = errorFor(status, res.headers(), decode(status, res.body()))
            if (error is PlanLimitException) throw error

            val retryable = status in RETRYABLE && (status == 429 || verb in IDEMPOTENT)
            if (retryable && !last) {
                delay(backoffMs(attempt, res.headers().firstValue("retry-after").orElse(null)))
                attempt++
                continue
            }
            throw error
        }
    }

    /**
     * Open a Server-Sent Events stream. Cold: the request is sent when the flow is collected.
     *
     * Never retried: a stream that fails mid-flight cannot be replayed without
     * duplicating what the caller already consumed. A non-2xx answer raises the
     * same typed error as [request]; a frame whose data is a plan-limit refusal
     * raises [PlanLimitException].
     *
     * @param terminator data payload that ends the stream (`"[DONE]"`), or null to read to EOF.
     */
    fun stream(
        method: String,
        path: String,
        query: Map<String, Any?>? = null,
        body: Any? = null,
        terminator: String? = null,
    ): Flow<SseEvent> = flow {
        val verb = method.uppercase()
        val uri = URI.create(baseUrl + path + buildQuery(query))
        val req = build(verb, uri, serialize(body), "text/event-stream")

        val res: HttpResponse<InputStream> = try {
            http.sendAsync(req, HttpResponse.BodyHandlers.ofInputStream()).await()
        } catch (e: IOException) {
            throw NetworkException(e.message ?: e.javaClass.simpleName, e)
        }

        val status = res.statusCode()
        if (status !in 200..299) {
            val text = withContext(Dispatchers.IO) {
                runCatching { res.body().use { String(it.readAllBytes(), Charsets.UTF_8) } }.getOrDefault("")
            }
            throw errorFor(status, res.headers(), decode(status, text))
        }

        res.body().bufferedReader(Charsets.UTF_8).use { reader ->
            val parser = SseParser(reader, terminator)
            while (true) {
                val event = try {
                    parser.next()
                } catch (e: IOException) {
                    throw NetworkException("Stream interrupted: ${e.message}", e)
                } ?: break
                // Other error frames are the stream's own business (the build
                // stream reports a failed step and carries on), so only the plan
                // refusal — which no amount of reading further will fix — is raised.
                if (isPlanLimitBody(event.data)) throw errorFor(402, res.headers(), event.data)
                emit(event)
            }
        }
    }.flowOn(Dispatchers.IO)

    private fun build(verb: String, uri: URI, payload: String?, accept: String): HttpRequest {
        val rb = HttpRequest.newBuilder(uri)
            .timeout(java.time.Duration.ofMillis(timeout.inWholeMilliseconds))
            .header("Authorization", "Bearer $apiKey")
            .header("Accept", accept)
            .header("Content-Type", "application/json")
            .header("X-Misar-SDK", "misardev-kotlin/$SDK_VERSION")
        extraHeaders.forEach { (k, v) -> rb.setHeader(k, v) }
        val publisher = if (payload != null) {
            HttpRequest.BodyPublishers.ofString(payload, Charsets.UTF_8)
        } else {
            HttpRequest.BodyPublishers.noBody()
        }
        return rb.method(verb, publisher).build()
    }

    companion object {
        /** Default API base URL. Override with `baseUrl` or `MISARDEV_BASE_URL`. */
        const val DEFAULT_BASE_URL = "https://api.misar.io/dev"

        /** This SDK's version, sent in `X-Misar-SDK`. */
        const val SDK_VERSION = "1.0.0"

        /** Where users create API keys; quoted in the missing-key error. */
        const val API_KEYS_URL = "https://www.misar.dev/settings/api-keys"

        internal val MAPPER: ObjectMapper = ObjectMapper().enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)

        /** Statuses worth retrying. 429 only when it is NOT a plan limit. */
        private val RETRYABLE = setOf(429, 500, 502, 503, 504)

        /**
         * A 5xx or a dropped connection on a POST may already have done its
         * work — started a build, charged an allowance. Only requests that are
         * safe to repeat are retried on those; a 429 is always safe because the
         * server refused it before doing anything.
         */
        private val IDEMPOTENT = setOf("GET", "HEAD", "OPTIONS", "PUT", "DELETE")
        internal const val MAX_BACKOFF_MS = 60_000L
        private const val PLAN_LIMIT_CODE = "plan_limit_exceeded"
        private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

        /**
         * Percent-encode one path segment or query component (RFC 3986): all
         * but `A-Z a-z 0-9 - . _ ~` is encoded, so `"a b/c"` becomes `"a%20b%2Fc"`.
         */
        fun encode(value: Any?): String {
            val sb = StringBuilder()
            for (b in value.toString().toByteArray(Charsets.UTF_8)) {
                val c = b.toInt() and 0xFF
                if (c < 128 && UNRESERVED.indexOf(c.toChar()) >= 0) sb.append(c.toChar())
                else sb.append('%').append("%02X".format(c))
            }
            return sb.toString()
        }

        /** `?a=1&b=true`, dropping null values; empty when nothing is left. */
        fun buildQuery(query: Map<String, Any?>?): String {
            val parts = query.orEmpty().mapNotNull { (k, v) ->
                when (v) {
                    null -> null
                    is JsonNode -> "${encode(k)}=${encode(v.asText())}"
                    else -> "${encode(k)}=${encode(v)}"
                }
            }
            return if (parts.isEmpty()) "" else "?" + parts.joinToString("&")
        }

        /** Merge a caller's optional query map with positional required parameters; required values win. */
        fun query(optional: Map<String, Any?>?, vararg required: Pair<String, Any?>): Map<String, Any?> =
            LinkedHashMap<String, Any?>().apply {
                optional?.let { putAll(it) }
                required.forEach { (k, v) -> put(k, v) }
            }

        /** A copy of [body] with `"stream": true` set, for the OpenAI-compatible stream. */
        fun withStream(body: Map<String, Any?>?): Map<String, Any?> =
            LinkedHashMap<String, Any?>().apply {
                body?.let { putAll(it) }
                put("stream", true)
            }

        internal fun serialize(body: Any?): String? {
            if (body == null) return null
            return try {
                MAPPER.writeValueAsString(body)
            } catch (e: JsonProcessingException) {
                throw MisarDevException(0, "Could not serialise the request body: ${e.originalMessage}", "invalid_body", cause = e)
            }
        }

        internal fun decode(status: Int, text: String?): JsonNode? =
            if (status == 204 || text.isNullOrEmpty()) null else parse(text)

        /** JSON when it parses, else a text node holding the raw string. */
        internal fun parse(text: String): JsonNode {
            if (text.isBlank()) return TextNode.valueOf(text)
            return try {
                val node: JsonNode? = MAPPER.readTree(text)
                if (node == null || node.isMissingNode) TextNode.valueOf(text) else node
            } catch (e: JsonProcessingException) {
                TextNode.valueOf(text)
            }
        }

        /** True when a body is the `@misar/upsell` plan-limit refusal. */
        internal fun isPlanLimitBody(body: JsonNode?): Boolean =
            body != null && body.isObject && body.path("code").asText(null) == PLAN_LIMIT_CODE

        /** Pull a human message out of the API's several error shapes. */
        internal fun messageOf(body: JsonNode?, fallback: String): String {
            if (body != null && body.isObject) {
                val err = body.get("error")
                if (err != null && err.isTextual) return err.asText()
                // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
                if (err != null && err.isObject && err.path("message").isTextual) return err.get("message").asText()
                val msg = body.get("message")
                if (msg != null && msg.isTextual) return msg.asText()
            }
            if (body != null && body.isTextual && body.asText().isNotBlank()) return body.asText().trim().take(500)
            return fallback
        }

        internal fun codeOf(body: JsonNode?): String? {
            if (body == null || !body.isObject) return null
            body.get("code")?.takeIf { it.isTextual }?.let { return it.asText() }
            val err = body.get("error")
            if (err != null && err.isObject && err.path("code").isTextual) return err.get("code").asText()
            return null
        }

        /** Map an error response to the right typed error. Plan limits first, by `code`. */
        internal fun errorFor(status: Int, headers: HttpHeaders?, body: JsonNode?): MisarDevException {
            val requestId = headers?.firstValue("x-request-id")?.orElse(null)
            val retryAfter = retryAfterSeconds(headers?.firstValue("retry-after")?.orElse(null))
            val message = messageOf(body, "HTTP $status")
            val code = codeOf(body)

            if (isPlanLimitBody(body)) {
                val offer = body!!.get("upgrade")?.takeUnless { it.isNull }
                return PlanLimitException(status, message, body, requestId, offer, retryAfter)
            }
            return when {
                status == 400 || status == 422 -> ValidationException(status, message, code, body, requestId)
                status == 401 -> AuthenticationException(status, message, code, body, requestId)
                status == 403 -> PermissionDeniedException(status, message, code, body, requestId)
                status == 404 -> NotFoundException(status, message, code, body, requestId)
                status == 409 -> ConflictException(status, message, code, body, requestId)
                status == 429 -> RateLimitException(status, message, code, body, requestId, retryAfter)
                status >= 500 -> ServerException(status, message, code, body, requestId)
                else -> MisarDevException(status, message, code, body, requestId)
            }
        }

        /** `Retry-After` as whole seconds (numeric or HTTP-date), or null. */
        internal fun retryAfterSeconds(value: String?): Int? {
            val v = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            v.toDoubleOrNull()?.let { return if (it >= 0 && it.isFinite()) ceil(it).toInt() else null }
            val at = httpDateMillis(v) ?: return null
            return max(0.0, ceil((at - System.currentTimeMillis()) / 1000.0)).toInt()
        }

        /** Exponential backoff with jitter, but honour `Retry-After` when sent. Capped at 60s. */
        internal fun backoffMs(attempt: Int, retryAfter: String?): Long {
            val v = retryAfter?.trim()?.takeIf { it.isNotEmpty() }
            if (v != null) {
                val seconds = v.toDoubleOrNull()
                if (seconds != null) {
                    if (seconds >= 0 && seconds.isFinite()) return min((seconds * 1000).toLong(), MAX_BACKOFF_MS)
                } else {
                    httpDateMillis(v)?.let { return min(max(0L, it - System.currentTimeMillis()), MAX_BACKOFF_MS) }
                }
            }
            val base = 250.0 * 2.0.pow(attempt)
            return min(base + Random.nextDouble() * base * 0.25, MAX_BACKOFF_MS.toDouble()).toLong()
        }

        private fun httpDateMillis(v: String): Long? =
            runCatching { ZonedDateTime.parse(v, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
    }
}
