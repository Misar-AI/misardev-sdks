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

First release under the `misardev` name, published to Maven Central as `io.misar:misardev-kotlin`. It
replaces the previous unpublished hand-written MisarDev Kotlin client (OkHttp + Gson, covering a small subset of routes).

### Added

- Every route in `sdks/manifest.json`: 21 resource groups, 106 methods and 3 Server-Sent
  Events streams — 109 operations in all, generated from the API's own route tree.
- `PlanLimitException`, raised whenever the body carries `code: "plan_limit_exceeded"`
  (402 `feature_locked` or 429 `quota_exhausted`), carrying the full upgrade offer plus
  `upgradeUrl`, `feature`, `currentPlan`, `recommendedPlan` and `retryAfter`.
- Typed errors for every other failure: validation, authentication, permission, not found,
  conflict, rate limit, server and network.
- Retries for 429 on any method and for 5xx / network failures on idempotent methods only,
  honouring `Retry-After` (seconds or HTTP-date, capped at 60 s), otherwise exponential
  backoff from 250 ms with jitter. Plan refusals are never retried.
- SSE streaming for `chat.completionsStream` (`POST /v1/chat/completions`, sets
  `stream: true`, ends at `[DONE]`), `chat.studioStream` (`POST /chat`) and
  `projects.buildStream` (`GET /projects/{id}/build-stream`).
- An offset pagination helper, `paginate`.
- API key from the constructor or `MISARDEV_API_KEY`; base URL from the constructor,
  `MISARDEV_BASE_URL`, or `https://api.misar.io/dev`.
- Every call is a `suspend fun` returning a Jackson `JsonNode?`, so array responses work; `204` returns `null`, a non-JSON body a `TextNode`.
- Streams return a cold `Flow<SseEvent>`, never retried; retries back off with `delay`, never blocking a thread.
- Java 11 bytecode on `java.net.http` with coroutines; no OkHttp or Gson.
