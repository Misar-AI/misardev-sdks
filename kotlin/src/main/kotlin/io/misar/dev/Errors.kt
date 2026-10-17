package io.misar.dev

import com.fasterxml.jackson.databind.JsonNode

/**
 * Base class of every error the MisarDev SDK throws.
 *
 * Every non-2xx answer becomes a [MisarDevException]; the subclasses let a
 * caller branch on the kind of failure without parsing strings. The one that
 * matters most commercially is [PlanLimitException]: the key is valid, but the
 * subscription behind it does not cover the call.
 *
 * @property status HTTP status, or `0` when the request never got an answer.
 * @property code Machine-readable error code (`body.code` or `body.error.code`).
 * @property body The decoded error body (JSON, or a text node for a non-JSON body).
 * @property requestId The `x-request-id` response header, for support requests.
 */
open class MisarDevException(
    val status: Int,
    message: String,
    val code: String? = null,
    val body: JsonNode? = null,
    val requestId: String? = null,
    cause: Throwable? = null,
) : RuntimeException(message, cause) {
    /** Worth retrying as-is: a throttle or a transient server condition. */
    val isRetryable: Boolean get() = status == 429 || status in 500..599
}

/** 400 / 422 — the request was malformed or failed validation. */
class ValidationException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/** 401 — the key is missing, revoked, expired, or not a MisarDev key. */
class AuthenticationException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/** 403 — authenticated, but not allowed to touch this resource. */
class PermissionDeniedException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/** 404 — no such resource, or not one this key can see. */
class NotFoundException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/** 409 — conflicts with current state (for example a build already running). */
class ConflictException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/**
 * 429 that is an ordinary throttle (identical for every user). The client has
 * already retried it `maxRetries` times, honouring `Retry-After`, before
 * throwing this.
 *
 * @property retryAfter Seconds the server asked us to wait, when it said.
 */
class RateLimitException(
    status: Int,
    message: String,
    code: String?,
    body: JsonNode?,
    requestId: String?,
    val retryAfter: Int?,
) : MisarDevException(status, message, code, body, requestId)

/** 5xx — the API failed. Retried automatically for idempotent requests (GET, HEAD, OPTIONS, PUT, DELETE). */
class ServerException(status: Int, message: String, code: String?, body: JsonNode?, requestId: String?) :
    MisarDevException(status, message, code, body, requestId)

/** The request never got an HTTP answer (DNS, TLS, connection reset, timeout). Status is `0`. */
class NetworkException(message: String, cause: Throwable? = null) :
    MisarDevException(0, message, "network_error", null, null, cause)

/**
 * The subscription behind the API key blocks this call.
 *
 * Detected by `code: "plan_limit_exceeded"` in the body — never by status,
 * because a spent quota is a 429 (`quota_exhausted`) that would otherwise look
 * like an ordinary throttle, and a feature outside the plan is a 402
 * (`feature_locked`). Retrying cannot help until the plan changes or the period
 * resets, so the client never retries it.
 *
 * @property offer The full `upgrade` object from the body, every field kept.
 *   Render it rather than a bare failure; all copy comes from the server.
 * @property retryAfter Seconds until a quota resets (`Retry-After`), for `quota_exhausted` blocks.
 */
class PlanLimitException(
    status: Int,
    message: String,
    body: JsonNode?,
    requestId: String?,
    val offer: JsonNode?,
    val retryAfter: Int?,
) : MisarDevException(status, message, "plan_limit_exceeded", body, requestId) {

    /** Where to send the user to unblock themselves: `offer.urls.billing`, else `offer.urls.pricing`. */
    val upgradeUrl: String? get() = text("urls", "billing") ?: text("urls", "pricing")

    /** The machine key of the limit that was hit, for example `api_access`. */
    val feature: String? get() = text("feature")

    /** The slug of the plan the key is on (`offer.current_plan.slug`). */
    val currentPlan: String? get() = text("current_plan", "slug")

    /** The slug of the plan the server recommends (`offer.recommended_plan`). */
    val recommendedPlan: String? get() = text("recommended_plan")

    private fun text(vararg path: String): String? {
        var cur: JsonNode? = offer
        for (p in path) {
            if (cur == null || !cur.isObject) return null
            cur = cur.get(p)
        }
        return if (cur != null && cur.isTextual) cur.asText() else null
    }
}
