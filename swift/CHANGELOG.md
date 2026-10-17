# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Swift Package Manager resolves
versions from git tags, so the version lives in the tag, not in `Package.swift`.

## [1.0.0] — 2026-10-16

First release of the `MisarDev` Swift package. It replaces the previous unpublished
hand-written MisarDev Swift client, which covered only a handful of routes and built on
Apple platforms only.

### Added

- Every route in `sdks/manifest.json` — 21 resource groups, 106 methods and 3 Server-Sent
  Events streams (109 operations) — generated from the API's own route tree and attached
  to `MisarDevClient` as properties (`dev.projects`, `dev.templates`, `dev.chat`, …).
  Each method is `async throws` and returns a `JSONValue`.
- Authentication with an account API key (`mdk_…`) sent as `Authorization: Bearer`, read
  from the initializer or `MISARDEV_API_KEY`; `MISARDEV_BASE_URL` overrides the base URL.
- A typed `PlanLimitError` thrown whenever the body carries `code: "plan_limit_exceeded"`
  (402 `feature_locked` or 429 `quota_exhausted`), carrying the full upgrade offer as
  `offer` plus `upgradeUrl`, `feature`, `currentPlan`, `recommendedPlan` and `retryAfter`.
- Typed errors for every other failure: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError` and `NetworkError`, all subclasses of `MisarDevError` with `status`,
  `code`, `body` and `requestId`.
- Retries for 429 on any method and for 5xx and network failures on idempotent methods,
  with exponential backoff that honours `Retry-After` (seconds or HTTP-date, capped at
  60 s). Plan refusals are never retried.
- SSE streaming as `AsyncThrowingStream<SSEEvent, Error>` for `chat.completionsStream`
  (sets `stream: true`, ends at `[DONE]`), `chat.studioStream` and
  `projects.buildStream`. Streams are never retried; a plan-limit frame throws
  `PlanLimitError`.
- `paginate` helper that walks offset-paginated lists.
- Builds on macOS, iOS, tvOS, watchOS and Linux (`FoundationNetworking`), using
  completion-handler and delegate `URLSession` APIs that exist on every platform.
