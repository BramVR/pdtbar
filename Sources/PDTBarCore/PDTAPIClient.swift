import Foundation

/// The read-only PDT REST resources PDTBar may request. Every case is a `GET`;
/// there is no way to name a write endpoint or another origin.
public enum PDTAPIResource: Equatable, Sendable {
    case holdings(date: String? = nil)
    case distributions
    case xRay
    case calendarEvents(dateFrom: String, dateTo: String)
    case dividends(dateFrom: String? = nil, dateTo: String? = nil)
    case portfolios(dateFrom: String, dateTo: String)
    case pricesBatch(symbolQuoteIds: [Int], dateFrom: String, dateTo: String)
    case symbolQuotes(symbolId: Int)
    case performance(dateFrom: String, dateTo: String)
    case gains(dateFrom: String, dateTo: String)
    case me
    case personalAccessTokens

    public static let pricesBatchLimit = 50

    enum Pagination: Equatable {
        case none
        case pages
        case offset
    }

    var endpoint: PDTAPIEndpoint {
        switch self {
        case .holdings: .holdings
        case .distributions: .distributions
        case .xRay: .xRay
        case .calendarEvents: .calendarEvents
        case .dividends: .dividends
        case .portfolios: .portfolios
        case .pricesBatch: .pricesBatch
        case .symbolQuotes: .symbolQuotes
        case .performance: .performance
        case .gains: .gains
        case .me: .me
        case .personalAccessTokens: .personalAccessTokens
        }
    }

    var path: String { endpoint.rawValue }

    var pagination: Pagination {
        switch self {
        case .calendarEvents, .dividends, .portfolios, .symbolQuotes: .pages
        case .xRay: .offset
        default: .none
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .holdings(date):
            return optionalItems(["date": date])
        case let .dividends(dateFrom, dateTo):
            return optionalItems(["dateFrom": dateFrom, "dateTo": dateTo])
        case let .calendarEvents(dateFrom, dateTo),
             let .portfolios(dateFrom, dateTo),
             let .performance(dateFrom, dateTo),
             let .gains(dateFrom, dateTo):
            return [URLQueryItem(name: "dateFrom", value: dateFrom), URLQueryItem(name: "dateTo", value: dateTo)]
        case let .pricesBatch(symbolQuoteIds, dateFrom, dateTo):
            // PDT is a Laravel API; its docs pass arrays as `name[]=` (see `fields[]`).
            return symbolQuoteIds.map { URLQueryItem(name: "symbolQuoteIds[]", value: String($0)) }
                + [URLQueryItem(name: "dateFrom", value: dateFrom), URLQueryItem(name: "dateTo", value: dateTo)]
        case let .symbolQuotes(symbolId):
            return [URLQueryItem(name: "symbolId", value: String(symbolId))]
        case .distributions, .xRay, .me, .personalAccessTokens:
            return []
        }
    }

    var isValid: Bool {
        if case let .pricesBatch(ids, _, _) = self {
            return (1...Self.pricesBatchLimit).contains(ids.count)
        }
        return true
    }

    private func optionalItems(_ values: KeyValuePairs<String, String?>) -> [URLQueryItem] {
        values.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }
}

/// A PDT REST endpoint with no request data: the raw value is the path under
/// `/v1/`. `PDTAPIResource.path` is derived from it, so the endpoint a
/// diagnostic names and the path requested cannot drift.
public enum PDTAPIEndpoint: String, Codable, Equatable, Sendable, CaseIterable {
    case holdings = "portfolio/holdings"
    case distributions = "portfolio/distributions"
    case xRay = "x-ray"
    case calendarEvents = "calendar-events"
    case dividends
    case portfolios
    case pricesBatch = "prices/batch"
    case symbolQuotes = "symbol-quotes"
    case performance = "portfolio/performance"
    case gains = "portfolio/gains"
    case me
    case personalAccessTokens = "personal-access-tokens"
}

