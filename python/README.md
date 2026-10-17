# MisarDev Python SDK

> Build, ship and run apps on MisarDev from Python — sync and async, from the same client.

[![PyPI](https://img.shields.io/pypi/v/misardev)](https://pypi.org/project/misardev/)
[![python](https://img.shields.io/pypi/pyversions/misardev)](https://pypi.org/project/misardev/)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resources · 106 methods · 3 SSE streams · 109 operations, each with an async twin**

MisarDev turns a prompt into a deployed app. This SDK reaches every public route of its API: create and edit projects, write files, build and deploy them, start from templates, call the OpenAI-compatible chat endpoint, search your code, and read your usage and plan.

Every resource method has an `a`-prefixed async twin (`projects.list` / `projects.alist`) on the same client, so sync and async code share one object. Python 3.9+, `httpx` the only runtime dependency.

---

## Install

### pip

```bash
pip install misardev
```

### uv

```bash
uv add misardev
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the client, or set `MISARDEV_API_KEY` and
construct the client with no arguments.

Every call is checked server-side against the subscription attached to that key. There is no
client-side limit checking — the server decides, and the SDK surfaces its answer. A plan
refusal carries `code: "plan_limit_exceeded"`, raises `PlanLimitError`, and is **never retried**.

```python
import os
from misardev import MisarDev

dev = MisarDev(os.environ["MISARDEV_API_KEY"])
dev = MisarDev()  # same thing: reads MISARDEV_API_KEY
```

---

## Resources

Every resource the client exposes, and every method on it. Each method also has an
`a`-prefixed async twin — `projects.list` / `projects.alist`, `chat.completions_stream` /
`chat.acompletions_stream`.

Call shape: `resource.method(path_params..., required_query..., body=None, query=None, *, headers=None)`.
`body` exists only where the route reads a JSON body, `query` only where it takes optional
query parameters (a dict keyed by the API's own parameter names).

### Build and ship

| Resource          | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | What it covers                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `dev.projects`    | `add_collaborator`, `archive`, `build_status`, `cancel_build`, `check_subdomain`, `create`, `create_conversation`, `delete`, `delete_env`, `delete_skills`, `deploy`, `duplicate`, `export`, `get`, `get_backend`, `get_deployment`, `get_domain`, `get_env`, `get_knowledge`, `get_skills`, `get_tools`, `import_artifact`, `list`, `list_checkpoints`, `list_collaborators`, `list_conversations`, `list_files`, `provision_backend`, `remove_collaborator`, `remove_domain`, `restore`, `set_domain`, `undeploy`, `update`, `update_env`, `update_knowledge`, `update_skills`, `update_subdomain`, `update_tools`, `write_files`, `build_stream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `dev.templates`   | `create`, `delete`, `get`, `list`, `remix`, `update`, `use`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `dev.checkpoints` | `delete`, `restore`, `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Saved project snapshots: rename, restore, delete.                                                                              |
| `dev.builds`      | `list`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Recent builds across your projects.                                                                                            |

### AI

| Resource     | Methods                                              | What it covers                                                                                    |
| ------------ | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `dev.chat`   | `completions`, `studio_stream`, `completions_stream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `dev.search` | `code`, `web`                                        | Web-grounded answers with citations, and search across your own code.                             |
| `dev.rag`    | `clear`, `index`, `search`                           | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource         | Methods                                                                                                                             | What it covers                                                              |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `dev.connectors` | `available`, `create_connection`, `delete_connection`, `list`, `list_connections`, `test_connection`, `toggle`, `update_connection` | Connector catalogue, per-account enable state, and per-project connections. |
| `dev.github`     | `disconnect`, `get_connection`                                                                                                      | The linked GitHub account: read it or disconnect it.                        |
| `dev.skills`     | `get`, `list`                                                                                                                       | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource            | Methods                                                                                                                                               | What it covers                                |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `dev.organizations` | `accept_invitation`, `create`, `create_invitation`, `list`, `list_invitations`, `list_members`, `remove_member`, `revoke_invitation`, `update_member` | Organizations, members and invitations.       |
| `dev.gallery`       | `like`, `list`, `unlike`                                                                                                                              | The public community gallery, and likes.      |
| `dev.profile`       | `follow`, `get`, `unfollow`                                                                                                                           | Public builder profiles, follow and unfollow. |
| `dev.notifications` | `list`, `mark_all_read`, `mark_read`                                                                                                                  | In-app notifications and read state.          |
| `dev.reports`       | `create`                                                                                                                                              | Report abusive content.                       |

### Account, plan and billing

| Resource       | Methods                                                          | What it covers                                                         |
| -------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `dev.account`  | `create_key`, `delete_key`, `export`, `list_keys`, `update_key`  | Account API keys (with expiry and IP allowlists) and your data export. |
| `dev.api_keys` | `create`, `delete`, `list`                                       | API keys — create, list, revoke.                                       |
| `dev.usage`    | `list`, `plan`, `track`                                          | Usage for a period, your plan's allowances, and usage events.          |
| `dev.billing`  | `checkout`, `comparison`, `plans`, `subscription`, `switch_plan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `dev.audit`    | `list`                                                           | Your account's audit log.                                              |
| `dev.domains`  | `lookup`                                                         | Custom-domain availability lookup.                                     |

---

## Client

| Thing                                             | Detail                                                                                                                                                                                                                                         |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point                                       | `MisarDev(api_key=None, *, base_url=None, max_retries=3, timeout=60.0, headers=None, http_client=None, async_http_client=None, transport=None)` — every resource is an attribute on it.                                                        |
| `api_key`                                         | Falls back to `MISARDEV_API_KEY`; raises `MisarDevError` pointing at https://www.misar.dev/settings/api-keys when neither is set.                                                                                                              |
| `base_url`                                        | `MISARDEV_BASE_URL`, else `https://api.misar.io/dev`.                                                                                                                                                                                          |
| `max_retries`                                     | Total attempts for a retryable failure. Default `3`.                                                                                                                                                                                           |
| `timeout`                                         | Per-attempt timeout in seconds. Default `60`.                                                                                                                                                                                                  |
| `http_client` / `async_http_client` / `transport` | Inject your own `httpx.Client`, `httpx.AsyncClient`, or an httpx transport such as `httpx.MockTransport` for tests.                                                                                                                            |
| Async                                             | `await dev.projects.alist()` — an `a`-prefixed twin of every method and stream.                                                                                                                                                                |
| Retried                                           | `429` on any verb; `500`, `502`, `503`, `504` and network failures only on `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`. `Retry-After` (seconds or HTTP-date) is honoured, otherwise exponential backoff from 250 ms with jitter, capped at 60 s. |
| Never retried                                     | Plan refusals (`code: "plan_limit_exceeded"`, whatever the status), 5xx on `POST`/`PATCH`, and streams.                                                                                                                                        |
| Errors                                            | `MisarDevError` and its subclasses, all exported from `misardev` — see [Errors](#errors).                                                                                                                                                      |
| Escape hatches                                    | `dev.request(method, path, query=, body=)`, `dev.stream(...)`, and their `arequest` / `astream` twins.                                                                                                                                         |
| Lifecycle                                         | `dev.close()` / `await dev.aclose()`, or `with MisarDev() as dev:` / `async with MisarDev() as dev:`.                                                                                                                                          |

---

## Quick start

```python
from misardev import MisarDev, PlanLimitError

dev = MisarDev()  # MISARDEV_API_KEY

projects = dev.projects.list({"limit": 10})
project = dev.projects.create({"name": "My landing page", "description": "A launch page for my app"})

try:
    dev.projects.deploy(project["project"]["id"], {"target": "misar"})
except PlanLimitError as e:
    print(e.offer["headline"], e.upgrade_url)
```

Async, from the same client:

```python
import asyncio
from misardev import MisarDev

async def main():
    async with MisarDev() as dev:
        projects = await dev.projects.alist()
        plan = await dev.usage.aplan()

asyncio.run(main())
```

---

## Primary functions

### Create a project

```python
created = dev.projects.create({"name": "Recipe box", "description": "Save and tag recipes"})
project_id = created["project"]["id"]
```

### Write files

```python
dev.projects.write_files(project_id, {
    "files": [
        {"path": "app/page.tsx", "content": "export default function Page() { return <h1>Hi</h1>; }"},
    ],
})
files = dev.projects.list_files(project_id)
```

### Deploy

```python
available = dev.projects.check_subdomain(project_id, "recipe-box")
deployment = dev.projects.deploy(project_id, {"target": "misar", "subdomain": "recipe-box"})
status = dev.projects.get_deployment(project_id)
```

### List templates and start from one

```python
templates = dev.templates.list({"featured": True, "limit": 12})
first = templates["templates"][0]
started = dev.templates.use(first["id"], {"projectName": "From a template"})
```

### OpenAI-compatible chat completion

```python
reply = dev.chat.completions({
    "model": "misar-online",
    "messages": [{"role": "user", "content": "Suggest three names for a recipe app."}],
})
print(reply["choices"][0]["message"]["content"])
```

### Streamed completion

```python
for event in dev.chat.completions_stream({"messages": [{"role": "user", "content": "Write a haiku."}]}):
    print(event.data["choices"][0]["delta"].get("content", ""), end="", flush=True)
```

### Code search

```python
hits = dev.search.code({"q": "useAuth", "types": "project,template", "limit": 20})
answers = dev.rag.search(project_id, {"query": "where is the login form?"})
```

### Read usage and plan

```python
plan = dev.usage.plan()
usage = dev.usage.list({"days": 30})
```

---

## Errors

Every non-2xx answer raises a subclass of `MisarDevError`. Each carries `status`, `message`,
`code` (from `body.code` or `body.error.code`), `body` (the decoded error body) and
`request_id` (the `x-request-id` header — quote it to support).

| Class                   | When                                                                                         |
| ----------------------- | -------------------------------------------------------------------------------------------- |
| `MisarDevError`         | Base class; also raised for any status not listed below, and for a missing API key.          |
| `ValidationError`       | `400`, `422` — malformed request or failed validation.                                       |
| `AuthenticationError`   | `401` — key missing, revoked, expired, or not a MisarDev key.                                |
| `PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                               |
| `NotFoundError`         | `404` — no such resource, or not one this key can see.                                       |
| `ConflictError`         | `409` — conflicts with current state, e.g. a build already running.                          |
| `RateLimitError`        | `429` that is an ordinary throttle, after retries; `retry_after` in seconds.                 |
| `ServerError`           | `5xx` after retries (idempotent verbs) or at once (`POST`, `PATCH`).                         |
| `NetworkError`          | No HTTP answer at all (DNS, TLS, reset, timeout); `status == 0`, `cause` is the httpx error. |
| `PlanLimitError`        | Body `code == "plan_limit_exceeded"`, whatever the status. Never retried.                    |

```python
from misardev import MisarDev, MisarDevError, NotFoundError

try:
    dev.projects.get("does-not-exist")
except NotFoundError:
    print("no such project")
except MisarDevError as e:
    print(e.status, e.code, e.message, e.request_id)
```

---

## Plan limits

The server decides what a key's plan allows, and refuses with an upgrade offer:

| Status | `upgrade.reason`  | Meaning                                                                 |
| ------ | ----------------- | ----------------------------------------------------------------------- |
| `402`  | `feature_locked`  | The feature is not on the plan.                                         |
| `429`  | `quota_exhausted` | An allowance is spent until the period resets; `Retry-After` says when. |

Both carry `code: "plan_limit_exceeded"`. The SDK keys on that code rather than the status —
a spent quota is a `429` that would otherwise look like an ordinary throttle — and raises
`PlanLimitError` at once, without retrying, because retrying cannot help.

| Field              | Value                                                                                                       |
| ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `offer`            | The full `upgrade` object exactly as sent, every field kept: `headline`, `plans`, `cta`, `usage`, `urls`, … |
| `upgrade_url`      | `offer["urls"]["billing"]`, falling back to `offer["urls"]["pricing"]`.                                     |
| `feature`          | The limit that was hit, e.g. `api_access`.                                                                  |
| `current_plan`     | `offer["current_plan"]["slug"]`, e.g. `starter`.                                                            |
| `recommended_plan` | `offer["recommended_plan"]`, e.g. `pro`.                                                                    |
| `retry_after`      | Seconds from `Retry-After`, for `quota_exhausted`.                                                          |

```python
from misardev import PlanLimitError

try:
    dev.projects.deploy(project_id, {"target": "misar"})
except PlanLimitError as e:
    offer = e.offer or {}
    print(offer.get("headline"))
    for plan in offer.get("plans", []):
        print(f"  {plan['name']}: {plan['price']} — {plan.get('unlocks') or ''}")
    print(offer.get("cta"), e.upgrade_url)
```

Read `dev.usage.plan()` before an expensive call rather than discovering the ceiling through a refusal.

---

## Streaming

Three routes stream Server-Sent Events. Each stream method yields `SSEEvent(event, data, id)`
— `data` JSON-decoded when it is JSON, else the raw string — and has an async twin for
`async for`. Streams are never retried: replaying one that failed mid-flight would duplicate
whatever you had already read. A frame carrying `code: "plan_limit_exceeded"` raises
`PlanLimitError`, exactly like the same refusal on a plain call.

| Method                    | Route                             | Ends                                                                                          |
| ------------------------- | --------------------------------- | --------------------------------------------------------------------------------------------- |
| `chat.completions_stream` | `POST /v1/chat/completions`       | At `data: [DONE]`, which is consumed, not yielded. Sets `"stream": True` in the body for you. |
| `chat.studio_stream`      | `POST /chat`                      | When the server closes the stream.                                                            |
| `projects.build_stream`   | `GET /projects/{id}/build-stream` | When the server closes the stream.                                                            |

```python
for event in dev.projects.build_stream(project_id):
    print(event.event, event.data)

async for event in dev.chat.acompletions_stream({"messages": [{"role": "user", "content": "hi"}]}):
    print(event.data["choices"][0]["delta"].get("content", ""), end="")
```

---

## Pagination

Offset-paginated lists (templates, gallery, API keys, …) return one page at a time.
`dev.paginate(fetch_page, page_size=50, max_items=None)` walks them: it calls
`fetch_page(offset, limit)`, yields each item — read from the page itself when it is a list,
otherwise from its first list-valued field — and stops on a short page.

```python
for template in dev.paginate(lambda offset, limit: dev.templates.list({"offset": offset, "limit": limit})):
    print(template["name"])

async for item in dev.apaginate(lambda offset, limit: dev.gallery.alist({"offset": offset, "limit": limit}), max_items=100):
    print(item)
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- PyPI — https://pypi.org/project/misardev/

MIT © [Misar.AI](https://misar.io)
