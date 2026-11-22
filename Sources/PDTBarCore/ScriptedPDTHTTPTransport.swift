import Foundation

/// Offline transport for tests and scripted smokes. It answers each request
/// with the reply scripted for that request, never with a reply meant for
/// another one, and records every request it receives. It never touches the
/// network.
///
/// A request nothing in the script answers throws
/// `ScriptError.unscriptedRequest` instead of succeeding, so a wrong, extra,
/// or repeated request fails the way it would against PDT. A key scripted more
/// than once answers its requests in script order (a `429` then a `200`).
public final class ScriptedPDTHTTPTransport: PDTHTTPTransport, @unchecked Sendable {
    public enum Reply: Sendable {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    /// The request a reply answers, written `"<METHOD> <target>"`: `"GET /v1/x-ray"`,
    /// `"GET /v1/calendar-events?page=2"`. A target starting with `/` is on the
    /// PDT API origin; any other origin is written out in full. The request
    /// must carry every query item the key names and may carry others.
    public struct Request: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
        public let method: String
        let origin: String
        let path: String
        let query: [URLQueryItem]

        public init?(parsing text: String) {
            let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, parts[0] == parts[0].uppercased() else {
                return nil
            }
            let target = parts[1].hasPrefix("/") ? Self.apiOrigin + parts[1] : parts[1]
            guard let components = URLComponents(string: target), let origin = Self.origin(of: components) else {
                return nil
            }
            method = parts[0]
            self.origin = origin
            path = components.path
            query = components.queryItems ?? []
        }

        public init(stringLiteral value: String) {
            guard let request = Request(parsing: value) else {
                preconditionFailure("not a scripted request: \(value)")
            }
            self = request
        }

        public init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let request = Request(parsing: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a scripted request: \(text)"))
            }
            self = request
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }

        public var description: String {
            let target = origin == Self.apiOrigin ? path : origin + path
            let items = query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            return "\(method) \(target)\(items.isEmpty ? "" : "?" + items)"
        }

        public func matches(_ request: URLRequest) -> Bool {
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  (request.httpMethod ?? "GET") == method,
                  Self.origin(of: components) == origin,
                  components.path == path
            else {
                return false
            }
            let sent = components.queryItems ?? []
            return query.allSatisfy(sent.contains)
        }

        private static let apiOrigin = origin(of: URLComponents(url: PDTAPIClient.baseURL, resolvingAgainstBaseURL: false)!)!

        private static func origin(of components: URLComponents) -> String? {
            guard let scheme = components.scheme, let host = components.host else {
                return nil
            }
            return "\(scheme)://\(host)\(components.port.map { ":\($0)" } ?? "")"
        }
    }

    public enum ScriptError: Error, Equatable, Sendable, CustomStringConvertible {
        /// No scripted key matches the request, or its replies are used up.
        case unscriptedRequest(String)
        /// More than one scripted key matches; name them apart with a query item.
        case ambiguousRequest(String)

        public var description: String {
            switch self {
            case let .unscriptedRequest(request): "unscripted request: \(request)"
            case let .ambiguousRequest(request): "request matches more than one scripted key: \(request)"
            }
        }
    }

    /// The reply bodies of one scenario under `docs/pdt/fixtures/api`, each
    /// keyed by the request its `provenance.json` entry says it answers.
    public static func fixtureReplies(scenario: String, apiFixtures: URL) throws -> [(request: Request, body: Data)] {
        struct Provenance: Decodable {
            struct Entry: Decodable {
                var file: String
                var request: Request
            }

            var scenarios: [String: [Entry]]
        }
        let provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: apiFixtures.appending(path: "provenance.json")))
        guard let entries = provenance.scenarios[scenario] else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: apiFixtures.appending(path: scenario).path])
        }
        return try entries.map { ($0.request, try Data(contentsOf: apiFixtures.appending(path: scenario).appending(path: $0.file))) }
    }

    private let lock = NSLock()
    private var script: [(request: Request, replies: [Reply])]
    private var recorded: [URLRequest] = []
    private var errors: [ScriptError] = []
    private var pendingInitialDelay: TimeInterval

    /// `initialDelaySeconds` holds the first request, so scripted smokes can
    /// observe the app while a refresh is in flight. Cancellation ends the wait.
    public convenience init(_ script: KeyValuePairs<Request, Reply>, initialDelaySeconds: TimeInterval = 0) {
        self.init(exchanges: script.map { ($0.key, $0.value) }, initialDelaySeconds: initialDelaySeconds)
    }

    public init(exchanges: [(Request, Reply)], initialDelaySeconds: TimeInterval = 0) {
        var script: [(request: Request, replies: [Reply])] = []
        for (request, reply) in exchanges {
            if let index = script.firstIndex(where: { $0.request == request }) {
                script[index].replies.append(reply)
            } else {
                script.append((request, [reply]))
            }
        }
        self.script = script
        pendingInitialDelay = max(0, initialDelaySeconds)
    }

    public var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Every `ScriptError` thrown so far. A client turns a thrown one into a
    /// transport failure, so tests read it here.
    public var scriptErrors: [ScriptError] {
        lock.lock()
        defer { lock.unlock() }
        return errors
    }

    /// Scripted replies no request asked for, one key per reply.
    public var unusedReplies: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return script.flatMap { entry in Array(repeating: entry.request, count: entry.replies.count) }
    }

    public func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        try waitForInitialDelay(cancellation: cancellation)
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        let matches = script.indices.filter { script[$0].request.matches(request) }
        let sent = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"
        guard matches.count < 2 else {
            errors.append(.ambiguousRequest(sent))
            throw ScriptError.ambiguousRequest(sent)
        }
        guard let index = matches.first, !script[index].replies.isEmpty else {
            errors.append(.unscriptedRequest(sent))
            throw ScriptError.unscriptedRequest(sent)
        }
        switch script[index].replies.removeFirst() {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, response)
        case let .failure(code):
            throw URLError(code)
        }
    }

    private func waitForInitialDelay(cancellation: PDTCancellation?) throws {
        lock.lock()
        let delay = pendingInitialDelay
        pendingInitialDelay = 0
        lock.unlock()
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if cancellation?.isCancelled == true {
                throw URLError(.cancelled)
            }
            Thread.sleep(forTimeInterval: min(0.05, max(0, deadline.timeIntervalSinceNow)))
        }
    }
}
