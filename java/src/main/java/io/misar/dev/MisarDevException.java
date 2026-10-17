package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Base class of every error the MisarDev SDK throws.
 *
 * <p>Every non-2xx answer becomes a {@code MisarDevException}; the subclasses
 * let a caller branch on the kind of failure without parsing strings:
 *
 * <ul>
 *   <li>{@link ValidationException} — 400 / 422</li>
 *   <li>{@link AuthenticationException} — 401</li>
 *   <li>{@link PermissionDeniedException} — 403</li>
 *   <li>{@link NotFoundException} — 404</li>
 *   <li>{@link ConflictException} — 409</li>
 *   <li>{@link RateLimitException} — 429 that is an ordinary throttle</li>
 *   <li>{@link ServerException} — 5xx</li>
 *   <li>{@link NetworkException} — no HTTP answer at all (status 0)</li>
 *   <li>{@link PlanLimitException} — the plan behind the key blocks the call
 *       ({@code code: "plan_limit_exceeded"}, whatever the status)</li>
 * </ul>
 *
 * <p>Unchecked, so SDK calls compose with lambdas, streams and
 * {@link Pagination#paginate}.
 */
public class MisarDevException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    private final int status;
    private final String code;
    private final transient JsonNode body;
    private final String requestId;

    public MisarDevException(int status, String message, String code, JsonNode body, String requestId, Throwable cause) {
        super(message, cause);
        this.status = status;
        this.code = code;
        this.body = body;
        this.requestId = requestId;
    }

    public MisarDevException(int status, String message, String code) {
        this(status, message, code, null, null, null);
    }

    /** HTTP status, or {@code 0} when the request never got an answer. */
    public int getStatus() {
        return status;
    }

    /** Machine-readable error code from the body ({@code body.code} or {@code body.error.code}), or {@code null}. */
    public String getCode() {
        return code;
    }

    /** The decoded error body (JSON, or a text node for a non-JSON body), or {@code null}. */
    public JsonNode getBody() {
        return body;
    }

    /** The {@code x-request-id} response header, for support requests, or {@code null}. */
    public String getRequestId() {
        return requestId;
    }

    /** Worth retrying as-is: a throttle or a transient server condition. */
    public boolean isRetryable() {
        return status == 429 || (status >= 500 && status < 600);
    }
}
