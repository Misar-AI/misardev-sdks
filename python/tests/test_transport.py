"""Core behaviour: auth, retries, typed errors, query/path encoding, SSE, pagination."""

from __future__ import annotations

import email.utils
import time

import httpx
import pytest

from misardev import (
    DEFAULT_BASE_URL,
    AuthenticationError,
    ConflictError,
    MisarDev,
    MisarDevError,
    NetworkError,
    NotFoundError,
    PermissionDeniedError,
    PlanLimitError,
    RateLimitError,
    ServerError,
    SSEEvent,
    ValidationError,
    __version__,
    apaginate,
    paginate,
)
from misardev.core.sse import iter_sse
from misardev.core.transport import backoff_seconds, build_query, encode_path

from .conftest import (
    BASE,
    PLAN_LIMIT_BODY,
    empty_response,
    json_response,
    sse_response,
    text_response,
)


def quota_body():
    return {**PLAN_LIMIT_BODY, "upgrade": {**PLAN_LIMIT_BODY["upgrade"], "reason": "quota_exhausted"}}


# ── Authentication and configuration ────────────────────────────────────────


def test_sends_bearer_key_and_sdk_header(make_client):
    dev, calls = make_client(json_response({"projects": []}))
    assert dev.projects.list() == {"projects": []}
    assert calls[0].headers["authorization"] == "Bearer mdk_test_key"
    assert calls[0].headers["x-misar-sdk"] == f"misardev-python/{__version__}"
    assert calls[0].headers["accept"] == "application/json"
    assert calls[0].headers["content-type"] == "application/json"
    assert calls[0].url == f"{BASE}/projects"


def test_missing_key_raises(monkeypatch):
    monkeypatch.delenv("MISARDEV_API_KEY", raising=False)
    with pytest.raises(MisarDevError, match="API key is required") as info:
        MisarDev()
    assert "https://www.misar.dev/settings/api-keys" in str(info.value)
    with pytest.raises(MisarDevError):
        MisarDev("")


def test_env_key_and_default_base_url(monkeypatch):
    monkeypatch.setenv("MISARDEV_API_KEY", "mdk_from_env")
    monkeypatch.delenv("MISARDEV_BASE_URL", raising=False)
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={})

    dev = MisarDev(transport=httpx.MockTransport(handler))
    dev.usage.plan()
    assert seen[0].headers["authorization"] == "Bearer mdk_from_env"
    assert dev.base_url == DEFAULT_BASE_URL == "https://api.misar.io/dev"
    assert str(seen[0].url) == "https://api.misar.io/dev/usage/plan"
    assert "mdk_from_env" not in repr(dev)


def test_env_base_url(monkeypatch):
    monkeypatch.setenv("MISARDEV_BASE_URL", "https://example.test/dev/")
    dev = MisarDev("mdk_x", transport=httpx.MockTransport(lambda r: httpx.Response(200)))
    assert dev.base_url == "https://example.test/dev"


def test_injected_http_client_and_extra_headers():
    seen = []
    http = httpx.Client(transport=httpx.MockTransport(lambda r: seen.append(r) or httpx.Response(200, json=[1, 2])))
    dev = MisarDev("mdk_x", base_url=BASE, http_client=http, headers={"X-Extra": "1"})
    assert dev.builds.list(headers={"X-Call": "2"}) == [1, 2]
    assert seen[0].headers["x-extra"] == "1"
    assert seen[0].headers["x-call"] == "2"
    dev.close()
    assert not http.is_closed  # caller-owned clients are left alone


# ── Plan limits ─────────────────────────────────────────────────────────────


def test_plan_limit_402_carries_full_offer_and_is_not_retried(make_client):
    dev, calls = make_client(json_response(PLAN_LIMIT_BODY, 402, {"x-request-id": "req_1"}))
    with pytest.raises(PlanLimitError) as info:
        dev.projects.list()
    err = info.value
    assert err.status == 402
    assert err.code == "plan_limit_exceeded"
    assert str(err) == "API access requires the Pro plan or higher."
    assert err.offer == PLAN_LIMIT_BODY["upgrade"]  # every field kept
    assert err.offer["headline"] == "API access isn't included in your Starter plan."
    assert err.offer["cta"] == "Upgrade to Pro to continue."
    assert err.upgrade_url == "https://www.misar.dev/settings/billing"
    assert err.feature == "api_access"
    assert err.current_plan == "starter"
    assert err.recommended_plan == "pro"
    assert err.request_id == "req_1"
    assert err.body["requiredPlan"] == "pro"
    assert len(calls) == 1


