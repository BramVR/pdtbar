import Foundation
import os

/// Offline transport for tests and scripted smokes. A request nothing in the script answers
/// throws `ScriptError.unscriptedRequest`. A key scripted more than once answers its requests
/// in script order.
public final class ScriptedPDTHTTPTransport: PDTHTTPTransport, Sendable {
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

    private struct State {
        var script: [(request: Request, replies: [Reply])]
        var recorded: [URLRequest] = []
        var errors: [ScriptError] = []
        var pendingInitialDelay: TimeInterval
    }

    private let state: OSAllocatedUnfairLock<State>

    /// `initialDelaySeconds` holds the first request; cancellation ends the wait.
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
        state = OSAllocatedUnfairLock(initialState: State(script: script, pendingInitialDelay: max(0, initialDelaySeconds)))
    }

    public var requests: [URLRequest] {
        state.withLock { $0.recorded }
    }

    public var scriptErrors: [ScriptError] {
        state.withLock { $0.errors }
    }

    public var unusedReplies: [Request] {
        state.withLock { state in
            state.script.flatMap { entry in Array(repeating: entry.request, count: entry.replies.count) }
        }
    }

    public func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        try waitForInitialDelay(cancellation: cancellation)
        let reply = try state.withLock { state -> Reply in
            state.recorded.append(request)
            let matches = state.script.indices.filter { state.script[$0].request.matches(request) }
            let sent = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"
            guard matches.count < 2 else {
                state.errors.append(.ambiguousRequest(sent))
                throw ScriptError.ambiguousRequest(sent)
            }
            guard let index = matches.first, !state.script[index].replies.isEmpty else {
                state.errors.append(.unscriptedRequest(sent))
                throw ScriptError.unscriptedRequest(sent)
            }
            return state.script[index].replies.removeFirst()
        }
        switch reply {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, response)
        case let .failure(code):
            throw URLError(code)
        }
    }

    private func waitForInitialDelay(cancellation: PDTCancellation?) throws {
        let delay = state.withLock { state in
            defer { state.pendingInitialDelay = 0 }
            return state.pendingInitialDelay
        }
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            if cancellation?.isCancelled == true {
                throw URLError(.cancelled)
            }
            Thread.sleep(forTimeInterval: min(0.05, max(0, deadline.timeIntervalSinceNow)))
        }
    }
}
