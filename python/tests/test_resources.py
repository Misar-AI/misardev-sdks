"""Every operation in sdks/manifest.json is reachable through the generated
client — sync and async — and builds the exact verb + URL the server routes.

Invoked for real against a recording MockTransport; nothing is declared.
"""

from __future__ import annotations

import json
import keyword
import re
from pathlib import Path

import pytest

from misardev import OPERATION_COUNT

from .conftest import BASE, json_response, sse_response

MANIFEST = json.loads((Path(__file__).resolve().parents[2] / "manifest.json").read_text())


def snake(name: str) -> str:
    """Same word split as scripts/sdk-gen/common.mjs `snake`."""
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", name)
    return "_".join(w.lower() for w in re.split(r"[-_/\s.:]+", s.strip()) if w)


def method_name(name: str) -> str:
    n = snake(name)
    return f"{n}_" if keyword.iskeyword(n) else n


def optional_query(m: dict) -> list:
    return [q for q in m.get("queryParams", []) if q not in m.get("requiredQuery", [])]


def args_for(m: dict) -> list:
    args: list = [f"{p}-1" for p in m.get("pathParams", [])]
    args += [f"{q}-v" for q in m.get("requiredQuery", [])]
    if m.get("hasBody"):
        args.append({"probe": True})
    if optional_query(m):
        args.append({})
    return args


def expected_url(m: dict) -> str:
    path = m["path"]
    for p in m.get("pathParams", []):
        path = path.replace(f":{p}", f"{p}-1")
    qs = "&".join(f"{q}={q}-v" for q in m.get("requiredQuery", []))
    return f"{BASE}{path}{'?' + qs if qs else ''}"


OPS = [(r, m) for r, d in MANIFEST["resources"].items() for m in d["methods"]]
STREAMS = MANIFEST["streams"]["sse"]


def test_operation_count_matches_manifest():
    assert len(OPS) + len(STREAMS) == 109
    assert OPERATION_COUNT == len(OPS) + len(STREAMS)


@pytest.mark.parametrize("resource,m", OPS, ids=[f"{r}.{m['name']}" for r, m in OPS])
def test_method(make_client, resource, m):
    dev, calls = make_client(json_response({"ok": True}))
    fn = getattr(getattr(dev, snake(resource)), method_name(m["name"]))
    assert fn(*args_for(m)) == {"ok": True}
    assert calls[0].method == m["verb"]
    assert calls[0].url == expected_url(m)
    if m.get("hasBody"):
        assert calls[0].body == {"probe": True}


@pytest.mark.parametrize("resource,m", OPS, ids=[f"{r}.a{snake(m['name'])}" for r, m in OPS])
async def test_async_method(make_client, resource, m):
    dev, calls = make_client(json_response({"ok": True}))
    fn = getattr(getattr(dev, snake(resource)), "a" + snake(m["name"]))
    assert await fn(*args_for(m)) == {"ok": True}
    assert calls[0].method == m["verb"]
    assert calls[0].url == expected_url(m)
    await dev.aclose()


@pytest.mark.parametrize("s", STREAMS, ids=[f"{s['resource']}.{s['name']}" for s in STREAMS])
def test_stream(make_client, s):
    dev, calls = make_client(sse_response(['data: {"x":1}\n\n']))
    fn = getattr(getattr(dev, snake(s["resource"])), method_name(s["name"]))
    events = list(fn(*args_for(s)))
    assert [e.data for e in events] == [{"x": 1}]
    assert calls[0].method == s["verb"]
    assert calls[0].url == expected_url(s)
    assert calls[0].headers["accept"] == "text/event-stream"
    if s.get("terminator") == "[DONE]":
        assert calls[0].body == {"probe": True, "stream": True}
    elif s.get("hasBody"):
        assert calls[0].body == {"probe": True}


@pytest.mark.parametrize("s", STREAMS, ids=[f"{s['resource']}.a{snake(s['name'])}" for s in STREAMS])
async def test_async_stream(make_client, s):
    dev, calls = make_client(sse_response(['data: {"x":1}\n\n']))
    fn = getattr(getattr(dev, snake(s["resource"])), "a" + snake(s["name"]))
    events = [e async for e in fn(*args_for(s))]
    assert [e.data for e in events] == [{"x": 1}]
    assert calls[0].method == s["verb"]
    assert calls[0].url == expected_url(s)
    await dev.aclose()
