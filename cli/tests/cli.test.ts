import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { PlanLimitError } from "@misardev/sdk";
import {
  API_KEYS_URL,
  EXIT_PLAN_LIMIT,
  renderPlanLimitCard,
} from "../src/index.js";
import { API_KEY, BASE, PLAN_LIMIT_BODY, cli, json, sse } from "./helpers.js";

const tmp = mkdtempSync(join(tmpdir(), "misardev-cli-"));
afterAll(() => rmSync(tmp, { recursive: true, force: true }));

describe("authentication and client setup", () => {
  it("sends the key as a bearer token, with the CLI's X-Misar-SDK header", async () => {
    const { code, calls } = await cli(
      ["projects", "list"],
      [json({ projects: [] })],
    );
    expect(code).toBe(0);
    expect(calls[0].headers.Authorization).toBe(`Bearer ${API_KEY}`);
    expect(calls[0].headers["X-Misar-SDK"]).toBe("misardev-cli/1.0.0");
    expect(calls[0].url).toBe(`${BASE}/projects`);
  });

  it("prefers --api-key and --base-url over the environment", async () => {
    const { calls } = await cli(
      [
        "--api-key",
        "mdk_flag",
        "--base-url",
        "https://other.test/dev",
        "usage",
        "plan",
      ],
      [json({ plan: "pro" })],
    );
    expect(calls[0].headers.Authorization).toBe("Bearer mdk_flag");
    expect(calls[0].url).toBe("https://other.test/dev/usage/plan");
  });

  it("accepts the global options after the subcommand too", async () => {
    const { calls } = await cli(
      ["projects", "list", "--api-key", "mdk_after"],
      [json({})],
    );
    expect(calls[0].headers.Authorization).toBe("Bearer mdk_after");
  });

  it("defaults the base URL to https://api.misar.io/dev", async () => {
    const { calls } = await cli(["projects", "list"], [json({})], {
      env: { MISARDEV_API_KEY: API_KEY },
    });
    expect(calls[0].url).toBe("https://api.misar.io/dev/projects");
  });

  it("fails with a pointer to the API-key page when no key is set, without calling the API", async () => {
    const { code, stderr, calls } = await cli(["projects", "list"], [], {
      env: {},
    });
    expect(code).toBe(1);
    expect(stderr).toContain("MISARDEV_API_KEY");
    expect(stderr).toContain(API_KEYS_URL);
    expect(calls).toHaveLength(0);
  });
});

