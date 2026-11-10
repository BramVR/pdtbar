import Foundation
import Testing
import PDTBarCore

@Suite("PDT API background detail refresh")
struct PDTAPIBackgroundDetailRefreshTests {
    @Test("A complete refresh reads every facet over GET with no tool discovery or per-holding lookups")
    func completeRefresh() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport(try fullReplies())
        let recorder = ProgressRecorder()

        let result = try refresh(transport, store: store).refresh(cancellation: nil, progress: recorder.record)

        #expect(transport.requests.map { $0.url!.path } == [
            "/v1/portfolio/holdings",
            "/v1/portfolio/distributions",
            "/v1/x-ray", "/v1/x-ray",
            "/v1/calendar-events", "/v1/calendar-events",
            "/v1/dividends",
            "/v1/prices/batch",
        ])
        #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.portfoliodividendtracker.com" })
        #expect(result.outcome == .completed)
        #expect(result.failures.isEmpty)
        #expect(recorder.phases == BackgroundDetailRefreshPhase.allCases)

        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.asOf == "2026-06-22")
        #expect(saved.latestDetailFillOutcome == .completed)
        #expect(saved.latestCompleteDetailFillAsOf == "2026-06-22")
        #expect(saved.openHoldings.map(\.quoteId) == [9001, 9002, 9003, 9004, 9010, 9013])
        #expect(!saved.sectors.isEmpty)
        #expect(saved.xRayHoldings?.count == 3)
        #expect(!saved.incomeEvents.isEmpty)
        #expect(saved.incomeEvents.allSatisfy { $0.quoteId != nil })
        #expect(Set(saved.priceSeries.map(\.quoteId)) == [9001, 9004])
        #expect(saved.performance == nil)
        #expect(store.lastSyncFailure() == nil)
    }

    @Test("A failed required base throws, keeps the last good snapshot, and records the failure")
    func baseFailureKeepsLastGoodSnapshot() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport([apiError(503, "SERVICE_UNAVAILABLE")])

        #expect(throws: PDTAPIError.self) {
            try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })
        }

        #expect(transport.requests.count == 1)
        #expect(try store.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
        #expect(store.lastSyncFailure() == PDTSyncFailure(
            phase: .baseHoldings,
            endpoint: .holdings,
            kind: .server(status: 503),
            requestCount: 1
        ))
    }

    @Test("A refresh that completes clears the failure an earlier refresh recorded")
    func completedRefreshClearsEarlierFailure() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try? refresh(ScriptedPDTHTTPTransport([apiError(503, "SERVICE_UNAVAILABLE")]), store: store)
            .refresh(cancellation: nil, progress: { _ in })
        #expect(store.lastSyncFailure() != nil)

        let result = try refresh(ScriptedPDTHTTPTransport(try fullReplies()), store: store)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .completed)
        #expect(store.lastSyncFailure() == nil)
    }

    @Test("A retried base failure persists the number of requests actually sent")
    func baseFailurePersistsRequestCount() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport(Array(repeating: apiError(503, "SERVICE_UNAVAILABLE"), count: 3))

        #expect(throws: PDTAPIError.server(status: 503, retryAfter: nil)) {
            try refresh(transport, store: store, maxAttempts: 3).refresh(cancellation: nil, progress: { _ in })
        }

        #expect(transport.requests.count == 3)
        #expect(store.lastSyncFailure()?.requestCount == 3)
    }

    @Test("A paged optional facet that fails after retries persists every request it sent")
    func optionalFailurePersistsRequestCount() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        let unavailable = apiError(503, "SERVICE_UNAVAILABLE")
        replies.replaceSubrange(5...6, with: [unavailable, unavailable, unavailable])
        let transport = ScriptedPDTHTTPTransport(replies)

        let result = try refresh(transport, store: store, maxAttempts: 3).refresh(cancellation: nil, progress: { _ in })

        let calendarRequests = transport.requests.filter { $0.url!.path == "/v1/calendar-events" }.count
        #expect(calendarRequests == 4)
        #expect(result.failures.map(\.requestCount) == [calendarRequests])
        #expect(store.lastSyncFailure()?.requestCount == calendarRequests)
    }

    @Test("A failed optional facet keeps its last good value and degrades the outcome")
    func optionalFailureKeepsLastGoodFacet() throws {
        let store = try seededStore { $0.sectors = [DistributionSummary(name: "last-good", percentage: 100, totalValue: Money(value: "1", currency: "EUR"))] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        replies[1] = apiError(500, "SERVER_ERROR")

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .degraded)
        #expect(result.failures.map(\.phase) == [.allocation])
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.asOf == "2026-06-22")
        #expect(saved.sectors.map(\.name) == ["last-good"])
        #expect(saved.xRayHoldings?.count == 3)
        #expect(saved.latestDetailFillOutcome == .degraded)
        #expect(saved.latestCompleteDetailFillAsOf == seededAsOf)
        #expect(store.lastSyncFailure()?.endpoint == .distributions)
    }

    @Test("A rate limit longer than the retry budget ends the sync instead of stalling or asking PDT again")
    func longRateLimitEndsSync() throws {
        let store = try seededStore { $0.xRayHoldings = [XRayHoldingSummary(weight: 0.42)] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let seeded = try #require(try store.loadPriorSnapshotResult().snapshot)
        var replies = try fullReplies()
        replies.replaceSubrange(2...3, with: [rateLimited(retryAfter: "120")])
        let transport = ScriptedPDTHTTPTransport(replies)

        let result = try refresh(transport, store: store, maxAttempts: 3).refresh(cancellation: nil, progress: { _ in })

        #expect(transport.requests.map { $0.url!.path } == ["/v1/portfolio/holdings", "/v1/portfolio/distributions", "/v1/x-ray"])
        #expect(result.outcome == .degraded)
        #expect(result.failures.map(\.kind) == [.rateLimited(retryAfterSeconds: 120)])
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.xRayHoldings?.map(\.weight) == [0.42])
        #expect(saved.incomeEvents == seeded.incomeEvents)
        #expect(saved.priceSeries == seeded.priceSeries)
    }

    @Test("A short rate limit is retried and the refresh completes")
    func shortRateLimitRetries() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        replies.insert(rateLimited(retryAfter: "1"), at: 1)

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store, maxAttempts: 3)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .completed)
    }

    @Test("An auth outage skips every later phase and keeps the last good details")
    func outageSkipsLaterPhases() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let seeded = try #require(try store.loadPriorSnapshotResult().snapshot)
        var replies = try fullReplies()
        replies[1] = apiError(401, "TOKEN_INVALID", details: #"{"reason":"expired"}"#)
        let transport = ScriptedPDTHTTPTransport(replies)

        let result = try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(transport.requests.map { $0.url!.path } == ["/v1/portfolio/holdings", "/v1/portfolio/distributions"])
        #expect(result.outcome == .degraded)
        #expect(result.failures.map(\.kind) == [.reconnect])
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.xRayHoldings == seeded.xRayHoldings)
        #expect(saved.incomeEvents == seeded.incomeEvents)
        #expect(saved.priceSeries == seeded.priceSeries)
    }

    @Test("An auth outage in one price batch skips the remaining batches and keeps their last good prices")
    func priceOutageSkipsRemainingBatches() throws {
        let quoteIDs = Array(1...51)
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try refresh(
            ScriptedPDTHTTPTransport(syntheticReplies(quoteIDs: quoteIDs) + [prices(quoteID: 1), prices(quoteID: 51)]),
            store: store,
            asOf: seededAsOf
        ).refresh(cancellation: nil, progress: { _ in })
        let transport = ScriptedPDTHTTPTransport(
            syntheticReplies(quoteIDs: quoteIDs) + [apiError(401, "TOKEN_INVALID"), prices(quoteID: 51)]
        )

        let result = try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(transport.requests.filter { $0.url!.path == "/v1/prices/batch" }.count == 1)
        #expect(result.outcome == .degraded)
        #expect(result.failures.map(\.phase) == [.priceHistory])
        #expect(result.failures.map(\.kind) == [.reconnect])
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.asOf == "2026-06-22")
        #expect(Set(saved.priceSeries.map(\.quoteId)) == [1, 51])
    }

    @Test("Cancelling mid-refresh, as an account switch does, commits nothing")
    func cancelCommitsNothing() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let cancellation = PDTCancellation()
        let transport = CancellingTransport(
            inner: ScriptedPDTHTTPTransport(try fullReplies()),
            cancelAtRequest: 7,
            cancellation: cancellation
        )

        #expect(throws: (any Error).self) {
            try refresh(transport, store: store).refresh(cancellation: cancellation, progress: { _ in })
        }

        #expect(transport.inner.requests.count == 7)
        #expect(try store.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
    }

    @Test("Pagination stops at the page cap and degrades instead of looping")
    func paginationCapDegrades() throws {
        let store = try seededStore { $0.xRayHoldings = [XRayHoldingSummary(weight: 0.42)] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        let endless = ok(#"{"data":{"items":[{"symbolName":"Loop","weight":1}],"hasMore":true}}"#)
        replies.replaceSubrange(2...3, with: [endless, endless])
        let transport = ScriptedPDTHTTPTransport(replies)

        let result = try refresh(transport, store: store, maxPages: 2).refresh(cancellation: nil, progress: { _ in })

        #expect(transport.requests.filter { $0.url!.path == "/v1/x-ray" }.count == 2)
        #expect(result.outcome == .degraded)
        #expect(try store.loadPriorSnapshotResult().snapshot?.xRayHoldings?.map(\.weight) == [0.42])
    }

    @Test("An empty page before the last page degrades instead of replacing income with a partial list")
    func emptyMidListPageDegrades() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let seeded = try #require(try store.loadPriorSnapshotResult().snapshot)
        var replies = try fullReplies()
        replies.replaceSubrange(4...6, with: [ok(#"{"data":[],"meta":{"currentPage":1,"lastPage":3}}"#)])

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .degraded)
        #expect(result.failures.map(\.phase) == [.income])
        #expect(try store.loadPriorSnapshotResult().snapshot?.incomeEvents == seeded.incomeEvents)
    }

    @Test("A holding that crosses back into concentration clears its old read mark")
    func readStateResetsOnRecrossing() throws {
        let replies = syntheticReplies(quoteIDs: [1, 2], weights: ["0.6", "0.4"]) + [prices(quoteID: 1)]
        let probe = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: probe.directory) }
        let current = try refresh(ScriptedPDTHTTPTransport(replies), store: probe)
            .refresh(cancellation: nil, progress: { _ in })
        let item = try #require(current.model.rankedAttentionItems.first { $0.holdingIdentity?.quoteId == 1 })

        var prior = try #require(try probe.loadPriorSnapshotResult().snapshot)
        prior.asOf = seededAsOf
        prior.openHoldings = prior.openHoldings.map { holding in
            var holding = holding
            holding.weight = holding.quoteId == 1 ? 0.19 : 0.81
            return holding
        }
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try store.commitCurrentSnapshot(prior)
        let readStore = PulseReadStore(directory: store.directory)
        try readStore.markRead(item.readFingerprint)

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store, readStore: readStore)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(result.model.rankedAttentionItems.contains { $0.readFingerprint == item.readFingerprint })
        #expect(!(try readStore.load()).contains(item.readFingerprint))
    }

    @Test("A corrupt prior snapshot is surfaced in Data health and the refresh still commits")
    func corruptPriorSnapshotIsSurfaced() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try Data("{".utf8).write(to: store.currentSnapshotPath)

        let result = try refresh(ScriptedPDTHTTPTransport(try fullReplies()), store: store)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .completed)
        #expect(result.pulse.priorSnapshotLoadStatus == .failed(.decode))
        #expect(result.model.facetSnapshots.dataHealth.cache.priorSnapshotStatus == .corrupt)
        #expect(result.model.portfolioGlance.priorSnapshotAsOf == nil)
        #expect(try store.loadPriorSnapshotResult().snapshot?.asOf == "2026-06-22")
    }

    @Test("Progress names every phase in order and counts price-history units across batches")
    func progressCountsPriceUnitsAcrossBatches() throws {
        let quoteIDs = Array(1...51)
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let recorder = ProgressRecorder()

        _ = try refresh(
            ScriptedPDTHTTPTransport(syntheticReplies(quoteIDs: quoteIDs) + [prices(quoteID: 1), prices(quoteID: 51)]),
            store: store
        ).refresh(cancellation: nil, progress: recorder.record)

        #expect(recorder.phases == BackgroundDetailRefreshPhase.allCases)
        let priceUnits = recorder.values.filter { $0.phase == .priceHistory }.map { [$0.completedUnitCount, $0.totalUnitCount] }
        #expect(priceUnits == [[0, 51], [50, 51], [51, 51]])
    }

    @Test("Quitting before the commit keeps the prior snapshot and its read mark until a later refresh recrosses")
    func quitBeforeCommitKeepsReadMarkUntilRecrossing() throws {
        let replies = syntheticReplies(quoteIDs: [1, 2], weights: ["0.6", "0.4"]) + [prices(quoteID: 1)]
        let probe = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: probe.directory) }
        let current = try refresh(ScriptedPDTHTTPTransport(replies), store: probe)
            .refresh(cancellation: nil, progress: { _ in })
        let alert = try #require(current.model.rankedAttentionItems.first { $0.holdingIdentity?.quoteId == 1 })

        var prior = try #require(try probe.loadPriorSnapshotResult().snapshot)
        prior.asOf = seededAsOf
        prior.openHoldings = prior.openHoldings.map { holding in
            var holding = holding
            holding.weight = holding.quoteId == 1 ? 0.19 : 0.81
            return holding
        }
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try store.commitCurrentSnapshot(prior)
        let readStore = PulseReadStore(directory: store.directory)
        try readStore.markRead(alert.readFingerprint)

        let quit = PDTCancellation()
        let transport = CancellingTransport(inner: ScriptedPDTHTTPTransport(replies), cancelAtRequest: 2, cancellation: quit)
        #expect(throws: (any Error).self) {
            try refresh(transport, store: store, readStore: readStore).refresh(cancellation: quit, progress: { _ in })
        }

        #expect(try store.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
        #expect(try readStore.load().contains(alert.readFingerprint))
        let relaunch = try #require(try PressureRunner.cachedPulse(snapshotStore: store, pulseReadStore: readStore, today: "2026-06-22"))
        #expect(!relaunch.model.rankedAttentionItems.contains { $0.id == alert.id })

        let next = try refresh(ScriptedPDTHTTPTransport(replies), store: store, readStore: readStore)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(next.model.rankedAttentionItems.contains { $0.readFingerprint == alert.readFingerprint })
        #expect(!(try readStore.load()).contains(alert.readFingerprint))
    }

    @Test("A completed refresh after a degraded one restores the facet and records a complete detail fill")
    func completedAfterDegradedRestoresFacet() throws {
        let store = try seededStore { $0.sectors = [DistributionSummary(name: "last-good", percentage: 100, totalValue: Money(value: "1", currency: "EUR"))] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var degradedReplies = try fullReplies()
        degradedReplies[1] = apiError(500, "SERVER_ERROR")
        let degraded = try refresh(ScriptedPDTHTTPTransport(degradedReplies), store: store)
            .refresh(cancellation: nil, progress: { _ in })
        #expect(degraded.outcome == .degraded)
        #expect(try store.loadPriorSnapshotResult().snapshot?.latestCompleteDetailFillAsOf == seededAsOf)

        let repaired = try refresh(ScriptedPDTHTTPTransport(try fullReplies()), store: store)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(repaired.outcome == .completed)
        #expect(repaired.failures.isEmpty)
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.sectors.map(\.name) == ["information-technology", "communication-services", "financials", "health-care"])
        #expect(saved.latestDetailFillOutcome == .completed)
        #expect(saved.latestCompleteDetailFillAsOf == "2026-06-22")
        #expect(store.lastSyncFailure() == nil)
    }

    @Test("Performance stays unavailable without degrading and never carries a prior period forward")
    func performanceIsNotCarriedForward() throws {
        let store = try seededStore {
            $0.performance = PortfolioPerformanceSummary.build(totalGainPercentage: 0.25, periodStart: "2024-06-21", periodEnd: seededAsOf)
        }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(try store.loadPriorSnapshotResult().snapshot?.performance != nil)

        let result = try refresh(ScriptedPDTHTTPTransport(try fullReplies()), store: store)
            .refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .completed)
        #expect(try store.loadPriorSnapshotResult().snapshot?.performance == nil)
    }

    @Test("Closed, zero, negative, and unreadable holdings are filtered out and get no price request")
    func filteredHoldingsGetNoPriceRequest() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport([ok(filteredHoldingsJSON)] + Array(syntheticReplies(quoteIDs: [1]).dropFirst()) + [prices(quoteID: 1001)])

        _ = try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })

        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.openHoldings.map(\.quoteId) == [1001])
        #expect(saved.totalValue == Money(value: "500.00", currency: "EUR"))
        let priceRequests = transport.requests.filter { $0.url!.path == "/v1/prices/batch" }
        #expect(priceRequests.map { query($0, "symbolQuoteIds[]") } == [["1001"]])
    }

    @Test("A portfolio held in USD is totalled in USD on refresh")
    func nonEURPortfolioCurrencyOnRefresh() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport(
            [ok(nonEURHoldingsJSON)] + Array(syntheticReplies(quoteIDs: [1]).dropFirst()) + [ok(#"{"data":{"prices":[]}}"#)]
        )

        _ = try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })

        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.openHoldings.map(\.quoteId) == [6001, 6002])
        #expect(saved.totalValue == Money(value: "750.00", currency: "USD"))
    }
}

