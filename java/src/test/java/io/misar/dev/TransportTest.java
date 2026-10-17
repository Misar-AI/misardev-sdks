package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.TextNode;
import io.misar.dev.TestServer.Reply;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TransportTest {

    private TestServer server;

    @BeforeEach
    void start() throws IOException {
        server = new TestServer();
    }

    @AfterEach
    void stop() {
        server.close();
    }

    @Nested
    class Authentication {
        @Test
        void sendsBearerKeyAndIdentifiesTheSdk() {
            server.reply(Reply.json("{\"projects\":[]}"));
            JsonNode res = server.client().projects.list();
            TestServer.Call call = server.calls.get(0);
            assertEquals("Bearer mdk_test_key", call.header("Authorization"));
            assertEquals("misardev-java/" + Transport.SDK_VERSION, call.header("X-Misar-SDK"));
            assertEquals("application/json", call.header("Accept"));
            assertEquals("application/json", call.header("Content-Type"));
            assertEquals("/projects", call.url());
            assertTrue(res.get("projects").isArray());
        }

        @Test
        void defaultsToTheProductionBaseUrl() {
            MisarDevClient dev = MisarDevClient.builder().apiKey("mdk_x").env(n -> null).build();
            assertEquals("https://api.misar.io/dev", dev.baseUrl());
        }

        @Test
        void readsKeyAndBaseUrlFromTheEnvironment() {
            Map<String, String> env = new HashMap<>();
            env.put("MISARDEV_API_KEY", "mdk_from_env");
            env.put("MISARDEV_BASE_URL", server.base() + "/");
            MisarDevClient dev = MisarDevClient.builder().env(env::get).build();
            assertEquals(server.base(), dev.baseUrl());
            dev.usage.plan();
            assertEquals("Bearer mdk_from_env", server.calls.get(0).header("Authorization"));
        }

        @Test
        void refusesToConstructWithoutAKey() {
            MisarDevException e = assertThrows(MisarDevException.class,
                    () -> MisarDevClient.builder().apiKey("").env(n -> null).build());
            assertTrue(e.getMessage().contains("API key is required"));
            assertTrue(e.getMessage().contains("https://www.misar.dev/settings/api-keys"));
            assertEquals("missing_api_key", e.getCode());
        }
    }

    @Nested
    class Errors {
        @Test
        void planLimitCarriesTheFullOfferAndIsNotRetried() {
            server.reply(Reply.json(402, TestServer.PLAN_LIMIT_BODY).header("x-request-id", "req_1"));
            PlanLimitException e = assertThrows(PlanLimitException.class, () -> server.client().projects.list());
            assertEquals(402, e.getStatus());
            assertEquals("plan_limit_exceeded", e.getCode());
            assertEquals("API access requires the Pro plan or higher.", e.getMessage());
            assertEquals("https://www.misar.dev/settings/billing", e.getUpgradeUrl());
            assertEquals("api_access", e.getFeature());
            assertEquals("starter", e.getCurrentPlan());
            assertEquals("pro", e.getRecommendedPlan());
            assertEquals("req_1", e.getRequestId());
            assertEquals("API access isn't included in your Starter plan.", e.getOffer().get("headline").asText());
            assertEquals("Upgrade to Pro to continue.", e.getOffer().get("cta").asText());
            assertTrue(e.getOffer().get("plans").isArray());
            assertTrue(e.getOffer().has("cross_sell"));
            assertEquals("pro", e.getBody().get("requiredPlan").asText());
            assertEquals(1, server.calls.size());
        }

        @Test
        void upgradeUrlFallsBackToPricing() {
            server.reply(Reply.json(402, TestServer.PLAN_LIMIT_BODY.replace("\"billing\":\"https://www.misar.dev/settings/billing\",", "")));
            PlanLimitException e = assertThrows(PlanLimitException.class, () -> server.client().projects.list());
            assertEquals("https://www.misar.dev/pricing", e.getUpgradeUrl());
        }

        @Test
        void neverRetriesA429ThatIsAPlanLimit() {
            server.reply(Reply.json(429, TestServer.QUOTA_BODY).header("Retry-After", "3600"));
            PlanLimitException e = assertThrows(PlanLimitException.class, () -> server.client().templates.list());
            assertEquals(429, e.getStatus());
            assertEquals(3600, e.getRetryAfter());
            assertEquals("quota_exhausted", e.getOffer().get("reason").asText());
            assertEquals(1, server.calls.size());
        }

        @Test
        void retriesAnOrdinary429HonouringRetryAfterEvenOnPost() {
            server.reply(Reply.json(429, "{\"error\":\"slow down\"}").header("Retry-After", "0"), Reply.json("{\"ok\":1}"));
            JsonNode res = server.client().projects.create(Map.of("name", "x"));
            assertEquals(1, res.get("ok").asInt());
            assertEquals(2, server.calls.size());
        }

        @Test
        void givesUpOnAPersistentThrottleWithRateLimitException() {
            server.reply(Reply.json(429, "{\"error\":\"slow down\"}").header("Retry-After", "0"));
            RateLimitException e = assertThrows(RateLimitException.class, () -> server.client(2).projects.list());
            assertEquals(0, e.getRetryAfter());
            assertEquals("slow down", e.getMessage());
            assertTrue(e.isRetryable());
            assertEquals(2, server.calls.size());
        }

        @Test
        void retriesA503OnGet() {
            server.reply(Reply.json(503, "{\"error\":\"down\"}"), Reply.json("{\"ok\":true}"));
            assertTrue(server.client().projects.list().get("ok").asBoolean());
            assertEquals(2, server.calls.size());
        }

        @Test
        void doesNotRetryA503OnPost() {
            server.reply(Reply.json(503, "{\"error\":\"down\"}"), Reply.json("{\"ok\":true}"));
            ServerException e = assertThrows(ServerException.class, () -> server.client().projects.create(Map.of()));
            assertEquals(503, e.getStatus());
            assertEquals(1, server.calls.size());
        }

        @Test
        void mapsStatusesToTypedErrors() {
            server.reply(Reply.json(401, "{\"error\":\"Unauthorized\"}"));
            assertThrows(AuthenticationException.class, () -> server.client().projects.list());
        }

        @Test
        void mapsNotFound() {
            server.reply(Reply.json(404, "{\"error\":\"nope\"}").header("x-request-id", "req_404"));
            NotFoundException e = assertThrows(NotFoundException.class, () -> server.client().projects.get("p1"));
            assertEquals("nope", e.getMessage());
            assertEquals("req_404", e.getRequestId());
        }

        @Test
        void mapsForbiddenAndConflict() {
            server.reply(Reply.json(403, "{\"message\":\"not yours\"}"), Reply.json(409, "{\"error\":\"busy\",\"code\":\"build_running\"}"));
            PermissionDeniedException a = assertThrows(PermissionDeniedException.class, () -> server.client(1).projects.get("p1"));
            assertEquals("not yours", a.getMessage());
            ConflictException b = assertThrows(ConflictException.class, () -> server.client(1).projects.deploy("p1"));
            assertEquals("build_running", b.getCode());
        }

        @Test
        void readsTheOpenAiErrorShape() {
            server.reply(Reply.json(400, "{\"error\":{\"message\":\"bad model\",\"type\":\"invalid_request_error\",\"code\":\"bad_model\"}}"));
            ValidationException e = assertThrows(ValidationException.class, () -> server.client().chat.completions(Map.of()));
            assertEquals("bad model", e.getMessage());
            assertEquals("bad_model", e.getCode());
            assertEquals(400, e.getStatus());
        }

        @Test
        void fallsBackToTheRawTextBody() {
            server.reply(Reply.text(418, "teapot"));
            MisarDevException e = assertThrows(MisarDevException.class, () -> server.client().projects.list());
            assertEquals(MisarDevException.class, e.getClass());
            assertEquals("teapot", e.getMessage());
            assertEquals(418, e.getStatus());
        }

        @Test
        void retriesNetworkFailuresForIdempotentCallsThenRaisesNetworkException() {
            String base = server.base();
            server.close();
            MisarDevClient dev = MisarDevClient.builder().apiKey("mdk_x").baseUrl(base).maxRetries(2).build();
            NetworkException e = assertThrows(NetworkException.class, dev.projects::list);
            assertEquals(0, e.getStatus());
            assertFalse(e.isRetryable());
        }
    }

    @Nested
    class Requests {
        @Test
        void encodesPathParamsAndRequiredQuery() {
            server.client().projects.checkSubdomain("a b/c", "my-app");
            assertEquals("GET", server.calls.get(0).method);
            assertEquals("/projects/a%20b%2Fc/subdomain/check?value=my-app", server.calls.get(0).url());
        }

        @Test
        void dropsNullOptionalQueryAndLowercasesBooleans() {
            Map<String, Object> q = new LinkedHashMap<>();
            q.put("limit", 5);
            q.put("featured", true);
            q.put("category", null);
            server.client().templates.list(q);
            assertEquals("/templates?limit=5&featured=true", server.calls.get(0).url());
        }

        @Test
        void sendsTheBodyAsJson() {
            server.client().projects.update("p1", Map.of("name", "New"));
            TestServer.Call call = server.calls.get(0);
            assertEquals("PATCH", call.method);
            assertEquals("/projects/p1", call.url());
            assertEquals("New", call.json().get("name").asText());
        }

        @Test
        void sendsAnEmptyObjectWhenTheBodyIsOmitted() {
            server.client().projects.create();
            assertEquals("{}", server.calls.get(0).body);
        }

        @Test
        void returnsNullForAnEmpty204() {
            server.reply(Reply.empty(204));
            assertNull(server.client().projects.delete("p1"));
        }

        @Test
        void returnsArraysAndRawText() {
            server.reply(Reply.json("[{\"id\":1},{\"id\":2}]"), Reply.text(200, "plain"));
            MisarDevClient dev = server.client();
            JsonNode arr = dev.skills.list();
            assertTrue(arr.isArray());
            assertEquals(2, arr.size());
            assertEquals(TextNode.valueOf("plain"), dev.account.export());
        }

        @Test
        void exposesARawRequestEscapeHatch() {
            server.reply(Reply.json("{\"hi\":1}"));
            JsonNode res = server.client().request("GET", "/usage", Map.of("days", 7), null);
            assertEquals(1, res.get("hi").asInt());
            assertEquals("/usage?days=7", server.calls.get(0).url());
        }

        @Test
        void buildsQueryStringsAndBackoffDelays() {
            assertEquals("", Transport.buildQuery(null));
            Map<String, Object> nulls = new HashMap<>();
            nulls.put("a", null);
            assertEquals("", Transport.buildQuery(nulls));
            assertEquals("a%20b%2Fc", Transport.encode("a b/c"));
            assertEquals(2000, Transport.backoffMs(0, "2"));
            assertEquals(60_000, Transport.backoffMs(0, "999"));
            assertTrue(Transport.backoffMs(3, null) >= 2000);
            assertTrue(Transport.backoffMs(30, null) <= 60_000);
            String soon = ZonedDateTime.now().plusSeconds(1).format(DateTimeFormatter.RFC_1123_DATE_TIME);
            assertTrue(Transport.backoffMs(0, soon) <= 1000);
            assertEquals(3600, Transport.retryAfterSeconds("3600"));
            assertNull(Transport.retryAfterSeconds("soon"));
        }
    }

    @Nested
    class Streaming {
        @Test
        void streamsChatCompletionsUntilDoneForcingStreamTrue() {
            server.reply(Reply.sse(
                    "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
                    ": keep-alive\n\n",
                    "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\r\n\r\n",
                    "data: [DONE]\n\n",
                    "data: {\"never\":\"seen\"}\n\n"));
            StringBuilder text = new StringBuilder();
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("model", "misar-online");
            body.put("messages", List.of(Map.of("role", "user", "content", "hi")));
            try (SseStream events = server.client().chat.completionsStream(body)) {
                for (SseEvent e : events) text.append(e.data().at("/choices/0/delta/content").asText());
            }
            assertEquals("Hello", text.toString());
            TestServer.Call call = server.calls.get(0);
            assertEquals("POST", call.method);
            assertEquals("/v1/chat/completions", call.url());
            assertTrue(call.json().get("stream").asBoolean());
            assertEquals("misar-online", call.json().get("model").asText());
            assertEquals("text/event-stream", call.header("Accept"));
            assertFalse(body.containsKey("stream"), "the caller's map is not mutated");
        }

        @Test
        void yieldsNamedEventsMultiLineDataAndATrailingFrame() {
            server.reply(Reply.sse("event: step\nid: 1\ndata: line1\ndata: line2\n\n", "data: {\"done\":true}"));
            List<SseEvent> events = server.client().projects.buildStream("p1").toList();
            assertEquals(2, events.size());
            assertEquals(new SseEvent("step", TextNode.valueOf("line1\nline2"), "1"), events.get(0));
            assertTrue(events.get(1).data().get("done").asBoolean());
            assertNull(events.get(1).event());
            assertEquals("GET", server.calls.get(0).method);
            assertEquals("/projects/p1/build-stream", server.calls.get(0).url());
        }

        @Test
        void raisesAPlanLimitFrame() {
            String frame = TestServer.PLAN_LIMIT_BODY.replaceFirst("\\{", "{\"type\":\"error\",");
            server.reply(Reply.sse("data: " + frame + "\n\n"));
            SseStream events = server.client().chat.studioStream(Map.of("message", "hi"));
            PlanLimitException e = assertThrows(PlanLimitException.class, events::hasNext);
            assertEquals("pro", e.getRecommendedPlan());
        }

        @Test
        void raisesAnHttpErrorBeforeStreaming() {
            server.reply(Reply.json(402, TestServer.PLAN_LIMIT_BODY));
            assertThrows(PlanLimitException.class, () -> server.client().projects.buildStream("p1"));
            assertEquals(1, server.calls.size());
        }

        @Test
        void neverRetriesAStream() {
            server.reply(Reply.json(503, "{\"error\":\"down\"}"), Reply.sse("data: 1\n\n"));
            assertThrows(ServerException.class, () -> server.client().projects.buildStream("p1"));
            assertEquals(1, server.calls.size());
        }

        @Test
        void exposesAJavaStream() {
            server.reply(Reply.sse("data: 1\n\n", "data: 2\n\n"));
            try (java.util.stream.Stream<SseEvent> s = server.client().projects.buildStream("p1").stream()) {
                assertEquals(3, s.mapToInt(e -> e.data().asInt()).sum());
            }
        }
    }

    @Nested
    class Paging {
        @Test
        void walksOffsetPagesUntilAShortPage() {
            JsonNode[] pages = {
                    Transport.parse("{\"items\":[1,2]}"),
                    Transport.parse("{\"items\":[3,4]}"),
                    Transport.parse("{\"items\":[5]}"),
            };
            List<Integer> seen = new ArrayList<>();
            List<Integer> offsets = new ArrayList<>();
            for (JsonNode n : Pagination.paginate((offset, limit) -> {
                offsets.add(offset);
                return pages[offsets.size() - 1];
            }, 2, Long.MAX_VALUE)) {
                seen.add(n.asInt());
            }
            assertEquals(List.of(1, 2, 3, 4, 5), seen);
            assertEquals(List.of(0, 2, 4), offsets);
        }

        @Test
        void drivesARealListMethodAndRespectsMaxItems() {
            server.reply(Reply.json("{\"templates\":[{\"id\":1},{\"id\":2}]}"), Reply.json("{\"templates\":[{\"id\":3},{\"id\":4}]}"));
            MisarDevClient dev = server.client();
            List<Integer> ids = new ArrayList<>();
            for (JsonNode t : dev.paginate((offset, limit) -> dev.templates.list(Map.of("offset", offset, "limit", limit)), 2, 3)) {
                ids.add(t.get("id").asInt());
            }
            assertEquals(List.of(1, 2, 3), ids);
            assertEquals(2, server.calls.size());
            assertTrue(server.calls.get(1).url().contains("offset=2"));
        }

        @Test
        void readsTopLevelArrays() {
            assertEquals(2, Pagination.itemsOf(Transport.parse("[1,2]")).size());
            assertEquals(0, Pagination.itemsOf(Transport.parse("{\"total\":3}")).size());
            assertInstanceOf(List.class, Pagination.itemsOf(null));
        }
    }
}
