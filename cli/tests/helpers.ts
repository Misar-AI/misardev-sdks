import { run, type RunOptions } from "../src/index.js";

export interface Call {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

export function json(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

export function sse(frames: string[], status = 200): Response {
  return new Response(frames.join(""), {
    status,
    headers: { "content-type": "text/event-stream" },
  });
}

/** A fetch stub that records every call and answers from a queue (last answer repeats). */
export function stubFetch(responses: Array<Response | Error> = []) {
  const calls: Call[] = [];
  const queue = [...responses];
  const fetchImpl = (async (
    input: RequestInfo | URL,
    init: RequestInit = {},
  ) => {
    calls.push({
      url: String(input),
      method: String(init.method),
      headers: init.headers as Record<string, string>,
      body: init.body ? JSON.parse(String(init.body)) : undefined,
    });
    const next = queue.length > 1 ? queue.shift() : queue[0];
    if (next instanceof Error) throw next;
    return next ? next.clone() : json({ ok: true });
  }) as typeof fetch;
  return { calls, fetchImpl };
}

class Sink {
  text = "";
  write(s: string) {
    this.text += s;
    return true;
  }
}

export const API_KEY = "mdk_test_secret_key_123";
export const BASE = "https://api.test/dev";

/** Run the CLI against a fetch stub; returns exit code, captured output and recorded calls. */
export async function cli(
  argv: string[],
  responses: Array<Response | Error> = [],
  extra: Partial<RunOptions> = {},
) {
  const stub = stubFetch(responses);
  const stdout = new Sink();
  const stderr = new Sink();
  const code = await run(argv, {
    stdout,
    stderr,
    fetch: stub.fetchImpl,
    env: { MISARDEV_API_KEY: API_KEY, MISARDEV_BASE_URL: BASE },
    ...extra,
  });
  return { code, stdout: stdout.text, stderr: stderr.text, calls: stub.calls };
}

export const PLAN_LIMIT_BODY = {
  error: "API access requires the Pro plan or higher.",
  code: "plan_limit_exceeded",
  requiredPlan: "pro",
  upgrade: {
    product: "dev",
    product_name: "Misar.Dev",
    reason: "feature_locked",
    feature: "api_access",
    feature_label: "API access",
    headline: "API access isn't included in your Starter plan.",
    usage: null,
    current_plan: { slug: "starter", name: "Starter" },
    recommended_plan: "pro",
    plans: [] as unknown[],
    topup: null,
    overage: null,
    trial: null,
    cross_sell: [],
    urls: {
      pricing: "https://www.misar.dev/pricing",
      billing: "https://www.misar.dev/settings/billing",
      docs: "https://docs.misar.io/dev/api",
      compare: "https://www.misar.dev/pricing#compare",
    },
    cta: "Upgrade to Pro to continue.",
  },
};
