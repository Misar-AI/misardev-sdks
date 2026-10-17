package misardev

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// recorded is one request the test server saw.
type recorded struct {
	Method string
	URL    string
	Header http.Header
	Body   map[string]any
}

// reply is one canned answer from the test server.
type reply struct {
	Status  int
	Headers map[string]string
	Body    string
}

func jsonReply(status int, v any, headers ...string) reply {
	b, _ := json.Marshal(v)
	h := map[string]string{"Content-Type": "application/json"}
	for i := 0; i+1 < len(headers); i += 2 {
		h[headers[i]] = headers[i+1]
	}
	return reply{Status: status, Headers: h, Body: string(b)}
}

func sseReply(frames ...string) reply {
	return reply{Status: 200, Headers: map[string]string{"Content-Type": "text/event-stream"}, Body: strings.Join(frames, "")}
}

// mock serves replies in order (the last one repeats) and records calls.
type mock struct {
	mu      sync.Mutex
	replies []reply
	calls   []recorded
	server  *httptest.Server
}

func newMock(t *testing.T, replies ...reply) *mock {
	t.Helper()
	m := &mock{replies: replies}
	m.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		if len(raw) > 0 {
			_ = json.Unmarshal(raw, &body)
		}
		m.mu.Lock()
		m.calls = append(m.calls, recorded{Method: r.Method, URL: r.URL.RequestURI(), Header: r.Header.Clone(), Body: body})
		next := reply{Status: 200, Headers: map[string]string{"Content-Type": "application/json"}, Body: `{"ok":true}`}
		if len(m.replies) > 0 {
			next = m.replies[0]
			if len(m.replies) > 1 {
				m.replies = m.replies[1:]
			}
		}
		m.mu.Unlock()
		for k, v := range next.Headers {
			w.Header().Set(k, v)
		}
		w.WriteHeader(next.Status)
		_, _ = io.WriteString(w, next.Body)
	}))
	t.Cleanup(m.server.Close)
	return m
}

func (m *mock) client(t *testing.T, opts ...Option) *Client {
	t.Helper()
	all := append([]Option{WithBaseURL(m.server.URL + "/dev"), WithHTTPClient(m.server.Client())}, opts...)
	c, err := NewClient("mdk_test_key", all...)
	if err != nil {
		t.Fatal(err)
	}
	// Retries wait for real in production; tests only record that they would.
	c.sleep = func(ctx context.Context, d time.Duration) error { return ctx.Err() }
	return c
}

var planLimitBody = map[string]any{
	"error":        "API access requires the Pro plan or higher.",
	"code":         "plan_limit_exceeded",
	"requiredPlan": "pro",
	"upgrade": map[string]any{
		"product":          "dev",
		"product_name":     "Misar.Dev",
		"reason":           "feature_locked",
		"feature":          "api_access",
		"feature_label":    "API access",
		"headline":         "API access isn't included in your Starter plan.",
		"usage":            nil,
		"current_plan":     map[string]any{"slug": "starter", "name": "Starter"},
		"recommended_plan": "pro",
		"plans":            []any{},
		"topup":            nil,
		"overage":          nil,
		"trial":            nil,
		"cross_sell":       []any{},
		"urls": map[string]any{
			"pricing": "https://www.misar.dev/pricing",
			"billing": "https://www.misar.dev/settings/billing",
			"docs":    "https://docs.misar.io/dev/api",
			"compare": "https://www.misar.dev/pricing#compare",
		},
		"cta": "Upgrade to Pro to continue.",
	},
}

var ctx = context.Background()

// ── Authentication ───────────────────────────────────────────────────────────

func TestSendsBearerAndSDKHeaders(t *testing.T) {
	m := newMock(t, jsonReply(200, map[string]any{"projects": []any{}}))
	c := m.client(t)
	if _, err := c.Projects.List(ctx, nil); err != nil {
		t.Fatal(err)
	}
	got := m.calls[0]
	if h := got.Header.Get("Authorization"); h != "Bearer mdk_test_key" {
		t.Errorf("Authorization = %q", h)
	}
	if h := got.Header.Get("X-Misar-SDK"); h != "misardev-go/"+Version {
		t.Errorf("X-Misar-SDK = %q", h)
	}
	if h := got.Header.Get("Accept"); h != "application/json" {
		t.Errorf("Accept = %q", h)
	}
	if h := got.Header.Get("Content-Type"); h != "application/json" {
		t.Errorf("Content-Type = %q", h)
	}
	if got.URL != "/dev/projects" {
		t.Errorf("URL = %q", got.URL)
	}
}

