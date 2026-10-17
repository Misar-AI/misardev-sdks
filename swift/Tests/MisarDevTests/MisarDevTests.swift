import Foundation
@testable import MisarDev

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Test bodies, written once against the helpers in TestSupport.swift and run
/// by XCTest (XCTestEntry.swift) or Swift Testing (SwiftTestingEntry.swift).

/// Await a call that must throw, and hand back what it threw.
func failure<T>(
    _ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line, column: Int = #column
) async -> Error? {
    do {
        _ = try await body()
        fail("expected the call to throw", file: file, line: line, column: column)
        return nil
    } catch {
        return error
    }
}

func collect(_ stream: AsyncThrowingStream<SSEEvent, Error>) async throws -> [SSEEvent] {
    var out: [SSEEvent] = []
    for try await event in stream { out.append(event) }
    return out
}

struct AuthenticationCases {
    func testSendsBearerKeyAndSdkHeaders() async throws {
        let dev = try Fixtures.client([.json(#"{"projects":[]}"#)])
        _ = try await dev.projects.list()
        let call = try unwrap(StubURLProtocol.calls.first)
        expectEqual(StubURLProtocol.calls.count, 1)
        expectEqual(call.header("Authorization"), "Bearer mdk_test_key")
        expectEqual(call.header("X-Misar-SDK"), "misardev-swift/1.0.0")
        expectEqual(call.header("Accept"), "application/json")
        expectEqual(call.header("Content-Type"), "application/json")
        expectEqual(call.url, "https://api.test/dev/projects")
    }

    func testRefusesToConstructWithoutAKey() {
        let previous = ProcessInfo.processInfo.environment["MISARDEV_API_KEY"]
        unsetenv("MISARDEV_API_KEY")
        defer { if let previous { setenv("MISARDEV_API_KEY", previous, 1) } }

        do {
            _ = try MisarDevClient()
            fail("expected a missing-key error")
        } catch let e as MisarDevError {
            expectEqual(e.code, "missing_api_key")
            expectTrue(e.message.contains("API key is required"))
            expectTrue(e.message.contains("https://www.misar.dev/settings/api-keys"))
        } catch {
            fail("unexpected \(error)")
        }
        do {
            _ = try MisarDevClient(apiKey: "")
            fail("expected a missing-key error for an empty key")
        } catch {
            expectTrue(error is MisarDevError)
        }
    }

    func testReadsKeyFromEnvironmentAndDefaultsBaseURL() async throws {
        let previousKey = ProcessInfo.processInfo.environment["MISARDEV_API_KEY"]
        let previousBase = ProcessInfo.processInfo.environment["MISARDEV_BASE_URL"]
        setenv("MISARDEV_API_KEY", "mdk_from_env", 1)
        unsetenv("MISARDEV_BASE_URL")
        defer {
            if let previousKey { setenv("MISARDEV_API_KEY", previousKey, 1) } else { unsetenv("MISARDEV_API_KEY") }
            if let previousBase { setenv("MISARDEV_BASE_URL", previousBase, 1) }
        }

        StubURLProtocol.reset([.json("{}")])
        let dev = try MisarDevClient(session: Fixtures.stubbedSession())
        expectEqual(dev.baseURL, "https://api.misar.io/dev")
        expectEqual(dev.maxRetries, 3)
        expectEqual(dev.timeout, 60)
        _ = try await dev.usage.plan()
        expectEqual(StubURLProtocol.calls.first?.header("Authorization"), "Bearer mdk_from_env")
        expectEqual(StubURLProtocol.calls.first?.url, "https://api.misar.io/dev/usage/plan")

        setenv("MISARDEV_BASE_URL", "https://example.test/dev/", 1)
        try expectEqual(try MisarDevClient(session: Fixtures.stubbedSession()).baseURL, "https://example.test/dev")
        unsetenv("MISARDEV_BASE_URL")
    }
}

struct ErrorCases {
    func testPlanLimitCarriesTheFullOfferDetectedByCode() async throws {
        let dev = try Fixtures.client([.json(Fixtures.planLimitBody, status: 402, headers: ["x-request-id": "req_1"])])
        let error = await failure { try await dev.projects.list() }
        let e = try unwrap(error as? PlanLimitError)
        expectEqual(e.status, 402)
        expectEqual(e.code, "plan_limit_exceeded")
        expectEqual(e.message, "API access requires the Pro plan or higher.")
        expectEqual(e.offer?["recommended_plan"], "pro")
        expectEqual(e.offer?["cta"], "Upgrade to Pro to continue.")
        expectEqual(e.offer?["urls"]?["compare"], "https://www.misar.dev/pricing#compare")
        expectEqual(e.offer?["plans"], .array([]))
        expectEqual(e.headline, "API access isn't included in your Starter plan.")
        expectEqual(e.upgradeUrl, "https://www.misar.dev/settings/billing")
        expectEqual(e.feature, "api_access")
        expectEqual(e.currentPlan, "starter")
        expectEqual(e.recommendedPlan, "pro")
        expectEqual(e.reason, "feature_locked")
        expectEqual(e.requestId, "req_1")
        expectEqual(StubURLProtocol.calls.count, 1)
    }

    func testNeverRetriesAQuotaExhausted429() async throws {
        let body = Fixtures.planLimitBody.replacingOccurrences(of: "feature_locked", with: "quota_exhausted")
        let dev = try Fixtures.client([.json(body, status: 429, headers: ["Retry-After": "3600"])])
        let error = await failure { try await dev.templates.list() }
        let e = try unwrap(error as? PlanLimitError)
        expectEqual(e.status, 429)
        expectEqual(e.retryAfter, 3600)
        expectEqual(e.reason, "quota_exhausted")
        expectEqual(StubURLProtocol.calls.count, 1)
    }

    func testRetriesAnOrdinary429OnAPostAndHonoursRetryAfter() async throws {
        let dev = try Fixtures.client([
            .json(#"{"error":"slow down"}"#, status: 429, headers: ["Retry-After": "0"]),
            .json(#"{"ok":1}"#),
        ])
        let result = try await dev.projects.create(["name": "x"])
        expectEqual(result["ok"]?.intValue, 1)
        expectEqual(StubURLProtocol.calls.count, 2)
    }

    func testGivesUpOnAPersistentThrottleWithRateLimitError() async throws {
        let dev = try Fixtures.client(
            [.json(#"{"error":"slow down"}"#, status: 429, headers: ["Retry-After": "0"])], maxRetries: 2
        )
        let error = await failure { try await dev.projects.list() }
        let e = try unwrap(error as? RateLimitError)
        expectEqual(e.retryAfter, 0)
        expectEqual(e.message, "slow down")
        expectEqual(StubURLProtocol.calls.count, 2)
    }

    func testRetries503OnGetButNotOnPost() async throws {
        let get = try Fixtures.client([.json(#"{"error":"down"}"#, status: 503), .json(#"{"ok":true}"#)])
        let ok = try await get.projects.list()
        expectEqual(ok["ok"], true)
        expectEqual(StubURLProtocol.calls.count, 2)

        let post = try Fixtures.client([.json(#"{"error":"down"}"#, status: 503), .json(#"{"ok":true}"#)])
        let error = await failure { try await post.projects.create([:]) }
        expectEqual((error as? ServerError)?.status, 503)
        expectEqual(StubURLProtocol.calls.count, 1)
    }

    func testMapsStatusesToTypedErrorsAndReadsTheOpenAIShape() async throws {
        var dev = try Fixtures.client([.json(#"{"error":"Unauthorized"}"#, status: 401)])
        var error = await failure { try await dev.projects.list() }
        expectTrue(error is AuthenticationError)

        dev = try Fixtures.client([.json(#"{"error":"nope"}"#, status: 404)])
        error = await failure { try await dev.projects.get("p1") }
        expectTrue(error is NotFoundError)

        dev = try Fixtures.client([
            .json(#"{"error":{"message":"bad model","type":"invalid_request_error","code":"bad_model"}}"#, status: 400),
        ])
        error = await failure { try await dev.chat.completions([:]) }
        let v = try unwrap(error as? ValidationError)
        expectEqual(v.message, "bad model")
        expectEqual(v.code, "bad_model")

        dev = try Fixtures.client([.json(#"{"message":"taken"}"#, status: 409)])
        error = await failure { try await dev.projects.deploy("p1") }
        expectEqual((error as? ConflictError)?.message, "taken")

        dev = try Fixtures.client([.json(#"{"error":"no"}"#, status: 403)])
        error = await failure { try await dev.projects.list() }
        expectTrue(error is PermissionDeniedError)

        dev = try Fixtures.client([.text("teapot", status: 418)])
        error = await failure { try await dev.projects.list() }
        let teapot = try unwrap(error as? MisarDevError)
        expectEqual(teapot.message, "teapot")
        expectEqual(teapot.status, 418)
    }

    func testRetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkError() async throws {
        let dev = try Fixtures.client([.failure()], maxRetries: 2)
        let error = await failure { try await dev.projects.list() }
        expectEqual((error as? NetworkError)?.status, 0)
        expectEqual(StubURLProtocol.calls.count, 2)

        let post = try Fixtures.client([.failure()])
        let postError = await failure { try await post.projects.create() }
        expectTrue(postError is NetworkError)
        expectEqual(StubURLProtocol.calls.count, 1)
    }
}

struct RequestCases {
    func testEncodesPathParamsRequiredAndOptionalQueryAndBody() async throws {
        let dev = try Fixtures.client([.json("{}")])
        try await dev.projects.checkSubdomain("a b/c", value: "my-app")
        expectEqual(StubURLProtocol.calls[0].url, "https://api.test/dev/projects/a%20b%2Fc/subdomain/check?value=my-app")

        try await dev.templates.list(query: ["limit": 5, "featured": true, "category": nil])
        expectEqual(StubURLProtocol.calls[1].url, "https://api.test/dev/templates?featured=true&limit=5")

        try await dev.projects.update("p1", ["name": "New"])
        expectEqual(StubURLProtocol.calls[2].method, "PATCH")
        expectEqual(StubURLProtocol.calls[2].json, ["name": "New"])

        try await dev.rag.search(projectId: "proj 1", query: ["query": "auth", "stats": true])
        expectEqual(StubURLProtocol.calls[3].url, "https://api.test/dev/rag?projectId=proj%201&query=auth&stats=true")

        try await dev.projects.create()
        expectEqual(StubURLProtocol.calls[4].json, [:])
    }

    func testReturnsNullForAnEmpty204AndStringsForNonJSON() async throws {
        var dev = try Fixtures.client([StubResponse(status: 204, headers: [:], pieces: [])])
        let deleted = try await dev.projects.delete("p1")
        expectEqual(deleted, .null)

        dev = try Fixtures.client([.text("plain text", status: 200)])
        let exported = try await dev.projects.export("p1")
        expectEqual(exported, "plain text")

        dev = try Fixtures.client([.json("[1,2,3]")])
        let builds = try await dev.builds.list()
        expectEqual(builds.arrayValue?.count, 3)
    }

    func testExposesARawRequestEscapeHatch() async throws {
        let dev = try Fixtures.client([.json(#"{"hi":1}"#)])
        let result = try await dev.request("GET", "/usage", query: ["days": 7])
        expectEqual(result["hi"]?.intValue, 1)
        expectEqual(StubURLProtocol.calls[0].url, "https://api.test/dev/usage?days=7")
    }

    func testBuildsQueryStringsAndBackoffDelays() {
        expectEqual(Transport.buildQuery([:]), "")
        expectEqual(Transport.buildQuery(["a": nil]), "")
        expectEqual(Transport.backoff(attempt: 0, retryAfter: "2"), 2)
        expectEqual(Transport.backoff(attempt: 0, retryAfter: "999"), 60)
        expectTrue(Transport.backoff(attempt: 3, retryAfter: nil) >= 2)
        expectTrue(Transport.backoff(attempt: 30, retryAfter: nil) <= 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let soon = formatter.string(from: Date().addingTimeInterval(1))
        expectTrue(Transport.backoff(attempt: 0, retryAfter: soon) <= 1)
    }
}

struct StreamingCases {
    func testStreamsChatCompletionsUntilDoneForcingStreamTrue() async throws {
        let dev = try Fixtures.client([.sse([
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"# + "\n\n",
            ": keep-alive\n\n",
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"# + "\r\n\r\n",
            "data: [DONE]\n\n",
            #"data: {"never":"seen"}"# + "\n\n",
        ])])
        var text = ""
        for try await event in dev.chat.completionsStream([
            "model": "misar-online",
            "messages": [["role": "user", "content": "hi"]],
        ]) {
            text += event.data["choices"]?[0]?["delta"]?["content"]?.stringValue ?? ""
        }
        expectEqual(text, "Hello")
        let call = try unwrap(StubURLProtocol.calls.first)
        expectEqual(call.json?["stream"], true)
        expectEqual(call.json?["model"], "misar-online")
        expectEqual(call.header("Accept"), "text/event-stream")
        expectEqual(call.url, "https://api.test/dev/v1/chat/completions")
    }

    func testYieldsNamedEventsMultiLineDataAndATrailingFrame() async throws {
        // The first frame is split across two chunks on purpose.
        let dev = try Fixtures.client([.sse(["event: step\nid: 1\ndata: li", "ne1\ndata: line2\n\n", #"data: {"done":true}"#])])
        let events = try await collect(dev.projects.buildStream("p1"))
        expectEqual(events.count, 2)
        expectEqual(events[0], SSEEvent(event: "step", data: "line1\nline2", id: "1", raw: "line1\nline2"))
        expectEqual(events[1].data, ["done": true])
        expectEqual(events[1].event, nil)
    }

    func testRaisesAPlanLimitFrameAsPlanLimitError() async throws {
        let frame = Fixtures.planLimitBody
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: #"{"error""#, with: #"{"type":"error","error""#)
        let dev = try Fixtures.client([.sse(["data: \(frame)\n\n"])])
        let error = await failure { try await collect(dev.chat.studioStream(["message": "hi"])) }
        expectEqual((error as? PlanLimitError)?.recommendedPlan, "pro")
    }

    func testRaisesAnHTTPErrorBeforeStreamingAndNeverRetries() async throws {
        var dev = try Fixtures.client([.json(Fixtures.planLimitBody, status: 402)])
        var error = await failure { try await collect(dev.projects.buildStream("p1")) }
        expectTrue(error is PlanLimitError)

        dev = try Fixtures.client([.json(#"{"error":"down"}"#, status: 503)])
        error = await failure { try await collect(dev.projects.buildStream("p1")) }
        expectTrue(error is ServerError)
        expectEqual(StubURLProtocol.calls.count, 1)
    }
}

struct PaginationCases {
    func testWalksOffsetPagesUntilAShortPage() async throws {
        let pages: [JSONValue] = [[1, 2], [3, 4], [5]]
        var seen: [Int] = []
        for try await item in paginate(pageSize: 2, { offset, _ in ["items": pages[offset / 2]] }) {
            seen.append(item.intValue ?? -1)
        }
        expectEqual(seen, [1, 2, 3, 4, 5])
    }

    func testDrivesARealListMethodAndRespectsMaxItems() async throws {
        let dev = try Fixtures.client([
            .json(#"{"templates":[{"id":1},{"id":2}]}"#),
            .json(#"{"templates":[{"id":3}]}"#),
        ])
        var ids: [Int] = []
        for try await template in dev.paginate(pageSize: 2, maxItems: 3, { offset, limit in
            try await dev.templates.list(query: ["offset": .init(offset), "limit": .init(limit)])
        }) {
            ids.append(template["id"]?.intValue ?? -1)
        }
        expectEqual(ids, [1, 2, 3])
        expectTrue(StubURLProtocol.calls[1].url.contains("offset=2"))
    }
}

/// Every operation in sdks/manifest.json is reachable through the generated
/// client and builds the exact verb + URL the server routes. The calls come from
/// the emitter's probe table; the manifest (when present alongside, as in the
/// monorepo) proves the table is complete.
struct ResourceCases {
    func testEveryOperationBuildsItsVerbAndURL() async throws {
        let probes = OperationProbes.all
        expectEqual(probes.count, MisarDevClient.operationCount)

        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MisarDevTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift
            .appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL) {
            let manifest = try JSONValue.decode(data)
            var expected = Set<String>()
            for (resource, def) in manifest["resources"]?.objectValue ?? [:] {
                for m in def["methods"]?.arrayValue ?? [] { expected.insert("\(resource).\(m["name"]?.stringValue ?? "")") }
            }
            for s in manifest["streams"]?["sse"]?.arrayValue ?? [] {
                expected.insert("\(s["resource"]?.stringValue ?? "").\(s["name"]?.stringValue ?? "")")
            }
            expectEqual(expected.count, 109)
            expectEqual(Set(probes.map { "\($0.resource).\($0.name)" }), expected)
        }

        for probe in probes {
            let label = "\(probe.resource).\(probe.name)"
            let dev = try Fixtures.client(
                [probe.stream ? .sse([#"data: {"x":1}"# + "\n\n"]) : .json(#"{"ok":true}"#)], maxRetries: 1
            )
            let events = try await probe.invoke(dev)
            if probe.stream { expectEqual(events, 1, "\(label)") }
            let calls = StubURLProtocol.calls
            expectEqual(calls.count, 1, "\(label)")
            expectEqual(calls.first?.method, probe.verb, "\(label)")
            expectEqual(calls.first?.url, "https://api.test/dev\(probe.path)", "\(label)")
            if probe.hasBody { expectEqual(calls.first?.json?["probe"], true, "\(label)") }
        }
    }
}
