# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions come from git tags
(Packagist); `composer.json` carries none.

## [1.0.0] — 2026-10-16

First release as **`misarai/misardev-php`**, the package name every Misar.Dev SDK now follows.
It replaces the previous unpublished hand-written client (`misar-ai/misardev-php`,
`MisarDev\Client`), whose methods do not carry over — see below.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods, 3 streams (109
  operations) — generated from the API's route tree, so the client cannot drift from what
  the server serves.
- `PlanLimitError` carrying the full upgrade offer (`$offer`, `upgradeUrl()`, `feature()`,
  `currentPlan()`, `recommendedPlan()`, `$retryAfter`), detected by
  `code: "plan_limit_exceeded"` rather than by status.
- Typed errors per status: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError`, `NetworkError`, all extending `MisarDevError`.
- Server-Sent Events as PHP `Generator`s: `chat->completionsStream()`,
  `chat->studioStream()`, `projects->buildStream()`.
- `paginate()` for offset-paginated lists.
- `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` environment fallbacks; injectable
  `MisarDev\Core\HttpClient`.

### Changed

- Default base URL is `https://api.misar.io/dev`.
- Built on ext-curl alone; the Guzzle dependency is gone.
- Retries honour `Retry-After`; `POST`/`PATCH` are not retried after a server error, and a
  plan refusal is never retried.
