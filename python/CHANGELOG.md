# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release under the `misardev` name on PyPI. Replaces the previous unpublished 0.x
`misar-dev` client (async-only, flat `projects_list`-style methods), which is removed.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3 SSE streams, 109
  operations — generated from the API's route tree, each with an `a`-prefixed async twin on
  the same `MisarDev` client.
- Typed errors: `MisarDevError` with `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`, `ServerError`,
  `NetworkError` and `PlanLimitError`, each carrying status, message, code, body and request id.
- `PlanLimitError` carrying the full upgrade offer (`offer`) plus `upgrade_url`, `feature`,
  `current_plan`, `recommended_plan` and `retry_after`, detected by `code: "plan_limit_exceeded"`
  for both `402 feature_locked` and `429 quota_exhausted`.
- Retries honouring `Retry-After` (seconds or HTTP-date, capped at 60 s) with exponential
  backoff otherwise; `429` retried on any verb, 5xx and network errors only on idempotent verbs;
  plan refusals never retried.
- SSE streaming for chat completions (`[DONE]`-terminated, `stream: true` set for you), the
  studio chat stream and the project build stream.
- `paginate` / `apaginate` offset-pagination helpers.
- API key fallback to `MISARDEV_API_KEY`, base URL override via `MISARDEV_BASE_URL`, and
  injectable `httpx` clients or transports.
