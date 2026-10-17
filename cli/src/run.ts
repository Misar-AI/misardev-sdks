/**
 * The `misardev` command runner.
 *
 * Every command comes from the generated table in ./generated/commands.ts (one
 * entry per manifest method and SSE stream), so the CLI covers exactly what the
 * API exposes:
 *
 *   misardev <resource> <method> [pathParams...] [requiredQuery...]
 *            [--body <json|@file>] [--query key=value ...] [--json]
 *
 * Each command is one call into @misardev/sdk — `dev[resource][method](...)` —
 * which owns auth, retries, typed errors and SSE parsing. The CLI only maps
 * arguments in and renders results (or the upgrade card) out.
 *
 * Authentication is the account API key and nothing else: `--api-key`, else
 * MISARDEV_API_KEY. What that key may do is decided server-side by the plan
 * behind it; a refusal arrives as a PlanLimitError and is rendered as an
 * upgrade card on stderr with exit code 2.
 */

import { readFileSync } from "node:fs";
import { Command, CommanderError } from "commander";
import {
  MisarDev,
  MisarDevError,
  PlanLimitError,
  type SSEEvent,
} from "@misardev/sdk";
import { COMMANDS, RESOURCES, type CommandSpec } from "./generated/commands.js";
import {
  deltaContent,
  formatEvent,
  formatResult,
  renderPlanLimitCard,
} from "./render.js";

export const CLI_VERSION = "1.0.0";
export const API_KEYS_URL = "https://www.misar.dev/settings/api-keys";

/** Exit codes: 0 ok, 1 error, 2 blocked by the plan behind the key. */
export const EXIT_OK = 0;
export const EXIT_ERROR = 1;
export const EXIT_PLAN_LIMIT = 2;

interface Writer {
  write(chunk: string): unknown;
}

export interface RunOptions {
  stdout?: Writer;
  stderr?: Writer;
  /** Environment to read MISARDEV_API_KEY / MISARDEV_BASE_URL from. Default `process.env`. */
  env?: Record<string, string | undefined>;
  /** fetch implementation handed to the SDK (tests, proxies). */
  fetch?: typeof fetch;
  /** Reads all of stdin, for `--body @-`. */
  readStdin?: () => Promise<string>;
}

/** A mistake in how the command was invoked (bad JSON, unknown query key, no key). */
export class UsageError extends Error {
  override name = "UsageError";
}

const kebab = (s: string) =>
  s
    .replace(/([a-z0-9])([A-Z])/g, "$1-$2")
    .replace(/[_\s]+/g, "-")
    .toLowerCase();

const collect = (value: string, previous: string[]) => [...previous, value];

async function readProcessStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks).toString("utf8");
}

