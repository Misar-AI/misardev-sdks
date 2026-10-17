// Package misardev is the Go client for the MisarDev API at
// https://api.misar.io/dev: create projects, write files, build and deploy,
// start from templates, run OpenAI-compatible chat completions, search code,
// and read usage and plan allowances.
//
// One [Client] reaches every resource as an exported field — c.Projects,
// c.Templates, c.Chat, c.Usage and the rest — and every method takes a
// context.Context first. Calls authenticate with an account API key (mdk_…)
// sent as Authorization: Bearer. Throttles are retried honouring Retry-After;
// a plan refusal is typed as [*PlanLimitError] carrying the server's upgrade
// offer and is never retried. Three endpoints stream Server-Sent Events and
// return a [*Stream].
package misardev

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	// DefaultBaseURL is where the client sends requests unless told otherwise.
	DefaultBaseURL = "https://api.misar.io/dev"
	// Version is this SDK's release, sent in the X-Misar-SDK header.
	Version = "1.0.0"

	defaultMaxRetries = 3
	defaultTimeout    = 60 * time.Second
	apiKeysURL        = "https://www.misar.dev/settings/api-keys"
)

// Query holds query-string parameters. Nil values are dropped and booleans
// are sent as true/false.
type Query map[string]any

// Body is a JSON request body.
type Body = map[string]any

// statuses worth retrying. A 429 is retried for any verb; the 5xx ones only
// for verbs that are safe to repeat.
var retryable = map[int]bool{429: true, 500: true, 502: true, 503: true, 504: true}

// idempotent verbs. A 5xx or a dropped connection on a POST may already have
// done its work — started a build, charged an allowance — so only these are
// retried on those failures. A 429 is always safe: the server refused it
// before doing anything.
var idempotent = map[string]bool{"GET": true, "HEAD": true, "OPTIONS": true, "PUT": true, "DELETE": true}

// Option configures a [Client].
type Option func(*Client)

// WithBaseURL overrides the API base URL (default https://api.misar.io/dev,
// or MISARDEV_BASE_URL when set).
func WithBaseURL(u string) Option {
	return func(c *Client) { c.baseURL = strings.TrimRight(u, "/") }
}

// WithMaxRetries sets the total number of attempts for a retryable failure
// (default 3; values below 1 mean 1).
func WithMaxRetries(n int) Option { return func(c *Client) { c.maxRetries = n } }

// WithTimeout sets the per-attempt timeout for ordinary requests (default
// 60s). Streams are bounded only by the context.
func WithTimeout(d time.Duration) Option { return func(c *Client) { c.timeout = d } }

// WithHTTPClient injects the *http.Client used for every request — for tests,
// proxies or custom transports.
func WithHTTPClient(h *http.Client) Option { return func(c *Client) { c.http = h } }

// WithHeader adds a header sent with every request.
func WithHeader(key, value string) Option {
	return func(c *Client) { c.headers.Set(key, value) }
}

// CallOption tweaks a single call.
type CallOption func(*callConfig)

type callConfig struct{ headers http.Header }

// WithCallHeader adds a header to one call only.
func WithCallHeader(key, value string) CallOption {
	return func(cc *callConfig) {
		if cc.headers == nil {
			cc.headers = http.Header{}
		}
		cc.headers.Set(key, value)
	}
}

// Client is the MisarDev API client. It is safe for concurrent use.
type Client struct {
	resources

	apiKey     string
	baseURL    string
	maxRetries int
	timeout    time.Duration
	http       *http.Client
	headers    http.Header

	// sleep waits between retries; replaceable in tests.
	sleep func(ctx context.Context, d time.Duration) error
}

// NewClient builds a client. An empty apiKey falls back to the
// MISARDEV_API_KEY environment variable; if that is empty too, NewClient
// returns an error.
func NewClient(apiKey string, opts ...Option) (*Client, error) {
	if apiKey == "" {
		apiKey = os.Getenv("MISARDEV_API_KEY")
	}
	if apiKey == "" {
		return nil, &APIError{
			Status: 0,
			Code:   "missing_api_key",
			Message: "a MisarDev API key is required: pass it to NewClient or set MISARDEV_API_KEY. " +
				"Create one at " + apiKeysURL,
		}
	}
	base := os.Getenv("MISARDEV_BASE_URL")
	if base == "" {
		base = DefaultBaseURL
	}
	c := &Client{
		apiKey:     apiKey,
		baseURL:    strings.TrimRight(base, "/"),
		maxRetries: defaultMaxRetries,
		timeout:    defaultTimeout,
		http:       &http.Client{},
		headers:    http.Header{},
		sleep:      sleepCtx,
	}
	for _, o := range opts {
		o(c)
	}
	if c.maxRetries < 1 {
		c.maxRetries = 1
	}
	if c.http == nil {
		c.http = &http.Client{}
	}
	c.resources = newResources(c)
	return c, nil
}

// BaseURL is the base every request path is appended to.
func (c *Client) BaseURL() string { return c.baseURL }

