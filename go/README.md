# Misar.Dev Go SDK

> Create, build and ship apps on Misar.Dev from Go — context-aware, standard library only.

[![Go Reference](https://pkg.go.dev/badge/github.com/Misar-AI/misardev-sdks/go.svg)](https://pkg.go.dev/github.com/Misar-AI/misardev-sdks/go/misardev)
[![go](https://img.shields.io/badge/go-1.22%2B-00ADD8)](https://pkg.go.dev/github.com/Misar-AI/misardev-sdks/go/misardev)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · zero dependencies outside the standard library**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves. Go 1.22+, every call takes a `context.Context`, and every call returns the decoded JSON as `any` (`map[string]any`, `[]any`, …) — convert it to your own struct with `misardev.As[T]`.

---

## Install

### go get

```bash
go get github.com/Misar-AI/misardev-sdks/go
```

### Import

```go
import "github.com/Misar-AI/misardev-sdks/go/misardev"
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to `NewClient`, or set `MISARDEV_API_KEY`
and pass `""`. With neither, `NewClient` returns an error pointing at the key settings page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, comes back as `*misardev.PlanLimitError`,
and is never retried.

```go
dev, err := misardev.NewClient(os.Getenv("MISARDEV_API_KEY"))
if err != nil {
	log.Fatal(err)
}
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's doc comment
names the route it calls. The signature is always
`Method(ctx, pathParams…, requiredQuery…, body?, query?, opts…)`: `body` is a
`misardev.Body` (`map[string]any`, nil sends `{}`) and `query` a `misardev.Query`
(nil values are dropped).

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
| `dev.RAG`    | `Clear`, `Index`, `Search`                         | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource         | Methods                                                                                                                        | What it covers                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `dev.Connectors` | `Available`, `CreateConnection`, `DeleteConnection`, `List`, `ListConnections`, `TestConnection`, `Toggle`, `UpdateConnection` | Connector catalogue, per-account enable state, and per-project connections. |
| `dev.GitHub`     | `Disconnect`, `GetConnection`                                                                                                  | The linked GitHub account: read it or disconnect it.                        |
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
| `dev.APIKeys` | `Create`, `Delete`, `List`                                      | API keys — create, list, revoke.                                       |
| `dev.Usage`   | `List`, `Plan`, `Track`                                         | Usage for a period, your plan's allowances, and usage events.          |
| `dev.Billing` | `Checkout`, `Comparison`, `Plans`, `Subscription`, `SwitchPlan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `dev.Audit`   | `List`                                                          | Your account's audit log.                                              |
| `dev.Domains` | `Lookup`                                                        | Custom-domain availability lookup.                                     |

---

## Client

| Thing          | Detail                                                                                                                                                                                                                      |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point    | `misardev.NewClient(apiKey string, opts ...Option) (*Client, error)` — every resource is an exported field.                                                                                                                 |
| Base URL       | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`); override with `WithBaseURL`.                                                                                                                                           |
| Attempts       | `3` total (`WithMaxRetries`).                                                                                                                                                                                               |
| Timeout        | `60s` per attempt (`WithTimeout`); streams are bounded only by the context.                                                                                                                                                 |
| HTTP client    | `WithHTTPClient(*http.Client)` — tests, proxies, custom transports.                                                                                                                                                         |
| Headers        | `WithHeader` on every request, `WithCallHeader` on one call.                                                                                                                                                                |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms with jitter, honouring `Retry-After` (seconds or HTTP date), capped at 60s. |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server or network error, and streams.                                                                                                                                                 |
| Escape hatches | `dev.Request(ctx, method, path, query, body)` and `dev.Stream(ctx, method, path, query, body, StreamOptions{})` for any route.                                                                                              |
| Errors         | `*APIError` and nine typed errors — match with `errors.As`.                                                                                                                                                                 |

---

## Quick start

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/Misar-AI/misardev-sdks/go/misardev"
)

func main() {
	dev, err := misardev.NewClient(os.Getenv("MISARDEV_API_KEY"))
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()

	out, err := dev.Projects.Create(ctx, misardev.Body{
		"name":        "Coffee shop site",
		"description": "A one-page site for a neighbourhood coffee shop",
	})
	if err != nil {
		log.Fatal(err)
	}

	created, _ := misardev.As[struct {
		Project struct{ ID string } `json:"project"`
	}](out)
	fmt.Println(created.Project.ID)
}
```

## Primary functions

Create a project and write its files:

```go
out, err := dev.Projects.Create(ctx, misardev.Body{"name": "Landing page"})
created, _ := misardev.As[struct {
	Project struct{ ID string } `json:"project"`
}](out)
id := created.Project.ID

_, err = dev.Projects.WriteFiles(ctx, id, misardev.Body{
	"files": []map[string]string{
		{"path": "index.html", "content": "<h1>Hello</h1>"},
		{"path": "styles.css", "content": "h1 { color: #22c55e; }"},
	},
})
files, err := dev.Projects.ListFiles(ctx, id)
```

Deploy — check the subdomain first; required query parameters are positional:

```go
check, err := dev.Projects.CheckSubdomain(ctx, id, "coffee-shop")
deployment, err := dev.Projects.Deploy(ctx, id, misardev.Body{"subdomain": "coffee-shop"})
status, err := dev.Projects.GetDeployment(ctx, id)
```

List templates and start a project from one:

```go
out, err := dev.Templates.List(ctx, misardev.Query{"featured": true, "limit": 10})
page, _ := misardev.As[struct {
	Templates []struct{ ID, Name string } `json:"templates"`
}](out)

project, err := dev.Templates.Use(ctx, page.Templates[0].ID, misardev.Body{
	"projectName": "My portfolio",
})
```

Ask the AI with an OpenAI-compatible chat completion:

```go
out, err := dev.Chat.Completions(ctx, misardev.Body{
	"model":    "misar-online",
	"messages": []map[string]string{{"role": "user", "content": "What's new in CSS this year?"}},
})
completion, _ := misardev.As[struct {
	Choices []struct {
		Message struct{ Content string } `json:"message"`
	} `json:"choices"`
}](out)
fmt.Println(completion.Choices[0].Message.Content)
```

Stream a completion as it is written — see [Streaming](#streaming):

```go
s, err := dev.Chat.CompletionsStream(ctx, misardev.Body{
	"model":    "misar-online",
	"messages": []map[string]string{{"role": "user", "content": "Write a haiku"}},
})
```

Search your code, by text and semantically:

```go
hits, err := dev.Search.Code(ctx, misardev.Query{"q": "useEffect", "types": "files", "limit": 20})
semantic, err := dev.RAG.Search(ctx, id, misardev.Query{"query": "where do we send email?"})
```

Read usage and the plan's allowances:

```go
plan, err := dev.Usage.Plan(ctx)
usage, err := dev.Usage.List(ctx, misardev.Query{"days": 30})
```

Create an account API key (the secret is shown once):

```go
key, err := dev.Account.CreateKey(ctx, misardev.Body{"name": "CI"})
```

## Errors

Every non-2xx answer comes back as a typed error; match with `errors.As`. Each embeds
`*misardev.APIError`, which carries `Status`, `Message`, `Code`, the decoded `Body` and the
`RequestID` (from `x-request-id`), so `errors.As(err, &apiErr)` catches them all.

| Type                     | When                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `*ValidationError`       | `400` / `422` — the request was malformed.                                                     |
| `*AuthenticationError`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.                           |
| `*PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                                 |
| `*NotFoundError`         | `404` — no such resource, or not one this key can see.                                         |
| `*ConflictError`         | `409` — conflicts with the current state (for example, a build already running).               |
| `*RateLimitError`        | `429` throttle, after retries. Carries `RetryAfter` (seconds, `-1` when not sent).             |
| `*PlanLimitError`        | The plan behind the key does not cover the call. See below.                                    |
| `*ServerError`           | `5xx`, after retries where retrying is safe.                                                   |
| `*NetworkError`          | The request never got an answer (DNS, socket, timeout). `Status` is `0`; unwraps to the cause. |
| `*APIError`              | The base type, and any other status.                                                           |

```go
_, err := dev.Projects.Get(ctx, "p_123")
var notFound *misardev.NotFoundError
var apiErr *misardev.APIError
switch {
case errors.As(err, &notFound):
	log.Printf("no such project (request %s)", notFound.RequestID)
case errors.As(err, &apiErr):
	log.Printf("API error %d %s: %s", apiErr.Status, apiErr.Code, apiErr.Message)
}
```

## Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError.Offer` is the full offer as a `map[string]any`, every field kept: a headline,
the plans that would unblock you with their prices and what each one unlocks, and the URLs.
All of that copy comes from the server, so render it rather than writing your own. The
accessors `UpgradeURL()` (billing URL, falling back to pricing), `Feature()`, `Reason()`,
`Headline()`, `CurrentPlan()`, `RecommendedPlan()` and `Plans()` read the common fields, and
`RetryAfter` holds the `Retry-After` seconds (`-1` when absent).

```go
_, err := dev.Projects.List(ctx, nil)
var limit *misardev.PlanLimitError
if errors.As(err, &limit) {
	fmt.Fprintln(os.Stderr, limit.Headline())
	for _, p := range limit.Plans() {
		fmt.Fprintf(os.Stderr, "  %v — %v\n", p["name"], p["price"])
	}
	fmt.Fprintln(os.Stderr, "Upgrade:", limit.UpgradeURL())
	// limit.Feature(), limit.CurrentPlan(), limit.RecommendedPlan(), limit.RetryAfter
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns a `*misardev.Stream`; iterate it with
`Next()` / `Event()`, then check `Err()`. An event is a `misardev.SSEEvent{Event, Data, ID}`,
with `Data` JSON-decoded when possible and the raw string otherwise.

| Method                   | Route                                                                          |
| ------------------------ | ------------------------------------------------------------------------------ |
| `Chat.CompletionsStream` | `POST /v1/chat/completions` — sets `"stream": true` for you, ends at `[DONE]`. |
| `Chat.StudioStream`      | `POST /chat` — the studio's build conversation.                                |
| `Projects.BuildStream`   | `GET /projects/{id}/build-stream` — live build progress.                       |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
comes back as `*PlanLimitError` (from the call, or from `Err()`). Cancel the context or call
`Close()` to stop early.

```go
s, err := dev.Chat.CompletionsStream(ctx, misardev.Body{
	"model":    "misar-online",
	"messages": []map[string]string{{"role": "user", "content": "Write a haiku"}},
})
if err != nil {
	log.Fatal(err)
}
defer s.Close()
for s.Next() {
	chunk, _ := misardev.As[struct {
		Choices []struct {
			Delta struct{ Content string } `json:"delta"`
		} `json:"choices"`
	}](s.Event().Data)
	if len(chunk.Choices) > 0 {
		fmt.Print(chunk.Choices[0].Delta.Content)
	}
}
if err := s.Err(); err != nil {
	log.Fatal(err)
}

build, err := dev.Projects.BuildStream(ctx, id)
if err != nil {
	log.Fatal(err)
}
defer build.Close()
for build.Next() {
	ev := build.Event()
	fmt.Println(ev.Event, ev.Data)
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `misardev.Paginate`
walks every page and stops on a short one, reading items from the page when it is an array
or from its first array-valued field otherwise:

```go
p := misardev.Paginate(ctx, func(ctx context.Context, offset, limit int) (any, error) {
	return dev.Templates.List(ctx, misardev.Query{"offset": offset, "limit": limit})
}, misardev.PaginateOptions{PageSize: 50})
for p.Next() {
	fmt.Println(p.Item())
}
if err := p.Err(); err != nil {
	log.Fatal(err)
}
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- pkg.go.dev — https://pkg.go.dev/github.com/Misar-AI/misardev-sdks/go/misardev

MIT © [Misar.AI](https://misar.io)
