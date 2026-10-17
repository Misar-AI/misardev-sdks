use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use futures::StreamExt;
use misardev::{paginate, MisarDev, MisarDevError, PaginateOptions, SseEvent};
use serde_json::{json, Value};
use wiremock::matchers::{any, body_partial_json, header, method, path, query_param};
use wiremock::{Mock, MockServer, Request, ResponseTemplate};

fn client(server: &MockServer) -> MisarDev {
    client_with(server, 3)
}

fn client_with(server: &MockServer, max_retries: u32) -> MisarDev {
    MisarDev::builder()
        .api_key("mdk_test_key")
        .base_url(format!("{}/dev", server.uri()))
        .max_retries(max_retries)
        .build()
        .expect("client")
}

fn plan_limit_body() -> Value {
    json!({
        "error": "API access requires the Pro plan or higher.",
        "code": "plan_limit_exceeded",
        "requiredPlan": "pro",
        "upgrade": {
            "product": "dev",
            "product_name": "Misar.Dev",
            "reason": "feature_locked",
            "feature": "api_access",
            "feature_label": "API access",
            "headline": "API access isn't included in your Starter plan.",
            "usage": null,
            "current_plan": { "slug": "starter", "name": "Starter" },
            "recommended_plan": "pro",
            "plans": [],
            "topup": null,
            "overage": null,
            "trial": null,
            "cross_sell": [],
            "urls": {
                "pricing": "https://www.misar.dev/pricing",
                "billing": "https://www.misar.dev/settings/billing",
                "docs": "https://docs.misar.io/dev/api",
                "compare": "https://www.misar.dev/pricing#compare"
            },
            "cta": "Upgrade to Pro to continue."
        }
    })
}

fn url_of(req: &Request) -> String {
    match req.url.query() {
        Some(q) => format!("{}?{}", req.url.path(), q),
        None => req.url.path().to_owned(),
    }
}

async fn ok_json(server: &MockServer, body: Value) {
    Mock::given(any())
        .respond_with(ResponseTemplate::new(200).set_body_json(body))
        .mount(server)
        .await;
}

fn sse(body: &str) -> ResponseTemplate {
    ResponseTemplate::new(200)
        .insert_header("content-type", "text/event-stream")
        .set_body_string(body.to_owned())
}

// ── Authentication ───────────────────────────────────────────────────────────

#[tokio::test]
async fn sends_bearer_and_sdk_headers() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/dev/projects"))
        .and(header("authorization", "Bearer mdk_test_key"))
        .and(header(
            "x-misar-sdk",
            format!("misardev-rust/{}", misardev::SDK_VERSION).as_str(),
        ))
        .and(header("accept", "application/json"))
        .and(header("content-type", "application/json"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "projects": [] })))
        .expect(1)
        .mount(&server)
        .await;

    let out = client(&server).projects().list(None).await.expect("list");
    assert_eq!(out, json!({ "projects": [] }));
}

/// Environment variables are process-global, so every env assertion lives in
/// this one test.
#[tokio::test]
async fn defaults_and_environment() {
    std::env::remove_var("MISARDEV_API_KEY");
    std::env::remove_var("MISARDEV_BASE_URL");

    let err = MisarDev::new("").unwrap_err();
    assert!(matches!(err, MisarDevError::MissingApiKey));
    assert!(err
        .to_string()
        .contains("https://www.misar.dev/settings/api-keys"));

    let dev = MisarDev::new("mdk_x").expect("client");
    assert_eq!(dev.base_url(), "https://api.misar.io/dev");

    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/env/usage/plan"))
        .and(header("authorization", "Bearer mdk_from_env"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "plan": "pro" })))
        .expect(1)
        .mount(&server)
        .await;
    std::env::set_var("MISARDEV_API_KEY", "mdk_from_env");
    std::env::set_var("MISARDEV_BASE_URL", format!("{}/env/", server.uri()));
    let dev = MisarDev::from_env().expect("client from env");
    std::env::remove_var("MISARDEV_API_KEY");
    std::env::remove_var("MISARDEV_BASE_URL");

    let out = dev.usage().plan().await.expect("plan");
    assert_eq!(out["plan"], "pro");
}

