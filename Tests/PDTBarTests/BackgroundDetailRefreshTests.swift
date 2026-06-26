import Foundation
import Testing
import PDTBarCore

@Suite("Background detail refresh")
struct BackgroundDetailRefreshTests {
    @Test("Background refresh joins income calendar events to holding quotes")
    func backgroundRefreshJoinsIncomeCalendarEventsToHoldingQuotes() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-join-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        let connector = ScriptedPDTMCPConnector(
            responses: try detailRefreshResponses(calendarSymbolID: 5102, calendarSymbolName: "Scripted Adapter B")
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let committed = try #require(try store.loadPriorSnapshot())
        let event = try #require(committed.incomeEvents.first)
        #expect(event.symbolId == 5102)
        #expect(event.quoteId == 9102)
        #expect(event.amount == Money(value: "6.00", currency: "EUR"))
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.count == 1)

        let holdingRow = try #require(
            result.descriptor.sections
                .first { $0.id == "allocation" }?
                .rows
                .first { $0.id == "allocation.9102" }
        )
        #expect(holdingRow.children.first { $0.id == "allocation.9102.nextIncome" }?.detail == "Ex-dividend date on 2026-03-30; confirmed; EUR 6.00")
    }

    @Test("Price-history failure keeps completed detail phases and continues other holdings")
    func priceHistoryFailureKeepsCompletedPhasesAndContinuesOtherHoldings() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = ScriptedPDTMCPConnector(
            responses: try detailRefreshResponses(omittingPriceQuoteID: 9102)
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let committed = try #require(try store.loadPriorSnapshot())
        #expect(result.outcome == .degraded)
        #expect(result.model.facetSnapshots.allocation.sectorBreakdown.count == 1)
        #expect(result.model.facetSnapshots.allocation.xRayHoldings?.count == 2)
        #expect(result.model.facetSnapshots.income.upcomingEvents.count == 1)
        #expect(result.model.facetSnapshots.bigMovers.priceSeriesCount == 2)
        #expect(committed.sectors.count == 1)
        #expect(committed.xRayHoldings?.count == 2)
        #expect(committed.incomeEvents.count == 1)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101])
        #expect(connector.calls.filter { $0 == "pdt-list-symbol-prices" }.count == 3)

        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.toolName == "pdt-list-symbol-prices")
        #expect(diagnostic.phase == .priceHistory)
        #expect(diagnostic.attemptCount == 2)
        #expect(diagnostic.category == .missingScriptedResponse)
        #expect(diagnostic.argumentShape == ["date_from", "date_to", "symbol_quote_id"])
    }

    @Test("Retry after degraded completion replaces diagnostic with complete details")
    func retryAfterDegradedCompletionReplacesDiagnosticWithCompleteDetails() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-retry-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        _ = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses(omittingPriceQuoteID: 9102)),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let retry = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses()),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let committed = try #require(try store.loadPriorSnapshot())
        #expect(retry.outcome == .completed)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
        #expect(try store.loadLastDetailRefreshDiagnostic() == nil)
    }

    @Test("Failed optional phase preserves prior detail slice")
    func failedOptionalPhasePreservesPriorDetailSlice() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-prior-allocation-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(testSnapshot(
            asOf: "2026-03-28",
            sectorName: "Prior Technology",
            assetTypeName: "Prior Stock"
        ))
        var responses = try detailRefreshResponses()
        responses.removeValue(forKey: "pdt-get-portfolio-distributions")

        let result = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: responses),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let committed = try #require(try store.loadPriorSnapshot())
        #expect(result.outcome == .degraded)
        #expect(committed.sectors.map(\.name) == ["Prior Technology"])
        #expect(committed.assetTypes.map(\.name) == ["Prior Stock"])
        #expect(committed.xRayHoldings?.count == 2)
        #expect(committed.incomeEvents.count == 1)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
    }

    @Test("Failed price history preserves prior series for that quote")
    func failedPriceHistoryPreservesPriorSeriesForThatQuote() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-prior-prices-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(testSnapshot(asOf: "2026-03-28"))

        let result = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses(omittingPriceQuoteID: 9102)),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let committed = try #require(try store.loadPriorSnapshot())
        #expect(result.outcome == .degraded)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
        #expect(committed.priceSeries.filter { $0.quoteId == 9102 }.map(\.date) == ["2026-03-20", "2026-03-21"])
    }

    @Test("Failed X-ray or income phase preserves prior optional detail")
    func failedXRayOrIncomePhasePreservesPriorOptionalDetail() throws {
        try assertPriorOptionalDetailPreservedWhenRemovingResponse(
            "pdt-list-x-ray-holdings?limit=500&offset=0",
            prefix: "pdtbar-detail-refresh-prior-xray-test"
        ) { committed in
            #expect(committed.xRayHoldings == [XRayHoldingSummary(weight: 25.0), XRayHoldingSummary(weight: 15.0)])
            #expect(committed.incomeEvents.count == 1)
        }

        try assertPriorOptionalDetailPreservedWhenRemovingResponse(
            "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28",
            prefix: "pdtbar-detail-refresh-prior-income-test"
        ) { committed in
            #expect(committed.xRayHoldings == [XRayHoldingSummary(weight: 0.25), XRayHoldingSummary(weight: 0.15)])
            #expect(committed.incomeEvents.first?.amount == Money(value: "7.00", currency: "EUR"))
        }
    }

    @Test("Background refresh resets reappeared read-state items")
    func backgroundRefreshResetsReappearedReadStateItems() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-read-state-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let readStore = PulseReadStore(directory: store.directory)
        let currentSnapshot = try testSnapshot(asOf: "2026-03-29")
        let originalItem = try #require(
            PressureEngine.buildModel(from: currentSnapshot).rankedAttentionItems.first {
                $0.holdingIdentity?.quoteId == 9101
            }
        )
        var priorSnapshot = currentSnapshot
        priorSnapshot.asOf = "2026-03-28"
        priorSnapshot.openHoldings[0].weight = 0.19

        try readStore.markRead(originalItem.readFingerprint)
        _ = try store.commitCurrentSnapshot(priorSnapshot)

        let result = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses()),
            snapshotStore: store,
            pulseReadStore: readStore,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.model.rankedAttentionItems.contains {
            $0.readFingerprint == originalItem.readFingerprint
        })
        #expect(!((try readStore.load()).contains(originalItem.readFingerprint)))
    }

    @Test("Progress callbacks are phase-aware with price-history totals")
    func progressCallbacksArePhaseAwareWithPriceHistoryTotals() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-progress-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let recorder = DetailProgressRecorder()

        _ = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses()),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh { recorder.append($0) }

        let progress = recorder.values
        #expect(progress.map(\.phase).contains(.baseHoldings))
        #expect(progress.map(\.phase).contains(.allocation))
        #expect(progress.map(\.phase).contains(.xRay))
        #expect(progress.map(\.phase).contains(.income))
        #expect(progress.contains {
            $0.phase == .priceHistory && $0.completedUnitCount == 2 && $0.totalUnitCount == 2
        })
    }

    @Test("Price-history refresh honors bounded concurrency")
    func priceHistoryRefreshHonorsBoundedConcurrency() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-concurrency-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = ConcurrencyTrackingPDTConnector(
            responses: try detailRefreshResponses(includingThirdHolding: true)
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .completed)
        #expect(result.model.facetSnapshots.bigMovers.priceSeriesCount == 6)
        #expect(connector.maxActivePriceCalls == 2)
    }

    @Test("Required base holdings retries a missing Claude tool call")
    func requiredBaseHoldingsRetriesMissingClaudeToolCall() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-base-retry-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = OneShotFailingPDTConnector(
            responses: try detailRefreshResponses(),
            failures: [
                "pdt-get-portfolio-holdings": .setupUnavailable("Claude did not call mcp__pdt__pdt-get-portfolio-holdings"),
            ]
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .completed)
        #expect(connector.calls.filter { $0 == "pdt-get-portfolio-holdings" }.count == 2)
        #expect(try store.loadLastDetailRefreshDiagnostic() == nil)
    }

    @Test("Required base holdings failure persists a redacted diagnostic")
    func requiredBaseHoldingsFailurePersistsRedactedDiagnostic() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-base-failure-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(testSnapshot(asOf: "2026-03-28"))

        do {
            _ = try PDTBackgroundDetailRefresh(
                connector: ScriptedPDTMCPConnector(
                    responses: try detailRefreshResponses(),
                    failure: .setupUnavailable("Claude did not call mcp__pdt__pdt-get-portfolio-holdings")
                ),
                snapshotStore: store,
                asOf: "2026-03-29",
                options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
            ).refresh()
            Issue.record("Expected required base holdings failure to throw")
        } catch {
            let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
            #expect(diagnostic.toolName == "pdt-get-portfolio-holdings")
            #expect(diagnostic.phase == .baseHoldings)
            #expect(diagnostic.attemptCount == 2)
            #expect(diagnostic.category == .setupUnavailable)
            #expect(diagnostic.argumentShape == [])

            let committed = try #require(try store.loadPriorSnapshot())
            #expect(committed.asOf == "2026-03-28")
            #expect(committed.sectors.count == 1)
            #expect(committed.priceSeries.count == 4)
        }
    }
}