def test_upgrade_url_falls_back_to_pricing(make_client):
    body = {**PLAN_LIMIT_BODY, "upgrade": {**PLAN_LIMIT_BODY["upgrade"], "urls": {"pricing": "https://p"}}}
    dev, _ = make_client(json_response(body, 402))
    with pytest.raises(PlanLimitError) as info:
        dev.projects.list()
    assert info.value.upgrade_url == "https://p"


def test_plan_limit_429_quota_is_never_retried(make_client, instant_backoff):
    dev, calls = make_client(json_response(quota_body(), 429, {"retry-after": "3600"}))
    with pytest.raises(PlanLimitError) as info:
        dev.templates.list()
    assert info.value.status == 429
    assert info.value.retry_after == 3600
    assert info.value.offer["reason"] == "quota_exhausted"
    assert not isinstance(info.value, RateLimitError)
    assert len(calls) == 1
    assert instant_backoff == []


# ── Retries ─────────────────────────────────────────────────────────────────


def test_ordinary_429_is_retried_then_succeeds_even_on_post(make_client, instant_backoff):
    dev, calls = make_client(
        json_response({"error": "slow down"}, 429, {"retry-after": "0"}),
        json_response({"ok": 1}),
    )
    assert dev.projects.create({"name": "x"}) == {"ok": 1}
    assert len(calls) == 2
    assert instant_backoff == [0]


def test_persistent_429_raises_rate_limit_error(make_client):
    dev, calls = make_client(json_response({"error": "slow down"}, 429, {"retry-after": "0"}), max_retries=2)
    with pytest.raises(RateLimitError) as info:
        dev.projects.list()
    assert info.value.retry_after == 0
    assert info.value.message == "slow down"
    assert len(calls) == 2


def test_503_retried_on_get(make_client):
    dev, calls = make_client(json_response({"error": "down"}, 503), json_response({"ok": True}))
    assert dev.projects.list() == {"ok": True}
    assert len(calls) == 2


def test_503_not_retried_on_post(make_client):
    dev, calls = make_client(json_response({"error": "down"}, 503), json_response({"ok": True}))
    with pytest.raises(ServerError):
        dev.projects.create({})
    assert len(calls) == 1


def test_network_errors_retried_for_idempotent_then_raise(make_client):
    dev, calls = make_client(httpx.ConnectError("connection refused"), max_retries=2)
    with pytest.raises(NetworkError) as info:
        dev.projects.list()
    assert info.value.status == 0
    assert isinstance(info.value.cause, httpx.ConnectError)
    assert len(calls) == 2


def test_network_errors_not_retried_for_post(make_client):
    dev, calls = make_client(httpx.ConnectError("connection refused"))
    with pytest.raises(NetworkError):
        dev.projects.create({})
    assert len(calls) == 1


def test_backoff_honours_retry_after_and_caps():
    assert backoff_seconds(0, "2") == 2
    assert backoff_seconds(0, "999") == 60
    assert 2 <= backoff_seconds(3) <= 2.5
    assert backoff_seconds(20) == 60
    future = email.utils.formatdate(time.time() + 1, usegmt=True)
    assert 0 <= backoff_seconds(0, future) <= 1.5


# ── Error mapping ───────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "status,cls",
    [
        (400, ValidationError),
        (422, ValidationError),
        (401, AuthenticationError),
        (403, PermissionDeniedError),
        (404, NotFoundError),
        (409, ConflictError),
        (500, ServerError),
    ],
)
def test_status_maps_to_typed_error(make_client, status, cls):
    dev, _ = make_client(json_response({"error": "nope", "code": "x_code"}, status))
    with pytest.raises(cls) as info:
        dev.projects.delete("p1")
    assert info.value.status == status
    assert info.value.message == "nope"
    assert info.value.code == "x_code"
    assert isinstance(info.value, MisarDevError)


def test_401_and_404(make_client):
    dev, _ = make_client(json_response({"error": "Unauthorized"}, 401))
    with pytest.raises(AuthenticationError):
        dev.projects.list()
    dev, _ = make_client(json_response({"error": "nope"}, 404))
    with pytest.raises(NotFoundError):
        dev.projects.get("p1")


