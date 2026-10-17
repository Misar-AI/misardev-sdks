/**
 * Typed errors for the MisarDev API.
 *
 * Every non-2xx answer becomes a {@link MisarDevError}; the subclasses let a
 * caller branch on the kind of failure without parsing strings. The one that
 * matters most commercially is {@link PlanLimitError}: the key is valid, but the
 * subscription behind it does not cover the call. It carries the full upgrade
 * offer the server sent (plan names, prices, URLs), so an app can render an
 * upgrade card rather than a bare failure.
 */

/** The `@misar/upsell` upgrade offer, as the API sends it. */
export interface UpgradeOffer {
  product: string;
  product_name: string;
  reason:
    | "quota_exhausted"
    | "feature_locked"
    | "overage_capped"
    | "credits_exhausted"
    | string;
  feature: string;
  feature_label: string;
  headline: string;
  usage: {
    used: number | null;
    limit: number | null;
    remaining: number | null;
    period: string | null;
    resets_at: string | null;
  } | null;
  current_plan: { slug: string; name: string };
  recommended_plan: string | null;
  plans: Array<{
    slug: string;
    name: string;
    price: string;
    price_note: string | null;
    recommended: boolean;
    current: boolean;
    unlocks: string | null;
    benefits: string[];
    url: string;
  }>;
  urls: { pricing: string; billing: string; docs: string; compare: string };
  cta: string;
  [key: string]: unknown;
}

export class MisarDevError extends Error {
  constructor(
    /** HTTP status, or 0 when the request never got an answer. */
    readonly status: number,
    message: string,
    /** Machine-readable error code from the body, when the API sends one. */
    readonly code: string | null = null,
    /** The decoded error body, for anything this class does not surface. */
    readonly body: unknown = null,
    /** The `x-request-id` header, for support requests. */
    readonly requestId: string | null = null,
  ) {
    super(message);
    this.name = "MisarDevError";
  }

  /** Worth retrying as-is: a throttle or a transient server condition. */
  get isRetryable(): boolean {
    return this.status === 429 || (this.status >= 500 && this.status < 600);
  }
}

/** 400 / 422 — the request was malformed or failed validation. */
export class ValidationError extends MisarDevError {
  override name = "ValidationError";
}

/** 401 — the key is missing, revoked, expired, or not a MisarDev key. */
export class AuthenticationError extends MisarDevError {
  override name = "AuthenticationError";
}

/** 403 — authenticated, but not allowed to touch this resource. */
export class PermissionDeniedError extends MisarDevError {
  override name = "PermissionDeniedError";
}

/** 404 — no such resource, or not one this key can see. */
export class NotFoundError extends MisarDevError {
  override name = "NotFoundError";
}

/** 409 — conflicts with current state (e.g. a build already running). */
export class ConflictError extends MisarDevError {
  override name = "ConflictError";
}

/**
 * 429 that is an ordinary throttle (identical for every user). Wait
 * {@link retryAfter} seconds and try again — the transport already did so
 * `maxRetries` times before throwing this.
 */
export class RateLimitError extends MisarDevError {
  override name = "RateLimitError";
  constructor(
    status: number,
    message: string,
    code: string | null,
    body: unknown,
    requestId: string | null,
    /** Seconds the server asked us to wait, when it said. */
    readonly retryAfter: number | null,
  ) {
    super(status, message, code, body, requestId);
  }
}

/** 5xx — the API failed. Retried automatically for idempotent requests. */
export class ServerError extends MisarDevError {
  override name = "ServerError";
}

/** The request never got an HTTP answer (DNS, TLS, reset, timeout). */
export class NetworkError extends MisarDevError {
  override name = "NetworkError";
  constructor(
    message: string,
    readonly cause?: unknown,
  ) {
    super(0, message, "network_error");
  }
}

/**
 * The subscription behind the API key blocks this call.
 *
 * Detected by `code: "plan_limit_exceeded"` in the body — NEVER by status,
 * because a spent quota is a 429 that would otherwise look like an ordinary
 * throttle. Retrying cannot help until the plan changes or the period resets,
 * so the transport never retries it.
 */
export class PlanLimitError extends MisarDevError {
  override name = "PlanLimitError";
  constructor(
    status: number,
    message: string,
    body: unknown,
    requestId: string | null,
    /** The full upgrade offer. Render it; all copy comes from the server. */
    readonly offer: UpgradeOffer | null,
    /** Seconds until a quota resets, for `quota_exhausted` blocks. */
    readonly retryAfter: number | null,
  ) {
    super(status, message, "plan_limit_exceeded", body, requestId);
  }

  /** Where to send the user to unblock themselves. */
  get upgradeUrl(): string | null {
    return this.offer?.urls?.billing ?? this.offer?.urls?.pricing ?? null;
  }

  /** The machine key of the limit that was hit, e.g. `api_access`. */
  get feature(): string | null {
    return this.offer?.feature ?? null;
  }

  get currentPlan(): string | null {
    return this.offer?.current_plan?.slug ?? null;
  }

  get recommendedPlan(): string | null {
    return this.offer?.recommended_plan ?? null;
  }
}
