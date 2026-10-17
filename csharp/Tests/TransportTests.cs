using System.Text.Json.Nodes;
using Xunit;

// Some tests set process environment variables; keep them from racing.
[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace MisarDev.Tests;

public sealed class AuthenticationTests
{
    [Fact]
    public async Task SendsBearerKeyAndSdkHeaders()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Json("""{"projects":[]}"""));
        await dev.Projects.List();
        var call = Assert.Single(h.Calls);
        Assert.Equal("Bearer mdk_test_key", call.Headers["Authorization"]);
        Assert.Equal("misardev-csharp/1.0.0", call.Headers["X-Misar-SDK"]);
        Assert.Equal("application/json", call.Headers["Accept"]);
        Assert.StartsWith("application/json", call.Headers["Content-Type"]);
        Assert.Equal("https://api.test/dev/projects", call.Url);
    }

    [Fact]
    public void RefusesToConstructWithoutAKey()
    {
        var prev = Environment.GetEnvironmentVariable("MISARDEV_API_KEY");
        Environment.SetEnvironmentVariable("MISARDEV_API_KEY", null);
        try
        {
            var err = Assert.Throws<MisarDevException>(() => new MisarDevClient());
            Assert.Contains("API key is required", err.Message);
            Assert.Contains("https://www.misar.dev/settings/api-keys", err.Message);
            Assert.Throws<MisarDevException>(() => new MisarDevClient(""));
        }
        finally
        {
            Environment.SetEnvironmentVariable("MISARDEV_API_KEY", prev);
        }
    }

    [Fact]
    public async Task ReadsKeyFromEnvironmentAndDefaultsBaseUrl()
    {
        var prevKey = Environment.GetEnvironmentVariable("MISARDEV_API_KEY");
        var prevBase = Environment.GetEnvironmentVariable("MISARDEV_BASE_URL");
        Environment.SetEnvironmentVariable("MISARDEV_API_KEY", "mdk_from_env");
        Environment.SetEnvironmentVariable("MISARDEV_BASE_URL", null);
        try
        {
            var h = new StubHandler(() => Stub.Json("{}"));
            using var dev = new MisarDevClient(null, new MisarDevClientOptions { HttpClient = new HttpClient(h) });
            Assert.Equal("https://api.misar.io/dev", dev.BaseUrl);
            Assert.Equal(3, dev.MaxRetries);
            Assert.Equal(TimeSpan.FromSeconds(60), dev.Timeout);
            await dev.Usage.Plan();
            Assert.Equal("Bearer mdk_from_env", h.Calls[0].Headers["Authorization"]);
            Assert.Equal("https://api.misar.io/dev/usage/plan", h.Calls[0].Url);

            Environment.SetEnvironmentVariable("MISARDEV_BASE_URL", "https://example.test/dev/");
            using var dev2 = new MisarDevClient(null, new MisarDevClientOptions { HttpClient = new HttpClient(h) });
            Assert.Equal("https://example.test/dev", dev2.BaseUrl);
        }
        finally
        {
            Environment.SetEnvironmentVariable("MISARDEV_API_KEY", prevKey);
            Environment.SetEnvironmentVariable("MISARDEV_BASE_URL", prevBase);
        }
    }
}

