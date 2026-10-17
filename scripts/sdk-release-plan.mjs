#!/usr/bin/env node
/**
 * Decide which SDKs to publish, by diffing declared versions between two git
 * refs. This is the trigger for the whole release pipeline: bump a version in
 * an SDK's own manifest, merge to main, and only that SDK publishes.
 *
 * Usage:
 *   node scripts/sdk-release-plan.mjs --base <ref> [--head <ref>]
 *   node scripts/sdk-release-plan.mjs --base HEAD~1 --github
 *   node scripts/sdk-release-plan.mjs --all 1.2.0     # force every SDK (dispatch)
 *
 * Emits JSON:
 *   { "publish": { "python": "1.1.0", ... }, "sdks": ["python", ...] }
 *
 * A version that goes *down* is reported as an error rather than published —
 * registries treat a version as immutable, and a downgrade is almost always an
 * accidental revert rather than an intended release.
 */

import { appendFileSync } from "node:fs";
import { sdkVersions } from "./sdk-versions.mjs";

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? null : args[i + 1];
};

/** Compare dotted numeric versions. Returns <0, 0, >0. */
function cmp(a, b) {
  const pa = String(a).split(/[.+-]/).map(Number);
  const pb = String(b).split(/[.+-]/).map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (Number.isNaN(x) || Number.isNaN(y)) return String(a).localeCompare(String(b));
    if (x !== y) return x - y;
  }
  return 0;
}

let publish = {};
const forceAll = args.indexOf("--all");

if (forceAll !== -1) {
  const pinned = args[forceAll + 1];
  const head = sdkVersions(flag("--head"));
  for (const [sdk, v] of Object.entries(head)) {
    if (v) publish[sdk] = pinned && !pinned.startsWith("--") ? pinned : v;
  }
} else {
  const base = flag("--base");
  if (!base) {
    console.error("error: --base <ref> is required (or use --all)");
    process.exit(2);
  }
  const before = sdkVersions(base);
  const after = sdkVersions(flag("--head"));
  const regressions = [];

  for (const [sdk, now] of Object.entries(after)) {
    if (!now) continue;
    const was = before[sdk];
    if (was === now) continue;
    if (was && cmp(now, was) < 0) {
      regressions.push(`${sdk}: ${was} -> ${now}`);
      continue;
    }
    publish[sdk] = now;
  }

  if (regressions.length) {
    console.error("error: version went backwards, refusing to publish:");
    for (const r of regressions) console.error(`  ${r}`);
    console.error("Registries treat published versions as immutable — bump forward instead.");
    process.exit(1);
  }
}

const sdks = Object.keys(publish).sort();
const plan = { publish, sdks };
process.stdout.write(JSON.stringify(plan, null, 2) + "\n");

if (args.includes("--github") && process.env.GITHUB_OUTPUT) {
  appendFileSync(process.env.GITHUB_OUTPUT, `plan=${JSON.stringify(plan)}\n`);
  appendFileSync(process.env.GITHUB_OUTPUT, `sdks=${JSON.stringify(sdks)}\n`);
  appendFileSync(process.env.GITHUB_OUTPUT, `any=${sdks.length > 0}\n`);
  for (const [sdk, version] of Object.entries(publish)) {
    appendFileSync(process.env.GITHUB_OUTPUT, `version_${sdk}=${version}\n`);
  }
}
