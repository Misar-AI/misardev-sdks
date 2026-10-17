<?php

declare(strict_types=1);

namespace MisarDev;

/**
 * The subscription behind the API key blocks this call.
 *
 * Detected by `code: "plan_limit_exceeded"` in the body — NEVER by status,
 * because a spent quota is a 429 that would otherwise look like an ordinary
 * throttle. A feature that is not on the plan answers 402 (`feature_locked`);
 * a spent allowance answers 429 (`quota_exhausted`). Retrying cannot help until
 * the plan changes or the period resets, so the transport never retries it.
 */
class PlanLimitError extends MisarDevError
{
    /**
     * @param array<string,mixed>|null $offer      The full upgrade offer, every field the server sent.
     *                                             Render it; all copy comes from the server.
     * @param float|null               $retryAfter Seconds until a quota resets, for `quota_exhausted` blocks.
     */
    public function __construct(
        int $status,
        string $message,
        mixed $body = null,
        ?string $requestId = null,
        public readonly ?array $offer = null,
        public readonly ?float $retryAfter = null,
    ) {
        parent::__construct($status, $message, 'plan_limit_exceeded', $body, $requestId);
    }

    /** Where to send the user to unblock themselves: billing, else pricing. */
    public function upgradeUrl(): ?string
    {
        $urls = $this->offer['urls'] ?? null;
        if (!is_array($urls)) {
            return null;
        }
        $url = $urls['billing'] ?? $urls['pricing'] ?? null;
        return is_string($url) ? $url : null;
    }

    /** The machine key of the limit that was hit, e.g. `api_access`. */
    public function feature(): ?string
    {
        $f = $this->offer['feature'] ?? null;
        return is_string($f) ? $f : null;
    }

    /** The slug of the plan the key is on now, e.g. `starter`. */
    public function currentPlan(): ?string
    {
        $plan = $this->offer['current_plan'] ?? null;
        $slug = is_array($plan) ? ($plan['slug'] ?? null) : null;
        return is_string($slug) ? $slug : null;
    }

    /** The slug of the plan the server recommends, e.g. `pro`. */
    public function recommendedPlan(): ?string
    {
        $r = $this->offer['recommended_plan'] ?? null;
        return is_string($r) ? $r : null;
    }
}
