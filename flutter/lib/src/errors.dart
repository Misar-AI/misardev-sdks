/// Typed errors for the MisarDev API.
///
/// Every non-2xx answer becomes a [MisarDevError]; the subclasses let a caller
/// branch on the kind of failure without parsing strings. The one that matters
/// most commercially is [PlanLimitError]: the key is valid, but the
/// subscription behind it does not cover the call. It carries the full upgrade
/// offer the server sent (plan names, prices, URLs), so an app can render an
/// upgrade card rather than a bare failure.
library;

/// Base class for every error the SDK raises.
class MisarDevError implements Exception {
  MisarDevError(
    this.status,
    this.message, {
    this.code,
    this.body,
    this.requestId,
  });

  /// HTTP status, or 0 when the request never got an answer.
  final int status;

  /// Human-readable message, taken from the error body when there is one.
  final String message;

  /// Machine-readable error code from the body, when the API sends one.
  final String? code;

  /// The decoded error body (JSON value or raw text), for anything this class
  /// does not surface.
  final Object? body;

  /// The `x-request-id` response header, for support requests.
  final String? requestId;

  /// Worth retrying as-is: a throttle or a transient server condition.
  bool get isRetryable => status == 429 || (status >= 500 && status < 600);

  /// The class name shown by [toString].
  String get kind => 'MisarDevError';

  @override
  String toString() {
    final extra = [
      if (code != null) 'code: $code',
      if (requestId != null) 'request: $requestId',
    ];
    return '$kind($status): $message${extra.isEmpty ? '' : ' (${extra.join(', ')})'}';
  }
}

/// 400 / 422 — the request was malformed or failed validation.
class ValidationError extends MisarDevError {
  ValidationError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'ValidationError';
}

/// 401 — the key is missing, revoked, expired, or not a MisarDev key.
class AuthenticationError extends MisarDevError {
  AuthenticationError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'AuthenticationError';
}

/// 403 — authenticated, but not allowed to touch this resource.
class PermissionDeniedError extends MisarDevError {
  PermissionDeniedError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'PermissionDeniedError';
}

/// 404 — no such resource, or not one this key can see.
class NotFoundError extends MisarDevError {
  NotFoundError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'NotFoundError';
}

/// 409 — conflicts with current state (e.g. a build already running).
class ConflictError extends MisarDevError {
  ConflictError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'ConflictError';
}

/// 429 that is an ordinary throttle, identical for every user.
///
/// The transport already retried it `maxRetries` times before raising this;
/// wait [retryAfter] seconds before trying again.
class RateLimitError extends MisarDevError {
  RateLimitError(
    super.status,
    super.message, {
    super.code,
    super.body,
    super.requestId,
    this.retryAfter,
  });

  /// Seconds the server asked us to wait, when it said.
  final int? retryAfter;

  @override
  String get kind => 'RateLimitError';
}

/// 5xx — the API failed. Retried automatically for idempotent requests.
class ServerError extends MisarDevError {
  ServerError(super.status, super.message, {super.code, super.body, super.requestId});

  @override
  String get kind => 'ServerError';
}

/// The request never got an HTTP answer (DNS, TLS, reset, timeout).
class NetworkError extends MisarDevError {
  NetworkError(String message, {this.cause}) : super(0, message, code: 'network_error');

  /// The underlying exception from the HTTP client.
  final Object? cause;

  @override
  String get kind => 'NetworkError';
}

/// The subscription behind the API key blocks this call.
///
/// Detected by `code: "plan_limit_exceeded"` in the body — NEVER by status,
/// because a spent quota is a 429 that would otherwise look like an ordinary
/// throttle. A feature that is not on the plan answers 402 (`feature_locked`);
/// a spent allowance answers 429 (`quota_exhausted`). Retrying cannot help
/// until the plan changes or the period resets, so the transport never retries
/// it.
class PlanLimitError extends MisarDevError {
  PlanLimitError(
    super.status,
    super.message, {
    super.body,
    super.requestId,
    this.offer,
    this.retryAfter,
  }) : super(code: 'plan_limit_exceeded');

  /// The full upgrade offer exactly as the server sent it — every field is
  /// kept (`headline`, `plans`, `usage`, `urls`, `cta`, …). Render it; all copy
  /// comes from the server.
  final Map<String, dynamic>? offer;

  /// Seconds until a quota resets, for `quota_exhausted` blocks
  /// (the `Retry-After` header).
  final int? retryAfter;

  Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

  String? _string(Object? v) => v is String ? v : null;

  /// Why the call was refused: `feature_locked`, `quota_exhausted`, …
  String? get reason => _string(offer?['reason']);

  /// Where to send the user to unblock themselves: the billing page, falling
  /// back to pricing.
  String? get upgradeUrl {
    final urls = _map(offer?['urls']);
    return _string(urls?['billing']) ?? _string(urls?['pricing']);
  }

  /// The machine key of the limit that was hit, e.g. `api_access`.
  String? get feature => _string(offer?['feature']);

  /// Slug of the plan the key is on now, e.g. `starter`.
  String? get currentPlan => _string(_map(offer?['current_plan'])?['slug']);

  /// Slug of the plan the server recommends, e.g. `pro`.
  String? get recommendedPlan => _string(offer?['recommended_plan']);

  @override
  String get kind => 'PlanLimitError';

  @override
  String toString() => 'PlanLimitError($status): $message'
      '${upgradeUrl == null ? '' : ' (upgrade: $upgradeUrl)'}';
}
