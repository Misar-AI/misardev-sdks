# Misar.Dev Rust SDK

> Async Rust client for Misar.Dev — create, build and ship apps from your own code over reqwest/tokio.

[![crates.io](https://img.shields.io/crates/v/misardev)](https://crates.io/crates/misardev)
[![docs.rs](https://img.shields.io/docsrs/misardev)](https://docs.rs/misardev)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · typed plan-limit errors**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves. Payloads are `serde_json::Value` in and out — no generated structs, so nothing breaks when the API adds a field; `serde_json::from_value` turns a response into your own type. TLS is rustls; there is no OpenSSL dependency.

---

## Install

### cargo add

```bash
cargo add misardev serde_json
cargo add tokio --features macros,rt-multi-thread
cargo add futures   # only if you use the SSE streams or pagination
```

### Cargo.toml

```toml
[dependencies]
misardev = "1.0"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
serde_json = "1"
futures = "0.3"   # only for streaming and pagination
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to `MisarDev::new`, or set
`MISARDEV_API_KEY` and call `MisarDev::from_env()` (an empty key passed to `new` falls back
to the variable too). With neither, building the client fails with
`MisarDevError::MissingApiKey`, whose message points at the key settings page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, comes back as
`MisarDevError::PlanLimit`, and is never retried.

```rust
let dev = misardev::MisarDev::from_env()?;
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's doc comment
names the route it calls. The signature is always
`dev.resource().method(path_params…, required_query…, body?, query?)`, where path params and
required query values are `&str`, `body` is `Option<Value>` (`None` sends `{}`) and `query` is
`Option<Value>` holding a JSON object (`null` values are dropped). Reserved words get a
trailing underscore (`templates().use_(…)`).

### Build and ship

| Resource            | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | What it covers                                                                                                                 |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `dev.projects()`    | `add_collaborator`, `archive`, `build_status`, `cancel_build`, `check_subdomain`, `create`, `create_conversation`, `delete`, `delete_env`, `delete_skills`, `deploy`, `duplicate`, `export`, `get`, `get_backend`, `get_deployment`, `get_domain`, `get_env`, `get_knowledge`, `get_skills`, `get_tools`, `import_artifact`, `list`, `list_checkpoints`, `list_collaborators`, `list_conversations`, `list_files`, `provision_backend`, `remove_collaborator`, `remove_domain`, `restore`, `set_domain`, `undeploy`, `update`, `update_env`, `update_knowledge`, `update_skills`, `update_subdomain`, `update_tools`, `write_files`, `build_stream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `dev.templates()`   | `create`, `delete`, `get`, `list`, `remix`, `update`, `use_`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `dev.checkpoints()` | `delete`, `restore`, `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Saved project snapshots: rename, restore, delete.                                                                              |
| `dev.builds()`      | `list`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Recent builds across your projects.                                                                                            |

### AI

| Resource       | Methods                                              | What it covers                                                                                    |
| -------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `dev.chat()`   | `completions`, `studio_stream`, `completions_stream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `dev.search()` | `code`, `web`                                        | Web-grounded answers with citations, and search across your own code.                             |
| `dev.rag()`    | `clear`, `index`, `search`                           | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource           | Methods                                                                                                                             | What it covers                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `dev.connectors()` | `available`, `create_connection`, `delete_connection`, `list`, `list_connections`, `test_connection`, `toggle`, `update_connection` | Connector catalogue, per-account enable state, and per-project connections. |
| `dev.github()`     | `disconnect`, `get_connection`                                                                                                      | The linked GitHub account: read it or disconnect it.                        |
| `dev.skills()`     | `get`, `list`                                                                                                                       | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource              | Methods                                                                                                                                               | What it covers                                |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `dev.organizations()` | `accept_invitation`, `create`, `create_invitation`, `list`, `list_invitations`, `list_members`, `remove_member`, `revoke_invitation`, `update_member` | Organizations, members and invitations.       |
| `dev.gallery()`       | `like`, `list`, `unlike`                                                                                                                              | The public community gallery, and likes.      |
| `dev.profile()`       | `follow`, `get`, `unfollow`                                                                                                                           | Public builder profiles, follow and unfollow. |
| `dev.notifications()` | `list`, `mark_all_read`, `mark_read`                                                                                                                  | In-app notifications and read state.          |
| `dev.reports()`       | `create`                                                                                                                                              | Report abusive content.                       |

### Account, plan and billing

| Resource         | Methods                                                          | What it covers                                                         |
| ---------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `dev.account()`  | `create_key`, `delete_key`, `export`, `list_keys`, `update_key`  | Account API keys (with expiry and IP allowlists) and your data export. |
| `dev.api_keys()` | `create`, `delete`, `list`                                       | API keys — create, list, revoke.                                       |
| `dev.usage()`    | `list`, `plan`, `track`                                          | Usage for a period, your plan's allowances, and usage events.          |
| `dev.billing()`  | `checkout`, `comparison`, `plans`, `subscription`, `switch_plan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `dev.audit()`    | `list`                                                           | Your account's audit log.                                              |
| `dev.domains()`  | `lookup`                                                         | Custom-domain availability lookup.                                     |

---

## Client

| Thing          | Detail                                                                                                                                                                                                                      |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point    | `MisarDev::new(api_key)`, `MisarDev::from_env()`, or `MisarDev::builder()…build()` — every resource is an accessor (`dev.projects()`). Cheap to clone.                                                                      |
| Builder        | `.api_key(..)`, `.base_url(..)`, `.max_retries(..)`, `.timeout(..)`, `.header(..)`, `.http_client(reqwest::Client)`.                                                                                                        |
| Base URL       | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                                                        |
| Attempts       | `3` total.                                                                                                                                                                                                                  |
| Timeout        | `60s` per attempt; streams are not bounded by it.                                                                                                                                                                           |
| Payloads       | `serde_json::Value` in, `Value` out — `Value::Null` for an empty or `204` answer, `Value::String` for a non-JSON body.                                                                                                      |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms with jitter, honouring `Retry-After` (seconds or HTTP date), capped at 60s. |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server or network error, and streams.                                                                                                                                                 |
| Escape hatches | `dev.request(Method, path, query, body)` and `dev.stream(Method, path, query, body, terminator)` for any route.                                                                                                             |
| Errors         | One `MisarDevError` enum with a variant per failure kind; `status()`, `message()`, `code()`, `body()` and `request_id()` work on every variant.                                                                             |

---

## Quick start

```rust
use misardev::{MisarDev, MisarDevError};
use serde_json::json;

#[tokio::main]
async fn main() -> Result<(), MisarDevError> {
    let dev = MisarDev::new("mdk_your_key")?;

    let created = dev
        .projects()
        .create(Some(json!({
            "name": "Coffee shop site",
            "description": "A one-page site for a neighbourhood coffee shop",
        })))
        .await?;

    println!("{}", created["project"]["id"]);
    Ok(())
}
```

## Primary functions

### Create a project and write its files

```rust
let created = dev.projects().create(Some(json!({ "name": "Landing page" }))).await?;
let id = created["project"]["id"].as_str().unwrap_or_default().to_owned();

dev.projects()
    .write_files(&id, Some(json!({
        "files": [
            { "path": "index.html", "content": "<h1>Hello</h1>" },
            { "path": "styles.css", "content": "h1 { color: #22c55e; }" },
        ]
    })))
    .await?;
let files = dev.projects().list_files(&id).await?;
```

### Deploy

Required query parameters are positional:

```rust
let check = dev.projects().check_subdomain(&id, "coffee-shop").await?;
let deployment = dev.projects().deploy(&id, Some(json!({ "subdomain": "coffee-shop" }))).await?;
let status = dev.projects().get_deployment(&id).await?;
```

### Start from a template

```rust
let page = dev.templates().list(Some(json!({ "featured": true, "limit": 10 }))).await?;
let first = page["templates"][0]["id"].as_str().unwrap_or_default();

let project = dev
    .templates()
    .use_(first, Some(json!({ "projectName": "My portfolio" })))
    .await?;
```

### Ask the AI (OpenAI-compatible)

```rust
let completion = dev
    .chat()
    .completions(Some(json!({
        "model": "misar-online",
        "messages": [{ "role": "user", "content": "What's new in CSS this year?" }],
    })))
    .await?;
println!("{}", completion["choices"][0]["message"]["content"]);
```

For a streamed completion, see [Streaming](#streaming).

### Search your code

```rust
let hits = dev
    .search()
    .code(Some(json!({ "q": "useEffect", "types": "files", "limit": 20 })))
    .await?;
let semantic = dev
    .rag()
    .search(&id, Some(json!({ "query": "where do we send email?" })))
    .await?;
```

### Read usage and plan

```rust
let plan = dev.usage().plan().await?;
let usage = dev.usage().list(Some(json!({ "days": 30 }))).await?;
```

### Manage API keys

```rust
let key = dev.account().create_key(Some(json!({ "name": "CI" }))).await?;
println!("{}", key["key"]); // shown once and never again
```

## Errors

Every non-2xx answer is a `MisarDevError`. Each HTTP variant carries an `ApiError` with
`status`, `message`, `code`, the decoded `body` and the `request_id` (from `x-request-id`);
the accessors `status()`, `message()`, `code()`, `body()` and `request_id()` read them from
any variant.

| Variant                    | When                                                                             |
| -------------------------- | -------------------------------------------------------------------------------- |
| `Validation`               | `400` / `422` — the request was malformed.                                       |
| `Authentication`           | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDenied`         | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFound`                 | `404` — no such resource, or not one this key can see.                           |
| `Conflict`                 | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimit`                | `429` throttle, after retries. `RateLimitError` carries `retry_after`.           |
| `PlanLimit`                | The plan behind the key does not cover the call. See below.                      |
| `Server`                   | `5xx`, after retries where retrying is safe.                                     |
| `Network`                  | The request never got an answer (DNS, socket, timeout). `status()` is `0`.       |
| `Api`                      | Any other status.                                                                |
| `MissingApiKey` / `Config` | The client could not be built.                                                   |

```rust
match dev.projects().get("p_123").await {
    Ok(project) => println!("{project}"),
    Err(MisarDevError::NotFound(e)) => eprintln!("no such project (request {:?})", e.request_id),
    Err(e) => eprintln!("{} {:?}: {}", e.status(), e.code(), e.message()),
}
```

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError::offer` is the full offer as a `serde_json::Value`, every field kept: a
headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. All of that copy comes from the server, so render it rather than writing your own.
`upgrade_url()` (billing URL, falling back to pricing), `feature()`, `reason()`,
`headline()`, `current_plan()`, `recommended_plan()` and `plans()` read the common fields, and
`retry_after` holds the `Retry-After` seconds.

```rust
match dev.projects().list(None).await {
    Err(MisarDevError::PlanLimit(limit)) => {
        eprintln!("{}", limit.headline().unwrap_or_default());
        for plan in limit.plans() {
            eprintln!("  {} — {}", plan["name"], plan["price"]);
        }
        eprintln!("Upgrade: {}", limit.upgrade_url().unwrap_or_default());
        // limit.feature(), limit.current_plan(), limit.recommended_plan(), limit.retry_after
    }
    other => {
        other?;
    }
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns an `EventStream` — a boxed
`Stream<Item = Result<SseEvent, MisarDevError>>` — where `SseEvent { event, data, id }` has
`data` JSON-decoded when possible and `Value::String` otherwise. Read it with
`futures::StreamExt`.

| Method                      | Route                                                                          |
| --------------------------- | ------------------------------------------------------------------------------ |
| `chat().completions_stream` | `POST /v1/chat/completions` — sets `"stream": true` for you, ends at `[DONE]`. |
| `chat().studio_stream`      | `POST /chat` — the studio's build conversation.                                |
| `projects().build_stream`   | `GET /projects/{id}/build-stream` — live build progress.                       |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
is `MisarDevError::PlanLimit` (from the call, or as the stream's last item). Drop the stream
to stop early.

```rust
use futures::StreamExt;

let mut chunks = dev
    .chat()
    .completions_stream(Some(json!({
        "model": "misar-online",
        "messages": [{ "role": "user", "content": "Write a haiku" }],
    })))
    .await?;
while let Some(chunk) = chunks.next().await {
    let chunk = chunk?;
    print!("{}", chunk.data["choices"][0]["delta"]["content"].as_str().unwrap_or(""));
}

let mut build = dev.projects().build_stream(&id).await?;
while let Some(event) = build.next().await {
    let event = event?;
    println!("{:?} {}", event.event, event.data);
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `misardev::paginate`
walks every page as a stream of items and stops on a short one, reading items from the page
when it is an array or from its first array-valued field otherwise:

```rust
use futures::StreamExt;
use misardev::{paginate, PaginateOptions};

let mut templates = paginate(
    |offset, limit| dev.templates().list(Some(json!({ "offset": offset, "limit": limit }))),
    PaginateOptions::default(), // 50 per page, no cap
);
while let Some(template) = templates.next().await {
    println!("{}", template?);
}
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- crates.io — https://crates.io/crates/misardev
- docs.rs — https://docs.rs/misardev

MIT © [Misar.AI](https://misar.io)
