package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Objects;

/** One Server-Sent Event. */
public final class SseEvent {
    private final String event;
    private final JsonNode data;
    private final String id;

    public SseEvent(String event, JsonNode data, String id) {
        this.event = event;
        this.data = data;
        this.id = id;
    }

    /** The {@code event:} name, or {@code null} when the server sent none. */
    public String event() {
        return event;
    }

    /** The JSON-decoded {@code data:} payload, or a text node holding the raw string when it is not JSON. */
    public JsonNode data() {
        return data;
    }

    /** The {@code id:} field, or {@code null}. */
    public String id() {
        return id;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof SseEvent)) return false;
        SseEvent other = (SseEvent) o;
        return Objects.equals(event, other.event) && Objects.equals(data, other.data) && Objects.equals(id, other.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(event, data, id);
    }

    @Override
    public String toString() {
        return "SseEvent{event=" + event + ", id=" + id + ", data=" + data + "}";
    }
}