def test_openai_error_shape(make_client):
    body = {"error": {"message": "bad model", "type": "invalid_request_error", "code": "bad_model"}}
    dev, _ = make_client(json_response(body, 400))
    with pytest.raises(ValidationError) as info:
        dev.chat.completions({})
    assert info.value.message == "bad model"
    assert info.value.code == "bad_model"


def test_message_fallbacks(make_client):
    dev, _ = make_client(text_response("teapot", 418))
    with pytest.raises(MisarDevError) as info:
        dev.projects.list()
    assert type(info.value) is MisarDevError
    assert info.value.message == "teapot"

    dev, _ = make_client(json_response({"message": "from message"}, 418))
    with pytest.raises(MisarDevError, match="from message"):
        dev.projects.list()

    dev, _ = make_client(empty_response(418))
    with pytest.raises(MisarDevError) as info:
        dev.projects.list()
    assert info.value.message  # the HTTP reason phrase


# ── Request building and decoding ───────────────────────────────────────────


def test_path_encoding_required_and_optional_query_and_body(make_client):
    dev, calls = make_client(json_response({}))
    dev.projects.check_subdomain("a b/c", "my-app")
    assert calls[0].url == f"{BASE}/projects/a%20b%2Fc/subdomain/check?value=my-app"

    dev.templates.list({"limit": 5, "featured": True, "category": None})
    assert calls[1].url == f"{BASE}/templates?limit=5&featured=true"

    dev.projects.update("p1", {"name": "New"})
    assert calls[2].method == "PATCH"
    assert calls[2].body == {"name": "New"}

    dev.rag.search("proj 1", {"query": "auth flow", "stats": False})
    assert calls[3].url == f"{BASE}/rag?query=auth%20flow&stats=false&projectId=proj%201"


def test_helpers():
    assert encode_path("a b/c") == "a%20b%2Fc"
    assert build_query(None) == ""
    assert build_query({"a": None}) == ""
    assert build_query({"b": False, "n": 3}) == "?b=false&n=3"


def test_decoding(make_client):
    dev, _ = make_client(empty_response(204))
    assert dev.projects.delete("p1") is None
    dev, _ = make_client(json_response([{"id": 1}]))
    assert dev.builds.list() == [{"id": 1}]
    dev, _ = make_client(text_response("plain text"))
    assert dev.projects.export("p1") == "plain text"


def test_raw_request_escape_hatch(make_client):
    dev, calls = make_client(json_response({"hi": 1}))
    assert dev.request("GET", "/usage", query={"days": 7}) == {"hi": 1}
    assert calls[0].url == f"{BASE}/usage?days=7"


# ── Async ───────────────────────────────────────────────────────────────────


async def test_async_twin_shares_semantics(make_client):
    dev, calls = make_client(json_response({"error": "down"}, 503), json_response({"projects": []}))
    assert await dev.projects.alist() == {"projects": []}
    assert len(calls) == 2
    assert calls[0].headers["authorization"] == "Bearer mdk_test_key"
    await dev.aclose()


async def test_async_plan_limit_not_retried(make_client):
    dev, calls = make_client(json_response(quota_body(), 429, {"retry-after": "3600"}))
    with pytest.raises(PlanLimitError) as info:
        await dev.templates.alist()
    assert info.value.retry_after == 3600
    assert len(calls) == 1


async def test_async_503_not_retried_on_post(make_client):
    dev, calls = make_client(json_response({"error": "down"}, 503))
    with pytest.raises(ServerError):
        await dev.projects.acreate({})
    assert len(calls) == 1


async def test_injected_async_client():
    seen = []
    http = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: seen.append(r) or httpx.Response(200, json={})))
    dev = MisarDev("mdk_x", base_url=BASE, async_http_client=http)
    await dev.usage.aplan()
    assert str(seen[0].url) == f"{BASE}/usage/plan"
    await http.aclose()


# ── Streaming ───────────────────────────────────────────────────────────────

CHAT_FRAMES = [
    'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
    ": keep-alive\n\n",
    'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
    "data: [DONE]\n\n",
    'data: {"never":"seen"}\n\n',
]