private let seededAsOf = "2026-06-21"

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func refresh(
    _ transport: any PDTHTTPTransport,
    store: SnapshotStore,
    readStore: PulseReadStore? = nil,
    asOf: String = "2026-06-22",
    maxAttempts: Int = 1,
    maxPages: Int = 50
) -> PDTAPIBackgroundDetailRefresh {
    PDTAPIBackgroundDetailRefresh(
        client: PDTAPIClient(
            transport: transport,
            tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("pdt_test_secret")),
            policy: PDTAPIRequestPolicy(maxAttempts: maxAttempts, maxPages: maxPages),
            sleeper: NoSleep()
        ),
        snapshotStore: store,
        pulseReadStore: readStore,
        asOf: asOf
    )
}

private func temporaryStore() throws -> SnapshotStore {
    try SnapshotStore.temporaryTestStore(prefix: "pdtbar-api-background-refresh-test")
}

/// A store holding one complete refresh of the `full` fixture as of
/// `seededAsOf`, optionally edited so a test can tell last-good facets apart.
private func seededStore(_ edit: (inout PortfolioSnapshot) -> Void = { _ in }) throws -> SnapshotStore {
    let store = try temporaryStore()
    _ = try refresh(ScriptedPDTHTTPTransport(try fullReplies()), store: store, asOf: seededAsOf)
        .refresh(cancellation: nil, progress: { _ in })
    var snapshot = try #require(try store.loadPriorSnapshotResult().snapshot)
    edit(&snapshot)
    _ = try store.commitCurrentSnapshot(snapshot)
    return store
}

