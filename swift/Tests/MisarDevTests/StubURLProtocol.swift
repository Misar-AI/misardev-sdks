import Foundation
@testable import MisarDev

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One request the stub saw.
struct RecordedCall {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?

    var json: JSONValue? { body.flatMap { try? JSONValue.decode($0) } }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A scripted response. `pieces` are delivered as separate `didLoad` calls so a
/// frame boundary can land mid-chunk; `error` fails the request instead.
struct StubResponse {
    var status: Int = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var pieces: [String] = []
    var error: URLError? = nil

    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        var h = ["Content-Type": "application/json"]
        headers.forEach { h[$0.key] = $0.value }
        return StubResponse(status: status, headers: h, pieces: [body])
    }

    static func text(_ body: String, status: Int) -> StubResponse {
        StubResponse(status: status, headers: ["Content-Type": "text/plain"], pieces: [body])
    }

    static func sse(_ frames: [String]) -> StubResponse {
        StubResponse(status: 200, headers: ["Content-Type": "text/event-stream"], pieces: frames)
    }

    static func failure(_ code: URLError.Code = .networkConnectionLost) -> StubResponse {
        StubResponse(error: URLError(code))
    }
}

/// Intercepts every request on a session configured with it, records it, and
/// answers from a queue; the last response repeats once the queue runs dry.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var queue: [StubResponse] = []
    private static var lastResponse = StubResponse.json(#"{"ok":true}"#)
    private static var recorded: [RecordedCall] = []

    static func reset(_ responses: [StubResponse]) {
        lock.lock()
        defer { lock.unlock() }
        queue = responses
        lastResponse = responses.last ?? .json(#"{"ok":true}"#)
        recorded = []
    }

    static var calls: [RecordedCall] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private static func next(recording call: RecordedCall) -> StubResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(call)
        return queue.isEmpty ? lastResponse : queue.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let call = RecordedCall(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        )
        let stub = Self.next(recording: call)

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for piece in stub.pieces where !piece.isEmpty {
            client?.urlProtocol(self, didLoad: Data(piece.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

enum Fixtures {
    static let planLimitBody = #"""
    {"error":"API access requires the Pro plan or higher.","code":"plan_limit_exceeded","requiredPlan":"pro",
     "upgrade":{"product":"dev","product_name":"Misar.Dev","reason":"feature_locked","feature":"api_access",
     "feature_label":"API access","headline":"API access isn't included in your Starter plan.","usage":null,
     "current_plan":{"slug":"starter","name":"Starter"},"recommended_plan":"pro","plans":[],"topup":null,
     "overage":null,"trial":null,"cross_sell":[],
     "urls":{"pricing":"https://www.misar.dev/pricing","billing":"https://www.misar.dev/settings/billing",
     "docs":"https://docs.misar.io/dev/api","compare":"https://www.misar.dev/pricing#compare"},
     "cta":"Upgrade to Pro to continue."}}
    """#

    static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// A client against `https://api.test/dev` answering from `responses`.
    static func client(_ responses: [StubResponse], maxRetries: Int = 3) throws -> MisarDevClient {
        StubURLProtocol.reset(responses)
        return try MisarDevClient(
            apiKey: "mdk_test_key",
            baseURL: "https://api.test/dev",
            maxRetries: maxRetries,
            session: stubbedSession()
        )
    }
}