func TestDefaultsAndEnvironment(t *testing.T) {
	t.Setenv("MISARDEV_API_KEY", "")
	t.Setenv("MISARDEV_BASE_URL", "")
	_, err := NewClient("")
	if err == nil || !strings.Contains(err.Error(), "https://www.misar.dev/settings/api-keys") {
		t.Fatalf("missing key error = %v", err)
	}

	c, err := NewClient("mdk_x")
	if err != nil {
		t.Fatal(err)
	}
	if c.BaseURL() != "https://api.misar.io/dev" || c.maxRetries != 3 || c.timeout != 60*time.Second {
		t.Errorf("defaults = %q %d %s", c.BaseURL(), c.maxRetries, c.timeout)
	}

	m := newMock(t)
	t.Setenv("MISARDEV_API_KEY", "mdk_from_env")
	t.Setenv("MISARDEV_BASE_URL", m.server.URL+"/env/")
	c, err = NewClient("", WithHTTPClient(m.server.Client()))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.Usage.Plan(ctx); err != nil {
		t.Fatal(err)
	}
	if h := m.calls[0].Header.Get("Authorization"); h != "Bearer mdk_from_env" {
		t.Errorf("Authorization = %q", h)
	}
	if m.calls[0].URL != "/env/usage/plan" {
		t.Errorf("URL = %q", m.calls[0].URL)
	}
}

// ── Errors and retries ───────────────────────────────────────────────────────

func TestPlanLimitErrorCarriesOffer(t *testing.T) {
	m := newMock(t, jsonReply(402, planLimitBody, "X-Request-Id", "req_1"))
	_, err := m.client(t).Projects.List(ctx, nil)

	var plan *PlanLimitError
	if !errors.As(err, &plan) {
		t.Fatalf("err = %T %v", err, err)
	}
	if plan.Status != 402 || plan.Code != "plan_limit_exceeded" || plan.RequestID != "req_1" {
		t.Errorf("plan = %+v", plan.APIError)
	}
	if plan.Message != "API access requires the Pro plan or higher." {
		t.Errorf("message = %q", plan.Message)
	}
	if plan.UpgradeURL() != "https://www.misar.dev/settings/billing" {
		t.Errorf("UpgradeURL = %q", plan.UpgradeURL())
	}
	if plan.Feature() != "api_access" || plan.CurrentPlan() != "starter" || plan.RecommendedPlan() != "pro" {
		t.Errorf("accessors = %q %q %q", plan.Feature(), plan.CurrentPlan(), plan.RecommendedPlan())
	}
	if plan.Offer["cta"] != "Upgrade to Pro to continue." || plan.Offer["product_name"] != "Misar.Dev" {
		t.Errorf("offer lost fields: %v", plan.Offer)
	}
	if _, ok := plan.Offer["cross_sell"]; !ok {
		t.Error("offer dropped cross_sell")
	}
	var base *APIError
	if !errors.As(err, &base) || base.Status != 402 {
		t.Error("PlanLimitError does not unwrap to *APIError")
	}
	if len(m.calls) != 1 {
		t.Errorf("calls = %d, want 1", len(m.calls))
	}
}

func TestQuotaPlanLimit429IsNotRetried(t *testing.T) {
	body := map[string]any{}
	for k, v := range planLimitBody {
		body[k] = v
	}
	upgrade := map[string]any{}
	for k, v := range planLimitBody["upgrade"].(map[string]any) {
		upgrade[k] = v
	}
	upgrade["reason"] = "quota_exhausted"
	body["upgrade"] = upgrade

	m := newMock(t, jsonReply(429, body, "Retry-After", "3600"))
	_, err := m.client(t).Templates.List(ctx, nil)
	var plan *PlanLimitError
	if !errors.As(err, &plan) {
		t.Fatalf("err = %T %v", err, err)
	}
	if plan.RetryAfter != 3600 || plan.Reason() != "quota_exhausted" || plan.Status != 429 {
		t.Errorf("plan = %d %q %d", plan.RetryAfter, plan.Reason(), plan.Status)
	}
	var rl *RateLimitError
	if errors.As(err, &rl) {
		t.Error("plan limit must not be a RateLimitError")
	}
	if len(m.calls) != 1 {
		t.Errorf("calls = %d, want 1", len(m.calls))
	}
}

