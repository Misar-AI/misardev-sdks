"""Hand-written runtime core: transport, retries, typed errors, SSE, pagination.

The resource layer above it (``misardev.generated``) is generated from
``sdks/manifest.json``; this half is written by hand because idiom matters most
here and generated code reads worst.
"""

from .pagination import apaginate, items_of, paginate
from .sse import SSEEvent, aiter_sse, iter_sse, parse_frame
from .transport import (
    DEFAULT_BASE_URL,
    SDK_VERSION,
    Transport,
    backoff_seconds,
    build_query,
    encode_path,
    error_for,
    is_plan_limit_body,
)

__all__ = [
    "DEFAULT_BASE_URL",
    "SDK_VERSION",
    "Transport",
    "backoff_seconds",
    "build_query",
    "encode_path",
    "error_for",
    "is_plan_limit_body",
    "SSEEvent",
    "iter_sse",
    "aiter_sse",
    "parse_frame",
    "paginate",
    "apaginate",
    "items_of",
]