public sealed class ErrorTests
{
    [Fact]
    public async Task PlanLimitCarriesTheFullOfferDetectedByCode()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Json(Stub.PlanLimitBody, 402, ("x-request-id", "req_1")));
        var err = await Assert.ThrowsAsync<PlanLimitException>(() => dev.Projects.List());
        Assert.Equal(402, err.Status);
        Assert.Equal("plan_limit_exceeded", err.Code);
        Assert.Equal("API access requires the Pro plan or higher.", err.Message);
        Assert.Equal("pro", err.Offer!["recommended_plan"]!.GetValue<string>());
        Assert.Equal("API access isn't included in your Starter plan.", err.Headline);
        Assert.Equal("Upgrade to Pro to continue.", err.Offer!["cta"]!.GetValue<string>());
        Assert.Equal("https://www.misar.dev/pricing#compare", err.Offer!["urls"]!["compare"]!.GetValue<string>());
        Assert.NotNull(err.Offer!["plans"] as JsonArray);
        Assert.Equal("https://www.misar.dev/settings/billing", err.UpgradeUrl);
        Assert.Equal("api_access", err.Feature);
        Assert.Equal("starter", err.CurrentPlan);
        Assert.Equal("pro", err.RecommendedPlan);
        Assert.Equal("feature_locked", err.Reason);
        Assert.Equal("req_1", err.RequestId);
        Assert.Single(h.Calls);
    }

    [Fact]
    public async Task NeverRetriesAQuotaExhausted429()
    {
        var body = JsonNode.Parse(Stub.PlanLimitBody)!;
        body["upgrade"]!["reason"] = "quota_exhausted";
        var (dev, h) = Stub.Client(3, () => Stub.Json(body.ToJsonString(), 429, ("Retry-After", "3600")));
        var err = await Assert.ThrowsAsync<PlanLimitException>(() => dev.Templates.List());
        Assert.Equal(429, err.Status);
        Assert.Equal(3600, err.RetryAfter);
        Assert.Equal("quota_exhausted", err.Reason);
        Assert.Single(h.Calls);
    }

    [Fact]
    public async Task RetriesAnOrdinary429OnAPostAndHonoursRetryAfter()
    {
        var (dev, h) = Stub.Client(3,
            () => Stub.Json("""{"error":"slow down"}""", 429, ("Retry-After", "0")),
            () => Stub.Json("""{"ok":1}"""));
        var res = await dev.Projects.Create(new { name = "x" });
        Assert.Equal(1, res!["ok"]!.GetValue<int>());
        Assert.Equal(2, h.Calls.Count);
    }

    [Fact]
    public async Task GivesUpOnAPersistentThrottleWithRateLimitException()
    {
        var (dev, h) = Stub.Client(2, () => Stub.Json("""{"error":"slow down"}""", 429, ("Retry-After", "0")));
        var err = await Assert.ThrowsAsync<RateLimitException>(() => dev.Projects.List());
        Assert.Equal(0, err.RetryAfter);
        Assert.Equal("slow down", err.Message);
        Assert.Equal(2, h.Calls.Count);
    }

    [Fact]
    public async Task Retries503OnGetButNotOnPost()
    {
        var get = Stub.Client(3, () => Stub.Json("""{"error":"down"}""", 503), () => Stub.Json("""{"ok":true}"""));
        var ok = await get.Dev.Projects.List();
        Assert.True(ok!["ok"]!.GetValue<bool>());
        Assert.Equal(2, get.Handler.Calls.Count);

        var post = Stub.Client(3, () => Stub.Json("""{"error":"down"}""", 503), () => Stub.Json("""{"ok":true}"""));
        var err = await Assert.ThrowsAsync<ServerException>(() => post.Dev.Projects.Create(new { }));
        Assert.Equal(503, err.Status);
        Assert.Single(post.Handler.Calls);
    }

    [Fact]
    public async Task MapsStatusesToTypedErrorsAndReadsTheOpenAiShape()
    {
        var a = Stub.Client(3, () => Stub.Json("""{"error":"Unauthorized"}""", 401));
        await Assert.ThrowsAsync<AuthenticationException>(() => a.Dev.Projects.List());

        var b = Stub.Client(3, () => Stub.Json("""{"error":"nope"}""", 404));
        await Assert.ThrowsAsync<NotFoundException>(() => b.Dev.Projects.Get("p1"));

        var c = Stub.Client(3, () => Stub.Json(
            """{"error":{"message":"bad model","type":"invalid_request_error","code":"bad_model"}}""", 400));
        var v = await Assert.ThrowsAsync<ValidationException>(() => c.Dev.Chat.Completions(new { }));
        Assert.Equal("bad model", v.Message);
        Assert.Equal("bad_model", v.Code);

        var d = Stub.Client(3, () => Stub.Json("""{"message":"taken"}""", 409));
        var conflict = await Assert.ThrowsAsync<ConflictException>(() => d.Dev.Projects.Deploy("p1"));
        Assert.Equal("taken", conflict.Message);

        var e = Stub.Client(3, () => Stub.Json("""{"error":"no"}""", 403));
        await Assert.ThrowsAsync<PermissionDeniedException>(() => e.Dev.Projects.List());

        var f = Stub.Client(3, () => Stub.Text("teapot", 418));
        var teapot = await Assert.ThrowsAsync<MisarDevException>(() => f.Dev.Projects.List());
        Assert.Equal("teapot", teapot.Message);
        Assert.Equal(418, teapot.Status);
    }

    [Fact]
    public async Task RetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkException()
    {
        var (dev, h) = Stub.Client(2, () => throw new HttpRequestException("connection reset"));
        var err = await Assert.ThrowsAsync<NetworkException>(() => dev.Projects.List());
        Assert.Equal(0, err.Status);
        Assert.Equal(2, h.Calls.Count);

        var post = Stub.Client(3, () => throw new HttpRequestException("connection reset"));
        await Assert.ThrowsAsync<NetworkException>(() => post.Dev.Projects.Create());
        Assert.Single(post.Handler.Calls);
    }
}

