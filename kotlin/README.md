# MisarDev Kotlin SDK

> Create, build and ship apps on Misar.Dev from Kotlin — suspend functions and Flow-based SSE.

[![Maven Central](https://img.shields.io/badge/maven--central-io.misar%3Amisardev--kotlin-blue)](https://central.sonatype.com/artifact/io.misar/misardev-kotlin)
[![kotlin](https://img.shields.io/badge/kotlin-2.1%2B-7F52FF)](https://central.sonatype.com/artifact/io.misar/misardev-kotlin)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 suspend functions · 3 Flow streams · pagination**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Built on `java.net.http` with coroutines and Jackson; bytecode targets Java 11. Every call is a `suspend fun` returning a Jackson `JsonNode?` (objects and arrays alike); the three streams return a cold `Flow<SseEvent>`. Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

---

## Install

### Gradle (Kotlin DSL)

```kotlin
implementation("io.misar:misardev-kotlin:1.0.0")
```

### Gradle (Groovy)

```groovy
implementation 'io.misar:misardev-kotlin:1.0.0'
```

### Maven

```xml
<dependency>
  <groupId>io.misar</groupId>
  <artifactId>misardev-kotlin</artifactId>
  <version>1.0.0</version>
</dependency>
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `MisarDevClient()` with no arguments. With neither, the
constructor throws a `MisarDevException` pointing at the API keys page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, raises `PlanLimitException`, and is never
retried.

```kotlin
import io.misar.dev.MisarDevClient

val dev = MisarDevClient(System.getenv("MISARDEV_API_KEY"))
```

---

## Resources

Every group the client exposes, and every public function on it. Each resource is a property
on the client; each function's KDoc names the route it calls.

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

| Thing          | Detail                                                                                                                                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point    | `MisarDevClient(apiKey?, baseUrl?, maxRetries, timeout, httpClient?, headers)` — every argument is optional and named; every resource is a property.                                                                                                     |
| `baseUrl`      | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                                                                                     |
| `maxRetries`   | `3` total attempts.                                                                                                                                                                                                                                      |
| `timeout`      | `60.seconds` per attempt (`kotlin.time.Duration`).                                                                                                                                                                                                       |
| `httpClient`   | Inject your own `java.net.http.HttpClient` (proxies, custom TLS, tests).                                                                                                                                                                                 |
| `headers`      | Extra headers on every request.                                                                                                                                                                                                                          |
| Call signature | `resource.method(pathParams…, requiredQuery…, body = emptyMap(), query = emptyMap())`                                                                                                                                                                    |
| Results        | `JsonNode?` — `null` for `204`; a `TextNode` for a non-JSON body.                                                                                                                                                                                        |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms with jitter, honouring `Retry-After`, capped at 60 s. Backoff uses `delay`, so it never blocks a thread. |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server error or dropped connection, and streams.                                                                                                                                                                   |
| Escape hatches | `dev.request(method, path, query, body)` and `dev.stream(method, path, query, body, terminator)` for any route.                                                                                                                                          |
| Errors         | `MisarDevException` and nine subclasses — see [Errors](#errors).                                                                                                                                                                                         |

The client is thread-safe; share one instance.

---

## Quick start

```kotlin
import io.misar.dev.MisarDevClient

suspend fun main() {
    val dev = MisarDevClient() // reads MISARDEV_API_KEY

    val created = dev.projects.create(
        mapOf(
            "name" to "Coffee shop site",
            "description" to "A one-page site for a neighbourhood coffee shop",
        ),
    )
    println(created!!.at("/project/id").asText())
}
```

## Primary functions

### Create a project and write its files

```kotlin
val projectId = dev.projects.create(mapOf("name" to "Landing page"))!!.at("/project/id").asText()

dev.projects.writeFiles(
    projectId,
    mapOf(
        "files" to listOf(
            mapOf("path" to "index.html", "content" to "<h1>Hello</h1>"),
            mapOf("path" to "styles.css", "content" to "h1 { color: #22c55e; }"),
        ),
    ),
)

val files = dev.projects.listFiles(projectId)
```

### Deploy

```kotlin
// Check the subdomain first — required query params are positional.
val check = dev.projects.checkSubdomain(projectId, "coffee-shop")

val deployment = dev.projects.deploy(projectId, mapOf("subdomain" to "coffee-shop"))
val status = dev.projects.getDeployment(projectId)
```

### Start from a template

```kotlin
val templates = dev.templates.list(query = mapOf("featured" to true, "limit" to 10))!!["templates"]

val started = dev.templates.use(templates[0]["id"].asText(), mapOf("projectName" to "My portfolio"))
```

### Ask the AI (OpenAI-compatible)

```kotlin
val completion = dev.chat.completions(
    mapOf(
        "model" to "misar-online",
        "messages" to listOf(mapOf("role" to "user", "content" to "What's new in CSS this year?")),
    ),
)
println(completion!!.at("/choices/0/message/content").asText())
```

### Stream a completion

```kotlin
dev.chat.completionsStream(
    mapOf(
        "model" to "misar-online",
        "messages" to listOf(mapOf("role" to "user", "content" to "Write a haiku")),
    ),
).collect { chunk ->
    print(chunk.data.at("/choices/0/delta/content").asText(""))
}
```

### Search your code

```kotlin
val hits = dev.search.code(mapOf("q" to "useEffect", "types" to "files", "limit" to 20))
val semantic = dev.rag.search(projectId, mapOf("query" to "where do we send email?"))
```

### Read usage and plan

```kotlin
val plan = dev.usage.plan()
val usage = dev.usage.list(mapOf("days" to 30))
```

## Errors

Every non-2xx answer throws a typed exception from `io.misar.dev`. Each carries `status`,
`message`, `code`, the decoded `body` and `requestId` (from `x-request-id`).

| Class                       | When                                                                              |
| --------------------------- | --------------------------------------------------------------------------------- |
| `ValidationException`       | `400` / `422` — the request was malformed.                                        |
| `AuthenticationException`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.              |
| `PermissionDeniedException` | `403` — authenticated, but not allowed to touch this resource.                    |
| `NotFoundException`         | `404` — no such resource, or not one this key can see.                            |
| `ConflictException`         | `409` — conflicts with the current state (for example, a build already running).  |
| `RateLimitException`        | `429` throttle, after retries. Carries `retryAfter`.                              |
| `PlanLimitException`        | The plan behind the key does not cover the call. See [Plan limits](#plan-limits). |
| `ServerException`           | `5xx`, after retries where retrying is safe.                                      |
| `NetworkException`          | The request never got an answer (DNS, socket, timeout). `status` is `0`.          |
| `MisarDevException`         | The base class, and anything else.                                                |

## Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitException.offer` is the full offer as a `JsonNode`, every field kept: a headline,
the plans that would unblock you with their prices and what each one unlocks, and the URLs.
Convenience properties: `upgradeUrl` (billing URL, else pricing), `feature`, `currentPlan`,
`recommendedPlan` and `retryAfter`. All of that copy comes from the server, so render it
rather than writing your own.

```kotlin
import io.misar.dev.PlanLimitException

try {
    dev.projects.list()
} catch (e: PlanLimitException) {
    System.err.println(e.offer?.path("headline")?.asText())
    e.offer?.path("plans")?.forEach { plan ->
        System.err.println("  ${plan.path("name").asText()} — ${plan.path("price").asText()}")
    }
    System.err.println("Upgrade: ${e.upgradeUrl}")
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns a cold `Flow<SseEvent>` — the request
is sent when you collect it, and the connection closes when collection ends or is cancelled.
`SseEvent` is a data class of `event`, `data` (a `JsonNode`, or a `TextNode` when the payload
is not JSON) and `id`.

| Function                 | Route                                                                        |
| ------------------------ | ---------------------------------------------------------------------------- |
| `chat.completionsStream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studioStream`      | `POST /chat` — the studio's build conversation.                              |
| `projects.buildStream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
throws `PlanLimitException`.

```kotlin
dev.projects.buildStream(projectId).collect { event ->
    println("${event.event} ${event.data}")
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.paginate` returns
a `Flow<JsonNode>` that fetches each page only when the previous one is used up, and stops on
a short page. Items come from the page itself when it is an array, else from its first
array-valued field.

```kotlin
dev.paginate { offset, limit ->
    dev.templates.list(mapOf("offset" to offset, "limit" to limit))
}.collect { template -> println(template.path("name").asText()) }

// Page size and an item cap:
dev.paginate(pageSize = 100, maxItems = 500) { offset, limit ->
    dev.apiKeys.list(mapOf("offset" to offset, "limit" to limit))
}.collect { println(it) }
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- Maven Central — https://central.sonatype.com/artifact/io.misar/misardev-kotlin

MIT © [Misar.AI](https://misar.io)
