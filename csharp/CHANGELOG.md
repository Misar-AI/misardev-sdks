# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release under the `MisarDev` name on NuGet. It replaces the previous unpublished
hand-written MisarDev .NET client, which covered only a handful of routes.

### Added

- Every route in `sdks/manifest.json` — 21 resource groups, 106 methods and 3 Server-Sent
  Events streams (109 operations) — generated from the API's own route tree and attached
  to `MisarDevClient` as properties (`dev.Projects`, `dev.Templates`, `dev.Chat`, …).
  Each method returns `Task<JsonNode?>` and takes an optional `CancellationToken`.
- Authentication with an account API key (`mdk_…`) sent as `Authorization: Bearer`, read
  from the constructor or `MISARDEV_API_KEY`; `MISARDEV_BASE_URL` overrides the base URL.
- A typed `PlanLimitException` raised whenever the body carries
  `code: "plan_limit_exceeded"` (402 `feature_locked` or 429 `quota_exhausted`), carrying
  the full upgrade offer as `Offer` plus `UpgradeUrl`, `Feature`, `CurrentPlan`,
  `RecommendedPlan` and `RetryAfter`.
- Typed exceptions for every other failure: `ValidationException`,
  `AuthenticationException`, `PermissionDeniedException`, `NotFoundException`,
  `ConflictException`, `RateLimitException`, `ServerException` and `NetworkException`, all
  deriving from `MisarDevException` with `Status`, `Code`, `Body` and `RequestId`.
- Retries for 429 on any method and for 5xx and network failures on idempotent methods,
  with exponential backoff that honours `Retry-After` (seconds or HTTP-date, capped at
  60 s). Plan refusals are never retried.
- SSE streaming as `IAsyncEnumerable<SseEvent>` for `Chat.CompletionsStream` (sets
  `stream: true`, ends at `[DONE]`), `Chat.StudioStream` and `Projects.BuildStream`.
  Streams are never retried; a plan-limit frame throws `PlanLimitException`.
- `Paginate` / `Pagination.Paginate` helper that walks offset-paginated lists.
- `RequestAsync` and `StreamAsync` escape hatches for any route.
