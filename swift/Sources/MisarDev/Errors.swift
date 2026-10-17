import Foundation

/// Base type for every error the SDK throws.
///
/// Every non-2xx answer becomes a `MisarDevError`; the subclasses let a caller
/// branch with `catch let e as PlanLimitError` without parsing strings. The one
/// that matters most commercially is ``PlanLimitError``: the key is valid, but
/// the subscription behind it does not cover the call. It carries the full
/// upgrade offer the server sent, so an app can render an upgrade card.
public class MisarDevError: Error, CustomStringConvertible, LocalizedError, @unchecked Sendable {
    /// HTTP status, or 0 when the request never got an answer.
    public let status: Int
    public let message: String
    /// Machine-readable error code (`body.code` or `body.error.code`).
    public let code: String?
    /// The decoded error body (a `.string` for non-JSON bodies).
    public let body: JSONValue?
    /// The error body exactly as received.
    public let rawBody: String?
    /// The `x-request-id` response header, for support requests.
    public let requestId: String?

    public init(
        status: Int,
        message: String,
        code: String? = nil,
        body: JSONValue? = nil,
        rawBody: String? = nil,
        requestId: String? = nil
    ) {
        self.status = status
        self.message = message
        self.code = code
        self.body = body
        self.rawBody = rawBody
        self.requestId = requestId
    }

    /// Worth retrying as-is: a throttle or a transient server condition.
    public var isRetryable: Bool { status == 429 || (500..<600).contains(status) }

    public var description: String {
        "\(type(of: self))(\(status)): \(message)"
    }

    public var errorDescription: String? { message }
}

/// 400 / 422 — the request was malformed or failed validation.
public final class ValidationError: MisarDevError, @unchecked Sendable {}

/// 401 — the key is missing, revoked, expired, or not a MisarDev key.
public final class AuthenticationError: MisarDevError, @unchecked Sendable {}

/// 403 — authenticated, but not allowed to touch this resource.
public final class PermissionDeniedError: MisarDevError, @unchecked Sendable {}

/// 404 — no such resource, or not one this key can see.
public final class NotFoundError: MisarDevError, @unchecked Sendable {}

/// 409 — conflicts with current state (e.g. a build already running).
public final class ConflictError: MisarDevError, @unchecked Sendable {}

/// 5xx — the API failed. Retried automatically for idempotent requests.
public final class ServerError: MisarDevError, @unchecked Sendable {}

/// 429 that is an ordinary throttle. The transport already retried it
/// `maxRetries` times before throwing this.
public final class RateLimitError: MisarDevError, @unchecked Sendable {
    /// Seconds the server asked us to wait, when it said.
    public let retryAfter: Int?

    public init(
        status: Int,
        message: String,
        code: String? = nil,
        body: JSONValue? = nil,
        rawBody: String? = nil,
        requestId: String? = nil,
        retryAfter: Int?
    ) {
        self.retryAfter = retryAfter
        super.init(status: status, message: message, code: code, body: body, rawBody: rawBody, requestId: requestId)
    }
}

/// The request never got an HTTP answer (DNS, TLS, reset, timeout). `status` is 0.
public final class NetworkError: MisarDevError, @unchecked Sendable {
    /// The underlying URL loading error.
    public let underlying: Error?

    public init(message: String, underlying: Error? = nil) {
        self.underlying = underlying
        super.init(status: 0, message: message, code: "network_error")
    }
}

/// The subscription behind the API key blocks this call.
///
/// Detected by `code: "plan_limit_exceeded"` in the body — never by status,
/// because a spent quota is a 429 that would otherwise look like an ordinary
/// throttle. A locked feature answers 402 (`feature_locked`), a spent allowance
/// 429 (`quota_exhausted`). Retrying cannot help until the plan changes or the
/// period resets, so the transport never retries it.
public final class PlanLimitError: MisarDevError, @unchecked Sendable {
    /// The full upgrade offer (every field the server sent). Render it; all copy comes from the server.
    public let offer: JSONValue?
    /// Seconds until a quota resets (`Retry-After`), for `quota_exhausted` blocks.
    public let retryAfter: Int?

    public init(
        status: Int,
        message: String,
        body: JSONValue? = nil,
        rawBody: String? = nil,
        requestId: String? = nil,
        offer: JSONValue?,
        retryAfter: Int?
    ) {
        self.offer = offer
        self.retryAfter = retryAfter
        super.init(
            status: status, message: message, code: "plan_limit_exceeded",
            body: body, rawBody: rawBody, requestId: requestId
        )
    }

    /// Where to send the user to unblock themselves: `offer.urls.billing`, else `offer.urls.pricing`.
    public var upgradeUrl: String? {
        offer?["urls"]?["billing"]?.stringValue ?? offer?["urls"]?["pricing"]?.stringValue
    }

    /// The machine key of the limit that was hit, e.g. `api_access`.
    public var feature: String? { offer?["feature"]?.stringValue }

    /// The account's current plan slug (`offer.current_plan.slug`).
    public var currentPlan: String? { offer?["current_plan"]?["slug"]?.stringValue }

    /// The plan the server recommends (`offer.recommended_plan`).
    public var recommendedPlan: String? { offer?["recommended_plan"]?.stringValue }

    /// Why the call was refused: `feature_locked`, `quota_exhausted`, …
    public var reason: String? { offer?["reason"]?.stringValue }

    /// One-line, user-facing explanation from the server.
    public var headline: String? { offer?["headline"]?.stringValue }
}