// ── Errors and retries ───────────────────────────────────────────────────────

#[tokio::test]
async fn plan_limit_402_carries_the_offer_and_is_not_retried() {
    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(
            ResponseTemplate::new(402)
                .insert_header("x-request-id", "req_1")
                .set_body_json(plan_limit_body()),
        )
        .expect(1)
        .mount(&server)
        .await;

    let err = client(&server).projects().list(None).await.unwrap_err();
    let plan = err.plan_limit().expect("PlanLimit");
    assert_eq!(err.status(), 402);
    assert_eq!(err.code(), Some("plan_limit_exceeded"));
    assert_eq!(err.request_id(), Some("req_1"));
    assert_eq!(err.message(), "API access requires the Pro plan or higher.");
    assert_eq!(
        plan.upgrade_url(),
        Some("https://www.misar.dev/settings/billing")
    );
    assert_eq!(plan.feature(), Some("api_access"));
    assert_eq!(plan.current_plan(), Some("starter"));
    assert_eq!(plan.recommended_plan(), Some("pro"));
    assert_eq!(
        plan.headline(),
        Some("API access isn't included in your Starter plan.")
    );
    assert_eq!(
        plan.offer,
        plan_limit_body()["upgrade"],
        "offer keeps every field"
    );
    assert_eq!(plan.retry_after, None);
}

#[tokio::test]
async fn quota_plan_limit_429_is_not_retried() {
    let server = MockServer::start().await;
    let mut body = plan_limit_body();
    body["upgrade"]["reason"] = json!("quota_exhausted");
    Mock::given(any())
        .respond_with(
            ResponseTemplate::new(429)
                .insert_header("retry-after", "3600")
                .set_body_json(body),
        )
        .expect(1)
        .mount(&server)
        .await;

    let err = client(&server).templates().list(None).await.unwrap_err();
    match &err {
        MisarDevError::PlanLimit(p) => {
            assert_eq!(p.retry_after, Some(3600));
            assert_eq!(p.reason(), Some("quota_exhausted"));
            assert_eq!(p.error.status, 429);
        }
        other => panic!("expected PlanLimit, got {other:?}"),
    }
}

#[tokio::test]
async fn ordinary_429_is_retried_for_any_verb() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(
            ResponseTemplate::new(429)
                .insert_header("retry-after", "0")
                .set_body_json(json!({ "error": "slow down" })),
        )
        .up_to_n_times(1)
        .with_priority(1)
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "ok": 1 })))
        .with_priority(2)
        .mount(&server)
        .await;

    let out = client(&server)
        .projects()
        .create(Some(json!({ "name": "x" })))
        .await
        .expect("create");
    assert_eq!(out, json!({ "ok": 1 }));
    assert_eq!(server.received_requests().await.unwrap().len(), 2);
}

#[tokio::test]
async fn persistent_429_raises_rate_limit() {
    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(
            ResponseTemplate::new(429)
                .insert_header("retry-after", "0")
                .set_body_json(json!({ "error": "slow down" })),
        )
        .expect(2)
        .mount(&server)
        .await;

    let err = client_with(&server, 2)
        .projects()
        .list(None)
        .await
        .unwrap_err();
    match &err {
        MisarDevError::RateLimit(r) => {
            assert_eq!(r.retry_after, Some(0));
            assert_eq!(r.error.message, "slow down");
        }
        other => panic!("expected RateLimit, got {other:?}"),
    }
    assert!(err.is_retryable());
}

