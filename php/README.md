# Misar.Dev PHP SDK

> Create, build and ship apps on Misar.Dev from PHP — one client, ext-curl and ext-json only.

[![Packagist](https://img.shields.io/packagist/v/misarai/misardev-php)](https://packagist.org/packages/misarai/misardev-php)
[![php](https://img.shields.io/badge/php-%3E%3D%208.1-777BB4)](https://packagist.org/packages/misarai/misardev-php)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · typed plan-limit errors**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI through an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

PHP 8.1+, with nothing but `ext-curl` and `ext-json` underneath. Requests take plain associative arrays and every method returns the decoded JSON — no DTOs to learn.

---

## Install

### Composer

```bash
composer require misarai/misardev-php
```

### composer.json

```json
{ "require": { "misarai/misardev-php": "^1.0" } }
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`. Pass it to the constructor, or set
`MISARDEV_API_KEY` and call `new MisarDev()` with no arguments.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, throws `PlanLimitError`, and is never
retried.

```php
use MisarDev\MisarDev;

$dev = new MisarDev(getenv('MISARDEV_API_KEY'));
```

---

## Resources

Every group the client exposes, and every public method on it. Each method's docblock names
the route it calls.

{"resources":21,"methods":106,"streams":3}

### Build and ship

| Resource            | Methods                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | What it covers                                                                                                                 |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `$dev->projects`    | `addCollaborator`, `archive`, `buildStatus`, `cancelBuild`, `checkSubdomain`, `create`, `createConversation`, `delete`, `deleteEnv`, `deleteSkills`, `deploy`, `duplicate`, `export`, `get`, `getBackend`, `getDeployment`, `getDomain`, `getEnv`, `getKnowledge`, `getSkills`, `getTools`, `importArtifact`, `list`, `listCheckpoints`, `listCollaborators`, `listConversations`, `listFiles`, `provisionBackend`, `removeCollaborator`, `removeDomain`, `restore`, `setDomain`, `undeploy`, `update`, `updateEnv`, `updateKnowledge`, `updateSkills`, `updateSubdomain`, `updateTools`, `writeFiles`, `buildStream` | Projects end to end: create, edit, files, builds, deploys, domains, env vars, collaborators, knowledge, skills, tools, export. |
| `$dev->templates`   | `create`, `delete`, `get`, `list`, `remix`, `update`, `use`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Starter templates: browse, create, remix, and start a project from one.                                                        |
| `$dev->checkpoints` | `delete`, `restore`, `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Saved project snapshots: rename, restore, delete.                                                                              |
| `$dev->builds`      | `list`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Recent builds across your projects.                                                                                            |

### AI

| Resource       | Methods                                            | What it covers                                                                                    |
| -------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `$dev->chat`   | `completions`, `studioStream`, `completionsStream` | OpenAI-compatible chat completions (plain and streamed) and the studio build conversation stream. |
| `$dev->search` | `code`, `web`                                      | Web-grounded answers with citations, and search across your own code.                             |
| `$dev->rag`    | `clear`, `index`, `search`                         | Index a project's code for semantic search, query it, clear it.                                   |

### Connect

| Resource           | Methods                                                                                                                        | What it covers                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `$dev->connectors` | `available`, `createConnection`, `deleteConnection`, `list`, `listConnections`, `testConnection`, `toggle`, `updateConnection` | Connector catalogue, per-account enable state, and per-project connections. |
| `$dev->github`     | `disconnect`, `getConnection`                                                                                                  | The linked GitHub account: read it or disconnect it.                        |
| `$dev->skills`     | `get`, `list`                                                                                                                  | Your Misar.AI skills library, read-only.                                    |

### Teams and community

| Resource              | Methods                                                                                                                                        | What it covers                                |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `$dev->organizations` | `acceptInvitation`, `create`, `createInvitation`, `list`, `listInvitations`, `listMembers`, `removeMember`, `revokeInvitation`, `updateMember` | Organizations, members and invitations.       |
| `$dev->gallery`       | `like`, `list`, `unlike`                                                                                                                       | The public community gallery, and likes.      |
| `$dev->profile`       | `follow`, `get`, `unfollow`                                                                                                                    | Public builder profiles, follow and unfollow. |
| `$dev->notifications` | `list`, `markAllRead`, `markRead`                                                                                                              | In-app notifications and read state.          |
| `$dev->reports`       | `create`                                                                                                                                       | Report abusive content.                       |

### Account, plan and billing

| Resource        | Methods                                                         | What it covers                                                         |
| --------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `$dev->account` | `createKey`, `deleteKey`, `export`, `listKeys`, `updateKey`     | Account API keys (with expiry and IP allowlists) and your data export. |
| `$dev->apiKeys` | `create`, `delete`, `list`                                      | API keys — create, list, revoke.                                       |
| `$dev->usage`   | `list`, `plan`, `track`                                         | Usage for a period, your plan's allowances, and usage events.          |
| `$dev->billing` | `checkout`, `comparison`, `plans`, `subscription`, `switchPlan` | Plans, plan comparison, subscription, checkout, plan switch.           |
| `$dev->audit`   | `list`                                                          | Your account's audit log.                                              |
| `$dev->domains` | `lookup`                                                        | Custom-domain availability lookup.                                     |

---

## Client

| Thing          | Detail                                                                                                                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entry point    | `new MisarDev\MisarDev($apiKey = null, baseUrl: …, maxRetries: …, timeout: …, httpClient: …, headers: …)` — every resource is a readonly property.                                         |
| `$apiKey`      | Falls back to `MISARDEV_API_KEY`; throws `MisarDevError` when neither is set.                                                                                                              |
| `baseUrl`      | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                       |
| `maxRetries`   | `3` total attempts.                                                                                                                                                                        |
| `timeout`      | `60.0` seconds per attempt. Streams have no overall timeout.                                                                                                                               |
| `httpClient`   | Any `MisarDev\Core\HttpClient` — inject one for tests or proxies. Defaults to cURL (10-second connect timeout).                                                                            |
| `headers`      | Extra headers on every request.                                                                                                                                                            |
| Call signature | `$dev->resource->method(pathParams…, requiredQuery…, $body = [], $query = [])`                                                                                                             |
| Results        | Decoded JSON as associative arrays (objects and lists alike). `204`/empty is `null`; a non-JSON body comes back as a string.                                                               |
| Retried        | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms, honouring `Retry-After` (capped at 60 s). |
| Never retried  | Plan refusals, `POST`/`PATCH` after a server error or dropped connection, and streams.                                                                                                     |
| Escape hatches | `$dev->request($method, $path, query: …, body: …)` and `$dev->stream($method, $path, …)` for any route.                                                                                    |
| Errors         | `MisarDev\MisarDevError` and nine subclasses.                                                                                                                                              |

---

## Quick start

```php
<?php
require 'vendor/autoload.php';

use MisarDev\MisarDev;

$dev = new MisarDev(getenv('MISARDEV_API_KEY'));

$created = $dev->projects->create([
    'name'        => 'Coffee shop site',
    'description' => 'A one-page site for a neighbourhood coffee shop',
]);

echo $created['project']['id'];
```

## Primary functions

### Create a project and write its files

```php
$projectId = $dev->projects->create(['name' => 'Landing page'])['project']['id'];

$dev->projects->writeFiles($projectId, [
    'files' => [
        ['path' => 'index.html', 'content' => '<h1>Hello</h1>'],
        ['path' => 'styles.css', 'content' => 'h1 { color: #22c55e; }'],
    ],
]);

$files = $dev->projects->listFiles($projectId);
```

### Deploy

```php
// Check the subdomain first — required query params are positional.
$check = $dev->projects->checkSubdomain($projectId, 'coffee-shop');

$deployment = $dev->projects->deploy($projectId, ['subdomain' => 'coffee-shop']);
$status     = $dev->projects->getDeployment($projectId);
```

### Start from a template

```php
$templates = $dev->templates->list(['featured' => true, 'limit' => 10])['templates'];

$created = $dev->templates->use($templates[0]['id'], ['projectName' => 'My portfolio']);
```

### Ask the AI (OpenAI-compatible)

```php
$completion = $dev->chat->completions([
    'model'    => 'misar-online',
    'messages' => [['role' => 'user', 'content' => "What's new in CSS this year?"]],
]);

echo $completion['choices'][0]['message']['content'];
```

### Stream a completion

```php
foreach ($dev->chat->completionsStream([
    'model'    => 'misar-online',
    'messages' => [['role' => 'user', 'content' => 'Write a haiku']],
]) as $chunk) {
    echo $chunk->data['choices'][0]['delta']['content'] ?? '';
}
```

### Search your code

```php
$hits     = $dev->search->code(['q' => 'useEffect', 'types' => 'files', 'limit' => 20]);
$semantic = $dev->rag->search($projectId, ['query' => 'where do we send email?']);
```

### Read usage and plan

```php
$plan  = $dev->usage->plan();
$usage = $dev->usage->list(['days' => 30]);
```

### Manage API keys

```php
$fresh = $dev->account->createKey(['name' => 'CI']);
echo $fresh['key'];   // shown once and never again
```

## Errors

Every non-2xx answer throws a typed error, all in the `MisarDev` namespace. Each carries
`$status`, the message (`getMessage()`), `$errorCode`, the decoded `$body` and the
`$requestId` (from `x-request-id`). `catch (MisarDev\MisarDevError $e)` catches everything
the SDK throws.

| Class                   | When                                                                             |
| ----------------------- | -------------------------------------------------------------------------------- |
| `ValidationError`       | `400` / `422` — the request was malformed.                                       |
| `AuthenticationError`   | `401` — the key is missing, revoked, expired or not a Misar.Dev key.             |
| `PermissionDeniedError` | `403` — authenticated, but not allowed to touch this resource.                   |
| `NotFoundError`         | `404` — no such resource, or not one this key can see.                           |
| `ConflictError`         | `409` — conflicts with the current state (for example, a build already running). |
| `RateLimitError`        | `429` throttle, after retries. Carries `$retryAfter` (seconds).                  |
| `PlanLimitError`        | The plan behind the key does not cover the call. See below.                      |
| `ServerError`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkError`          | The request never got an answer (DNS, socket, timeout). `$status` is `0`.        |
| `MisarDevError`         | The base class, and anything else. Extends `RuntimeException`.                   |

### Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError::$offer` is the full offer as an array, every field the server sent: a
headline, the plans that would unblock you with their prices and what each one unlocks, and
the URLs. All of that copy comes from the server, so render it rather than writing your own.
Convenience accessors: `upgradeUrl()` (billing, else pricing), `feature()`, `currentPlan()`,
`recommendedPlan()`, plus `$retryAfter` (seconds until a quota resets).

```php
use MisarDev\PlanLimitError;

try {
    $dev->projects->list();
} catch (PlanLimitError $e) {
    fwrite(STDERR, ($e->offer['headline'] ?? $e->getMessage()) . "\n");
    foreach ($e->offer['plans'] ?? [] as $plan) {
        fwrite(STDERR, "  {$plan['name']} — {$plan['price']}\n");
    }
    fwrite(STDERR, 'Upgrade: ' . $e->upgradeUrl() . "\n");
    // $e->feature(), $e->currentPlan(), $e->recommendedPlan(), $e->retryAfter
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each method returns a `Generator` of
`MisarDev\StreamEvent` (`$event`, `$data`, `$id`) — `$data` is the decoded JSON, or the raw
string when the payload is not JSON. Nothing is sent until you start iterating.

| Method                      | Route                                                                        |
| --------------------------- | ---------------------------------------------------------------------------- |
| `chat->completionsStream()` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat->studioStream()`      | `POST /chat` — the studio's build conversation.                              |
| `projects->buildStream()`   | `GET /projects/{id}/build-stream` — live build progress.                     |

A stream is never retried: replaying one that failed mid-flight would duplicate whatever you
had already read. A plan refusal — before the stream opens or as an error frame inside it —
throws `PlanLimitError`. `break` out of the loop to stop early; the connection is closed.

```php
foreach ($dev->chat->completionsStream([
    'model'    => 'misar-online',
    'messages' => [['role' => 'user', 'content' => 'Write a haiku']],
]) as $chunk) {
    echo $chunk->data['choices'][0]['delta']['content'] ?? '';
}

foreach ($dev->projects->buildStream($projectId) as $event) {
    echo $event->event, ' ', json_encode($event->data), "\n";
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `$dev->paginate()`
walks every page and stops on a short one. Items come from the page itself when it is a
list, otherwise from its first list-valued field (`templates`, `items`, …).

```php
foreach ($dev->paginate(fn (int $offset, int $limit) =>
    $dev->templates->list(['offset' => $offset, 'limit' => $limit])) as $template) {
    echo $template['name'], "\n";
}

// pageSize and maxItems are optional: $dev->paginate($fetch, 50, 200)
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- Packagist — https://packagist.org/packages/misarai/misardev-php

MIT © [Misar.AI](https://misar.io)
