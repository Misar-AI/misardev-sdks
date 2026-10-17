# Misar.Dev SDKs

Official client libraries for the [Misar.Dev](https://www.misar.dev) API — create,
build and deploy apps, manage their files, domains, environment variables and
collaborators, start from templates, search your code, and call the
OpenAI-compatible chat completions endpoint.

Every SDK covers the full public API surface: **21 resources, 106 methods and 3
Server-Sent Events streams**, generated from one manifest
([`manifest.json`](manifest.json)) that is itself derived from the API's route
tree — so no language can fall behind another, or behind the server. They speak
only HTTPS and SSE, and authenticate with a Misar.Dev API key (`mdk_…`) — create
one at [misar.dev/settings/api-keys](https://www.misar.dev/settings/api-keys).

## Install

| Language                | Registry      | Package                                | Install                                                                     |
| ----------------------- | ------------- | -------------------------------------- | --------------------------------------------------------------------------- |
| TypeScript / JavaScript | npm           | `@misardev/sdk`                        | `npm install @misardev/sdk`                                                 |
| CLI                     | npm           | `@misardev/cli`                        | `npm install -g @misardev/cli`                                              |
| Python                  | PyPI          | `misardev`                             | `pip install misardev`                                                      |
| Go                      | module proxy  | `github.com/Misar-AI/misardev-sdks/go` | `go get github.com/Misar-AI/misardev-sdks/go`                               |
| Rust                    | crates.io     | `misardev`                             | `cargo add misardev`                                                        |
| Java                    | Maven Central | `io.misar:misardev`                    | `<artifactId>misardev</artifactId>`                                         |
| Kotlin                  | Maven Central | `io.misar:misardev-kotlin`             | `implementation("io.misar:misardev-kotlin:1.0.0")`                          |
| Swift                   | Swift PM      | `MisarDev`                             | `.package(url: "https://github.com/Misar-AI/misardev-sdks", from: "1.0.0")` |
| Ruby                    | RubyGems      | `misardev`                             | `gem install misardev`                                                      |
| PHP                     | Packagist     | `misarai/misardev-php`                 | `composer require misarai/misardev-php`                                     |
| C# / .NET               | NuGet         | `MisarDev`                             | `dotnet add package MisarDev`                                               |
| Dart                    | pub.dev       | `misardev`                             | `dart pub add misardev`                                                     |
| Flutter                 | pub.dev       | `misardev_flutter`                     | `flutter pub add misardev_flutter`                                          |

Each language directory has its own README with the full method reference and
examples for that SDK.

> The TypeScript SDK was previously published as `@misar/dev` (0.x). That package
> is deprecated — install `@misardev/sdk`.

## Quick start

```ts
import { MisarDev } from "@misardev/sdk";

const dev = new MisarDev(process.env.MISARDEV_API_KEY);

const { project } = await dev.projects.create<{ project: { id: string } }>({
  name: "Coffee shop site",
});

for await (const chunk of dev.chat.completionsStream({
  model: "misar-online",
  messages: [{ role: "user", content: "Suggest a tagline for a coffee shop" }],
})) {
  process.stdout.write((chunk.data as any).choices?.[0]?.delta?.content ?? "");
}
```

## Plan limits

Limits are enforced server-side against the plan that owns the API key, never in
the client. A blocked call answers with `code: "plan_limit_exceeded"` and an
`upgrade` offer — **402** when the feature is not on the plan, **429** with
`Retry-After` when an allowance is spent. Every SDK detects it by that code (not
by status), raises a `PlanLimitError` carrying the full offer, and never retries
it. Ordinary throttles (429 without that code) and transient server errors are
retried with backoff that honours `Retry-After`.

## Releases

Versions are per-SDK. A bump to a language's manifest on `main` is tagged
`<language>/vX.Y.Z` automatically, and that tag publishes to the registry. Go,
Swift and PHP carry no manifest version: their release version is
[`VERSION`](VERSION), and for them the git tag _is_ the release — which is why
`Package.swift` sits at the repository root and the Go module path carries the
`/go` suffix. See [PUBLISHING.md](PUBLISHING.md).

## Links

- Website — https://www.misar.dev
- Documentation — https://docs.misar.io/dev
- API — https://api.misar.io/dev
- MCP server — `npx -y @misardev/mcp`, or https://api.misar.io/dev/mcp

## Licence

MIT. See [LICENSE](LICENSE).
