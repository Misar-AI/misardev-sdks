//! HTTP transport shared by the generated resource layer.
//!
//! Everything the SDK does goes through here, and it authenticates exactly one
//! way: the account API key (`mdk_…`), sent as a bearer token. What a key may
//! do — and how much of it — is decided server-side from the subscription
//! behind that key; the SDK carries the key and surfaces the answer.

use std::time::{Duration, SystemTime};

use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::Method;
use serde_json::{Map, Value};

use crate::error::{error_for, MisarDevError};
use crate::sse::{events, EventStream};

/// Where the client sends requests unless told otherwise.
pub const DEFAULT_BASE_URL: &str = "https://api.misar.io/dev";
/// This SDK's release, sent in the `X-Misar-SDK` header.
pub const SDK_VERSION: &str = env!("CARGO_PKG_VERSION");

const MAX_BACKOFF: Duration = Duration::from_secs(60);

/// Optional query parameters: a JSON object whose `null` values are dropped.
pub type Query = Option<Value>;

/// Statuses worth retrying. A 429 for any verb; the 5xx ones only for verbs
/// that are safe to repeat.
fn retryable(status: u16) -> bool {
    matches!(status, 429 | 500 | 502 | 503 | 504)
}

/// A 5xx or a dropped connection on a POST may already have done its work —
/// started a build, charged an allowance — so only these verbs are retried on
/// those failures. A 429 is always safe: the server refused it before doing
/// anything.
fn idempotent(method: &Method) -> bool {
    matches!(
        *method,
        Method::GET | Method::HEAD | Method::OPTIONS | Method::PUT | Method::DELETE
    )
}

/// URL-encode one path segment: `a b/c` → `a%20b%2Fc`.
pub fn encode_path(segment: &str) -> String {
    urlencoding::encode(segment).into_owned()
}

fn query_value(v: &Value) -> Option<String> {
    match v {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Number(n) => Some(n.to_string()),
        other => Some(other.to_string()),
    }
}

/// Render a query string (with its leading `?`). Optional parameters come from
/// a JSON object (nulls dropped); required ones are layered on top.
pub fn build_query(optional: Option<&Value>, required: &[(&str, &str)]) -> String {
    let mut pairs: Vec<(String, String)> = Vec::new();
    if let Some(Value::Object(map)) = optional {
        for (k, v) in map {
            if required.iter().any(|(rk, _)| rk == k) {
                continue;
            }
            if let Some(s) = query_value(v) {
                pairs.push((k.clone(), s));
            }
        }
    }
    for (k, v) in required {
        pairs.push(((*k).to_owned(), (*v).to_owned()));
    }
    if pairs.is_empty() {
        return String::new();
    }
    let joined = pairs
        .iter()
        .map(|(k, v)| format!("{}={}", urlencoding::encode(k), urlencoding::encode(v)))
        .collect::<Vec<_>>()
        .join("&");
    format!("?{joined}")
}

/// Send `{}` for a method that takes a body when the caller passed `None`.
pub(crate) fn body_or_empty(body: Option<Value>) -> Value {
    body.unwrap_or_else(|| Value::Object(Map::new()))
}

/// Copy the body with `"stream": true` set, for chat completions.
pub(crate) fn with_stream(body: Option<Value>) -> Value {
    let mut v = body_or_empty(body);
    if let Value::Object(map) = &mut v {
        map.insert("stream".into(), Value::Bool(true));
    }
    v
}

fn jitter() -> f64 {
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    f64::from(nanos % 1000) / 1000.0
}

/// How long to wait before retry number `attempt + 1`: `Retry-After` when sent
/// (seconds or an HTTP date), otherwise `250ms * 2^attempt` plus a little
/// jitter. Both capped at 60s.
pub fn backoff(attempt: u32, retry_after: Option<&str>) -> Duration {
    if let Some(ra) = retry_after.map(str::trim).filter(|s| !s.is_empty()) {
        if let Ok(secs) = ra.parse::<f64>() {
            if secs >= 0.0 {
                return Duration::from_secs_f64(secs).min(MAX_BACKOFF);
            }
        }
        if let Ok(when) = httpdate::parse_http_date(ra) {
            return when
                .duration_since(SystemTime::now())
                .unwrap_or(Duration::ZERO)
                .min(MAX_BACKOFF);
        }
    }
    if attempt > 20 {
        return MAX_BACKOFF;
    }
    let base = 250.0 * f64::from(1u32 << attempt);
    Duration::from_secs_f64((base + jitter() * base * 0.25) / 1000.0).min(MAX_BACKOFF)
}

/// Decode a success body: `Null` when empty, JSON when it parses (objects and
/// arrays alike), otherwise the raw text.
fn decode(text: &str) -> Value {
    if text.trim().is_empty() {
        return Value::Null;
    }
    serde_json::from_str(text).unwrap_or_else(|_| Value::String(text.to_owned()))
}

/// The configured HTTP core every resource calls into.
#[derive(Debug, Clone)]
pub struct Transport {
    pub(crate) api_key: String,
    pub(crate) base_url: String,
    pub(crate) max_retries: u32,
    pub(crate) timeout: Duration,
    pub(crate) headers: HeaderMap,
    pub(crate) http: reqwest::Client,
}

