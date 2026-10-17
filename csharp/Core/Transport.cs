using System.Globalization;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace MisarDev;

/// <summary>
/// HTTP transport shared by the generated resource layer.
/// </summary>
/// <remarks>
/// Everything the SDK does goes through here, and it authenticates exactly one
/// way: the account API key (<c>mdk_…</c>), sent as <c>Authorization: Bearer</c>.
/// What a key may do — and how much of it — is decided server-side from the
/// subscription behind that key; the SDK carries the key and surfaces the answer.
/// </remarks>
internal sealed class Transport
{
    public const string DefaultBaseUrl = "https://api.misar.io/dev";
    public const string SdkVersion = "1.0.0";
    public const string SdkHeader = "misardev-csharp/" + SdkVersion;

    /// <summary>Statuses worth retrying. 429 only when it is NOT a plan limit.</summary>
    private static readonly HashSet<int> Retryable = new() { 429, 500, 502, 503, 504 };

    /// <summary>
    /// A 5xx or a dropped connection on a POST may already have done its work —
    /// started a build, charged an allowance. Only requests that are safe to
    /// repeat are retried on those; a 429 is always safe because the server
    /// refused it before doing anything.
    /// </summary>
    private static readonly HashSet<string> Idempotent = new(StringComparer.Ordinal)
        { "GET", "HEAD", "OPTIONS", "PUT", "DELETE" };

    private static readonly TimeSpan MaxBackoff = TimeSpan.FromSeconds(60);

    private readonly string _apiKey;
    private readonly HttpClient _http;
    private readonly IReadOnlyDictionary<string, string> _extraHeaders;

    public string BaseUrl { get; }
    public int MaxRetries { get; }
    public TimeSpan Timeout { get; }

    public Transport(string apiKey, string baseUrl, int maxRetries, TimeSpan timeout, HttpClient http,
        IReadOnlyDictionary<string, string>? headers)
    {
        _apiKey = apiKey;
        BaseUrl = baseUrl.TrimEnd('/');
        MaxRetries = Math.Max(1, maxRetries);
        Timeout = timeout;
        _http = http;
        _extraHeaders = headers ?? new Dictionary<string, string>();
    }

    // ── Helpers used by the generated layer ────────────────────────────────

    /// <summary>Path-segment encoding: <c>a b/c</c> → <c>a%20b%2Fc</c>.</summary>
    public static string EncodePath(string value) => Uri.EscapeDataString(value);

    /// <summary>The body sent when a method that takes one is called without it.</summary>
    public static JsonObject EmptyBody() => new();

    /// <summary>Copy a caller's body and set <c>"stream": true</c> on it (chat completions).</summary>
    public static JsonObject WithStreamFlag(object? body)
    {
        var obj = body is null ? new JsonObject() : ToObject(body, "body");
        obj["stream"] = true;
        return obj;
    }

    /// <summary>Merge optional query params (anonymous object or dictionary) with required ones.</summary>
    public static List<KeyValuePair<string, object?>> Query(object? optional, params (string Name, object? Value)[] required)
    {
        var list = new List<KeyValuePair<string, object?>>();
        if (optional is not null)
        {
            if (optional is IEnumerable<KeyValuePair<string, object?>> pairs)
            {
                list.AddRange(pairs);
            }
            else
            {
                foreach (var (k, v) in ToObject(optional, "query"))
                    list.Add(new(k, v));
            }
        }
        foreach (var (name, value) in required)
        {
            list.RemoveAll(p => p.Key == name);
            list.Add(new(name, value));
        }
        return list;
    }

    private static JsonObject ToObject(object value, string what)
    {
        if (value is JsonObject jo) return (JsonObject)jo.DeepClone();
        var node = JsonSerializer.SerializeToNode(value);
        return node as JsonObject
            ?? throw new ArgumentException($"{what} must serialize to a JSON object", what);
    }

