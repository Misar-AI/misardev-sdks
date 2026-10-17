package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/** 5xx — the API failed. Retried automatically for idempotent requests (GET, HEAD, OPTIONS, PUT, DELETE). */
public class ServerException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public ServerException(int status, String message, String code, JsonNode body, String requestId) {
        super(status, message, code, body, requestId, null);
    }
}
