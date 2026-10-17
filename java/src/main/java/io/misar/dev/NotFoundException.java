package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 404 — no such resource, or not one this key can see. */
public class NotFoundException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public NotFoundException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
