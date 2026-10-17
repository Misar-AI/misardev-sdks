import Foundation

// On Linux, URLSession/URLRequest/HTTPURLResponse live in FoundationNetworking.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP transport shared by the generated resource layer.
///
/// Everything the SDK does goes through here, and it authenticates exactly one
/// way: the account API key (`mdk_…`), sent as `Authorization: Bearer`. What a
/// key may do — and how much of it — is decided server-side from the
/// subscription behind that key; the SDK carries the key and surfaces the answer.
///
/// Requests use `URLSession.dataTask` with a completion handler (and streams a
/// data delegate) rather than the async `data(for:)`/`bytes(for:)` helpers,
/// which swift-corelibs-foundation lacks — one implementation on every platform.
final class Transport: @unchecked Sendable {
    static let defaultBaseURL = "https://api.misar.io/dev"
    static let sdkVersion = "1.0.0"
    static let sdkHeader = "misardev-swift/\(sdkVersion)"

    /// Statuses worth retrying. 429 only when it is NOT a plan limit.
    static let retryable: Set<Int> = [429, 500, 502, 503, 504]

    /// A 5xx or a dropped connection on a POST may already have done its work —
    /// started a build, charged an allowance. Only requests that are safe to
    /// repeat are retried on those; a 429 is always safe because the server
    /// refused it before doing anything.
    static let idempotent: Set<String> = ["GET", "HEAD", "OPTIONS", "PUT", "DELETE"]

    static let maxBackoff: TimeInterval = 60

    let apiKey: String
    let baseURL: String
    let maxRetries: Int
    let timeout: TimeInterval
    let session: URLSession
    let extraHeaders: [String: String]

    init(apiKey: String, baseURL: String, maxRetries: Int, timeout: TimeInterval, session: URLSession,
         headers: [String: String]) {
        self.apiKey = apiKey
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base
        self.maxRetries = max(1, maxRetries)
        self.timeout = timeout
        self.session = session
        self.extraHeaders = headers
    }

    // MARK: Helpers used by the generated layer

    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Path-segment / query-component encoding: `a b/c` → `a%20b%2Fc`.
    static func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// `?a=b&c=d`, keys sorted for stable URLs: nulls dropped, booleans lowercase, everything encoded.
    static func buildQuery(_ query: [String: JSONValue]) -> String {
        let parts: [String] = query.keys.sorted().compactMap { key in
            guard let value = query[key], let s = stringify(value) else { return nil }
            return "\(encodePath(key))=\(encodePath(s))"
        }
        return parts.isEmpty ? "" : "?" + parts.joined(separator: "&")
    }

    static func stringify(_ value: JSONValue) -> String? {
        switch value {
        case .null: return nil
        case .bool(let b): return b ? "true" : "false"
        case .string(let s): return s
        case .number(let n):
            if n.rounded() == n, abs(n) < 9.2e18 { return String(Int64(n)) }
            return String(n)
        case .array, .object: return value.jsonString
        }
    }