#[tokio::test]
async fn retries_503_on_get_but_not_on_post() {
    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(ResponseTemplate::new(503).set_body_json(json!({ "error": "down" })))
        .up_to_n_times(1)
        .with_priority(1)
        .mount(&server)
        .await;
    ok_json(&server, json!({ "ok": true })).await;
    client(&server)
        .projects()
        .list(None)
        .await
        .expect("GET retried");
    assert_eq!(server.received_requests().await.unwrap().len(), 2);

    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(ResponseTemplate::new(503).set_body_json(json!({ "error": "down" })))
        .up_to_n_times(1)
        .with_priority(1)
        .mount(&server)
        .await;
    ok_json(&server, json!({ "ok": true })).await;
    let err = client(&server)
        .projects()
        .create(Some(json!({})))
        .await
        .unwrap_err();
    assert!(
        matches!(err, MisarDevError::Server(ref e) if e.status == 503),
        "{err:?}"
    );
    assert_eq!(server.received_requests().await.unwrap().len(), 1);
}

#[tokio::test]
async fn maps_statuses_to_typed_errors() {
    async fn fail(status: u16, body: Value) -> MisarDevError {
        let server = MockServer::start().await;
        Mock::given(any())
            .respond_with(ResponseTemplate::new(status).set_body_json(body))
            .mount(&server)
            .await;
        client(&server).projects().get("p1").await.unwrap_err()
    }
    assert!(matches!(
        fail(401, json!({"error": "Unauthorized"})).await,
        MisarDevError::Authentication(_)
    ));
    assert!(matches!(
        fail(403, json!({"error": "no"})).await,
        MisarDevError::PermissionDenied(_)
    ));
    assert!(matches!(
        fail(404, json!({"error": "nope"})).await,
        MisarDevError::NotFound(_)
    ));
    assert!(
        matches!(fail(409, json!({"message": "busy"})).await, MisarDevError::Conflict(ref e) if e.message == "busy")
    );
    assert!(matches!(
        fail(422, json!({"error": "bad"})).await,
        MisarDevError::Validation(_)
    ));

    // The OpenAI-shaped error /v1/* answers with.
    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(ResponseTemplate::new(400).set_body_json(json!({
            "error": { "message": "bad model", "type": "invalid_request_error", "code": "bad_model" }
        })))
        .mount(&server)
        .await;
    let err = client(&server)
        .chat()
        .completions(Some(json!({})))
        .await
        .unwrap_err();
    assert!(matches!(err, MisarDevError::Validation(_)));
    assert_eq!(err.message(), "bad model");
    assert_eq!(err.code(), Some("bad_model"));

    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(ResponseTemplate::new(418).set_body_string("teapot"))
        .mount(&server)
        .await;
    let err = client(&server).projects().list(None).await.unwrap_err();
    assert!(matches!(err, MisarDevError::Api(_)));
    assert_eq!(err.status(), 418);
    assert_eq!(err.message(), "teapot");
}

#[tokio::test]
async fn network_errors_are_retried_for_idempotent_calls_only() {
    // A listener that accepts each connection and hangs up without answering.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let accepted = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&accepted);
    tokio::spawn(async move {
        while let Ok((socket, _)) = listener.accept().await {
            counter.fetch_add(1, Ordering::SeqCst);
            drop(socket);
        }
    });
    let dev = MisarDev::builder()
        .api_key("mdk_test_key")
        .base_url(format!("http://{addr}/dev"))
        .max_retries(2)
        .timeout(Duration::from_secs(5))
        .build()
        .unwrap();

    let err = dev.projects().list(None).await.unwrap_err();
    assert!(matches!(err, MisarDevError::Network { .. }), "{err:?}");
    assert_eq!(err.status(), 0);
    assert_eq!(err.code(), Some("network_error"));
    assert_eq!(accepted.load(Ordering::SeqCst), 2, "GET is retried");

    accepted.store(0, Ordering::SeqCst);
    let err = dev.projects().create(Some(json!({}))).await.unwrap_err();
    assert!(matches!(err, MisarDevError::Network { .. }), "{err:?}");
    assert_eq!(accepted.load(Ordering::SeqCst), 1, "POST is not retried");
}

// ── Requests ─────────────────────────────────────────────────────────────────

