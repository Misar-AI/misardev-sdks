using System.Reflection;
using System.Text.Json.Nodes;
using Xunit;

namespace MisarDev.Tests;

/// <summary>
/// Every operation in sdks/manifest.json is reachable through the generated
/// client and builds the exact verb + URL the server routes. Each method is
/// invoked for real (by reflection) against a recording stub — nothing is
/// declared by hand.
/// </summary>
public sealed class ResourceTests
{
    private static JsonObject? LoadManifest()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "manifest.json");
        return File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))!.AsObject() : null;
    }

    private static string Pascal(string s) => char.ToUpperInvariant(s[0]) + s[1..];

    private static List<string> Strings(JsonNode? n) =>
        n is JsonArray a ? a.Select(x => x!.GetValue<string>()).ToList() : new List<string>();

    private sealed record Op(string Resource, string Name, string Verb, string Path, List<string> PathParams,
        List<string> RequiredQuery, bool Stream);

    private static IEnumerable<Op> Ops(JsonObject manifest)
    {
        foreach (var (resource, def) in manifest["resources"]!.AsObject())
            foreach (var m in def!["methods"]!.AsArray())
                yield return new Op(resource, m!["name"]!.GetValue<string>(), m["verb"]!.GetValue<string>(),
                    m["path"]!.GetValue<string>(), Strings(m["pathParams"]), Strings(m["requiredQuery"]), false);
        foreach (var s in manifest["streams"]!["sse"]!.AsArray())
            yield return new Op(s!["resource"]!.GetValue<string>(), s["name"]!.GetValue<string>(),
                s["verb"]!.GetValue<string>(), s["path"]!.GetValue<string>(), Strings(s["pathParams"]),
                Strings(s["requiredQuery"]), true);
    }

    private static string ExpectedUrl(Op op)
    {
        var p = op.Path;
        foreach (var name in op.PathParams) p = p.Replace($":{name}", $"{name}-1");
        var qs = string.Join("&", op.RequiredQuery.Select(q => $"{q}={q}-v"));
        return $"https://api.test/dev{p}{(qs.Length > 0 ? "?" + qs : "")}";
    }

    private static object?[] ArgsFor(MethodInfo method, Op op)
    {
        var args = new List<object?>();
        foreach (var param in method.GetParameters())
        {
            if (op.PathParams.Contains(param.Name!)) args.Add($"{param.Name}-1");
            else if (op.RequiredQuery.Contains(param.Name!)) args.Add($"{param.Name}-v");
            else if (param.Name == "body") args.Add(new Dictionary<string, object?> { ["probe"] = true });
            else args.Add(param.DefaultValue is DBNull ? null : param.DefaultValue);
        }
        return args.ToArray();
    }

    [Fact]
    public async Task EveryManifestOperationBuildsItsVerbAndUrl()
    {
        var manifest = LoadManifest();
        if (manifest is null) return; // public mirror: no manifest alongside
        var ops = Ops(manifest).ToList();
        Assert.Equal(MisarDevClient.OperationCount, ops.Count);
        Assert.Equal(109, ops.Count);

        foreach (var op in ops)
        {
            var label = $"{op.Resource}.{op.Name}";
            var (dev, h) = Stub.Client(1, op.Stream
                ? () => Stub.Sse("data: {\"x\":1}\n\n")
                : () => Stub.Json("""{"ok":true}"""));

            var prop = typeof(MisarDevClient).GetProperty(Pascal(op.Resource));
            Assert.True(prop is not null, $"missing resource {op.Resource}");
            var resource = prop!.GetValue(dev)!;
            var method = resource.GetType().GetMethod(Pascal(op.Name));
            Assert.True(method is not null, $"missing method {label}");

            var result = method!.Invoke(resource, ArgsFor(method, op));
            if (op.Stream)
            {
                var events = new List<SseEvent>();
                await foreach (var ev in (IAsyncEnumerable<SseEvent>)result!) events.Add(ev);
                Assert.Single(events);
            }
            else
            {
                await (Task<JsonNode?>)result!;
            }

            var call = Assert.Single(h.Calls);
            Assert.True(op.Verb == call.Method, $"{label}: verb {call.Method} != {op.Verb}");
            Assert.True(ExpectedUrl(op) == call.Url, $"{label}: url {call.Url} != {ExpectedUrl(op)}");
            if (method.GetParameters().Any(p => p.Name == "body"))
                Assert.True(call.Json?["probe"]?.GetValue<bool>() == true, $"{label}: body not sent");
        }
    }
}
