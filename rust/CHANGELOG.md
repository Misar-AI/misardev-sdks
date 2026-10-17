# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release under the `misardev` crate name. It replaces the previous
unpublished hand-written `misar_dev` client, whose types and method set it does
not keep.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3
  Server-Sent Events streams (109 operations) — generated from the API's own
  route tree and reached as `dev.<resource>().<method>(…)`, `serde_json::Value`
  in and out.
- `MisarDev::new`, `MisarDev::from_env` and `MisarDev::builder()` with
  `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` fallbacks, base URL, max retries,
  timeout, extra headers and an injectable `reqwest::Client`. rustls TLS, no
  OpenSSL.
- `MisarDevError` with a variant per failure kind — `Validation`,
  `Authentication`, `PermissionDenied`, `NotFound`, `Conflict`, `RateLimit`,
  `Server`, `Network`, `Api` — and `PlanLimit`, carrying the server's full
  upgrade offer with `upgrade_url()`, `feature()`, `current_plan()`,
  `recommended_plan()` and `retry_after`.
- Retries for throttles (any verb) and transient failures (idempotent verbs
  only), honouring `Retry-After` and never retrying a plan refusal.
- SSE streaming as an `EventStream` of `SseEvent { event, data, id }` for chat
  completions, the studio conversation and build progress.
- `paginate` for offset-paginated list endpoints.
