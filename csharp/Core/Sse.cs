using System.Text.Json;
using System.Text.Json.Nodes;

namespace MisarDev;

/// <summary>
/// One Server-Sent Event.
/// </summary>
/// <param name="Event">The <c>event:</c> name, when the server sends one.</param>
/// <param name="Data">The <c>data:</c> payload, JSON-decoded when it is JSON, otherwise a string value.</param>
/// <param name="Id">The <c>id:</c> field, when present.</param>
/// <param name="Raw">The <c>data:</c> payload exactly as received (multi-line data joined with <c>\n</c>).</param>
public sealed record SseEvent(string? Event, JsonNode? Data, string? Id, string Raw);

/// <summary>
/// Incremental <c>text/event-stream</c> parser.
/// </summary>
/// <remarks>
/// Feed it one line at a time (without the line terminator). A blank line ends
/// a frame; several <c>data:</c> lines are joined with <c>\n</c>; one leading
/// space after the colon is stripped; <c>:</c> comment lines are keep-alives and
/// are skipped. A frame with no <c>data:</c> line yields nothing.
/// </remarks>
public sealed class SseParser
{
    private string? _event;
    private string? _id;
    private readonly List<string> _data = new();

    /// <summary>Consume one line. Returns a completed frame when <paramref name="line"/> is blank.</summary>
    public SseFrame? Push(string line)
    {
        if (line.Length == 0) return Flush();
        if (line[0] == ':') return null;

        int idx = line.IndexOf(':');
        string field = idx < 0 ? line : line[..idx];
        string value = idx < 0 ? "" : line[(idx + 1)..];
        if (value.StartsWith(' ')) value = value[1..];

        switch (field)
        {
            case "data": _data.Add(value); break;
            case "event": _event = value; break;
            case "id": _id = value; break;
        }
        return null;
    }

    /// <summary>End the current frame (blank line or end of stream).</summary>
    public SseFrame? Flush()
    {
        SseFrame? frame = _data.Count == 0 ? null : new SseFrame(_event, string.Join("\n", _data), _id);
        _data.Clear();
        _event = null;
        _id = null;
        return frame;
    }

    /// <summary>JSON-decode an event payload when possible, else keep it as a string value.</summary>
    public static JsonNode? Decode(string raw)
    {
        try
        {
            return JsonNode.Parse(raw);
        }
        catch (JsonException)
        {
            return JsonValue.Create(raw);
        }
    }
}

/// <summary>A parsed but not yet decoded SSE frame.</summary>
public sealed record SseFrame(string? Event, string Data, string? Id);
