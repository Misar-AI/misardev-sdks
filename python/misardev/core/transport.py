"""HTTP transport shared by the generated resource layer.

Everything the SDK does goes through here, and it authenticates exactly one
way: the account API key (``mdk_…``), sent as a bearer token. There is no
second credential path. What a key may do — and how much of it — is decided
server-side from the subscription behind that key; the SDK carries the key and
surfaces the answer rather than deciding locally what a plan allows.

Every operation has a sync form (:meth:`Transport.request`,
:meth:`Transport.stream`) and an async twin (:meth:`Transport.arequest`,
:meth:`Transport.astream`) with identical semantics.
"""

from __future__ import annotations

import asyncio
import json as _json
import os
import random
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, AsyncIterator, Dict, Iterator, Mapping, Optional, Union
from urllib.parse import quote, urlencode

import httpx

from .._version import __version__
from ..errors import (
    AuthenticationError,
    ConflictError,
    MisarDevError,
    NetworkError,
    NotFoundError,
    PermissionDeniedError,
    PlanLimitError,
    RateLimitError,
    ServerError,
    ValidationError,
)
from .sse import DONE, SSEEvent, aiter_sse, iter_sse

__all__ = [
    "DEFAULT_BASE_URL",
    "SDK_VERSION",
    "Transport",
    "build_query",
    "encode_path",
    "backoff_seconds",
    "error_for",
    "is_plan_limit_body",
]

DEFAULT_BASE_URL = "https://api.misar.io/dev"
SDK_VERSION = __version__
API_KEYS_URL = "https://www.misar.dev/settings/api-keys"

#: Statuses worth retrying. 429 only when it is NOT a plan limit.
RETRYABLE = frozenset({429, 500, 502, 503, 504})
#: A 5xx or a dropped connection on a POST may already have done its work —
#: started a build, charged an allowance. Only requests that are safe to repeat
#: are retried on those; a 429 is always safe because the server refused it
#: before doing anything.
IDEMPOTENT = frozenset({"GET", "HEAD", "OPTIONS", "PUT", "DELETE"})
MAX_BACKOFF_S = 60.0

QueryValue = Union[str, int, float, bool, None]
Query = Mapping[str, Any]

# Indirected so tests can make backoff instant.
_sleep = time.sleep
_asleep = asyncio.sleep


# ── Helpers ──────────────────────────────────────────────────────────────────


def encode_path(value: Any) -> str:
    """Path-segment encoding: ``"a b/c"`` → ``"a%20b%2Fc"``."""
    return quote(str(value), safe="")


def _query_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def build_query(query: Optional[Query] = None) -> str:
    """Encode a query mapping: ``None`` dropped, booleans as ``true``/``false``."""
    if not query:
        return ""
    pairs = []
    for key, value in query.items():
        if value is None:
            continue
        if isinstance(value, (list, tuple)):
            pairs.extend((key, _query_value(v)) for v in value if v is not None)
        else:
            pairs.append((key, _query_value(value)))
    if not pairs:
        return ""
    return "?" + urlencode(pairs, quote_via=quote)


def _retry_after_seconds(value: Optional[str]) -> Optional[float]:
    """``Retry-After`` as seconds — either delta-seconds or an HTTP-date."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    try:
        seconds = float(value)
        if seconds >= 0:
            return int(seconds) if seconds.is_integer() else seconds
        return None
    except ValueError:
        pass
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if when is None:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max(0.0, (when - datetime.now(timezone.utc)).total_seconds())


def backoff_seconds(attempt: int, retry_after: Optional[str] = None) -> float:
    """Exponential backoff with jitter, but honour ``Retry-After`` when sent."""
    hinted = _retry_after_seconds(retry_after)
    if hinted is not None:
        return min(float(hinted), MAX_BACKOFF_S)
    base = 0.25 * (2**attempt)
    return min(base + random.random() * base * 0.25, MAX_BACKOFF_S)


def _message_of(body: Any, fallback: str) -> str:
    """Pull a human message out of the API's several error shapes."""
    if isinstance(body, dict):
        err = body.get("error")
        if isinstance(err, str):
            return err
        # /v1/* answers in the OpenAI shape: {"error": {"message", "type", "code"}}
        if isinstance(err, dict) and isinstance(err.get("message"), str):
            return err["message"]
        if isinstance(body.get("message"), str):
            return body["message"]
    if isinstance(body, str) and body.strip():
        return body.strip()[:500]
    return fallback


