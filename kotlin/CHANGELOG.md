# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
