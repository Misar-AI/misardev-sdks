package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

import java.io.BufferedReader;
import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.http.HttpHeaders;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Spliterator;
import java.util.Spliterators;
import java.util.stream.Stream;
import java.util.stream.StreamSupport;

/**
 * A live Server-Sent Events stream: iterate it, then close it.
 *
 * <p>Frames are separated by a blank line and may span several {@code data:}
 * lines, which are joined with newlines. Comment lines ({@code :}) are
 * keep-alives and are skipped. The terminator payload — {@code [DONE]} on the
 * OpenAI-compatible chat completions stream — ends iteration and is never
 * yielded. A final frame with no closing blank line is still delivered.
 *
 * <pre>{@code
 * try (SseStream events = dev.chat.completionsStream(body)) {
 *     for (SseEvent e : events) System.out.print(e.data().at("/choices/0/delta/content").asText(""));
 * }
 * }</pre>
 *
 * <p>Single use: {@link #iterator()} returns this same iterator. The
 * connection is released when the stream ends, when it throws, or on
 * {@link #close()}.
 */
public final class SseStream implements Iterable<SseEvent>, Iterator<SseEvent>, Closeable {

    private final BufferedReader reader;
    private final String terminator;
    private final HttpHeaders headers;
    private SseEvent next;
    private boolean done;

    SseStream(InputStream body, String terminator, HttpHeaders headers) {
        this.reader = new BufferedReader(new InputStreamReader(body, StandardCharsets.UTF_8));
        this.terminator = terminator;
        this.headers = headers;
    }

    @Override
    public Iterator<SseEvent> iterator() {
        return this;
    }

    @Override
    public boolean hasNext() {
        if (next != null) return true;
        if (done) return false;
        try {
            next = readEvent();
        } catch (IOException e) {
            close();
            throw new NetworkException("Stream interrupted: " + e.getMessage(), e);
        } catch (RuntimeException e) {
            close();
            throw e;
        }
        if (next == null) close();
        return next != null;
    }

    @Override
    public SseEvent next() {
        if (!hasNext()) throw new NoSuchElementException();
        SseEvent e = next;
        next = null;
        return e;
    }

    /** The events as a {@link Stream}; closing it closes the connection. */
    public Stream<SseEvent> stream() {
        return StreamSupport.stream(Spliterators.spliteratorUnknownSize(this, Spliterator.ORDERED | Spliterator.NONNULL), false)
                .onClose(this::close);
    }

    /** Collect every remaining event (blocks until the stream ends). */
    public List<SseEvent> toList() {
        List<SseEvent> out = new ArrayList<>();
        while (hasNext()) out.add(next());
        return out;
    }

    @Override
    public void close() {
        done = true;
        try {
            reader.close();
        } catch (IOException ignored) {
            // Nothing useful to do: the connection is being abandoned either way.
        }
    }

    /** Read frames until one yields an event; null at the end of the stream. */
    private SseEvent readEvent() throws IOException {
        String event = null;
        String id = null;
        List<String> data = new ArrayList<>();
        while (true) {
            String line = done ? null : reader.readLine();
            if (line == null || line.isEmpty()) {
                if (!data.isEmpty()) {
                    SseEvent e = finish(event, id, String.join("\n", data));
                    if (e == null) return null; // terminator
                    if (line == null) done = true;
                    return e;
                }
                if (line == null) return null;
                event = null;
                id = null;
                continue;
            }
            if (line.startsWith(":")) continue;
            int idx = line.indexOf(':');
            String field = idx == -1 ? line : line.substring(0, idx);
            String value = idx == -1 ? "" : line.substring(idx + 1);
            if (value.startsWith(" ")) value = value.substring(1);
            switch (field) {
                case "data":
                    data.add(value);
                    break;
                case "event":
                    event = value;
                    break;
                case "id":
                    id = value;
                    break;
                default:
                    break;
            }
        }
    }

    /** Build the event for a complete frame; null when it is the terminator. */
    private SseEvent finish(String event, String id, String raw) {
        if (terminator != null && raw.trim().equals(terminator)) {
            done = true;
            return null;
        }
        JsonNode data = Transport.parse(raw);
        // Other error frames are the stream's own business (the build stream
        // reports a failed step and carries on), so only the plan refusal —
        // which no amount of reading further will fix — is raised.
        if (Transport.isPlanLimitBody(data)) throw Transport.errorFor(402, headers, data);
        return new SseEvent(event, data, id);
    }
}