/// A bearer token. It never prints: `description`, `debugDescription`, and
/// `Mirror` are redacted, and `fingerprint` is the only diagnostic view.
public struct PDTAPIToken: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let secret: String

    public init(_ secret: String) {
        self.secret = secret
    }

    public init(from decoder: Decoder) throws {
        secret = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(secret)
    }

    public var fingerprint: PDTSecretFingerprint { PDTSecretFingerprint(secret) }
    public var description: String { "PDTAPIToken(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// Supplies the bearer token per request. Production backs this with
/// `PDTConnection` (ADR-0002); tests and smokes may use `InMemoryPDTAPITokenProvider`.
public protocol PDTAPITokenProvider: Sendable {
    func currentToken() throws -> PDTAPIToken
    /// PDT answered `401 TOKEN_INVALID` for `token`. Return true to resend the
    /// request once with `currentToken()`.
    func shouldRetry(afterRejecting token: PDTAPIToken, reason: String?) throws -> Bool
}

public extension PDTAPITokenProvider {
    func shouldRetry(afterRejecting _: PDTAPIToken, reason _: String?) throws -> Bool {
        false
    }
}

public struct InMemoryPDTAPITokenProvider: PDTAPITokenProvider {
    public var token: PDTAPIToken?

    public init(token: PDTAPIToken?) {
        self.token = token
    }

    public func currentToken() throws -> PDTAPIToken {
        guard let token else {
            throw PDTAPIError.missingToken
        }
        return token
    }
}

public enum PDTAPIError: Error, Equatable, Sendable {
    case missingToken
    case invalidRequest
    case unauthenticated
    /// `reason` is PDT's `details.reason`: `invalid`, `expired`, or `revoked`.
    case tokenInvalid(reason: String?)
    case insufficientScope
    case apiAccessPaused
    case forbidden
    case notFound
    case validationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, retryAfter: TimeInterval?)
    case unexpectedStatus(Int)
    case transport(code: Int)
    case invalidResponse
    case paginationStalled
    case paginationLimitExceeded
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .server:
            true
        case let .transport(code):
            Self.transientTransportCodes.contains(code)
        default:
            false
        }
    }

    var retryAfter: TimeInterval? {
        switch self {
        case let .rateLimited(retryAfter), let .server(_, retryAfter):
            retryAfter
        default:
            nil
        }
    }

    private static let transientTransportCodes: Set<Int> = [
        URLError.timedOut.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.dnsLookupFailed.rawValue,
    ]

    static func classify(status: Int, body: Data, headers: [String: String], now: Date) -> PDTAPIError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        let code = envelope?.error.code
        switch status {
        case 401:
            if code == "TOKEN_INVALID" {
                return .tokenInvalid(reason: envelope?.error.details?.reason)
            }
            return .unauthenticated
        case 403:
            switch code {
            case "INSUFFICIENT_SCOPE": return .insufficientScope
            case "API_ACCESS_PAUSED": return .apiAccessPaused
            default: return .forbidden
            }
        case 404:
            return .notFound
        case 422:
            return .validationFailed
        case 429:
            return .rateLimited(retryAfter: retryAfter(headers["retry-after"], now: now))
        case 500...599:
            return .server(status: status, retryAfter: retryAfter(headers["retry-after"], now: now))
        default:
            return .unexpectedStatus(status)
        }
    }

    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    /// The trace id of an error response: `X-Request-Id`, else `error.traceId`.
    static func traceID(body: Data, headers: [String: String]) -> PDTTraceID? {
        PDTTraceID(headers["x-request-id"])
            ?? PDTTraceID((try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error.traceId)
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            struct Details: Decodable {
                var reason: String?
            }

            var code: String
            var details: Details?
            var traceId: String?
        }

        var error: Body
    }
}

public struct PDTAPIRequestPolicy: Sendable {
    public var maxAttempts: Int
    public var baseBackoff: TimeInterval
    /// Longest wait PDTBar accepts before a retry. A longer `Retry-After`
    /// fails the request instead of stalling the refresh.
    public var maxRetryDelay: TimeInterval
    public var requestTimeout: TimeInterval
    public var pageSize: Int
    public var maxPages: Int
    public var maxConcurrentRequests: Int

    public init(
        maxAttempts: Int = 3,
        baseBackoff: TimeInterval = 1,
        maxRetryDelay: TimeInterval = 30,
        requestTimeout: TimeInterval = 20,
        pageSize: Int = 100,
        maxPages: Int = 50,
        maxConcurrentRequests: Int = 4
    ) {
        self.maxAttempts = maxAttempts
        self.baseBackoff = baseBackoff
        self.maxRetryDelay = maxRetryDelay
        self.requestTimeout = requestTimeout
        self.pageSize = pageSize
        self.maxPages = maxPages
        self.maxConcurrentRequests = maxConcurrentRequests
    }
}

