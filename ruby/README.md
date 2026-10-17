# Misar.Dev Ruby SDK

> Create, build and ship apps on Misar.Dev from Ruby — one client, no runtime dependencies.

[![gem](https://img.shields.io/gem/v/misardev)](https://rubygems.org/gems/misardev)
[![ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-CC342D)](https://rubygems.org/gems/misardev)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · typed plan-limit errors**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI through an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

Built on `net/http` with nothing outside the standard library, for Ruby 3.0+. Every method returns the decoded JSON — a `Hash` with **string** keys, or an `Array` — so nothing breaks when the API adds a field.

---

## Install

### RubyGems

```bash
gem install misardev
```

### Bundler

```ruby
gem "misardev", "~> 1.0"
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `MisarDev.new` with no arguments.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, raises `PlanLimitError`, and is never
retried.

```ruby
require "misardev"

dev = MisarDev.new(ENV["MISARDEV_API_KEY"])
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's comment names
the route it calls.

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

| Thing          | Detail                                                                                                                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entry point    | `MisarDev::Client.new(api_key = nil, base_url:, max_retries:, timeout:, http_client:, headers:)`. `MisarDev.new(...)` is a shorthand. Every resource is a reader.                          |
| `api_key`      | Falls back to `MISARDEV_API_KEY`; raises `MisarDev::MisarDevError` when neither is set.                                                                                                    |
| `base_url:`    | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                       |
| `max_retries:` | `3` total attempts.                                                                                                                                                                        |
| `timeout:`     | `60` seconds per attempt. Streams have no overall timeout.                                                                                                                                 |
| `http_client:` | Any object with `call(request)` and `stream(request) { \|response\| }` — inject one for tests or proxies. Defaults to `net/http` (10-second open timeout).                                 |
| `headers:`     | Extra headers on every request.                                                                                                                                                            |
| Call signature | `dev.resource.method(path_params…, required_query…, body = {}, query = {})` — keyword-style hashes work: `dev.templates.list(limit: 5)`.                                                   |
| Results        | Decoded JSON (`Hash` with string keys, or `Array`). `204`/empty is `nil`; a non-JSON body comes back as a `String`.                                                                        |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms, honouring `Retry-After` (capped at 60 s). |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server error or dropped connection, and streams.                                                                                                     |
| Escape hatches | `dev.request(method, path, query:, body:)` and `dev.stream(method, path, ...)` for any route.                                                                                              |
| Errors         | `MisarDev::MisarDevError` (alias `MisarDev::Error`) and nine subclasses.                                                                                                                   |

---

## Quick start

```ruby
require "misardev"

dev = MisarDev.new(ENV["MISARDEV_API_KEY"])

created = dev.projects.create(
  name: "Coffee shop site",
  description: "A one-page site for a neighbourhood coffee shop"
)

puts created["project"]["id"]
```

## Primary functions

### Create a project and write its files

```ruby
project_id = dev.projects.create(name: "Landing page")["project"]["id"]

dev.projects.write_files(project_id, files: [
  { path: "index.html", content: "<h1>Hello</h1>" },
  { path: "styles.css", content: "h1 { color: #22c55e; }" }
])

files = dev.projects.list_files(project_id)
```

### Deploy

```ruby
# Check the subdomain first — required query params are positional.
check = dev.projects.check_subdomain(project_id, "coffee-shop")

deployment = dev.projects.deploy(project_id, subdomain: "coffee-shop")
status     = dev.projects.get_deployment(project_id)
```

### Start from a template

```ruby
templates = dev.templates.list(featured: true, limit: 10)["templates"]

created = dev.templates.use(templates.first["id"], projectName: "My portfolio")
```

### Ask the AI (OpenAI-compatible)

```ruby
completion = dev.chat.completions(
  model: "misar-online",
  messages: [{ role: "user", content: "What's new in CSS this year?" }]
)

puts completion["choices"][0]["message"]["content"]
```

### Stream a completion

```ruby
dev.chat.completions_stream(
  model: "misar-online",
  messages: [{ role: "user", content: "Write a haiku" }]
) do |chunk|
  print chunk.data["choices"][0]["delta"]["content"]
end
```

### Search your code

```ruby
hits     = dev.search.code(q: "useEffect", types: "files", limit: 20)
semantic = dev.rag.search(project_id, query: "where do we send email?")
```

### Read usage and plan

```ruby
plan  = dev.usage.plan
usage = dev.usage.list(days: 30)
```

### Manage API keys

```ruby
fresh = dev.account.create_key(name: "CI")
puts fresh["key"] # shown once and never again
```

## Errors

Every non-2xx answer raises a typed error, all under `MisarDev`. Each carries `status`,
`message`, `code`, the decoded `body` and the `request_id` (from `x-request-id`).
`rescue MisarDev::MisarDevError` catches everything the SDK raises.

| Class                   | When                                                                             |
| ----------------------- | -------------------------------------------------------------------------------- |
| `ValidationError`       | `400` / `422` — the request was malformed.                                       |
| `AuthenticationError`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFoundError`         | `404` — no such resource, or not one this key can see.                           |
| `ConflictError`         | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimitError`        | `429` throttle, after retries. Carries `retry_after` (seconds).                  |
| `PlanLimitError`        | The plan behind the key does not cover the call. See below.                      |
| `ServerError`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkError`          | The request never got an answer (DNS, socket, timeout). `status` is `0`.         |
| `MisarDevError`         | The base class, and anything else. Subclasses `StandardError`.                   |

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError#offer` is the full offer as a `Hash`, every field the server sent: a
headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. All of that copy comes from the server, so render it rather than writing your own.
Convenience readers: `upgrade_url` (billing, else pricing), `feature`, `current_plan`,
`recommended_plan`, `retry_after` (seconds until a quota resets).

```ruby
begin
  dev.projects.list
rescue MisarDev::PlanLimitError => e
  warn e.offer&.fetch("headline", nil) || e.message
  (e.offer&.fetch("plans", nil) || []).each { |plan| warn "  #{plan['name']} — #{plan['price']}" }
  warn "Upgrade: #{e.upgrade_url}"
  # e.feature, e.current_plan, e.recommended_plan, e.retry_after
end
```

## Streaming

Three endpoints stream Server-Sent Events. Pass a block to receive each
`MisarDev::StreamEvent` (`event`, `data`, `id`) as it arrives; without a block you get a
lazy `Enumerator` — nothing is sent until you iterate it. `data` is the decoded JSON, or the
raw string when the payload is not JSON.

| Method                    | Route                                                                        |
| ------------------------- | ---------------------------------------------------------------------------- |
| `chat.completions_stream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studio_stream`      | `POST /chat` — the studio's build conversation.                              |
| `projects.build_stream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
raises `PlanLimitError`. `break` out of the block to stop early; the connection is closed.

```ruby
dev.chat.completions_stream(
  model: "misar-online",
  messages: [{ role: "user", content: "Write a haiku" }]
) do |chunk|
  print chunk.data["choices"][0]["delta"]["content"]
end

dev.projects.build_stream(project_id).each do |event|
  puts "#{event.event} #{event.data}"
end
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.paginate` walks
every page and stops on a short one, returning an `Enumerator` over the items. Items come from
the page itself when it is an `Array`, otherwise from its first `Array`-valued field
(`templates`, `items`, …).

```ruby
dev.paginate { |offset, limit| dev.templates.list(offset: offset, limit: limit) }.each do |template|
  puts template["name"]
end

# page_size: and max_items: are optional
dev.paginate(page_size: 50, max_items: 200) { |offset, limit| dev.gallery.list(offset: offset, limit: limit) }.to_a
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- RubyGems — https://rubygems.org/gems/misardev

MIT © [Misar.AI](https://misar.io)
