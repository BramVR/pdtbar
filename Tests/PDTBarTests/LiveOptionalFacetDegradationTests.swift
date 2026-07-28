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
        diagnostics: OptionalFacetDiagnosticRecorder
    ) -> PDTLiveDataSource {
        PDTLiveDataSource(
            toolClient: client,
            options: PDTLiveDataSourceOptions(
                includeDistributions: true,
                includeXRayHoldings: true,
                includeIncomeEvents: true,
                includeDividends: true,
                includeIncomeQuoteLookups: false,
                includePriceSeries: false
            ),
            onOptionalFacetFailure: diagnostics.append
        )
    }
}

private final class OptionalFacetToolClient: PDTLiveToolClient, @unchecked Sendable {
    private let failures: [String: any Error]
    private let lock = NSLock()
    private var calls: [String] = []

    init(failures: [String: any Error] = [:]) {
        self.failures = failures
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
        return Self.responses[name] ?? Data()
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