def test_chat_completions_stream_until_done(make_client):
    dev, calls = make_client(sse_response(CHAT_FRAMES))
    chunks = [
        ev.data["choices"][0]["delta"]["content"]
        for ev in dev.chat.completions_stream({"model": "misar-online", "messages": [{"role": "user", "content": "hi"}]})
    ]
    assert "".join(chunks) == "Hello"
    assert calls[0].body["stream"] is True
    assert calls[0].body["model"] == "misar-online"
    assert calls[0].headers["accept"] == "text/event-stream"
    assert calls[0].url == f"{BASE}/v1/chat/completions"


async def test_async_chat_completions_stream(make_client):
    dev, calls = make_client(sse_response(CHAT_FRAMES))
    chunks = []
    async for ev in dev.chat.acompletions_stream({"messages": []}):
        chunks.append(ev.data["choices"][0]["delta"]["content"])
    assert "".join(chunks) == "Hello"
    assert calls[0].body == {"messages": [], "stream": True}


def test_named_events_multiline_and_trailing_frame(make_client):
    dev, calls = make_client(sse_response(["event: step\nid: 1\ndata: line1\ndata: line2\n\n", 'data: {"done":true}']))
    events = list(dev.projects.build_stream("p1"))
    assert events[0] == SSEEvent(event="step", id="1", data="line1\nline2")
    assert events[1].data == {"done": True}
    assert calls[0].method == "GET"
    assert calls[0].url == f"{BASE}/projects/p1/build-stream"


def test_crlf_frames_and_chunk_boundaries():
    chunks = ["event: a\r\nda", "ta:  two spaces\r\n\r", "\ndata: [DONE]\r\n\r\n", "data: x\r\n\r\n"]
    events = list(iter_sse(chunks, "[DONE]"))
    assert events == [SSEEvent(event="a", data=" two spaces", id=None)]
    # No terminator: [DONE] is just data, and the stream reads to EOF.
    events = list(iter_sse(chunks, None))
    assert [e.data for e in events] == [" two spaces", "[DONE]", "x"]


def test_plan_limit_frame_raises(make_client):
    import json

    frame = f"data: {json.dumps({'type': 'error', **PLAN_LIMIT_BODY})}\n\n"
    dev, _ = make_client(sse_response([frame]))
    with pytest.raises(PlanLimitError) as info:
        next(iter(dev.chat.studio_stream({"message": "hi"})))
    assert info.value.recommended_plan == "pro"


async def test_async_plan_limit_frame_raises(make_client):
    import json

    frame = f"data: {json.dumps(PLAN_LIMIT_BODY)}\n\n"
    dev, _ = make_client(sse_response([frame]))
    with pytest.raises(PlanLimitError):
        async for _ in dev.chat.astudio_stream({"message": "hi"}):
            pass


def test_http_error_before_streaming_is_typed_and_not_retried(make_client):
    dev, calls = make_client(json_response(PLAN_LIMIT_BODY, 402))
    with pytest.raises(PlanLimitError):
        list(dev.projects.build_stream("p1"))
    dev, calls = make_client(json_response({"error": "down"}, 503))
    with pytest.raises(ServerError):
        list(dev.projects.build_stream("p1"))
    assert len(calls) == 1


# ── Pagination ──────────────────────────────────────────────────────────────


def test_paginate_walks_until_short_page():
    pages = [[1, 2], [3, 4], [5]]
    offsets = []

    def fetch(offset, limit):
        offsets.append(offset)
        return {"items": pages[len(offsets) - 1]}

    assert list(paginate(fetch, page_size=2)) == [1, 2, 3, 4, 5]
    assert offsets == [0, 2, 4]


def test_paginate_drives_a_real_list_method(make_client):
    dev, calls = make_client(
        json_response({"templates": [{"id": 1}, {"id": 2}]}),
        json_response({"templates": [{"id": 3}]}),
    )
    ids = [
        t["id"]
        for t in dev.paginate(
            lambda offset, limit: dev.templates.list({"offset": offset, "limit": limit}), page_size=2, max_items=3
        )
    ]
    assert ids == [1, 2, 3]
    assert "offset=2" in calls[1].url


async def test_apaginate(make_client):
    dev, _ = make_client(json_response([{"id": 1}, {"id": 2}]), json_response([]))
    out = [t async for t in apaginate(lambda o, n: dev.gallery.alist({"offset": o, "limit": n}), page_size=2)]
    assert out == [{"id": 1}, {"id": 2}]