    // MARK: Backoff

    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// Exponential backoff with jitter, but honour `Retry-After` (seconds or HTTP-date), capped at 60s.
    static func backoff(attempt: Int, retryAfter: String?) -> TimeInterval {
        if let raw = retryAfter?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            if let seconds = Double(raw), seconds >= 0 { return min(seconds, maxBackoff) }
            if let date = httpDate.date(from: raw) {
                return min(max(0, date.timeIntervalSinceNow), maxBackoff)
            }
        }
        let base = 0.25 * pow(2.0, Double(attempt))
        return min(base + Double.random(in: 0...(base * 0.25)), maxBackoff)
    }

    /// `Retry-After` as whole seconds: numeric, or an HTTP-date converted to seconds from now.
    static func retryAfterSeconds(_ value: String?) -> Int? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return Int(seconds.rounded(.up)) }
        if let date = httpDate.date(from: raw) { return max(0, Int(date.timeIntervalSinceNow.rounded(.up))) }
        return nil
    }

    // MARK: Bodies and error mapping

    /// Empty → nil, JSON → value, anything else → `.string`.
    static func decodeBody(_ data: Data) -> JSONValue? {
        if data.isEmpty { return nil }
        if let value = try? JSONValue.decode(data) { return value }
        return .string(String(decoding: data, as: UTF8.self))
    }

    /// Pull a human message out of the API's several error shapes.
    static func messageOf(_ body: JSONValue?, raw: String, fallback: String) -> String {
        if case .object = body {
            if let s = body?["error"]?.stringValue { return s }
            // /v1/* answers in the OpenAI shape: { error: { message, type, code } }
            if let s = body?["error"]?["message"]?.stringValue { return s }
            if let s = body?["message"]?.stringValue { return s }
            return fallback
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(500))
    }

    static func codeOf(_ body: JSONValue?) -> String? {
        body?["code"]?.stringValue ?? body?["error"]?["code"]?.stringValue
    }

    /// True when a body is the plan-limit refusal (`code: "plan_limit_exceeded"`).
    static func isPlanLimitBody(_ body: JSONValue?) -> Bool {
        body?["code"]?.stringValue == "plan_limit_exceeded"
    }

    /// Case-insensitive header lookup that behaves the same on Darwin and Linux.
    static func header(_ response: HTTPURLResponse, _ name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, k.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String ?? "\(value)"
            }
        }
        return nil
    }

    /// Map an error response to the right typed error. Plan limits first, by `code`.
    static func errorFor(status: Int, data: Data, requestId: String?, retryAfter: String?) -> MisarDevError {
        let raw = String(decoding: data, as: UTF8.self)
        let body = decodeBody(data)
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        let message = messageOf(body, raw: raw, fallback: reason.isEmpty ? "HTTP \(status)" : reason)
        let code = codeOf(body)

        if isPlanLimitBody(body) {
            return PlanLimitError(
                status: status, message: message, body: body, rawBody: raw, requestId: requestId,
                offer: body?["upgrade"], retryAfter: retryAfterSeconds(retryAfter)
            )
        }
        switch status {
        case 400, 422:
            return ValidationError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        case 401:
            return AuthenticationError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        case 403:
            return PermissionDeniedError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        case 404:
            return NotFoundError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        case 409:
            return ConflictError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        case 429:
            return RateLimitError(
                status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId,
                retryAfter: retryAfterSeconds(retryAfter)
            )
        case 500...:
            return ServerError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        default:
            return MisarDevError(status: status, message: message, code: code, body: body, rawBody: raw, requestId: requestId)
        }
    }

    // MARK: Requests

    func makeRequest(_ method: String, _ path: String, query: [String: JSONValue], body: JSONValue?,
                     accept: String) throws -> URLRequest {
        let urlString = baseURL + path + Transport.buildQuery(query)
        guard let url = URL(string: urlString) else {
            throw MisarDevError(status: 0, message: "Invalid URL: \(urlString)", code: "invalid_url")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Transport.sdkHeader, forHTTPHeaderField: "X-Misar-SDK")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = try body.jsonData() }
        return request
    }

    /// One round trip via a completion-handler data task (works on Linux), cancellable from the Task.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), http))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Send one request, retrying throttles and (for idempotent verbs) transient failures.
    func request(
        _ method: String,
        _ path: String,
        query: [String: JSONValue] = [:],
        body: JSONValue? = nil
    ) async throws -> JSONValue {
        let verb = method.uppercased()
        let request = try makeRequest(verb, path, query: query, body: body, accept: "application/json")

        var attempt = 0
        while true {
            defer { attempt += 1 }
            let last = attempt >= maxRetries - 1

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await send(request)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if !last && Transport.idempotent.contains(verb) {
                    try await sleep(Transport.backoff(attempt: attempt, retryAfter: nil))
                    continue
                }
                throw NetworkError(message: "Request to \(verb) \(path) failed: \(error.localizedDescription)",
                                   underlying: error)
            }

            let status = response.statusCode
            if (200..<300).contains(status) {
                if status == 204 { return .null }
                return Transport.decodeBody(data) ?? .null
            }

            // Read the body BEFORE deciding to retry: a 429 from the rate limiter
            // and a 429 from a spent plan allowance share a status, and only the
            // first is worth retrying.
            let retryAfter = Transport.header(response, "Retry-After")
            let error = Transport.errorFor(
                status: status, data: data,
                requestId: Transport.header(response, "x-request-id"), retryAfter: retryAfter
            )
            if error is PlanLimitError { throw error }

            let retryable = Transport.retryable.contains(status)
                && (status == 429 || Transport.idempotent.contains(verb))
            if retryable && !last {
                try await sleep(Transport.backoff(attempt: attempt, retryAfter: retryAfter))
                continue
            }
            throw error
        }
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        if seconds <= 0 { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Holds a data task so a Task cancellation handler can cancel it.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let cancelNow = cancelled
        lock.unlock()
        if cancelNow { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}