public sealed class RequestTests
{
    [Fact]
    public async Task EncodesPathParamsRequiredAndOptionalQueryAndBody()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Json("{}"));
        await dev.Projects.CheckSubdomain("a b/c", "my-app");
        Assert.Equal("https://api.test/dev/projects/a%20b%2Fc/subdomain/check?value=my-app", h.Calls[0].Url);

        await dev.Templates.List(query: new Dictionary<string, object?> { ["limit"] = 5, ["featured"] = true, ["category"] = null });
        Assert.Equal("https://api.test/dev/templates?limit=5&featured=true", h.Calls[1].Url);

        await dev.Templates.List(query: new { limit = 5, featured = false, category = (string?)null });
        Assert.Equal("https://api.test/dev/templates?limit=5&featured=false", h.Calls[2].Url);

        await dev.Projects.Update("p1", new { name = "New" });
        Assert.Equal("PATCH", h.Calls[3].Method);
        Assert.Equal("New", h.Calls[3].Json!["name"]!.GetValue<string>());

        await dev.Rag.Search("proj 1", new { query = "auth", stats = true });
        Assert.Equal("https://api.test/dev/rag?query=auth&stats=true&projectId=proj%201", h.Calls[4].Url);

        await dev.Projects.Create();
        Assert.Equal("{}", h.Calls[5].Body);
    }

    [Fact]
    public async Task ReturnsNullForAnEmpty204AndStringsForNonJson()
    {
        var (dev, _) = Stub.Client(3, () => Stub.Empty(204));
        Assert.Null(await dev.Projects.Delete("p1"));

        var t = Stub.Client(3, () => Stub.Text("plain text", 200));
        var res = await t.Dev.Projects.Export("p1");
        Assert.Equal("plain text", res!.GetValue<string>());

        var arr = Stub.Client(3, () => Stub.Json("[1,2,3]"));
        var list = await arr.Dev.Builds.List();
        Assert.Equal(3, list!.AsArray().Count);
    }

    [Fact]
    public async Task ExposesARawRequestEscapeHatch()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Json("""{"hi":1}"""));
        var res = await dev.RequestAsync("GET", "/usage", query: new { days = 7 });
        Assert.Equal(1, res!["hi"]!.GetValue<int>());
        Assert.Equal("https://api.test/dev/usage?days=7", h.Calls[0].Url);
    }

    [Fact]
    public void BuildsQueryStringsAndBackoffDelays()
    {
        Assert.Equal("", Transport.BuildQuery(null));
        Assert.Equal("", Transport.BuildQuery(Transport.Query(new { a = (string?)null })));
        Assert.Equal(TimeSpan.FromSeconds(2), Transport.Backoff(0, "2"));
        Assert.Equal(TimeSpan.FromSeconds(60), Transport.Backoff(0, "999"));
        Assert.True(Transport.Backoff(3, null) >= TimeSpan.FromSeconds(2));
        Assert.True(Transport.Backoff(30, null) <= TimeSpan.FromSeconds(60));
        var date = DateTimeOffset.UtcNow.AddSeconds(1).ToString("r");
        Assert.True(Transport.Backoff(0, date) <= TimeSpan.FromSeconds(1));
    }
}

