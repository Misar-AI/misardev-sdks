import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The MisarDev API client.
///
/// Every resource (`projects`, `templates`, `chat`, …) is generated from the
/// API's route tree, so it always matches what the server exposes. The client
/// authenticates with your account API key (`mdk_…`) and nothing else.
///
/// ```swift
/// let dev = try MisarDevClient()            // reads MISARDEV_API_KEY
/// let projects = try await dev.projects.list()
/// ```
public final class MisarDevClient: @unchecked Sendable {
    /// Default API base URL.
    public static let defaultBaseURL = Transport.defaultBaseURL

    /// The SDK version sent in `X-Misar-SDK`.
    public static let version = Transport.sdkVersion

    let transport: Transport

    /// Create a client.
    ///
    /// - Parameters:
    ///   - apiKey: Your `mdk_…` key. When nil or empty, `MISARDEV_API_KEY` is used.
    ///   - baseURL: Defaults to `MISARDEV_BASE_URL`, else `https://api.misar.io/dev`.
    ///   - maxRetries: Total attempts for a retryable failure. Default 3.
    ///   - timeout: Per-request timeout in seconds. Default 60 — builds and AI calls are slow.
    ///   - session: Inject a `URLSession` (tests, proxies). Streams reuse its configuration.
    ///   - headers: Extra headers sent with every request.
    /// - Throws: ``MisarDevError`` when no API key was supplied or found in the environment.
    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        maxRetries: Int = 3,
        timeout: TimeInterval = 60,
        session: URLSession = .shared,
        headers: [String: String] = [:]
    ) throws {
        let env = ProcessInfo.processInfo.environment
        let key = (apiKey?.isEmpty == false ? apiKey : env["MISARDEV_API_KEY"]) ?? ""
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MisarDevError(
                status: 0,
                message: "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. "
                    + "Create one at https://www.misar.dev/settings/api-keys.",
                code: "missing_api_key"
            )
        }
        let base: String
        if let baseURL, !baseURL.isEmpty {
            base = baseURL
        } else if let fromEnv = env["MISARDEV_BASE_URL"], !fromEnv.isEmpty {
            base = fromEnv
        } else {
            base = Transport.defaultBaseURL
        }
        transport = Transport(
            apiKey: key, baseURL: base, maxRetries: maxRetries, timeout: timeout,
            session: session, headers: headers
        )
    }

    /// The API base URL in use.
    public var baseURL: String { transport.baseURL }

    /// Total attempts for a retryable failure.
    public var maxRetries: Int { transport.maxRetries }

    /// Per-request timeout, in seconds.
    public var timeout: TimeInterval { transport.timeout }

    /// Call any route directly, for routes the SDK does not wrap yet:
    /// `try await dev.request("GET", "/usage", query: ["days": 7])`.
    @discardableResult
    public func request(
        _ method: String,
        _ path: String,
        query: [String: JSONValue] = [:],
        body: JSONValue? = nil
    ) async throws -> JSONValue {
        try await transport.request(method, path, query: query, body: body)
    }

    /// Open any SSE route directly. A nil `terminator` reads to EOF.
    public func stream(
        _ method: String,
        _ path: String,
        query: [String: JSONValue] = [:],
        body: JSONValue? = nil,
        terminator: String? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        transport.stream(method, path, query: query, body: body, terminator: terminator)
    }

    /// Walk every page of an offset-paginated list. See ``Pagination``.
    public func paginate(
        pageSize: Int = 50,
        maxItems: Int? = nil,
        _ fetchPage: @escaping @Sendable (_ offset: Int, _ limit: Int) async throws -> JSONValue
    ) -> AsyncThrowingStream<JSONValue, Error> {
        MisarDev.paginate(pageSize: pageSize, maxItems: maxItems, fetchPage)
    }
}
