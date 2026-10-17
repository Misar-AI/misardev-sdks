"""Shared fixtures: a recording ``httpx.MockTransport`` — no network, ever."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable, List, Optional, Union

import httpx
import pytest

import misardev.core.transport as transport_module
from misardev import MisarDev

BASE = "https://api.test/dev"

PLAN_LIMIT_BODY = {
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
        "usage": None,
        "current_plan": {"slug": "starter", "name": "Starter"},
        "recommended_plan": "pro",
        "plans": [],
        "topup": None,
        "overage": None,
        "trial": None,
        "cross_sell": [],
        "urls": {
            "pricing": "https://www.misar.dev/pricing",
            "billing": "https://www.misar.dev/settings/billing",
            "docs": "https://docs.misar.io/dev/api",
            "compare": "https://www.misar.dev/pricing#compare",
        },
        "cta": "Upgrade to Pro to continue.",
    },
}


@dataclass
class Call:
    method: str
    url: str
    headers: httpx.Headers
    body: Any


Responder = Union[Callable[[httpx.Request], httpx.Response], BaseException]


def json_response(body: Any, status: int = 200, headers: Optional[dict] = None) -> Responder:
    return lambda request: httpx.Response(status, json=body, headers=headers or {})


def text_response(text: str, status: int = 200, headers: Optional[dict] = None) -> Responder:
    return lambda request: httpx.Response(status, text=text, headers=headers or {})


def empty_response(status: int = 204) -> Responder:
    return lambda request: httpx.Response(status)


def sse_response(frames: List[str], status: int = 200) -> Responder:
    return lambda request: httpx.Response(
        status, content="".join(frames).encode(), headers={"content-type": "text/event-stream"}
    )


class Recorder:
    """An httpx MockTransport handler that records calls and answers from a queue.

    The last queued answer repeats once the queue is down to one.
    """

    def __init__(self, responses: List[Responder]) -> None:
        self.queue = list(responses) or [json_response({"ok": True})]
        self.calls: List[Call] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        raw = request.read()
        self.calls.append(
            Call(
                method=request.method,
                url=str(request.url),
                headers=request.headers,
                body=json.loads(raw) if raw else None,
            )
        )
        nxt = self.queue.pop(0) if len(self.queue) > 1 else self.queue[0]
        if isinstance(nxt, BaseException):
            raise nxt
        return nxt(request)


@pytest.fixture(autouse=True)
def instant_backoff(monkeypatch):
    """Record backoff delays instead of sleeping through them."""
    slept: List[float] = []

    async def asleep(seconds: float) -> None:
        slept.append(seconds)

    monkeypatch.setattr(transport_module, "_sleep", slept.append)
    monkeypatch.setattr(transport_module, "_asleep", asleep)
    return slept


@pytest.fixture
def make_client():
    def make(*responses: Responder, max_retries: int = 3):
        rec = Recorder(list(responses))
        dev = MisarDev(
            "mdk_test_key",
            base_url=BASE,
            max_retries=max_retries,
            transport=httpx.MockTransport(rec),
        )
        return dev, rec.calls

    return make
