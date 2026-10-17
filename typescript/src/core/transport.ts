/**
 * HTTP transport shared by the generated resource layer.
 *
 * Everything the SDK does goes through here, and it authenticates exactly one
 * way: the account API key (`mdk_…`), sent as a bearer token. There is no
 * second credential path. What a key may do — and how much of it — is decided
 * server-side from the subscription behind that key; the SDK carries the key
 * and surfaces the answer rather than deciding locally what a plan allows.
 */

import {
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
  type UpgradeOffer,
} from "./errors.js";
import { parseSSE, type SSEEvent } from "./sse.js";

export const DEFAULT_BASE_URL = "https://api.misar.io/dev";
export const SDK_VERSION = "1.0.0";

export type QueryValue = string | number | boolean | null | undefined;
export type Query = Record<string, QueryValue>;

export interface ClientOptions {
  /** Defaults to `https://api.misar.io/dev`. */
  baseURL?: string;
  /** Total attempts for a retryable failure. Default 3. */
  maxRetries?: number;
  /** Per-attempt timeout. Default 60s — builds and AI calls are slow. */
  timeoutMs?: number;
  /** Extra headers sent with every request. */
  headers?: Record<string, string>;
  /** Inject a fetch implementation (tests, proxies, older runtimes). */
  fetch?: typeof fetch;
}

export interface RequestOptions {
  query?: Query;
  body?: unknown;
  /** Abort the request (and stop retrying) from outside. */
  signal?: AbortSignal;
  headers?: Record<string, string>;
}

/** Statuses worth retrying. 429 only when it is NOT a plan limit. */
const RETRYABLE = new Set([429, 500, 502, 503, 504]);
/**
 * A 5xx or a dropped connection on a POST may already have done its work —
 * started a build, charged an allowance. Only requests that are safe to repeat
 * are retried on those; a 429 is always safe because the server refused it
 * before doing anything.
 */
const IDEMPOTENT = new Set(["GET", "HEAD", "OPTIONS", "PUT", "DELETE"]);

const MAX_BACKOFF_MS = 60_000;

function env(name: string): string | undefined {
  const p = (
    globalThis as { process?: { env?: Record<string, string | undefined> } }
  ).process;
  return p?.env?.[name];
}

export function buildQuery(query?: Query): string {
  if (!query) return "";
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null) continue;
    params.append(key, String(value));
  }
  const s = params.toString();
  return s ? `?${s}` : "";
}

/** Exponential backoff with jitter, but honour Retry-After when sent. */
export function backoffMs(attempt: number, retryAfter: string | null): number {
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds >= 0)
      return Math.min(seconds * 1000, MAX_BACKOFF_MS);
    const date = Date.parse(retryAfter);
    if (!Number.isNaN(date))
      return Math.min(Math.max(0, date - Date.now()), MAX_BACKOFF_MS);
  }
  const base = 250 * 2 ** attempt;
  return Math.min(base + Math.random() * base * 0.25, MAX_BACKOFF_MS);
}

function retryAfterSeconds(value: string | null): number | null {
  if (!value) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Pull a human message out of the API's several error shapes. */
function messageOf(body: unknown, fallback: string): string {
  if (body && typeof body === "object") {
    const b = body as Record<string, unknown>;
    if (typeof b.error === "string") return b.error;
    // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
    if (b.error && typeof b.error === "object") {
      const m = (b.error as Record<string, unknown>).message;
      if (typeof m === "string") return m;
    }
    if (typeof b.message === "string") return b.message;
  }
  if (typeof body === "string" && body.trim()) return body.trim().slice(0, 500);
  return fallback;
}

function codeOf(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  if (typeof b.code === "string") return b.code;
  if (b.error && typeof b.error === "object") {
    const c = (b.error as Record<string, unknown>).code;
    if (typeof c === "string") return c;
  }
  return null;
}

/** True when a body is the `@misar/upsell` plan-limit refusal. */
export function isPlanLimitBody(body: unknown): boolean {
  return (
    !!body &&
    typeof body === "object" &&
    (body as Record<string, unknown>).code === "plan_limit_exceeded"
  );
}

/** Map an error response to the right typed error. Plan limits first, by `code`. */
export function errorFor(
  status: number,
  headers: Headers,
  body: unknown,
  statusText = "",
): MisarDevError {
  const requestId = headers.get("x-request-id");
  const message = messageOf(body, statusText || `HTTP ${status}`);
  const code = codeOf(body);

  if (isPlanLimitBody(body)) {
    const offer = ((body as Record<string, unknown>).upgrade ??
      null) as UpgradeOffer | null;
    return new PlanLimitError(
      status,
      message,
      body,
      requestId,
      offer,
      retryAfterSeconds(headers.get("retry-after")),
    );
  }
  switch (true) {
    case status === 400 || status === 422:
      return new ValidationError(status, message, code, body, requestId);
    case status === 401:
      return new AuthenticationError(status, message, code, body, requestId);
    case status === 403:
      return new PermissionDeniedError(status, message, code, body, requestId);
    case status === 404:
      return new NotFoundError(status, message, code, body, requestId);
    case status === 409:
      return new ConflictError(status, message, code, body, requestId);
    case status === 429:
      return new RateLimitError(
        status,
        message,
        code,
        body,
        requestId,
        retryAfterSeconds(headers.get("retry-after")),
      );
    case status >= 500:
      return new ServerError(status, message, code, body, requestId);
    default:
      return new MisarDevError(status, message, code, body, requestId);
  }
}

async function readBody(res: Response): Promise<unknown> {
  if (res.status === 204) return null;
  const text = await res.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(t);
      reject(signal.reason ?? new Error("aborted"));
    });
  });
}