func TestOrdinary429IsRetriedForAnyVerb(t *testing.T) {
	m := newMock(t,
		jsonReply(429, map[string]any{"error": "slow down"}, "Retry-After", "0"),
		jsonReply(200, map[string]any{"ok": 1}),
	)
	c := m.client(t)
	var waits []time.Duration
	c.sleep = func(ctx context.Context, d time.Duration) error { waits = append(waits, d); return nil }
	out, err := c.Projects.Create(ctx, Body{"name": "x"})
	if err != nil {
		t.Fatal(err)
	}
	if out.(map[string]any)["ok"] != float64(1) {
		t.Errorf("out = %v", out)
	}
	if len(m.calls) != 2 || m.calls[0].Method != "POST" {
		t.Errorf("calls = %d", len(m.calls))
	}
	if len(waits) != 1 || waits[0] != 0 {
		t.Errorf("waits = %v, want [0] (Retry-After honoured)", waits)
	}
}

func TestPersistent429RaisesRateLimitError(t *testing.T) {
	m := newMock(t, jsonReply(429, map[string]any{"error": "slow down"}, "Retry-After", "0"))
	_, err := m.client(t, WithMaxRetries(2)).Projects.List(ctx, nil)
	var rl *RateLimitError
	if !errors.As(err, &rl) {
		t.Fatalf("err = %T %v", err, err)
	}
	if rl.RetryAfter != 0 || rl.Message != "slow down" {
		t.Errorf("rl = %d %q", rl.RetryAfter, rl.Message)
	}
	if len(m.calls) != 2 {
		t.Errorf("calls = %d, want 2", len(m.calls))
	}
}

func Test503RetriedOnGetNotOnPost(t *testing.T) {
	get := newMock(t, jsonReply(503, map[string]any{"error": "down"}), jsonReply(200, map[string]any{"ok": true}))
	if _, err := get.client(t).Projects.List(ctx, nil); err != nil {
		t.Fatal(err)
	}
	if len(get.calls) != 2 {
		t.Errorf("GET calls = %d, want 2", len(get.calls))
	}

	post := newMock(t, jsonReply(503, map[string]any{"error": "down"}), jsonReply(200, map[string]any{"ok": true}))
	_, err := post.client(t).Projects.Create(ctx, Body{})
	var se *ServerError
	if !errors.As(err, &se) || se.Status != 503 {
		t.Fatalf("err = %T %v", err, err)
	}
	if len(post.calls) != 1 {
		t.Errorf("POST calls = %d, want 1", len(post.calls))
	}
}

func TestStatusMapping(t *testing.T) {
	cases := []struct {
		reply reply
		check func(error) bool
	}{
		{jsonReply(401, map[string]any{"error": "Unauthorized"}), func(e error) bool { var x *AuthenticationError; return errors.As(e, &x) }},
		{jsonReply(403, map[string]any{"error": "no"}), func(e error) bool { var x *PermissionDeniedError; return errors.As(e, &x) }},
		{jsonReply(404, map[string]any{"error": "nope"}), func(e error) bool { var x *NotFoundError; return errors.As(e, &x) }},
		{jsonReply(409, map[string]any{"message": "busy"}), func(e error) bool { var x *ConflictError; return errors.As(e, &x) && x.Message == "busy" }},
		{jsonReply(422, map[string]any{"error": "bad"}), func(e error) bool { var x *ValidationError; return errors.As(e, &x) }},
	}
	for i, tc := range cases {
		m := newMock(t, tc.reply)
		_, err := m.client(t).Projects.Get(ctx, "p1")
		if !tc.check(err) {
			t.Errorf("case %d: err = %T %v", i, err, err)
		}
	}

	m := newMock(t, jsonReply(400, map[string]any{"error": map[string]any{"message": "bad model", "type": "invalid_request_error", "code": "bad_model"}}))
	_, err := m.client(t).Chat.Completions(ctx, Body{})
	var ve *ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("err = %T %v", err, err)
	}
	if ve.Message != "bad model" || ve.Code != "bad_model" {
		t.Errorf("ve = %q %q", ve.Message, ve.Code)
	}

	tea := newMock(t, reply{Status: 418, Body: "teapot"})
	_, err = tea.client(t).Projects.List(ctx, nil)
	var base *APIError
	if !errors.As(err, &base) || base.Message != "teapot" || base.Status != 418 {
		t.Fatalf("err = %T %v", err, err)
	}
}