describe("argument mapping", () => {
  it("maps path params and required query positionally, URL-encoded", async () => {
    const { code, calls } = await cli(
      ["projects", "check-subdomain", "a b/c", "my-app"],
      [json({ available: true })],
    );
    expect(code).toBe(0);
    expect(calls[0].method).toBe("GET");
    expect(calls[0].url).toBe(
      `${BASE}/projects/a%20b%2Fc/subdomain/check?value=my-app`,
    );
  });

  it("sends --body JSON", async () => {
    const { calls } = await cli(
      ["projects", "create", "--body", '{"name":"my-app","private":true}'],
      [json({})],
    );
    expect(calls[0].method).toBe("POST");
    expect(calls[0].body).toEqual({ name: "my-app", private: true });
  });

  it("reads --body @file", async () => {
    const file = join(tmp, "body.json");
    writeFileSync(
      file,
      JSON.stringify({
        files: [{ path: "index.html", content: "<h1>hi</h1>" }],
      }),
    );
    const { calls } = await cli(
      ["projects", "write-files", "p1", "--body", `@${file}`],
      [json({})],
    );
    expect(calls[0].url).toBe(`${BASE}/projects/p1/files`);
    expect(calls[0].body).toEqual({
      files: [{ path: "index.html", content: "<h1>hi</h1>" }],
    });
  });

  it("reads --body @- from stdin", async () => {
    const { calls } = await cli(
      ["templates", "create", "--body", "@-"],
      [json({})],
      {
        readStdin: async () => '{"name":"t"}',
      },
    );
    expect(calls[0].body).toEqual({ name: "t" });
  });

  it("sends an empty object when a body command gets no --body", async () => {
    const { calls } = await cli(["projects", "deploy", "p1"], [json({})]);
    expect(calls[0].body).toEqual({});
  });

  it("rejects invalid JSON and non-object bodies before calling the API", async () => {
    const bad = await cli(
      ["projects", "create", "--body", "{nope"],
      [json({})],
    );
    expect(bad.code).toBe(1);
    expect(bad.stderr).toContain("not valid JSON");
    expect(bad.calls).toHaveLength(0);

    const arr = await cli(
      ["projects", "create", "--body", "[1,2]"],
      [json({})],
    );
    expect(arr.code).toBe(1);
    expect(arr.stderr).toContain("must be a JSON object");

    const missing = await cli(
      ["projects", "create", "--body", `@${join(tmp, "nope.json")}`],
      [json({})],
    );
    expect(missing.code).toBe(1);
    expect(missing.stderr).toContain("Could not read");
  });

  it("sends repeatable --query key=value pairs", async () => {
    const { calls } = await cli(
      [
        "templates",
        "list",
        "--query",
        "category=saas",
        "--query",
        "limit=10",
        "--query",
        "search=a b",
      ],
      [json([])],
    );
    expect(calls[0].url).toBe(
      `${BASE}/templates?category=saas&limit=10&search=a+b`,
    );
  });

  it("rejects an unknown query key and a pair without '='", async () => {
    const unknown = await cli(
      ["templates", "list", "--query", "colour=red"],
      [json([])],
    );
    expect(unknown.code).toBe(1);
    expect(unknown.stderr).toContain('Unknown query parameter "colour"');
    expect(unknown.stderr).toContain("category");
    expect(unknown.calls).toHaveLength(0);

    const malformed = await cli(
      ["templates", "list", "--query", "limit"],
      [json([])],
    );
    expect(malformed.code).toBe(1);
    expect(malformed.stderr).toContain("key=value");
  });

  it("rejects a missing positional argument", async () => {
    const { code, stderr, calls } = await cli(["projects", "get"], [json({})]);
    expect(code).toBe(1);
    expect(stderr).toContain("missing required argument");
    expect(calls).toHaveLength(0);
  });
});

describe("output", () => {
  it("prints pretty JSON by default and compact JSON with --json", async () => {
    const pretty = await cli(
      ["projects", "get", "p1"],
      [json({ id: "p1", name: "App" })],
    );
    expect(pretty.stdout).toBe('{\n  "id": "p1",\n  "name": "App"\n}\n');
    const compact = await cli(
      ["projects", "get", "p1", "--json"],
      [json({ id: "p1", name: "App" })],
    );
    expect(compact.stdout).toBe('{"id":"p1","name":"App"}\n');
  });

  it("prints arrays, and nothing for an empty 204", async () => {
    const arr = await cli(["builds", "list"], [json([{ id: "b1" }])]);
    expect(JSON.parse(arr.stdout)).toEqual([{ id: "b1" }]);
    const empty = await cli(
      ["projects", "delete", "p1"],
      [new Response(null, { status: 204 })],
    );
    expect(empty.code).toBe(0);
    expect(empty.stdout).toBe("");
  });

  it("keeps the 0.x shortcuts: `misardev usage` and `misardev projects list`", async () => {
    const usage = await cli(["usage"], [json({ requests: 50 })]);
    expect(usage.calls[0].url).toBe(`${BASE}/usage`);
    expect(JSON.parse(usage.stdout)).toEqual({ requests: 50 });
    const usageQ = await cli(["usage", "--query", "days=7"], [json({})]);
    expect(usageQ.calls[0].url).toBe(`${BASE}/usage?days=7`);
    const list = await cli(["projects", "list"], [json({ projects: [] })]);
    expect(list.calls[0].url).toBe(`${BASE}/projects`);
  });

  it("prints help and the version with exit 0", async () => {
    const help = await cli(["--help"]);
    expect(help.code).toBe(0);
    expect(help.stdout).toContain("projects");
    expect(help.stdout).toContain("api-keys");
    const version = await cli(["--version"]);
    expect(version.code).toBe(0);
    expect(version.stdout.trim()).toBe("1.0.0");
  });
});

