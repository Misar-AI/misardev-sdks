/**
 * Server-Sent Events parsing.
 *
 * Frames are separated by a blank line and may span several `data:` lines,
 * which are joined with newlines per the SSE spec. Comment lines (`:`) are
 * keep-alives and are skipped. The terminator payload — `[DONE]` on the
 * OpenAI-compatible `/v1/chat/completions` stream — ends iteration and is never
 * yielded, so callers can simply read to completion.
 */

export interface SSEEvent<T = unknown> {
  /** The `event:` name, when the server sends one. */
  event: string | null;
  /** JSON-decoded `data:` payload, or the raw string when it is not JSON. */
  data: T;
  /** The `id:` field, when present. */
  id: string | null;
}

function decode(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

/** Parse one complete frame (the text between blank lines). */
export function parseFrame(frame: string): {
  event: string | null;
  data: string | null;
  id: string | null;
} {
  let event: string | null = null;
  let id: string | null = null;
  const data: string[] = [];
  for (const line of frame.split(/\r?\n/)) {
    if (!line || line.startsWith(":")) continue;
    const idx = line.indexOf(":");
    const field = idx === -1 ? line : line.slice(0, idx);
    let value = idx === -1 ? "" : line.slice(idx + 1);
    if (value.startsWith(" ")) value = value.slice(1);
    if (field === "data") data.push(value);
    else if (field === "event") event = value;
    else if (field === "id") id = value;
  }
  return { event, data: data.length ? data.join("\n") : null, id };
}

/** Iterate the events of a `text/event-stream` body. */
export async function* parseSSE<T = unknown>(
  body: ReadableStream<Uint8Array>,
  terminator: string | null = "[DONE]",
): AsyncGenerator<SSEEvent<T>, void, unknown> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (value) buffer += decoder.decode(value, { stream: true });
      if (done) buffer += decoder.decode();

      let boundary: RegExpExecArray | null;
      const sep = /\r?\n\r?\n/;
      while ((boundary = sep.exec(buffer))) {
        const frame = buffer.slice(0, boundary.index);
        buffer = buffer.slice(boundary.index + boundary[0].length);
        const parsed = parseFrame(frame);
        if (parsed.data === null) continue;
        if (terminator !== null && parsed.data.trim() === terminator) return;
        yield {
          event: parsed.event,
          data: decode(parsed.data) as T,
          id: parsed.id,
        };
      }

      if (done) {
        const parsed = parseFrame(buffer);
        if (
          parsed.data !== null &&
          !(terminator !== null && parsed.data.trim() === terminator)
        ) {
          yield {
            event: parsed.event,
            data: decode(parsed.data) as T,
            id: parsed.id,
          };
        }
        return;
      }
    }
  } finally {
    reader.releaseLock();
  }
}
