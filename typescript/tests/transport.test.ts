import { describe, expect, it, vi } from "vitest";
import {
  AuthenticationError,
  MisarDev,
  MisarDevError,
  NetworkError,
  NotFoundError,
  PlanLimitError,
  RateLimitError,
  ServerError,
  ValidationError,
  backoffMs,
  buildQuery,
  paginate,
} from "../src/index.js";
import { PLAN_LIMIT_BODY, client, json, sse } from "./helpers.js";

/** Await a promise that must reject, and hand back what it threw. */
async function fail(p: Promise<unknown>): Promise<any> {
  try {
    await p;
  } catch (e) {
    return e;
  }
  throw new Error("expected the call to reject");
}

vi.useFakeTimers({ shouldAdvanceTime: true, advanceTimeDelta: 1000 });

describe("authentication", () => {
  it("sends the key as a bearer token and identifies the SDK", async () => {
    const { dev, calls } = client([json({ projects: [] })]);
    await dev.projects.list();
    expect(calls[0].headers.Authorization).toBe("Bearer mdk_test_key");
    expect(calls[0].headers["X-Misar-SDK"]).toMatch(/^misardev-typescript\//);
    expect(calls[0].url).toBe("https://api.test/dev/projects");
  });

  it("refuses to construct without a key", () => {
    const prev = process.env.MISARDEV_API_KEY;
    delete process.env.MISARDEV_API_KEY;
    expect(
      () => new MisarDev(undefined, { fetch: (() => {}) as never }),
    ).toThrow(/API key is required/);
    if (prev !== undefined) process.env.MISARDEV_API_KEY = prev;
  });

  it("reads MISARDEV_API_KEY from the environment", async () => {
    process.env.MISARDEV_API_KEY = "mdk_from_env";
    const calls: string[] = [];
    const dev = new MisarDev(undefined, {
      fetch: (async (_u: unknown, init: RequestInit) => {
        calls.push((init.headers as Record<string, string>).Authorization);
        return json({});
      }) as typeof fetch,
    });
    await dev.usage.plan();
    expect(calls[0]).toBe("Bearer mdk_from_env");
    expect(dev.baseURL).toBe("https://api.misar.io/dev");
    delete process.env.MISARDEV_API_KEY;
  });
});

describe("errors", () => {
  it("raises PlanLimitError with the full offer, detected by code not status", async () => {
    const { dev, calls } = client([
      json(PLAN_LIMIT_BODY, 402, { "x-request-id": "req_1" }),
    ]);
    const err = await fail(dev.projects.list());
    expect(err).toBeInstanceOf(PlanLimitError);
    expect(err.status).toBe(402);
    expect(err.offer.recommended_plan).toBe("pro");
    expect(err.upgradeUrl).toBe("https://www.misar.dev/settings/billing");
    expect(err.feature).toBe("api_access");
    expect(err.currentPlan).toBe("starter");
    expect(err.recommendedPlan).toBe("pro");
    expect(err.requestId).toBe("req_1");
    expect(calls).toHaveLength(1);
  });

  it("never retries a 429 that is a plan limit", async () => {
    const { dev, calls } = client([
      json(
        {
          ...PLAN_LIMIT_BODY,
          upgrade: { ...PLAN_LIMIT_BODY.upgrade, reason: "quota_exhausted" },
        },
        429,
        { "retry-after": "3600" },
      ),
    ]);
    const err = await fail(dev.templates.list());
    expect(err).toBeInstanceOf(PlanLimitError);
    expect(err.retryAfter).toBe(3600);
    expect(calls).toHaveLength(1);
  });

  it("retries an ordinary 429 and honours Retry-After", async () => {
    const { dev, calls } = client([
      json({ error: "slow down" }, 429, { "retry-after": "0" }),
      json({ ok: 1 }),
    ]);
    await expect(dev.projects.create({ name: "x" })).resolves.toEqual({
      ok: 1,
    });
    expect(calls).toHaveLength(2);
  });

  it("gives up on a persistent throttle with RateLimitError", async () => {
    const { dev, calls } = client(
      [json({ error: "slow down" }, 429, { "retry-after": "0" })],
      2,
    );
    const err = await fail(dev.projects.list());
    expect(err).toBeInstanceOf(RateLimitError);
    expect(err.retryAfter).toBe(0);
    expect(calls).toHaveLength(2);
  });

  it("retries a 503 on GET but not on POST", async () => {
    const get = client([json({ error: "down" }, 503), json({ ok: true })]);
    await expect(get.dev.projects.list()).resolves.toEqual({ ok: true });
    expect(get.calls).toHaveLength(2);

    const post = client([json({ error: "down" }, 503), json({ ok: true })]);
    await expect(post.dev.projects.create({})).rejects.toBeInstanceOf(
      ServerError,
    );
    expect(post.calls).toHaveLength(1);
  });

  it("maps statuses to typed errors and reads the OpenAI error shape", async () => {
    const a = client([json({ error: "Unauthorized" }, 401)]);
    await expect(a.dev.projects.list()).rejects.toBeInstanceOf(
      AuthenticationError,
    );
    const b = client([json({ error: "nope" }, 404)]);
    await expect(b.dev.projects.get("p1")).rejects.toBeInstanceOf(
      NotFoundError,
    );
    const c = client([
      json(
        {
          error: {
            message: "bad model",
            type: "invalid_request_error",
            code: "bad_model",
          },
        },
        400,
      ),
    ]);
    const err = await fail(c.dev.chat.completions({}));
    expect(err).toBeInstanceOf(ValidationError);
    expect(err.message).toBe("bad model");
    expect(err.code).toBe("bad_model");
    const d = client([new Response("teapot", { status: 418 })]);
    const e = await fail(d.dev.projects.list());
    expect(e).toBeInstanceOf(MisarDevError);
    expect(e.message).toBe("teapot");
  });

  it("retries network failures for idempotent calls, then raises NetworkError", async () => {
    const { dev, calls } = client([new TypeError("fetch failed")], 2);
    await expect(dev.projects.list()).rejects.toBeInstanceOf(NetworkError);
    expect(calls).toHaveLength(2);
  });
});

describe("requests", () => {
  it("encodes path params, required and optional query, and body", async () => {
    const { dev, calls } = client([json({})]);
    await dev.projects.checkSubdomain("a b/c", "my-app");
    expect(calls[0].url).toBe(
      "https://api.test/dev/projects/a%20b%2Fc/subdomain/check?value=my-app",
    );

    await dev.templates.list({ limit: 5, featured: true, category: undefined });
    expect(calls[1].url).toBe(
      "https://api.test/dev/templates?limit=5&featured=true",
    );

    await dev.projects.update("p1", { name: "New" });
    expect(calls[2].method).toBe("PATCH");
    expect(calls[2].body).toEqual({ name: "New" });
  });

  it("returns null for an empty 204", async () => {
    const { dev } = client([new Response(null, { status: 204 })]);
    await expect(dev.projects.delete("p1")).resolves.toBeNull();
  });

  it("exposes a raw request escape hatch", async () => {
    const { dev, calls } = client([json({ hi: 1 })]);
    await expect(
      dev.request("GET", "/usage", { query: { days: 7 } }),
    ).resolves.toEqual({ hi: 1 });
    expect(calls[0].url).toBe("https://api.test/dev/usage?days=7");
  });

  it("builds query strings and backoff delays", () => {
    expect(buildQuery()).toBe("");
    expect(buildQuery({ a: null, b: undefined })).toBe("");
    expect(backoffMs(0, "2")).toBe(2000);
    expect(backoffMs(0, "999")).toBe(60_000);
    expect(backoffMs(3, null)).toBeGreaterThanOrEqual(2000);
    expect(
      backoffMs(0, new Date(Date.now() + 1000).toUTCString()),
    ).toBeLessThanOrEqual(1000);
  });
});

describe("streaming", () => {
  it("streams chat completions until [DONE], forcing stream: true", async () => {
    const { dev, calls } = client([
      sse([
        'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
        ": keep-alive\n\n",
        'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
        "data: [DONE]\n\n",
        'data: {"never":"seen"}\n\n',
      ]),
    ]);
    const chunks: string[] = [];
    for await (const ev of dev.chat.completionsStream<{
      choices: Array<{ delta: { content: string } }>;
    }>({
      model: "misar-online",
      messages: [{ role: "user", content: "hi" }],
    })) {
      chunks.push(ev.data.choices[0].delta.content);
    }
    expect(chunks.join("")).toBe("Hello");
    expect(calls[0].body).toMatchObject({
      stream: true,
      model: "misar-online",
    });
    expect(calls[0].headers.Accept).toBe("text/event-stream");
  });

  it("yields named events, multi-line data, and a trailing unterminated frame", async () => {
    const { dev } = client([
      sse([
        "event: step\nid: 1\ndata: line1\ndata: line2\n\n",
        'data: {"done":true}',
      ]),
    ]);
    const events = [];
    for await (const ev of dev.projects.buildStream("p1")) events.push(ev);
    expect(events[0]).toEqual({ event: "step", id: "1", data: "line1\nline2" });
    expect(events[1].data).toEqual({ done: true });
  });

  it("raises a plan-limit error frame as PlanLimitError", async () => {
    const { dev } = client([
      sse([
        `data: ${JSON.stringify({ type: "error", ...PLAN_LIMIT_BODY })}\n\n`,
      ]),
    ]);
    const it = dev.chat.studioStream({ message: "hi" });
    await expect(it.next()).rejects.toBeInstanceOf(PlanLimitError);
  });

  it("raises an HTTP error before streaming", async () => {
    const { dev } = client([json(PLAN_LIMIT_BODY, 402)]);
    await expect(dev.projects.buildStream("p1").next()).rejects.toBeInstanceOf(
      PlanLimitError,
    );
  });
});

describe("pagination", () => {
  it("walks offset pages until a short page", async () => {
    const pages = [[1, 2], [3, 4], [5]];
    const seen: number[] = [];
    let n = 0;
    for await (const x of paginate<number>(
      async () => ({ items: pages[n++] }),
      { pageSize: 2 },
    ))
      seen.push(x);
    expect(seen).toEqual([1, 2, 3, 4, 5]);
  });

  it("drives a real list method through the client and respects maxItems", async () => {
    const { dev, calls } = client([
      json({ templates: [{ id: 1 }, { id: 2 }] }),
      json({ templates: [{ id: 3 }] }),
    ]);
    const ids: number[] = [];
    for await (const t of dev.paginate<{ id: number }>(
      (offset, limit) => dev.templates.list({ offset, limit }),
      {
        pageSize: 2,
        maxItems: 3,
      },
    )) {
      ids.push(t.id);
    }
    expect(ids).toEqual([1, 2, 3]);
    expect(calls[1].url).toContain("offset=2");
  });
});
