package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;
import io.misar.dev.TestServer.Reply;
import io.misar.dev.generated.MisarDevResources;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Every operation in sdks/manifest.json is reachable through the generated
 * client and builds the exact verb + path the server routes. Each method is
 * invoked for real, by reflection, against a recording local server — nothing
 * is declared by hand.
 */
class ResourcesTest {

    private static final JsonNode MANIFEST = load();

    private static JsonNode load() {
        try {
            return Transport.MAPPER.readTree(new File("../manifest.json"));
        } catch (IOException e) {
            throw new IllegalStateException("cannot read sdks/manifest.json", e);
        }
    }

    private static List<String> strings(JsonNode arr) {
        List<String> out = new ArrayList<>();
        if (arr != null) arr.forEach(n -> out.add(n.asText()));
        return out;
    }

    private static String camel(String s) {
        StringBuilder out = new StringBuilder();
        boolean up = false;
        for (char c : s.toCharArray()) {
            if (c == '-' || c == '_') {
                up = true;
            } else {
                out.append(up ? Character.toUpperCase(c) : c);
                up = false;
            }
        }
        return out.toString();
    }

    /** The full-signature overload: (pathParams…, requiredQuery…, body?, query?). */
    private static Method find(Object resource, String name, int arity) {
        return Arrays.stream(resource.getClass().getMethods())
                .filter(m -> m.getName().equals(name) || m.getName().equals(name + "_"))
                .filter(m -> m.getParameterCount() == arity)
                .findFirst()
                .orElseThrow(() -> new AssertionError("no " + name + "/" + arity + " on " + resource.getClass().getSimpleName()));
    }

    private static Object[] args(JsonNode m, List<String> pathParams, List<String> requiredQuery, boolean hasQuery) {
        List<Object> args = new ArrayList<>();
        for (String p : pathParams) args.add(p + "-1");
        for (String q : requiredQuery) args.add(q + "-v");
        if (m.path("hasBody").asBoolean()) args.add(Map.of("probe", true));
        if (hasQuery) args.add(Map.of());
        return args.toArray();
    }

    private static String expectedUrl(String path, List<String> pathParams, List<String> requiredQuery) {
        String p = path;
        for (String name : pathParams) p = p.replace(":" + name, name + "-1");
        List<String> qs = new ArrayList<>();
        for (String q : requiredQuery) qs.add(q + "=" + q + "-v");
        return p + (qs.isEmpty() ? "" : "?" + String.join("&", qs));
    }

    @Test
    void coverEveryManifestOperation() {
        int methods = 0;
        for (JsonNode r : (Iterable<JsonNode>) MANIFEST.get("resources")::elements) methods += r.get("methods").size();
        assertEquals(methods + MANIFEST.at("/streams/sse").size(), MisarDevResources.OPERATION_COUNT);
        assertEquals(109, MisarDevResources.OPERATION_COUNT);
    }

    @TestFactory
    Stream<DynamicTest> everyMethod() {
        List<DynamicTest> tests = new ArrayList<>();
        MANIFEST.get("resources").fields().forEachRemaining(entry -> {
            for (JsonNode m : entry.getValue().get("methods")) {
                String label = entry.getKey() + "." + m.get("name").asText();
                tests.add(DynamicTest.dynamicTest(label, () -> checkMethod(entry.getKey(), m)));
            }
        });
        return tests.stream();
    }

    @TestFactory
    Stream<DynamicTest> everyStream() {
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode s : MANIFEST.at("/streams/sse")) {
            String label = "stream " + s.get("resource").asText() + "." + s.get("name").asText();
            tests.add(DynamicTest.dynamicTest(label, () -> checkStream(s)));
        }
        return tests.stream();
    }

    // A fresh server per operation: @BeforeEach does not run per dynamic test.

    private static void checkMethod(String resource, JsonNode m) throws Exception {
        try (TestServer server = new TestServer()) {
            Object res = MisarDevClient.class.getField(camel(resource)).get(server.client(1));
            List<String> pathParams = strings(m.get("pathParams"));
            List<String> required = strings(m.get("requiredQuery"));
            boolean hasQuery = strings(m.get("queryParams")).stream().anyMatch(q -> !required.contains(q));
            Object[] a = args(m, pathParams, required, hasQuery);
            find(res, m.get("name").asText(), a.length).invoke(res, a);

            TestServer.Call call = server.calls.get(0);
            assertEquals(m.get("verb").asText(), call.method);
            assertEquals(expectedUrl(m.get("path").asText(), pathParams, required), call.url());
            if (m.path("hasBody").asBoolean()) assertTrue(call.json().get("probe").asBoolean());
            else assertEquals("", call.body);
        }
    }

    private static void checkStream(JsonNode s) throws Exception {
        try (TestServer server = new TestServer()) {
            server.reply(Reply.sse("data: {\"x\":1}\n\n"));
            Object res = MisarDevClient.class.getField(camel(s.get("resource").asText())).get(server.client(1));
            List<String> pathParams = strings(s.get("pathParams"));
            Object[] a = args(s, pathParams, List.of(), false);
            List<SseEvent> events;
            try (SseStream stream = (SseStream) find(res, s.get("name").asText(), a.length).invoke(res, a)) {
                events = stream.toList();
            }
            assertEquals(1, events.size());
            assertEquals(1, events.get(0).data().get("x").asInt());
            TestServer.Call call = server.calls.get(0);
            assertEquals(s.get("verb").asText(), call.method);
            assertEquals(expectedUrl(s.get("path").asText(), pathParams, List.of()), call.url());
            if ("[DONE]".equals(s.path("terminator").asText(null))) {
                assertNotNull(call.json());
                assertTrue(call.json().get("stream").asBoolean());
            }
        }
    }
}
