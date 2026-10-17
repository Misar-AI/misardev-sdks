# SDK Publishing Guide

Everything publishes from the GitHub mirror,
**[github.com/Misar-AI/misardev-sdks](https://github.com/Misar-AI/misardev-sdks)**,
which is populated from this repository by `.forgejo/workflows/sync-sdks-to-github.yml`
on every push to `main` that touches `sdks/`. The mirror keeps each language at its
**root** — `typescript/`, `go/`, … — not under `sdks/`, together with the root
`Package.swift`, `VERSION`, `manifest.json`, `README.md`, this file, and
`scripts/check-sdk-release.mjs`.

Nothing in this repository publishes. The workflows that do —
`sdks/.github/workflows/auto-tag.yml` and `publish.yml` — run **on the mirror**.

## Before anything reaches the mirror

The sync job re-runs the same gates CI runs on every PR, and refuses to mirror a
tree that fails any of them:

| Gate             | Command                                           | Fails when                                                                                                                    |
| ---------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Manifest         | `node scripts/sync-sdk-manifest.mjs --check`      | `sdks/manifest.json` no longer matches the route tree                                                                         |
| Generated code   | `node scripts/generate-sdk-resources.mjs --check` | a language's generated layer is stale                                                                                         |
| Coverage         | `node scripts/check-sdk-coverage.mjs`             | any language misses an operation, its core lacks plan-limit/Retry-After/SSE handling, or it contains a second credential path |
| Release metadata | `node scripts/check-sdk-release.mjs --all`        | a LICENSE/README is missing, a manifest does not parse, or it links the private Forgejo host                                  |

`pnpm sdk:check` runs all of them locally; `pnpm sdk:sync` regenerates the manifest
and every language's resource layer after a route change.

## Releasing

A release is a **version bump**, nothing else. Bump the version in the SDK's own
manifest (or `sdks/VERSION` for Go, Swift and PHP), merge to `main`, and:

1. `sync-sdks-to-github.yml` mirrors the tree;
2. `auto-tag.yml` on the mirror sees the version change and pushes
   `<language>/vX.Y.Z` (plus a bare `vX.Y.Z` for Swift);
3. `publish.yml` on the mirror runs `check-sdk-release.mjs <sdk> <version>` —
   before any credential is touched — and publishes that one SDK.

`node scripts/sdk-release-plan.mjs --base origin/main` shows locally which SDKs a
merge would release, and refuses a version that went **down**: every registry
treats a published version as permanent — npm's unpublish window is 72 hours,
crates.io and the Go module proxy are immutable, Maven Central has no delete at
all. CI runs the same check on every PR (`sdk-release-plan` job).

## Tags and registries

| SDK        | Tag                                 | Registry           | Identifier                                  |
| ---------- | ----------------------------------- | ------------------ | ------------------------------------------- |
| TypeScript | `typescript/v1.0.0`                 | npm                | `@misardev/sdk`                             |
| CLI        | `cli/v1.0.0`                        | npm                | `@misardev/cli`                             |
| Python     | `python/v1.0.0`                     | PyPI               | `misardev`                                  |
| Rust       | `rust/v1.0.0`                       | crates.io          | `misardev`                                  |
| Ruby       | `ruby/v1.0.0`                       | RubyGems           | `misardev`                                  |
| C#         | `csharp/v1.0.0`                     | NuGet              | `MisarDev`                                  |
| Java       | `java/v1.0.0`                       | Maven Central      | `io.misar:misardev`                         |
| Kotlin     | `kotlin/v1.0.0`                     | Maven Central      | `io.misar:misardev-kotlin`                  |
| Dart       | `dart/v1.0.0`                       | pub.dev            | `misardev`                                  |
| Flutter    | `flutter/v1.0.0`                    | pub.dev            | `misardev_flutter`                          |
| Go         | `go/v1.0.0`                         | Go module proxy    | `github.com/Misar-AI/misardev-sdks/go`      |
| Swift      | `swift/v1.0.0` + `v1.0.0`           | SwiftPM (git tags) | `https://github.com/Misar-AI/misardev-sdks` |
| PHP        | `v1.0.0` on `Misar-AI/misardev-php` | Packagist          | `misarai/misardev-php`                      |

```bash
# from the misardev-sdks mirror, to release by hand
git tag typescript/v1.0.0 && git push origin typescript/v1.0.0
```

The CLI depends on the SDK by path here (`file:../typescript`) so the two are
tested together. `publish.yml` pins it to `^<sdk version>` before packing and
refuses to publish until that SDK version is on npm — release `typescript/vX`
first.

## Go, Swift and PHP do not publish to a registry

**Go** has no registry. The module proxy resolves straight from the mirror, so the
`go/v1.0.0` tag is the release. The import path is the module path in
`go/go.mod` — `github.com/Misar-AI/misardev-sdks/go`. It deliberately has **no**
`/v1` suffix: Go only allows a major-version suffix from `/v2` up, and a module
path ending in `/v1` cannot be fetched at all.

**Swift**: SwiftPM requires `Package.swift` at the repository root, so the mirror
carries `sdks/Package.swift` there, reaching into `swift/Sources`. SwiftPM only
recognises a **bare** semver tag, so `auto-tag.yml` pushes `v1.0.0` alongside
`swift/v1.0.0`.

```swift
.package(url: "https://github.com/Misar-AI/misardev-sdks", from: "1.0.0")
```

**PHP**: Packagist reads `composer.json` from a repository **root** and cannot
index a subdirectory, so the sync job also splits `sdks/php` into its own
repository, `Misar-AI/misardev-php`, and tags it `v<sdks/VERSION>`. Until that
repository exists the step is skipped with a warning.

## Secrets on the mirror

Set on `Misar-AI/misardev-sdks` → Settings → Secrets → Actions. These are the
names `publish.yml` actually references; other products use different ones, so do
not copy a list between products.

| Secret                                             | Used by                                                                                                           |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `RELEASE_TOKEN`                                    | `auto-tag.yml` — a PAT, so its tags can trigger `publish.yml` (a tag pushed with `GITHUB_TOKEN` triggers nothing) |
| `NPM_TOKEN`                                        | npm (SDK and CLI)                                                                                                 |
| _(none — Trusted Publishing)_                      | PyPI, via the `release` environment                                                                               |
| `CARGO_REGISTRY_TOKEN`                             | crates.io                                                                                                         |
| `RUBYGEMS_API_KEY`                                 | RubyGems                                                                                                          |
| `NUGET_API_KEY`                                    | NuGet                                                                                                             |
| `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD` | Maven Central                                                                                                     |
| `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`                | Maven Central signing                                                                                             |
| _(none — automated publishing)_                    | pub.dev, via the `release` environment                                                                            |
| `PACKAGIST_USERNAME`, `PACKAGIST_API_TOKEN`        | Packagist re-crawl (optional)                                                                                     |

And on this Forgejo repository: `GH_SYNC_TOKEN`, a GitHub token that can push to
`Misar-AI/misardev-sdks` and `Misar-AI/misardev-php`.

## One-time registry setup

Publishing accounts follow AGENTS.md: `noreply@misar.io` (Google SSO) by
default.

- **GitHub** — create `Misar-AI/misardev-sdks` and `Misar-AI/misardev-php`.
- **npm** — scope `@misardev`; token with publish access. Deprecate the old
  package once `@misardev/sdk` is live:
  `npm deprecate @misar/dev "Renamed to @misardev/sdk"`.
- **PyPI** — add a Trusted Publisher for `Misar-AI/misardev-sdks`, workflow
  `publish.yml`, environment `release`.
- **crates.io** — sign in with GitHub, generate a token.
- **RubyGems** — the first `gem push` needs email confirmation.
- **pub.dev** — publish `misardev` (Dart) before `misardev_flutter`, enable
  automated publishing from the mirror, then move both under the verified
  publisher.
- **NuGet** — key scoped to `MisarDev`.
- **Maven Central** — the `io.misar` namespace is already verified for the other
  Misar SDKs; reuse its credentials and GPG key.
- **Packagist** — submit **`https://github.com/Misar-AI/misardev-php`**, not the
  monorepo or the mirror, and add the update webhook.
- **SwiftPM** — nothing to register. Submitting the mirror to the Swift Package
  Index is optional and only affects discoverability.

## MCP server

`@misardev/mcp` is published from misar-io (`packages/dev-mcp-server`) and is
**not** part of this pipeline. The hosted endpoint is `api.misar.io/dev/mcp`, served
by this repository's thin route (`apps/web/src/app/api/mcp/route.ts`), which
delegates to that package.