private final class DetailProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [BackgroundDetailRefreshProgress] = []

    var values: [BackgroundDetailRefreshProgress] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recorded
    }

    func append(_ progress: BackgroundDetailRefreshProgress) {
        lock.lock()
        recorded.append(progress)
        lock.unlock()
    }
}

private final class ConcurrencyTrackingPDTConnector: PDTMCPConnector, @unchecked Sendable {
    let responses: [String: Data]
    private let lock = NSLock()
    private var activePriceCalls = 0
    private(set) var maxActivePriceCalls = 0

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        let isPriceCall = name == "pdt-list-symbol-prices"
        if isPriceCall {
            lock.lock()
            activePriceCalls += 1
            maxActivePriceCalls = max(maxActivePriceCalls, activePriceCalls)
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.03)
        }
        defer {
            if isPriceCall {
                lock.lock()
                activePriceCalls -= 1
                lock.unlock()
            }
        }
        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(key)
        }
        return response
    }
}

private final class OneShotFailingPDTConnector: PDTMCPConnector, @unchecked Sendable {
    let responses: [String: Data]
    private var failures: [String: PDTMCPConnectorError]
    private let lock = NSLock()
    private(set) var calls: [String] = []

    init(responses: [String: Data], failures: [String: PDTMCPConnectorError]) {
        self.responses = responses
        self.failures = failures
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        if let failure = failures.removeValue(forKey: name) {
            lock.unlock()
            throw failure
        }
        lock.unlock()

        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(key)
        }
        return response
    }
}