/// The `full` fixture in background-refresh request order. Symbol-quote
/// lookups belong to the first fetch only.
private func fullReplies() throws -> [ScriptedPDTHTTPTransport.Reply] {
    let directory = packageRoot.appending(path: "docs/pdt/fixtures/api/full")
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("symbol-quotes") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { .response(status: 200, body: try Data(contentsOf: $0)) }
}

/// Holdings plus empty optional facets, ready for price-batch replies.
private func syntheticReplies(quoteIDs: [Int], weights: [String]? = nil) -> [ScriptedPDTHTTPTransport.Reply] {
    let weight = String(1.0 / Double(quoteIDs.count))
    let rows = quoteIDs.enumerated().map { index, quoteID in
        #"{"symbolName":"Holding \#(quoteID)","symbolQuoteId":\#(quoteID),"symbolId":\#(quoteID + 1000),"currentPriceDate":"2026-06-22T23:59:59+00:00","portfolioWeight":"\#(weights?[index] ?? weight)","closedAt":null,"currentWorthLocal":{"value":"100.00","currency":"EUR"}}"#
    }
    let emptyPage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1}}"#
    return [
        ok(#"{"data":[\#(rows.joined(separator: ","))]}"#),
        ok(#"{"data":{"sectors":[],"assetTypes":[]}}"#),
        ok(#"{"data":{"items":[],"hasMore":false}}"#),
        ok(emptyPage),
        ok(emptyPage),
    ]
}

private func prices(quoteID: Int) -> ScriptedPDTHTTPTransport.Reply {
    ok(#"{"data":{"prices":[[{"date":"2026-06-22","closeAdjusted":"10.00","closeCurrency":"EUR","symbolQuoteId":\#(quoteID)}]]}}"#)
}

private func ok(_ body: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(body.utf8))
}

private func apiError(_ status: Int, _ code: String, details: String = "{}") -> ScriptedPDTHTTPTransport.Reply {
    .response(status: status, body: Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details),"traceId":"t"}}"#.utf8))
}

