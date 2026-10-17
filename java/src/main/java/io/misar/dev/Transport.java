package io.misar.dev;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.TextNode;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpHeaders;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Function;

/**
 * HTTP transport shared by the generated resource layer.
 *
 * <p>Everything the SDK does goes through here, and it authenticates exactly one
 * way: the account API key ({@code mdk_…}), sent as
 * {@code Authorization: Bearer <key>}. There is no second credential path. What
 * a key may do — and how much of it — is decided server-side from the
 * subscription behind that key; the SDK carries the key and surfaces the answer
 * rather than deciding locally what a plan allows.
 *
 * <p>Public because the generated resources live in another package. Use
 * {@link MisarDevClient#request} for routes the SDK does not wrap.
 */
public final class Transport {

    /** Default API base URL. Override with the builder or {@code MISARDEV_BASE_URL}. */
    public static final String DEFAULT_BASE_URL = "https://api.misar.io/dev";
    /** This SDK's version, sent in {@code X-Misar-SDK}. */
    public static final String SDK_VERSION = "1.0.0";
    /** Where users create API keys; quoted in the missing-key error. */
    public static final String API_KEYS_URL = "https://www.misar.dev/settings/api-keys";

    static final ObjectMapper MAPPER = new ObjectMapper()
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);

    /** Statuses worth retrying. 429 only when it is NOT a plan limit. */
    private static final Set<Integer> RETRYABLE = Set.of(429, 500, 502, 503, 504);
    /**
     * A 5xx or a dropped connection on a POST may already have done its work —
     * started a build, charged an allowance. Only requests that are safe to
     * repeat are retried on those; a 429 is always safe because the server
     * refused it before doing anything.
     */
    private static final Set<String> IDEMPOTENT = Set.of("GET", "HEAD", "OPTIONS", "PUT", "DELETE");
    static final long MAX_BACKOFF_MS = 60_000L;
    private static final String PLAN_LIMIT_CODE = "plan_limit_exceeded";

    private final String apiKey;
    private final String baseUrl;
    private final int maxRetries;
    private final Duration timeout;
    private final HttpClient http;
    private final Map<String, String> extraHeaders;

    Transport(String apiKey, String baseUrl, int maxRetries, Duration timeout, HttpClient http,
              Map<String, String> extraHeaders, Function<String, String> env) {
        String key = apiKey;
        if (key == null || key.isBlank()) key = env.apply("MISARDEV_API_KEY");
        if (key == null || key.isBlank()) {
            throw new MisarDevException(0,
                    "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. "
                            + "Create one at " + API_KEYS_URL + ".",
                    "missing_api_key");
        }
        this.apiKey = key.trim();
        String base = baseUrl;
        if (base == null || base.isBlank()) base = env.apply("MISARDEV_BASE_URL");
        if (base == null || base.isBlank()) base = DEFAULT_BASE_URL;
        while (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        this.baseUrl = base;
        this.maxRetries = Math.max(1, maxRetries);
        this.timeout = timeout != null ? timeout : Duration.ofSeconds(60);
        this.http = http != null ? http : HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
        this.extraHeaders = extraHeaders != null ? new LinkedHashMap<>(extraHeaders) : Collections.emptyMap();
    }

    public String baseUrl() {
        return baseUrl;
    }

    public int maxRetries() {
        return maxRetries;
    }

    public Duration timeout() {
        return timeout;
    }

    // ── Requests ──────────────────────────────────────────────────────────────

    /**
     * Send one request, retrying throttles and (for idempotent verbs) transient failures.
     *
     * @param method HTTP verb
     * @param path   path below the base URL, already encoded (see {@link #encode})
     * @param query  query parameters; null values are dropped (may be null)
     * @param body   JSON body (any Jackson-serialisable value), or null for none
     * @return the decoded JSON, a text node for a non-JSON body, or {@code null} for 204 / empty
     */
    public JsonNode request(String method, String path, Map<String, ?> query, Object body) {
        String verb = method.toUpperCase(Locale.ROOT);
        URI uri = URI.create(baseUrl + path + buildQuery(query));
        String payload = serialize(body);

        for (int attempt = 0; ; attempt++) {
            boolean last = attempt >= maxRetries - 1;
            HttpRequest req = build(verb, uri, payload, "application/json").timeout(timeout).build();

            HttpResponse<String> res;
            try {
                res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            } catch (IOException e) {
                if (!last && IDEMPOTENT.contains(verb)) {
                    sleep(backoffMs(attempt, null));
                    continue;
                }
                throw new NetworkException(e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName(), e);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new NetworkException("Interrupted", e);
            }

            int status = res.statusCode();
            if (status >= 200 && status < 300) return decode(status, res.body());

            // Read the body BEFORE deciding to retry: a 429 from the rate limiter
            // and a 429 from a spent plan allowance share a status, and only the
            // first is worth retrying.
            JsonNode errBody = decode(status, res.body());
            MisarDevException error = errorFor(status, res.headers(), errBody);
            if (error instanceof PlanLimitException) throw error;

            boolean retryable = RETRYABLE.contains(status) && (status == 429 || IDEMPOTENT.contains(verb));
            if (retryable && !last) {
                sleep(backoffMs(attempt, res.headers().firstValue("retry-after").orElse(null)));
                continue;
            }
            throw error;
        }
    }

    /**
     * Open a Server-Sent Events stream.
     *
     * <p>Never retried: a stream that fails mid-flight cannot be replayed
     * without duplicating what the caller already consumed. A non-2xx answer
     * raises the same typed error as {@link #request}; a frame whose data is a
     * plan-limit refusal raises {@link PlanLimitException} while iterating.
     *
     * @param terminator data payload that ends the stream ({@code "[DONE]"}), or null to read to EOF
     */
    public SseStream stream(String method, String path, Map<String, ?> query, Object body, String terminator) {
        String verb = method.toUpperCase(Locale.ROOT);
        URI uri = URI.create(baseUrl + path + buildQuery(query));
        HttpRequest req = build(verb, uri, serialize(body), "text/event-stream").timeout(timeout).build();

        HttpResponse<InputStream> res;
        try {
            res = http.send(req, HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException e) {
            throw new NetworkException(e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName(), e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new NetworkException("Interrupted", e);
        }

        int status = res.statusCode();
        if (status < 200 || status >= 300) {
            String text;
            try (InputStream in = res.body()) {
                text = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            } catch (IOException e) {
                text = "";
            }
            throw errorFor(status, res.headers(), decode(status, text));
        }
        return new SseStream(res.body(), terminator, res.headers());
    }

    private HttpRequest.Builder build(String verb, URI uri, String payload, String accept) {
        HttpRequest.Builder rb = HttpRequest.newBuilder(uri)
                .header("Authorization", "Bearer " + apiKey)
                .header("Accept", accept)
                .header("Content-Type", "application/json")
                .header("X-Misar-SDK", "misardev-java/" + SDK_VERSION);
        for (Map.Entry<String, String> h : extraHeaders.entrySet()) rb.setHeader(h.getKey(), h.getValue());
        HttpRequest.BodyPublisher publisher = payload != null
                ? HttpRequest.BodyPublishers.ofString(payload, StandardCharsets.UTF_8)
                : HttpRequest.BodyPublishers.noBody();
        return rb.method(verb, publisher);
    }

    private static String serialize(Object body) {
        if (body == null) return null;
        try {
            return MAPPER.writeValueAsString(body);
        } catch (JsonProcessingException e) {
            throw new MisarDevException(0, "Could not serialise the request body: " + e.getOriginalMessage(), "invalid_body", null, null, e);
        }
    }

    private static void sleep(long ms) {
        if (ms <= 0) return;
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new NetworkException("Interrupted while waiting to retry", e);
        }
    }

    // ── Encoding helpers (used by the generated layer) ────────────────────────

    /**
     * Percent-encode one path segment or query component (RFC 3986): everything
     * except {@code A-Z a-z 0-9 - . _ ~} is encoded, so {@code "a b/c"} becomes
     * {@code "a%20b%2Fc"}.
     */
    public static String encode(Object value) {
        String s = String.valueOf(value);
        byte[] bytes = s.getBytes(StandardCharsets.UTF_8);
        StringBuilder out = new StringBuilder(bytes.length + 8);
        for (byte b : bytes) {
            int c = b & 0xFF;
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
                    || c == '-' || c == '.' || c == '_' || c == '~') {
                out.append((char) c);
            } else {
                out.append('%').append(Character.toUpperCase(Character.forDigit(c >> 4, 16)))
                        .append(Character.toUpperCase(Character.forDigit(c & 0xF, 16)));
            }
        }
        return out.toString();
    }

    /** {@code ?a=1&b=true}, dropping null values; empty string when nothing is left. */
    public static String buildQuery(Map<String, ?> query) {
        if (query == null || query.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, ?> e : query.entrySet()) {
            Object v = e.getValue();
            if (v == null) continue;
            String s = v instanceof JsonNode ? ((JsonNode) v).asText() : String.valueOf(v);
            sb.append(sb.length() == 0 ? '?' : '&').append(encode(e.getKey())).append('=').append(encode(s));
        }
        return sb.toString();
    }

    /**
     * Merge a caller's optional query map with positional required parameters
     * ({@code name, value, name, value…}); required values win.
     */
    public static Map<String, Object> query(Map<String, ?> optional, Object... required) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (optional != null) out.putAll(optional);
        for (int i = 0; i + 1 < required.length; i += 2) out.put(String.valueOf(required[i]), required[i + 1]);
        return out;
    }

    /** A copy of {@code body} with {@code "stream": true} set, for the OpenAI-compatible stream. */
    public static Map<String, Object> withStream(Map<String, ?> body) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (body != null) out.putAll(body);
        out.put("stream", Boolean.TRUE);
        return out;
    }

    // ── Response decoding and error mapping ───────────────────────────────────

    static JsonNode decode(int status, String text) {
        if (status == 204 || text == null || text.isEmpty()) return null;
        return parse(text);
    }

    /** JSON when it parses, else a text node holding the raw string. */
    static JsonNode parse(String text) {
        if (text.isBlank()) return TextNode.valueOf(text);
        try {
            JsonNode node = MAPPER.readTree(text);
            return node == null || node.isMissingNode() ? TextNode.valueOf(text) : node;
        } catch (JsonProcessingException e) {
            return TextNode.valueOf(text);
        }
    }

    /** True when a body is the {@code @misar/upsell} plan-limit refusal. */
    static boolean isPlanLimitBody(JsonNode body) {
        return body != null && body.isObject() && PLAN_LIMIT_CODE.equals(body.path("code").asText(null));
    }

    /** Pull a human message out of the API's several error shapes. */
    static String messageOf(JsonNode body, String fallback) {
        if (body != null && body.isObject()) {
            JsonNode err = body.get("error");
            if (err != null && err.isTextual()) return err.asText();
            // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
            if (err != null && err.isObject() && err.path("message").isTextual()) return err.get("message").asText();
            JsonNode msg = body.get("message");
            if (msg != null && msg.isTextual()) return msg.asText();
        }
        if (body != null && body.isTextual() && !body.asText().isBlank()) {
            String t = body.asText().trim();
            return t.length() > 500 ? t.substring(0, 500) : t;
        }
        return fallback;
    }

    static String codeOf(JsonNode body) {
        if (body == null || !body.isObject()) return null;
        JsonNode code = body.get("code");
        if (code != null && code.isTextual()) return code.asText();
        JsonNode err = body.get("error");
        if (err != null && err.isObject() && err.path("code").isTextual()) return err.get("code").asText();
        return null;
    }

    /** Map an error response to the right typed error. Plan limits first, by {@code code}. */
    static MisarDevException errorFor(int status, HttpHeaders headers, JsonNode body) {
        String requestId = headers != null ? headers.firstValue("x-request-id").orElse(null) : null;
        String retryAfterHeader = headers != null ? headers.firstValue("retry-after").orElse(null) : null;
        String message = messageOf(body, "HTTP " + status);
        String code = codeOf(body);

        if (isPlanLimitBody(body)) {
            JsonNode offer = body.get("upgrade");
            if (offer != null && offer.isNull()) offer = null;
            return new PlanLimitException(status, message, body, requestId, offer, retryAfterSeconds(retryAfterHeader));
        }
        if (status == 400 || status == 422) return new ValidationException(status, message, code, body, requestId);
        if (status == 401) return new AuthenticationException(status, message, code, body, requestId);
        if (status == 403) return new PermissionDeniedException(status, message, code, body, requestId);
        if (status == 404) return new NotFoundException(status, message, code, body, requestId);
        if (status == 409) return new ConflictException(status, message, code, body, requestId);
        if (status == 429) {
            return new RateLimitException(status, message, code, body, requestId, retryAfterSeconds(retryAfterHeader));
        }
        if (status >= 500) return new ServerException(status, message, code, body, requestId);
        return new MisarDevException(status, message, code, body, requestId, null);
    }

    /** {@code Retry-After} as whole seconds (numeric or HTTP-date), or null. */
    static Integer retryAfterSeconds(String value) {
        if (value == null || value.isBlank()) return null;
        String v = value.trim();
        try {
            double seconds = Double.parseDouble(v);
            if (seconds >= 0 && !Double.isInfinite(seconds)) return (int) Math.ceil(seconds);
            return null;
        } catch (NumberFormatException ignored) {
            // fall through to HTTP-date
        }
        Long at = httpDateMillis(v);
        if (at == null) return null;
        return (int) Math.max(0, Math.ceil((at - System.currentTimeMillis()) / 1000.0));
    }

    /** Exponential backoff with jitter, but honour {@code Retry-After} when sent. Capped at 60s. */
    static long backoffMs(int attempt, String retryAfter) {
        if (retryAfter != null && !retryAfter.isBlank()) {
            String v = retryAfter.trim();
            try {
                double seconds = Double.parseDouble(v);
                if (seconds >= 0 && !Double.isInfinite(seconds)) return Math.min((long) (seconds * 1000), MAX_BACKOFF_MS);
            } catch (NumberFormatException ignored) {
                Long at = httpDateMillis(v);
                if (at != null) return Math.min(Math.max(0, at - System.currentTimeMillis()), MAX_BACKOFF_MS);
            }
        }
        double base = 250.0 * Math.pow(2, attempt);
        double jitter = ThreadLocalRandom.current().nextDouble() * base * 0.25;
        return (long) Math.min(base + jitter, MAX_BACKOFF_MS);
    }

    private static Long httpDateMillis(String v) {
        try {
            return ZonedDateTime.parse(v, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli();
        } catch (RuntimeException e) {
            return null;
        }
    }
}
