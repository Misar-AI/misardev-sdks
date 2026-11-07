# Changelog

All notable changes to this CLI are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-11-07

### Added

- The social API, generated from the route tree like everything else. New commands:
  - `misardev posts`: `create`, `create-comment`, `get`, `like`, `list`, `list-comments`, `list-saved`, `save`, `share-to-dm`, `unlike`, `unsave`, `update`
  - `misardev comments`: `delete`, `like`, `unlike`, `update`
  - `misardev feed`: `following`, `for-you`
  - `misardev tags`: `get`
  - `misardev collections`: `add-post`, `create`, `delete`, `list`, `remove-post`, `update`
  - `misardev stories`: `create`, `delete`, `get`, `list-my-posts`, `list-viewers`, `mark-seen`, `reply`, `tray`
  - `misardev highlights`: `add-story`, `create`, `delete`, `list`, `remove-story`, `update`
  - `misardev close-friends`: `add`, `list`, `remove`
  - `misardev dm`: `accept-thread`, `create-thread`, `decline-thread`, `list-messages`, `list-threads`, `mark-thread-read`, `send-message`, `unread-counts`
  - `misardev social`: `dismiss-suggestion`, `list-suggestions`, `relationship`
  - `misardev profile`: `block`, `mute`, `unblock`, `unmute`
- Routes that had landed without reaching the manifest:
  - `misardev domains`: `checkout`, `create-dns-record`, `delete-dns-record`, `list`, `list-dns-records`, `search`, `update`
  - `misardev projects`: `recommend-domains`
- `misardev search code` now takes the `cursor` and `type` query parameters the route already read.
- `misardev profile`: `get-highlight` — one profile highlight's stories, ready to play, read when its circle is opened. `list-highlights` now answers the circles only (`id`, `title`, `coverUrl`, `createdAt`, `storyCount`, `closeFriends`), without stories.
- The surface is now 31 resources, 180 methods and 3 streams (183 operations).

### Notes

- `misardev posts list`, `misardev posts get`, `misardev posts list-comments`, `misardev tags get` and `misardev feed for-you` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

## [1.0.0] — 2026-10-16

First release under the `misardev` name, as `@misardev/cli`. It replaces the previous
unpublished `@misar/dev-cli`, which wrapped only `projects list`, `projects create` and `usage`.

### Added

- Every route in `sdks/manifest.json` as a command — 109 operations (106 methods and 3 SSE
  streams across 21 resources) — generated from the same manifest as the SDKs:
  `misardev <resource> <method> [path-params...] [required-query...] [--body <json|@file>] [--query key=value ...] [--json]`.
- Built on `@misardev/sdk`: one SDK call per command, so auth, retries and error typing are the
  SDK's.
- `--body` accepts inline JSON, `@file` or `@-` (stdin); `--query` is repeatable and checked
  against the route's accepted parameters before anything is sent.
- Global `--api-key` (else `MISARDEV_API_KEY`) and `--base-url` (else `MISARDEV_BASE_URL`, else
  `https://api.misar.io/dev`). The key is never printed, including when an error echoes it.
- Typed plan-limit handling: a `PlanLimitError` carrying the upgrade offer renders as an upgrade
  card (headline, current plan, usage, each plan's name, price and unlocks, call to action,
  upgrade URL) on stderr with exit code `2`; other errors print message, status, code and request
  id with exit code `1`.
- Retries honouring `Retry-After`, from the SDK: `429` on any command, `5xx` and network failures
  on idempotent verbs only; plan refusals are never retried.
- SSE streaming: `chat completions-stream` prints the reply inline and stops at `[DONE]`;
  `chat studio-stream` and `projects build-stream` print one line per event; `--json` prints one
  JSON event per line.
- Pagination through `--query limit=… --query offset=…` (or `cursor=…`) on list commands.
- `misardev usage` and `misardev projects list` keep working as before.