private func detailRefreshResponses(
    omittingPriceQuoteID omittedQuoteID: Int? = nil,
    includingThirdHolding: Bool = false,
    calendarSymbolID: Int? = nil,
    calendarSymbolName: String = "Scripted Adapter A"
) throws -> [String: Data] {
    let thirdHolding = includingThirdHolding ? """
            ,
            {
              "symbolName": "Scripted Adapter C",
              "symbolQuoteId": 9103,
              "currentPriceDate": "2026-03-29T22:00:00+00:00",
              "currentPriceLocal": { "value": "40.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "100.00", "currency": "EUR" },
              "portfolioWeight": 0.10,
              "closedAt": null
            }
    """ : ""
    var responses: [String: Data] = [
        "pdt-get-portfolio-holdings": try mcpContent("""
        {
          "holdings": [
            {
              "symbolName": "Scripted Adapter A",
              "symbolQuoteId": 9101,
              "currentPriceDate": "2026-03-29T22:00:00+00:00",
              "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
              "portfolioWeight": 0.25,
              "closedAt": null
            },
            {
              "symbolName": "Scripted Adapter B",
              "symbolQuoteId": 9102,
              "currentPriceDate": "2026-03-29T22:00:00+00:00",
              "currentPriceLocal": { "value": "30.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "150.00", "currency": "EUR" },
              "portfolioWeight": 0.15,
              "closedAt": null
            }
            \(thirdHolding)
          ]
        }
        """),
        "pdt-get-portfolio-distributions": try mcpResult("""
        {
          "sectors": [
            { "categoryName": "Technology", "totalValue": { "value": "400.00", "currency": "EUR" }, "percentage": 100.0 }
          ],
          "assetTypes": [
            { "categoryName": "Stock", "totalValue": { "value": "400.00", "currency": "EUR" }, "percentage": 100.0 }
          ]
        }
        """),
        "pdt-list-x-ray-holdings?limit=500&offset=0": try mcpResult("""
        {
          "items": [
            { "weight": 25.0 },
            { "weight": 15.0 }
          ],
          "hasMore": false
        }
        """),
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": \(calendarSymbolID.map(String.init) ?? "null"), "symbolName": "\(calendarSymbolName)" }
          ]
        }
        """),
        "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=250": try mcpResult("""
        {
          "data": [
            { "date": "2026-03-28T08:13:00+00:00", "amount": { "value": "8.00", "currency": "EUR" }, "symbolQuoteId": 9101 },
            { "date": "2026-03-28T08:13:00+00:00", "amount": { "value": "6.00", "currency": "EUR" }, "symbolQuoteId": 9102 }
          ],
          "meta": { "last_page": 1 }
        }
        """),
        "pdt-get-symbol-quote?id=9101": try mcpContent("""
        { "id": 9101, "code": "ADPA", "symbolId": 5101 }
        """),
        "pdt-get-symbol-quote?id=9102": try mcpContent("""
        { "id": 9102, "code": "ADPB", "symbolId": 5102 }
        """),
    ]
    if omittedQuoteID != 9101 {
        responses["pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9101"] = try mcpContent("""
        {
          "data": [
            { "date": "2026-03-27", "closeAdjusted": "19.00", "symbolQuoteId": 9101 },
            { "date": "2026-03-29", "closeAdjusted": "20.00", "symbolQuoteId": 9101 }
          ]
        }
        """)
    }
    if omittedQuoteID != 9102 {
        responses["pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9102"] = try mcpContent("""
        {
          "data": [
            { "date": "2026-03-27", "closeAdjusted": "28.00", "symbolQuoteId": 9102 },
            { "date": "2026-03-29", "closeAdjusted": "30.00", "symbolQuoteId": 9102 }
          ]
        }
        """)
    }
    if includingThirdHolding, omittedQuoteID != 9103 {
        responses["pdt-get-symbol-quote?id=9103"] = try mcpContent("""
        { "id": 9103, "code": "ADPC", "symbolId": 5103 }
        """)
        responses["pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9103"] = try mcpContent("""
        {
          "data": [
            { "date": "2026-03-27", "closeAdjusted": "39.00", "symbolQuoteId": 9103 },
            { "date": "2026-03-29", "closeAdjusted": "40.00", "symbolQuoteId": 9103 }
          ]
        }
        """)
    }
    return responses
}

private func testSnapshot(
    asOf: String,
    sectorName: String = "Technology",
    assetTypeName: String = "Stock"
) throws -> PortfolioSnapshot {
    let json = """
    {
      "asOf": "\(asOf)",
      "totalValue": { "value": "400.00", "currency": "EUR" },
      "openHoldings": [
        {
          "name": "Scripted Adapter A",
          "quoteId": 9101,
          "weight": 0.25,
          "worth": { "value": "250.00", "currency": "EUR" },
          "price": { "value": "20.00", "currency": "EUR" },
          "priceAsOf": "\(asOf)"
        },
        {
          "name": "Scripted Adapter B",
          "quoteId": 9102,
          "weight": 0.15,
          "worth": { "value": "150.00", "currency": "EUR" },
          "price": { "value": "30.00", "currency": "EUR" },
          "priceAsOf": "\(asOf)"
        }
      ],
      "sectors": [
        { "name": "\(sectorName)", "percentage": 100.0, "totalValue": { "value": "400.00", "currency": "EUR" } }
      ],
      "assetTypes": [
        { "name": "\(assetTypeName)", "percentage": 100.0, "totalValue": { "value": "400.00", "currency": "EUR" } }
      ],
      "xRayHoldings": [
        { "weight": 25.0 },
        { "weight": 15.0 }
      ],
      "incomeEvents": [
        {
          "date": "2026-03-30",
          "kind": "ex-dividend",
          "symbolName": "Scripted Adapter A",
          "estimated": false,
          "symbolId": null,
          "quoteId": 9101,
          "amount": { "value": "7.00", "currency": "EUR" },
          "priorAmount": null,
          "changePercent": null
        }
      ],
      "dividendRowCount": 1,
      "priceSeries": [
        { "quoteId": 9101, "date": "2026-03-20", "closeAdjusted": "18.00" },
        { "quoteId": 9101, "date": "2026-03-21", "closeAdjusted": "19.00" },
        { "quoteId": 9102, "date": "2026-03-20", "closeAdjusted": "27.00" },
        { "quoteId": 9102, "date": "2026-03-21", "closeAdjusted": "28.00" }
      ]
    }
    """
    return try JSONDecoder().decode(PortfolioSnapshot.self, from: Data(json.utf8))
}

private func assertPriorOptionalDetailPreservedWhenRemovingResponse(
    _ responseKey: String,
    prefix: String,
    expectations: (PortfolioSnapshot) throws -> Void
) throws {
    let store = try SnapshotStore.temporaryTestStore(prefix: prefix)
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    _ = try store.commitCurrentSnapshot(testSnapshot(asOf: "2026-03-28"))
    var responses = try detailRefreshResponses()
    responses.removeValue(forKey: responseKey)

    let result = try PDTBackgroundDetailRefresh(
        connector: ScriptedPDTMCPConnector(responses: responses),
        snapshotStore: store,
        asOf: "2026-03-29",
        options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
    ).refresh()

    let committed = try #require(try store.loadPriorSnapshot())
    #expect(result.outcome == .degraded)
    try expectations(committed)
}

private func mcpContent(_ json: String) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "content": [
                [
                    "type": "text",
                    "text": json,
                ],
            ],
        ],
        options: [.sortedKeys]
    )
}

private func mcpResult(_ json: String) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONSerialization.data(withJSONObject: ["result": object], options: [.sortedKeys])
}
