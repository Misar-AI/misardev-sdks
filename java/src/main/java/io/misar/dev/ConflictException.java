package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 409 — conflicts with current state (for example a build already running). */
public class ConflictException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public ConflictException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