def _code_of(body: Any) -> Optional[str]:
    if not isinstance(body, dict):
        return None
    if isinstance(body.get("code"), str):
        return body["code"]
    err = body.get("error")
    if isinstance(err, dict) and isinstance(err.get("code"), str):
        return err["code"]
    return None


def is_plan_limit_body(body: Any) -> bool:
    """True when a body is the ``@misar/upsell`` plan-limit refusal."""
    return isinstance(body, dict) and body.get("code") == "plan_limit_exceeded"


def error_for(
    status: int,
    headers: Mapping[str, str],
    body: Any,
    reason: str = "",
) -> MisarDevError:
    """Map an error response to the right typed error. Plan limits first, by ``code``."""
    lowered = {k.lower(): v for k, v in headers.items()}
    request_id = lowered.get("x-request-id")
    message = _message_of(body, reason or f"HTTP {status}")
    code = _code_of(body)
    retry_after = _retry_after_seconds(lowered.get("retry-after"))

    if is_plan_limit_body(body):
        offer = body.get("upgrade")
        return PlanLimitError(
            status,
            message,
            body,
            request_id,
            offer if isinstance(offer, dict) else None,
            retry_after,
        )
    if status in (400, 422):
        return ValidationError(status, message, code, body, request_id)
    if status == 401:
        return AuthenticationError(status, message, code, body, request_id)
    if status == 403:
        return PermissionDeniedError(status, message, code, body, request_id)
    if status == 404:
        return NotFoundError(status, message, code, body, request_id)
    if status == 409:
        return ConflictError(status, message, code, body, request_id)
    if status == 429:
        return RateLimitError(status, message, code, body, request_id, retry_after)
    if status >= 500:
        return ServerError(status, message, code, body, request_id)
    return MisarDevError(status, message, code, body, request_id)


def _decode_text(status: int, text: str) -> Any:
    if status == 204 or not text:
        return None
    try:
        return _json.loads(text)
    except ValueError:
        return text


def _decode(response: httpx.Response) -> Any:
    """204/empty → ``None``; JSON → decoded value; anything else → raw text."""
    if response.status_code == 204 or not response.content:
        return None
    return _decode_text(response.status_code, response.text)


# ── Transport ────────────────────────────────────────────────────────────────


