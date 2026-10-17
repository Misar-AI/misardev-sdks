# Misar.Dev Swift SDK

> Create, build and ship apps on Misar.Dev from Swift — async/await on Apple platforms and Linux.

[![Swift](https://img.shields.io/badge/swift-5.9%2B-F05138)](https://swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](https://github.com/Misar-AI/misardev-sdks)
[![platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgrey)](https://github.com/Misar-AI/misardev-sdks)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · no dependencies beyond Foundation**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

macOS 12+, iOS 15+, tvOS 15+, watchOS 8+ and Linux. Because `URLSession.data(for:)` and `.bytes(for:)` do not exist in swift-corelibs-foundation, the package uses the completion-handler and delegate APIs instead — one implementation, every platform.

---

## Install

### Package.swift

```swift
.package(url: "https://github.com/Misar-AI/misardev-sdks.git", from: "1.0.0")
```

and add the product to your target:

```swift
.product(name: "MisarDev", package: "misardev-sdks")
```

### Xcode

File → Add Package Dependencies → `https://github.com/Misar-AI/misardev-sdks.git`

> SwiftPM requires `Package.swift` at the repository root, so this SDK is consumed from the
> public `misardev-sdks` mirror, whose root manifest points at `swift/`. The monorepo URL
> will not resolve.

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the initializer, or set
`MISARDEV_API_KEY` and call `try MisarDevClient()` with no arguments. With neither, the
initializer throws a `MisarDevError` that points at the API-keys page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, throws `PlanLimitError`, and is never
retried.

```swift
import MisarDev

let dev = try MisarDevClient(apiKey: ProcessInfo.processInfo.environment["MISARDEV_API_KEY"])
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's doc comment
names the route it calls.

### Build and ship

| Resource          | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | What it covers                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `dev.projects`    | `addCollaborator`, `archive`, `buildStatus`, `cancelBuild`, `checkSubdomain`, `create`, `createConversation`, `delete`, `deleteEnv`, `deleteSkills`, `deploy`, `duplicate`, `export`, `get`, `getBackend`, `getDeployment`, `getDomain`, `getEnv`, `getKnowledge`, `getSkills`, `getTools`, `importArtifact`, `list`, `listCheckpoints`, `listCollaborators`, `listConversations`, `listFiles`, `provisionBackend`, `removeCollaborator`, `removeDomain`, `restore`, `setDomain`, `undeploy`, `update`, `updateEnv`, `updateKnowledge`, `updateSkills`, `updateSubdomain`, `updateTools`, `writeFiles`, `buildStream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `dev.templates`   | `create`, `delete`, `get`, `list`, `remix`, `update`, `use`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `dev.checkpoints` | `delete`, `restore`, `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Saved project snapshots: rename, restore, delete.                                                                              |
| `dev.builds`      | `list`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Recent builds across your projects.                                                                                            |

### AI

| Resource     | Methods                                            | What it covers                                                                                    |
| ------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `dev.chat`   | `completions`, `studioStream`, `completionsStream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `dev.search` | `code`, `web`                                      | Web-grounded answers with citations, and search across your own code.                             |
| `dev.rag`    | `clear`, `index`, `search`                         | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource         | Methods                                                                                                                        | What it covers                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `dev.connectors` | `available`, `createConnection`, `deleteConnection`, `list`, `listConnections`, `testConnection`, `toggle`, `updateConnection` | Connector catalogue, per-account enable state, and per-project connections. |
| `dev.github`     | `disconnect`, `getConnection`                                                                                                  | The linked GitHub account: read it or disconnect it.                        |
| `dev.skills`     | `get`, `list`                                                                                                                  | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource            | Methods                                                                                                                                        | What it covers                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `dev.organizations` | `acceptInvitation`, `create`, `createInvitation`, `list`, `listInvitations`, `listMembers`, `removeMember`, `revokeInvitation`, `updateMember` | Organizations, members and invitations.       |
| `dev.gallery`       | `like`, `list`, `unlike`                                                                                                                       | The public community gallery, and likes.      |
| `dev.profile`       | `follow`, `get`, `unfollow`                                                                                                                    | Public builder profiles, follow and unfollow. |
| `dev.notifications` | `list`, `markAllRead`, `markRead`                                                                                                              | In-app notifications and read state.          |
| `dev.reports`       | `create`                                                                                                                                       | Report abusive content.                       |

### Account, plan and billing

| Resource      | Methods                                                         | What it covers                                                         |
| ------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `dev.account` | `createKey`, `deleteKey`, `export`, `listKeys`, `updateKey`     | Account API keys (with expiry and IP allowlists) and your data export. |
| `dev.apiKeys` | `create`, `delete`, `list`                                      | API keys — create, list, revoke.                                       |
| `dev.usage`   | `list`, `plan`, `track`                                         | Usage for a period, your plan's allowances, and usage events.          |
| `dev.billing` | `checkout`, `comparison`, `plans`, `subscription`, `switchPlan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `dev.audit`   | `list`                                                          | Your account's audit log.                                              |
| `dev.domains` | `lookup`                                                        | Custom-domain availability lookup.                                     |

---

## Client

| Thing          | Detail                                                                                                                                                                                                                                                                           |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point    | `try MisarDevClient(apiKey:baseURL:maxRetries:timeout:session:headers:)` — every resource is a computed property.                                                                                                                                                                |
| `baseURL`      | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`)                                                                                                                                                                                                                              |
| `maxRetries`   | `3` total attempts                                                                                                                                                                                                                                                               |
| `timeout`      | `60` seconds per request                                                                                                                                                                                                                                                         |
| `session`      | Inject a `URLSession` (tests, proxies). Streams reuse its configuration.                                                                                                                                                                                                         |
| `headers`      | Extra headers on every request.                                                                                                                                                                                                                                                  |
| Call signature | `resource.method(pathParam…, requiredQuery: …, body?, query: [:])` — path params are positional, required query params are labeled with their own name.                                                                                                                          |
| Payloads       | `[String: JSONValue]` in, `JSONValue` out. `JSONValue` takes literals (`["name": "x", "private": true]`) and reads with subscripts and `.stringValue`, `.intValue`, `.boolValue`, `.arrayValue`, `.objectValue`. A `204` or empty body is `.null`; a non-JSON body is `.string`. |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms, honouring `Retry-After` (capped at 60 s).                                                                                       |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server error, and streams.                                                                                                                                                                                                                 |
| Escape hatches | `dev.request(method, path, query:, body:)` and `dev.stream(method, path, …)` for any route.                                                                                                                                                                                      |
| Errors         | `MisarDevError` and nine subclasses — catch them with `catch let e as PlanLimitError`.                                                                                                                                                                                           |

---

## Quick start

```swift
import MisarDev

let dev = try MisarDevClient(apiKey: ProcessInfo.processInfo.environment["MISARDEV_API_KEY"])

let created = try await dev.projects.create([
    "name": "Coffee shop site",
    "description": "A one-page site for a neighbourhood coffee shop",
])

print(created["project"]?["id"]?.stringValue ?? "")
```

## Primary functions

### Create a project and write its files

```swift
let created = try await dev.projects.create(["name": "Landing page"])
let projectId = created["project"]?["id"]?.stringValue ?? ""

try await dev.projects.writeFiles(projectId, [
    "files": [
        ["path": "index.html", "content": "<h1>Hello</h1>"],
        ["path": "styles.css", "content": "h1 { color: #22c55e; }"],
    ],
])

let files = try await dev.projects.listFiles(projectId)
```

### Deploy

```swift
// Check the subdomain first — required query params are labeled.
let check = try await dev.projects.checkSubdomain(projectId, value: "coffee-shop")

let deployment = try await dev.projects.deploy(projectId, ["subdomain": "coffee-shop"])
let status = try await dev.projects.getDeployment(projectId)
```

### Start from a template

```swift
let page = try await dev.templates.list(query: ["featured": true, "limit": 10])
let templateId = page["templates"]?[0]?["id"]?.stringValue ?? ""

let fromTemplate = try await dev.templates.use(templateId, ["projectName": "My portfolio"])
```

### Ask the AI (OpenAI-compatible)

```swift
let completion = try await dev.chat.completions([
    "model": "misar-online",
    "messages": [["role": "user", "content": "What's new in CSS this year?"]],
])

print(completion["choices"]?[0]?["message"]?["content"]?.stringValue ?? "")
```

### Search your code

```swift
let hits = try await dev.search.code(query: ["q": "useEffect", "types": "files", "limit": 20])
let semantic = try await dev.rag.search(projectId: projectId, query: ["query": "where do we send email?"])
```

### Read usage and plan

```swift
let plan = try await dev.usage.plan()
let usage = try await dev.usage.list(query: ["days": 30])
```

### Manage API keys

```swift
let key = try await dev.account.createKey(["name": "CI"])
print(key["key"]?.stringValue ?? "") // shown once and never again
```

## Errors

Every non-2xx answer throws a typed error. Each is a subclass of `MisarDevError` and carries
`status`, `message`, `code`, the decoded `body` (`JSONValue?`), the `rawBody` and the
`requestId` (from `x-request-id`).

| Class                   | When                                                                             |
| ----------------------- | -------------------------------------------------------------------------------- |
| `ValidationError`       | `400` / `422` — the request was malformed.                                       |
| `AuthenticationError`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFoundError`         | `404` — no such resource, or not one this key can see.                           |
| `ConflictError`         | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimitError`        | `429` throttle, after retries. Carries `retryAfter` (seconds).                   |
| `PlanLimitError`        | The plan behind the key does not cover the call. See below.                      |
| `ServerError`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkError`          | The request never got an answer (DNS, socket, timeout). `status` is `0`.         |
| `MisarDevError`         | The base class, and anything else.                                               |

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError.offer` is the full offer as a `JSONValue`, every field the server sent: a
headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. All of that copy comes from the server, so render it rather than writing your own.
Convenience properties: `upgradeUrl` (`offer.urls.billing`, else `offer.urls.pricing`),
`feature`, `currentPlan`, `recommendedPlan`, `reason`, `headline` and `retryAfter`.

```swift
do {
    _ = try await dev.projects.list()
} catch let e as PlanLimitError {
    print(e.offer?["headline"]?.stringValue ?? e.message)
    for plan in e.offer?["plans"]?.arrayValue ?? [] {
        print("  \(plan["name"]?.stringValue ?? "") — \(plan["price"]?.stringValue ?? "")")
    }
    print("Upgrade: \(e.upgradeUrl ?? "")")
    // e.feature, e.currentPlan, e.recommendedPlan, e.retryAfter
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns an
`AsyncThrowingStream<SSEEvent, Error>`, where an `SSEEvent` carries `event`, `data` (the
JSON-decoded payload as a `JSONValue`, or `.string`), `id` and `raw`:

| Method                   | Route                                                                        |
| ------------------------ | ---------------------------------------------------------------------------- |
| `chat.completionsStream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studioStream`      | `POST /chat` — the studio's build conversation.                              |
| `projects.buildStream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
throws `PlanLimitError`. Breaking out of the loop cancels the underlying task.

```swift
for try await chunk in dev.chat.completionsStream([
    "model": "misar-online",
    "messages": [["role": "user", "content": "Write a haiku"]],
]) {
    print(chunk.data["choices"]?[0]?["delta"]?["content"]?.stringValue ?? "", terminator: "")
}

for try await event in dev.projects.buildStream(projectId) {
    print(event.event ?? "message", event.raw)
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.paginate` walks
every page and stops on a short one. Items come from the page itself when it is an array,
otherwise from its first array-valued field:

```swift
for try await template in dev.paginate({ offset, limit in
    try await dev.templates.list(query: ["offset": .init(offset), "limit": .init(limit)])
}) {
    print(template["name"]?.stringValue ?? "")
}
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- Swift Package — https://github.com/Misar-AI/misardev-sdks

MIT © [Misar.AI](https://misar.io)