func sleepCtx(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// buildQuery renders q as a query string (with its leading "?"), dropping
// nil values. Keys are sorted, so the output is stable.
func buildQuery(q Query) string {
	if len(q) == 0 {
		return ""
	}
	keys := make([]string, 0, len(q))
	for k, v := range q {
		if v == nil {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)
	vals := url.Values{}
	for _, k := range keys {
		s, ok := queryString(q[k])
		if !ok {
			continue
		}
		vals.Add(k, s)
	}
	if enc := vals.Encode(); enc != "" {
		return "?" + enc
	}
	return ""
}

func queryString(v any) (string, bool) {
	switch x := v.(type) {
	case nil:
		return "", false
	case string:
		return x, true
	case *string:
		if x == nil {
			return "", false
		}
		return *x, true
	case bool:
		return strconv.FormatBool(x), true
	case *bool:
		if x == nil {
			return "", false
		}
		return strconv.FormatBool(*x), true
	case int:
		return strconv.Itoa(x), true
	case *int:
		if x == nil {
			return "", false
		}
		return strconv.Itoa(*x), true
	case int64:
		return strconv.FormatInt(x, 10), true
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64), true
	case json.Number:
		return x.String(), true
	default:
		b, err := json.Marshal(x)
		if err != nil {
			return "", false
		}
		return strings.Trim(string(b), `"`), true
	}
}

// mergeQuery layers required query parameters over the caller's optional ones.
func mergeQuery(optional Query, required Query) Query {
	out := Query{}
	for k, v := range optional {
		out[k] = v
	}
	for k, v := range required {
		out[k] = v
	}
	return out
}

// orEmpty sends `{}` for a method that takes a body when the caller passed nil.
func orEmpty(b Body) Body {
	if b == nil {
		return Body{}
	}
	return b
}

// withStream copies b and sets "stream": true, for chat completions.
func withStream(b Body) Body {
	out := Body{}
	for k, v := range b {
		out[k] = v
	}
	out["stream"] = true
	return out
}

func (c *Client) newRequest(ctx context.Context, method, fullURL string, body any, accept string, opts []CallOption) (*http.Request, error) {
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, fullURL, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Accept", accept)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Misar-SDK", "misardev-go/"+Version)
	for k, vs := range c.headers {
		req.Header[k] = vs
	}
	cc := callConfig{}
	for _, o := range opts {
		if o != nil {
			o(&cc)
		}
	}
	for k, vs := range cc.headers {
		req.Header[k] = vs
	}
	return req, nil
}

// Request sends one call to path (relative to the base URL) and returns the
// decoded JSON: a map[string]any, a []any, a scalar, nil for an empty or 204
// answer, or the raw text when the body is not JSON. It is the escape hatch
// under every generated method.
//
// Throttles (429) are retried for any verb; 500/502/503/504 and network
// errors only for GET, HEAD, OPTIONS, PUT and DELETE. A plan-limit refusal is
// returned at once as *PlanLimitError and never retried.
func (c *Client) Request(ctx context.Context, method, path string, query Query, body any, opts ...CallOption) (any, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	verb := strings.ToUpper(method)
	fullURL := c.baseURL + path + buildQuery(query)

	for attempt := 0; ; attempt++ {
		last := attempt >= c.maxRetries-1
		status, header, reason, raw, err := c.attempt(ctx, verb, fullURL, body, opts)
		if err != nil {
			if ctx.Err() != nil {
				return nil, newNetworkError(ctx.Err())
			}
			if !last && idempotent[verb] {
				if serr := c.sleep(ctx, backoff(attempt, "", rand.Float64)); serr != nil {
					return nil, newNetworkError(serr)
				}
				continue
			}
			return nil, newNetworkError(err)
		}

		decoded := decodeBody(raw)
		if status >= 200 && status < 300 {
			if status == http.StatusNoContent {
				return nil, nil
			}
			return decoded, nil
		}

		// Read the body BEFORE deciding to retry: a 429 from the rate limiter
		// and a 429 from a spent plan allowance share a status, and only the
		// first is worth retrying.
		apiErr := errorFor(status, header, decoded, reason)
		var plan *PlanLimitError
		if errors.As(apiErr, &plan) {
			return nil, apiErr
		}
		if retryable[status] && (status == 429 || idempotent[verb]) && !last {
			if serr := c.sleep(ctx, backoff(attempt, header.Get("Retry-After"), rand.Float64)); serr != nil {
				return nil, newNetworkError(serr)
			}
			continue
		}
		return nil, apiErr
	}
}

// attempt performs one HTTP round trip and reads the whole body inside the
// per-attempt timeout.
func (c *Client) attempt(ctx context.Context, verb, fullURL string, body any, opts []CallOption) (int, http.Header, string, []byte, error) {
	actx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()
	req, err := c.newRequest(actx, verb, fullURL, body, "application/json", opts)
	if err != nil {
		return 0, nil, "", nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, nil, "", nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, nil, "", nil, err
	}
	return resp.StatusCode, resp.Header, statusReason(resp), raw, nil
}

func statusReason(resp *http.Response) string {
	if t := http.StatusText(resp.StatusCode); t != "" {
		return t
	}
	return resp.Status
}

// StreamOptions configures [Client.Stream].
type StreamOptions struct {
	// Terminator is the data payload that ends the stream without being
	// yielded ("[DONE]" for chat completions). Empty reads to EOF.
	Terminator string
}

// Stream opens a Server-Sent Events stream. It is never retried: a stream that
// failed mid-flight cannot be replayed without duplicating what the caller
// already consumed. A non-2xx answer is returned as the usual typed error.
func (c *Client) Stream(ctx context.Context, method, path string, query Query, body any, so StreamOptions, opts ...CallOption) (*Stream, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	fullURL := c.baseURL + path + buildQuery(query)
	req, err := c.newRequest(ctx, strings.ToUpper(method), fullURL, body, "text/event-stream", opts)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, newNetworkError(err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		raw, _ := io.ReadAll(resp.Body)
		return nil, errorFor(resp.StatusCode, resp.Header, decodeBody(raw), statusReason(resp))
	}
	return newStream(resp, so.Terminator), nil
}

// As converts a decoded JSON value (what every method returns) into a typed
// value by round-tripping it through encoding/json.
//
//	project, err := misardev.As[MyProject](raw)
func As[T any](v any) (T, error) {
	var out T
	b, err := json.Marshal(v)
	if err != nil {
		return out, err
	}
	err = json.Unmarshal(b, &out)
	return out, err
}
