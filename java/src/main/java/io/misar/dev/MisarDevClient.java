package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;
import io.misar.dev.generated.MisarDevResources;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Function;

/**
 * The MisarDev API client.
 *
 * <p>Every resource ({@code projects}, {@code templates}, {@code chat}, …) is a
 * public final field generated from the API's route tree, so it always matches
 * what the server exposes. The client authenticates with your account API key
 * ({@code mdk_…}) and nothing else.
 *
 * <pre>{@code
 * MisarDevClient dev = new MisarDevClient();            // reads MISARDEV_API_KEY
 * JsonNode projects = dev.projects.list();
 *
 * MisarDevClient custom = MisarDevClient.builder()
 *         .apiKey("mdk_...")
 *         .maxRetries(5)
 *         .timeout(Duration.ofSeconds(120))
 *         .build();
 * }</pre>
 *
 * <p>Thread-safe: share one instance.
 */
public final class MisarDevClient extends MisarDevResources {

    private final Transport transport;

    /** A client keyed from {@code MISARDEV_API_KEY}. Throws when it is unset. */
    public MisarDevClient() {
        this(builder());
    }

    /** A client with this API key, falling back to {@code MISARDEV_API_KEY} when null or empty. */
    public MisarDevClient(String apiKey) {
        this(builder().apiKey(apiKey));
    }

    private MisarDevClient(Builder b) {
        this(b.transport());
    }

    private MisarDevClient(Transport transport) {
        super(transport);
        this.transport = transport;
    }

    public static Builder builder() {
        return new Builder();
    }

    /** The base URL every request goes to. */
    public String baseUrl() {
        return transport.baseUrl();
    }

    /** The underlying transport. */
    public Transport transport() {
        return transport;
    }

    /**
     * Call any route directly, for anything the SDK does not wrap yet.
     *
     * @param path path below the base URL, e.g. {@code "/usage"}
     */
    public JsonNode request(String method, String path, Map<String, ?> query, Object body) {
        return transport.request(method, path, query, body);
    }

    /** Open any SSE route directly. {@code terminator} is {@code "[DONE]"} or null to read to EOF. */
    public SseStream stream(String method, String path, Map<String, ?> query, Object body, String terminator) {
        return transport.stream(method, path, query, body, terminator);
    }

    /** Walk every page of an offset-paginated list. See {@link Pagination}. */
    public Iterable<JsonNode> paginate(Pagination.PageFetcher fetchPage) {
        return Pagination.paginate(fetchPage);
    }

    /** Walk every page of an offset-paginated list. See {@link Pagination}. */
    public Iterable<JsonNode> paginate(Pagination.PageFetcher fetchPage, int pageSize, long maxItems) {
        return Pagination.paginate(fetchPage, pageSize, maxItems);
    }

    /** Options for {@link MisarDevClient}. */
    public static final class Builder {
        private String apiKey;
        private String baseUrl;
        private int maxRetries = 3;
        private Duration timeout = Duration.ofSeconds(60);
        private HttpClient httpClient;
        private final Map<String, String> headers = new LinkedHashMap<>();
        private Function<String, String> env = System::getenv;

        private Builder() {
        }

        /** The {@code mdk_…} key. Defaults to {@code MISARDEV_API_KEY}. */
        public Builder apiKey(String apiKey) {
            this.apiKey = apiKey;
            return this;
        }

        /** Defaults to {@code MISARDEV_BASE_URL}, else {@code https://api.misar.io/dev}. */
        public Builder baseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
            return this;
        }

        /** Total attempts for a retryable failure. Default 3. */
        public Builder maxRetries(int maxRetries) {
            this.maxRetries = maxRetries;
            return this;
        }

        /** Per-attempt timeout. Default 60 seconds — builds and AI calls are slow. */
        public Builder timeout(Duration timeout) {
            this.timeout = timeout;
            return this;
        }

        /** Use your own {@link HttpClient} (proxies, custom TLS, tests). */
        public Builder httpClient(HttpClient httpClient) {
            this.httpClient = httpClient;
            return this;
        }

        /** An extra header sent with every request. */
        public Builder header(String name, String value) {
            this.headers.put(name, value);
            return this;
        }

        /** Environment lookup, replaceable in tests. */
        Builder env(Function<String, String> env) {
            this.env = env;
            return this;
        }

        private Transport transport() {
            return new Transport(apiKey, baseUrl, maxRetries, timeout, httpClient, headers, env);
        }

        public MisarDevClient build() {
            return new MisarDevClient(this);
        }
    }
}
