import Foundation
import Testing
import PDTBarCore

@Suite("PDT API data source")
struct PDTAPIDataSourceTests {
    @Test("Requests are GET-only to the PDT origin, in a fixed order, with the snapshot date windows")
    func requestContract() throws {
        let run = try replay("full")

        #expect(run.transport.requests.map { $0.url!.path } == [
            "/v1/portfolio/holdings",
            "/v1/portfolio/distributions",
            "/v1/x-ray", "/v1/x-ray",
            "/v1/calendar-events", "/v1/calendar-events",
            "/v1/dividends",
            "/v1/symbol-quotes", "/v1/symbol-quotes", "/v1/symbol-quotes",
            "/v1/symbol-quotes", "/v1/symbol-quotes", "/v1/symbol-quotes",
            "/v1/prices/batch",
        ])
        for request in run.transport.requests {
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.portfoliodividendtracker.com")
        }
        let requests = run.transport.requests
        #expect(query(requests[2], "offset") == ["0"])
        #expect(query(requests[3], "offset") == ["2"])
        #expect(query(requests[4], "dateFrom") == ["2026-06-22"])
        #expect(query(requests[4], "dateTo") == ["2026-07-22"])
        #expect(requests[4...5].map { query($0, "page") } == [["1"], ["2"]])
        #expect(query(requests[6], "dateFrom") == ["2025-06-17"])
        #expect(query(requests[6], "dateTo") == ["2026-07-22"])
        #expect(requests[7...12].map { query($0, "symbolId") } == [["5001"], ["5002"], ["5003"], ["5004"], ["5010"], ["5013"]])
        #expect(query(requests[13], "symbolQuoteIds[]") == ["9001", "9002", "9003", "9004", "9010", "9013"])
        #expect(query(requests[13], "dateFrom") == ["2026-06-15"])
        #expect(query(requests[13], "dateTo") == ["2026-06-22"])
        #expect(run.failures.isEmpty)
        #expect(run.snapshot.latestDetailFillOutcome == nil)
    }

    @Test("Every paged request asks for at most PDT's documented page size")
    func pagedRequestsStayWithinDocumentedPageSize() throws {
        let documentedMaximumPageSize = 100
        let pageSizes = try replay("full").transport.requests.compactMap { request in
            (query(request, "perPage") + query(request, "limit")).first.flatMap(Int.init)
        }

        #expect(pageSizes.count == 11)
        #expect(pageSizes.allSatisfy { $0 <= documentedMaximumPageSize })
    }

    @Test("Holdings keep open rows, local FX values, identifiers, and tolerate malformed optional fields")
    func holdingsMapping() throws {
        let snapshot = try replay("full").snapshot
        let holdings = Dictionary(uniqueKeysWithValues: snapshot.openHoldings.map { ($0.quoteId, $0) })

        #expect(snapshot.openHoldings.map(\.quoteId) == [9001, 9002, 9003, 9004, 9010, 9013])
        #expect(snapshot.totalValue == Money(value: "40000.00", currency: "EUR"))

        let meridian = try #require(holdings[9004])
        #expect(meridian.worth == Money(value: "8000.00", currency: "EUR"))
        #expect(meridian.price == Money(value: "9.44", currency: "EUR"))
        #expect(meridian.averageBuyPrice == Money(value: "8.10", currency: "EUR"))
        #expect(meridian.copyableIdentifier == "MRDN")
        #expect(meridian.isin == "GB0000000044")

        let nova = try #require(holdings[9001])
        #expect(nova.weight == 0.3)
        #expect(nova.copyableIdentifier == "NOVA")
        #expect(nova.averageBuyPrice == Money(value: "500.0000", currency: "EUR"))
        #expect(nova.gainLoss == Money(value: "2200", currency: "EUR"))
        #expect(nova.gainLossPercentage == 0.2245)

        let helix = try #require(holdings[9003])
        #expect(helix.gainLoss == nil)
        #expect(helix.gainLossPercentage == nil)
        #expect(holdings[9002]?.price == nil)
        #expect(holdings[9013]?.worth == Money(value: "2000", currency: "EUR"))
        #expect(holdings[9013]?.weight == 0.05)
        #expect(holdings[9010]?.copyableIdentifier == nil)
        #expect(holdings[9010]?.isin == nil)
    }

    @Test("Distributions, x-ray, income, dividends, and prices map into facets")
    func detailFacetsMapping() throws {
        let snapshot = try replay("full").snapshot

        #expect(snapshot.sectors.map(\.name) == ["information-technology", "communication-services", "financials", "health-care"])
        #expect(snapshot.sectors.map(\.percentage) == [30, 20, 20, 15])
        #expect(snapshot.sectors[1].totalValue == Money(value: "8000", currency: "EUR"))
        #expect(snapshot.assetTypes.map(\.name) == ["common-stock", "cash"])
        #expect(snapshot.xRayHoldings?.map(\.weight) == [0.125, 0.0825, 0.04])

        let events = snapshot.incomeEvents
        #expect(events.map(\.symbolName) == ["Helix Pharma A/S", "Nova Lithography", "Orbit Communications"])
        #expect(events.map(\.quoteId) == [9003, 9001, 9002])
        #expect(events.map(\.estimated) == [false, false, true])
        #expect(events[0].amount == Money(value: "78.00", currency: "EUR"))
        #expect(events[1].amount == nil, "a +/- correction pair nets the Nova dividend out")
        #expect(snapshot.dividendRowCount == 4)

        #expect(snapshot.priceSeries.map(\.quoteId) == [9001, 9001, 9004, 9004])
        #expect(snapshot.priceSeries.map(\.closeAdjusted) == ["612.40", "598", "818.00", "812"])
        #expect(snapshot.priceSeries.map(\.closeCurrency) == ["EUR", "EUR", "GBX", "GBX"])
    }

    @Test("prices/batch splits open holdings into chunks of 50 and flattens the groups")
    func pricesBatchChunking() throws {
        let quoteIDs = Array(1...120)
        let holdings = quoteIDs.map { holdingRow(quoteId: $0, symbolId: $0 + 1000) }.joined(separator: ",")
        let priceGroup = { (id: Int) in #"[{"date":"2026-06-22","closeAdjusted":"1.00","closeCurrency":"EUR","symbolQuoteId":\#(id)}]"# }
        let batches = [Array(1...50), Array(51...100), Array(101...120)].map { chunk in
            ok(#"{"data":{"prices":[\#(chunk.map(priceGroup).joined(separator: ","))]}}"#)
        }
        let transport = ScriptedPDTHTTPTransport([ok(#"{"data":[\#(holdings)]}"#)] + batches)

        let snapshot = try dataSource(transport, options: options(prices: true)).snapshot(asOf: "2026-06-22")

        let batchRequests = transport.requests.dropFirst()
        #expect(batchRequests.map { query($0, "symbolQuoteIds[]").count } == [50, 50, 20])
        #expect(batchRequests.flatMap { query($0, "symbolQuoteIds[]") } == quoteIDs.map(String.init))
        #expect(snapshot.priceSeries.map(\.quoteId) == quoteIDs)
        #expect(snapshot.latestDetailFillOutcome == nil)
    }

    @Test("A malformed required holdings field fails the snapshot as an invalid response")
    func malformedRequiredHoldingFieldThrows() throws {
        for row in [
            holdingRow(quoteId: 1, symbolId: 2, worthLocal: nil),
            holdingRow(quoteId: 1, symbolId: 2, weight: #""heavy""#),
            holdingRow(quoteId: 1, symbolId: 2, worthLocal: #"{"value":"lots","currency":"EUR"}"#),
            holdingRow(quoteId: 1, symbolId: 2, closedAt: "20260302"),
        ] {
            let transport = ScriptedPDTHTTPTransport([ok(#"{"data":[\#(row)]}"#)])
            #expect(throws: PDTAPIError.invalidResponse) {
                try dataSource(transport, options: .firstFetch).snapshot(asOf: "2026-06-22")
            }
        }
    }

    @Test("A holdings failure throws and requests nothing else")
    func holdingsFailureThrows() throws {
        let transport = ScriptedPDTHTTPTransport([apiError(401, "TOKEN_INVALID", details: #"{"reason":"revoked"}"#)])

        #expect(throws: PDTAPIError.tokenInvalid(reason: "revoked")) {
            try dataSource(transport).snapshot(asOf: "2026-06-22")
        }
        #expect(transport.requests.count == 1)
    }

    @Test("Requested empty facets are empty and complete; unrequested facets are missing")
    func missingVersusEmptyDetail() throws {
        let holdings = ok(#"{"data":[\#(holdingRow(quoteId: 1, symbolId: 2))]}"#)
        let emptyPage = ok(#"{"data":[],"meta":{"currentPage":1,"lastPage":1,"perPage":100,"total":0}}"#)
        let requested = ScriptedPDTHTTPTransport([
            holdings,
            ok(#"{"data":{"sectors":[],"assetTypes":[]}}"#),
            ok(#"{"data":{"items":[],"hasMore":false,"totalCount":0}}"#),
            emptyPage,
            emptyPage,
            emptyPage,
            ok(#"{"data":{"prices":[]}}"#),
        ])
        let unrequested = ScriptedPDTHTTPTransport([holdings])
        let recorder = FailureRecorder()

        let empty = try dataSource(requested, recorder: recorder).snapshot(asOf: "2026-06-22")
        let missing = try dataSource(unrequested, options: .firstFetch).snapshot(asOf: "2026-06-22")

        #expect(requested.requests.count == 7)
        #expect(recorder.failures.isEmpty)
        #expect(empty.xRayHoldings == [])
        #expect(empty.sectors.isEmpty)
        #expect(empty.incomeEvents.isEmpty)
        #expect(empty.priceSeries.isEmpty)
        #expect(empty.latestDetailFillOutcome == nil)
        #expect(unrequested.requests.count == 1)
        #expect(missing.xRayHoldings == nil)
        #expect(missing.latestDetailFillOutcome == nil)
        #expect(missing.openHoldings.map(\.quoteId) == [1])
    }

    @Test("A failed optional facet is missing, degrades the snapshot, and later facets still load")
    func failedOptionalFacetDegrades() throws {
        let recorder = FailureRecorder()
        let transport = ScriptedPDTHTTPTransport([
            ok(#"{"data":[\#(holdingRow(quoteId: 1, symbolId: 2))]}"#),
            ok(#"{"data":{"sectors":[{"categoryName":"energy","totalValue":{"value":"1.00","currency":"EUR"},"percentage":"most"}],"assetTypes":[]}}"#),
            ok(#"{"data":{"items":"broken"}}"#),
            ok(#"{"data":{"prices":[[{"date":"2026-06-22","closeAdjusted":2.5,"symbolQuoteId":1}]]}}"#),
        ])
        let options = PDTAPIDataSourceOptions(includeIncomeEvents: false, includeDividends: false, includeQuoteCodes: false)

        let snapshot = try dataSource(transport, options: options, recorder: recorder).snapshot(asOf: "2026-06-22")

        #expect(snapshot.sectors.isEmpty)
        #expect(snapshot.xRayHoldings == nil)
        #expect(snapshot.priceSeries.map(\.closeAdjusted) == ["2.5"])
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(recorder.failures == [
            PDTSyncFailure(phase: .allocation, endpoint: .distributions, kind: .unreadableResponse, requestCount: 1),
            PDTSyncFailure(phase: .xRay, endpoint: .xRay, kind: .unreadableResponse, requestCount: 1),
        ])
    }

    @Test("An auth failure on an optional facet skips the remaining facets and keeps the token out of the failure")
    func authFailureSkipsRemainingFacets() throws {
        let recorder = FailureRecorder()
        let transport = ScriptedPDTHTTPTransport([
            ok(#"{"data":[\#(holdingRow(quoteId: 1, symbolId: 2))]}"#),
            ok(#"{"data":{"sectors":[],"assetTypes":[]}}"#),
            apiError(401, "TOKEN_INVALID", details: #"{"reason":"expired"}"#),
        ])

        let snapshot = try dataSource(transport, recorder: recorder).snapshot(asOf: "2026-06-22")

        #expect(transport.requests.count == 3)
        #expect(snapshot.openHoldings.map(\.quoteId) == [1])
        #expect(snapshot.xRayHoldings == nil)
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(recorder.failures == [
            PDTSyncFailure(phase: .xRay, endpoint: .xRay, kind: .reconnect, requestCount: 1),
        ])
        let encoded = String(decoding: try stableJSONData(recorder.failures), as: UTF8.self)
        #expect(!encoded.contains(testSecret))
        #expect(!encoded.contains("pdt_"))
    }

    @Test(
        "REST errors map to typed sync failures",
        arguments: [
            (403, "INSUFFICIENT_SCOPE", PDTSyncFailure.Kind.readAccessMissing),
            (403, "API_ACCESS_PAUSED", .accessPaused),
            (403, "FORBIDDEN", .forbidden),
            (401, "UNAUTHENTICATED", .reconnect),
            (429, "RATE_LIMITED", .rateLimited(retryAfterSeconds: nil)),
            (503, "SERVER_ERROR", .server(status: 503)),
            (404, "NOT_FOUND", .unexpected(status: 404)),
            (200, "not json", .unreadableResponse),
        ]
    )
    func errorKinds(status: Int, code: String, kind: PDTSyncFailure.Kind) throws {
        let reply = status == 200 ? ok(code) : apiError(status, code)
        let recorder = FailureRecorder()
        let transport = ScriptedPDTHTTPTransport([ok(#"{"data":[\#(holdingRow(quoteId: 1, symbolId: 2))]}"#), reply])
        let options = PDTAPIDataSourceOptions(
            includeXRayHoldings: false,
            includeIncomeEvents: false,
            includeDividends: false,
            includeQuoteCodes: false,
            includePriceSeries: false
        )

        _ = try dataSource(transport, options: options, recorder: recorder).snapshot(asOf: "2026-06-22")

        #expect(recorder.failures.map(\.kind) == [kind])
    }

    @Test("Multi-currency holdings total in the portfolio currency")
    func multiCurrencyTotalsInPortfolioCurrency() throws {
        let transport = ScriptedPDTHTTPTransport([ok(#"""
        {"data":[
          {"symbolName":"US Traded Co","symbolQuoteId":2001,"symbolId":3001,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"347.66","currency":"EUR"},"currentExchangeRate":1.154,"currentWorth":{"value":"9347.40","currency":"USD"},"currentWorthLocal":{"value":"8100.00","currency":"EUR"},"portfolioWeight":0.34,"closedAt":null},
          {"symbolName":"Danish Traded Co","symbolQuoteId":2002,"symbolId":3002,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"25.00","currency":"DKK"},"currentExchangeRate":2.0,"currentWorth":{"value":"250.00","currency":"DKK"},"currentWorthLocal":{"value":"250.00","currency":"DKK"},"portfolioWeight":0.66,"closedAt":null}
        ]}
        """#)])

        let snapshot = try dataSource(transport, options: .firstFetch).snapshot(asOf: "2026-06-22")

        #expect(snapshot.openHoldings.map(\.quoteId) == [2001, 2002])
        #expect(snapshot.totalValue == Money(value: "8225.00", currency: "EUR"))
    }

    @Test("A portfolio held in USD is totalled in USD")
    func nonEURPortfolioCurrencyIsInferred() throws {
        let transport = ScriptedPDTHTTPTransport([ok(#"""
        {"data":[
          {"symbolName":"US Portfolio Holding","symbolQuoteId":6001,"symbolId":7001,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"100.00","currency":"USD"},"currentExchangeRate":0.8,"currentWorth":{"value":"400.00","currency":"EUR"},"currentWorthLocal":{"value":"500.00","currency":"USD"},"portfolioWeight":0.67,"closedAt":null},
          {"symbolName":"Second US Portfolio Holding","symbolQuoteId":6002,"symbolId":7002,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"25.00","currency":"USD"},"currentWorth":{"value":"250.00","currency":"USD"},"currentWorthLocal":{"value":"250.00","currency":"USD"},"portfolioWeight":0.33,"closedAt":null}
        ]}
        """#)])

        let snapshot = try dataSource(transport, options: .firstFetch).snapshot(asOf: "2026-06-22")

        #expect(snapshot.openHoldings.map(\.quoteId) == [6001, 6002])
        #expect(snapshot.totalValue == Money(value: "750.00", currency: "USD"))
    }

    @Test("Filtered-out holdings get no quote-code or price request")
    func filteredHoldingsGetNoQuoteOrPriceRequest() throws {
        let transport = ScriptedPDTHTTPTransport([
            ok(#"""
            {"data":[
              {"symbolName":"Open Public Co","symbolQuoteId":1001,"symbolId":5001,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorth":{"value":"500.00","currency":"EUR"},"currentWorthLocal":{"value":"500.00","currency":"EUR"},"portfolioWeight":0.10,"closedAt":null},
              {"symbolName":"Zero Worth","symbolQuoteId":1003,"symbolId":5003,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorthLocal":{"value":"0.00","currency":"EUR"},"portfolioWeight":0.45,"closedAt":null},
              {"symbolName":"Negative Worth","symbolQuoteId":1005,"symbolId":5005,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorthLocal":{"value":"-10.00","currency":"EUR"},"portfolioWeight":0.50,"closedAt":null},
              {"symbolName":"Closed Co","symbolQuoteId":1002,"symbolId":5002,"currentPriceDate":"2026-06-21T21:59:00+00:00","currentWorthLocal":{"value":"0.00","currency":"EUR"},"portfolioWeight":0.40,"closedAt":"2026-06-01T00:00:00+00:00"}
            ]}
            """#),
            ok(#"{"data":[{"id":1001,"code":"PUBC","symbolId":5001}],"meta":{"currentPage":1,"lastPage":1}}"#),
            ok(#"{"data":{"prices":[[{"date":"2026-06-22","closeAdjusted":"10.25","closeCurrency":"EUR","symbolQuoteId":1001}]]}}"#),
        ])
        let options = PDTAPIDataSourceOptions(
            includeDistributions: false,
            includeXRayHoldings: false,
            includeIncomeEvents: false,
            includeDividends: false
        )

        let snapshot = try dataSource(transport, options: options).snapshot(asOf: "2026-06-22")

        #expect(snapshot.openHoldings.map(\.quoteId) == [1001])
        #expect(snapshot.openHoldings.first?.copyableIdentifier == "PUBC")
        #expect(snapshot.priceSeries.map(\.quoteId) == [1001])
        #expect(transport.requests.map { $0.url!.path } == ["/v1/portfolio/holdings", "/v1/symbol-quotes", "/v1/prices/batch"])
        #expect(query(transport.requests[1], "symbolId") == ["5001"])
        #expect(query(transport.requests[2], "symbolQuoteIds[]") == ["1001"])
    }

    @Test(
        "REST fixtures for the same portfolio produce the same pressure as the MCP fixtures",
        arguments: [
            ("quiet-no-pressure", PDTAPIDataSourceOptions(includeXRayHoldings: false, includeDividends: false, includeQuoteCodes: false)),
            ("concentration-pressure", PDTAPIDataSourceOptions(
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeQuoteCodes: false,
                includePriceSeries: false
            )),
        ]
    )
    func quietAndPressureParity(scenario: String, options: PDTAPIDataSourceOptions) throws {
        let fixture = try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/\(scenario).json"))
        let run = try replay(scenario, options: options, asOf: fixture.asOf)
        let expected = PressureEngine.buildModel(from: fixture, today: fixture.asOf)
        let actual = PressureEngine.buildModel(from: run.snapshot, today: fixture.asOf)

        #expect(run.failures.isEmpty)
        #expect(actual.allQuiet == expected.allQuiet)
        #expect(actual.rankedAttentionItems.map(\.id) == expected.rankedAttentionItems.map(\.id))
        #expect(actual.rankedAttentionItems.map(\.facet) == expected.rankedAttentionItems.map(\.facet))
        #expect(expected.allQuiet == (scenario == "quiet-no-pressure"))
    }
}

private let testSecret = "pdt_test_secret"

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private struct ReplayRun {
    var snapshot: PortfolioSnapshot
    var transport: ScriptedPDTHTTPTransport
    var failures: [PDTSyncFailure]
}

private func replay(
    _ scenario: String,
    options: PDTAPIDataSourceOptions = PDTAPIDataSourceOptions(),
    asOf: String = "2026-06-22"
) throws -> ReplayRun {
    let directory = packageRoot.appending(path: "docs/pdt/fixtures/api/\(scenario)")
    let bodies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { ScriptedPDTHTTPTransport.Reply.response(status: 200, body: try Data(contentsOf: $0)) }
    let transport = ScriptedPDTHTTPTransport(bodies)
    let recorder = FailureRecorder()
    let snapshot = try dataSource(transport, options: options, recorder: recorder).snapshot(asOf: asOf)
    return ReplayRun(snapshot: snapshot, transport: transport, failures: recorder.failures)
}

private func dataSource(
    _ transport: ScriptedPDTHTTPTransport,
    options: PDTAPIDataSourceOptions = PDTAPIDataSourceOptions(),
    recorder: FailureRecorder? = nil
) -> PDTAPIDataSource {
    PDTAPIDataSource(
        client: PDTAPIClient(
            transport: transport,
            tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(testSecret)),
            policy: PDTAPIRequestPolicy(maxAttempts: 1),
            sleeper: NoSleep()
        ),
        options: options,
        onSyncFailure: { failure in recorder?.record(failure) }
    )
}

private func options(prices: Bool) -> PDTAPIDataSourceOptions {
    var options = PDTAPIDataSourceOptions.firstFetch
    options.includePriceSeries = prices
    return options
}

private func holdingRow(
    quoteId: Int,
    symbolId: Int,
    worthLocal: String? = #"{"value":"100.00","currency":"EUR"}"#,
    weight: String = "0.5",
    closedAt: String = "null"
) -> String {
    let worth = worthLocal.map { #","currentWorthLocal":\#($0)"# } ?? ""
    return #"{"symbolName":"Holding \#(quoteId)","symbolQuoteId":\#(quoteId),"symbolId":\#(symbolId),"currentPriceDate":"2026-06-22T23:59:59+00:00","portfolioWeight":\#(weight),"closedAt":\#(closedAt)\#(worth)}"#
}

private func ok(_ body: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(body.utf8))
}

private func apiError(_ status: Int, _ code: String, details: String = "{}") -> ScriptedPDTHTTPTransport.Reply {
    .response(status: status, body: Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details),"traceId":"t"}}"#.utf8))
}

private func query(_ request: URLRequest, _ name: String) -> [String] {
    (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .filter { $0.name == name }
        .compactMap(\.value)
}

private struct NoSleep: PDTAPISleeper {
    func sleep(seconds _: TimeInterval, cancellation _: PDTCancellation?) throws {}
}

private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [PDTSyncFailure] = []

    var failures: [PDTSyncFailure] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ failure: PDTSyncFailure) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(failure)
    }
}
