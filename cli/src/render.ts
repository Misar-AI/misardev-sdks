/**
 * Terminal rendering: results, stream events, and the plan-limit upgrade card.
 *
 * All upgrade copy (headline, plan names, prices, call to action, URLs) comes
 * from the server's offer — the CLI only lays it out.
 */

import type { PlanLimitError, SSEEvent, UpgradeOffer } from "@misardev/sdk";

/** Pretty JSON by default; one compact line with `--json` (pipe-friendly). */
export function formatResult(value: unknown, compact: boolean): string | null {
  if (value === null || value === undefined) return compact ? "null" : null;
  if (typeof value === "string" && !compact) return value;
  return compact ? JSON.stringify(value) : JSON.stringify(value, null, 2);
}

/** The text delta of an OpenAI-compatible `chat.completion.chunk`, if any. */
export function deltaContent(data: unknown): string | null {
  if (!data || typeof data !== "object") return null;
  const choices = (data as { choices?: unknown }).choices;
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const delta = (choices[0] as { delta?: { content?: unknown } } | null)?.delta;
  return typeof delta?.content === "string" ? delta.content : null;
}

/** One human-readable line for a non-chat stream event. */
export function formatEvent(ev: SSEEvent): string {
  const data = typeof ev.data === "string" ? ev.data : JSON.stringify(ev.data);
  return ev.event ? `${ev.event}: ${data}` : data;
}

type Plan = UpgradeOffer["plans"][number];

function planLine(p: Plan): string[] {
  const tags = [
    p.recommended ? "recommended" : null,
    p.current ? "current plan" : null,
  ].filter(Boolean);
  const price = [p.price, p.price_note].filter(Boolean).join(" ");
  const head = `  • ${p.name}${price ? ` — ${price}` : ""}${tags.length ? `  (${tags.join(", ")})` : ""}`;
  const out = [head];
  if (p.unlocks) out.push(`      unlocks: ${p.unlocks}`);
  return out;
}

/**
 * The upgrade card printed (to stderr) when the subscription behind the key
 * does not cover a call. Works with a partial or missing offer.
 */
export function renderPlanLimitCard(err: PlanLimitError): string {
  const offer = (err.offer ?? null) as Partial<UpgradeOffer> | null;
  const title = offer?.product_name
    ? `Upgrade required — ${offer.product_name}`
    : "Upgrade required";
  const lines: string[] = [
    title,
    "─".repeat(Math.min(Math.max(title.length, 24), 60)),
  ];

  lines.push(offer?.headline || err.message);
  if (offer?.current_plan?.name)
    lines.push(`Current plan: ${offer.current_plan.name}`);

  const usage = offer?.usage;
  if (usage && (usage.used !== null || usage.limit !== null)) {
    const period = usage.period ? ` this ${usage.period}` : "";
    const resets = usage.resets_at ? ` · resets ${usage.resets_at}` : "";
    lines.push(
      `Usage: ${usage.used ?? "?"} of ${usage.limit ?? "?"}${period}${resets}`,
    );
  } else if (err.retryAfter) {
    lines.push(`Resets in about ${Math.ceil(err.retryAfter / 60)} minute(s).`);
  }

  const plans = Array.isArray(offer?.plans) ? offer.plans : [];
  if (plans.length) {
    lines.push("", "Plans:");
    for (const p of plans) lines.push(...planLine(p));
  }

  if (offer?.cta) lines.push("", offer.cta);
  const url = err.upgradeUrl;
  if (url) lines.push(`Upgrade: ${url}`);
  return lines.join("\n");
}