export class Transport {
  readonly baseURL: string;
  readonly maxRetries: number;
  readonly timeoutMs: number;
  private readonly apiKey: string;
  private readonly extraHeaders: Record<string, string>;
  private readonly fetchImpl: typeof fetch;

  constructor(apiKey?: string, options: ClientOptions = {}) {
    const key = apiKey ?? env("MISARDEV_API_KEY");
    if (!key) {
      throw new MisarDevError(
        0,
        "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. " +
          "Create one at https://www.misar.dev/settings/api-keys.",
        "missing_api_key",
      );
    }
    this.apiKey = key;
    this.baseURL = (
      options.baseURL ??
      env("MISARDEV_BASE_URL") ??
      DEFAULT_BASE_URL
    ).replace(/\/+$/, "");
    this.maxRetries = Math.max(1, options.maxRetries ?? 3);
    this.timeoutMs = options.timeoutMs ?? 60_000;
    this.extraHeaders = options.headers ?? {};
    const f = options.fetch ?? (globalThis.fetch as typeof fetch | undefined);
    if (!f)
      throw new MisarDevError(
        0,
        "No fetch implementation available; pass options.fetch.",
        "no_fetch",
      );
    this.fetchImpl = f.bind(globalThis);
  }

  private headers(
    accept: string,
    extra?: Record<string, string>,
  ): Record<string, string> {
    return {
      Authorization: `Bearer ${this.apiKey}`,
      Accept: accept,
      "Content-Type": "application/json",
      "X-Misar-SDK": `misardev-typescript/${SDK_VERSION}`,
      ...this.extraHeaders,
      ...extra,
    };
  }

  /** Send one request, retrying throttles and (for idempotent verbs) transient failures. */
  async request<T = unknown>(
    method: string,
    path: string,
    options: RequestOptions = {},
  ): Promise<T> {
    const url = `${this.baseURL}${path}${buildQuery(options.query)}`;
    const verb = method.toUpperCase();

    for (let attempt = 0; ; attempt++) {
      const last = attempt >= this.maxRetries - 1;
      const controller = new AbortController();
      const timer = setTimeout(
        () => controller.abort(new Error("timeout")),
        this.timeoutMs,
      );
      const onAbort = () => controller.abort(options.signal?.reason);
      options.signal?.addEventListener("abort", onAbort);

      let res: Response;
      try {
        res = await this.fetchImpl(url, {
          method: verb,
          headers: this.headers("application/json", options.headers),
          body:
            options.body !== undefined
              ? JSON.stringify(options.body)
              : undefined,
          signal: controller.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        options.signal?.removeEventListener("abort", onAbort);
        if (options.signal?.aborted) throw err;
        if (!last && IDEMPOTENT.has(verb)) {
          await sleep(backoffMs(attempt, null), options.signal);
          continue;
        }
        throw new NetworkError(
          err instanceof Error ? err.message : "Network error",
          err,
        );
      }
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", onAbort);

      if (res.ok) return (await readBody(res)) as T;

      // Read the body BEFORE deciding to retry: a 429 from the rate limiter and
      // a 429 from a spent plan allowance share a status, and only the first is
      // worth retrying.
      const body = await readBody(res);
      const error = errorFor(res.status, res.headers, body, res.statusText);
      if (error instanceof PlanLimitError) throw error;

      const retryable =
        RETRYABLE.has(res.status) &&
        (res.status === 429 || IDEMPOTENT.has(verb));
      if (retryable && !last) {
        await sleep(
          backoffMs(attempt, res.headers.get("retry-after")),
          options.signal,
        );
        continue;
      }
      throw error;
    }
  }

  /**
   * Open a Server-Sent Events stream and yield each event.
   *
   * Never retried: a stream that fails mid-flight cannot be replayed without
   * duplicating what the caller already consumed. A `{type:"error", code:
   * "plan_limit_exceeded", upgrade}` frame is raised as a {@link PlanLimitError},
   * exactly as the same refusal on a plain request would be.
   */
  async *stream<T = unknown>(
    method: string,
    path: string,
    options: RequestOptions & { terminator?: string | null } = {},
  ): AsyncGenerator<SSEEvent<T>, void, unknown> {
    const url = `${this.baseURL}${path}${buildQuery(options.query)}`;
    let res: Response;
    try {
      res = await this.fetchImpl(url, {
        method: method.toUpperCase(),
        headers: this.headers("text/event-stream", options.headers),
        body:
          options.body !== undefined ? JSON.stringify(options.body) : undefined,
        signal: options.signal,
      });
    } catch (err) {
      throw new NetworkError(
        err instanceof Error ? err.message : "Network error",
        err,
      );
    }

    if (!res.ok) {
      const body = await readBody(res);
      throw errorFor(res.status, res.headers, body, res.statusText);
    }
    if (!res.body) return;

    for await (const event of parseSSE<T>(
      res.body,
      options.terminator ?? "[DONE]",
    )) {
      // Other error frames are the stream's own business (the build stream
      // reports a failed step and carries on), so only the plan refusal —
      // which no amount of reading further will fix — is raised.
      if (isPlanLimitBody(event.data))
        throw errorFor(402, res.headers, event.data);
      yield event;
    }
  }
}
