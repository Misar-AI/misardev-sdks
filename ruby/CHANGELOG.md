# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-16

First release as the **`misardev`** gem, the package name every Misar.Dev SDK now follows.
It replaces the previous unpublished hand-written `misar_dev` client (`require "misar_dev"`,
Faraday-based), whose methods do not carry over — see below.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods, 3 streams (109
  operations) — generated from the API's route tree, so the client cannot drift from what
  the server serves.
- `PlanLimitError` carrying the full upgrade offer (`offer`, `upgrade_url`, `feature`,
  `current_plan`, `recommended_plan`, `retry_after`), detected by
  `code: "plan_limit_exceeded"` rather than by status.
- Typed errors per status: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError`, `NetworkError`, all subclassing `MisarDevError`.
- Server-Sent Events, block-yielding or as an `Enumerator`: `chat.completions_stream`,
  `chat.studio_stream`, `projects.build_stream`.
- `paginate` for offset-paginated lists.
- `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` environment fallbacks; injectable `http_client:`.

### Changed

- Default base URL is `https://api.misar.io/dev`.
- Built on `net/http` alone; the Faraday dependency is gone. Requires Ruby 3.0+.
- Retries honour `Retry-After`; `POST`/`PATCH` are not retried after a server error, and a
  plan refusal is never retried.