class Transport:
    """Low-level request plumbing. Generated resources are written against this.

    Args:
        api_key: The account API key. Falls back to ``MISARDEV_API_KEY``.
        base_url: Defaults to ``MISARDEV_BASE_URL``, then ``https://api.misar.io/dev``.
        max_retries: Total attempts for a retryable failure (default 3).
        timeout: Per-attempt timeout in seconds (default 60 — builds and AI calls are slow).
        headers: Extra headers sent with every request.
        http_client: An ``httpx.Client`` to use for sync calls (proxies, tests).
        async_http_client: An ``httpx.AsyncClient`` to use for async calls.
        transport: An httpx transport (e.g. ``httpx.MockTransport``) used to
            build both clients when they are not injected.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        *,
        base_url: Optional[str] = None,
        max_retries: int = 3,
        timeout: float = 60.0,
        headers: Optional[Mapping[str, str]] = None,
        http_client: Optional[httpx.Client] = None,
        async_http_client: Optional[httpx.AsyncClient] = None,
        transport: Optional[Any] = None,
    ) -> None:
        key = api_key or os.environ.get("MISARDEV_API_KEY")
        if not key:
            raise MisarDevError(
                0,
                "A MisarDev API key is required. Pass it to the client or set "
                f"MISARDEV_API_KEY. Create one at {API_KEYS_URL}.",
                "missing_api_key",
            )
        self._api_key = key
        self.base_url = (base_url or os.environ.get("MISARDEV_BASE_URL") or DEFAULT_BASE_URL).rstrip("/")
        self.max_retries = max(1, int(max_retries))
        self.timeout = timeout
        self._extra_headers: Dict[str, str] = dict(headers or {})
        self._http = http_client
        self._owns_http = http_client is None
        self._async_http = async_http_client
        self._mock_transport = transport
        self._shared_async: Optional[httpx.AsyncClient] = None

    def __repr__(self) -> str:  # never leak the key
        return f"Transport(base_url={self.base_url!r}, max_retries={self.max_retries})"

    # ── Plumbing ────────────────────────────────────────────────────────────

    def _headers(self, accept: str, extra: Optional[Mapping[str, str]] = None) -> Dict[str, str]:
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Accept": accept,
            "Content-Type": "application/json",
            "X-Misar-SDK": f"misardev-python/{SDK_VERSION}",
        }
        headers.update(self._extra_headers)
        if extra:
            headers.update(extra)
        return headers

    def _url(self, path: str, query: Optional[Query]) -> str:
        return f"{self.base_url}{path}{build_query(query)}"

    @staticmethod
    def _content(body: Any) -> Optional[bytes]:
        return None if body is None else _json.dumps(body).encode("utf-8")

    def _client(self) -> httpx.Client:
        if self._http is None:
            kwargs: Dict[str, Any] = {"timeout": self.timeout}
            if self._mock_transport is not None:
                kwargs["transport"] = self._mock_transport
            self._http = httpx.Client(**kwargs)
        return self._http

    @asynccontextmanager
    async def _aclient(self) -> AsyncIterator[httpx.AsyncClient]:
        if self._async_http is not None:
            yield self._async_http
        elif self._mock_transport is not None:
            if self._shared_async is None:
                self._shared_async = httpx.AsyncClient(transport=self._mock_transport, timeout=self.timeout)
            yield self._shared_async
        else:
            # A fresh client per call: an AsyncClient's pool is bound to the
            # event loop that opened it, and callers often run several loops.
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                yield client

    def close(self) -> None:
        """Close the sync HTTP client, if the transport created it."""
        if self._owns_http and self._http is not None:
            self._http.close()
            self._http = None

    async def aclose(self) -> None:
        """Close any async HTTP client the transport created."""
        if self._shared_async is not None:
            await self._shared_async.aclose()
            self._shared_async = None

    def _should_retry(self, status: int, verb: str) -> bool:
        return status in RETRYABLE and (status == 429 or verb in IDEMPOTENT)

    # ── Requests ────────────────────────────────────────────────────────────

    def request(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Query] = None,
        body: Any = None,
        headers: Optional[Mapping[str, str]] = None,
    ) -> Any:
        """Send one request, retrying throttles and (for idempotent verbs) transient failures."""
        verb = method.upper()
        url = self._url(path, query)
        content = self._content(body)
        client = self._client()

        for attempt in range(self.max_retries):
            last = attempt >= self.max_retries - 1
            try:
                response = client.request(
                    verb,
                    url,
                    headers=self._headers("application/json", headers),
                    content=content,
                    timeout=self.timeout,
                )
            except httpx.HTTPError as exc:
                if not last and verb in IDEMPOTENT:
                    _sleep(backoff_seconds(attempt))
                    continue
                raise NetworkError(str(exc) or type(exc).__name__, exc) from exc

            if response.is_success:
                return _decode(response)

            # Read the body BEFORE deciding to retry: a 429 from the rate
            # limiter and a 429 from a spent plan allowance share a status, and
            # only the first is worth retrying.
            error = error_for(response.status_code, response.headers, _decode(response), response.reason_phrase)
            if isinstance(error, PlanLimitError):
                raise error
            if not last and self._should_retry(response.status_code, verb):
                _sleep(backoff_seconds(attempt, response.headers.get("retry-after")))
                continue
            raise error
        raise NetworkError("retries exhausted")  # pragma: no cover — loop always returns or raises

    async def arequest(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Query] = None,
        body: Any = None,
        headers: Optional[Mapping[str, str]] = None,
    ) -> Any:
        """Async twin of :meth:`request`."""
        verb = method.upper()
        url = self._url(path, query)
        content = self._content(body)

        async with self._aclient() as client:
            for attempt in range(self.max_retries):
                last = attempt >= self.max_retries - 1
                try:
                    response = await client.request(
                        verb,
                        url,
                        headers=self._headers("application/json", headers),
                        content=content,
                        timeout=self.timeout,
                    )
                except httpx.HTTPError as exc:
                    if not last and verb in IDEMPOTENT:
                        await _asleep(backoff_seconds(attempt))
                        continue
                    raise NetworkError(str(exc) or type(exc).__name__, exc) from exc

                if response.is_success:
                    return _decode(response)

                error = error_for(response.status_code, response.headers, _decode(response), response.reason_phrase)
                if isinstance(error, PlanLimitError):
                    raise error
                if not last and self._should_retry(response.status_code, verb):
                    await _asleep(backoff_seconds(attempt, response.headers.get("retry-after")))
                    continue
                raise error
        raise NetworkError("retries exhausted")  # pragma: no cover

    # ── Streams ─────────────────────────────────────────────────────────────

    def stream(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Query] = None,
        body: Any = None,
        headers: Optional[Mapping[str, str]] = None,
        terminator: Optional[str] = DONE,
    ) -> Iterator[SSEEvent]:
        """Open a Server-Sent Events stream and yield each event.

        Never retried: a stream that fails mid-flight cannot be replayed
        without duplicating what the caller already consumed. A frame carrying
        ``code: "plan_limit_exceeded"`` is raised as :class:`PlanLimitError`,
        exactly as the same refusal on a plain request would be.
        """
        client = self._client()
        try:
            with client.stream(
                method.upper(),
                self._url(path, query),
                headers=self._headers("text/event-stream", headers),
                content=self._content(body),
                timeout=self.timeout,
            ) as response:
                if not response.is_success:
                    response.read()
                    raise error_for(response.status_code, response.headers, _decode(response), response.reason_phrase)
                for event in iter_sse(response.iter_text(), terminator):
                    # Other error frames are the stream's own business (the
                    # build stream reports a failed step and carries on), so
                    # only the plan refusal is raised.
                    if is_plan_limit_body(event.data):
                        raise error_for(402, response.headers, event.data)
                    yield event
        except httpx.HTTPError as exc:
            raise NetworkError(str(exc) or type(exc).__name__, exc) from exc

    async def astream(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Query] = None,
        body: Any = None,
        headers: Optional[Mapping[str, str]] = None,
        terminator: Optional[str] = DONE,
    ) -> AsyncIterator[SSEEvent]:
        """Async twin of :meth:`stream`."""
        try:
            async with self._aclient() as client:
                async with client.stream(
                    method.upper(),
                    self._url(path, query),
                    headers=self._headers("text/event-stream", headers),
                    content=self._content(body),
                    timeout=self.timeout,
                ) as response:
                    if not response.is_success:
                        await response.aread()
                        raise error_for(
                            response.status_code, response.headers, _decode(response), response.reason_phrase
                        )
                    async for event in aiter_sse(response.aiter_text(), terminator):
                        if is_plan_limit_body(event.data):
                            raise error_for(402, response.headers, event.data)
                        yield event
        except httpx.HTTPError as exc:
            raise NetworkError(str(exc) or type(exc).__name__, exc) from exc
