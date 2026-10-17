package io.misar.dev

import com.fasterxml.jackson.databind.node.TextNode
import io.misar.dev.TestServer.Reply
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransportTest {

    private lateinit var server: TestServer

    @BeforeTest
    fun start() {
        server = TestServer()
    }

    @AfterTest
    fun stop() = server.close()

    // ── authentication ───────────────────────────────────────────────────────

    @Test
    fun `sends the key as a bearer token and identifies the SDK`() = runBlocking {
        server.reply(Reply.json("""{"projects":[]}"""))
        val res = server.client().projects.list()
        val call = server.calls[0]
        assertEquals("Bearer mdk_test_key", call.header("Authorization"))
        assertEquals("misardev-kotlin/${Transport.SDK_VERSION}", call.header("X-Misar-SDK"))
        assertEquals("application/json", call.header("Accept"))
        assertEquals("application/json", call.header("Content-Type"))
        assertEquals("/projects", call.url)
        assertTrue(res!!["projects"].isArray)
    }

    @Test
    fun `defaults to the production base URL`() {
        val dev = MisarDevClient("mdk_x", null, env = { null })
        assertEquals("https://api.misar.io/dev", dev.baseUrl)
    }

    @Test
    fun `reads key and base URL from the environment`() = runBlocking {
        val env = mapOf("MISARDEV_API_KEY" to "mdk_from_env", "MISARDEV_BASE_URL" to server.base + "/")
        val dev = MisarDevClient(null, null, env = { env[it] })
        assertEquals(server.base, dev.baseUrl)
        dev.usage.plan()
        assertEquals("Bearer mdk_from_env", server.calls[0].header("Authorization"))
    }

    @Test
    fun `refuses to construct without a key`() {
        val e = assertFailsWith<MisarDevException> { MisarDevClient("", null, env = { null }) }
        assertTrue(e.message!!.contains("API key is required"))
        assertTrue(e.message!!.contains("https://www.misar.dev/settings/api-keys"))
        assertEquals("missing_api_key", e.code)
    }

    // ── errors ───────────────────────────────────────────────────────────────

    @Test
    fun `plan limit carries the full offer and is not retried`() = runBlocking {
        server.reply(Reply.json(TestServer.PLAN_LIMIT_BODY, 402).header("x-request-id", "req_1"))
        val e = assertFailsWith<PlanLimitException> { server.client().projects.list() }
        assertEquals(402, e.status)
        assertEquals("plan_limit_exceeded", e.code)
        assertEquals("API access requires the Pro plan or higher.", e.message)
        assertEquals("https://www.misar.dev/settings/billing", e.upgradeUrl)
        assertEquals("api_access", e.feature)
        assertEquals("starter", e.currentPlan)
        assertEquals("pro", e.recommendedPlan)
        assertEquals("req_1", e.requestId)
        assertEquals("API access isn't included in your Starter plan.", e.offer!!["headline"].asText())
        assertEquals("Upgrade to Pro to continue.", e.offer!!["cta"].asText())
        assertTrue(e.offer!!["plans"].isArray)
        assertTrue(e.offer!!.has("cross_sell"))
        assertEquals("pro", e.body!!["requiredPlan"].asText())
        assertEquals(1, server.calls.size)
    }

    @Test
    fun `upgrade URL falls back to pricing`() = runBlocking {
        server.reply(Reply.json(TestServer.PLAN_LIMIT_BODY.replace(""""billing":"https://www.misar.dev/settings/billing",""", ""), 402))
        val e = assertFailsWith<PlanLimitException> { server.client().projects.list() }
        assertEquals("https://www.misar.dev/pricing", e.upgradeUrl)
    }

    @Test
    fun `never retries a 429 that is a plan limit`() = runBlocking {
        server.reply(Reply.json(TestServer.QUOTA_BODY, 429).header("Retry-After", "3600"))
        val e = assertFailsWith<PlanLimitException> { server.client().templates.list() }
        assertEquals(429, e.status)
        assertEquals(3600, e.retryAfter)
        assertEquals("quota_exhausted", e.offer!!["reason"].asText())
        assertEquals(1, server.calls.size)
    }

    @Test
    fun `retries an ordinary 429 honouring Retry-After even on POST`() = runBlocking {
        server.reply(Reply.json("""{"error":"slow down"}""", 429).header("Retry-After", "0"), Reply.json("""{"ok":1}"""))
        val res = server.client().projects.create(mapOf("name" to "x"))
        assertEquals(1, res!!["ok"].asInt())
        assertEquals(2, server.calls.size)
    }

    @Test
    fun `gives up on a persistent throttle with RateLimitException`() = runBlocking {
        server.reply(Reply.json("""{"error":"slow down"}""", 429).header("Retry-After", "0"))
        val e = assertFailsWith<RateLimitException> { server.client(2).projects.list() }
        assertEquals(0, e.retryAfter)
        assertEquals("slow down", e.message)
        assertTrue(e.isRetryable)
        assertEquals(2, server.calls.size)
    }

    @Test
    fun `retries a 503 on GET`() = runBlocking {
        server.reply(Reply.json("""{"error":"down"}""", 503), Reply.json("""{"ok":true}"""))
        assertTrue(server.client().projects.list()!!["ok"].asBoolean())
        assertEquals(2, server.calls.size)
    }

    @Test
    fun `does not retry a 503 on POST`() = runBlocking {
        server.reply(Reply.json("""{"error":"down"}""", 503), Reply.json("""{"ok":true}"""))
        val e = assertFailsWith<ServerException> { server.client().projects.create() }
        assertEquals(503, e.status)
        assertEquals(1, server.calls.size)
    }

    @Test
    fun `maps statuses to typed errors`() = runBlocking {
        server.reply(
            Reply.json("""{"error":"Unauthorized"}""", 401),
            Reply.json("""{"error":"nope"}""", 404),
            Reply.json("""{"message":"not yours"}""", 403),
            Reply.json("""{"error":"busy","code":"build_running"}""", 409),
        )
        val dev = server.client(1)
        assertFailsWith<AuthenticationException> { dev.projects.list() }
        assertEquals("nope", assertFailsWith<NotFoundException> { dev.projects.get("p1") }.message)
        assertEquals("not yours", assertFailsWith<PermissionDeniedException> { dev.projects.get("p1") }.message)
        assertEquals("build_running", assertFailsWith<ConflictException> { dev.projects.deploy("p1") }.code)
    }

    @Test
    fun `reads the OpenAI error shape`() = runBlocking {
        server.reply(Reply.json("""{"error":{"message":"bad model","type":"invalid_request_error","code":"bad_model"}}""", 400))
        val e = assertFailsWith<ValidationException> { server.client().chat.completions() }
        assertEquals("bad model", e.message)
        assertEquals("bad_model", e.code)
        assertEquals(400, e.status)
    }

    @Test
    fun `falls back to the raw text body`() = runBlocking {
        server.reply(Reply.text("teapot", 418))
        val e = assertFailsWith<MisarDevException> { server.client().projects.list() }
        assertEquals(MisarDevException::class, e::class)
        assertEquals("teapot", e.message)
        assertEquals(418, e.status)
    }

    @Test
    fun `retries network failures for idempotent calls then raises NetworkException`() = runBlocking {
        val base = server.base
        server.close()
        val dev = MisarDevClient("mdk_x", base, maxRetries = 2)
        val e = assertFailsWith<NetworkException> { dev.projects.list() }
        assertEquals(0, e.status)
        assertFalse(e.isRetryable)
    }

    // ── requests ─────────────────────────────────────────────────────────────

    @Test
    fun `encodes path params and required query`() = runBlocking {
        server.client().projects.checkSubdomain("a b/c", "my-app")
        assertEquals("GET", server.calls[0].method)
        assertEquals("/projects/a%20b%2Fc/subdomain/check?value=my-app", server.calls[0].url)
    }

    @Test
    fun `drops null optional query and lowercases booleans`() = runBlocking {
        server.client().templates.list(mapOf("limit" to 5, "featured" to true, "category" to null))
        assertEquals("/templates?limit=5&featured=true", server.calls[0].url)
    }

    @Test
    fun `sends the body as JSON`() = runBlocking {
        server.client().projects.update("p1", mapOf("name" to "New"))
        val call = server.calls[0]
        assertEquals("PATCH", call.method)
        assertEquals("/projects/p1", call.url)
        assertEquals("New", call.json!!["name"].asText())
    }

    @Test
    fun `sends an empty object when the body is omitted`() = runBlocking {
        server.client().projects.create()
        assertEquals("{}", server.calls[0].body)
    }

    @Test
    fun `returns null for an empty 204`() = runBlocking {
        server.reply(Reply.empty(204))
        assertNull(server.client().projects.delete("p1"))
    }

    @Test
    fun `returns arrays and raw text`() = runBlocking {
        server.reply(Reply.json("""[{"id":1},{"id":2}]"""), Reply.text("plain"))
        val dev = server.client()
        val arr = dev.skills.list()!!
        assertTrue(arr.isArray)
        assertEquals(2, arr.size())
        assertEquals(TextNode.valueOf("plain"), dev.account.export())
    }

    @Test
    fun `exposes a raw request escape hatch`() = runBlocking {
        server.reply(Reply.json("""{"hi":1}"""))
        val res = server.client().request("GET", "/usage", mapOf("days" to 7))
        assertEquals(1, res!!["hi"].asInt())
        assertEquals("/usage?days=7", server.calls[0].url)
    }

    @Test
    fun `builds query strings and backoff delays`() {
        assertEquals("", Transport.buildQuery(null))
        assertEquals("", Transport.buildQuery(mapOf("a" to null)))
        assertEquals("a%20b%2Fc", Transport.encode("a b/c"))
        assertEquals(2000, Transport.backoffMs(0, "2"))
        assertEquals(60_000, Transport.backoffMs(0, "999"))
        assertTrue(Transport.backoffMs(3, null) >= 2000)
        assertTrue(Transport.backoffMs(30, null) <= 60_000)
        val soon = ZonedDateTime.now().plusSeconds(1).format(DateTimeFormatter.RFC_1123_DATE_TIME)
        assertTrue(Transport.backoffMs(0, soon) <= 1000)
        assertEquals(3600, Transport.retryAfterSeconds("3600"))
        assertNull(Transport.retryAfterSeconds("soon"))
    }

    // ── streaming ────────────────────────────────────────────────────────────

    @Test
    fun `streams chat completions until DONE forcing stream true`() = runBlocking {
        server.reply(
            Reply.sse(
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
                ": keep-alive\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\r\n\r\n",
                "data: [DONE]\n\n",
                "data: {\"never\":\"seen\"}\n\n",
            ),
        )
        val body = mapOf("model" to "misar-online", "messages" to listOf(mapOf("role" to "user", "content" to "hi")))
        val text = StringBuilder()
        server.client().chat.completionsStream(body).collect { text.append(it.data.at("/choices/0/delta/content").asText()) }
        assertEquals("Hello", text.toString())
        val call = server.calls[0]
        assertEquals("POST", call.method)
        assertEquals("/v1/chat/completions", call.url)
        assertTrue(call.json!!["stream"].asBoolean())
        assertEquals("misar-online", call.json!!["model"].asText())
        assertEquals("text/event-stream", call.header("Accept"))
        assertFalse(body.containsKey("stream"))
    }

    @Test
    fun `yields named events, multi-line data and a trailing frame`() = runBlocking {
        server.reply(Reply.sse("event: step\nid: 1\ndata: line1\ndata: line2\n\n", "data: {\"done\":true}"))
        val events = server.client().projects.buildStream("p1").toList()
        assertEquals(2, events.size)
        assertEquals(SseEvent("step", TextNode.valueOf("line1\nline2"), "1"), events[0])
        assertTrue(events[1].data["done"].asBoolean())
        assertNull(events[1].event)
        assertEquals("GET", server.calls[0].method)
        assertEquals("/projects/p1/build-stream", server.calls[0].url)
    }

    @Test
    fun `raises a plan-limit frame`() = runBlocking {
        val frame = TestServer.PLAN_LIMIT_BODY.replaceFirst("{", "{\"type\":\"error\",")
        server.reply(Reply.sse("data: $frame\n\n"))
        val e = assertFailsWith<PlanLimitException> { server.client().chat.studioStream(mapOf("message" to "hi")).collect {} }
        assertEquals("pro", e.recommendedPlan)
    }

    @Test
    fun `raises an HTTP error before streaming and never retries`() = runBlocking {
        server.reply(Reply.json(TestServer.PLAN_LIMIT_BODY, 402), Reply.json("""{"error":"down"}""", 503))
        assertFailsWith<PlanLimitException> { server.client().projects.buildStream("p1").collect {} }
        assertFailsWith<ServerException> { server.client().projects.buildStream("p1").collect {} }
        assertEquals(2, server.calls.size)
    }

    @Test
    fun `streams are cold`() = runBlocking {
        val flow = server.client().projects.buildStream("p1")
        assertEquals(0, server.calls.size)
        server.reply(Reply.sse("data: 1\n\n", "data: 2\n\n"))
        assertEquals(listOf(1, 2), flow.map { it.data.asInt() }.toList())
    }

    // ── pagination ───────────────────────────────────────────────────────────

    @Test
    fun `walks offset pages until a short page`() = runBlocking {
        val pages = listOf("""{"items":[1,2]}""", """{"items":[3,4]}""", """{"items":[5]}""").map(Transport::parse)
        val offsets = mutableListOf<Int>()
        val seen = paginate(pageSize = 2) { offset, _ ->
            offsets += offset
            pages[offsets.size - 1]
        }.map { it.asInt() }.toList()
        assertEquals(listOf(1, 2, 3, 4, 5), seen)
        assertEquals(listOf(0, 2, 4), offsets)
    }

    @Test
    fun `drives a real list method and respects maxItems`() = runBlocking {
        server.reply(Reply.json("""{"templates":[{"id":1},{"id":2}]}"""), Reply.json("""{"templates":[{"id":3},{"id":4}]}"""))
        val dev = server.client()
        val ids = dev.paginate(pageSize = 2, maxItems = 3) { offset, limit ->
            dev.templates.list(mapOf("offset" to offset, "limit" to limit))
        }.map { it["id"].asInt() }.toList()
        assertEquals(listOf(1, 2, 3), ids)
        assertEquals(2, server.calls.size)
        assertTrue(server.calls[1].url.contains("offset=2"))
    }

    @Test
    fun `reads top-level arrays`() {
        assertEquals(2, itemsOf(Transport.parse("[1,2]")).size)
        assertEquals(0, itemsOf(Transport.parse("""{"total":3}""")).size)
        assertIs<List<*>>(itemsOf(null))
    }
}