public sealed class StreamingTests
{
    [Fact]
    public async Task StreamsChatCompletionsUntilDoneForcingStreamTrue()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Sse(
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            ": keep-alive\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\r\n\r\n",
            "data: [DONE]\n\n",
            "data: {\"never\":\"seen\"}\n\n"));
        var text = "";
        await foreach (var ev in dev.Chat.CompletionsStream(new
                       {
                           model = "misar-online",
                           messages = new[] { new { role = "user", content = "hi" } },
                       }))
            text += ev.Data!["choices"]![0]!["delta"]!["content"]!.GetValue<string>();

        Assert.Equal("Hello", text);
        var body = h.Calls[0].Json!;
        Assert.True(body["stream"]!.GetValue<bool>());
        Assert.Equal("misar-online", body["model"]!.GetValue<string>());
        Assert.Equal("text/event-stream", h.Calls[0].Headers["Accept"]);
        Assert.Equal("https://api.test/dev/v1/chat/completions", h.Calls[0].Url);
    }

    [Fact]
    public async Task YieldsNamedEventsMultiLineDataAndATrailingFrame()
    {
        var (dev, _) = Stub.Client(3, () => Stub.Sse(
            "event: step\nid: 1\ndata: line1\ndata: line2\n\n",
            "data: {\"done\":true}"));
        var events = new List<SseEvent>();
        await foreach (var ev in dev.Projects.BuildStream("p1")) events.Add(ev);

        Assert.Equal(2, events.Count);
        Assert.Equal("step", events[0].Event);
        Assert.Equal("1", events[0].Id);
        Assert.Equal("line1\nline2", events[0].Data!.GetValue<string>());
        Assert.True(events[1].Data!["done"]!.GetValue<bool>());
        Assert.Null(events[1].Event);
    }

    [Fact]
    public async Task RaisesAPlanLimitFrameAsPlanLimitException()
    {
        var frame = JsonNode.Parse(Stub.PlanLimitBody)!.AsObject();
        frame["type"] = "error";
        var (dev, _) = Stub.Client(3, () => Stub.Sse($"data: {frame.ToJsonString()}\n\n"));
        var err = await Assert.ThrowsAsync<PlanLimitException>(async () =>
        {
            await foreach (var _ in dev.Chat.StudioStream(new { message = "hi" })) { }
        });
        Assert.Equal("pro", err.RecommendedPlan);
    }

    [Fact]
    public async Task RaisesAnHttpErrorBeforeStreamingAndNeverRetries()
    {
        var (dev, h) = Stub.Client(3, () => Stub.Json(Stub.PlanLimitBody, 402));
        await Assert.ThrowsAsync<PlanLimitException>(async () =>
        {
            await foreach (var _ in dev.Projects.BuildStream("p1")) { }
        });

        var s = Stub.Client(3, () => Stub.Json("""{"error":"down"}""", 503));
        await Assert.ThrowsAsync<ServerException>(async () =>
        {
            await foreach (var _ in s.Dev.Projects.BuildStream("p1")) { }
        });
        Assert.Single(s.Handler.Calls);
    }
}

public sealed class PaginationTests
{
    [Fact]
    public async Task WalksOffsetPagesUntilAShortPage()
    {
        var pages = new[] { "[1,2]", "[3,4]", "[5]" };
        int n = 0;
        var seen = new List<int>();
        await foreach (var x in Pagination.Paginate((_, _) =>
                           Task.FromResult<JsonNode?>(new JsonObject { ["items"] = JsonNode.Parse(pages[n++]) }), pageSize: 2))
            seen.Add(x!.GetValue<int>());
        Assert.Equal(new[] { 1, 2, 3, 4, 5 }, seen);
    }

    [Fact]
    public async Task DrivesARealListMethodAndRespectsMaxItems()
    {
        var (dev, h) = Stub.Client(3,
            () => Stub.Json("""{"templates":[{"id":1},{"id":2}]}"""),
            () => Stub.Json("""{"templates":[{"id":3}]}"""));
        var ids = new List<int>();
        await foreach (var t in dev.Paginate((offset, limit) => dev.Templates.List(query: new { offset, limit }),
                           pageSize: 2, maxItems: 3))
            ids.Add(t!["id"]!.GetValue<int>());
        Assert.Equal(new[] { 1, 2, 3 }, ids);
        Assert.Contains("offset=2", h.Calls[1].Url);
    }
}
