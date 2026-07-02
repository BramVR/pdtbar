import Foundation
import Testing
import PDTBarCore

// Serialized: every refresh test parks one thread in the price-history
// phase's DispatchGroup.wait and spawns worker threads besides it. Running
// twenty-plus of those concurrently exhausts libdispatch's thread pool, so
// workers never get scheduled and each parked wait only returns after the full
// 240-second price-history budget.
@Suite("Background detail refresh", .serialized)
struct BackgroundDetailRefreshTests {
    @Test("Default price-history budget covers Claude CLI batches")
    func defaultPriceHistoryBudgetCoversClaudeCLIBatches() {
        let defaults = PDTBackgroundDetailRefreshOptions()

        #expect(defaults.effectivePriceHistoryTimeoutSeconds(holdingCount: 19) >= 240)
        #expect(defaults.effectivePriceHistoryTimeoutSeconds(holdingCount: 50) >= 390)
        #expect(PDTBackgroundDetailRefreshOptions(
            priceHistoryTimeoutSeconds: 0.05
        ).effectivePriceHistoryTimeoutSeconds(holdingCount: 50) == 0.05)
    }

    @Test("Background refresh reuses cached income quote mapping")
    func backgroundRefreshReusesCachedIncomeQuoteMapping() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-join-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(PortfolioSnapshot(
            asOf: "2026-03-28",
            totalValue: Money(value: "0.00", currency: "EUR"),
            openHoldings: [],
            sectors: [],
            assetTypes: [],
            incomeEvents: [
                IncomeEventSummary(
                    date: "2026-03-29",
                    kind: "ex-dividend",
                    symbolName: "Scripted Adapter B",
                    estimated: false,
                    symbolId: 5102,
                    quoteId: 9102
                ),
            ],
            dividendRowCount: 0,
            priceSeries: []
        ))

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
        #expect(result.outcome == .completed)
        #expect(result.pulse.source == .refreshedSnapshot)
        #expect(result.snapshotCommit == result.pulse.snapshotCommit)
        #expect(result.descriptor == result.pulse.descriptor)
        #expect(event.symbolId == 5102)
        #expect(event.quoteId == 9102)
        #expect(event.amount == Money(value: "6.00", currency: "EUR"))
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.isEmpty)

        let holdingRow = try #require(
            result.descriptor.sections
                .first { $0.id == "allocation" }?
                .rows
                .first { $0.id == "allocation.portfolio.details" }?
                .children
                .first { $0.id == "allocation.9102" }
        )
        #expect(holdingRow.children.first { $0.id == "allocation.9102.nextIncome" }?.detail == "Ex-dividend date on 2026-03-30; confirmed; EUR 6.00")
    }

    @Test("Background refresh maps income by current holding name")
    func backgroundRefreshMapsIncomeByCurrentHoldingName() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-name-map-test")
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

        let event = try #require(result.model.facetSnapshots.income.upcomingEvents.first)
        #expect(event.symbolId == 5102)
        #expect(event.quoteId == 9102)
        #expect(event.amount == Money(value: "6.00", currency: "EUR"))
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.isEmpty)
    }

    @Test("Background refresh falls back to symbol quote when income name differs")
    func backgroundRefreshFallsBackToSymbolQuoteWhenIncomeNameDiffers() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-symbol-fallback-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = ScriptedPDTMCPConnector(
            responses: try detailRefreshResponses(calendarSymbolID: 5102, calendarSymbolName: "ADPB")
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let event = try #require(result.model.facetSnapshots.income.upcomingEvents.first)
        #expect(event.symbolId == 5102)
        #expect(event.quoteId == 9102)
        #expect(event.amount == Money(value: "6.00", currency: "EUR"))
        #expect(connector.calls.contains("pdt-get-symbol-quote"))
    }

    @Test("Background refresh ignores stale cached income quote mapping")
    func backgroundRefreshIgnoresStaleCachedIncomeQuoteMapping() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-stale-cache-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(PortfolioSnapshot(
            asOf: "2026-03-28",
            totalValue: Money(value: "0.00", currency: "EUR"),
            openHoldings: [],
            sectors: [],
            assetTypes: [],
            incomeEvents: [
                IncomeEventSummary(
                    date: "2026-03-29",
                    kind: "ex-dividend",
                    symbolName: "Old Adapter B",
                    estimated: false,
                    symbolId: 5102,
                    quoteId: 9999
                ),
            ],
            dividendRowCount: 0,
            priceSeries: []
        ))
        let connector = ScriptedPDTMCPConnector(
            responses: try detailRefreshResponses(calendarSymbolID: 5102, calendarSymbolName: "ADPB")
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        let event = try #require(result.model.facetSnapshots.income.upcomingEvents.first)
        #expect(event.symbolId == 5102)
        #expect(event.quoteId == 9102)
        #expect(event.amount == Money(value: "6.00", currency: "EUR"))
        #expect(connector.calls.contains("pdt-get-symbol-quote"))
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
        #expect(result.pulse.source == .refreshedSnapshot)
        #expect(result.snapshotCommit == result.pulse.snapshotCommit)
        #expect(result.descriptor == result.pulse.descriptor)
        #expect(result.model.facetSnapshots.allocation.sectorBreakdown.count == 1)
        #expect(result.model.facetSnapshots.allocation.xRayHoldings?.count == 2)
        #expect(result.model.facetSnapshots.income.upcomingEvents.count == 1)
        #expect(result.model.facetSnapshots.bigMovers.priceSeriesCount == 2)
        #expect(committed.sectors.count == 1)
        #expect(committed.xRayHoldings?.count == 2)
        #expect(committed.incomeEvents.count == 1)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101])
        // The missing scripted response is deterministic, so the failing
        // holding gets exactly one attempt instead of a retry.
        #expect(connector.calls.filter { $0 == "pdt-list-symbol-prices" }.count == 2)

        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.toolName == "pdt-list-symbol-prices")
        #expect(diagnostic.phase == .priceHistory)
        #expect(diagnostic.attemptCount == 1)
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

    @Test("Corrupt prior snapshot is surfaced during background refresh")
    func corruptPriorSnapshotIsSurfacedDuringBackgroundRefresh() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-corrupt-prior-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        try Data("{".utf8).write(to: store.currentSnapshotPath)

        let result = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: try detailRefreshResponses()),
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .completed)
        #expect(result.pulse.priorSnapshotLoadStatus == .failed(.decode))
        #expect(result.model.facetSnapshots.dataHealth.cache.priorSnapshotStatus == .corrupt)
        #expect(result.model.portfolioGlance.priorSnapshotAsOf == nil)
    }

    @Test("New refresh clears stale diagnostic before setup failure")
    func newRefreshClearsStaleDiagnosticBeforeSetupFailure() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-stale-diagnostic-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        try store.saveLastDetailRefreshDiagnostic(
            PDTDetailRefreshFailureDiagnostic(
                toolName: "pdt-list-symbol-prices",
                phase: .priceHistory,
                attemptCount: 1,
                category: .transientFailure,
                argumentShape: ["symbol_quote_id"]
            )
        )

        #expect(throws: Error.self) {
            _ = try PDTBackgroundDetailRefresh(
                connector: ScriptedPDTMCPConnector(availableTools: [], responses: [:]),
                snapshotStore: store,
                asOf: "2026-03-29",
                options: PDTBackgroundDetailRefreshOptions(retryBackoffSeconds: 0)
            ).refresh()
        }
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
            "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28&page=1&per_page=250",
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
            $0.phase == .baseHoldings && $0.detail == "Checking PDT tools"
        })
        #expect(progress.contains {
            $0.phase == .baseHoldings && $0.detail == "Calling pdt-get-portfolio-holdings"
        })
        #expect(progress.contains {
            $0.phase == .priceHistory && $0.detail == "Calling pdt-list-symbol-prices"
        })
        #expect(!progress.contains {
            $0.phase == .priceHistory && $0.detail != nil && ($0.completedUnitCount == nil || $0.totalUnitCount == nil)
        })
        #expect(progress.contains {
            $0.phase == .priceHistory && $0.completedUnitCount == 2 && $0.totalUnitCount == 2
        })
    }

    @Test("Tool discovery progress is forwarded before first read call")
    func toolDiscoveryProgressIsForwardedBeforeFirstReadCall() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-tool-discovery-progress-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let recorder = DetailProgressRecorder()
        let connector = ProgressReportingPDTConnector(responses: try detailRefreshResponses())

        _ = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh { recorder.append($0) }

        let details = recorder.values.compactMap(\.detail)
        let discoveryIndex = try #require(details.firstIndex(of: "Waiting on Claude for PDT tool discovery"))
        let holdingsIndex = try #require(details.firstIndex(of: "Calling pdt-get-portfolio-holdings"))
        #expect(discoveryIndex < holdingsIndex)
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

    @Test("Price-history refresh returns after bounded timeout")
    func priceHistoryRefreshReturnsAfterBoundedTimeout() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-timeout-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = SlowPriceHistoryPDTConnector(
            responses: try detailRefreshResponses(includingThirdHolding: true),
            priceDelaySeconds: 1.0
        )

        let startedAt = Date()
        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(
                priceHistoryConcurrencyLimit: 2,
                priceHistoryTimeoutSeconds: 0.05,
                retryBackoffSeconds: 0
            )
        ).refresh()
        let elapsedSeconds = Date().timeIntervalSince(startedAt)

        #expect(result.outcome == .degraded)
        #expect(elapsedSeconds < 0.5)
        #expect(connector.maxActivePriceCalls <= 2)
        #expect(result.diagnostics.contains {
            $0.phase == .priceHistory && $0.category == .timeout
        })
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
                "pdt-get-portfolio-holdings": .transientFailure("Claude did not call mcp__pdt__pdt-get-portfolio-holdings"),
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
                    failure: .setupUnavailable("Claude PDT MCP server is not connected")
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
            // Setup outages are deterministic for the refresh, so the failure
            // is recorded after a single attempt instead of burning retries.
            #expect(diagnostic.attemptCount == 1)
            #expect(diagnostic.category == .setupUnavailable)
            #expect(diagnostic.argumentShape == [])

            let committed = try #require(try store.loadPriorSnapshot())
            #expect(committed.asOf == "2026-03-28")
            #expect(committed.sectors.count == 1)
            #expect(committed.priceSeries.count == 4)
        }
    }

    @Test("Deterministic decode failures are not retried in optional phases")
    func deterministicDecodeFailuresAreNotRetriedInOptionalPhases() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-decode-no-retry-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        var responses = try detailRefreshResponses()
        responses["pdt-get-portfolio-distributions"] = Data("{".utf8)
        let connector = SelectiveFailingPDTConnector(responses: responses)

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .degraded)
        // Same malformed payload on every attempt: one full call is enough.
        #expect(connector.callCount(of: "pdt-get-portfolio-distributions") == 1)
        #expect(result.diagnostics.contains {
            $0.toolName == "pdt-get-portfolio-distributions"
                && $0.phase == .allocation
                && $0.category == .decode
                && $0.attemptCount == 1
        })
        // A decode mismatch is tool-specific, not an outage: later phases run.
        #expect(connector.callCount(of: "pdt-list-calendar-events") == 1)
        #expect(connector.callCount(of: "pdt-list-symbol-prices") == 2)
    }

    @Test("Unavailable setup failure short-circuits the remaining detail phases")
    func unavailableSetupFailureShortCircuitsRemainingDetailPhases() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-short-circuit-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(testSnapshot(asOf: "2026-03-28"))
        let connector = SelectiveFailingPDTConnector(
            responses: try detailRefreshResponses(),
            failures: [
                "pdt-get-portfolio-distributions": .setupUnavailable("Claude PDT MCP server is not connected"),
            ]
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .degraded)
        // One failing attempt for the outage; the X-ray, income, and
        // price-history phases must not spawn further doomed Claude runs.
        #expect(connector.callCount(of: "pdt-get-portfolio-distributions") == 1)
        #expect(connector.callCount(of: "pdt-list-x-ray-holdings") == 0)
        #expect(connector.callCount(of: "pdt-list-calendar-events") == 0)
        #expect(connector.callCount(of: "pdt-list-dividends") == 0)
        #expect(connector.callCount(of: "pdt-get-symbol-quote") == 0)
        #expect(connector.callCount(of: "pdt-list-symbol-prices") == 0)
        #expect(result.diagnostics.map(\.category) == [.setupUnavailable])

        // Prior optional details stay visible instead of being discarded.
        let committed = try #require(try store.loadPriorSnapshot())
        #expect(committed.sectors.map(\.name) == ["Technology"])
        #expect(committed.xRayHoldings?.count == 2)
        #expect(committed.incomeEvents.count == 1)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
    }

    @Test("Income quote scan honors its deadline and degrades instead of blocking")
    func incomeQuoteScanHonorsDeadlineAndDegrades() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-deadline-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = SelectiveFailingPDTConnector(
            responses: try detailRefreshResponses(calendarSymbolID: 5102, calendarSymbolName: "ADPB"),
            delaySecondsByTool: ["pdt-get-symbol-quote": 0.2]
        )

        let startedAt = Date()
        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(
                priceHistoryConcurrencyLimit: 2,
                incomeQuoteLookupTimeoutSeconds: 0.05,
                retryBackoffSeconds: 0
            )
        ).refresh()
        let elapsedSeconds = Date().timeIntervalSince(startedAt)

        #expect(result.outcome == .degraded)
        #expect(elapsedSeconds < 2.0)
        // The scan stops at the deadline instead of walking every holding.
        #expect(connector.callCount(of: "pdt-get-symbol-quote") == 1)
        #expect(result.diagnostics.contains {
            $0.toolName == "pdt-get-symbol-quote"
                && $0.phase == .income
                && $0.category == .timeout
                && $0.argumentShape == ["id"]
        })

        // The partial mapping still publishes income events.
        let committed = try #require(try store.loadPriorSnapshot())
        #expect(committed.incomeEvents.count == 1)
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
    }

    @Test("Income quote scan does not start retries after its deadline passes")
    func incomeQuoteScanDoesNotStartRetriesAfterDeadlinePasses() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-income-deadline-retry-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = SelectiveFailingPDTConnector(
            responses: try detailRefreshResponses(calendarSymbolID: 5102, calendarSymbolName: "ADPB"),
            failures: [
                "pdt-get-symbol-quote": .transientFailure("Claude pdt-get-symbol-quote call timed out"),
            ],
            delaySecondsByTool: ["pdt-get-symbol-quote": 0.1]
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(
                priceHistoryConcurrencyLimit: 2,
                incomeQuoteLookupTimeoutSeconds: 0.05,
                optionalRetryCount: 1,
                retryBackoffSeconds: 0
            )
        ).refresh()

        #expect(result.outcome == .degraded)
        // The transient lookup failure would normally earn a retry, but the
        // deadline already passed, so no second full Claude run starts.
        #expect(connector.callCount(of: "pdt-get-symbol-quote") == 1)
        #expect(result.diagnostics.contains {
            $0.toolName == "pdt-get-symbol-quote"
                && $0.phase == .income
                && $0.category == .timeout
        })

        let committed = try #require(try store.loadPriorSnapshot())
        #expect(committed.incomeEvents.count == 1)
    }

    @Test("Price-history workers stop pulling holdings after an unavailable setup failure")
    func priceHistoryWorkersStopAfterUnavailableSetupFailure() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-detail-refresh-price-abandon-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        _ = try store.commitCurrentSnapshot(testSnapshot(asOf: "2026-03-28"))
        let connector = SelectiveFailingPDTConnector(
            responses: try detailRefreshResponses(includingThirdHolding: true),
            failures: [
                "pdt-list-symbol-prices": .setupUnavailable("Claude PDT MCP server is not connected"),
            ]
        )

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 1, retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .degraded)
        // One failing price call reveals the outage; the other holdings are
        // abandoned instead of each spawning another doomed Claude run.
        #expect(connector.callCount(of: "pdt-list-symbol-prices") == 1)
        let priceDiagnostics = result.diagnostics.filter { $0.phase == .priceHistory }
        #expect(priceDiagnostics.count == 3)
        #expect(priceDiagnostics.allSatisfy { $0.category == .setupUnavailable })

        // Prior price series for the abandoned holdings stay visible.
        let committed = try #require(try store.loadPriorSnapshot())
        #expect(committed.priceSeries.map(\.quoteId) == [9101, 9101, 9102, 9102])
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

