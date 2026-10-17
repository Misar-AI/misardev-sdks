"""MisarDev Python SDK.

Build, ship and run apps on MisarDev from Python — every API route, sync and
async from the same client::

    from misardev import MisarDev

    dev = MisarDev()                 # reads MISARDEV_API_KEY
    project = dev.projects.create({"name": "my-app"})
"""

from ._version import __version__
from .client import MisarDev, MisarDevClient
from .core.pagination import apaginate, items_of, paginate
from .core.sse import SSEEvent
from .core.transport import DEFAULT_BASE_URL, SDK_VERSION, Transport
from .errors import (
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
from .generated import OPERATION_COUNT, MisarDevResources

__all__ = [
    "__version__",
    "MisarDev",
    "MisarDevClient",
    "MisarDevResources",
    "OPERATION_COUNT",
    "Transport",
    "DEFAULT_BASE_URL",
    "SDK_VERSION",
    "SSEEvent",
    "paginate",
    "apaginate",
    "items_of",
    "MisarDevError",
    "ValidationError",
    "AuthenticationError",
    "PermissionDeniedError",
    "NotFoundError",
    "ConflictError",
    "RateLimitError",
    "ServerError",
    "NetworkError",
    "PlanLimitError",
]
