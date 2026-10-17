# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release under the `misardev` name on pub.dev. Replaces the previous unpublished
`misar_dev` client, which covered a handful of routes by hand.

### Added

- Every route in `sdks/manifest.json` — 21 resource groups, 106 methods and 3 Server-Sent
  Events streams (109 operations), generated from the API's own route tree so the client
  cannot drift from the server.
- `MisarDev` client: API key from `apiKey:` or `MISARDEV_API_KEY`, base URL from `baseUrl:` or
  `MISARDEV_BASE_URL`, configurable retries and timeout, injectable `http.Client`.
- Typed errors: `MisarDevError` with `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`, `ServerError`,
  `NetworkError` and `PlanLimitError`.
- `PlanLimitError` carrying the server's full upgrade offer (`offer`), plus `upgradeUrl`,
  `feature`, `currentPlan`, `recommendedPlan` and `retryAfter`. Detected by
  `code: "plan_limit_exceeded"`, never by status.
- Retries for `429` and, on idempotent requests only, `5xx` and network failures — honouring
  `Retry-After` (seconds or HTTP-date, capped at 60 s), with exponential backoff otherwise.
  Plan refusals are never retried.
- SSE streaming as `Stream<SseEvent>` for chat completions, the studio conversation and
  build progress; `[DONE]` handled for you, plan-limit frames raised as `PlanLimitError`.
- `paginate` helper for offset-paginated list endpoints.
