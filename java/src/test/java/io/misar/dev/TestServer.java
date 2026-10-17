package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A real local HTTP server that records every request and answers from a queue.
 *
 * <p>The JDK's own {@link HttpServer} rather than a mocking library: the client
 * is built on java.net.http, so a real socket tests the transport that actually
 * ships — and the SSE tests need a server that flushes a body in pieces, which
 * is where frame-boundary bugs live. Nothing leaves 127.0.0.1.
 */
final class TestServer implements AutoCloseable {

    /** One recorded request. */
    static final class Call {
        final String method;
        final String path;   // raw, still percent-encoded
        final String query;  // raw, or null
        final Map<String, String> headers;
        final String body;

        Call(String method, String path, String query, Map<String, String> headers, String body) {
            this.method = method;
            this.path = path;
            this.query = query;
            this.headers = headers;
            this.body = body;
        }

        String url() {
            return path + (query != null ? "?" + query : "");
        }

        String header(String name) {
            return headers.get(name.toLowerCase());
        }

        JsonNode json() {
            return body == null || body.isEmpty() ? null : Transport.parse(body);
        }
    }

    /** One canned answer. */
    static final class Reply {
        final int status;
        final String body;
        final Map<String, String> headers = new LinkedHashMap<>();
        final List<String> ssePieces;

        private Reply(int status, String body, List<String> ssePieces) {
            this.status = status;
            this.body = body;
            this.ssePieces = ssePieces;
        }

        static Reply json(int status, String body) {
            Reply r = new Reply(status, body, null);
            r.headers.put("Content-Type", "application/json");
            return r;
        }

        static Reply json(String body) {
            return json(200, body);
        }

        static Reply text(int status, String body) {
            Reply r = new Reply(status, body, null);
            r.headers.put("Content-Type", "text/plain");
            return r;
        }

        static Reply empty(int status) {
            return new Reply(status, null, null);
        }

        static Reply sse(String... pieces) {
            Reply r = new Reply(200, null, List.of(pieces));
            r.headers.put("Content-Type", "text/event-stream");
            return r;
        }

        Reply header(String name, String value) {
            headers.put(name, value);
            return this;
        }
    }

    final List<Call> calls = Collections.synchronizedList(new ArrayList<>());
    private final Deque<Reply> queue = new ArrayDeque<>();
    private final HttpServer server;

    TestServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", this::handle);
        server.start();
    }

    /** Queue replies; the last one keeps answering once the others are used. */
    TestServer reply(Reply... replies) {
        synchronized (queue) {
            queue.addAll(List.of(replies));
        }
        return this;
    }

    String base() {
        return "http://127.0.0.1:" + server.getAddress().getPort() + "/dev";
    }

    MisarDevClient client(int maxRetries) {
        return MisarDevClient.builder().apiKey("mdk_test_key").baseUrl(base()).maxRetries(maxRetries).build();
    }

    MisarDevClient client() {
        return client(3);
    }

    private void handle(HttpExchange ex) throws IOException {
        Map<String, String> headers = new LinkedHashMap<>();
        ex.getRequestHeaders().forEach((k, v) -> headers.put(k.toLowerCase(), String.join(",", v)));
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        String path = ex.getRequestURI().getRawPath();
        if (path.startsWith("/dev")) path = path.substring(4);
        calls.add(new Call(ex.getRequestMethod(), path, ex.getRequestURI().getRawQuery(), headers, body));

        Reply r;
        synchronized (queue) {
            r = queue.size() > 1 ? queue.poll() : queue.peek();
        }
        if (r == null) r = Reply.json("{\"ok\":true}");
        r.headers.forEach((k, v) -> ex.getResponseHeaders().add(k, v));

        if (r.ssePieces != null) {
            ex.sendResponseHeaders(r.status, 0);
            try (OutputStream out = ex.getResponseBody()) {
                for (String piece : r.ssePieces) {
                    out.write(piece.getBytes(StandardCharsets.UTF_8));
                    out.flush();
                }
            }
            return;
        }
        if (r.body == null) {
            ex.sendResponseHeaders(r.status, -1);
            ex.close();
            return;
        }
        byte[] bytes = r.body.getBytes(StandardCharsets.UTF_8);
        ex.sendResponseHeaders(r.status, bytes.length);
        try (OutputStream out = ex.getResponseBody()) {
            out.write(bytes);
        }
    }

    @Override
    public void close() {
        server.stop(0);
    }

    static final String PLAN_LIMIT_BODY = "{\"error\":\"API access requires the Pro plan or higher.\",\"code\":\"plan_limit_exceeded\",\"requiredPlan\":\"pro\","
            + "\"upgrade\":{\"product\":\"dev\",\"product_name\":\"Misar.Dev\",\"reason\":\"feature_locked\",\"feature\":\"api_access\","
            + "\"feature_label\":\"API access\",\"headline\":\"API access isn't included in your Starter plan.\",\"usage\":null,"
            + "\"current_plan\":{\"slug\":\"starter\",\"name\":\"Starter\"},\"recommended_plan\":\"pro\",\"plans\":[],\"topup\":null,"
            + "\"overage\":null,\"trial\":null,\"cross_sell\":[],"
            + "\"urls\":{\"pricing\":\"https://www.misar.dev/pricing\",\"billing\":\"https://www.misar.dev/settings/billing\","
            + "\"docs\":\"https://docs.misar.io/dev/api\",\"compare\":\"https://www.misar.dev/pricing#compare\"},"
            + "\"cta\":\"Upgrade to Pro to continue.\"}}";

    static final String QUOTA_BODY = PLAN_LIMIT_BODY.replace("\"feature_locked\"", "\"quota_exhausted\"");
}