describe("streams", () => {
  it("chat completions-stream prints delta content inline, stops at [DONE], forces stream:true", async () => {
    const frames = [
      'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n',
      'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
      ": keep-alive\n\n",
      'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
      "data: [DONE]\n\n",
      'data: {"choices":[{"delta":{"content":"NEVER"}}]}\n\n',
    ];
    const { code, stdout, calls } = await cli(
      [
        "chat",
        "completions-stream",
        "--body",
        '{"messages":[{"role":"user","content":"Hi"}]}',
      ],
      [sse(frames)],
    );
    expect(code).toBe(0);
    expect(stdout).toBe("Hello\n");
    expect(calls[0].url).toBe(`${BASE}/v1/chat/completions`);
    expect(calls[0].body).toEqual({
      messages: [{ role: "user", content: "Hi" }],
      stream: true,
    });
  });

  it("--json prints every event as one JSON line", async () => {
    const { stdout } = await cli(
      ["chat", "completions-stream", "--json"],
      [
        sse([
          'data: {"choices":[{"delta":{"content":"a"}}]}\n\n',
          "data: [DONE]\n\n",
        ]),
      ],
    );
    expect(
      stdout
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l)),
    ).toEqual([
      {
        event: null,
        data: { choices: [{ delta: { content: "a" } }] },
        id: null,
      },
    ]);
  });

  it("build-stream prints named events, multi-line data and a trailing frame", async () => {
    const frames = [
      'event: step\nid: 1\ndata: {"step":"install"}\n\n',
      "data: line one\ndata: line two\n\n",
      'event: done\ndata: {"ok":true}',
    ];
    const { code, stdout, calls } = await cli(
      ["projects", "build-stream", "p1"],
      [sse(frames)],
    );
    expect(code).toBe(0);
    expect(calls[0].url).toBe(`${BASE}/projects/p1/build-stream`);
    expect(stdout).toBe(
      'step: {"step":"install"}\nline one\nline two\ndone: {"ok":true}\n',
    );
  });

  it("a plan-limit frame mid-stream renders the upgrade card and exits 2", async () => {
    const { code, stderr } = await cli(
      ["chat", "studio-stream", "--body", "{}"],
      [
        sse([
          `data: ${JSON.stringify({ type: "error", ...PLAN_LIMIT_BODY })}\n\n`,
        ]),
      ],
    );
    expect(code).toBe(EXIT_PLAN_LIMIT);
    expect(stderr).toContain("API access isn't included in your Starter plan.");
  });
});

