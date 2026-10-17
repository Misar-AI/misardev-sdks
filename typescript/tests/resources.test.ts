/**
 * Every operation in sdks/manifest.json is reachable through the generated
 * client, and builds the exact verb + path the server routes. Invoked for real
 * against a recording stub — nothing is declared.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { OPERATION_COUNT } from "../src/index.js";
import { client, json, sse } from "./helpers.js";

interface Method {
  name: string;
  verb: string;
  path: string;
  pathParams: string[];
  requiredQuery: string[];
  queryParams: string[];
  hasBody: boolean;
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

const camel = (s: string) =>
  s.replace(/[-_](\w)/g, (_, c: string) => c.toUpperCase());

function argsFor(m: Method) {
  const args: unknown[] = m.pathParams.map((p) => `${p}-1`);
  for (const q of m.requiredQuery) args.push(`${q}-v`);
  if (m.hasBody) args.push({ probe: true });
  if (m.queryParams.some((q) => !m.requiredQuery.includes(q))) args.push({});
  return args;
}

function expectedUrl(m: Method) {
  let p = m.path;
  for (const name of m.pathParams) p = p.replace(`:${name}`, `${name}-1`);
  const qs = m.requiredQuery.map((q) => `${q}=${q}-v`).join("&");
  return `https://api.test/dev${p}${qs ? `?${qs}` : ""}`;
}

const ops = Object.entries(manifest.resources).flatMap(([r, d]) =>
  d.methods.map((m) => [r, m] as const),
);

describe("generated resources", () => {
  it("cover every manifest operation", () => {
    expect(OPERATION_COUNT).toBe(ops.length + manifest.streams.sse.length);
  });

  it.each(ops.map(([r, m]) => [`${r}.${m.name}`, r, m] as const))(
    "%s",
    async (_label, resource, m) => {
      const { dev, calls } = client([json({ ok: true })]);
      const res = (
        dev as unknown as Record<
          string,
          Record<string, (...a: unknown[]) => Promise<unknown>>
        >
      )[camel(resource)];
      expect(typeof res[m.name]).toBe("function");
      await res[m.name](...argsFor(m));
      expect(calls[0].method).toBe(m.verb);
      expect(calls[0].url).toBe(expectedUrl(m));
      if (m.hasBody) expect(calls[0].body).toMatchObject({ probe: true });
    },
  );

  it.each(
    manifest.streams.sse.map((s) => [`${s.resource}.${s.name}`, s] as const),
  )("stream %s", async (_l, s) => {
    const { dev, calls } = client([sse(['data: {"x":1}\n\n'])]);
    const res = (
      dev as unknown as Record<
        string,
        Record<string, (...a: unknown[]) => AsyncGenerator>
      >
    )[camel(s.resource)];
    const out = [];
    for await (const ev of res[s.name](
      ...argsFor({ ...s, requiredQuery: [], queryParams: [] }),
    ))
      out.push(ev);
    expect(out).toHaveLength(1);
    expect(calls[0].method).toBe(s.verb);
    expect(calls[0].url).toBe(
      expectedUrl({ ...s, requiredQuery: [], queryParams: [] }),
    );
  });
});
