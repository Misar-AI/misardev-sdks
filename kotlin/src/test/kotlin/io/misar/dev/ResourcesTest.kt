package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode
import io.misar.dev.TestServer.Reply
import io.misar.dev.generated.MisarDevResources
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.reflect.KFunction
import kotlin.reflect.full.callSuspendBy
import kotlin.reflect.full.memberFunctions
import kotlin.reflect.full.memberProperties
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Every operation in sdks/manifest.json is reachable through the generated
 * client and builds the exact verb + path the server routes. Each method is
 * invoked for real, by reflection, against a recording local server — nothing
 * is declared by hand.
 */
class ResourcesTest {

    private val manifest: JsonNode = Transport.MAPPER.readTree(File("../manifest.json"))

    private fun JsonNode?.strings(): List<String> = this?.map { it.asText() } ?: emptyList()

    private fun camel(s: String) = s.replace(Regex("[-_](\\w)")) { it.groupValues[1].uppercase() }

    private fun resourceOf(dev: MisarDevClient, name: String): Any =
        MisarDevResources::class.memberProperties.first { it.name == camel(name) }.get(dev)!!

    private fun functionOf(resource: Any, name: String): KFunction<*> =
        resource::class.memberFunctions.firstOrNull { it.name == name } ?: fail("no $name on ${resource::class.simpleName}")

    /** Positional path params and required query, plus a probe body; optional query left at its default. */
    private suspend fun invoke(resource: Any, fn: KFunction<*>, m: JsonNode, requiredQuery: List<String>): Any? {
        val args = mutableMapOf(fn.parameters[0] to resource)
        val values = m["pathParams"].strings().map { "$it-1" } + requiredQuery.map { "$it-v" }
        val positional = fn.parameters.drop(1).filter { it.name != "body" && it.name != "query" }
        assertEquals(values.size, positional.size, "positional arity of ${fn.name}")
        positional.zip(values).forEach { (p, v) -> args[p] = v }
        if (m.path("hasBody").asBoolean()) args[fn.parameters.first { it.name == "body" }] = mapOf("probe" to true)
        return if (fn.isSuspend) fn.callSuspendBy(args) else fn.callBy(args)
    }

    private fun expectedUrl(m: JsonNode, requiredQuery: List<String>): String {
        var p = m["path"].asText()
        for (name in m["pathParams"].strings()) p = p.replace(":$name", "$name-1")
        val qs = requiredQuery.joinToString("&") { "$it=$it-v" }
        return p + if (qs.isEmpty()) "" else "?$qs"
    }

    @Test
    fun `covers every manifest operation`() {
        val methods = manifest["resources"].sumOf { it["methods"].size() }
        assertEquals(methods + manifest.at("/streams/sse").size(), MisarDevResources.OPERATION_COUNT)
        assertEquals(109, MisarDevResources.OPERATION_COUNT)
    }

    @Test
    fun `every method builds the manifest verb and URL`() = runBlocking {
        var checked = 0
        for ((resource, def) in manifest["resources"].fields()) {
            for (m in def["methods"]) {
                TestServer().use { server ->
                    val res = resourceOf(server.client(1), resource)
                    val fn = functionOf(res, m["name"].asText())
                    assertTrue(fn.isSuspend, "${fn.name} is a suspend fun")
                    val required = m["requiredQuery"].strings()
                    invoke(res, fn, m, required)
                    val call = server.calls[0]
                    val label = "$resource.${m["name"].asText()}"
                    assertEquals(m["verb"].asText(), call.method, label)
                    assertEquals(expectedUrl(m, required), call.url, label)
                    if (m.path("hasBody").asBoolean()) assertTrue(call.json!!["probe"].asBoolean(), label)
                    else assertEquals("", call.body, label)
                    checked++
                }
            }
        }
        assertEquals(manifest["resources"].sumOf { it["methods"].size() }, checked)
    }

    @Test
    fun `every stream builds the manifest verb and URL`() = runBlocking {
        for (s in manifest.at("/streams/sse")) {
            TestServer().use { server ->
                server.reply(Reply.sse("data: {\"x\":1}\n\n"))
                val res = resourceOf(server.client(1), s["resource"].asText())
                val fn = functionOf(res, s["name"].asText())
                @Suppress("UNCHECKED_CAST")
                val events = (invoke(res, fn, s, emptyList()) as Flow<SseEvent>).toList()
                val label = "${s["resource"].asText()}.${s["name"].asText()}"
                assertEquals(1, events.size, label)
                assertEquals(1, events[0].data["x"].asInt(), label)
                val call = server.calls[0]
                assertEquals(s["verb"].asText(), call.method, label)
                assertEquals(expectedUrl(s, emptyList()), call.url, label)
                if (s.path("terminator").asText(null) == "[DONE]") assertTrue(call.json!!["stream"].asBoolean(), label)
            }
        }
    }
}
