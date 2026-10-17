# Changelog

All notable changes to this CLI are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
