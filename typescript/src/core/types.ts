/** Per-call options every generated method accepts as its last argument. */
export interface CallOptions {
  /** Abort the call (and any pending retry). */
  signal?: AbortSignal;
  /** Extra headers for this call only. */
  headers?: Record<string, string>;
}
