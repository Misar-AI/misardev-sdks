"""Offset pagination.

List endpoints that take ``limit``/``offset`` (templates, gallery, API keys…)
return one page at a time. :func:`paginate` walks every page for you: it calls
``fetch_page(offset, limit)``, yields each item, and stops on a short page.
Items are read from the response itself when it is a list, otherwise from its
first list-valued field (``templates``, ``items``, ``keys``, …).

Example::

    for t in paginate(lambda offset, limit: dev.templates.list({"offset": offset, "limit": limit})):
        print(t["name"])

    async for t in apaginate(lambda offset, limit: dev.templates.alist({"offset": offset, "limit": limit})):
        print(t["name"])
"""

from __future__ import annotations

from typing import Any, AsyncIterator, Awaitable, Callable, Iterator, List, Optional

__all__ = ["items_of", "paginate", "apaginate"]


def items_of(page: Any) -> List[Any]:
    """The items of one page: the page itself if a list, else its first list field."""
    if isinstance(page, list):
        return page
    if isinstance(page, dict):
        for value in page.values():
            if isinstance(value, list):
                return value
    return []


def paginate(
    fetch_page: Callable[[int, int], Any],
    page_size: int = 50,
    max_items: Optional[int] = None,
) -> Iterator[Any]:
    """Yield every item across offset pages, stopping on a short page."""
    offset = 0
    yielded = 0
    while max_items is None or yielded < max_items:
        items = items_of(fetch_page(offset, page_size))
        for item in items:
            if max_items is not None and yielded >= max_items:
                return
            yield item
            yielded += 1
        if len(items) < page_size:
            return
        offset += len(items)


async def apaginate(
    fetch_page: Callable[[int, int], Awaitable[Any]],
    page_size: int = 50,
    max_items: Optional[int] = None,
) -> AsyncIterator[Any]:
    """Async variant of :func:`paginate`; ``fetch_page`` returns an awaitable."""
    offset = 0
    yielded = 0
    while max_items is None or yielded < max_items:
        items = items_of(await fetch_page(offset, page_size))
        for item in items:
            if max_items is not None and yielded >= max_items:
                return
            yield item
            yielded += 1
        if len(items) < page_size:
            return
        offset += len(items)
