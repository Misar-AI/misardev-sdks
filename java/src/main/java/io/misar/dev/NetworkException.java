package io.misar.dev;

/** The request never got an HTTP answer (DNS, TLS, connection reset, timeout). Status is {@code 0}. */
public class NetworkException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    public NetworkException(String message, Throwable cause) {
        super(0, message, "network_error", null, null, cause);
    }
}