    /// <summary>Render <c>?a=b&amp;c=d</c>: nulls dropped, booleans lowercase, everything URL-encoded.</summary>
    public static string BuildQuery(IEnumerable<KeyValuePair<string, object?>>? query)
    {
        if (query is null) return "";
        var parts = new List<string>();
        foreach (var (key, value) in query)
        {
            string? s = Stringify(value);
            if (s is null) continue;
            parts.Add($"{Uri.EscapeDataString(key)}={Uri.EscapeDataString(s)}");
        }
        return parts.Count == 0 ? "" : "?" + string.Join("&", parts);
    }

    private static string? Stringify(object? value)
    {
        switch (value)
        {
            case null: return null;
            case bool b: return b ? "true" : "false";
            case string s: return s;
            case JsonValue jv:
                if (jv.GetValueKind() == JsonValueKind.Null) return null;
                if (jv.TryGetValue<string>(out var str)) return str;
                if (jv.GetValueKind() is JsonValueKind.True or JsonValueKind.False)
                    return jv.GetValueKind() == JsonValueKind.True ? "true" : "false";
                return jv.ToJsonString();
            case JsonNode node: return node.ToJsonString();
            case JsonElement el:
                return el.ValueKind switch
                {
                    JsonValueKind.Null or JsonValueKind.Undefined => null,
                    JsonValueKind.String => el.GetString(),
                    JsonValueKind.True => "true",
                    JsonValueKind.False => "false",
                    _ => el.GetRawText(),
                };
            case IFormattable f: return f.ToString(null, CultureInfo.InvariantCulture);
            default: return value.ToString();
        }
    }

    // ── Backoff ─────────────────────────────────────────────────────────────

    /// <summary>Exponential backoff with jitter, but honour <c>Retry-After</c> (seconds or HTTP-date), capped at 60s.</summary>
    public static TimeSpan Backoff(int attempt, string? retryAfter)
    {
        if (!string.IsNullOrWhiteSpace(retryAfter))
        {
            if (double.TryParse(retryAfter, NumberStyles.Float, CultureInfo.InvariantCulture, out var secs) && secs >= 0)
                return Min(TimeSpan.FromSeconds(secs), MaxBackoff);
            if (DateTimeOffset.TryParse(retryAfter, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var date))
            {
                var wait = date - DateTimeOffset.UtcNow;
                return Min(wait < TimeSpan.Zero ? TimeSpan.Zero : wait, MaxBackoff);
            }
        }
        double baseMs = 250 * Math.Pow(2, attempt);
        double jitter = Random.Shared.NextDouble() * baseMs * 0.25;
        return Min(TimeSpan.FromMilliseconds(baseMs + jitter), MaxBackoff);
    }

    private static TimeSpan Min(TimeSpan a, TimeSpan b) => a < b ? a : b;

