import Foundation
import PDTBarCore
import Testing

@Suite("Live optional facet degradation")
struct LiveOptionalFacetDegradationTests {
    @Test("Calendar failure preserves holdings and emits one degraded diagnostic")
    func calendarFailurePreservesHoldings() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-list-calendar-events": PDTMCPConnectorError.transientFailure("calendar unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.openHoldings.map(\.quoteId) == [9101])
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(diagnostics.values.count == 1)
        #expect(diagnostics.values.first?.toolName == "pdt-list-calendar-events")
    }

    @Test("X-ray failure remains not fetched rather than genuinely empty")
    func xRayFailureRemainsNotFetched() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-list-x-ray-holdings": PDTLiveDataSourceError.malformedToolResult("pdt-list-x-ray-holdings"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.xRayHoldings == nil)
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(diagnostics.values.map(\.toolName) == ["pdt-list-x-ray-holdings"])
    }

    @Test("Quote metadata failure preserves holdings and emits one degraded diagnostic")
    func quoteMetadataFailurePreservesHoldings() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-get-symbol-quote": PDTMCPConnectorError.transientFailure("quote metadata unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(
            client: client,
            diagnostics: diagnostics,
            includeIncomeQuoteLookups: true
        ).snapshot(asOf: "2026-07-28")

        #expect(snapshot.openHoldings.map(\.quoteId) == [9101])
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(diagnostics.values.count == 1)
        #expect(diagnostics.values.first?.toolName == "pdt-get-symbol-quote")
    }

    @Test("Price series failure preserves holdings and emits one degraded diagnostic")
    func priceSeriesFailurePreservesHoldings() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-list-symbol-prices": PDTMCPConnectorError.transientFailure("price series unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(
            client: client,
            diagnostics: diagnostics,
            includePriceSeries: true
        ).snapshot(asOf: "2026-07-28")

        #expect(snapshot.openHoldings.map(\.quoteId) == [9101])
        #expect(snapshot.priceSeries.isEmpty)
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(diagnostics.values.count == 1)
        #expect(diagnostics.values.first?.toolName == "pdt-list-symbol-prices")
    }

    @Test("Successful optional facets do not force a degraded outcome")
    func successfulOptionalFacetsRemainHealthy() throws {
        let client = OptionalFacetToolClient()
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.openHoldings.count == 1)
        #expect(snapshot.xRayHoldings == [])
        #expect(snapshot.latestDetailFillOutcome != .degraded)
        #expect(diagnostics.values.isEmpty)
    }

    @Test("Empty dividend page terminates despite an absurd server last page")
    func emptyDividendPageTerminatesImmediately() throws {
        let client = OptionalFacetToolClient(responses: [
            "pdt-list-dividends?date_from=2025-07-23&date_to=2026-08-27&page=1&per_page=250":
                Data(#"{"data":[],"meta":{"last_page":999999}}"#.utf8),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.latestDetailFillOutcome != .degraded)
        #expect(client.recordedCalls.filter { $0 == "pdt-list-dividends" }.count == 1)
        #expect(diagnostics.values.isEmpty)
    }

    @Test("X-ray pagination cap preserves partial rows and reports truncation")
    func xRayPaginationCapReportsTruncation() throws {
        let client = OptionalFacetToolClient(responses: [
            "pdt-list-x-ray-holdings?limit=500&offset=0":
                Data(#"{"items":[{"weight":25.0}],"hasMore":true}"#.utf8),
            "pdt-list-x-ray-holdings?limit=500&offset=500":
                Data(#"{"items":[{"weight":15.0}],"hasMore":true}"#.utf8),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(
            client: client,
            diagnostics: diagnostics,
            maxPagesPerList: 2
        ).snapshot(asOf: "2026-07-28")

        #expect(snapshot.xRayHoldings?.map(\.weight) == [0.25, 0.15])
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(client.recordedCalls.filter { $0 == "pdt-list-x-ray-holdings" }.count == 2)
        #expect(diagnostics.values.contains {
            $0.toolName == "pdt-list-x-ray-holdings"
                && $0.phase == .xRay
                && $0.category == .timeout
                && $0.argumentShape == ["limit", "offset"]
        })
    }

    @Test("Calendar pagination returns three pages in order without truncation")
    func calendarPaginationReturnsEveryPageInOrder() throws {
        var responses: [String: Data] = [:]
        for (page, date, name) in [
            (1, "2026-07-29", "Page One"),
            (2, "2026-07-30", "Page Two"),
            (3, "2026-07-31", "Page Three"),
        ] {
            responses["pdt-list-calendar-events?date_from=2026-07-28&date_to=2026-08-27&page=\(page)&per_page=250"] = Data("""
            {
              "data": [
                { "date": "\(date)", "type": "ex-dividend", "isEstimated": false, "symbolId": null, "symbolName": "\(name)" }
              ],
              "meta": { "last_page": 3 }
            }
            """.utf8)
        }
        let client = OptionalFacetToolClient(responses: responses)
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.incomeEvents.map(\.symbolName) == ["Page One", "Page Two", "Page Three"])
        #expect(snapshot.latestDetailFillOutcome != .degraded)
        #expect(client.recordedCalls.filter { $0 == "pdt-list-calendar-events" }.count == 3)
        #expect(diagnostics.values.isEmpty)
    }

    @Test("Deadline error preserves completed live pages and reports truncation")
    func deadlineErrorPreservesCompletedPages() throws {
        let secondPageKey = "pdt-list-x-ray-holdings?limit=500&offset=500"
        let client = OptionalFacetToolClient(
            failuresByRequest: [
                secondPageKey: PDTMCPConnectorError.timeout("X-ray page timed out"),
            ],
            responses: [
                "pdt-list-x-ray-holdings?limit=500&offset=0":
                    Data(#"{"items":[{"weight":25.0}],"hasMore":true}"#.utf8),
            ],
            delaySecondsByRequest: [secondPageKey: 0.06]
        )
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(
            client: client,
            diagnostics: diagnostics,
            paginationTimeoutSeconds: 0.05
        ).snapshot(asOf: "2026-07-28")

        #expect(snapshot.xRayHoldings?.map(\.weight) == [0.25])
        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(client.recordedCalls.filter { $0 == "pdt-list-x-ray-holdings" }.count == 2)
        #expect(diagnostics.values.contains {
            $0.toolName == "pdt-list-x-ray-holdings"
                && $0.phase == .xRay
                && $0.category == .timeout
        })
    }

    @Test("Setup outage skips every later optional request")
    func setupOutageSkipsLaterOptionalRequests() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-get-portfolio-distributions": PDTMCPConnectorError.setupUnavailable("PDT setup unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")

        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(client.recordedCalls == [
            "pdt-get-portfolio-holdings",
            "pdt-get-portfolio-distributions",
        ])
        #expect(diagnostics.values.map(\.category) == [.setupUnavailable])
    }

    @Test("Quote setup outage skips price series")
    func quoteSetupOutageSkipsPriceSeries() throws {
        let client = OptionalFacetToolClient(failures: [
            "pdt-get-symbol-quote": PDTMCPConnectorError.setupUnavailable("PDT setup unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        let snapshot = try liveDataSource(
            client: client,
            diagnostics: diagnostics,
            includeIncomeQuoteLookups: true,
            includePriceSeries: true
        ).snapshot(asOf: "2026-07-28")

        #expect(snapshot.latestDetailFillOutcome == .degraded)
        #expect(client.recordedCalls == [
            "pdt-get-portfolio-holdings",
            "pdt-get-portfolio-distributions",
            "pdt-list-x-ray-holdings",
            "pdt-list-calendar-events",
            "pdt-list-dividends",
            "pdt-get-symbol-quote",
        ])
        #expect(diagnostics.values.map(\.category) == [.setupUnavailable])
    }

    @Test("Holdings failure remains fatal")
    func holdingsFailureRemainsFatal() {
        let client = OptionalFacetToolClient(failures: [
            "pdt-get-portfolio-holdings": PDTMCPConnectorError.transientFailure("holdings unavailable"),
        ])
        let diagnostics = OptionalFacetDiagnosticRecorder()

        #expect(throws: (any Error).self) {
            _ = try liveDataSource(client: client, diagnostics: diagnostics).snapshot(asOf: "2026-07-28")
        }
        #expect(diagnostics.values.isEmpty)
    }

    private func liveDataSource(
        client: OptionalFacetToolClient,
        diagnostics: OptionalFacetDiagnosticRecorder,
        includeIncomeQuoteLookups: Bool = false,
        includePriceSeries: Bool = false,
        paginationTimeoutSeconds: Double = 240,
        maxPagesPerList: Int = 50
    ) -> PDTLiveDataSource {
        PDTLiveDataSource(
            toolClient: client,
            options: PDTLiveDataSourceOptions(
                includeDistributions: true,
                includeXRayHoldings: true,
                includeIncomeEvents: true,
                includeDividends: true,
                includeIncomeQuoteLookups: includeIncomeQuoteLookups,
                includePriceSeries: includePriceSeries,
                paginationTimeoutSeconds: paginationTimeoutSeconds,
                maxPagesPerList: maxPagesPerList,
            ),
            onOptionalFacetFailure: diagnostics.append
        )
    }
}

