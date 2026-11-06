# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-11-07

### Added

- The social API, generated from the route tree like everything else. New methods:
  - `dev.posts()`: `create`, `create_comment`, `get`, `like`, `list`, `list_comments`, `list_saved`, `save`, `share_to_dm`, `unlike`, `unsave`, `update`
  - `dev.comments()`: `delete`, `like`, `unlike`, `update`
  - `dev.feed()`: `following`, `for_you`
  - `dev.tags()`: `get`
  - `dev.collections()`: `add_post`, `create`, `delete`, `list`, `remove_post`, `update`
  - `dev.stories()`: `create`, `delete`, `get`, `list_my_posts`, `list_viewers`, `mark_seen`, `reply`, `tray`
  - `dev.highlights()`: `add_story`, `create`, `delete`, `list`, `remove_story`, `update`
  - `dev.close_friends()`: `add`, `list`, `remove`
  - `dev.dm()`: `accept_thread`, `create_thread`, `decline_thread`, `list_messages`, `list_threads`, `mark_thread_read`, `send_message`, `unread_counts`
  - `dev.social()`: `dismiss_suggestion`, `list_suggestions`, `relationship`
  - `dev.profile()`: `block`, `mute`, `unblock`, `unmute`
- Routes that had landed without reaching the manifest:
  - `dev.domains()`: `checkout`, `create_dns_record`, `delete_dns_record`, `list`, `list_dns_records`, `search`, `update`
  - `dev.projects()`: `recommend_domains`
- `dev.search().code` now takes the `cursor` and `type` query parameters the route already read.
- The surface is now 31 resources, 179 methods and 3 streams (182 operations).

### Notes

- `dev.posts().list`, `dev.posts().get`, `dev.posts().list_comments`, `dev.tags().get` and `dev.feed().for_you` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

## [1.0.0] — 2026-10-16

First release under the `misardev` crate name. It replaces the previous
unpublished hand-written `misar_dev` client, whose types and method set it does
not keep.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3
  Server-Sent Events streams (109 operations) — generated from the API's own
  route tree and reached as `dev.<resource>().<method>(…)`, `serde_json::Value`
  in and out.
- `MisarDev::new`, `MisarDev::from_env` and `MisarDev::builder()` with
  `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` fallbacks, base URL, max retries,
  timeout, extra headers and an injectable `reqwest::Client`. rustls TLS, no
  OpenSSL.
- `MisarDevError` with a variant per failure kind — `Validation`,
  `Authentication`, `PermissionDenied`, `NotFound`, `Conflict`, `RateLimit`,
  `Server`, `Network`, `Api` — and `PlanLimit`, carrying the server's full
  upgrade offer with `upgrade_url()`, `feature()`, `current_plan()`,
  `recommended_plan()` and `retry_after`.
- Retries for throttles (any verb) and transient failures (idempotent verbs
  only), honouring `Retry-After` and never retrying a plan refusal.
- SSE streaming as an `EventStream` of `SseEvent { event, data, id }` for chat
  completions, the studio conversation and build progress.
- `paginate` for offset-paginated list endpoints.
