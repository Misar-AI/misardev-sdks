# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
