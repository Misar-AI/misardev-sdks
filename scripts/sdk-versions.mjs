#!/usr/bin/env node
/**
 * Read the declared version of every publishable SDK.
 *
 * Each ecosystem keeps its version somewhere different, so this is the single
 * place that knows where to look. CI uses it to decide what to publish: the
 * publish workflow reads versions at HEAD and at the previous commit, and
 * publishes exactly the SDKs whose version changed.
 *
 * Usage:
 *   node scripts/sdk-versions.mjs              # JSON map to stdout
 *   node scripts/sdk-versions.mjs --github     # also emit GITHUB_OUTPUT vars
 *   node scripts/sdk-versions.mjs --ref HEAD~1 # read from a git ref instead of disk
 *
 * Go, Swift and PHP have no version field: their registries resolve from a git
 * tag, so their "version" is whatever the release tag says. They are reported
 * as null and handled by the tag-mirroring job rather than a publish job.
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

/** sdk dir → [manifest path relative to the sdk dir, extractor] */
const SOURCES = {
  typescript: ["package.json", (s) => JSON.parse(s).version],
  cli: ["package.json", (s) => JSON.parse(s).version],
  python: ["pyproject.toml", (s) => match(s, /^version\s*=\s*"([^"]+)"/m)],
  rust: ["Cargo.toml", (s) => match(s, /^version\s*=\s*"([^"]+)"/m)],
  ruby: ["misardev.gemspec", (s) => match(s, /spec\.version\s*=\s*"([^"]+)"/)],
  csharp: ["MisarDev.csproj", (s) => match(s, /<Version>([^<]+)<\/Version>/)],
  java: ["pom.xml", (s) => match(s, /<artifactId>misardev<\/artifactId>\s*<version>([^<]+)<\/version>/)],
  kotlin: ["build.gradle.kts", (s) => match(s, /^version\s*=\s*"([^"]+)"/m)],
  dart: ["pubspec.yaml", (s) => match(s, /^version:\s*(\S+)/m)],
  flutter: ["pubspec.yaml", (s) => match(s, /^version:\s*(\S+)/m)],
};

/**
 * Go, Swift and PHP have no manifest version — their registries resolve from a
 * git tag. `sdks/VERSION` is the declared release version for all three, so a
 * bump there is what triggers their tag-mirroring job.
 */
const TAG_VERSIONED = ["go", "swift", "php"];

function match(text, re) {
  const m = text.match(re);
  if (!m) throw new Error(`version not found (pattern ${re})`);
  return m[1];
}

/** Read a file from disk, or from a git ref when one is given. */
function read(path, ref) {
  if (!ref) return readFileSync(path, "utf8");
  return execFileSync("git", ["show", `${ref}:${path}`], {
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
    // A file absent at an older ref is an expected outcome (new SDK), not a
    // failure worth printing — the caller turns the throw into `null`.
    stdio: ["ignore", "pipe", "ignore"],
  });
}

/** Strip comments and whitespace from sdks/VERSION. */
function tagVersion(ref) {
  const raw = read(join("sdks", "VERSION"), ref);
  const line = raw
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l && !l.startsWith("#"));
  if (!line) throw new Error("sdks/VERSION has no version line");
  return line;
}

export function sdkVersions(ref = null) {
  const out = {};

  const safely = (sdk, fn) => {
    try {
      out[sdk] = fn();
    } catch (err) {
      // A missing file at an older ref just means the SDK did not exist yet —
      // that is a new SDK, not an error.
      out[sdk] = null;
      if (!ref && !/ENOENT|does not exist|exists on disk/.test(String(err))) {
        throw new Error(`${sdk}: ${err.message}`);
      }
    }
  };

  for (const [sdk, [manifest, extract]] of Object.entries(SOURCES)) {
    safely(sdk, () => extract(read(join("sdks", sdk, manifest), ref)));
  }
  for (const sdk of TAG_VERSIONED) {
    safely(sdk, () => tagVersion(ref));
  }

  return out;
}

// ── CLI ──────────────────────────────────────────────────────────────────────
// Guarded so `import { sdkVersions }` stays side-effect free — sdk-release-plan
// imports this module and must not inherit its stdout.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const args = process.argv.slice(2);
  const refIdx = args.indexOf("--ref");
  const ref = refIdx === -1 ? null : args[refIdx + 1];
  const versions = sdkVersions(ref);

  process.stdout.write(JSON.stringify(versions, null, 2) + "\n");

  if (args.includes("--github") && process.env.GITHUB_OUTPUT) {
    const { appendFileSync } = await import("node:fs");
    appendFileSync(process.env.GITHUB_OUTPUT, `versions=${JSON.stringify(versions)}\n`);
  }
}
