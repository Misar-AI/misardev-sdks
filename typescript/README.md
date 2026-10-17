# Misar.Dev TypeScript SDK

> Create, build and ship apps on Misar.Dev from your own code — typed, from Node, Deno, Bun or the edge.

[![npm](https://img.shields.io/npm/v/@misardev/sdk)](https://www.npmjs.com/package/@misardev/sdk)
[![types](https://img.shields.io/badge/types-included-blue)](https://www.npmjs.com/package/@misardev/sdk)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · zero runtime dependencies**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

Works anywhere with a global `fetch` — Node 18+, Deno, Bun, Cloudflare Workers and other edge runtimes. Dual ESM + CJS build with bundled `.d.ts`.

---

## Install

### npm

```bash
npm install @misardev/sdk
```

### pnpm

```bash
pnpm add @misardev/sdk
```

### yarn

```bash
yarn add @misardev/sdk
```

### bun

```bash
bun add @misardev/sdk
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `new MisarDev()` with no arguments.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, raises `PlanLimitError`, and is never
retried.

```ts
import { MisarDev } from "@misardev/sdk";

const dev = new MisarDev(process.env.MISARDEV_API_KEY);
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's JSDoc names the
route it calls.

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

| Thing                | Detail                                                                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entry point          | `new MisarDev(apiKey?, options?)` — every resource is a readonly property on it.                                                                       |
| `options.baseURL`    | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`)                                                                                                    |
| `options.maxRetries` | `3` total attempts                                                                                                                                     |
| `options.timeoutMs`  | `60_000` per attempt                                                                                                                                   |
| `options.fetch`      | Inject a `fetch` implementation (tests, proxies).                                                                                                      |
| `options.headers`    | Extra headers on every request.                                                                                                                        |
| Call signature       | `resource.method(pathParams…, requiredQuery…, body?, query?, { signal, headers }?)`                                                                    |
| Retried              | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `PUT`, `DELETE`; exponential backoff from 250 ms, honouring `Retry-After`. |
| Never retried        | Plan refusals, `POST`/`PATCH` after a server error, and streams.                                                                                       |
| Escape hatches       | `dev.request(method, path, { query, body })` and `dev.stream(method, path, …)` for any route.                                                          |
| Errors               | `MisarDevError` and nine subclasses — all exported from the package root.                                                                              |

---

## Quick start

```ts
import { MisarDev } from "@misardev/sdk";

const dev = new MisarDev(process.env.MISARDEV_API_KEY);

const { project } = await dev.projects.create<{ project: { id: string } }>({
  name: "Coffee shop site",
  description: "A one-page site for a neighbourhood coffee shop",
});

console.log(project.id);
```

## Primary functions

### Create a project and write its files

```ts
const { project } = await dev.projects.create<{ project: { id: string } }>({
  name: "Landing page",
});

await dev.projects.writeFiles(project.id, {
  files: [
    { path: "index.html", content: "<h1>Hello</h1>" },
    { path: "styles.css", content: "h1 { color: #22c55e; }" },
  ],
});

const files = await dev.projects.listFiles(project.id);
```

### Deploy

```ts
// Check the subdomain first — required query params are positional.
const check = await dev.projects.checkSubdomain(project.id, "coffee-shop");

const deployment = await dev.projects.deploy(project.id, {
  subdomain: "coffee-shop",
});
const status = await dev.projects.getDeployment(project.id);
```

### Start from a template

```ts
const { templates } = await dev.templates.list<{
  templates: Array<{ id: string; name: string }>;
}>({
  featured: true,
  limit: 10,
});

const created = await dev.templates.use(templates[0].id, {
  projectName: "My portfolio",
});
```

### Ask the AI (OpenAI-compatible)

```ts
const completion = await dev.chat.completions<{
  choices: Array<{ message: { content: string } }>;
}>({
  model: "misar-online",
  messages: [{ role: "user", content: "What's new in CSS this year?" }],
});

console.log(completion.choices[0].message.content);
```

### Search your code

```ts
const hits = await dev.search.code({
  q: "useEffect",
  types: "files",
  limit: 20,
});
const semantic = await dev.rag.search(project.id, {
  query: "where do we send email?",
});
```

### Read usage and plan

```ts
const plan = await dev.usage.plan();
const usage = await dev.usage.list({ days: 30 });
```

### Manage API keys

```ts
const { key } = await dev.account.createKey<{ key: string }>({ name: "CI" });
console.log(key); // shown once and never again
```

## Errors

Every non-2xx answer raises a typed error, all exported from the package root. Each carries
`status`, `message`, `code`, the decoded `body` and the `requestId` (from `x-request-id`).

| Class                   | When                                                                             |
| ----------------------- | -------------------------------------------------------------------------------- |
| `ValidationError`       | `400` / `422` — the request was malformed.                                       |
| `AuthenticationError`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFoundError`         | `404` — no such resource, or not one this key can see.                           |
| `ConflictError`         | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimitError`        | `429` throttle, after retries. Carries `retryAfter`.                             |
| `PlanLimitError`        | The plan behind the key does not cover the call. See below.                      |
| `ServerError`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkError`          | The request never got an answer (DNS, socket, timeout). `status` is `0`.         |
| `MisarDevError`         | The base class, and anything else.                                               |

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError.offer` is the full offer: a headline, the plans that would unblock you with
their prices and what each one unlocks, and the URLs. All of that copy comes from the server,
so render it rather than writing your own.

```ts
import { MisarDev, PlanLimitError } from "@misardev/sdk";

try {
  await dev.projects.list();
} catch (err) {
  if (err instanceof PlanLimitError) {
    console.error(err.offer?.headline);
    for (const plan of err.offer?.plans ?? [])
      console.error(`  ${plan.name} — ${plan.price}`);
    console.error(`Upgrade: ${err.upgradeUrl}`);
    // err.feature, err.currentPlan, err.recommendedPlan, err.retryAfter
  } else {
    throw err;
  }
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each is an async generator of
`{ event, data, id }`:

| Method                   | Route                                                                        |
| ------------------------ | ---------------------------------------------------------------------------- |
| `chat.completionsStream` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studioStream`      | `POST /chat` — the studio's build conversation.                              |
| `projects.buildStream`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
raises `PlanLimitError`.

```ts
for await (const chunk of dev.chat.completionsStream<{
  choices: Array<{ delta: { content?: string } }>;
}>({
  model: "misar-online",
  messages: [{ role: "user", content: "Write a haiku" }],
})) {
  process.stdout.write(chunk.data.choices[0]?.delta.content ?? "");
}

for await (const event of dev.projects.buildStream(project.id)) {
  console.log(event.event, event.data);
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `dev.paginate` walks
every page and stops on a short one:

```ts
for await (const template of dev.paginate((offset, limit) =>
  dev.templates.list({ offset, limit }),
)) {
  console.log(template);
}
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- npm — https://www.npmjs.com/package/@misardev/sdk

MIT © [Misar.AI](https://misar.io)
