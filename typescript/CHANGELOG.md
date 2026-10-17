# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release as **`@misardev/sdk`**, the package name every Misar.Dev SDK now follows.

> **`@misar/dev` is deprecated.** The 0.x client was published under `@misar/dev`; it will
> receive no further releases. Install `@misardev/sdk` instead. `MisarDevClient` is kept as an
> alias of `MisarDev` so existing imports compile, but the resource methods have changed —
> see below.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods, 3 streams — generated
  from the API's route tree, so the client cannot drift from what the server serves.
- `PlanLimitError` carrying the full upgrade offer (`offer`, `upgradeUrl`, `feature`,
  `currentPlan`, `recommendedPlan`, `retryAfter`), detected by `code: "plan_limit_exceeded"`
  rather than by status.
- Typed errors per status: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError`, `NetworkError`.
- Server-Sent Events: `chat.completionsStream`, `chat.studioStream`, `projects.buildStream`.
- `paginate()` for offset-paginated lists.
- `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` environment fallbacks; injectable `fetch`.

### Changed

- Default base URL is `https://api.misar.io/dev`.
- Retries honour `Retry-After`; `POST`/`PATCH` are no longer retried after a server error,
  and a plan refusal is never retried.

### Removed

- Methods for staff-only and service routes (`admin/*`, `internal/*`, maintenance, health)
  — they were never usable with an account key.