public protocol PDTHTTPTransport: Sendable {
    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse)
}

extension PDTHTTPTransport {
    func sendClassifyingFailures(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        do {
            return try send(request, cancellation: cancellation)
        } catch let error as PDTAPIError {
            throw error
        } catch let error as URLError {
            throw error.code == .cancelled ? PDTAPIError.cancelled : PDTAPIError.transport(code: error.code.rawValue)
        } catch {
            throw PDTAPIError.transport(code: URLError.unknown.rawValue)
        }
    }
}

extension HTTPURLResponse {
    var lowercasedHeaders: [String: String] {
        Dictionary(
            allHeaderFields.compactMap { key, value in
                (key as? String).map { ($0.lowercased(), "\(value)") }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// PDT sits behind Cloudflare, which rejects some default user agents (error 1010).
enum PDTUserAgent {
    static let value: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "pdtbar/\(version ?? "dev")"
    }()
}

public protocol PDTAPISleeper: Sendable {
    func sleep(seconds: TimeInterval, cancellation: PDTCancellation?) throws
}

public struct ThreadPDTAPISleeper: PDTAPISleeper {
    public init() {}

    public func sleep(seconds: TimeInterval, cancellation: PDTCancellation?) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cancellation?.isCancelled == true {
                throw PDTAPIError.cancelled
            }
            Thread.sleep(forTimeInterval: min(0.1, deadline.timeIntervalSinceNow))
        }
    }
}

/// Read-only PDT REST client: `GET` only, bearer token only to the PDT API
/// origin, typed errors, bounded retries, pagination, and no response logging.
/// A successful call and the HTTP requests it sent, retries and pages included.
public struct PDTAPIResult<Value> {
    public let value: Value
    public let attemptCount: Int
}

/// A failed call and the HTTP requests it sent before failing, retries and
/// pages included. `underlyingError` is the `PDTAPIError` the plain calls throw.
public struct PDTAPIRequestFailure: Error, CustomStringConvertible {
    public let underlyingError: any Error
    public let attemptCount: Int
    /// The trace id of the response that failed the call, when PDT sent one.
    public let traceID: PDTTraceID?

    public var description: String {
        "\(underlyingError) after \(attemptCount) request(s)"
    }
}

public struct PDTAPIClient: Sendable {
    public static let baseURL = URL(string: "https://api.portfoliodividendtracker.com/v1/")!

    private let transport: any PDTHTTPTransport
    private let tokenProvider: any PDTAPITokenProvider
    private let policy: PDTAPIRequestPolicy
    private let sleeper: any PDTAPISleeper
    private let now: @Sendable () -> Date
    private let gate: DispatchSemaphore