private final class OptionalFacetToolClient: PDTLiveToolClient, @unchecked Sendable {
    private let failures: [String: any Error]
    private let failuresByRequest: [String: any Error]
    private let responses: [String: Data]
    private let delaySecondsByRequest: [String: TimeInterval]
    private let lock = NSLock()
    private var calls: [String] = []

    init(
        failures: [String: any Error] = [:],
        failuresByRequest: [String: any Error] = [:],
        responses: [String: Data] = [:],
        delaySecondsByRequest: [String: TimeInterval] = [:]
    ) {
        self.failures = failures
        self.failuresByRequest = failuresByRequest
        self.responses = responses
        self.delaySecondsByRequest = delaySecondsByRequest
    }

    var recordedCalls: [String] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return calls
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        lock.unlock()
        if let failure = failures[name] {
            throw failure
        }
        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        if let delay = delaySecondsByRequest[key] {
            Thread.sleep(forTimeInterval: delay)
        }
        if let failure = failuresByRequest[key] {
            throw failure
        }
        guard let response = responses[key] ?? Self.responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(name)
        }
        return response
    }

    private static let responses: [String: Data] = [
        "pdt-get-portfolio-holdings": Data("""
        {
          "holdings": [
            {
              "symbolName": "Synthetic Holding",
              "symbolQuoteId": 9101,
              "currentPriceDate": "2026-07-28T22:00:00+00:00",
              "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
              "portfolioWeight": 0.25,
              "closedAt": null
            }
          ]
        }
        """.utf8),
        "pdt-get-portfolio-distributions": Data(#"{"sectors":[],"assetTypes":[]}"#.utf8),
        "pdt-list-x-ray-holdings": Data(#"{"items":[],"hasMore":false}"#.utf8),
        "pdt-list-calendar-events": Data(#"{"data":[],"meta":{"last_page":1}}"#.utf8),
        "pdt-list-dividends": Data(#"{"data":[],"meta":{"last_page":1}}"#.utf8),
    ]
}

private final class OptionalFacetDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []

    var values: [PDTDetailRefreshFailureDiagnostic] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return diagnostics
    }

    func append(_ diagnostic: PDTDetailRefreshFailureDiagnostic) {
        lock.lock()
        diagnostics.append(diagnostic)
        lock.unlock()
    }
}