private final class SlowPriceHistoryPDTConnector: PDTMCPConnector, @unchecked Sendable {
    let responses: [String: Data]
    let priceDelaySeconds: TimeInterval
    private let lock = NSLock()
    private var activePriceCalls = 0
    private(set) var maxActivePriceCalls = 0

    init(responses: [String: Data], priceDelaySeconds: TimeInterval) {
        self.responses = responses
        self.priceDelaySeconds = priceDelaySeconds
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
            Thread.sleep(forTimeInterval: priceDelaySeconds)
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

private final class SelectiveFailingPDTConnector: PDTMCPConnector, @unchecked Sendable {
    let responses: [String: Data]
    private let failures: [String: PDTMCPConnectorError]
    private let delaySecondsByTool: [String: TimeInterval]
    private let lock = NSLock()
    private var calls: [String] = []

    init(
        responses: [String: Data],
        failures: [String: PDTMCPConnectorError] = [:],
        delaySecondsByTool: [String: TimeInterval] = [:]
    ) {
        self.responses = responses
        self.failures = failures
        self.delaySecondsByTool = delaySecondsByTool
    }

    func callCount(of name: String) -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return calls.filter { $0 == name }.count
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        lock.unlock()
        if let delay = delaySecondsByTool[name], delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        if let failure = failures[name] {
            throw failure
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

private final class ProgressReportingPDTConnector: PDTMCPConnector, PDTMCPConnectorProgressReporting, @unchecked Sendable {
    let responses: [String: Data]

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func availableReadTools(
        required: Set<String>,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String> {
        progress("Waiting on Claude for PDT tool discovery")
        return required
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
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
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28&page=1&per_page=250": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": \(calendarSymbolID.map(String.init) ?? "null"), "symbolName": "\(calendarSymbolName)" }
          ],
          "meta": { "last_page": 1 }
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
