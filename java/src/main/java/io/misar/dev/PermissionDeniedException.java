package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 403 — authenticated, but not allowed to touch this resource. */
public class PermissionDeniedException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public PermissionDeniedException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
