# MisarDev CLI

> Misar.Dev from the terminal — create, build and deploy projects, write files, start from templates, search code and stream chat completions, one command per API route.

[![npm](https://img.shields.io/npm/v/@misardev/cli)](https://www.npmjs.com/package/@misardev/cli)
[![node](https://img.shields.io/badge/node-%3E%3D18-blue)](https://www.npmjs.com/package/@misardev/cli)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resources · 106 commands · 3 streaming commands · built on [`@misardev/sdk`](https://www.npmjs.com/package/@misardev/sdk)**

Misar.Dev builds, hosts and deploys apps. The `misardev` CLI exposes its whole API as
commands: every route in the API is a `misardev <resource> <method>` command, generated from
the same route manifest as the SDKs, so the CLI never lags the API. Results print as JSON, so
the output pipes straight into `jq` and scripts.

---

## Install

### npm

```bash
npm install -g @misardev/cli
```

### npx (no install)

```bash
npx @misardev/cli projects list
```

### pnpm

```bash
pnpm add -g @misardev/cli
```

### yarn

```bash
yarn global add @misardev/cli
```

### bun

```bash
bun add -g @misardev/cli
```

Requires Node.js 18 or newer. The binary is called `misardev`.

---

## Authentication

Every command authenticates with an account API key (`mdk_…`). Create one at
https://www.misar.dev/settings/api-keys, then either export it or pass it per command:

```bash
export MISARDEV_API_KEY=mdk_...
misardev projects list

misardev --api-key mdk_... projects list
```

`--api-key` wins over `MISARDEV_API_KEY`. Without either, the CLI stops before calling the API
and points you at the API-key page. The key is sent as `Authorization: Bearer <key>` and is
never printed — not in output, not in error messages.

What a key may do is decided **server-side** from the plan behind it. When the plan does not
cover a command, the API refuses with an upgrade offer and the CLI renders it as an upgrade card
(see [Plan limits](#plan-limits)). Plan refusals are never retried.

---

## Resources

Every command has the same shape:

```text
misardev <resource> <method> [path-params...] [required-query...] [--body <json|@file>] [--query key=value ...] [--json]
```

- **Path parameters** and **required query parameters** are positional, in that order
  (`misardev projects check-subdomain <id> <value>`). They are URL-encoded for you.
- **`--body`** (commands that send a body) takes inline JSON, `@path/to/file.json`, or `@-` for
  stdin. Omitted, an empty object is sent.
- **`--query key=value`** (commands with optional query parameters) is repeatable. Unknown keys
  are rejected before anything is sent; `misardev <resource> <method> --help` lists the keys.
- **`--json`** prints compact one-line JSON (and, for streams, one JSON event per line).

`misardev <resource> --help` lists a resource's commands with the route each one calls.

### Build and ship

| Resource               | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | What it covers                                                                                                                 |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `misardev projects`    | `add-collaborator`, `archive`, `build-status`, `cancel-build`, `check-subdomain`, `create`, `create-conversation`, `delete`, `delete-env`, `delete-skills`, `deploy`, `duplicate`, `export`, `get`, `get-backend`, `get-deployment`, `get-domain`, `get-env`, `get-knowledge`, `get-skills`, `get-tools`, `import-artifact`, `list`, `list-checkpoints`, `list-collaborators`, `list-conversations`, `list-files`, `provision-backend`, `remove-collaborator`, `remove-domain`, `restore`, `set-domain`, `undeploy`, `update`, `update-env`, `update-knowledge`, `update-skills`, `update-subdomain`, `update-tools`, `write-files`, `build-stream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `misardev templates`   | `create`, `delete`, `get`, `list`, `remix`, `update`, `use`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `misardev checkpoints` | `delete`, `restore`, `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Saved project snapshots: rename, restore, delete.                                                                              |
| `misardev builds`      | `list`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Recent builds across your projects.                                                                                            |

### AI

| Resource          | Methods                                              | What it covers                                                                                    |
| ----------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `misardev chat`   | `completions`, `studio-stream`, `completions-stream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `misardev search` | `code`, `web`                                        | Web-grounded answers with citations, and search across your own code.                             |
| `misardev rag`    | `clear`, `index`, `search`                           | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource              | Methods                                                                                                                             | What it covers                                                              |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `misardev connectors` | `available`, `create-connection`, `delete-connection`, `list`, `list-connections`, `test-connection`, `toggle`, `update-connection` | Connector catalogue, per-account enable state, and per-project connections. |
| `misardev github`     | `disconnect`, `get-connection`                                                                                                      | The linked GitHub account: read it or disconnect it.                        |
| `misardev skills`     | `get`, `list`                                                                                                                       | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource                 | Methods                                                                                                                                               | What it covers                                |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `misardev organizations` | `accept-invitation`, `create`, `create-invitation`, `list`, `list-invitations`, `list-members`, `remove-member`, `revoke-invitation`, `update-member` | Organizations, members and invitations.       |
| `misardev gallery`       | `like`, `list`, `unlike`                                                                                                                              | The public community gallery, and likes.      |
| `misardev profile`       | `follow`, `get`, `unfollow`                                                                                                                           | Public builder profiles, follow and unfollow. |
| `misardev notifications` | `list`, `mark-all-read`, `mark-read`                                                                                                                  | In-app notifications and read state.          |
| `misardev reports`       | `create`                                                                                                                                              | Report abusive content.                       |

### Account, plan and billing

| Resource            | Methods                                                          | What it covers                                                         |
| ------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `misardev account`  | `create-key`, `delete-key`, `export`, `list-keys`, `update-key`  | Account API keys (with expiry and IP allowlists) and your data export. |
| `misardev api-keys` | `create`, `delete`, `list`                                       | API keys — create, list, revoke.                                       |
| `misardev usage`    | `list`, `plan`, `track`                                          | Usage for a period, your plan's allowances, and usage events.          |
| `misardev billing`  | `checkout`, `comparison`, `plans`, `subscription`, `switch-plan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `misardev audit`    | `list`                                                           | Your account's audit log.                                              |
| `misardev domains`  | `lookup`                                                         | Custom-domain availability lookup.                                     |

---

## Client

The CLI is a thin layer over [`@misardev/sdk`](https://www.npmjs.com/package/@misardev/sdk):
each command is exactly one SDK call, `dev.<resource>.<method>(...)`.

| Thing              | Detail                                                                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--api-key <key>`  | Account API key. Default: `MISARDEV_API_KEY`.                                                                                                                                                                             |
| `--base-url <url>` | API base URL. Default: `MISARDEV_BASE_URL`, else `https://api.misar.io/dev`.                                                                                                                                              |
| Timeout            | 60 s per attempt — builds and AI calls are slow.                                                                                                                                                                          |
| Retries            | Up to 3 attempts in total.                                                                                                                                                                                                |
| Retried            | `429` on any command; `500`, `502`, `503`, `504` and network failures only on idempotent verbs (`GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`). Backoff honours `Retry-After` (capped at 60 s), else 250 ms × 2ⁿ with jitter. |
| Never retried      | Plan refusals (`code: "plan_limit_exceeded"`), streams, and a 5xx or dropped connection on `POST`/`PATCH` (it may already have done its work).                                                                            |
| Output             | Pretty JSON on stdout; `--json` for compact JSON. An empty (`204`) answer prints nothing.                                                                                                                                 |
| Errors             | On stderr, with exit codes `0` success, `1` error, `2` blocked by your plan.                                                                                                                                              |
| Header             | `X-Misar-SDK: misardev-cli/1.0.0` on every request.                                                                                                                                                                       |

---

## Quick start

```bash
npm install -g @misardev/cli
export MISARDEV_API_KEY=mdk_...

misardev projects create --body '{"name":"my-app","description":"A landing page"}'
misardev projects list
```

---

## Primary functions

### Create a project

```bash
misardev projects create --body '{"name":"my-app","description":"Marketing site"}'
```

### Write files

```bash
misardev projects write-files <project-id> --body '{"files":[{"path":"index.html","content":"<h1>Hello</h1>"}]}'

# or from a file
misardev projects write-files <project-id> --body @files.json
```

### Deploy

```bash
misardev projects deploy <project-id> --body '{"subdomain":"my-app"}'
misardev projects get-deployment <project-id>
```

Check a subdomain first — the path parameter and the required `value` are both positional:

```bash
misardev projects check-subdomain <project-id> my-app
```

### List templates and start from one

```bash
misardev templates list --query category=saas --query limit=10
misardev templates use <template-id> --body '{"projectName":"from-template"}'
```

### OpenAI-compatible chat completion

```bash
misardev chat completions --body '{"messages":[{"role":"user","content":"Write a haiku about deploys"}]}'
```

### Streamed completion

```bash
misardev chat completions-stream --body '{"messages":[{"role":"user","content":"Explain SSE in one paragraph"}]}'
```

The reply prints as it arrives. `stream: true` is set for you.

### Code search

```bash
misardev search code --query q=useEffect --query limit=20
```

### Read usage and plan

```bash
misardev usage                       # same as: misardev usage list
misardev usage list --query days=7
misardev usage plan
```

Every result is JSON, so it composes with `jq`:

```bash
misardev projects list --json | jq -r '.projects[].id'
```

---

## Errors

Errors go to stderr as `Error (HTTP <status>): <message> [<code>]`, plus the request id when the
API sends one (quote it to support). The CLI maps the SDK's typed errors like this:

| SDK error               | When                                                               | Exit code |
| ----------------------- | ------------------------------------------------------------------ | --------- |
| `ValidationError`       | `400` / `422` — malformed request or failed validation             | `1`       |
| `AuthenticationError`   | `401` — key missing, revoked, expired, or not a Misar.Dev key      | `1`       |
| `PermissionDeniedError` | `403` — not allowed to touch this resource                         | `1`       |
| `NotFoundError`         | `404` — no such resource, or not one this key can see              | `1`       |
| `ConflictError`         | `409` — conflicts with current state, e.g. a build already running | `1`       |
| `RateLimitError`        | `429` throttle, after the retries ran out                          | `1`       |
| `ServerError`           | `5xx`, after retries on idempotent commands                        | `1`       |
| `NetworkError`          | No HTTP answer (DNS, TLS, reset, timeout)                          | `1`       |
| `PlanLimitError`        | The plan behind the key does not cover the command                 | `2`       |

Invalid `--body` JSON, an unknown `--query` key or a missing positional argument also exit `1`,
before any request is sent.

### Plan limits

A plan refusal carries `code: "plan_limit_exceeded"` and arrives with one of two statuses:

| Status | `upgrade.reason`  | Meaning                                                                           |
| ------ | ----------------- | --------------------------------------------------------------------------------- |
| `402`  | `feature_locked`  | The feature is not on your plan.                                                  |
| `429`  | `quota_exhausted` | The plan's allowance is spent for this period; `Retry-After` says when it resets. |

It is detected by `code`, never by status — so a spent quota is never mistaken for an ordinary
throttle and retried. The CLI prints an upgrade card built entirely from the server's offer
(`headline`, current plan, usage, each of `plans` with name, price and what it unlocks, `cta`,
and the upgrade URL — `urls.billing`, falling back to `urls.pricing`) and exits `2`:

```text
Upgrade required — Misar.Dev
────────────────────────────
API access isn't included in your Starter plan.
Current plan: Starter

Plans:
  • Pro — $29/mo  (recommended)
      unlocks: API access

Upgrade to Pro to continue.
Upgrade: https://www.misar.dev/settings/billing
```

In a script, branch on the exit code:

```bash
misardev projects deploy "$ID"
case $? in
  0) echo deployed ;;
  2) echo "plan does not cover deploys" ;;
  *) echo "deploy failed" ;;
esac
```

Programs that need the raw offer use [`@misardev/sdk`](https://www.npmjs.com/package/@misardev/sdk)
directly: `PlanLimitError.offer`, `upgradeUrl`, `feature`, `currentPlan`, `recommendedPlan`,
`retryAfter`.

---

## Streaming

Three commands stream Server-Sent Events:

| Command                               | Route                             | Prints                                                                               |
| ------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------ |
| `misardev chat completions-stream`    | `POST /v1/chat/completions`       | The reply text inline as it arrives; stops at `[DONE]`. Sets `stream: true` for you. |
| `misardev chat studio-stream`         | `POST /chat`                      | One line per event: `<event>: <data>`.                                               |
| `misardev projects build-stream <id>` | `GET /projects/{id}/build-stream` | One line per build event, until the server closes the stream.                        |

With `--json`, every stream prints one JSON object per event — `{"event","data","id"}` — for
piping into `jq` or another program. Streams are never retried: replaying one that failed
mid-flight would duplicate what was already printed. A plan refusal inside a stream renders the
same upgrade card and exits `2`.

```bash
misardev projects build-stream <project-id> --json | jq -c '.data'
```

---

## Pagination

List commands take their paging parameters through `--query`:

```bash
misardev templates list --query limit=50 --query offset=50
misardev api-keys list --query limit=20 --query offset=0
misardev projects list --query limit=20 --query cursor=<next-cursor>
```

To walk every page in a program, use `paginate()` from
[`@misardev/sdk`](https://www.npmjs.com/package/@misardev/sdk).

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- npm — https://www.npmjs.com/package/@misardev/cli

MIT © [Misar.AI](https://misar.io)
