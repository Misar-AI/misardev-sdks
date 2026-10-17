//! Async Rust client for the [Misar.Dev](https://www.misar.dev) API.
//!
//! Create projects, write their files, build and deploy them, start from
//! templates, run OpenAI-compatible chat completions, search code, and read
//! usage and plan allowances — every route in the API, generated from its own
//! route tree.
//!
//! ```no_run
//! use misardev::MisarDev;
//! use serde_json::json;
//!
//! # async fn run() -> Result<(), misardev::MisarDevError> {
//! let dev = MisarDev::new("mdk_your_key")?;
//! let created = dev.projects().create(Some(json!({ "name": "Coffee shop site" }))).await?;
//! println!("{}", created["project"]["id"]);
//! # Ok(()) }
//! ```
//!
//! Calls authenticate with an account API key (`mdk_…`) sent as
//! `Authorization: Bearer`. Throttles are retried honouring `Retry-After`; a
//! plan refusal is [`MisarDevError::PlanLimit`], carrying the server's upgrade
//! offer, and is never retried. Three endpoints stream Server-Sent Events as an
//! [`EventStream`].

#![forbid(unsafe_code)]

mod error;
#[rustfmt::skip]
pub mod generated;
mod pagination;
mod sse;
mod transport;

use std::sync::Arc;
use std::time::Duration;

use reqwest::header::HeaderMap;
use reqwest::Method;
use serde_json::Value;

pub use error::{ApiError, MisarDevError, PlanLimitError, RateLimitError};
pub use generated::*;
pub use pagination::{items_of, paginate, PaginateOptions};
pub use sse::{parse_frame, EventStream, RawFrame, SseEvent};
pub use transport::{
    backoff, build_query, encode_path, Query, Transport, DEFAULT_BASE_URL, SDK_VERSION,
};

/// The Misar.Dev API client. Cheap to clone; clones share one connection pool.
///
/// Every resource is an accessor: `dev.projects()`, `dev.templates()`,
/// `dev.chat()`, `dev.usage()`, …
#[derive(Debug, Clone)]
pub struct MisarDev {
    pub(crate) transport: Arc<Transport>,
}

impl MisarDev {
    /// Build a client with default options. An empty key falls back to the
    /// `MISARDEV_API_KEY` environment variable.
    pub fn new(api_key: impl Into<String>) -> Result<Self, MisarDevError> {
        Self::builder().api_key(api_key).build()
    }

    /// Build a client from `MISARDEV_API_KEY` (and `MISARDEV_BASE_URL`, when set).
    pub fn from_env() -> Result<Self, MisarDevError> {
        Self::builder().build()
    }

    /// Configure a client.
    pub fn builder() -> MisarDevBuilder {
        MisarDevBuilder::default()
    }

    /// The base every request path is appended to.
    pub fn base_url(&self) -> &str {
        &self.transport.base_url
    }

    /// The configured transport, for calling a route by hand.
    pub fn transport(&self) -> &Transport {
        &self.transport
    }

    /// Call any route by hand: `path` is relative to the base URL and `query`
    /// an optional JSON object (nulls dropped). Same retries and errors as the
    /// generated methods.
    pub async fn request(
        &self,
        method: Method,
        path: &str,
        query: Option<Value>,
        body: Option<Value>,
    ) -> Result<Value, MisarDevError> {
        let q = build_query(query.as_ref(), &[]);
        self.transport.request(method, path, &q, body).await
    }

    /// Open any Server-Sent Events route by hand. `terminator` is the data
    /// payload that ends the stream (`Some("[DONE]")` for chat completions).
    pub async fn stream(
        &self,
        method: Method,
        path: &str,
        query: Option<Value>,
        body: Option<Value>,
        terminator: Option<&str>,
    ) -> Result<EventStream, MisarDevError> {
        let q = build_query(query.as_ref(), &[]);
        self.transport
            .stream(method, path, &q, body, terminator)
            .await
    }
}

/// Builder for [`MisarDev`].
#[derive(Debug, Default)]
pub struct MisarDevBuilder {
    api_key: Option<String>,
    base_url: Option<String>,
    max_retries: Option<u32>,
    timeout: Option<Duration>,
    headers: Vec<(String, String)>,
    http: Option<reqwest::Client>,
}

impl MisarDevBuilder {
    /// The account API key (`mdk_…`). Empty or unset falls back to
    /// `MISARDEV_API_KEY`.
    pub fn api_key(mut self, key: impl Into<String>) -> Self {
        self.api_key = Some(key.into());
        self
    }

    /// Override the base URL. Default `https://api.misar.io/dev`, or
    /// `MISARDEV_BASE_URL` when set.
    pub fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = Some(url.into());
        self
    }

    /// Total attempts for a retryable failure. Default 3 (minimum 1).
    pub fn max_retries(mut self, n: u32) -> Self {
        self.max_retries = Some(n);
        self
    }

    /// Per-attempt timeout for ordinary requests. Default 60s. Streams are not
    /// bounded by it.
    pub fn timeout(mut self, d: Duration) -> Self {
        self.timeout = Some(d);
        self
    }

    /// A header sent with every request.
    pub fn header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }

    /// Inject the `reqwest::Client` used for every request (proxies, custom
    /// TLS, tests).
    pub fn http_client(mut self, client: reqwest::Client) -> Self {
        self.http = Some(client);
        self
    }

    /// Build the client. Fails with [`MisarDevError::MissingApiKey`] when no
    /// key was given and `MISARDEV_API_KEY` is empty.
    pub fn build(self) -> Result<MisarDev, MisarDevError> {
        let api_key = self
            .api_key
            .filter(|k| !k.is_empty())
            .or_else(|| {
                std::env::var("MISARDEV_API_KEY")
                    .ok()
                    .filter(|k| !k.is_empty())
            })
            .ok_or(MisarDevError::MissingApiKey)?;
        let base_url = self
            .base_url
            .filter(|u| !u.is_empty())
            .or_else(|| {
                std::env::var("MISARDEV_BASE_URL")
                    .ok()
                    .filter(|u| !u.is_empty())
            })
            .unwrap_or_else(|| DEFAULT_BASE_URL.to_owned())
            .trim_end_matches('/')
            .to_owned();
        let mut headers = HeaderMap::new();
        for (name, value) in &self.headers {
            let (n, v) = transport::header_pair(name, value)?;
            headers.insert(n, v);
        }
        let http = match self.http {
            Some(h) => h,
            None => reqwest::Client::builder()
                .build()
                .map_err(|e| MisarDevError::Config(e.to_string()))?,
        };
        Ok(MisarDev {
            transport: Arc::new(Transport {
                api_key,
                base_url,
                max_retries: self.max_retries.unwrap_or(3).max(1),
                timeout: self.timeout.unwrap_or(Duration::from_secs(60)),
                headers,
                http,
            }),
        })
    }
}
