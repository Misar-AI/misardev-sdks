/**
 * The generated command table covers sdks/manifest.json exactly, every entry
 * becomes a `misardev <group> <command>` command, and invoking each one for real
 * (through @misardev/sdk, against a recording fetch stub) builds the verb + URL
 * the server routes.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  buildProgram,
  COMMANDS,
  OPERATION_COUNT,
  type CommandSpec,
} from "../src/index.js";
import { BASE, cli, json, sse } from "./helpers.js";

interface Method {
  name: string;
  verb: string;
  path: string;
  pathParams: string[];
  requiredQuery?: string[];
  queryParams?: string[];
  hasBody: boolean;
  terminator?: string | null;
}

const manifest = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("../../manifest.json", import.meta.url)),
    "utf8",
  ),
) as {
  resources: Record<string, { methods: Method[] }>;
  streams: { sse: Array<Method & { resource: string }> };
};

const methods = Object.entries(manifest.resources).flatMap(([r, d]) =>
  d.methods.map((m) => [r, m] as const),
);
const streams = manifest.streams.sse.map((s) => [s.resource, s] as const);

function argvFor(spec: CommandSpec): string[] {
  const argv = [spec.group, spec.command];
  for (const p of spec.pathParams) argv.push(`${p}-1`);
  for (const q of spec.requiredQuery) argv.push(`${q}-v`);
  if (spec.hasBody) argv.push("--body", '{"probe":true}');
  return argv;
}

function expectedUrl(spec: CommandSpec): string {
  let p = spec.path;
  for (const name of spec.pathParams) p = p.replace(`:${name}`, `${name}-1`);
  const qs = spec.requiredQuery.map((q) => `${q}=${q}-v`).join("&");
  return `${BASE}${p}${qs ? `?${qs}` : ""}`;
}

describe("command table", () => {
  it("has one entry per manifest method and stream", () => {
    expect(COMMANDS).toHaveLength(methods.length + streams.length);
    expect(OPERATION_COUNT).toBe(methods.length + streams.length);
  });

  it.each(
    [...methods, ...streams].map(([r, m]) => [`${r}.${m.name}`, r, m] as const),
  )("%s matches the manifest", (_label, resource, m) => {
    const spec = COMMANDS.find(
      (c) => c.resource === resource && c.method === m.name,
    );
    expect(spec).toBeDefined();
    expect(spec!.verb).toBe(m.verb);
    expect(spec!.path).toBe(m.path);
    expect(spec!.pathParams).toEqual(m.pathParams);
    expect(spec!.hasBody).toBe(m.hasBody);
  });

  it("turns every entry into a commander command", () => {
    const program = buildProgram();
    let found = 0;
    for (const spec of COMMANDS) {
      const group = program.commands.find((c) => c.name() === spec.group);
      expect(group, spec.group).toBeDefined();
      const cmd = group!.commands.find((c) => c.name() === spec.command);
      expect(cmd, `${spec.group} ${spec.command}`).toBeDefined();
      expect(cmd!.registeredArguments).toHaveLength(
        spec.pathParams.length + spec.requiredQuery.length,
      );
      expect(cmd!.options.some((o) => o.long === "--body")).toBe(spec.hasBody);
      expect(cmd!.options.some((o) => o.long === "--query")).toBe(
        spec.optionalQuery.length > 0,
      );
      found += 1;
    }
    expect(found).toBe(OPERATION_COUNT);
  });
});

describe("every command calls the right route", () => {
  it.each(
    COMMANDS.filter((c) => !c.stream).map(
      (c) => [`${c.group} ${c.command}`, c] as const,
    ),
  )("%s", async (_label, spec) => {
    const { code, calls, stderr } = await cli(argvFor(spec), [
      json({ ok: true }),
    ]);
    expect(stderr).toBe("");
    expect(code).toBe(0);
    expect(calls).toHaveLength(1);
    expect(calls[0].method).toBe(spec.verb);
    expect(calls[0].url).toBe(expectedUrl(spec));
    if (spec.hasBody) expect(calls[0].body).toMatchObject({ probe: true });
    else expect(calls[0].body).toBeUndefined();
  });

  it.each(
    COMMANDS.filter((c) => c.stream).map(
      (c) => [`${c.group} ${c.command}`, c] as const,
    ),
  )("stream %s", async (_label, spec) => {
    const { code, calls } = await cli(argvFor(spec), [
      sse(['data: {"x":1}\n\n']),
    ]);
    expect(code).toBe(0);
    expect(calls).toHaveLength(1);
    expect(calls[0].method).toBe(spec.verb);
    expect(calls[0].url).toBe(expectedUrl(spec));
    expect(calls[0].headers.Accept).toBe("text/event-stream");
  });
});
