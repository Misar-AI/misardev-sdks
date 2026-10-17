package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 400 / 422 — the request was malformed or failed validation. */
public class ValidationException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public ValidationException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
