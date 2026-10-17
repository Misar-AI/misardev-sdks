"""Typed errors for the MisarDev API.

Every non-2xx answer becomes a :class:`MisarDevError`; the subclasses let a
caller branch on the kind of failure without parsing strings. The one that
matters most commercially is :class:`PlanLimitError`: the key is valid, but the
subscription behind it does not cover the call. It carries the full upgrade
offer the server sent (plan names, prices, URLs), so an app can render an
upgrade card rather than a bare failure.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

__all__ = [
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


class MisarDevError(Exception):
    """Base class for every error the SDK raises.

    Attributes:
        status: HTTP status, or ``0`` when the request never got an answer.
        message: Human-readable message extracted from the response.
        code: Machine-readable error code from the body, when the API sends one.
        body: The decoded error body (dict, list or raw string), for anything
            this class does not surface.
        request_id: The ``x-request-id`` response header, for support requests.
    """

    def __init__(
        self,
        status: int,
        message: str,
        code: Optional[str] = None,
        body: Any = None,
        request_id: Optional[str] = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code
        self.body = body
        self.request_id = request_id

    @property
    def is_retryable(self) -> bool:
        """Worth retrying as-is: a throttle or a transient server condition."""
        return self.status == 429 or 500 <= self.status < 600

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}(status={self.status!r}, message={self.message!r}, "
            f"code={self.code!r}, request_id={self.request_id!r})"
        )


class ValidationError(MisarDevError):
    """400 / 422 — the request was malformed or failed validation."""


class AuthenticationError(MisarDevError):
    """401 — the key is missing, revoked, expired, or not a MisarDev key."""


class PermissionDeniedError(MisarDevError):
    """403 — authenticated, but not allowed to touch this resource."""


class NotFoundError(MisarDevError):
    """404 — no such resource, or not one this key can see."""


class ConflictError(MisarDevError):
    """409 — conflicts with current state (e.g. a build already running)."""


class RateLimitError(MisarDevError):
    """429 that is an ordinary throttle, identical for every user.

    Wait :attr:`retry_after` seconds and try again — the transport already did
    so ``max_retries`` times before raising this.
    """

    def __init__(
        self,
        status: int,
        message: str,
        code: Optional[str] = None,
        body: Any = None,
        request_id: Optional[str] = None,
        retry_after: Optional[float] = None,
    ) -> None:
        super().__init__(status, message, code, body, request_id)
        #: Seconds the server asked us to wait, when it said.
        self.retry_after = retry_after


class ServerError(MisarDevError):
    """5xx — the API failed. Retried automatically for idempotent requests."""


class NetworkError(MisarDevError):
    """The request never got an HTTP answer (DNS, TLS, reset, timeout)."""

    def __init__(self, message: str, cause: Optional[BaseException] = None) -> None:
        super().__init__(0, message, "network_error")
        self.cause = cause


class PlanLimitError(MisarDevError):
    """The subscription behind the API key blocks this call.

    Detected by ``code == "plan_limit_exceeded"`` in the body — NEVER by status,
    because a spent quota is a 429 that would otherwise look like an ordinary
    throttle. ``402`` means the feature is not on the plan (``feature_locked``);
    ``429`` means an allowance is spent (``quota_exhausted``). Retrying cannot
    help until the plan changes or the period resets, so the transport never
    retries it.

    Attributes:
        offer: The full upgrade offer exactly as the server sent it (every
            field kept). Render it; all copy comes from the server.
        retry_after: Seconds until a quota resets, from ``Retry-After``.
    """

    def __init__(
        self,
        status: int,
        message: str,
        body: Any = None,
        request_id: Optional[str] = None,
        offer: Optional[Dict[str, Any]] = None,
        retry_after: Optional[float] = None,
    ) -> None:
        super().__init__(status, message, "plan_limit_exceeded", body, request_id)
        self.offer: Optional[Dict[str, Any]] = offer if isinstance(offer, dict) else None
        self.retry_after = retry_after

    def _get(self, *keys: str) -> Any:
        node: Any = self.offer
        for key in keys:
            if not isinstance(node, dict):
                return None
            node = node.get(key)
        return node

    @property
    def upgrade_url(self) -> Optional[str]:
        """Where to send the user to unblock themselves."""
        return self._get("urls", "billing") or self._get("urls", "pricing")

    @property
    def feature(self) -> Optional[str]:
        """The machine key of the limit that was hit, e.g. ``api_access``."""
        return self._get("feature")

    @property
    def current_plan(self) -> Optional[str]:
        """The account's current plan slug, e.g. ``starter``."""
        return self._get("current_plan", "slug")

    @property
    def recommended_plan(self) -> Optional[str]:
        """The plan slug the server recommends upgrading to."""
        return self._get("recommended_plan")
