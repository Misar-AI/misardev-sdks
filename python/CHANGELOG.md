# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-11-07

### Added

- The social API, generated from the route tree like everything else. New methods:
  - `dev.posts`: `create`, `create_comment`, `get`, `like`, `list`, `list_comments`, `list_saved`, `save`, `share_to_dm`, `unlike`, `unsave`, `update`
  - `dev.comments`: `delete`, `like`, `unlike`, `update`
  - `dev.feed`: `following`, `for_you`
  - `dev.tags`: `get`
  - `dev.collections`: `add_post`, `create`, `delete`, `list`, `remove_post`, `update`
  - `dev.stories`: `create`, `delete`, `get`, `list_my_posts`, `list_viewers`, `mark_seen`, `reply`, `tray`
  - `dev.highlights`: `add_story`, `create`, `delete`, `list`, `remove_story`, `update`
  - `dev.close_friends`: `add`, `list`, `remove`
  - `dev.dm`: `accept_thread`, `create_thread`, `decline_thread`, `list_messages`, `list_threads`, `mark_thread_read`, `send_message`, `unread_counts`
  - `dev.social`: `dismiss_suggestion`, `list_suggestions`, `relationship`
  - `dev.profile`: `block`, `mute`, `unblock`, `unmute`
- Routes that had landed without reaching the manifest:
  - `dev.domains`: `checkout`, `create_dns_record`, `delete_dns_record`, `list`, `list_dns_records`, `search`, `update`
  - `dev.projects`: `recommend_domains`
- `dev.search.code` now takes the `cursor` and `type` query parameters the route already read.
- `dev.profile`: `get_highlight` — one profile highlight's stories, ready to play, read when its circle is opened. `list_highlights` now answers the circles only (`id`, `title`, `coverUrl`, `createdAt`, `storyCount`, `closeFriends`), without stories.
- The surface is now 31 resources, 180 methods and 3 streams (183 operations).

### Notes

- `dev.posts.list`, `dev.posts.get`, `dev.posts.list_comments`, `dev.tags.get` and `dev.feed.for_you` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

## [1.0.0] — 2026-10-16

First release under the `misardev` name on PyPI. Replaces the previous unpublished 0.x
`misar-dev` client (async-only, flat `projects_list`-style methods), which is removed.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3 SSE streams, 109
  operations — generated from the API's route tree, each with an `a`-prefixed async twin on
  the same `MisarDev` client.
- Typed errors: `MisarDevError` with `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`, `ServerError`,
  `NetworkError` and `PlanLimitError`, each carrying status, message, code, body and request id.
- `PlanLimitError` carrying the full upgrade offer (`offer`) plus `upgrade_url`, `feature`,
  `current_plan`, `recommended_plan` and `retry_after`, detected by `code: "plan_limit_exceeded"`
  for both `402 feature_locked` and `429 quota_exhausted`.
- Retries honouring `Retry-After` (seconds or HTTP-date, capped at 60 s) with exponential
  backoff otherwise; `429` retried on any verb, 5xx and network errors only on idempotent verbs;
  plan refusals never retried.
- SSE streaming for chat completions (`[DONE]`-terminated, `stream: true` set for you), the
  studio chat stream and the project build stream.
- `paginate` / `apaginate` offset-pagination helpers.
- API key fallback to `MISARDEV_API_KEY`, base URL override via `MISARDEV_BASE_URL`, and
  injectable `httpx` clients or transports.