#[tokio::test]
async fn encodes_path_params_query_and_body() {
    let server = MockServer::start().await;
    ok_json(&server, json!({})).await;
    let dev = client(&server);

    dev.projects()
        .check_subdomain("a b/c", "my-app")
        .await
        .unwrap();
    dev.templates()
        .list(Some(
            json!({ "limit": 5, "featured": true, "category": null }),
        ))
        .await
        .unwrap();
    dev.projects()
        .update("p1", Some(json!({ "name": "New" })))
        .await
        .unwrap();
    dev.domains().lookup("example.com").await.unwrap();

    let reqs = server.received_requests().await.unwrap();
    assert_eq!(
        url_of(&reqs[0]),
        "/dev/projects/a%20b%2Fc/subdomain/check?value=my-app"
    );
    assert_eq!(url_of(&reqs[1]), "/dev/templates?featured=true&limit=5");
    assert_eq!(reqs[2].method.as_str(), "PATCH");
    assert_eq!(
        serde_json::from_slice::<Value>(&reqs[2].body).unwrap(),
        json!({ "name": "New" })
    );
    assert_eq!(url_of(&reqs[3]), "/dev/domains/lookup?domain=example.com");
}

#[tokio::test]
async fn decodes_success_bodies() {
    let server = MockServer::start().await;
    Mock::given(method("DELETE"))
        .respond_with(ResponseTemplate::new(204))
        .mount(&server)
        .await;
    Mock::given(path("/dev/builds"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([1, 2])))
        .mount(&server)
        .await;
    Mock::given(path("/dev/audit"))
        .respond_with(ResponseTemplate::new(200).set_body_string("plain text"))
        .mount(&server)
        .await;
    let dev = client(&server);
    assert_eq!(dev.projects().delete("p1").await.unwrap(), Value::Null);
    assert_eq!(dev.builds().list(None).await.unwrap(), json!([1, 2]));
    assert_eq!(dev.audit().list().await.unwrap(), json!("plain text"));
}

#[tokio::test]
async fn raw_request_escape_hatch() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/dev/usage"))
        .and(query_param("days", "7"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "hi": 1 })))
        .expect(1)
        .mount(&server)
        .await;
    let out = client(&server)
        .request(
            reqwest::Method::GET,
            "/usage",
            Some(json!({ "days": 7 })),
            None,
        )
        .await
        .unwrap();
    assert_eq!(out, json!({ "hi": 1 }));
}

// ── Streaming ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn completions_stream_stops_at_done_and_forces_stream_true() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/dev/v1/chat/completions"))
        .and(header("accept", "text/event-stream"))
        .and(body_partial_json(
            json!({ "stream": true, "model": "misar-online" }),
        ))
        .respond_with(sse(concat!(
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            ": keep-alive\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\r\n\r\n",
            "data: [DONE]\n\n",
            "data: {\"never\":\"seen\"}\n\n",
        )))
        .expect(1)
        .mount(&server)
        .await;

    let mut stream = client(&server)
        .chat()
        .completions_stream(Some(json!({
            "model": "misar-online",
            "messages": [{ "role": "user", "content": "hi" }]
        })))
        .await
        .expect("open stream");
    let mut text = String::new();
    while let Some(ev) = stream.next().await {
        let ev = ev.expect("event");
        text.push_str(ev.data["choices"][0]["delta"]["content"].as_str().unwrap());
    }
    assert_eq!(text, "Hello");
}

#[tokio::test]
async fn stream_named_events_multiline_and_trailing_frame() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/dev/projects/p1/build-stream"))
        .respond_with(sse(
            "event: step\nid: 1\ndata: line1\ndata: line2\n\ndata: {\"done\":true}",
        ))
        .mount(&server)
        .await;

    let events: Vec<SseEvent> = client(&server)
        .projects()
        .build_stream("p1")
        .await
        .unwrap()
        .map(|e| e.expect("event"))
        .collect()
        .await;
    assert_eq!(
        events,
        vec![
            SseEvent {
                event: Some("step".into()),
                id: Some("1".into()),
                data: json!("line1\nline2")
            },
            SseEvent {
                event: None,
                id: None,
                data: json!({ "done": true })
            },
        ]
    );
}