impl Transport {
    fn builder(&self, method: Method, url: &str, accept: &'static str) -> reqwest::RequestBuilder {
        self.http
            .request(method, url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Accept", accept)
            .header("Content-Type", "application/json")
            .header("X-Misar-SDK", format!("misardev-rust/{SDK_VERSION}"))
            .headers(self.headers.clone())
    }

    /// Send one call and return the decoded JSON.
    ///
    /// Throttles (429) are retried for any verb; 500/502/503/504 and network
    /// errors only for GET, HEAD, OPTIONS, PUT and DELETE. A plan refusal is
    /// returned at once and never retried.
    pub async fn request(
        &self,
        method: Method,
        path: &str,
        query: &str,
        body: Option<Value>,
    ) -> Result<Value, MisarDevError> {
        let url = format!("{}{}{}", self.base_url, path, query);
        let mut attempt: u32 = 0;
        loop {
            let last = attempt + 1 >= self.max_retries;
            let mut req = self
                .builder(method.clone(), &url, "application/json")
                .timeout(self.timeout);
            if let Some(b) = &body {
                req = req
                    .body(serde_json::to_vec(b).map_err(|e| MisarDevError::Config(e.to_string()))?);
            }

            let resp = match req.send().await {
                Ok(r) => r,
                Err(e) => {
                    if !last && idempotent(&method) {
                        tokio::time::sleep(backoff(attempt, None)).await;
                        attempt += 1;
                        continue;
                    }
                    return Err(e.into());
                }
            };

            let status = resp.status();
            let headers = resp.headers().clone();
            let text = match resp.text().await {
                Ok(t) => t,
                Err(e) => {
                    if !last && idempotent(&method) {
                        tokio::time::sleep(backoff(attempt, None)).await;
                        attempt += 1;
                        continue;
                    }
                    return Err(e.into());
                }
            };

            if status.is_success() {
                if status.as_u16() == 204 {
                    return Ok(Value::Null);
                }
                return Ok(decode(&text));
            }

            // Read the body BEFORE deciding to retry: a 429 from the rate
            // limiter and a 429 from a spent plan allowance share a status, and
            // only the first is worth retrying.
            let err = error_for(
                status.as_u16(),
                &headers,
                decode(&text),
                status.canonical_reason().unwrap_or(""),
            );
            if matches!(err, MisarDevError::PlanLimit(_)) {
                return Err(err);
            }
            let code = status.as_u16();
            if retryable(code) && (code == 429 || idempotent(&method)) && !last {
                let ra = headers.get("retry-after").and_then(|v| v.to_str().ok());
                tokio::time::sleep(backoff(attempt, ra)).await;
                attempt += 1;
                continue;
            }
            return Err(err);
        }
    }

    /// Open a Server-Sent Events stream.
    ///
    /// Never retried: a stream that fails mid-flight cannot be replayed without
    /// duplicating what the caller already consumed. A non-2xx answer is the
    /// usual typed error; a `plan_limit_exceeded` frame ends the stream with
    /// [`MisarDevError::PlanLimit`].
    pub async fn stream(
        &self,
        method: Method,
        path: &str,
        query: &str,
        body: Option<Value>,
        terminator: Option<&str>,
    ) -> Result<EventStream, MisarDevError> {
        let url = format!("{}{}{}", self.base_url, path, query);
        let mut req = self.builder(method, &url, "text/event-stream");
        if let Some(b) = &body {
            req =
                req.body(serde_json::to_vec(b).map_err(|e| MisarDevError::Config(e.to_string()))?);
        }
        let resp = req.send().await?;
        let status = resp.status();
        let headers = resp.headers().clone();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            return Err(error_for(
                status.as_u16(),
                &headers,
                decode(&text),
                status.canonical_reason().unwrap_or(""),
            ));
        }
        Ok(events(
            resp.bytes_stream(),
            terminator.map(str::to_owned),
            headers,
        ))
    }
}

/// Parse a `(name, value)` header pair, for the client builder.
pub(crate) fn header_pair(
    name: &str,
    value: &str,
) -> Result<(HeaderName, HeaderValue), MisarDevError> {
    let n = HeaderName::from_bytes(name.as_bytes())
        .map_err(|e| MisarDevError::Config(e.to_string()))?;
    let v = HeaderValue::from_str(value).map_err(|e| MisarDevError::Config(e.to_string()))?;
    Ok((n, v))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn query_drops_nulls_and_lowercases_bools() {
        assert_eq!(build_query(None, &[]), "");
        assert_eq!(build_query(Some(&json!({"a": null})), &[]), "");
        assert_eq!(
            build_query(
                Some(&json!({"featured": true, "limit": 5, "q": "a b"})),
                &[("value", "x/y")]
            ),
            "?featured=true&limit=5&q=a%20b&value=x%2Fy"
        );
    }

    #[test]
    fn path_segments_are_encoded() {
        assert_eq!(encode_path("a b/c"), "a%20b%2Fc");
    }

    #[test]
    fn backoff_honours_retry_after_and_caps() {
        assert_eq!(backoff(0, Some("2")), Duration::from_secs(2));
        assert_eq!(backoff(0, Some("999")), MAX_BACKOFF);
        assert!(backoff(3, None) >= Duration::from_secs(2));
        assert!(backoff(3, None) <= Duration::from_millis(2500));
        assert_eq!(backoff(40, None), MAX_BACKOFF);
        let soon = httpdate::fmt_http_date(SystemTime::now() + Duration::from_secs(1));
        assert!(backoff(0, Some(&soon)) <= Duration::from_secs(1));
    }

    #[test]
    fn stream_body_forces_stream_true() {
        assert_eq!(with_stream(None), json!({"stream": true}));
        assert_eq!(
            with_stream(Some(json!({"model": "m"}))),
            json!({"model": "m", "stream": true})
        );
    }
}