describe("errors", () => {
  it("renders the plan-limit upgrade card on a 402, exits 2, makes exactly one request", async () => {
    const { code, stdout, stderr, calls } = await cli(
      ["projects", "list"],
      [json(PLAN_LIMIT_BODY, 402)],
    );
    expect(code).toBe(2);
    expect(calls).toHaveLength(1);
    expect(stdout).toBe("");
    expect(stderr).toContain("Upgrade required — Misar.Dev");
    expect(stderr).toContain("API access isn't included in your Starter plan.");
    expect(stderr).toContain("Current plan: Starter");
    expect(stderr).toContain("Upgrade to Pro to continue.");
    expect(stderr).toContain("Upgrade: https://www.misar.dev/settings/billing");
  });

  it("never retries a 429 quota refusal", async () => {
    const body = {
      ...PLAN_LIMIT_BODY,
      upgrade: { ...PLAN_LIMIT_BODY.upgrade, reason: "quota_exhausted" },
    };
    const { code, calls } = await cli(
      ["projects", "create"],
      [json(body, 429, { "retry-after": "3600" })],
    );
    expect(code).toBe(2);
    expect(calls).toHaveLength(1);
  });

  it("renders each plan's name, price and unlocks, plus usage", () => {
    const offer = {
      ...PLAN_LIMIT_BODY.upgrade,
      reason: "quota_exhausted",
      usage: {
        used: 100,
        limit: 100,
        remaining: 0,
        period: "month",
        resets_at: "2026-11-01",
      },
      plans: [
        {
          slug: "pro",
          name: "Pro",
          price: "$29/mo",
          price_note: null,
          recommended: true,
          current: false,
          unlocks: "API access",
          benefits: [],
          url: "",
        },
        {
          slug: "max",
          name: "Max",
          price: "$99/mo",
          price_note: "billed yearly",
          recommended: false,
          current: false,
          unlocks: null,
          benefits: [],
          url: "",
        },
      ],
    };
    const err = new PlanLimitError(
      429,
      "Quota used",
      { ...PLAN_LIMIT_BODY, upgrade: offer },
      null,
      offer as never,
      3600,
    );
    const card = renderPlanLimitCard(err);
    expect(card).toContain("Usage: 100 of 100 this month · resets 2026-11-01");
    expect(card).toContain("• Pro — $29/mo  (recommended)");
    expect(card).toContain("unlocks: API access");
    expect(card).toContain("• Max — $99/mo billed yearly");
  });

  it("falls back to the message and pricing URL when the offer is partial or missing", () => {
    const bare = renderPlanLimitCard(
      new PlanLimitError(402, "Blocked by plan", {}, null, null, 120),
    );
    expect(bare).toContain("Upgrade required");
    expect(bare).toContain("Blocked by plan");
    expect(bare).toContain("Resets in about 2 minute(s).");
    const partial = renderPlanLimitCard(
      new PlanLimitError(
        402,
        "x",
        {},
        null,
        { urls: { pricing: "https://www.misar.dev/pricing" } } as never,
        null,
      ),
    );
    expect(partial).toContain("Upgrade: https://www.misar.dev/pricing");
  });

  it("maps 401 / 404 / OpenAI-shaped 400 to a message + status, exit 1", async () => {
    const unauth = await cli(
      ["projects", "list"],
      [json({ error: "Invalid API key" }, 401)],
    );
    expect(unauth.code).toBe(1);
    expect(unauth.stderr).toContain("Error (HTTP 401): Invalid API key");

    const missing = await cli(
      ["projects", "get", "p404"],
      [
        json({ error: "Project not found" }, 404, {
          "x-request-id": "req_123",
        }),
      ],
    );
    expect(missing.code).toBe(1);
    expect(missing.stderr).toContain("Error (HTTP 404): Project not found");
    expect(missing.stderr).toContain("Request id: req_123");

    const invalid = await cli(
      ["chat", "completions", "--body", "{}"],
      [
        json(
          {
            error: {
              message: "messages is required",
              type: "invalid_request_error",
              code: "missing_messages",
            },
          },
          400,
        ),
      ],
    );
    expect(invalid.code).toBe(1);
    expect(invalid.stderr).toContain(
      "Error (HTTP 400): messages is required [missing_messages]",
    );
  });

  it("never prints the API key, even when the server echoes it back", async () => {
    const { stderr, stdout } = await cli(
      ["projects", "list"],
      [json({ error: `Key ${API_KEY} is revoked` }, 401)],
    );
    expect(stderr).not.toContain(API_KEY);
    expect(stdout).not.toContain(API_KEY);
    expect(stderr).toContain("Key *** is revoked");

    const flag = await cli(
      ["--api-key", "mdk_flag_secret", "projects", "list"],
      [json({ error: "bad mdk_flag_secret" }, 401)],
    );
    expect(flag.stderr).not.toContain("mdk_flag_secret");
  });

  it("reports a network failure as an error, exit 1", async () => {
    const { code, stderr } = await cli(
      ["projects", "create"],
      [new TypeError("fetch failed")],
    );
    expect(code).toBe(1);
    expect(stderr).toContain("fetch failed");
  });

  it("returns commander's exit code for an unknown command", async () => {
    const { code, stderr } = await cli(["projectz"]);
    expect(code).toBe(1);
    expect(stderr).toContain("unknown command");
  });
});