func TestNetworkErrorsRetriedForIdempotentCalls(t *testing.T) {
	var attempts int
	failing := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		attempts++
		return nil, errors.New("connection reset")
	})}
	c, err := NewClient("mdk_test_key", WithBaseURL("https://api.test/dev"), WithHTTPClient(failing), WithMaxRetries(2))
	if err != nil {
		t.Fatal(err)
	}
	c.sleep = func(context.Context, time.Duration) error { return nil }

	_, err = c.Projects.List(ctx, nil)
	var ne *NetworkError
	if !errors.As(err, &ne) || ne.Status != 0 {
		t.Fatalf("err = %T %v", err, err)
	}
	if attempts != 2 {
		t.Errorf("GET attempts = %d, want 2", attempts)
	}

	attempts = 0
	_, err = c.Projects.Create(ctx, Body{})
	if !errors.As(err, &ne) || attempts != 1 {
		t.Errorf("POST attempts = %d, err = %v", attempts, err)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// ── Requests ─────────────────────────────────────────────────────────────────

func TestEncodesPathQueryAndBody(t *testing.T) {
	m := newMock(t)
	c := m.client(t)

	if _, err := c.Projects.CheckSubdomain(ctx, "a b/c", "my-app"); err != nil {
		t.Fatal(err)
	}
	if m.calls[0].URL != "/dev/projects/a%20b%2Fc/subdomain/check?value=my-app" {
		t.Errorf("URL = %q", m.calls[0].URL)
	}

	if _, err := c.Templates.List(ctx, Query{"limit": 5, "featured": true, "category": nil}); err != nil {
		t.Fatal(err)
	}
	if m.calls[1].URL != "/dev/templates?featured=true&limit=5" {
		t.Errorf("URL = %q", m.calls[1].URL)
	}

	if _, err := c.Projects.Update(ctx, "p1", Body{"name": "New"}); err != nil {
		t.Fatal(err)
	}
	if m.calls[2].Method != "PATCH" || m.calls[2].Body["name"] != "New" {
		t.Errorf("call = %+v", m.calls[2])
	}

	if _, err := c.Domains.Lookup(ctx, "example.com"); err != nil {
		t.Fatal(err)
	}
	if m.calls[3].URL != "/dev/domains/lookup?domain=example.com" {
		t.Errorf("URL = %q", m.calls[3].URL)
	}
}

func TestDecodesSuccessBodies(t *testing.T) {
	m := newMock(t,
		reply{Status: 204},
		jsonReply(200, []any{1, 2}),
		reply{Status: 200, Body: "plain text"},
	)
	c := m.client(t)
	if out, err := c.Projects.Delete(ctx, "p1"); err != nil || out != nil {
		t.Errorf("204 → %v %v", out, err)
	}
	out, err := c.Builds.List(ctx, nil)
	if arr, ok := out.([]any); err != nil || !ok || len(arr) != 2 {
		t.Errorf("array → %v %v", out, err)
	}
	if out, err := c.Audit.List(ctx); err != nil || out != "plain text" {
		t.Errorf("text → %v %v", out, err)
	}
}

func TestRawRequestAndAs(t *testing.T) {
	m := newMock(t, jsonReply(200, map[string]any{"hi": 1}))
	out, err := m.client(t).Request(ctx, "GET", "/usage", Query{"days": 7}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if m.calls[0].URL != "/dev/usage?days=7" {
		t.Errorf("URL = %q", m.calls[0].URL)
	}
	typed, err := As[struct{ Hi int }](out)
	if err != nil || typed.Hi != 1 {
		t.Errorf("As = %+v %v", typed, err)
	}
}

func TestQueryAndBackoffHelpers(t *testing.T) {
	if buildQuery(nil) != "" || buildQuery(Query{"a": nil}) != "" {
		t.Error("nil query values must be dropped")
	}
	if got := buildQuery(Query{"b": false, "a": "x y"}); got != "?a=x+y&b=false" {
		t.Errorf("buildQuery = %q", got)
	}
	zero := func() float64 { return 0 }
	if backoff(0, "2", zero) != 2*time.Second {
		t.Error("Retry-After seconds not honoured")
	}
	if backoff(0, "999", zero) != 60*time.Second {
		t.Error("Retry-After not capped at 60s")
	}
	if backoff(3, "", zero) != 2*time.Second {
		t.Errorf("exponential = %s", backoff(3, "", zero))
	}
	if backoff(30, "", zero) != 60*time.Second {
		t.Error("exponential not capped")
	}
	date := time.Now().Add(time.Second).UTC().Format(http.TimeFormat)
	if d := backoff(0, date, zero); d > time.Second || d < 0 {
		t.Errorf("HTTP-date Retry-After = %s", d)
	}
}

// ── Streaming ────────────────────────────────────────────────────────────────

func TestCompletionsStreamStopsAtDone(t *testing.T) {
	m := newMock(t, sseReply(
		"data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
		": keep-alive\n\n",
		"data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\r\n\r\n",
		"data: [DONE]\n\n",
		"data: {\"never\":\"seen\"}\n\n",
	))
	s, err := m.client(t).Chat.CompletionsStream(ctx, Body{"model": "misar-online", "messages": []any{map[string]any{"role": "user", "content": "hi"}}})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	var text strings.Builder
	for s.Next() {
		data := s.Event().Data.(map[string]any)
		delta := data["choices"].([]any)[0].(map[string]any)["delta"].(map[string]any)
		text.WriteString(delta["content"].(string))
	}
	if err := s.Err(); err != nil {
		t.Fatal(err)
	}
	if text.String() != "Hello" {
		t.Errorf("text = %q", text.String())
	}
	call := m.calls[0]
	if call.Body["stream"] != true || call.Body["model"] != "misar-online" {
		t.Errorf("body = %v", call.Body)
	}
	if call.Header.Get("Accept") != "text/event-stream" {
		t.Errorf("Accept = %q", call.Header.Get("Accept"))
	}
}

func TestStreamNamedEventsMultilineAndTrailingFrame(t *testing.T) {
	m := newMock(t, sseReply("event: step\nid: 1\ndata: line1\ndata: line2\n\n", `data: {"done":true}`))
	s, err := m.client(t).Projects.BuildStream(ctx, "p1")
	if err != nil {
		t.Fatal(err)
	}
	var events []SSEEvent
	for s.Next() {
		events = append(events, s.Event())
	}
	if err := s.Err(); err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 {
		t.Fatalf("events = %+v", events)
	}
	if events[0] != (SSEEvent{Event: "step", ID: "1", Data: "line1\nline2"}) {
		t.Errorf("first = %+v", events[0])
	}
	if events[1].Data.(map[string]any)["done"] != true {
		t.Errorf("second = %+v", events[1])
	}
	if m.calls[0].URL != "/dev/projects/p1/build-stream" || m.calls[0].Method != "GET" {
		t.Errorf("call = %+v", m.calls[0])
	}
}

func TestStreamPlanLimitFrameAndHTTPError(t *testing.T) {
	frame := map[string]any{"type": "error"}
	for k, v := range planLimitBody {
		frame[k] = v
	}
	b, _ := json.Marshal(frame)
	m := newMock(t, sseReply("data: "+string(b)+"\n\n"))
	s, err := m.client(t).Chat.StudioStream(ctx, Body{"message": "hi"})
	if err != nil {
		t.Fatal(err)
	}
	if s.Next() {
		t.Fatal("plan-limit frame must not be yielded")
	}
	var plan *PlanLimitError
	if !errors.As(s.Err(), &plan) || plan.RecommendedPlan() != "pro" {
		t.Fatalf("err = %T %v", s.Err(), s.Err())
	}

	h := newMock(t, jsonReply(402, planLimitBody))
	_, err = h.client(t).Projects.BuildStream(ctx, "p1")
	if !errors.As(err, &plan) {
		t.Fatalf("err = %T %v", err, err)
	}
	if len(h.calls) != 1 {
		t.Errorf("stream retried: %d calls", len(h.calls))
	}
}

// ── Pagination ───────────────────────────────────────────────────────────────

func TestPaginateWalksPages(t *testing.T) {
	pages := [][]any{{1, 2}, {3, 4}, {5}}
	n := 0
	p := Paginate(ctx, func(ctx context.Context, offset, limit int) (any, error) {
		page := map[string]any{"items": pages[n]}
		n++
		return page, nil
	}, PaginateOptions{PageSize: 2})
	var seen []any
	for p.Next() {
		seen = append(seen, p.Item())
	}
	if p.Err() != nil || fmt.Sprint(seen) != "[1 2 3 4 5]" {
		t.Errorf("seen = %v err = %v", seen, p.Err())
	}
}

func TestPaginateThroughClientRespectsMaxItems(t *testing.T) {
	m := newMock(t,
		jsonReply(200, map[string]any{"templates": []any{map[string]any{"id": 1}, map[string]any{"id": 2}}}),
		jsonReply(200, map[string]any{"templates": []any{map[string]any{"id": 3}, map[string]any{"id": 4}}}),
	)
	c := m.client(t)
	p := Paginate(ctx, func(ctx context.Context, offset, limit int) (any, error) {
		return c.Templates.List(ctx, Query{"offset": offset, "limit": limit})
	}, PaginateOptions{PageSize: 2, MaxItems: 3})
	var ids []any
	for p.Next() {
		ids = append(ids, p.Item().(map[string]any)["id"])
	}
	if fmt.Sprint(ids) != "[1 2 3]" {
		t.Errorf("ids = %v", ids)
	}
	if !strings.Contains(m.calls[1].URL, "offset=2") {
		t.Errorf("second page URL = %q", m.calls[1].URL)
	}
}

// ── Every manifest operation ─────────────────────────────────────────────────

func TestGeneratedOperationsCoverManifest(t *testing.T) {
	if got := len(generatedOperations) + len(generatedStreamOperations); got != OperationCount {
		t.Fatalf("table has %d operations, OperationCount = %d", got, OperationCount)
	}
	// In the monorepo the manifest sits two directories up; in the public
	// mirror it may not exist, and the generated table is the source of truth.
	raw, err := os.ReadFile(filepath.Join("..", "..", "manifest.json"))
	if err != nil {
		t.Skip("sdks/manifest.json not present: ", err)
	}
	var manifest struct {
		Resources map[string]struct {
			Methods []struct{ Name, Verb, Path string } `json:"methods"`
		} `json:"resources"`
		Streams struct {
			SSE []struct{ Name, Resource, Verb, Path string } `json:"sse"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(raw, &manifest); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{}
	for r, def := range manifest.Resources {
		for _, m := range def.Methods {
			want[r+"."+m.Name] = m.Verb
		}
	}
	for _, s := range manifest.Streams.SSE {
		want[s.Resource+"."+s.Name] = s.Verb
	}
	have := map[string]string{}
	for _, op := range generatedOperations {
		have[op.name] = op.verb
	}
	for _, op := range generatedStreamOperations {
		have[op.name] = op.verb
	}
	if len(want) != len(have) {
		t.Errorf("manifest has %d operations, client has %d", len(want), len(have))
	}
	for name, verb := range want {
		if have[name] != verb {
			t.Errorf("%s: manifest %s, client %q", name, verb, have[name])
		}
	}
}

func TestEveryGeneratedMethodBuildsItsRoute(t *testing.T) {
	for _, op := range generatedOperations {
		t.Run(op.name, func(t *testing.T) {
			m := newMock(t)
			if _, err := op.call(ctx, m.client(t)); err != nil {
				t.Fatal(err)
			}
			got := m.calls[0]
			if got.Method != op.verb {
				t.Errorf("verb = %s, want %s", got.Method, op.verb)
			}
			if got.URL != "/dev"+op.url {
				t.Errorf("URL = %s, want /dev%s", got.URL, op.url)
			}
			if op.hasBody && got.Body["probe"] != true {
				t.Errorf("body = %v, want probe", got.Body)
			}
		})
	}
}

func TestEveryGeneratedStreamBuildsItsRoute(t *testing.T) {
	for _, op := range generatedStreamOperations {
		t.Run(op.name, func(t *testing.T) {
			m := newMock(t, sseReply("data: {\"x\":1}\n\n"))
			s, err := op.call(ctx, m.client(t))
			if err != nil {
				t.Fatal(err)
			}
			n := 0
			for s.Next() {
				n++
			}
			if s.Err() != nil || n != 1 {
				t.Errorf("events = %d err = %v", n, s.Err())
			}
			got := m.calls[0]
			if got.Method != op.verb || got.URL != "/dev"+op.url {
				t.Errorf("call = %s %s, want %s /dev%s", got.Method, got.URL, op.verb, op.url)
			}
			if op.hasBody && got.Body["probe"] != true {
				t.Errorf("body = %v, want probe", got.Body)
			}
		})
	}
}
