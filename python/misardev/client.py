"""The MisarDev API client — sync and async on one object."""

from __future__ import annotations

from typing import Any, AsyncIterator, Awaitable, Callable, Iterator, Mapping, Optional

import httpx

from .core.pagination import apaginate, paginate
from .core.sse import DONE, SSEEvent
from .core.transport import Query, Transport
from .generated import MisarDevResources

__all__ = ["MisarDev", "MisarDevClient"]


class MisarDev(MisarDevResources):
    """The MisarDev API client.

    Every resource (``projects``, ``templates``, ``chat``, …) is generated from
    the API's route tree, so it always matches what the server exposes. Each
    method has an ``a``-prefixed async twin on the same object
    (``dev.projects.list`` / ``dev.projects.alist``). The client authenticates
    with your account API key (``mdk_…``) and nothing else.

    Sync usage::

        from misardev import MisarDev

        dev = MisarDev()                       # reads MISARDEV_API_KEY
        projects = dev.projects.list()

    Async usage::

        projects = await dev.projects.alist()

    Args:
        api_key: The account API key. Falls back to ``MISARDEV_API_KEY``.
        base_url: Defaults to ``MISARDEV_BASE_URL``, then ``https://api.misar.io/dev``.
        max_retries: Total attempts for a retryable failure (default 3).
        timeout: Per-attempt timeout in seconds (default 60).
        headers: Extra headers sent with every request.
        http_client: An ``httpx.Client`` for sync calls (proxies, tests).
        async_http_client: An ``httpx.AsyncClient`` for async calls.
        transport: An httpx transport (e.g. ``httpx.MockTransport``) used for
            both when the clients are not injected.
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
        self.transport = Transport(
            api_key,
            base_url=base_url,
            max_retries=max_retries,
            timeout=timeout,
            headers=headers,
            http_client=http_client,
            async_http_client=async_http_client,
            transport=transport,
        )
        super().__init__(self.transport)

    def __repr__(self) -> str:  # never leak the key
        return f"MisarDev(base_url={self.base_url!r})"

    @property
    def base_url(self) -> str:
        return self.transport.base_url

    # ── Escape hatches for routes the SDK does not wrap yet ─────────────────

    def request(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Query] = None,
        body: Any = None,
        headers: Optional[Mapping[str, str]] = None,
    ) -> Any:
        """Call any route directly: ``dev.request("GET", "/projects", query={...})``."""
        return self.transport.request(method, path, query=query, body=body, headers=headers)

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
        return await self.transport.arequest(method, path, query=query, body=body, headers=headers)

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
        """Open any SSE route directly."""
        return self.transport.stream(method, path, query=query, body=body, headers=headers, terminator=terminator)

    def astream(
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
        return self.transport.astream(method, path, query=query, body=body, headers=headers, terminator=terminator)

    # ── Pagination ──────────────────────────────────────────────────────────

    def paginate(
        self,
        fetch_page: Callable[[int, int], Any],
        page_size: int = 50,
        max_items: Optional[int] = None,
    ) -> Iterator[Any]:
        """Walk every page of an offset-paginated list. See :func:`misardev.paginate`."""
        return paginate(fetch_page, page_size=page_size, max_items=max_items)

    def apaginate(
        self,
        fetch_page: Callable[[int, int], Awaitable[Any]],
        page_size: int = 50,
        max_items: Optional[int] = None,
    ) -> AsyncIterator[Any]:
        """Async twin of :meth:`paginate`."""
        return apaginate(fetch_page, page_size=page_size, max_items=max_items)

    # ── Lifecycle ───────────────────────────────────────────────────────────

    def close(self) -> None:
        """Close the HTTP connection pool the client opened."""
        self.transport.close()

    async def aclose(self) -> None:
        """Close any async connection pool the client opened."""
        await self.transport.aclose()

    def __enter__(self) -> "MisarDev":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()

    async def __aenter__(self) -> "MisarDev":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        await self.aclose()
        self.close()


#: Deprecated alias for :class:`MisarDev`, kept so ``from misardev import MisarDevClient`` still imports.
MisarDevClient = MisarDev
