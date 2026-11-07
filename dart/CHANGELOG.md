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
- `dev.profile`: `getHighlight` — one profile highlight's stories, ready to play, read when its circle is opened. `listHighlights` now answers the circles only (`id`, `title`, `coverUrl`, `createdAt`, `storyCount`, `closeFriends`), without stories.
- The surface is now 31 resources, 180 methods and 3 streams (183 operations).

### Notes

- `dev.posts.list`, `dev.posts.get`, `dev.posts.listComments`, `dev.tags.get` and `dev.feed.forYou` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

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
