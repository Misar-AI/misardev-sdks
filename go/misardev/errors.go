package misardev

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// APIError is the base of every error the SDK returns. Each concrete type
// below embeds it, so a caller can match the kind of failure with errors.As
// against the concrete type, or catch everything with errors.As(err, &apiErr)
// where apiErr is a *APIError.
type APIError struct {
	// Status is the HTTP status, or 0 when the request never got an answer.
	Status int
	// Message is the human-readable reason the API gave.
	Message string
	// Code is the machine-readable error code from the body, when sent.
	Code string
	// Body is the decoded error body (JSON value, or the raw text).
	Body any
	// RequestID is the x-request-id response header, for support requests.
	RequestID string
}

func (e *APIError) Error() string {
	if e.Code != "" {
		return fmt.Sprintf("misardev: %d %s: %s", e.Status, e.Code, e.Message)
	}
	return fmt.Sprintf("misardev: %d: %s", e.Status, e.Message)
}

// IsRetryable reports a throttle or a transient server condition.
func (e *APIError) IsRetryable() bool {
	return e.Status == 429 || (e.Status >= 500 && e.Status < 600)
}

// ValidationError is a 400 or 422: the request was malformed or failed validation.
type ValidationError struct{ *APIError }

// AuthenticationError is a 401: the key is missing, revoked, expired, or not a MisarDev key.
type AuthenticationError struct{ *APIError }

// PermissionDeniedError is a 403: authenticated, but not allowed to touch this resource.
type PermissionDeniedError struct{ *APIError }

// NotFoundError is a 404: no such resource, or not one this key can see.
type NotFoundError struct{ *APIError }

// ConflictError is a 409: the request conflicts with current state.
type ConflictError struct{ *APIError }

// ServerError is a 5xx. Retried automatically for idempotent requests.
type ServerError struct{ *APIError }

// RateLimitError is a 429 that is an ordinary throttle, returned once the
// client has already retried it MaxRetries times.
type RateLimitError struct {
	*APIError
	// RetryAfter is the number of seconds the server asked us to wait, or -1
	// when it did not say.
	RetryAfter int
}

// NetworkError means the request never got an HTTP answer (DNS, TLS, reset,
// timeout). Status is 0.
type NetworkError struct {
	*APIError
	Cause error
}

// PlanLimitError means the subscription behind the API key blocks this call.
//
// It is detected by `code: "plan_limit_exceeded"` in the body — never by
// status, because a spent quota is a 429 that would otherwise look like an
// ordinary throttle. Retrying cannot help until the plan changes or the
// period resets, so the client never retries it.
type PlanLimitError struct {
	*APIError
	// Offer is the full upgrade offer the server sent, with every field kept.
	// Render it; all copy comes from the server.
	Offer map[string]any
	// RetryAfter is the Retry-After header in seconds (quota_exhausted
	// blocks), or -1 when absent.
	RetryAfter int
}

func (e *ValidationError) Unwrap() error       { return e.APIError }
func (e *AuthenticationError) Unwrap() error   { return e.APIError }
func (e *PermissionDeniedError) Unwrap() error { return e.APIError }
func (e *NotFoundError) Unwrap() error         { return e.APIError }
func (e *ConflictError) Unwrap() error         { return e.APIError }
func (e *ServerError) Unwrap() error           { return e.APIError }
func (e *RateLimitError) Unwrap() error        { return e.APIError }
func (e *PlanLimitError) Unwrap() error        { return e.APIError }

// Unwrap exposes both the base *APIError and the underlying transport error.
func (e *NetworkError) Unwrap() []error {
	if e.Cause == nil {
		return []error{e.APIError}
	}
	return []error{e.APIError, e.Cause}
}

// UpgradeURL is where to send the user to unblock themselves: the offer's
// billing URL, falling back to its pricing URL.
func (e *PlanLimitError) UpgradeURL() string {
	if s := str(dig(e.Offer, "urls", "billing")); s != "" {
		return s
	}
	return str(dig(e.Offer, "urls", "pricing"))
}

// Feature is the machine key of the limit that was hit, e.g. "api_access".
func (e *PlanLimitError) Feature() string { return str(dig(e.Offer, "feature")) }

// Reason is "feature_locked", "quota_exhausted", or another offer reason.
func (e *PlanLimitError) Reason() string { return str(dig(e.Offer, "reason")) }

// Headline is the server-written one-line explanation of the refusal.
func (e *PlanLimitError) Headline() string { return str(dig(e.Offer, "headline")) }

// CurrentPlan is the slug of the plan the key is on.
func (e *PlanLimitError) CurrentPlan() string { return str(dig(e.Offer, "current_plan", "slug")) }

