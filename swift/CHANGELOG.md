# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Swift Package Manager resolves
versions from git tags, so the version lives in the tag, not in `Package.swift`.

## [1.1.0] — 2026-11-07

### Added

- The social API, generated from the route tree like everything else. New methods:
  - `dev.posts`: `create`, `createComment`, `get`, `like`, `list`, `listComments`, `listSaved`, `save`, `shareToDm`, `unlike`, `unsave`, `update`
  - `dev.comments`: `delete`, `like`, `unlike`, `update`
  - `dev.feed`: `following`, `forYou`
  - `dev.tags`: `get`
  - `dev.collections`: `addPost`, `create`, `delete`, `list`, `removePost`, `update`
  - `dev.stories`: `create`, `delete`, `get`, `listMyPosts`, `listViewers`, `markSeen`, `reply`, `tray`
  - `dev.highlights`: `addStory`, `create`, `delete`, `list`, `removeStory`, `update`
  - `dev.closeFriends`: `add`, `list`, `remove`
  - `dev.dm`: `acceptThread`, `createThread`, `declineThread`, `listMessages`, `listThreads`, `markThreadRead`, `sendMessage`, `unreadCounts`
  - `dev.social`: `dismissSuggestion`, `listSuggestions`, `relationship`
  - `dev.profile`: `block`, `mute`, `unblock`, `unmute`
- Routes that had landed without reaching the manifest:
  - `dev.domains`: `checkout`, `createDnsRecord`, `deleteDnsRecord`, `list`, `listDnsRecords`, `search`, `update`
  - `dev.projects`: `recommendDomains`
- `dev.search.code` now takes the `cursor` and `type` query parameters the route already read.
- The surface is now 31 resources, 179 methods and 3 streams (182 operations).

### Notes

- `dev.posts.list`, `dev.posts.get`, `dev.posts.listComments`, `dev.tags.get` and `dev.feed.forYou` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

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
