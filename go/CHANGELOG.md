# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are tagged
`go/vX.Y.Z` on https://github.com/Misar-AI/misardev-sdks.

## [1.0.0] — 2026-10-16

First release under the `misardev` name, at `github.com/Misar-AI/misardev-sdks/go`.
It replaces the previous unpublished hand-written `misardev-go` client, whose
types and method set it does not keep.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3
  Server-Sent Events streams (109 operations) — generated from the API's own
  route tree, each method taking a `context.Context` first and returning the
  decoded JSON.
- `NewClient(apiKey, opts...)` with `MISARDEV_API_KEY` / `MISARDEV_BASE_URL`
  fallbacks and `WithBaseURL`, `WithMaxRetries`, `WithTimeout`,
  `WithHTTPClient`, `WithHeader` options; `WithCallHeader` per call.
- Typed errors embedding `*APIError`: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError`, `NetworkError`, and `PlanLimitError` carrying the server's full
  upgrade offer with `UpgradeURL`, `Feature`, `CurrentPlan`, `RecommendedPlan`
  and `RetryAfter`.
- Retries for throttles (any verb) and transient failures (idempotent verbs
  only), honouring `Retry-After` and never retrying a plan refusal.
- SSE streaming via `*Stream` (`Next` / `Event` / `Err` / `Close`) for chat
  completions, the studio conversation and build progress.
- `Paginate` for offset-paginated list endpoints, and `As[T]` to convert a
  decoded response into your own type.
