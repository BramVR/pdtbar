import Foundation
import Testing
import PDTBarCore

@Suite("PDT API client")
struct PDTAPIClientTests {
    @Test("Every resource is a GET to the PDT API origin with bearer auth")
    func everyResourceIsReadOnlyGETToPDTOrigin() throws {
        let resources: [PDTAPIResource] = [
            .holdings(), .distributions, .me, .personalAccessTokens,
            .performance(dateFrom: "2026-01-01", dateTo: "2026-11-09"),
            .gains(dateFrom: "2026-01-01", dateTo: "2026-11-09"),
            .pricesBatch(symbolQuoteIds: [7], dateFrom: "2026-10-01", dateTo: "2026-11-09"),
            .xRay,
            .calendarEvents(dateFrom: "2026-11-09", dateTo: "2027-01-08"),
            .dividends(),
            .portfolios(dateFrom: "2026-01-01", dateTo: "2026-11-09"),
            .symbolQuotes(symbolId: 3),
        ]
        let transport = ScriptedPDTHTTPTransport(resources.map { _ in ok(#"{"data":[]}"#) })
        let client = makeClient(transport)

        for resource in resources {
            _ = try client.get(resource)
        }

        #expect(transport.requests.count == resources.count)
        for request in transport.requests {
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.portfoliodividendtracker.com")
            #expect(request.url?.path.hasPrefix("/v1/") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pdt_test_secret")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        }
    }

    @Test("Paths and query strings match the PDT REST contract")
    func pathsAndQueryEncoding() throws {
        let transport = ScriptedPDTHTTPTransport(Array(repeating: ok(onePage), count: 4))
        let client = makeClient(transport)

        _ = try client.get(.holdings(date: "2026-11-01"))
        _ = try client.get(.pricesBatch(symbolQuoteIds: [11, 12], dateFrom: "2026-10-01", dateTo: "2026-11-09"))
        _ = try client.get(.dividends())
        let _: [Row] = try client.getAll(.calendarEvents(dateFrom: "2026-11-09", dateTo: "2027-01-08"))

        #expect(transport.requests.map { $0.url!.absoluteString } == [
            "https://api.portfoliodividendtracker.com/v1/portfolio/holdings?date=2026-11-01",
            "https://api.portfoliodividendtracker.com/v1/prices/batch?symbolQuoteIds%5B%5D=11&symbolQuoteIds%5B%5D=12&dateFrom=2026-10-01&dateTo=2026-11-09",
            "https://api.portfoliodividendtracker.com/v1/dividends",
            "https://api.portfoliodividendtracker.com/v1/calendar-events?dateFrom=2026-11-09&dateTo=2027-01-08&page=1&perPage=100",
        ])
    }

    @Test("Page pagination collects every page in order")
    func pagePaginationCompletes() throws {
        let transport = ScriptedPDTHTTPTransport([
            ok(#"{"data":[{"id":1},{"id":2}],"meta":{"currentPage":1,"lastPage":3,"perPage":2,"total":5}}"#),
            ok(#"{"data":[{"id":3},{"id":4}],"meta":{"currentPage":2,"lastPage":3,"perPage":2,"total":5}}"#),
            ok(#"{"data":[{"id":5}],"meta":{"currentPage":3,"lastPage":3,"perPage":2,"total":5}}"#),
        ])

        let rows: [Row] = try makeClient(transport).getAll(.dividends())

        #expect(rows.map(\.id) == [1, 2, 3, 4, 5])
        #expect(transport.requests.map { queryValue($0, "page") } == ["1", "2", "3"])
    }

    @Test("Unpaged list envelopes decode with no meta or an empty meta array")
    func unpagedEnvelopesDecode() throws {
        let transport = ScriptedPDTHTTPTransport([
            ok(#"{"data":[{"id":1},{"id":2}]}"#),
            ok(#"{"data":[{"id":3}],"meta":[]}"#),
        ])
        let client = makeClient(transport)

        let holdings: [Row] = try client.getAll(.holdings())
        let distributions: [Row] = try client.getAll(.distributions)

        #expect(holdings.map(\.id) == [1, 2])
        #expect(distributions.map(\.id) == [3])
        #expect(transport.requests.allSatisfy { queryValue($0, "page") == nil })
    }

    @Test("Stalled or runaway pagination fails instead of looping")
    func stalledPaginationFails() {
        let stalled = ScriptedPDTHTTPTransport([
            ok(#"{"data":[{"id":1}],"meta":{"currentPage":1,"lastPage":9,"perPage":1,"total":9}}"#),
            ok(#"{"data":[],"meta":{"currentPage":2,"lastPage":9,"perPage":1,"total":9}}"#),
        ])
        #expect(throws: PDTAPIError.paginationStalled) {
            let _: [Row] = try makeClient(stalled).getAll(.dividends())
        }

        let repeatedPage = ScriptedPDTHTTPTransport(Array(
            repeating: ok(#"{"data":[{"id":1}],"meta":{"currentPage":1,"lastPage":2,"perPage":1,"total":2}}"#),
            count: 2
        ))
        #expect(throws: PDTAPIError.paginationStalled) {
            let _: [Row] = try makeClient(repeatedPage).getAll(.dividends())
        }

        let missingMeta = ScriptedPDTHTTPTransport([ok(#"{"data":[{"id":1}]}"#)])
        #expect(throws: PDTAPIError.invalidResponse) {
            let _: [Row] = try makeClient(missingMeta).getAll(.dividends())
        }

        let noBudget = ScriptedPDTHTTPTransport([ok(onePage)])
        let rows: [Row] = (try? makeClient(noBudget, policy: PDTAPIRequestPolicy(maxPages: 0)).getAll(.dividends())) ?? []
        #expect(rows.isEmpty)
        #expect(noBudget.requests.count == 1)

        let runaway = ScriptedPDTHTTPTransport((1...3).map { page in
            ok(#"{"data":[{"id":1}],"meta":{"currentPage":\#(page),"lastPage":99,"perPage":1,"total":99}}"#)
        })
        #expect(throws: PDTAPIError.paginationLimitExceeded) {
            let _: [Row] = try makeClient(runaway, policy: PDTAPIRequestPolicy(maxPages: 2)).getAll(.dividends())
        }
        #expect(runaway.requests.count == 2)
    }

    @Test("X-ray follows limit/offset until hasMore is false")
    func xRayOffsetPagination() throws {
        let transport = ScriptedPDTHTTPTransport([
            ok(#"{"data":{"items":[{"id":1},{"id":2}],"hasMore":true,"totalCount":3},"meta":[]}"#),
            ok(#"{"data":{"items":[{"id":3}],"hasMore":false,"totalCount":3},"meta":[]}"#),
        ])

        let rows: [Row] = try makeClient(transport).getAll(.xRay)

        #expect(rows.map(\.id) == [1, 2, 3])
        #expect(transport.requests.map { queryValue($0, "offset") } == ["0", "2"])
        #expect(transport.requests.allSatisfy { queryValue($0, "limit") == "100" })
    }

    @Test("API error envelopes map to typed errors without retrying")
    func errorEnvelopesClassify() {
        let cases: [(Int, String, PDTAPIError)] = [
            (401, envelope("TOKEN_INVALID", details: #"{"reason":"expired"}"#), .tokenInvalid(reason: "expired")),
            (401, envelope("UNAUTHENTICATED"), .unauthenticated),
            (403, envelope("INSUFFICIENT_SCOPE"), .insufficientScope),
            (403, envelope("API_ACCESS_PAUSED"), .apiAccessPaused),
            (403, envelope("FORBIDDEN"), .forbidden),
            (404, envelope("NOT_FOUND"), .notFound),
            (422, envelope("VALIDATION_FAILED"), .validationFailed),
            (302, "", .unexpectedStatus(302)),
        ]
        for (status, body, expected) in cases {
            let transport = ScriptedPDTHTTPTransport([.response(status: status, body: Data(body.utf8))])
            let sleeper = RecordingSleeper()
            #expect(throws: expected) {
                _ = try makeClient(transport, sleeper: sleeper).get(.me)
            }
            #expect(transport.requests.count == 1)
            #expect(sleeper.delays.isEmpty)
        }
    }

    @Test("429 honours Retry-After, then gives up after the attempt budget")
    func rateLimitRetries() throws {
        let limited = PDTAPIError.rateLimited(retryAfter: 2)
        let recovering = ScriptedPDTHTTPTransport([rateLimited(retryAfter: "2"), ok(#"{"data":[]}"#)])
        let sleeper = RecordingSleeper()
        _ = try makeClient(recovering, sleeper: sleeper).get(.me)
        #expect(recovering.requests.count == 2)
        #expect(sleeper.delays == [2])

        let exhausted = ScriptedPDTHTTPTransport(Array(repeating: rateLimited(retryAfter: "2"), count: 5))
        let exhaustedSleeper = RecordingSleeper()
        #expect(throws: limited) {
            _ = try makeClient(exhausted, sleeper: exhaustedSleeper).get(.me)
        }
        #expect(exhausted.requests.count == 3)
        #expect(exhaustedSleeper.delays == [2, 2])
    }

    @Test("A Retry-After longer than the policy allows fails fast")
    func longRetryAfterFailsFast() {
        let transport = ScriptedPDTHTTPTransport([rateLimited(retryAfter: "120"), ok(#"{"data":[]}"#)])
        let sleeper = RecordingSleeper()
        #expect(throws: PDTAPIError.rateLimited(retryAfter: 120)) {
            _ = try makeClient(transport, sleeper: sleeper).get(.me)
        }
        #expect(transport.requests.count == 1)
        #expect(sleeper.delays.isEmpty)
    }

    @Test("Retry-After as an HTTP date is measured from the injected clock")
    func retryAfterHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let retryAt = formatter.string(from: now.addingTimeInterval(5))
        let transport = ScriptedPDTHTTPTransport([rateLimited(retryAfter: retryAt), ok(#"{"data":[]}"#)])
        let sleeper = RecordingSleeper()

        _ = try makeClient(transport, sleeper: sleeper, now: now).get(.me)

        #expect(sleeper.delays == [5])
    }

    @Test("5xx and transient transport failures back off exponentially; others fail at once")
    func serverAndTransportRetries() throws {
        let server = ScriptedPDTHTTPTransport([
            .response(status: 503, body: Data(envelope("INTERNAL_ERROR").utf8)),
            .failure(.timedOut),
            ok(#"{"data":[]}"#),
        ])
        let sleeper = RecordingSleeper()
        _ = try makeClient(server, sleeper: sleeper).get(.me)
        #expect(server.requests.count == 3)
        #expect(sleeper.delays == [1, 2])

        let unavailable = ScriptedPDTHTTPTransport([
            .response(status: 503, body: Data(envelope("INTERNAL_ERROR").utf8), headers: ["Retry-After": "7"]),
            ok(#"{"data":[]}"#),
        ])
        let unavailableSleeper = RecordingSleeper()
        _ = try makeClient(unavailable, sleeper: unavailableSleeper).get(.me)
        #expect(unavailableSleeper.delays == [7])

        let offline = ScriptedPDTHTTPTransport([.failure(.secureConnectionFailed), ok(#"{"data":[]}"#)])
        #expect(throws: PDTAPIError.transport(code: URLError.secureConnectionFailed.rawValue)) {
            _ = try makeClient(offline).get(.me)
        }
        #expect(offline.requests.count == 1)
    }

    @Test("No token, a cancelled caller, or an oversized batch sends nothing")
    func preflightFailuresSendNothing() {
        let transport = ScriptedPDTHTTPTransport([ok(#"{"data":[]}"#)])
        #expect(throws: PDTAPIError.missingToken) {
            _ = try PDTAPIClient(transport: transport, tokenProvider: InMemoryPDTAPITokenProvider(token: nil)).get(.me)
        }

        let cancellation = PDTCancellation()
        cancellation.cancel()
        #expect(throws: PDTAPIError.cancelled) {
            _ = try makeClient(transport).get(.me, cancellation: cancellation)
        }

        #expect(throws: PDTAPIError.invalidRequest) {
            _ = try makeClient(transport).get(.pricesBatch(symbolQuoteIds: Array(1...51), dateFrom: "2026-10-01", dateTo: "2026-11-09"))
        }
        #expect(throws: PDTAPIError.invalidRequest) {
            _ = try makeClient(transport).get(.pricesBatch(symbolQuoteIds: [], dateFrom: "2026-10-01", dateTo: "2026-11-09"))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Tokens and response bodies never leak into descriptions or errors")
    func secretsStayRedacted() {
        let token = PDTAPIToken("pdt_test_secret")
        #expect(!String(describing: token).contains("pdt_test_secret"))
        #expect(!String(reflecting: token).contains("pdt_test_secret"))

        let body = #"{"error":{"code":"FORBIDDEN","message":"portfolio Acme 1234 EUR","details":{},"traceId":"t"}}"#
        let transport = ScriptedPDTHTTPTransport([.response(status: 403, body: Data(body.utf8))])
        do {
            _ = try makeClient(transport).get(.me)
            Issue.record("expected a forbidden error")
        } catch {
            let rendered = String(describing: error) + String(reflecting: error)
            #expect(!rendered.contains("pdt_test_secret"))
            #expect(!rendered.contains("Acme"))
        }
    }

    @Test("URLSession transport leaves the caller's configuration untouched")
    func urlSessionTransportCopiesConfiguration() {
        let configuration = URLSessionConfiguration.default
        let cookies = configuration.httpCookieStorage
        _ = URLSessionPDTHTTPTransport(configuration: configuration)
        #expect(configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieStorage === cookies)
        #expect(configuration.urlCache != nil)
    }

    @Test("URLSession transport refuses non-GET requests and every redirect")
    func urlSessionTransportGuards() throws {
        let transport = URLSessionPDTHTTPTransport()
        var post = URLRequest(url: PDTAPIClient.baseURL.appending(path: "me"))
        post.httpMethod = "POST"
        #expect(throws: PDTAPIError.invalidRequest) {
            _ = try transport.send(post, cancellation: nil)
        }

        let redirect = RedirectCapture()
        transport.urlSession(
            URLSession.shared,
            task: URLSession.shared.dataTask(with: PDTAPIClient.baseURL),
            willPerformHTTPRedirection: HTTPURLResponse(url: PDTAPIClient.baseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: URL(string: "https://elsewhere.example/v1/me")!),
            completionHandler: { redirect.record($0) }
        )
        #expect(redirect.called)
        #expect(redirect.request == nil)
    }
}

private struct Row: Decodable, Equatable {
    var id: Int
}

private func makeClient(
    _ transport: ScriptedPDTHTTPTransport,
    policy: PDTAPIRequestPolicy = PDTAPIRequestPolicy(),
    sleeper: RecordingSleeper = RecordingSleeper(),
    now: Date = Date(timeIntervalSince1970: 1_794_000_000)
) -> PDTAPIClient {
    PDTAPIClient(
        transport: transport,
        tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("pdt_test_secret")),
        policy: policy,
        sleeper: sleeper,
        now: { now }
    )
}

private let onePage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1,"perPage":100,"total":0}}"#

private func ok(_ body: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(body.utf8))
}

private func rateLimited(retryAfter: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 429, body: Data(envelope("RATE_LIMITED").utf8), headers: ["Retry-After": retryAfter])
}

private func envelope(_ code: String, details: String = "{}") -> String {
    #"{"error":{"code":"\#(code)","message":"m","details":\#(details),"traceId":"trace"}}"#
}

private func queryValue(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

private final class RecordingSleeper: PDTAPISleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(seconds: TimeInterval, cancellation _: PDTCancellation?) throws {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(seconds)
    }
}

private final class RedirectCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var called = false
    private(set) var request: URLRequest?

    func record(_ request: URLRequest?) {
        lock.lock()
        defer { lock.unlock() }
        called = true
        self.request = request
    }
}
