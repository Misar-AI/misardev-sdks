# Misar.Dev Flutter SDK

> Create, build and ship apps on Misar.Dev from your Flutter app — iOS, Android, macOS, Windows, Linux and web.

[![pub](https://img.shields.io/pub/v/misardev_flutter)](https://pub.dev/packages/misardev_flutter)
[![flutter](https://img.shields.io/badge/flutter-%3E%3D3.10.0-02569B)](https://pub.dev/packages/misardev_flutter)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**21 resource groups · 106 methods · 3 streams · secure key storage · typed plan-limit errors**

Misar.Dev turns a description into a working app and puts it online. This SDK is the same API the studio uses: create a project, write its files, deploy it to a subdomain or your own domain, start from a template, ask the AI with an OpenAI-compatible chat endpoint, and search across your code.

Every resource and method is generated from the API's own route tree (`sdks/manifest.json`), so the client never drifts from what the server actually serves.

Flutter `>=3.10.0` (Dart `>=3.0.0 <4.0.0`), depending on `package:http`, `package:http_parser` and `flutter_secure_storage`. Every method returns `Future<dynamic>` — the decoded JSON value (a `Map`, a `List`, …), not a generated model. Writing a server, CLI or pure-Dart package instead? Use [`misardev`](https://pub.dev/packages/misardev), the same client without the Flutter dependency.

---

## Install

### flutter pub

```bash
flutter pub add misardev_flutter
```

### pubspec.yaml

```yaml
dependencies:
  misardev_flutter: ^1.0.0
```

---

## Authentication

Create an API key at https://www.misar.dev/settings/api-keys. It starts with `mdk_` and is
sent as `Authorization: Bearer mdk_…`.

In an app, keep the key in the platform's secure storage rather than in source: `SecureKeyStore`
wraps `flutter_secure_storage` (the Keychain on iOS and macOS, Keystore-backed encrypted storage
on Android), and `MisarDev.fromKeyStore` builds a client from it. You can also pass `apiKey:`
directly, or set `MISARDEV_API_KEY` where a process environment exists (desktop, tests). With
no key at all, construction throws a `MisarDevError` (`code: "missing_api_key"`) that points at
the API keys page.

Every call is checked against the plan behind that key. There is no client-side limit
checking — the server decides, and the SDK surfaces its answer. A plan refusal carries
`code: "plan_limit_exceeded"` and an upgrade offer, raises `PlanLimitError`, and is never
retried.

```dart
import 'package:misardev_flutter/misardev_flutter.dart';

const store = SecureKeyStore();
await store.saveApiKey('mdk_…'); // once, e.g. after the user pastes it in

final dev = await MisarDev.fromKeyStore(store);
// or: MisarDev(apiKey: 'mdk_…')

await store.deleteApiKey(); // sign out
```

`SecureKeyStore` implements `ApiKeyStore`; implement that interface yourself to load the key
from anywhere else.

---

## Resources

Every group the client exposes, and every public method on it. Each method's doc comment names
the route it calls. The call shape is the same everywhere:
`resource.method(pathParams…, requiredQuery…, [body, query])` — `body` is a
`Map<String, dynamic>` for routes that read one, `query` a `Map<String, Object?>` of the
optional query parameters (nulls are dropped).

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

| Thing         | Detail                                                                                                                                                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entry point   | `MisarDev({apiKey, baseUrl, maxRetries, timeout, httpClient, headers, environment})` or `await MisarDev.fromKeyStore(store, …)` — every resource is a final field on it.                                                     |
| Key storage   | `SecureKeyStore` (`saveApiKey`, `loadApiKey`, `deleteApiKey`) over `flutter_secure_storage`; any `ApiKeyStore` works with `fromKeyStore`.                                                                                    |
| `apiKey`      | `mdk_…`; falls back to `MISARDEV_API_KEY`.                                                                                                                                                                                   |
| `baseUrl`     | `https://api.misar.io/dev` (or `MISARDEV_BASE_URL`).                                                                                                                                                                         |
| `maxRetries`  | `3` total attempts.                                                                                                                                                                                                          |
| `timeout`     | `Duration(seconds: 60)` per attempt — builds and AI calls are slow.                                                                                                                                                          |
| `httpClient`  | Inject an `http.Client` (tests, proxies, platform clients). A client you pass is never closed by `dev.close()`.                                                                                                              |
| `headers`     | Extra headers on every request.                                                                                                                                                                                              |
| `environment` | Where to read `MISARDEV_API_KEY` / `MISARDEV_BASE_URL` from; defaults to the process environment (none on the web or mobile, so pass the key or use a key store there).                                                      |
| Results       | `Future<dynamic>` — the decoded JSON (`Map`, `List`, …); `null` for an empty answer; the raw `String` for a non-JSON one.                                                                                                    |
| Retried       | `429` (any method), and `500`/`502`/`503`/`504`/network failures for `GET`, `HEAD`, `OPTIONS`, `PUT`, `DELETE`; exponential backoff from 250 ms with jitter, honouring `Retry-After` (seconds or HTTP-date), capped at 60 s. |
| Never retried | Plan refusals, `POST`/`PATCH` after a server error or dropped connection, and streams.                                                                                                                                       |
| Escape hatch  | `dev.transport.request(method, path, query:, body:)` and `dev.transport.stream(…)` for any route.                                                                                                                            |
| Errors        | `MisarDevError` and nine subclasses — all exported from `package:misardev_flutter/misardev_flutter.dart`.                                                                                                                    |
| Cleanup       | `dev.close()` releases the HTTP client the SDK created.                                                                                                                                                                      |

---

## Quick start

```dart
import 'package:misardev_flutter/misardev_flutter.dart';

Future<String> createSite() async {
  final dev = await MisarDev.fromKeyStore(const SecureKeyStore());
  try {
    final created = await dev.projects.create({
      'name': 'Coffee shop site',
      'description': 'A one-page site for a neighbourhood coffee shop',
    });
    return created['project']['id'] as String;
  } finally {
    dev.close();
  }
}
```

## Primary functions

### Create a project and write its files

```dart
final created = await dev.projects.create({'name': 'Landing page'});
final projectId = created['project']['id'] as String;

await dev.projects.writeFiles(projectId, {
  'files': [
    {'path': 'index.html', 'content': '<h1>Hello</h1>'},
    {'path': 'styles.css', 'content': 'h1 { color: #22c55e; }'},
  ],
});

final files = await dev.projects.listFiles(projectId);
```

### Deploy

```dart
// Check the subdomain first — required query params are positional.
final check = await dev.projects.checkSubdomain(projectId, 'coffee-shop');

final deployment = await dev.projects.deploy(projectId, {'subdomain': 'coffee-shop'});
final status = await dev.projects.getDeployment(projectId);
```

### Start from a template

```dart
final page = await dev.templates.list({'featured': true, 'limit': 10});
final templates = page['templates'] as List;

final project = await dev.templates.use(templates.first['id'] as String, {
  'projectName': 'My portfolio',
});
```

### Ask the AI (OpenAI-compatible)

```dart
final completion = await dev.chat.completions({
  'model': 'misar-online',
  'messages': [
    {'role': 'user', 'content': "What's new in CSS this year?"},
  ],
});

debugPrint(completion['choices'][0]['message']['content'] as String?);
```

### Stream a completion

```dart
await for (final chunk in dev.chat.completionsStream({
  'model': 'misar-online',
  'messages': [
    {'role': 'user', 'content': 'Write a haiku'},
  ],
})) {
  setState(() => _reply += chunk.data['choices'][0]['delta']['content'] ?? '');
}
```

### Search your code

```dart
final hits = await dev.search.code({'q': 'useEffect', 'types': 'files', 'limit': 20});
final semantic = await dev.rag.search(projectId, {'query': 'where do we send email?'});
```

### Read usage and plan

```dart
final plan = await dev.usage.plan();
final usage = await dev.usage.list({'days': 30});
```

### Manage API keys

```dart
final key = await dev.account.createKey({'name': 'CI'});
final secret = key['key'] as String; // shown once and never again — store it now
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
| `RateLimitError`        | `429` throttle, after retries. Carries `retryAfter` (seconds).                   |
| `PlanLimitError`        | The plan behind the key does not cover the call. See below.                      |
| `ServerError`           | `5xx`, after retries where retrying is safe.                                     |
| `NetworkError`          | The request never got an answer (DNS, socket, timeout). `status` is `0`.         |
| `MisarDevError`         | The base class, and anything else.                                               |

The message is read from `error` (a string), then `error.message` (the OpenAI shape the
`/v1/*` routes use), then `message`, then the raw body; `code` from `code` or `error.code`.

Catch from most specific to least:

```dart
try {
  await dev.projects.deploy(projectId);
} on PlanLimitError catch (e) {
  showUpgradeSheet(e); // see Plan limits
} on RateLimitError catch (e) {
  debugPrint('throttled; retry in ${e.retryAfter}s');
} on NetworkError catch (e) {
  debugPrint('transport failure: ${e.message}');
} on MisarDevError catch (e) {
  debugPrint('${e.status} ${e.code}: ${e.message} (request ${e.requestId})');
}
```

## Plan limits

A feature that is not on the plan answers **`402`** (`reason: "feature_locked"`); a spent
allowance answers **`429`** (`reason: "quota_exhausted"`, with `Retry-After`). Both carry
`code: "plan_limit_exceeded"` and an `upgrade` offer. The SDK keys on that code — never on
the status — so a spent quota is never mistaken for a throttle and never retried.

`PlanLimitError.offer` is the full offer as a `Map<String, dynamic>`, every field kept: a
headline, the plans that would unblock you with their prices and what each one unlocks, the
usage, and the URLs. All of that copy comes from the server, so render it rather than writing
your own. Convenience getters: `upgradeUrl` (`urls.billing`, falling back to `urls.pricing`),
`feature`, `reason`, `currentPlan` (`current_plan.slug`), `recommendedPlan`, and `retryAfter`
(seconds until a quota resets).

```dart
void showUpgradeSheet(PlanLimitError e) {
  final offer = e.offer ?? const {};
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(title: Text('${offer['headline']}')),
        for (final plan in (offer['plans'] as List? ?? const []))
          ListTile(title: Text('${plan['name']}'), trailing: Text('${plan['price']}')),
        // Open e.upgradeUrl with url_launcher. Also: e.feature, e.currentPlan,
        // e.recommendedPlan, e.retryAfter.
        TextButton(onPressed: () => launchUrlString(e.upgradeUrl!), child: Text('${offer['cta']}')),
      ],
    ),
  );
}
```

## Streaming

Three endpoints stream Server-Sent Events. Each returns a `Stream<SseEvent>`; an `SseEvent`
has `event` (the `event:` name or null), `data` (JSON-decoded when it is JSON, else the raw
string) and `id`.

| Method                         | Route                                                                        |
| ------------------------------ | ---------------------------------------------------------------------------- |
| `chat.completionsStream(body)` | `POST /v1/chat/completions` — sets `stream: true` for you, ends at `[DONE]`. |
| `chat.studioStream(body)`      | `POST /chat` — the studio's build conversation.                              |
| `projects.buildStream(id)`     | `GET /projects/{id}/build-stream` — live build progress.                     |

Keep-alive comments are skipped, multi-line `data:` is joined with newlines, and the
`[DONE]` sentinel is consumed rather than handed on. A stream is never retried: replaying one
that failed mid-flight would duplicate whatever you had already read. A plan refusal — before
the stream opens or as an error frame inside it — raises `PlanLimitError`.

```dart
await for (final event in dev.projects.buildStream(projectId)) {
  setState(() => _buildLog.add('${event.event}: ${event.data}'));
}
```

## Pagination

List endpoints that take `limit` / `offset` return one page at a time. `paginate` walks every
page and stops on a short one. Items are read from the page when it is a list, otherwise from
its first list-valued field (`templates`, `items`, `keys`, …):

```dart
await for (final template in paginate(
  (offset, limit) => dev.templates.list({'offset': offset, 'limit': limit}),
  pageSize: 50,
  maxItems: 200,
)) {
  debugPrint(template['name'] as String?);
}
```

---

## Links

- Website — https://www.misar.dev
- Parent — https://misar.io
- Documentation — https://docs.misar.io/dev
- Source — https://github.com/Misar-AI/misardev-sdks
- pub.dev — https://pub.dev/packages/misardev_flutter

MIT © [Misar.AI](https://misar.io)
