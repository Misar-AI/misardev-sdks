using System.Net;
using System.Text;
using System.Text.Json.Nodes;

namespace MisarDev.Tests;

/// <summary>One request the stub saw.</summary>
public sealed record Call(string Method, string Url, Dictionary<string, string> Headers, string? Body)
{
    public JsonNode? Json => string.IsNullOrEmpty(Body) ? null : JsonNode.Parse(Body);
}

/// <summary>
/// An <see cref="HttpMessageHandler"/> that records every request and answers
/// from a queue; the last response repeats once the queue runs dry. The real
/// transport (headers, retries, error mapping, SSE parsing) runs unmodified.
/// </summary>
public sealed class StubHandler : HttpMessageHandler
{
    private readonly Queue<Func<HttpResponseMessage>> _queue;
    private Func<HttpResponseMessage> _last;

    public List<Call> Calls { get; } = new();

    public StubHandler(params Func<HttpResponseMessage>[] responses)
    {
        _queue = new Queue<Func<HttpResponseMessage>>(responses);
        _last = responses.Length > 0 ? responses[^1] : () => Stub.Json("{\"ok\":true}");
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in request.Headers) headers[h.Key] = string.Join(",", h.Value);
        string? body = null;
        if (request.Content is not null)
        {
            foreach (var h in request.Content.Headers) headers[h.Key] = string.Join(",", h.Value);
            body = await request.Content.ReadAsStringAsync(ct);
        }
        Calls.Add(new Call(request.Method.Method, request.RequestUri!.AbsoluteUri, headers, body));

        var next = _queue.Count > 0 ? _queue.Dequeue() : _last;
        return next();
    }
}

public static class Stub
{
    public const string PlanLimitBody = """
        {"error":"API access requires the Pro plan or higher.","code":"plan_limit_exceeded","requiredPlan":"pro",
         "upgrade":{"product":"dev","product_name":"Misar.Dev","reason":"feature_locked","feature":"api_access",
         "feature_label":"API access","headline":"API access isn't included in your Starter plan.","usage":null,
         "current_plan":{"slug":"starter","name":"Starter"},"recommended_plan":"pro","plans":[],"topup":null,
         "overage":null,"trial":null,"cross_sell":[],
         "urls":{"pricing":"https://www.misar.dev/pricing","billing":"https://www.misar.dev/settings/billing",
         "docs":"https://docs.misar.io/dev/api","compare":"https://www.misar.dev/pricing#compare"},
         "cta":"Upgrade to Pro to continue."}}
        """;

    public static HttpResponseMessage Json(string body, int status = 200, params (string Name, string Value)[] headers)
    {
        var res = new HttpResponseMessage((HttpStatusCode)status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        foreach (var (n, v) in headers) res.Headers.TryAddWithoutValidation(n, v);
        return res;
    }

    public static HttpResponseMessage Text(string body, int status) =>
        new((HttpStatusCode)status) { Content = new StringContent(body, Encoding.UTF8, "text/plain") };

    public static HttpResponseMessage Empty(int status) =>
        new((HttpStatusCode)status) { Content = new ByteArrayContent(Array.Empty<byte>()) };

    public static HttpResponseMessage Sse(params string[] frames) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(string.Concat(frames), Encoding.UTF8, "text/event-stream"),
        };

    public static (MisarDevClient Dev, StubHandler Handler) Client(int maxRetries = 3, params Func<HttpResponseMessage>[] responses)
    {
        var handler = new StubHandler(responses);
        var dev = new MisarDevClient("mdk_test_key", new MisarDevClientOptions
        {
            BaseUrl = "https://api.test/dev",
            MaxRetries = maxRetries,
            HttpClient = new HttpClient(handler),
        });
        return (dev, handler);
    }
}
