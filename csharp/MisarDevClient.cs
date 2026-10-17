using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

[assembly: InternalsVisibleTo("MisarDevTests")]

namespace MisarDev;

/// <summary>Options for <see cref="MisarDevClient"/>. Every property is optional.</summary>
public sealed class MisarDevClientOptions
{
    /// <summary>API base URL. Default <c>MISARDEV_BASE_URL</c>, else <c>https://api.misar.io/dev</c>.</summary>
    public string? BaseUrl { get; set; }

    /// <summary>Total attempts for a retryable failure. Default 3.</summary>
    public int MaxRetries { get; set; } = 3;

    /// <summary>Per-attempt timeout. Default 60 seconds — builds and AI calls are slow.</summary>
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(60);

    /// <summary>
    /// Bring your own <see cref="System.Net.Http.HttpClient"/> (tests, proxies,
    /// <c>IHttpClientFactory</c>). The client never disposes one you pass in.
    /// Its own <c>Timeout</c> still applies, so leave it at least as long as
    /// <see cref="Timeout"/>.
    /// </summary>
    public HttpClient? HttpClient { get; set; }

    /// <summary>Extra headers sent with every request.</summary>
    public IDictionary<string, string>? Headers { get; set; }
}

/// <summary>
/// The MisarDev API client.
/// </summary>
/// <remarks>
/// Every resource (<see cref="Projects"/>, <see cref="Templates"/>,
/// <see cref="Chat"/>, …) is generated from the API's route tree, so it always
/// matches what the server exposes. The client authenticates with your account
/// API key (<c>mdk_…</c>) and nothing else.
/// <code>
/// using var dev = new MisarDevClient(); // reads MISARDEV_API_KEY
/// var projects = await dev.Projects.List();
/// </code>
/// </remarks>
public sealed partial class MisarDevClient : IDisposable
{
    /// <summary>Default API base URL.</summary>
    public const string DefaultBaseUrl = Transport.DefaultBaseUrl;

    /// <summary>The SDK version sent in <c>X-Misar-SDK</c>.</summary>
    public const string Version = Transport.SdkVersion;

    private readonly Transport _transport;
    private readonly HttpClient _http;
    private readonly bool _ownsHttp;

    /// <summary>
    /// Create a client. When <paramref name="apiKey"/> is null or empty the
    /// <c>MISARDEV_API_KEY</c> environment variable is used; if that is empty
    /// too, the constructor throws.
    /// </summary>
    /// <exception cref="MisarDevException">No API key was supplied or found in the environment.</exception>
    public MisarDevClient(string? apiKey = null, MisarDevClientOptions? options = null)
    {
        options ??= new MisarDevClientOptions();
        string? key = string.IsNullOrWhiteSpace(apiKey)
            ? Environment.GetEnvironmentVariable("MISARDEV_API_KEY")
            : apiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            throw new MisarDevException(
                0,
                "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. " +
                "Create one at https://www.misar.dev/settings/api-keys.",
                "missing_api_key");
        }

        string baseUrl = !string.IsNullOrWhiteSpace(options.BaseUrl)
            ? options.BaseUrl!
            : Environment.GetEnvironmentVariable("MISARDEV_BASE_URL") is { Length: > 0 } envBase
                ? envBase
                : DefaultBaseUrl;

        _ownsHttp = options.HttpClient is null;
        // Our own client gets an infinite timeout: the transport applies
        // Options.Timeout per attempt, and streams must be able to stay open.
        _http = options.HttpClient ?? new HttpClient { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        var headers = options.Headers is null ? null : new Dictionary<string, string>(options.Headers);
        _transport = new Transport(key!, baseUrl, options.MaxRetries, options.Timeout, _http, headers);
        InitResources(_transport);
    }

    /// <summary>The API base URL in use.</summary>
    public string BaseUrl => _transport.BaseUrl;

    /// <summary>Total attempts for a retryable failure.</summary>
    public int MaxRetries => _transport.MaxRetries;

    /// <summary>Per-attempt timeout.</summary>
    public TimeSpan Timeout => _transport.Timeout;

    /// <summary>
    /// Call any route directly, for routes the SDK does not wrap yet:
    /// <c>await dev.RequestAsync("GET", "/usage", query: new { days = 7 })</c>.
    /// </summary>
    public Task<JsonNode?> RequestAsync(
        string method,
        string path,
        object? body = null,
        object? query = null,
        CancellationToken cancellationToken = default) =>
        _transport.RequestAsync(method, path, body, query is null ? null : Transport.Query(query), cancellationToken);

    /// <summary>Open any SSE route directly. <paramref name="terminator"/> null reads to EOF.</summary>
    public IAsyncEnumerable<SseEvent> StreamAsync(
        string method,
        string path,
        object? body = null,
        object? query = null,
        string? terminator = null,
        CancellationToken cancellationToken = default) =>
        _transport.StreamAsync(method, path, body, query is null ? null : Transport.Query(query), terminator, cancellationToken);

    /// <summary>Walk every page of an offset-paginated list. See <see cref="Pagination"/>.</summary>
    public IAsyncEnumerable<JsonNode?> Paginate(
        Func<int, int, Task<JsonNode?>> fetchPage,
        int pageSize = 50,
        int? maxItems = null,
        CancellationToken cancellationToken = default) =>
        Pagination.Paginate(fetchPage, pageSize, maxItems, cancellationToken);

    /// <summary>Disposes the underlying <see cref="HttpClient"/> if the client created it.</summary>
    public void Dispose()
    {
        if (_ownsHttp) _http.Dispose();
    }
}
