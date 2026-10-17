# Misar.Dev .NET SDK

> Create, build and ship apps on Misar.Dev from C# — async/await, cancellation, no dependencies beyond the BCL.

[![NuGet](https://img.shields.io/nuget/v/MisarDev)](https://www.nuget.org/packages/MisarDev)
[![net](https://img.shields.io/badge/.NET-8.0-512BD4)](https://www.nuget.org/packages/MisarDev)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · no dependencies beyond the BCL**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

Targets `net8.0` and uses `System.Text.Json`. Resources hang off the client (`dev.Projects`, `dev.Templates`, …); every method takes an optional `CancellationToken` and returns `Task<JsonNode?>`, and every stream is an `IAsyncEnumerable<SseEvent>`.

---

## Install

### dotnet CLI

```bash
dotnet add package MisarDev --version 1.0.0
```

### PackageReference

```xml
<PackageReference Include="MisarDev" Version="1.0.0" />
```

### Package Manager

```powershell
Install-Package MisarDev -Version 1.0.0
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `new MisarDevClient()` with no arguments. With neither, the
constructor throws a `MisarDevException` that points at the API-keys page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, throws `PlanLimitException`, and is
never retried.

```csharp
using MisarDev;

using var dev = new MisarDevClient(Environment.GetEnvironmentVariable("MISARDEV_API_KEY"));
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's XML doc names
the route it calls.

### Build and ship

| Resource          | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | What it covers                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `dev.Projects`    | `AddCollaborator`, `Archive`, `BuildStatus`, `CancelBuild`, `CheckSubdomain`, `Create`, `CreateConversation`, `Delete`, `DeleteEnv`, `DeleteSkills`, `Deploy`, `Duplicate`, `Export`, `Get`, `GetBackend`, `GetDeployment`, `GetDomain`, `GetEnv`, `GetKnowledge`, `GetSkills`, `GetTools`, `ImportArtifact`, `List`, `ListCheckpoints`, `ListCollaborators`, `ListConversations`, `ListFiles`, `ProvisionBackend`, `RemoveCollaborator`, `RemoveDomain`, `Restore`, `SetDomain`, `Undeploy`, `Update`, `UpdateEnv`, `UpdateKnowledge`, `UpdateSkills`, `UpdateSubdomain`, `UpdateTools`, `WriteFiles`, `BuildStream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `dev.Templates`   | `Create`, `Delete`, `Get`, `List`, `Remix`, `Update`, `Use`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `dev.Checkpoints` | `Delete`, `Restore`, `Update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Saved project snapshots: rename, restore, delete.                                                                              |
| `dev.Builds`      | `List`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Recent builds across your projects.                                                                                            |

### AI

| Resource     | Methods                                            | What it covers                                                                                    |
| ------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `dev.Chat`   | `Completions`, `StudioStream`, `CompletionsStream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `dev.Search` | `Code`, `Web`                                      | Web-grounded answers with citations, and search across your own code.                             |
| `dev.Rag`    | `Clear`, `Index`, `Search`                         | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource         | Methods                                                                                                                        | What it covers                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `dev.Connectors` | `Available`, `CreateConnection`, `DeleteConnection`, `List`, `ListConnections`, `TestConnection`, `Toggle`, `UpdateConnection` | Connector catalogue, per-account enable state, and per-project connections. |
| `dev.Github`     | `Disconnect`, `GetConnection`                                                                                                  | The linked GitHub account: read it or disconnect it.                        |
| `dev.Skills`     | `Get`, `List`                                                                                                                  | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource            | Methods                                                                                                                                        | What it covers                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `dev.Organizations` | `AcceptInvitation`, `Create`, `CreateInvitation`, `List`, `ListInvitations`, `ListMembers`, `RemoveMember`, `RevokeInvitation`, `UpdateMember` | Organizations, members and invitations.       |
| `dev.Gallery`       | `Like`, `List`, `Unlike`                                                                                                                       | The public community gallery, and likes.      |
| `dev.Profile`       | `Follow`, `Get`, `Unfollow`                                                                                                                    | Public builder profiles, follow and unfollow. |
| `dev.Notifications` | `List`, `MarkAllRead`, `MarkRead`                                                                                                              | In-app notifications and read state.          |
| `dev.Reports`       | `Create`                                                                                                                                       | Report abusive content.                       |

### Account, plan and billing

| Resource      | Methods                                                         | What it covers                                                         |
| ------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `dev.Account` | `CreateKey`, `DeleteKey`, `Export`, `ListKeys`, `UpdateKey`     | Account API keys (with expiry and IP allowlists) and your data export. |
| `dev.ApiKeys` | `Create`, `Delete`, `List`                                      | API keys — create, list, revoke.                                       |
| `dev.Usage`   | `List`, `Plan`, `Track`                                         | Usage for a period, your plan's allowances, and usage events.          |
| `dev.Billing` | `Checkout`, `Comparison`, `Plans`, `Subscription`, `SwitchPlan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `dev.Audit`   | `List`                                                          | Your account's audit log.                                              |
| `dev.Domains` | `Lookup`                                                        | Custom-domain availability lookup.                                     |

---

## Client

| Thing          | Detail                                                                                                                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entry point    | `new MisarDevClient(apiKey?, options?)` — every resource is a property on it. Implements `IDisposable` and owns its `HttpClient` unless you pass one.                                      |
| `BaseUrl`      | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`)                                                                                                                                        |
| `MaxRetries`   | `3` total attempts                                                                                                                                                                         |
| `Timeout`      | 60 seconds per attempt                                                                                                                                                                     |
| `HttpClient`   | Inject your own `HttpClient` (tests, proxies, `IHttpClientFactory`). Never disposed by the SDK.                                                                                            |
| `Headers`      | Extra headers on every request.                                                                                                                                                            |
| Call signature | `dev.Resource.Method(pathParams…, requiredQuery…, body?, query?, cancellationToken?)`                                                                                                      |
| Payloads       | `body` and `query` take any `object` — anonymous objects, dictionaries or `JsonNode` — serialized with `System.Text.Json`. Null query values are dropped.                                  |
| Results        | `Task<JsonNode?>`: objects and arrays as `JsonNode`, `null` for `204`/empty bodies, a string value for non-JSON.                                                                           |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms, honouring `Retry-After` (capped at 60 s). |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server error, and streams.                                                                                                                           |
| Escape hatches | `dev.RequestAsync(method, path, body, query)` and `dev.StreamAsync(method, path, …)` for any route.                                                                                        |
| Errors         | `MisarDevException` and nine subclasses, all in the `MisarDev` namespace.                                                                                                                  |

---

## Quick start

```csharp
using MisarDev;

using var dev = new MisarDevClient(Environment.GetEnvironmentVariable("MISARDEV_API_KEY"));

var created = await dev.Projects.Create(new {
    name = "Coffee shop site",
    description = "A one-page site for a neighbourhood coffee shop",
});

Console.WriteLine(created!["project"]!["id"]!.GetValue<string>());
```

## Primary functions

### Create a project and write its files

```csharp
var created = await dev.Projects.Create(new { name = "Landing page" });
string projectId = created!["project"]!["id"]!.GetValue<string>();

await dev.Projects.WriteFiles(projectId, new {
    files = new[] {
        new { path = "index.html", content = "<h1>Hello</h1>" },
        new { path = "styles.css", content = "h1 { color: #22c55e; }" },
    },
});

var files = await dev.Projects.ListFiles(projectId);
```

### Deploy

```csharp
// Check the subdomain first — required query params are positional.
var check = await dev.Projects.CheckSubdomain(projectId, "coffee-shop");

var deployment = await dev.Projects.Deploy(projectId, new { subdomain = "coffee-shop" });
var status = await dev.Projects.GetDeployment(projectId);
```

### Start from a template

```csharp
var page = await dev.Templates.List(query: new { featured = true, limit = 10 });
string templateId = page!["templates"]![0]!["id"]!.GetValue<string>();

var fromTemplate = await dev.Templates.Use(templateId, new { projectName = "My portfolio" });
```

### Ask the AI (OpenAI-compatible)

```csharp
var completion = await dev.Chat.Completions(new {
    model = "misar-online",
    messages = new[] { new { role = "user", content = "What's new in CSS this year?" } },
});

Console.WriteLine(completion!["choices"]![0]!["message"]!["content"]);
```

### Search your code

```csharp
var hits = await dev.Search.Code(query: new { q = "useEffect", types = "files", limit = 20 });
var semantic = await dev.Rag.Search(projectId, new { query = "where do we send email?" });
```

### Read usage and plan

```csharp
var plan = await dev.Usage.Plan();
var usage = await dev.Usage.List(query: new { days = 30 });
```

### Manage API keys

```csharp
var key = await dev.Account.CreateKey(new { name = "CI" });
Console.WriteLine(key!["key"]); // shown once and never again
```

## Errors

Every non-2xx answer throws a typed exception, all in the `MisarDev` namespace. Each carries
`Status`, `Message`, `Code`, the decoded `Body` (`JsonNode?`), the `RawBody` and the
`RequestId` (from `x-request-id`). `catch (MisarDevException)` catches everything the SDK
throws.

| Type                        | When                                                                             |
| --------------------------- | -------------------------------------------------------------------------------- |
| `ValidationException`       | `400` / `422` — the request was malformed.                                       |
| `AuthenticationException`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDeniedException` | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFoundException`         | `404` — no such resource, or not one this key can see.                           |
| `ConflictException`         | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimitException`        | `429` throttle, after retries. Carries `RetryAfter` (seconds).                   |
| `PlanLimitException`        | The plan behind the key does not cover the call. See below.                      |
| `ServerException`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkException`          | The request never got an answer (DNS, socket, timeout). `Status` is `0`.         |
| `MisarDevException`         | The base class, and anything else.                                               |

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitException.Offer` is the full offer as a `JsonObject`, every field the server sent:
a headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. All of that copy comes from the server, so render it rather than writing your own.
Convenience properties: `UpgradeUrl` (`offer.urls.billing`, else `offer.urls.pricing`),
`Feature`, `CurrentPlan`, `RecommendedPlan`, `Reason`, `Headline` and `RetryAfter`.

```csharp
try
{
    await dev.Projects.List();
}
catch (PlanLimitException e)
{
    Console.Error.WriteLine(e.Offer?["headline"]);
    foreach (var plan in e.Offer?["plans"]?.AsArray() ?? new JsonArray())
        Console.Error.WriteLine($"  {plan?["name"]} — {plan?["price"]}");
    Console.Error.WriteLine($"Upgrade: {e.UpgradeUrl}");
    // e.Feature, e.CurrentPlan, e.RecommendedPlan, e.RetryAfter
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each is an `IAsyncEnumerable<SseEvent>`, where an
`SseEvent` carries `Event`, `Data` (the JSON-decoded payload as a `JsonNode?`, or a string
value), `Id` and `Raw`:

| Method                   | Route                                                                        |
| ------------------------ | ---------------------------------------------------------------------------- |
| `Chat.CompletionsStream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `Chat.StudioStream`      | `POST /chat` — the studio's build conversation.                              |
| `Projects.BuildStream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
throws `PlanLimitException`.

```csharp
await foreach (var chunk in dev.Chat.CompletionsStream(new {
    model = "misar-online",
    messages = new[] { new { role = "user", content = "Write a haiku" } },
}))
    Console.Write(chunk.Data?["choices"]?[0]?["delta"]?["content"]);

await foreach (var ev in dev.Projects.BuildStream(projectId))
    Console.WriteLine($"{ev.Event} {ev.Raw}");
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.Paginate` walks
every page and stops on a short one. Items come from the page itself when it is an array,
otherwise from its first array-valued field:

```csharp
await foreach (var template in dev.Paginate((offset, limit) =>
                   dev.Templates.List(query: new { offset, limit })))
    Console.WriteLine(template?["name"]);
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- NuGet — https://www.nuget.org/packages/MisarDev

MIT © [Misar.AI](https://misar.io)