    public init(
        transport: any PDTHTTPTransport,
        tokenProvider: any PDTAPITokenProvider,
        policy: PDTAPIRequestPolicy = PDTAPIRequestPolicy(),
        sleeper: any PDTAPISleeper = ThreadPDTAPISleeper(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.policy = policy
        self.sleeper = sleeper
        self.now = now
        gate = DispatchSemaphore(value: max(1, policy.maxConcurrentRequests))
    }

    /// One response body. For paged resources this is the first page only.
    public func get(_ resource: PDTAPIResource, cancellation: PDTCancellation? = nil) throws -> Data {
        try withoutAttemptCount {
            try countingRequests { log in
                try send(resource, extraQuery: [], cancellation: cancellation, log: &log)
            }
        }
    }

    /// Every row of a list resource, following page or offset pagination.
    /// Rows come from `data` (lists), or `data.items` (x-ray).
    public func getAll<Row: Decodable>(
        _ resource: PDTAPIResource,
        as type: Row.Type = Row.self,
        cancellation: PDTCancellation? = nil
    ) throws -> [Row] {
        try withoutAttemptCount {
            try getAllReportingAttempts(resource, as: type, cancellation: cancellation)
        }
    }

    /// `get` decoded as `Body`, with the request count. Failures, decoding
    /// included, throw `PDTAPIRequestFailure`.
    public func getReportingAttempts<Body: Decodable>(
        _ resource: PDTAPIResource,
        as _: Body.Type,
        cancellation: PDTCancellation? = nil
    ) throws -> PDTAPIResult<Body> {
        try countingRequests { log in
            try decode(Body.self, from: send(resource, extraQuery: [], cancellation: cancellation, log: &log))
        }
    }

    /// `getAll` with the request count. Failures throw `PDTAPIRequestFailure`.
    public func getAllReportingAttempts<Row: Decodable>(
        _ resource: PDTAPIResource,
        as _: Row.Type = Row.self,
        cancellation: PDTCancellation? = nil
    ) throws -> PDTAPIResult<[Row]> {
        try countingRequests { log in
            switch resource.pagination {
            case .none:
                try decode(ListPage<Row>.self, from: send(resource, extraQuery: [], cancellation: cancellation, log: &log)).data
            case .pages:
                try collectPages(resource, cancellation: cancellation, log: &log)
            case .offset:
                try collectOffsets(resource, cancellation: cancellation, log: &log)
            }
        }
    }

    /// What one call has sent so far. `traceID` belongs to the latest request only.
    private struct RequestLog {
        var sent = 0
        var traceID: PDTTraceID?
    }

    private func countingRequests<Value>(_ call: (inout RequestLog) throws -> Value) throws -> PDTAPIResult<Value> {
        var log = RequestLog()
        do {
            let value = try call(&log)
            return PDTAPIResult(value: value, attemptCount: log.sent)
        } catch {
            throw PDTAPIRequestFailure(underlyingError: error, attemptCount: log.sent, traceID: log.traceID)
        }
    }

    private func withoutAttemptCount<Value>(_ call: () throws -> PDTAPIResult<Value>) throws -> Value {
        do {
            return try call().value
        } catch let failure as PDTAPIRequestFailure {
            throw failure.underlyingError
        }
    }

    private func collectPages<Row: Decodable>(
        _ resource: PDTAPIResource,
        cancellation: PDTCancellation?,
        log: inout RequestLog
    ) throws -> [Row] {
        var rows: [Row] = []
        for page in 1...max(1, policy.maxPages) {
            let body = try send(
                resource,
                extraQuery: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "perPage", value: String(policy.pageSize)),
                ],
                cancellation: cancellation,
                log: &log
            )
            let decoded = try decode(ListPage<Row>.self, from: body)
            guard let meta = decoded.meta else {
                throw PDTAPIError.invalidResponse
            }
            guard meta.currentPage == page else {
                throw PDTAPIError.paginationStalled
            }
            rows += decoded.data
            if page >= meta.lastPage {
                return rows
            }
            if decoded.data.isEmpty {
                throw PDTAPIError.paginationStalled
            }
        }
        throw PDTAPIError.paginationLimitExceeded
    }

    private func collectOffsets<Row: Decodable>(
        _ resource: PDTAPIResource,
        cancellation: PDTCancellation?,
        log: inout RequestLog
    ) throws -> [Row] {
        var rows: [Row] = []
        for _ in 1...max(1, policy.maxPages) {
            let body = try send(
                resource,
                extraQuery: [
                    URLQueryItem(name: "limit", value: String(policy.pageSize)),
                    URLQueryItem(name: "offset", value: String(rows.count)),
                ],
                cancellation: cancellation,
                log: &log
            )
            let decoded = try decode(OffsetPage<Row>.self, from: body).data
            rows += decoded.items
            if !decoded.hasMore {
                return rows
            }
            if decoded.items.isEmpty {
                throw PDTAPIError.paginationStalled
            }
        }
        throw PDTAPIError.paginationLimitExceeded
    }

    private func send(
        _ resource: PDTAPIResource,
        extraQuery: [URLQueryItem],
        cancellation: PDTCancellation?,
        log: inout RequestLog
    ) throws -> Data {
        guard resource.isValid else {
            throw PDTAPIError.invalidRequest
        }
        var components = URLComponents(url: Self.baseURL.appending(path: resource.path), resolvingAgainstBaseURL: false)!
        let query = resource.queryItems + extraQuery
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!

        var attempt = 1
        var retriedRejectedToken = false
        while true {
            if cancellation?.isCancelled == true {
                throw PDTAPIError.cancelled
            }
            let token = try tokenProvider.currentToken()
            do {
                return try sendOnce(url: url, token: token, cancellation: cancellation, log: &log)
            } catch let PDTAPIError.tokenInvalid(reason) where !retriedRejectedToken {
                guard try tokenProvider.shouldRetry(afterRejecting: token, reason: reason) else {
                    throw PDTAPIError.tokenInvalid(reason: reason)
                }
                retriedRejectedToken = true
            } catch let error as PDTAPIError where error.isRetryable && attempt < policy.maxAttempts {
                let delay = retryDelay(for: error, attempt: attempt)
                guard delay <= policy.maxRetryDelay else {
                    throw error
                }
                try sleeper.sleep(seconds: delay, cancellation: cancellation)
                attempt += 1
            }
        }
    }

