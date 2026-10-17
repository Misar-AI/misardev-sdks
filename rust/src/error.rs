//! Typed errors for the MisarDev API.
//!
//! Every non-2xx answer becomes a [`MisarDevError`]; its variants let a caller
//! branch on the kind of failure without parsing strings. The one that matters
//! most commercially is [`MisarDevError::PlanLimit`]: the key is valid, but the
//! subscription behind it does not cover the call. It carries the full upgrade
//! offer the server sent, so an app can render an upgrade card rather than a
//! bare failure.

use std::fmt;

use reqwest::header::HeaderMap;
use serde_json::Value;

/// What every API error carries.
#[derive(Debug, Clone, PartialEq)]
pub struct ApiError {
    /// HTTP status, or 0 when the request never got an answer.
    pub status: u16,
    /// The human-readable reason the API gave.
    pub message: String,
    /// Machine-readable error code from the body, when the API sends one.
    pub code: Option<String>,
    /// The decoded error body (JSON, or `Value::String` for a text body).
    pub body: Value,
    /// The `x-request-id` response header, for support requests.
    pub request_id: Option<String>,
}

/// A 429 that is an ordinary throttle (identical for every user), returned
/// once the client has already retried it `max_retries` times.
#[derive(Debug, Clone, PartialEq)]
pub struct RateLimitError {
    /// Status, message, code, body and request id.
    pub error: ApiError,
    /// Seconds the server asked us to wait, when it said.
    pub retry_after: Option<u64>,
}

/// The subscription behind the API key blocks this call.
///
/// Detected by `code: "plan_limit_exceeded"` in the body — never by status,
/// because a spent quota is a 429 that would otherwise look like an ordinary
/// throttle. Retrying cannot help until the plan changes or the period resets,
/// so the client never retries it.
#[derive(Debug, Clone, PartialEq)]
pub struct PlanLimitError {
    /// Status, message, code (`plan_limit_exceeded`), body and request id.
    pub error: ApiError,
    /// The full upgrade offer (the body's `upgrade` object), every field kept.
    /// Render it; all copy comes from the server.
    pub offer: Value,
    /// Seconds from the `Retry-After` header (quota_exhausted blocks).
    pub retry_after: Option<u64>,
}

impl PlanLimitError {
    fn s(&self, pointer: &str) -> Option<&str> {
        self.offer.pointer(pointer).and_then(Value::as_str)
    }

    /// Where to send the user to unblock themselves: the billing URL, falling
    /// back to the pricing URL.
    pub fn upgrade_url(&self) -> Option<&str> {
        self.s("/urls/billing").or_else(|| self.s("/urls/pricing"))
    }

    /// The machine key of the limit that was hit, e.g. `api_access`.
    pub fn feature(&self) -> Option<&str> {
        self.s("/feature")
    }

    /// `feature_locked`, `quota_exhausted`, or another offer reason.
    pub fn reason(&self) -> Option<&str> {
        self.s("/reason")
    }

    /// The server-written one-line explanation.
    pub fn headline(&self) -> Option<&str> {
        self.s("/headline")
    }

    /// Slug of the plan the key is on.
    pub fn current_plan(&self) -> Option<&str> {
        self.s("/current_plan/slug")
    }

    /// Slug of the plan that would unblock the call.
    pub fn recommended_plan(&self) -> Option<&str> {
        self.s("/recommended_plan")
    }

    /// The plan options in the offer.
    pub fn plans(&self) -> &[Value] {
        self.offer
            .get("plans")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }
}

/// Every error the SDK returns.
#[derive(Debug)]
pub enum MisarDevError {
    /// 400 / 422 — the request was malformed or failed validation.
    Validation(ApiError),
    /// 401 — the key is missing, revoked, expired, or not a MisarDev key.
    Authentication(ApiError),
    /// 403 — authenticated, but not allowed to touch this resource.
    PermissionDenied(ApiError),
    /// 404 — no such resource, or not one this key can see.
    NotFound(ApiError),
    /// 409 — conflicts with current state (e.g. a build already running).
    Conflict(ApiError),
    /// 429 that is an ordinary throttle, after the client already retried it.
    RateLimit(Box<RateLimitError>),
    /// 5xx — the API failed. Retried automatically for idempotent requests.
    Server(ApiError),
    /// The plan behind the key does not cover this call. Never retried.
    PlanLimit(Box<PlanLimitError>),
    /// Any other non-2xx status.
    Api(ApiError),
    /// The request never got an HTTP answer (DNS, TLS, reset, timeout). Status 0.
    Network {
        message: String,
        source: Option<reqwest::Error>,
    },
    /// No API key was passed and `MISARDEV_API_KEY` is unset.
    MissingApiKey,
    /// The client could not be configured (e.g. the HTTP client failed to build).
    Config(String),
}

impl MisarDevError {
    /// The shared fields, when this is an HTTP error.
    pub fn api_error(&self) -> Option<&ApiError> {
        match self {
            Self::Validation(e)
            | Self::Authentication(e)
            | Self::PermissionDenied(e)
            | Self::NotFound(e)
            | Self::Conflict(e)
            | Self::Server(e)
            | Self::Api(e) => Some(e),
            Self::RateLimit(r) => Some(&r.error),
            Self::PlanLimit(p) => Some(&p.error),
            _ => None,
        }
    }

    /// HTTP status, or 0 when there was no HTTP answer.
    pub fn status(&self) -> u16 {
        self.api_error().map(|e| e.status).unwrap_or(0)
    }