    /// <summary><c>Retry-After</c> as whole seconds: numeric, or an HTTP-date converted to seconds from now.</summary>
    public static int? RetryAfterSeconds(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var secs))
            return (int)Math.Ceiling(secs);
        if (DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var date))
            return Math.Max(0, (int)Math.Ceiling((date - DateTimeOffset.UtcNow).TotalSeconds));
        return null;
    }

    // ── Error mapping ───────────────────────────────────────────────────────

    /// <summary>Decode a body: empty → null, JSON → node, anything else → string value.</summary>
    public static JsonNode? DecodeBody(string text)
    {
        if (string.IsNullOrEmpty(text)) return null;
        try
        {
            return JsonNode.Parse(text);
        }
        catch (JsonException)
        {
            return JsonValue.Create(text);
        }
    }

    private static string? StringAt(JsonNode? node, string key) =>
        node is JsonObject o && o.TryGetPropertyValue(key, out var v) && v is JsonValue jv
        && jv.TryGetValue<string>(out var s) ? s : null;

    private static JsonNode? At(JsonNode? node, string key) =>
        node is JsonObject o && o.TryGetPropertyValue(key, out var v) ? v : null;

    /// <summary>Pull a human message out of the API's several error shapes.</summary>
    public static string MessageOf(JsonNode? body, string rawText, string fallback)
    {
        if (body is JsonObject)
        {
            var err = StringAt(body, "error");
            if (err is not null) return err;
            // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
            var nested = StringAt(At(body, "error"), "message");
            if (nested is not null) return nested;
            var msg = StringAt(body, "message");
            if (msg is not null) return msg;
        }
        var trimmed = rawText.Trim();
        if (body is not JsonObject && trimmed.Length > 0)
            return trimmed.Length > 500 ? trimmed[..500] : trimmed;
        return fallback;
    }

    public static string? CodeOf(JsonNode? body) =>
        StringAt(body, "code") ?? StringAt(At(body, "error"), "code");

    /// <summary>True when a body is the plan-limit refusal (<c>code: "plan_limit_exceeded"</c>).</summary>
    public static bool IsPlanLimitBody(JsonNode? body) => StringAt(body, "code") == "plan_limit_exceeded";

    private static string? Header(HttpResponseMessage res, string name)
    {
        if (res.Headers.TryGetValues(name, out var values)) return values.FirstOrDefault();
        if (res.Content.Headers.TryGetValues(name, out var cvalues)) return cvalues.FirstOrDefault();
        return null;
    }

    /// <summary>Map an error response to the right typed exception. Plan limits first, by <c>code</c>.</summary>
    public static MisarDevException ErrorFor(int status, string? reason, string rawText, JsonNode? body,
        string? requestId, string? retryAfter)
    {
        string message = MessageOf(body, rawText, string.IsNullOrEmpty(reason) ? $"HTTP {status}" : reason);
        string? code = CodeOf(body);

        if (IsPlanLimitBody(body))
        {
            var offer = At(body, "upgrade") as JsonObject;
            return new PlanLimitException(status, message, body, rawText, requestId, offer, RetryAfterSeconds(retryAfter));
        }
        return status switch
        {
            400 or 422 => new ValidationException(status, message, code, body, rawText, requestId),
            401 => new AuthenticationException(status, message, code, body, rawText, requestId),
            403 => new PermissionDeniedException(status, message, code, body, rawText, requestId),
            404 => new NotFoundException(status, message, code, body, rawText, requestId),
            409 => new ConflictException(status, message, code, body, rawText, requestId),
            429 => new RateLimitException(status, message, code, body, rawText, requestId, RetryAfterSeconds(retryAfter)),
            >= 500 => new ServerException(status, message, code, body, rawText, requestId),
            _ => new MisarDevException(status, message, code, body, rawText, requestId),
        };
    }

    // ── Requests ────────────────────────────────────────────────────────────

    private HttpRequestMessage Build(string method, string url, string? json, string accept)
    {
        var req = new HttpRequestMessage(new HttpMethod(method), url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue(accept));
        req.Headers.TryAddWithoutValidation("X-Misar-SDK", SdkHeader);
        // Content-Type is a content header in .NET, so a body-less request
        // carries an empty JSON body to send it.
        req.Content = new StringContent(json ?? "", Encoding.UTF8);
        req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        if (json is null) req.Content.Headers.ContentLength = 0;
        foreach (var (k, v) in _extraHeaders)
        {
            req.Headers.Remove(k);
            req.Headers.TryAddWithoutValidation(k, v);
        }
        return req;
    }

    private static string? Serialize(object? body) =>
        body switch
        {
            null => null,
            JsonNode node => node.ToJsonString(),
            string s => JsonSerializer.Serialize(s),
            _ => JsonSerializer.Serialize(body),
        };

    /// <summary>Send one request, retrying throttles and (for idempotent verbs) transient failures.</summary>
    public async Task<JsonNode?> RequestAsync(
        string method,
        string path,
        object? body = null,
        IEnumerable<KeyValuePair<string, object?>>? query = null,
        CancellationToken cancellationToken = default)
    {
        string verb = method.ToUpperInvariant();
        string url = BaseUrl + path + BuildQuery(query);
        string? json = Serialize(body);

        for (int attempt = 0; ; attempt++)
        {
            bool last = attempt >= MaxRetries - 1;
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(Timeout);

            HttpResponseMessage res;
            try
            {
                using var req = Build(verb, url, json, "application/json");
                res = await _http.SendAsync(req, HttpCompletionOption.ResponseContentRead, timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException or IOException)
            {
                if (cancellationToken.IsCancellationRequested) throw;
                if (!last && Idempotent.Contains(verb))
                {
                    await Task.Delay(Backoff(attempt, null), cancellationToken).ConfigureAwait(false);
                    continue;
                }
                string what = ex is OperationCanceledException ? $"timed out after {Timeout.TotalSeconds:0.#}s" : ex.Message;
                throw new NetworkException($"Request to {verb} {path} failed: {what}", ex);
            }

            using (res)
            {
                int status = (int)res.StatusCode;
                string text = await res.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

                if (res.IsSuccessStatusCode)
                    return status == 204 ? null : DecodeBody(text);

                // Read the body BEFORE deciding to retry: a 429 from the rate
                // limiter and a 429 from a spent plan allowance share a status,
                // and only the first is worth retrying.
                var decoded = DecodeBody(text);
                string? retryAfter = Header(res, "Retry-After");
                var error = ErrorFor(status, res.ReasonPhrase, text, decoded, Header(res, "x-request-id"), retryAfter);
                if (error is PlanLimitException) throw error;

                bool retryable = Retryable.Contains(status) && (status == 429 || Idempotent.Contains(verb));
                if (retryable && !last)
                {
                    await Task.Delay(Backoff(attempt, retryAfter), cancellationToken).ConfigureAwait(false);
                    continue;
                }
                throw error;
            }
        }
    }

    /// <summary>
    /// Open a Server-Sent Events stream (<c>Accept: text/event-stream</c>) and yield each event.
    /// </summary>
    /// <remarks>
    /// Never retried: a stream that fails mid-flight cannot be replayed without
    /// duplicating what the caller already consumed. The terminator payload
    /// (<c>[DONE]</c> on chat completions; <c>null</c> = read to EOF) ends
    /// iteration and is never yielded. A frame carrying
    /// <c>code: "plan_limit_exceeded"</c> is raised as a <see cref="PlanLimitException"/>.
    /// </remarks>
    public async IAsyncEnumerable<SseEvent> StreamAsync(
        string method,
        string path,
        object? body = null,
        IEnumerable<KeyValuePair<string, object?>>? query = null,
        string? terminator = "[DONE]",
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        string verb = method.ToUpperInvariant();
        string url = BaseUrl + path + BuildQuery(query);

        HttpResponseMessage res;
        try
        {
            using var req = Build(verb, url, Serialize(body), "text/event-stream");
            // ResponseHeadersRead is what makes this a stream rather than a
            // buffered read of the whole body.
            res = await _http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException
                                   || (ex is OperationCanceledException && !cancellationToken.IsCancellationRequested))
        {
            throw new NetworkException($"Stream {verb} {path} failed: {ex.Message}", ex);
        }

        using (res)
        {
            int status = (int)res.StatusCode;
            string? requestId = Header(res, "x-request-id");
            if (!res.IsSuccessStatusCode)
            {
                string text = await res.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                throw ErrorFor(status, res.ReasonPhrase, text, DecodeBody(text), requestId, Header(res, "Retry-After"));
            }

            await using var stream = await res.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var parser = new SseParser();

            while (true)
            {
                string? line;
                try
                {
                    line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is IOException or HttpRequestException)
                {
                    throw new NetworkException($"Stream {verb} {path} broke: {ex.Message}", ex);
                }

                // ReadLine handles \n, \r\n and \r; a blank line ends a frame and
                // end of stream flushes a final unterminated one.
                var frame = line is null ? parser.Flush() : parser.Push(line);
                if (frame is not null)
                {
                    if (terminator is not null && frame.Data.Trim() == terminator) yield break;
                    var data = SseParser.Decode(frame.Data);
                    // Other error frames are the stream's own business (the build
                    // stream reports a failed step and carries on), so only the plan
                    // refusal — which no amount of reading further will fix — is raised.
                    if (IsPlanLimitBody(data))
                        throw ErrorFor(402, null, frame.Data, data, requestId, Header(res, "Retry-After"));
                    yield return new SseEvent(frame.Event, data, frame.Id, frame.Data);
                }
                if (line is null) yield break;
            }
        }
    }
}