    private func sendOnce(url: URL, token: PDTAPIToken, cancellation: PDTCancellation?, log: inout RequestLog) throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: policy.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PDTUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token.secret)", forHTTPHeaderField: "Authorization")

        while gate.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation?.isCancelled == true {
                throw PDTAPIError.cancelled
            }
        }
        defer { gate.signal() }
        if cancellation?.isCancelled == true {
            throw PDTAPIError.cancelled
        }
        log.sent += 1
        log.traceID = nil
        let (data, response) = try transport.sendClassifyingFailures(request, cancellation: cancellation)
        if (200..<300).contains(response.statusCode) {
            return data
        }
        let headers = response.lowercasedHeaders
        log.traceID = PDTAPIError.traceID(body: data, headers: headers)
        throw PDTAPIError.classify(status: response.statusCode, body: data, headers: headers, now: now())
    }

    private func retryDelay(for error: PDTAPIError, attempt: Int) -> TimeInterval {
        error.retryAfter ?? min(policy.maxRetryDelay, policy.baseBackoff * pow(2, Double(attempt - 1)))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PDTAPIError.invalidResponse
        }
    }

    private struct ListPage<Row: Decodable>: Decodable {
        struct Meta: Decodable {
            var currentPage: Int
            var lastPage: Int
        }

        var data: [Row]
        var meta: Meta?

        enum CodingKeys: String, CodingKey {
            case data
            case meta
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try container.decode([Row].self, forKey: .data)
            // Unpaged list endpoints send no meta, or an empty `meta: []`.
            meta = try? container.decodeIfPresent(Meta.self, forKey: .meta)
        }
    }

    private struct OffsetPage<Row: Decodable>: Decodable {
        struct Window: Decodable {
            var items: [Row]
            var hasMore: Bool
        }

        var data: Window
    }
}

/// Production transport. Sends `GET`s, plus the `POST` to PDT's token endpoint,
/// and refuses every redirect so a token can never follow a response to
/// another origin.
public final class URLSessionPDTHTTPTransport: NSObject, PDTHTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        // Copy first: URLSessionConfiguration is a reference type the caller may reuse.
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.configuration = configuration
    }

    public func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        guard request.httpMethod == "GET" || PDTOAuthEndpoints.isTokenRequest(request) else {
            throw PDTAPIError.invalidRequest
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let result = TransportResult()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            result.set(data: data, response: response, error: error)
            done.signal()
        }
        task.resume()
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation?.isCancelled == true {
                task.cancel()
            }
        }
        return try result.unwrap()
    }

    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private final class TransportResult: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var response: URLResponse?
        private var error: Error?

        func set(data: Data?, response: URLResponse?, error: Error?) {
            lock.lock()
            defer { lock.unlock() }
            self.data = data
            self.response = response
            self.error = error
        }

        func unwrap() throws -> (Data, HTTPURLResponse) {
            lock.lock()
            defer { lock.unlock() }
            if let error {
                throw error
            }
            guard let response = response as? HTTPURLResponse else {
                throw PDTAPIError.invalidResponse
            }
            return (data ?? Data(), response)
        }
    }
}

/// Offline transport for tests and scripted smokes: replays queued responses
/// and records every request it receives. It never touches the network.
public final class ScriptedPDTHTTPTransport: PDTHTTPTransport, @unchecked Sendable {
    public enum Reply {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [URLRequest] = []
    private var pendingInitialDelay: TimeInterval

    /// `initialDelaySeconds` holds the first request, so scripted smokes can
    /// observe the app while a refresh is in flight. Cancellation ends the wait.
    public init(_ replies: [Reply], initialDelaySeconds: TimeInterval = 0) {
        self.replies = replies
        pendingInitialDelay = max(0, initialDelaySeconds)
    }

    public var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        try waitForInitialDelay(cancellation: cancellation)
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !replies.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        switch replies.removeFirst() {
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
