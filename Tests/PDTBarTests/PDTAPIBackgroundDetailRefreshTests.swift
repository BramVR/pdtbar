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
        #expect(result.diagnostics.isEmpty)
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
        #expect(try store.loadLastDetailRefreshDiagnostic() == nil)
    }

    @Test("A failed required base throws, keeps the last good snapshot, and records the diagnostic")
    func baseFailureKeepsLastGoodSnapshot() throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let transport = ScriptedPDTHTTPTransport([apiError(503, "SERVICE_UNAVAILABLE")])

        #expect(throws: PDTAPIError.self) {
            try refresh(transport, store: store).refresh(cancellation: nil, progress: { _ in })
        }

        #expect(transport.requests.count == 1)
        #expect(try store.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.phase == .baseHoldings)
        #expect(diagnostic.toolName == "portfolio/holdings")
        #expect(diagnostic.category == .transientFailure)
    }

    @Test("A failed optional facet keeps its last good value and degrades the outcome")
    func optionalFailureKeepsLastGoodFacet() throws {
        let store = try seededStore { $0.sectors = [DistributionSummary(name: "last-good", percentage: 100, totalValue: Money(value: "1", currency: "EUR"))] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        replies[1] = apiError(500, "SERVER_ERROR")

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .degraded)
        #expect(result.diagnostics.map(\.phase) == [.allocation])
        let saved = try #require(try store.loadPriorSnapshotResult().snapshot)
        #expect(saved.asOf == "2026-06-22")
        #expect(saved.sectors.map(\.name) == ["last-good"])
        #expect(saved.xRayHoldings?.count == 3)
        #expect(saved.latestDetailFillOutcome == .degraded)
        #expect(saved.latestCompleteDetailFillAsOf == seededAsOf)
        #expect(try store.loadLastDetailRefreshDiagnostic()?.toolName == "portfolio/distributions")
    }

    @Test("A rate limit longer than the retry budget degrades the facet instead of stalling")
    func longRateLimitDegrades() throws {
        let store = try seededStore { $0.xRayHoldings = [XRayHoldingSummary(weight: 0.42)] }
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = try fullReplies()
        replies.replaceSubrange(2...3, with: [rateLimited(retryAfter: "120")])

        let result = try refresh(ScriptedPDTHTTPTransport(replies), store: store).refresh(cancellation: nil, progress: { _ in })

        #expect(result.outcome == .degraded)
        #expect(result.diagnostics.map(\.category) == [.transientFailure])
        #expect(try store.loadPriorSnapshotResult().snapshot?.xRayHoldings?.map(\.weight) == [0.42])
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
        #expect(result.diagnostics.map(\.category) == [.setupUnavailable])
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
        #expect(result.diagnostics.map(\.phase) == [.priceHistory])
        #expect(result.diagnostics.map(\.category) == [.setupUnavailable])
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
        #expect(result.diagnostics.map(\.phase) == [.income])
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
    private var recorded: [BackgroundDetailRefreshPhase] = []

    var phases: [BackgroundDetailRefreshPhase] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ progress: BackgroundDetailRefreshProgress) {
        lock.lock()
        defer { lock.unlock() }
        if recorded.last != progress.phase {
            recorded.append(progress.phase)
        }
    }
}