// RecommendedPlan is the slug of the plan that would unblock the call.
func (e *PlanLimitError) RecommendedPlan() string { return str(dig(e.Offer, "recommended_plan")) }

// Plans is the list of plan options in the offer, each a JSON object.
func (e *PlanLimitError) Plans() []map[string]any {
	raw, _ := dig(e.Offer, "plans").([]any)
	out := make([]map[string]any, 0, len(raw))
	for _, p := range raw {
		if m, ok := p.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

func dig(v any, keys ...string) any {
	for _, k := range keys {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		v = m[k]
	}
	return v
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

// isPlanLimitBody reports whether a decoded body is the plan-limit refusal.
func isPlanLimitBody(body any) bool {
	return str(dig(body, "code")) == "plan_limit_exceeded"
}

// messageOf pulls a human message out of the API's several error shapes.
func messageOf(body any, fallback string) string {
	if m, ok := body.(map[string]any); ok {
		if s, ok := m["error"].(string); ok {
			return s
		}
		// /v1/* answers in the OpenAI shape: {"error": {"message", "type", "code"}}
		if s := str(dig(m, "error", "message")); s != "" {
			return s
		}
		if s, ok := m["message"].(string); ok {
			return s
		}
	}
	if s, ok := body.(string); ok {
		if s = strings.TrimSpace(s); s != "" {
			if len(s) > 500 {
				s = s[:500]
			}
			return s
		}
	}
	return fallback
}

func codeOf(body any) string {
	if s := str(dig(body, "code")); s != "" {
		return s
	}
	return str(dig(body, "error", "code"))
}

// retryAfterSeconds parses a Retry-After header given in seconds; -1 when
// absent or not a number.
func retryAfterSeconds(h http.Header) int {
	v := strings.TrimSpace(h.Get("Retry-After"))
	if v == "" {
		return -1
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return -1
	}
	return n
}

// errorFor maps an error response to the right typed error. Plan limits are
// checked first, by code, whatever the status.
func errorFor(status int, h http.Header, body any, reason string) error {
	fallback := strings.TrimSpace(reason)
	if fallback == "" {
		fallback = fmt.Sprintf("HTTP %d", status)
	}
	base := &APIError{
		Status:    status,
		Message:   messageOf(body, fallback),
		Code:      codeOf(body),
		Body:      body,
		RequestID: h.Get("X-Request-Id"),
	}
	if isPlanLimitBody(body) {
		offer, _ := dig(body, "upgrade").(map[string]any)
		base.Code = "plan_limit_exceeded"
		return &PlanLimitError{APIError: base, Offer: offer, RetryAfter: retryAfterSeconds(h)}
	}
	switch {
	case status == 400 || status == 422:
		return &ValidationError{base}
	case status == 401:
		return &AuthenticationError{base}
	case status == 403:
		return &PermissionDeniedError{base}
	case status == 404:
		return &NotFoundError{base}
	case status == 409:
		return &ConflictError{base}
	case status == 429:
		return &RateLimitError{APIError: base, RetryAfter: retryAfterSeconds(h)}
	case status >= 500:
		return &ServerError{base}
	default:
		return base
	}
}

func newNetworkError(err error) *NetworkError {
	return &NetworkError{
		APIError: &APIError{Status: 0, Message: err.Error(), Code: "network_error"},
		Cause:    err,
	}
}

// decodeBody turns a response body into a generic JSON value: nil when empty,
// the decoded value when it is JSON (objects and arrays alike), otherwise the
// raw text.
func decodeBody(raw []byte) any {
	if len(strings.TrimSpace(string(raw))) == 0 {
		return nil
	}
	var v any
	if err := json.Unmarshal(raw, &v); err == nil {
		return v
	}
	return string(raw)
}

// backoff is how long to wait before retry number attempt+1: Retry-After when
// the server sent one (seconds or an HTTP date), otherwise exponential
// 250ms * 2^attempt with a little jitter. Both are capped at 60s.
func backoff(attempt int, retryAfter string, jitter func() float64) time.Duration {
	const maxWait = 60 * time.Second
	if retryAfter = strings.TrimSpace(retryAfter); retryAfter != "" {
		if secs, err := strconv.ParseFloat(retryAfter, 64); err == nil && secs >= 0 {
			d := time.Duration(secs * float64(time.Second))
			if d > maxWait {
				return maxWait
			}
			return d
		}
		if t, err := http.ParseTime(retryAfter); err == nil {
			d := time.Until(t)
			if d < 0 {
				return 0
			}
			if d > maxWait {
				return maxWait
			}
			return d
		}
	}
	if attempt > 20 {
		return maxWait
	}
	base := 250 * time.Millisecond << attempt
	d := base + time.Duration(jitter()*0.25*float64(base))
	if d > maxWait {
		return maxWait
	}
	return d
}