private func rateLimited(retryAfter: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 429,
        body: Data(#"{"error":{"code":"RATE_LIMITED","message":"m","details":{},"traceId":"t"}}"#.utf8),
        headers: ["Retry-After": retryAfter]
    )
}

private func query(_ request: URLRequest, _ name: String) -> [String] {
    (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .filter { $0.name == name }
        .compactMap(\.value)
}

private let filteredHoldingsJSON = #"""
{"data":[
  {"symbolName":"Closed Co","symbolQuoteId":1002,"symbolId":5002,"currentPriceDate":"2026-06-21T21:59:00+00:00","currentWorthLocal":{"value":"0.00","currency":"EUR"},"portfolioWeight":0.10,"closedAt":"2026-06-01T00:00:00+00:00"},
  {"symbolName":"Open Public Co","symbolQuoteId":1001,"symbolId":5001,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorth":{"value":"500.00","currency":"EUR"},"currentWorthLocal":{"value":"500.00","currency":"EUR"},"portfolioWeight":0.25,"closedAt":null},
  {"symbolName":"Zero Worth","symbolQuoteId":1003,"symbolId":5003,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorthLocal":{"value":"0.00","currency":"EUR"},"portfolioWeight":0.05,"closedAt":null},
  {"symbolName":"Negative Worth","symbolQuoteId":1005,"symbolId":5005,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentWorthLocal":{"value":"-10.00","currency":"EUR"},"portfolioWeight":0.05,"closedAt":null}
]}
"""#

private let nonEURHoldingsJSON = #"""
{"data":[
  {"symbolName":"US Portfolio Holding","symbolQuoteId":6001,"symbolId":7001,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"100.00","currency":"USD"},"currentExchangeRate":0.8,"currentWorth":{"value":"400.00","currency":"EUR"},"currentWorthLocal":{"value":"500.00","currency":"USD"},"portfolioWeight":0.67,"closedAt":null},
  {"symbolName":"Second US Portfolio Holding","symbolQuoteId":6002,"symbolId":7002,"currentPriceDate":"2026-06-22T21:59:00+00:00","currentPriceLocal":{"value":"25.00","currency":"USD"},"currentWorth":{"value":"250.00","currency":"USD"},"currentWorthLocal":{"value":"250.00","currency":"USD"},"portfolioWeight":0.33,"closedAt":null}
]}
"""#

private struct NoSleep: PDTAPISleeper {
    func sleep(seconds _: TimeInterval, cancellation _: PDTCancellation?) throws {}
}

private final class CancellingTransport: PDTHTTPTransport, @unchecked Sendable {
    let inner: ScriptedPDTHTTPTransport
    private let cancelAtRequest: Int
    private let cancellation: PDTCancellation

    init(inner: ScriptedPDTHTTPTransport, cancelAtRequest: Int, cancellation: PDTCancellation) {
        self.inner = inner
        self.cancelAtRequest = cancelAtRequest
        self.cancellation = cancellation
    }

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        let reply = try inner.send(request, cancellation: cancellation)
        if inner.requests.count == cancelAtRequest {
            self.cancellation.cancel()
        }
        return reply
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [BackgroundDetailRefreshProgress] = []

    var values: [BackgroundDetailRefreshProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var phases: [BackgroundDetailRefreshPhase] {
        values.map(\.phase).reduce(into: []) { phases, phase in
            if phases.last != phase {
                phases.append(phase)
            }
        }
    }

    func record(_ progress: BackgroundDetailRefreshProgress) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(progress)
    }
}
