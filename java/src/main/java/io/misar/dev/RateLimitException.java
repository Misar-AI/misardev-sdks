package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * 429 that is an ordinary throttle (identical for every user). The client has
 * already retried it {@code maxRetries} times, honouring {@code Retry-After},
 * before throwing this.
 */
public class RateLimitException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    private final Integer retryAfter;

    public RateLimitException(int status, String message, String code, JsonNode body, String requestId, Integer retryAfter) {
        super(status, message, code, body, requestId, null);
        this.retryAfter = retryAfter;
    }

    /** Seconds the server asked us to wait ({@code Retry-After}), or {@code null} when it did not say. */
    public Integer getRetryAfter() {
        return retryAfter;
    }
}
