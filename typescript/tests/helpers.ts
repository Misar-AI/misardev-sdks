import { MisarDev } from "../src/index.js";

export interface Call {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

/** A fetch stub that records calls and answers from a queue of responses. */
export function stubFetch(
  responses: Array<Response | (() => Response) | Error> = [],
) {
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
    if (typeof next === "function") return next();
    return next ? next.clone() : json({ ok: true });
  }) as typeof fetch;
  return { calls, fetchImpl };
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

export function client(
  responses: Array<Response | (() => Response) | Error> = [],
  maxRetries = 3,
) {
  const stub = stubFetch(responses);
  const dev = new MisarDev("mdk_test_key", {
    fetch: stub.fetchImpl,
    maxRetries,
    baseURL: "https://api.test/dev",
  });
  return { dev, ...stub };
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
    plans: [],
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
