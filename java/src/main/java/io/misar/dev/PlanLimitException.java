package io.misar.dev;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * The subscription behind the API key blocks this call.
 *
 * <p>Detected by {@code code: "plan_limit_exceeded"} in the body — never by
 * status, because a spent quota is a 429 ({@code quota_exhausted}) that would
 * otherwise look like an ordinary throttle, and a feature outside the plan is a
 * 402 ({@code feature_locked}). Retrying cannot help until the plan changes or
 * the period resets, so the client never retries it.
 *
 * <p>{@link #getOffer()} is the full upgrade offer the server sent (headline,
 * plans with prices, URLs, call to action). Render it rather than a bare
 * failure; all copy comes from the server.
 */
public class PlanLimitException extends MisarDevException {
    private static final long serialVersionUID = 1L;

    private final transient JsonNode offer;
    private final Integer retryAfter;

    public PlanLimitException(int status, String message, JsonNode body, String requestId, JsonNode offer, Integer retryAfter) {
        super(status, message, "plan_limit_exceeded", body, requestId, null);
        this.offer = offer;
        this.retryAfter = retryAfter;
    }

    /** The full {@code upgrade} object from the body, every field kept, or {@code null}. */
    public JsonNode getOffer() {
        return offer;
    }

    /** Seconds until a quota resets ({@code Retry-After}), for {@code quota_exhausted} blocks, or {@code null}. */
    public Integer getRetryAfter() {
        return retryAfter;
    }

    /** Where to send the user to unblock themselves: {@code offer.urls.billing}, else {@code offer.urls.pricing}. */
    public String getUpgradeUrl() {
        String billing = text(offer, "urls", "billing");
        return billing != null ? billing : text(offer, "urls", "pricing");
    }

    /** The machine key of the limit that was hit, for example {@code api_access}. */
    public String getFeature() {
        return text(offer, "feature");
    }

    /** The slug of the plan the key is on ({@code offer.current_plan.slug}). */
    public String getCurrentPlan() {
        return text(offer, "current_plan", "slug");
    }

    /** The slug of the plan the server recommends ({@code offer.recommended_plan}). */
    public String getRecommendedPlan() {
        return text(offer, "recommended_plan");
    }

    private static String text(JsonNode node, String... path) {
        JsonNode cur = node;
        for (String p : path) {
            if (cur == null || !cur.isObject()) return null;
            cur = cur.get(p);
        }
        return cur != null && cur.isTextual() ? cur.asText() : null;
    }
}