/** `--body '{"a":1}'`, `--body @payload.json`, or `--body @-` (stdin). */
export async function parseBody(
  raw: string,
  readStdin: () => Promise<string>,
): Promise<Record<string, unknown>> {
  let text = raw;
  let source = "--body";
  if (raw.startsWith("@")) {
    const file = raw.slice(1);
    if (!file)
      throw new UsageError("--body @ needs a file name, or @- to read stdin.");
    source = file === "-" ? "stdin" : file;
    try {
      text = file === "-" ? await readStdin() : readFileSync(file, "utf8");
    } catch (err) {
      throw new UsageError(
        `Could not read ${source}: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (err) {
    throw new UsageError(
      `${source} is not valid JSON: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new UsageError(
      `${source} must be a JSON object, e.g. '{"name":"my-app"}'.`,
    );
  }
  return value as Record<string, unknown>;
}

/** `--query limit=10 --query view=all` → `{ limit: "10", view: "all" }`, checked against the route. */
export function parseQuery(
  pairs: string[],
  allowed: readonly string[],
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const pair of pairs) {
    const idx = pair.indexOf("=");
    if (idx <= 0)
      throw new UsageError(`--query expects key=value, got "${pair}".`);
    const key = pair.slice(0, idx);
    if (!allowed.includes(key)) {
      throw new UsageError(
        `Unknown query parameter "${key}". This command accepts: ${allowed.join(", ") || "none"}.`,
      );
    }
    out[key] = pair.slice(idx + 1);
  }
  return out;
}

function describe(spec: CommandSpec): string {
  const parts = [spec.summary];
  if (spec.stream)
    parts.push(
      spec.terminator === "[DONE]"
        ? "— streamed; prints the reply as it arrives"
        : "— streams events",
    );
  if (spec.auth === "public") parts.push("(public)");
  return parts.join(" ");
}

/** Build the commander program. A fresh one per run: commander keeps parse state. */
export function buildProgram(options: RunOptions = {}): Command {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const env = options.env ?? process.env;
  const readStdin = options.readStdin ?? readProcessStdin;

  const program = new Command("misardev")
    .description("Misar.Dev from the terminal — every API route as a command.")
    .version(CLI_VERSION)
    .option(
      "--api-key <key>",
      "account API key (mdk_…); defaults to MISARDEV_API_KEY",
    )
    .option(
      "--base-url <url>",
      "API base URL; defaults to MISARDEV_BASE_URL or https://api.misar.io/dev",
    )
    .configureOutput({
      writeOut: (s) => void stdout.write(s),
      writeErr: (s) => void stderr.write(s),
    })
    .exitOverride()
    .addHelpText(
      "after",
      [
        "",
        "Examples:",
        "  misardev projects list",
        "  misardev projects list-files <project-id>",
        '  misardev projects create --body \'{"name":"my-app"}\'',
        "  misardev projects check-subdomain <project-id> my-app",
        "  misardev templates list --query category=saas --query limit=10",
        '  misardev chat completions-stream --body \'{"messages":[{"role":"user","content":"Hi"}]}\'',
        "  misardev usage",
        "",
        `Create an API key at ${API_KEYS_URL}`,
      ].join("\n"),
    );

  const client = (cmd: Command): MisarDev => {
    const globals = cmd.optsWithGlobals() as {
      apiKey?: string;
      baseUrl?: string;
    };
    const apiKey = globals.apiKey || env.MISARDEV_API_KEY;
    if (!apiKey) {
      throw new UsageError(
        `No API key. Pass --api-key or set MISARDEV_API_KEY. Create one at ${API_KEYS_URL}.`,
      );
    }
    return new MisarDev(apiKey, {
      baseURL: globals.baseUrl || env.MISARDEV_BASE_URL || undefined,
      fetch: options.fetch,
      headers: { "X-Misar-SDK": `misardev-cli/${CLI_VERSION}` },
    });
  };

  const groups = new Map<string, Command>();
  for (const spec of COMMANDS) {
    let group = groups.get(spec.group);
    if (!group) {
      group = program
        .command(spec.group)
        .description(
          RESOURCES[spec.resource] ?? `The ${spec.resource} resource.`,
        );
      groups.set(spec.group, group);
    }

    // `misardev usage` alone shows usage — the 0.x CLI's shortcut.
    const isDefault = spec.resource === "usage" && spec.method === "list";
    const cmd = group
      .command(spec.command, { isDefault })
      .description(describe(spec));
    for (const p of spec.pathParams)
      cmd.argument(`<${kebab(p)}>`, `path parameter :${p}`);
    for (const q of spec.requiredQuery)
      cmd.argument(`<${kebab(q)}>`, `query parameter ${q}`);
    if (spec.hasBody)
      cmd.option(
        "--body <json|@file>",
        "JSON request body, or @file to read it (@- for stdin)",
      );
    if (spec.optionalQuery.length) {
      cmd.option(
        "--query <key=value>",
        `optional query parameter, repeatable: ${spec.optionalQuery.join(", ")}`,
        collect,
        [],
      );
    }
    cmd.option(
      "--json",
      spec.stream
        ? "print every event as one JSON line"
        : "print compact JSON on one line",
    );

    cmd.action(async (...actionArgs: unknown[]) => {
      const self = actionArgs[actionArgs.length - 1] as Command;
      const opts = self.opts() as {
        body?: string;
        query?: string[];
        json?: boolean;
      };
      const args: unknown[] = [...(self.processedArgs as string[])];
      if (spec.hasBody)
        args.push(
          opts.body !== undefined ? await parseBody(opts.body, readStdin) : {},
        );
      if (spec.optionalQuery.length)
        args.push(parseQuery(opts.query ?? [], spec.optionalQuery));

      const dev = client(self);
      const resource = (
        dev as unknown as Record<
          string,
          Record<string, (...a: unknown[]) => unknown>
        >
      )[spec.accessor];
      const fn = resource?.[spec.method];
      if (typeof fn !== "function") {
        throw new UsageError(
          `@misardev/sdk has no ${spec.accessor}.${spec.method}() — update the SDK.`,
        );
      }

      if (!spec.stream) {
        const result = await (fn.apply(resource, args) as Promise<unknown>);
        const text = formatResult(result, Boolean(opts.json));
        if (text !== null) stdout.write(`${text}\n`);
        return;
      }

      const events = fn.apply(resource, args) as AsyncGenerator<SSEEvent>;
      const chat = spec.terminator === "[DONE]";
      let inline = false;
      for await (const ev of events) {
        if (opts.json) {
          stdout.write(`${JSON.stringify(ev)}\n`);
          continue;
        }
        if (chat) {
          const content = deltaContent(ev.data);
          if (content !== null) {
            stdout.write(content);
            inline = true;
          } else if (
            ev.data &&
            typeof ev.data === "object" &&
            "error" in ev.data
          ) {
            stderr.write(`${formatEvent(ev)}\n`);
          }
          continue;
        }
        stdout.write(`${formatEvent(ev)}\n`);
      }
      if (inline) stdout.write("\n");
    });
  }

  return program;
}

function redact(text: string, secrets: Array<string | undefined>): string {
  let out = text;
  for (const s of secrets)
    if (s && s.length >= 4) out = out.split(s).join("***");
  return out;
}

function isPlanLimit(err: unknown): err is PlanLimitError {
  // The name check covers a second copy of the SDK in node_modules, where
  // instanceof against this copy's class would miss.
  return (
    err instanceof PlanLimitError ||
    (err instanceof Error && err.name === "PlanLimitError" && "offer" in err)
  );
}

/** Run the CLI with `argv` (without `node` and the script path). Resolves to the exit code. */
export async function run(
  argv: string[],
  options: RunOptions = {},
): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const env = options.env ?? process.env;
  const apiKeyArg =
    argv.find((a, i) => argv[i - 1] === "--api-key") ??
    argv.find((a) => a.startsWith("--api-key="))?.slice(10);
  const secrets = [env.MISARDEV_API_KEY, apiKeyArg];
  const err = (s: string) => void stderr.write(`${redact(s, secrets)}\n`);

  const program = buildProgram(options);
  try {
    await program.parseAsync(argv, { from: "user" });
    return EXIT_OK;
  } catch (e) {
    if (e instanceof CommanderError) return e.exitCode;
    if (isPlanLimit(e)) {
      err(renderPlanLimitCard(e));
      return EXIT_PLAN_LIMIT;
    }
    if (e instanceof MisarDevError) {
      const status = e.status ? ` (HTTP ${e.status})` : "";
      const code = e.code ? ` [${e.code}]` : "";
      err(`Error${status}: ${e.message}${code}`);
      if (e.requestId) err(`Request id: ${e.requestId}`);
      return EXIT_ERROR;
    }
    err(`Error: ${e instanceof Error ? e.message : String(e)}`);
    return EXIT_ERROR;
  }
}
