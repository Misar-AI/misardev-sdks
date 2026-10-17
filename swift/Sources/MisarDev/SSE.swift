import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One Server-Sent Event.
public struct SSEEvent: Equatable, Sendable {
    /// The `event:` name, when the server sends one.
    public let event: String?
    /// The `data:` payload, JSON-decoded when it is JSON, otherwise `.string`.
    public let data: JSONValue
    /// The `id:` field, when present.
    public let id: String?
    /// The `data:` payload exactly as received (multi-line data joined with `\n`).
    public let raw: String

    public init(event: String?, data: JSONValue, id: String?, raw: String) {
        self.event = event
        self.data = data
        self.id = id
        self.raw = raw
    }
}

/// Incremental `text/event-stream` parser.
///
/// Feed it bytes as they arrive; it splits frames on a blank line (`\n\n` or
/// `\r\n\r\n`), joins several `data:` lines with `\n`, strips one leading space
/// after the colon, skips `:` comment lines and captures `event:` / `id:`.
/// A frame with no `data:` line yields nothing.
public struct SSEParser: Sendable {
    public struct Frame: Equatable, Sendable {
        public let event: String?
        public let data: String
        public let id: String?
    }

    private var buffer = Data()

    public init() {}

    /// Append bytes and return every frame they complete.
    public mutating func push(_ chunk: Data) -> [Frame] {
        buffer.append(chunk)
        var frames: [Frame] = []
        while let range = nextBoundary() {
            let text = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let frame = SSEParser.parse(text) { frames.append(frame) }
        }
        return frames
    }

    /// The final, unterminated frame once the stream ends.
    public mutating func finish() -> Frame? {
        let text = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return SSEParser.parse(text)
    }

    private func nextBoundary() -> Range<Data.Index>? {
        let lf = buffer.range(of: Data("\n\n".utf8))
        let crlf = buffer.range(of: Data("\r\n\r\n".utf8))
        switch (lf, crlf) {
        case (nil, nil): return nil
        case (let l?, nil): return l
        case (nil, let c?): return c
        case (let l?, let c?): return l.lowerBound <= c.lowerBound ? l : c
        }
    }

    /// Parse the text of one complete frame.
    public static func parse(_ frame: String) -> Frame? {
        var event: String?
        var id: String?
        var data: [String] = []
        let normalized = frame.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty || line.hasPrefix(":") { continue }
            let field: String
            var value: String
            if let colon = line.firstIndex(of: ":") {
                field = String(line[..<colon])
                value = String(line[line.index(after: colon)...])
            } else {
                field = line
                value = ""
            }
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "data": data.append(value)
            case "event": event = value
            case "id": id = value
            default: break
            }
        }
        guard !data.isEmpty else { return nil }
        return Frame(event: event, data: data.joined(separator: "\n"), id: id)
    }

    /// JSON-decode a payload when possible, else keep it as `.string`.
    public static func decode(_ raw: String) -> JSONValue {
        (try? JSONValue.decode(Data(raw.utf8))) ?? .string(raw)
    }
}

/// Bridges `URLSession`'s delegate callbacks into closures. `URLSession.bytes(for:)`
/// would be simpler, but it does not exist in swift-corelibs-foundation; a data
/// delegate works on every platform.
final class SSEChunkDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onResponse: (HTTPURLResponse) -> Void
    private let onChunk: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(
        onResponse: @escaping (HTTPURLResponse) -> Void,
        onChunk: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.onResponse = onResponse
        self.onChunk = onChunk
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse { onResponse(http) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onChunk(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
    }
}

/// Mutable stream state, confined to the delegate's serial queue.
private final class SSEStreamState: @unchecked Sendable {
    var response: HTTPURLResponse?
    var parser = SSEParser()
    var errorBody = Data()
    var finished = false

    var status: Int { response?.statusCode ?? 0 }
}

extension Transport {
    /// Open a Server-Sent Events stream (`Accept: text/event-stream`) and yield each event.
    ///
    /// Never retried: a stream that fails mid-flight cannot be replayed without
    /// duplicating what the caller already consumed. The terminator payload
    /// (`[DONE]` on chat completions; `nil` = read to EOF) ends iteration and is
    /// never yielded. A frame carrying `code: "plan_limit_exceeded"` is raised as
    /// a ``PlanLimitError``.
    func stream(
        _ method: String,
        _ path: String,
        query: [String: JSONValue] = [:],
        body: JSONValue? = nil,
        terminator: String? = "[DONE]"
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let verb = method.uppercased()
        return AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try makeRequest(verb, path, query: query, body: body, accept: "text/event-stream")
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let state = SSEStreamState()
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1

            /// Yield one frame; returns false once the stream is over.
            func deliver(_ frame: SSEParser.Frame) -> Bool {
                if let terminator, frame.data.trimmingCharacters(in: .whitespaces) == terminator {
                    state.finished = true
                    continuation.finish()
                    return false
                }
                let data = SSEParser.decode(frame.data)
                // Other error frames are the stream's own business (the build
                // stream reports a failed step and carries on), so only the plan
                // refusal — which no amount of reading further will fix — is raised.
                if Transport.isPlanLimitBody(data) {
                    state.finished = true
                    let headers = state.response
                    continuation.finish(throwing: Transport.errorFor(
                        status: 402, data: Data(frame.data.utf8),
                        requestId: headers.flatMap { Transport.header($0, "x-request-id") },
                        retryAfter: headers.flatMap { Transport.header($0, "Retry-After") }
                    ))
                    return false
                }
                continuation.yield(SSEEvent(event: frame.event, data: data, id: frame.id, raw: frame.data))
                return true
            }

            let delegate = SSEChunkDelegate(
                onResponse: { http in state.response = http },
                onChunk: { chunk in
                    guard !state.finished else { return }
                    // A refusal body is JSON, not SSE: collect it and report it
                    // once the transfer ends.
                    guard (200..<300).contains(state.status) else {
                        state.errorBody.append(chunk)
                        return
                    }
                    for frame in state.parser.push(chunk) {
                        if !deliver(frame) { return }
                    }
                },
                onComplete: { error in
                    guard !state.finished else { return }
                    state.finished = true
                    if let error {
                        continuation.finish(throwing: NetworkError(
                            message: "Stream \(verb) \(path) failed: \(error.localizedDescription)",
                            underlying: error
                        ))
                        return
                    }
                    if let response = state.response, !(200..<300).contains(response.statusCode) {
                        continuation.finish(throwing: Transport.errorFor(
                            status: response.statusCode, data: state.errorBody,
                            requestId: Transport.header(response, "x-request-id"),
                            retryAfter: Transport.header(response, "Retry-After")
                        ))
                        return
                    }
                    // A trailing frame the server never closed with a blank line.
                    if let frame = state.parser.finish() {
                        state.finished = false
                        guard deliver(frame) else { return }
                        state.finished = true
                    }
                    continuation.finish()
                }
            )

            // The injected session's configuration (timeouts, proxies,
            // protocolClasses) applies to streams too.
            let streamSession = URLSession(
                configuration: session.configuration,
                delegate: delegate,
                delegateQueue: queue
            )
            let task = streamSession.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                // Invalidation waits for the delegate queue to drain, and the
                // stream normally finishes from inside a delegate callback on that
                // very queue — invalidating there would deadlock. Hand it off.
                DispatchQueue.global().async { streamSession.finishTasksAndInvalidate() }
            }
            task.resume()
        }
    }
}