    /// Human-readable message.
    pub fn message(&self) -> String {
        match self {
            Self::Network { message, .. } => message.clone(),
            Self::MissingApiKey => MISSING_KEY.to_owned(),
            Self::Config(m) => m.clone(),
            other => other
                .api_error()
                .map(|e| e.message.clone())
                .unwrap_or_default(),
        }
    }

    /// Machine-readable code from the body, when sent.
    pub fn code(&self) -> Option<&str> {
        match self {
            Self::Network { .. } => Some("network_error"),
            Self::MissingApiKey => Some("missing_api_key"),
            other => other.api_error().and_then(|e| e.code.as_deref()),
        }
    }

    /// The decoded error body.
    pub fn body(&self) -> Option<&Value> {
        self.api_error().map(|e| &e.body)
    }

    /// The `x-request-id` header.
    pub fn request_id(&self) -> Option<&str> {
        self.api_error().and_then(|e| e.request_id.as_deref())
    }

    /// The throttle details, when this is an ordinary rate limit.
    pub fn rate_limit(&self) -> Option<&RateLimitError> {
        match self {
            Self::RateLimit(r) => Some(r),
            _ => None,
        }
    }

    /// The plan-limit details, when this is a plan refusal.
    pub fn plan_limit(&self) -> Option<&PlanLimitError> {
        match self {
            Self::PlanLimit(p) => Some(p),
            _ => None,
        }
    }

    /// Worth retrying as-is: a throttle or a transient server condition.
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::RateLimit(_) | Self::Server(_) | Self::Network { .. }
        )
    }
}

pub(crate) const MISSING_KEY: &str =
    "a MisarDev API key is required: pass it to the client or set \
MISARDEV_API_KEY. Create one at https://www.misar.dev/settings/api-keys";

impl fmt::Display for MisarDevError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let kind = match self {
            Self::Validation(_) => "validation error",
            Self::Authentication(_) => "authentication error",
            Self::PermissionDenied(_) => "permission denied",
            Self::NotFound(_) => "not found",
            Self::Conflict(_) => "conflict",
            Self::RateLimit(_) => "rate limited",
            Self::Server(_) => "server error",
            Self::PlanLimit(_) => "plan limit",
            Self::Api(_) => "API error",
            Self::Network { .. } => "network error",
            Self::MissingApiKey => "missing API key",
            Self::Config(_) => "configuration error",
        };
        match self.api_error() {
            Some(e) => write!(f, "misardev: {kind} ({}): {}", e.status, e.message),
            None => write!(f, "misardev: {kind}: {}", self.message()),
        }
    }
}

impl std::error::Error for MisarDevError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Network {
                source: Some(e), ..
            } => Some(e),
            _ => None,
        }
    }
}

impl From<reqwest::Error> for MisarDevError {
    fn from(e: reqwest::Error) -> Self {
        Self::Network {
            message: e.to_string(),
            source: Some(e),
        }
    }
}

// ── Mapping ──────────────────────────────────────────────────────────────────

/// True when a decoded body is the plan-limit refusal.
pub(crate) fn is_plan_limit_body(body: &Value) -> bool {
    body.get("code").and_then(Value::as_str) == Some("plan_limit_exceeded")
}

/// Pull a human message out of the API's several error shapes.
fn message_of(body: &Value, fallback: &str) -> String {
    if let Some(s) = body.get("error").and_then(Value::as_str) {
        return s.to_owned();
    }
    // /v1/* answers in the OpenAI shape: {"error": {"message", "type", "code"}}
    if let Some(s) = body.pointer("/error/message").and_then(Value::as_str) {
        return s.to_owned();
    }
    if let Some(s) = body.get("message").and_then(Value::as_str) {
        return s.to_owned();
    }
    if let Value::String(s) = body {
        let t = s.trim();
        if !t.is_empty() {
            return t.chars().take(500).collect();
        }
    }
    fallback.to_owned()
}

fn code_of(body: &Value) -> Option<String> {
    body.get("code")
        .and_then(Value::as_str)
        .or_else(|| body.pointer("/error/code").and_then(Value::as_str))
        .map(str::to_owned)
}

/// Retry-After in whole seconds, when given as a number.
pub(crate) fn retry_after_seconds(headers: &HeaderMap) -> Option<u64> {
    headers
        .get("retry-after")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<u64>().ok())
}

/// Map an error response to the right typed error. Plan limits first, by code.
pub(crate) fn error_for(
    status: u16,
    headers: &HeaderMap,
    body: Value,
    reason: &str,
) -> MisarDevError {
    let fallback = if reason.is_empty() {
        format!("HTTP {status}")
    } else {
        reason.to_owned()
    };
    let error = ApiError {
        status,
        message: message_of(&body, &fallback),
        code: code_of(&body),
        request_id: headers
            .get("x-request-id")
            .and_then(|v| v.to_str().ok())
            .map(str::to_owned),
        body,
    };
    if is_plan_limit_body(&error.body) {
        let offer = error.body.get("upgrade").cloned().unwrap_or(Value::Null);
        return MisarDevError::PlanLimit(Box::new(PlanLimitError {
            error,
            offer,
            retry_after: retry_after_seconds(headers),
        }));
    }
    match status {
        400 | 422 => MisarDevError::Validation(error),
        401 => MisarDevError::Authentication(error),
        403 => MisarDevError::PermissionDenied(error),
        404 => MisarDevError::NotFound(error),
        409 => MisarDevError::Conflict(error),
        429 => MisarDevError::RateLimit(Box::new(RateLimitError {
            error,
            retry_after: retry_after_seconds(headers),
        })),
        s if s >= 500 => MisarDevError::Server(error),
        _ => MisarDevError::Api(error),
    }
}
