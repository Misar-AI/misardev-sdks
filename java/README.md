# MisarDev Java SDK

> Create, build and ship apps on Misar.Dev from Java 11+ — one client, every route, typed errors.

[![Maven Central](https://img.shields.io/maven-central/v/io.misar/misardev)](https://central.sonatype.com/artifact/io.misar/misardev)
[![java](https://img.shields.io/badge/java-11%2B-007396)](https://central.sonatype.com/artifact/io.misar/misardev)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · SSE streaming and pagination**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Java 11+ on `java.net.http` with Jackson. Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves. Results are Jackson `JsonNode` values — objects and arrays alike.

---

## Install

### Maven

```xml
<dependency>
  <groupId>io.misar</groupId>
  <artifactId>misardev</artifactId>
  <version>1.0.0</version>
</dependency>
```

### Gradle (Kotlin DSL)

```kotlin
implementation("io.misar:misardev:1.0.0")
```

### Gradle (Groovy)

```groovy
implementation 'io.misar:misardev:1.0.0'
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `new MisarDevClient()` with no arguments. With neither, the
constructor throws a `MisarDevException` pointing at the API keys page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, raises `PlanLimitException`, and is never
retried.

```java
import io.misar.dev.MisarDevClient;

MisarDevClient dev = new MisarDevClient(System.getenv("MISARDEV_API_KEY"));
```

---

## Resources

Every group the client exposes, and every public method on it. Each resource is a public
final field on the client; each method's Javadoc names the route it calls.

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

| Thing             | Detail                                                                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point       | `new MisarDevClient()`, `new MisarDevClient(apiKey)` or `MisarDevClient.builder()…build()` — every resource is a public final field.                                                                  |
| `.baseUrl(..)`    | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                                  |
| `.maxRetries(..)` | `3` total attempts.                                                                                                                                                                                   |
| `.timeout(..)`    | `Duration.ofSeconds(60)` per attempt.                                                                                                                                                                 |
| `.httpClient(..)` | Inject your own `java.net.http.HttpClient` (proxies, custom TLS, tests).                                                                                                                              |
| `.header(..)`     | An extra header on every request.                                                                                                                                                                     |
| Call signature    | `resource.method(pathParams…, requiredQuery…, body?, query?)` — overloads drop the trailing optional `Map` arguments.                                                                                 |
| Results           | `JsonNode` (objects and arrays); `null` for `204`; a `TextNode` for a non-JSON body.                                                                                                                  |
| Retried           | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms with jitter, honouring `Retry-After`, capped at 60 s. |
| Never retried     | Plan refusals, `POST`/`PATCH` after a server error or dropped connection, and streams.                                                                                                                |
| Escape hatches    | `dev.request(method, path, query, body)` and `dev.stream(method, path, query, body, terminator)` for any route.                                                                                       |
| Errors            | `MisarDevException` (unchecked) and nine subclasses — see [Errors](#errors).                                                                                                                          |

The client is thread-safe; share one instance.

---

## Quick start

```java
import com.fasterxml.jackson.databind.JsonNode;
import io.misar.dev.MisarDevClient;
import java.util.Map;

MisarDevClient dev = new MisarDevClient(); // reads MISARDEV_API_KEY

JsonNode created = dev.projects.create(Map.of(
    "name", "Coffee shop site",
    "description", "A one-page site for a neighbourhood coffee shop"));

System.out.println(created.at("/project/id").asText());
```

## Primary functions

### Create a project and write its files

```java
String projectId = dev.projects.create(Map.of("name", "Landing page")).at("/project/id").asText();

dev.projects.writeFiles(projectId, Map.of("files", List.of(
    Map.of("path", "index.html", "content", "<h1>Hello</h1>"),
    Map.of("path", "styles.css", "content", "h1 { color: #22c55e; }"))));

JsonNode files = dev.projects.listFiles(projectId);
```

### Deploy

```java
// Check the subdomain first — required query params are positional.
JsonNode check = dev.projects.checkSubdomain(projectId, "coffee-shop");

JsonNode deployment = dev.projects.deploy(projectId, Map.of("subdomain", "coffee-shop"));
JsonNode status = dev.projects.getDeployment(projectId);
```

### Start from a template

```java
JsonNode templates = dev.templates.list(Map.of("featured", true, "limit", 10)).get("templates");

JsonNode started = dev.templates.use(templates.get(0).get("id").asText(),
    Map.of("projectName", "My portfolio"));
```

### Ask the AI (OpenAI-compatible)

```java
JsonNode completion = dev.chat.completions(Map.of(
    "model", "misar-online",
    "messages", List.of(Map.of("role", "user", "content", "What's new in CSS this year?"))));

System.out.println(completion.at("/choices/0/message/content").asText());
```

### Stream a completion

```java
try (SseStream chunks = dev.chat.completionsStream(Map.of(
        "model", "misar-online",
        "messages", List.of(Map.of("role", "user", "content", "Write a haiku"))))) {
    for (SseEvent chunk : chunks) {
        System.out.print(chunk.data().at("/choices/0/delta/content").asText(""));
    }
}
```

### Search your code

```java
JsonNode hits = dev.search.code(Map.of("q", "useEffect", "types", "files", "limit", 20));
JsonNode semantic = dev.rag.search(projectId, Map.of("query", "where do we send email?"));
```

### Read usage and plan

```java
JsonNode plan = dev.usage.plan();
JsonNode usage = dev.usage.list(Map.of("days", 30));
```

## Errors

Every non-2xx answer throws a typed, unchecked exception from `io.misar.dev`. Each carries
`getStatus()`, `getMessage()`, `getCode()`, the decoded `getBody()` and `getRequestId()`
(from `x-request-id`).

| Class                       | When                                                                              |
| --------------------------- | --------------------------------------------------------------------------------- |
| `ValidationException`       | `400` / `422` — the request was malformed.                                        |
| `AuthenticationException`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.              |
| `PermissionDeniedException` | `403` — authenticated, but not allowed to touch this resource.                    |
| `NotFoundException`         | `404` — no such resource, or not one this key can see.                            |
| `ConflictException`         | `409` — conflicts with the current state (for example, a build already running).  |
| `RateLimitException`        | `429` throttle, after retries. Carries `getRetryAfter()`.                         |
| `PlanLimitException`        | The plan behind the key does not cover the call. See [Plan limits](#plan-limits). |
| `ServerException`           | `5xx`, after retries where retrying is safe.                                      |
| `NetworkException`          | The request never got an answer (DNS, socket, timeout). Status is `0`.            |
| `MisarDevException`         | The base class, and anything else.                                                |

## Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitException.getOffer()` is the full offer as a `JsonNode`, every field kept: a
headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. Convenience accessors: `getUpgradeUrl()` (billing URL, else pricing),
`getFeature()`, `getCurrentPlan()`, `getRecommendedPlan()` and `getRetryAfter()`. All of
that copy comes from the server, so render it rather than writing your own.

```java
import io.misar.dev.PlanLimitException;

try {
    dev.projects.list();
} catch (PlanLimitException e) {
    System.err.println(e.getOffer().path("headline").asText());
    for (JsonNode plan : e.getOffer().path("plans")) {
        System.err.printf("  %s — %s%n", plan.path("name").asText(), plan.path("price").asText());
    }
    System.err.println("Upgrade: " + e.getUpgradeUrl());
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns an `SseStream` — an
`Iterable<SseEvent>` you close (try-with-resources), also available as a
`java.util.stream.Stream` via `.stream()`. Each `SseEvent` has `event()`, `data()` (a
`JsonNode`, or a `TextNode` when the payload is not JSON) and `id()`.

| Method                   | Route                                                                        |
| ------------------------ | ---------------------------------------------------------------------------- |
| `chat.completionsStream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studioStream`      | `POST /chat` — the studio's build conversation.                              |
| `projects.buildStream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
throws `PlanLimitException`.

```java
try (SseStream events = dev.projects.buildStream(projectId)) {
    for (SseEvent e : events) {
        System.out.println(e.event() + " " + e.data());
    }
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.paginate` walks
every page lazily and stops on a short one. Items come from the page itself when it is an
array, else from its first array-valued field.

```java
for (JsonNode template : dev.paginate((offset, limit) ->
        dev.templates.list(Map.of("offset", offset, "limit", limit)))) {
    System.out.println(template.path("name").asText());
}

// Page size and an item cap:
dev.paginate((offset, limit) -> dev.apiKeys.list(Map.of("offset", offset, "limit", limit)), 100, 500);
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- Maven Central — https://central.sonatype.com/artifact/io.misar/misardev

MIT © [Misar.AI](https://misar.io)
