using System.Text.Json.Nodes;

namespace MisarDev;

/// <summary>
/// Base type for every error the SDK throws. Every non-2xx answer becomes one
/// of these; the subclasses let a caller branch on the kind of failure without
/// parsing strings.
/// </summary>
/// <remarks>
/// The one that matters most commercially is <see cref="PlanLimitException"/>:
/// the key is valid, but the subscription behind it does not cover the call.
/// It carries the full upgrade offer the server sent, so an app can render an
/// upgrade card rather than a bare failure.
/// </remarks>
public class MisarDevException : Exception
{
    /// <summary>HTTP status, or <c>0</c> when the request never got an answer.</summary>
    public int Status { get; }

    /// <summary>Machine-readable error code from the body (<c>body.code</c> or <c>body.error.code</c>).</summary>
    public string? Code { get; }

    /// <summary>The decoded error body (JSON, or a string value for non-JSON bodies).</summary>
    public JsonNode? Body { get; }

    /// <summary>The error body exactly as received.</summary>
    public string? RawBody { get; }

    /// <summary>The <c>x-request-id</c> response header, for support requests.</summary>
    public string? RequestId { get; }

    public MisarDevException(
        int status,
        string message,
        string? code = null,
        JsonNode? body = null,
        string? rawBody = null,
        string? requestId = null,
        Exception? inner = null)
        : base(message, inner)
    {
        Status = status;
        Code = code;
        Body = body;
        RawBody = rawBody;
        RequestId = requestId;
    }

    /// <summary>Worth retrying as-is: a throttle or a transient server condition.</summary>
    public bool IsRetryable => Status == 429 || (Status >= 500 && Status < 600);
}

/// <summary>400 / 422 — the request was malformed or failed validation.</summary>
public sealed class ValidationException : MisarDevException
{
    public ValidationException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>401 — the key is missing, revoked, expired, or not a MisarDev key.</summary>
public sealed class AuthenticationException : MisarDevException
{
    public AuthenticationException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>403 — authenticated, but not allowed to touch this resource.</summary>
public sealed class PermissionDeniedException : MisarDevException
{
    public PermissionDeniedException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>404 — no such resource, or not one this key can see.</summary>
public sealed class NotFoundException : MisarDevException
{
    public NotFoundException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>409 — conflicts with current state (e.g. a build already running).</summary>
public sealed class ConflictException : MisarDevException
{
    public ConflictException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>
/// 429 that is an ordinary throttle. The transport already retried it
/// <c>MaxRetries</c> times before throwing this.
/// </summary>
public sealed class RateLimitException : MisarDevException
{
    /// <summary>Seconds the server asked us to wait, when it said.</summary>
    public int? RetryAfter { get; }

    public RateLimitException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null, int? retryAfter = null)
        : base(status, message, code, body, rawBody, requestId)
    {
        RetryAfter = retryAfter;
    }
}

/// <summary>5xx — the API failed. Retried automatically for idempotent requests.</summary>
public sealed class ServerException : MisarDevException
{
    public ServerException(int status, string message, string? code = null, JsonNode? body = null,
        string? rawBody = null, string? requestId = null)
        : base(status, message, code, body, rawBody, requestId) { }
}

/// <summary>The request never got an HTTP answer (DNS, TLS, reset, timeout). <c>Status</c> is 0.</summary>
public sealed class NetworkException : MisarDevException
{
    public NetworkException(string message, Exception? inner = null)
        : base(0, message, "network_error", inner: inner) { }
}

/// <summary>
/// The subscription behind the API key blocks this call.
/// </summary>
/// <remarks>
/// Detected by <c>code: "plan_limit_exceeded"</c> in the body — never by
/// status, because a spent quota is a 429 that would otherwise look like an
/// ordinary throttle. A locked feature answers 402 (<c>feature_locked</c>), a
/// spent allowance 429 (<c>quota_exhausted</c>). Retrying cannot help until the
/// plan changes or the period resets, so the transport never retries it.
/// </remarks>
public sealed class PlanLimitException : MisarDevException
{
    /// <summary>The full upgrade offer (every field the server sent). Render it; all copy comes from the server.</summary>
    public JsonObject? Offer { get; }

    /// <summary>Seconds until a quota resets (<c>Retry-After</c>), for <c>quota_exhausted</c> blocks.</summary>
    public int? RetryAfter { get; }

    public PlanLimitException(int status, string message, JsonNode? body = null, string? rawBody = null,
        string? requestId = null, JsonObject? offer = null, int? retryAfter = null)
        : base(status, message, "plan_limit_exceeded", body, rawBody, requestId)
    {
        Offer = offer;
        RetryAfter = retryAfter;
    }

    /// <summary>Where to send the user to unblock themselves: <c>offer.urls.billing</c>, else <c>offer.urls.pricing</c>.</summary>
    public string? UpgradeUrl => Str(At(At(Offer, "urls"), "billing")) ?? Str(At(At(Offer, "urls"), "pricing"));

    /// <summary>The machine key of the limit that was hit, e.g. <c>api_access</c>.</summary>
    public string? Feature => Str(At(Offer, "feature"));

    /// <summary>The account's current plan slug (<c>offer.current_plan.slug</c>).</summary>
    public string? CurrentPlan => Str(At(At(Offer, "current_plan"), "slug"));

    /// <summary>The plan the server recommends upgrading to (<c>offer.recommended_plan</c>).</summary>
    public string? RecommendedPlan => Str(At(Offer, "recommended_plan"));

    /// <summary>Why the call was refused: <c>feature_locked</c>, <c>quota_exhausted</c>, …</summary>
    public string? Reason => Str(At(Offer, "reason"));

    /// <summary>One-line, user-facing explanation from the server.</summary>
    public string? Headline => Str(At(Offer, "headline"));

    private static JsonNode? At(JsonNode? node, string key) =>
        node is JsonObject o && o.TryGetPropertyValue(key, out var v) ? v : null;

    private static string? Str(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
}
