package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 401 — the key is missing, revoked, expired, or not a MisarDev key. */
public class AuthenticationException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public AuthenticationException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
