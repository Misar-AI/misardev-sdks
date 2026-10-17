"""Server-Sent Events parsing.

Frames are separated by a blank line (``\\n\\n`` or ``\\r\\n\\r\\n``) and may
span several ``data:`` lines, which are joined with newlines per the SSE spec.
Comment lines (``:``) are keep-alives and are skipped. The terminator payload —
``[DONE]`` on the OpenAI-compatible ``/v1/chat/completions`` stream — ends
iteration and is never yielded, so callers can simply read to completion.
Streams with no terminator (``None``) are read to EOF, and a final frame that
was never closed by a blank line is still delivered.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, AsyncIterable, AsyncIterator, Iterable, Iterator, List, Optional, Tuple

__all__ = ["SSEEvent", "DONE", "parse_frame", "iter_sse", "aiter_sse"]

#: The terminator of the OpenAI-compatible chat completions stream.
DONE = "[DONE]"

_SEPARATOR = re.compile(r"\r?\n\r?\n")


@dataclass(frozen=True)
class SSEEvent:
    """One Server-Sent Event."""

    #: The ``event:`` name, when the server sends one.
    event: Optional[str]
    #: JSON-decoded ``data:`` payload, or the raw string when it is not JSON.
    data: Any
    #: The ``id:`` field, when present.
    id: Optional[str]


def _decode(raw: str) -> Any:
    try:
        return json.loads(raw)
    except ValueError:
        return raw


def parse_frame(frame: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Parse one complete frame into ``(event, data, id)``.

    ``data`` is ``None`` when the frame carried no ``data:`` line at all.
    """
    event: Optional[str] = None
    event_id: Optional[str] = None
    data: List[str] = []
    for line in re.split(r"\r?\n", frame):
        if not line or line.startswith(":"):
            continue
        field, sep, value = line.partition(":")
        if not sep:
            value = ""
        if value.startswith(" "):
            value = value[1:]
        if field == "data":
            data.append(value)
        elif field == "event":
            event = value
        elif field == "id":
            event_id = value
    return event, ("\n".join(data) if data else None), event_id


class _Decoder:
    """Incremental frame splitter shared by the sync and async iterators."""

    def __init__(self, terminator: Optional[str]) -> None:
        self.terminator = terminator
        self.buffer = ""
        self.done = False

    def _event(self, frame: str) -> Optional[SSEEvent]:
        event, data, event_id = parse_frame(frame)
        if data is None:
            return None
        if self.terminator is not None and data.strip() == self.terminator:
            self.done = True
            return None
        return SSEEvent(event=event, data=_decode(data), id=event_id)

    def feed(self, text: str) -> List[SSEEvent]:
        self.buffer += text
        out: List[SSEEvent] = []
        while not self.done:
            match = _SEPARATOR.search(self.buffer)
            if not match:
                break
            frame = self.buffer[: match.start()]
            self.buffer = self.buffer[match.end() :]
            ev = self._event(frame)
            if ev is not None:
                out.append(ev)
        return out

    def flush(self) -> List[SSEEvent]:
        if self.done:
            return []
        frame, self.buffer = self.buffer, ""
        ev = self._event(frame)
        return [ev] if ev is not None else []


def iter_sse(chunks: Iterable[str], terminator: Optional[str] = DONE) -> Iterator[SSEEvent]:
    """Iterate the events of a ``text/event-stream`` body given as text chunks."""
    decoder = _Decoder(terminator)
    for chunk in chunks:
        for ev in decoder.feed(chunk):
            yield ev
        if decoder.done:
            return
    for ev in decoder.flush():
        yield ev


async def aiter_sse(
    chunks: AsyncIterable[str], terminator: Optional[str] = DONE
) -> AsyncIterator[SSEEvent]:
    """Async variant of :func:`iter_sse`."""
    decoder = _Decoder(terminator)
    async for chunk in chunks:
        for ev in decoder.feed(chunk):
            yield ev
        if decoder.done:
            return
    for ev in decoder.flush():
        yield ev