#[tokio::test]
async fn stream_plan_limit_frame_and_http_error() {
    let server = MockServer::start().await;
    let mut frame = plan_limit_body();
    frame["type"] = json!("error");
    Mock::given(method("POST"))
        .and(path("/dev/chat"))
        .respond_with(sse(&format!("data: {frame}\n\ndata: {{\"after\":1}}\n\n")))
        .mount(&server)
        .await;
    let mut stream = client(&server)
        .chat()
        .studio_stream(Some(json!({ "message": "hi" })))
        .await
        .unwrap();
    let first = stream.next().await.expect("an item");
    let err = first.expect_err("plan-limit frame raises");
    assert_eq!(
        err.plan_limit().and_then(|p| p.recommended_plan()),
        Some("pro")
    );
    assert!(
        stream.next().await.is_none(),
        "stream ends after a plan refusal"
    );

    let server = MockServer::start().await;
    Mock::given(any())
        .respond_with(ResponseTemplate::new(402).set_body_json(plan_limit_body()))
        .expect(1)
        .mount(&server)
        .await;
    let err = client(&server)
        .projects()
        .build_stream("p1")
        .await
        .err()
        .expect("error before streaming");
    assert!(matches!(err, MisarDevError::PlanLimit(_)));
}

// ── Pagination ───────────────────────────────────────────────────────────────

#[tokio::test]
async fn paginate_walks_pages_until_a_short_one() {
    let pages = [
        json!({ "items": [1, 2] }),
        json!({ "items": [3, 4] }),
        json!({ "items": [5] }),
    ];
    let mut n = 0;
    let items: Vec<Value> = paginate(
        |_offset, _limit| {
            let page = pages[n].clone();
            n += 1;
            async move { Ok(page) }
        },
        PaginateOptions {
            page_size: 2,
            max_items: None,
        },
    )
    .map(|r| r.unwrap())
    .collect()
    .await;
    assert_eq!(
        items,
        vec![json!(1), json!(2), json!(3), json!(4), json!(5)]
    );
}

#[tokio::test]
async fn paginate_through_the_client_respects_max_items() {
    let server = MockServer::start().await;
    Mock::given(query_param("offset", "0"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "templates": [{ "id": 1 }, { "id": 2 }] })),
        )
        .mount(&server)
        .await;
    Mock::given(query_param("offset", "2"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "templates": [{ "id": 3 }, { "id": 4 }] })),
        )
        .mount(&server)
        .await;
    let dev = client(&server);
    let ids: Vec<Value> = paginate(
        |offset, limit| {
            dev.templates()
                .list(Some(json!({ "offset": offset, "limit": limit })))
        },
        PaginateOptions {
            page_size: 2,
            max_items: Some(3),
        },
    )
    .map(|r| r.unwrap()["id"].clone())
    .collect()
    .await;
    assert_eq!(ids, vec![json!(1), json!(2), json!(3)]);
    let urls: Vec<String> = server
        .received_requests()
        .await
        .unwrap()
        .iter()
        .map(url_of)
        .collect();
    assert_eq!(urls.len(), 2, "{urls:?}");
}

// ── Manifest parity ──────────────────────────────────────────────────────────

#[test]
fn generated_layer_matches_the_manifest() {
    let Ok(raw) = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../manifest.json"))
    else {
        eprintln!("sdks/manifest.json not present; the generated table is the source of truth");
        return;
    };
    let manifest: Value = serde_json::from_str(&raw).unwrap();
    let methods: usize = manifest["resources"]
        .as_object()
        .unwrap()
        .values()
        .map(|r| r["methods"].as_array().unwrap().len())
        .sum();
    let streams = manifest["streams"]["sse"].as_array().unwrap().len();
    assert_eq!(methods + streams, misardev::OPERATION_COUNT);
}
