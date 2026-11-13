import Foundation
import Testing
import PDTBarCore

@Suite("Data health")
struct DataHealthTests {
    @Test("A pulse fetched in this run with current prices and a complete fill is healthy")
    func fetchedCompletePulseIsHealthy() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-fetched-truth")

        let fetched = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: snapshot()),
            snapshotStore: store
        )
        let health = fetched.model.facetSnapshots.dataHealth

        #expect(health.status == .healthy)
        #expect(health.source.pulse == .fetchedSnapshot)
        #expect(health.access.state == .connected)
        #expect(health.cache.lastSyncAsOf == "2026-06-25")
        #expect(health.cache.lastCompleteSyncAsOf == "2026-06-25")
        #expect(health.lastFailure == nil)
        #expect(healthRow(in: fetched.descriptor) == nil)
        #expect(dataSection(in: fetched.descriptor)?.title == "Data")
        #expect(pricesRow(in: fetched.descriptor)?.title == "Prices")
        #expect(pricesRow(in: fetched.descriptor)?.detail == "Current through 2026-06-24")
        #expect(pricesRow(in: fetched.descriptor)?.children.allSatisfy { $0.id.hasPrefix("freshness.price.") } == true)
    }

    @Test("All quiet over a saved copy says the saved copy is quiet, not that it is quiet right now")
    func allQuietNamesTheSavedCopy() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
        let quietSnapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-cached-quiet")
        _ = try store.commitCurrentSnapshot(quietSnapshot)
        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store, today: quietSnapshot.asOf))
        let quiet = { (descriptor: MenuDescriptor) in
            descriptor.sections.flatMap(\.rows).first { $0.id == "pulse.quiet" }?.detail
        }

        #expect(quiet(cached.descriptor) == "No attention items in the saved copy.")
        #expect(quiet(MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: quietSnapshot))) == "No attention items right now.")
    }

    @Test("A saved copy is never healthy and never claims a checked connection")
    func savedCopyIsNeverHealthy() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-cached-truth")
        _ = try store.commitCurrentSnapshot(snapshot())

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-06-25"))
        let health = cached.model.facetSnapshots.dataHealth

        #expect(health.freshness.status == .fresh)
        #expect(health.source.pulse == .cachedSnapshot)
        #expect(health.access.state == .unverified)
        #expect(health.status == .degraded)
        #expect(healthRow(in: cached.descriptor)?.detail == "Showing a saved copy")
        #expect(healthDetail("source", in: cached.descriptor) == "PDT, read-only; saved copy from 2026-06-25")
        #expect(healthDetail("access", in: cached.descriptor) == "Not checked this session")
        for access in [DataHealthAccess.connected, .checking, .unverified] {
            let shown = DataHealth.snapshot(health, in: DataHealthRuntime(access: access))
            #expect(shown.status != .healthy, "\(access)")
        }
    }

    @Test("Stale saved prices are never shown as freshly fetched, and a failed refresh moves no date")
    func staleSavedDataNeverLooksFresh() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-stale-saved")
        _ = try store.commitCurrentSnapshot(snapshot(holdings: [
            holding("Stale One", quoteId: 1, priceAsOf: "2026-06-22"),
            holding("Stale Two", quoteId: 2, priceAsOf: "2026-06-23"),
        ]))
        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-07-01"))

        #expect(healthRow(in: cached.descriptor)?.detail == "Showing a saved copy")
        #expect(healthDetail("source", in: cached.descriptor) == "PDT, read-only; saved copy from 2026-06-25")
        #expect(healthDetail("access", in: cached.descriptor) == "Not checked this session")
        #expect(healthDetail("freshness", in: cached.descriptor) == "2 stale; oldest 2026-06-22")
        #expect(healthDetail("cache", in: cached.descriptor) == "Last sync 2026-06-25")

        let checking = cached.descriptor(in: DataHealthRuntime(access: .checking))
        #expect(healthRow(in: checking)?.detail == "Checking")
        #expect(healthDetail("access", in: checking) == "Checking")
        #expect(healthDetail("freshness", in: checking) == "2 stale; oldest 2026-06-22")

        let failure = PDTSyncFailure(phase: .baseHoldings, endpoint: .holdings, kind: .server(status: 503), requestCount: 3)
        let failed = cached.descriptor(in: DataHealthRuntime(access: .connected, sync: .failed(failure)))
        #expect(healthRow(in: failed)?.detail == "Detail fill failed")
        #expect(healthDetail("source", in: failed) == "PDT, read-only; saved copy from 2026-06-25")
        #expect(healthDetail("cache", in: failed) == "Last sync 2026-06-25")
        #expect(healthDetail("freshness", in: failed) == "2 stale; oldest 2026-06-22")
        #expect(healthDetail("detailFill", in: failed) == "Failed")
        #expect(healthDetail("diagnostic", in: failed) == "Base holdings: PDT server problem; try again later")
    }

    @Test("Last sync, last complete sync, and price freshness are reported separately")
    func lastSyncIsSeparateFromPriceFreshness() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-sync-dates")
        var degraded = snapshot()
        degraded.latestCompleteDetailFillAsOf = "2026-06-20"
        let failure = PDTSyncFailure(phase: .income, endpoint: .dividends, kind: .server(status: 502), requestCount: 1)

        let pulse = try PressureRunner.refreshedPulse(
            snapshot: degraded,
            priorSnapshot: nil,
            snapshotStore: store,
            detailRefreshOutcome: .degraded,
            lastSyncFailure: failure
        )
        let health = pulse.model.facetSnapshots.dataHealth

        #expect(health.cache.lastSyncAsOf == "2026-06-25")
        #expect(health.cache.lastCompleteSyncAsOf == "2026-06-20")
        #expect(health.freshness.oldestPriceAsOf == "2026-06-24")
        #expect(healthDetail("source", in: pulse.descriptor) == "PDT, read-only; fetched this session")
        #expect(healthDetail("access", in: pulse.descriptor) == "Connected")
        #expect(healthDetail("cache", in: pulse.descriptor) == "Last sync 2026-06-25; last complete 2026-06-20")
        #expect(healthDetail("freshness", in: pulse.descriptor) == "Current; oldest 2026-06-24")
        #expect(healthDetail("detailFill", in: pulse.descriptor) == "Degraded")
        #expect(healthDetail("diagnostic", in: pulse.descriptor) == "Income: PDT server problem; try again later")
    }

    @Test("Copy diagnostics names the step, request, and failure, and nothing from the portfolio")
    func copyDiagnosticsIsBuiltFromTypedFacts() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-copy")
        _ = try store.commitCurrentSnapshot(snapshot())
        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-06-25"))
        let failure = PDTSyncFailure(
            phase: .baseHoldings,
            endpoint: .holdings,
            kind: .rateLimited(retryAfterSeconds: 120),
            requestCount: 3,
            traceID: PDTTraceID("6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f")
        )

        let menu = cached.descriptor(in: DataHealthRuntime(access: .connected, sync: .failed(failure)))
        let diagnostics = try #require(healthRow(in: menu)?.children.first { $0.id == "dataHealth.diagnostic" })
        let copy = try #require(diagnostics.children.first)

        #expect(copy.title == "Copy diagnostics")
        #expect(copy.actionTarget?.kind == .copyDataHealthDiagnostic)
        #expect(copy.actionTarget?.copyText == """
        PDTBar data health
        source: PDT API, read-only
        shown: saved copy
        access: connected
        detail fill: failed
        step: base holdings
        request: GET /v1/portfolio/holdings
        failure: rate limited (HTTP 429)
        retry after: 120 s
        requests sent: 3
        trace: 6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f
        """)
        #expect(copy.actionTarget?.copyText?.contains("Example Holding") == false)
        #expect(copy.actionTarget?.copyText?.contains("2026-06") == false)
    }

    @Test("Descriptor exposes Data health submenu rows when degraded")
    func descriptorExposesDataHealthSubmenuRowsWhenDegraded() throws {
        let model = PressureEngine.buildModel(
            from: snapshot(),
            readState: PulseReadState(readFingerprints: ["read-one"]),
            detailRefreshOutcome: .completed
        )
        let dataSection = try #require(MenuDescriptorRenderer.render(model: model)
            .sections
            .first { $0.id == "freshness" })
        let prices = try #require(dataSection.rows.first { $0.id == "freshness.summary" })
        let dataHealth = try #require(dataSection.rows.first { $0.id == "dataHealth" })

        #expect(dataSection.title == "Data")
        #expect(prices.title == "Prices")
        #expect(prices.detail == "Current through 2026-06-24")
        #expect(dataHealth.title == "Data health")
        #expect(dataHealth.role == .dataHealthSummary)
        #expect(dataHealth.children.map(\.id) == [
            "dataHealth.source",
            "dataHealth.access",
            "dataHealth.cache",
            "dataHealth.freshness",
            "dataHealth.detailFill",
            "dataHealth.readState",
            "dataHealth.diagnostic",
        ])
        #expect(dataHealth.children.map(\.title) == ["Source", "Access", "Cache", "Prices", "Detail fill", "Read state", "Diagnostics"])
        #expect(dataHealth.children.map(\.detail) == [
            "PDT, read-only; not fetched this session",
            "Not checked this session",
            "Last sync 2026-06-25",
            "Current; oldest 2026-06-24",
            "Completed 2026-06-25",
            "1 read",
            "None recorded",
        ])
    }

    @Test("Cached snapshot preserves saved degraded detail fill")
    func cachedSnapshotPreservesSavedDegradedDetailFill() throws {
        var snapshot = snapshot()
        snapshot.latestDetailFillOutcome = .degraded
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))

        #expect(healthRow(in: descriptor)?.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Degraded")
    }

    @Test("Cached pulse lifecycle preserves saved degraded detail fill")
    func cachedPulseLifecyclePreservesSavedDegradedDetailFill() throws {
        var snapshot = snapshot()
        snapshot.latestDetailFillOutcome = .degraded
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health")
        _ = try store.commitCurrentSnapshot(snapshot)

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(healthRow(in: cached.descriptor)?.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Degraded")
    }

    @Test("A saved copy shows the failure of the degraded sync that wrote it, and drops it after a complete fill")
    func savedCopyShowsOnlyTheFailureOfItsOwnSync() throws {
        let failure = PDTSyncFailure(phase: .priceHistory, endpoint: .pricesBatch, kind: .network(urlErrorCode: -1009), requestCount: 1)
        var degraded = snapshot()
        degraded.latestDetailFillOutcome = .degraded
        let degradedStore = try SnapshotStore.temporaryTestStore(prefix: "data-health-own-failure")
        degradedStore.setLastSyncFailure(failure)
        _ = try degradedStore.commitCurrentSnapshot(degraded)
        var completed = snapshot()
        completed.latestDetailFillOutcome = .completed
        let completedStore = try SnapshotStore.temporaryTestStore(prefix: "data-health-older-failure")
        completedStore.setLastSyncFailure(failure)
        _ = try completedStore.commitCurrentSnapshot(completed)

        let withFailure = try #require(try PressureRunner.cachedPulse(snapshotStore: degradedStore))
        let withoutFailure = try #require(try PressureRunner.cachedPulse(snapshotStore: completedStore))

        #expect(healthDetail("diagnostic", in: withFailure.descriptor) == "Price history: could not reach PDT; check your connection")
        #expect(healthDetail("detailFill", in: withoutFailure.descriptor) == "Completed 2026-06-25")
        #expect(healthDetail("diagnostic", in: withoutFailure.descriptor) == "None recorded")
    }

    @Test(
        "An unreadable or foreign sync failure file is no failure and does not break the saved copy",
        arguments: [
            "not json",
            #"{"toolName":"pdt-list-symbol-prices","phase":"priceHistory","attemptCount":1,"category":"transientFailure","argumentShape":["symbol_quote_id"]}"#,
            #"{"phase":"income","endpoint":"dividends","kind":{"notInventedYet":{}},"requestCount":1}"#,
            #"{"phase":"income","endpoint":"not/an/endpoint","kind":{"cancelled":{}},"requestCount":1}"#,
            #"{"phase":"income","endpoint":"dividends","kind":{"cancelled":{}},"requestCount":1,"traceID":"acct-4242 is not a trace id"}"#,
        ]
    )
    func unreadableSyncFailureFileIsNoFailure(contents: String) throws {
        var degraded = snapshot()
        degraded.latestDetailFillOutcome = .degraded
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-unreadable-failure")
        _ = try store.commitCurrentSnapshot(degraded)
        try Data(contents.utf8).write(to: store.directory.appending(path: "latest-sync-failure.json"))

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(store.lastSyncFailure() == nil)
        #expect(healthDetail("detailFill", in: cached.descriptor) == "Degraded")
        #expect(healthDetail("diagnostic", in: cached.descriptor) == "None recorded")
    }

    @Test("A Claude-era diagnostic file left by an older build never reaches Data health")
    func claudeEraDiagnosticFileNeverReachesDataHealth() throws {
        var degraded = snapshot()
        degraded.latestDetailFillOutcome = .degraded
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-claude-era-file")
        _ = try store.commitCurrentSnapshot(degraded)
        try Data(#"{"argumentShape":["symbol_quote_id"],"attemptCount":2,"category":"transientFailure","phase":"priceHistory","toolName":"pdt-list-symbol-prices"}"#.utf8)
            .write(to: store.directory.appending(path: "latest-detail-refresh-diagnostic.json"))

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(healthDetail("diagnostic", in: cached.descriptor) == "None recorded")
        let rendered = String(decoding: try stableJSONData(cached.descriptor), as: UTF8.self)
        #expect(!rendered.contains("pdt-list-symbol-prices"))
        #expect(!rendered.contains("symbol_quote_id"))
    }

    @Test("A stored sync failure reads back as written")
    func storedSyncFailureRoundTrips() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-failure-round-trip")
        let failure = PDTSyncFailure(
            phase: .income,
            endpoint: .dividends,
            kind: .rateLimited(retryAfterSeconds: 90),
            requestCount: 2,
            traceID: PDTTraceID("0123456789abcdef0123456789abcdef")
        )

        store.setLastSyncFailure(failure)
        #expect(store.lastSyncFailure() == failure)

        store.setLastSyncFailure(nil)
        #expect(store.lastSyncFailure() == nil)
    }

    @Test("A model saved with the Claude-era Data health shape still loads, as an unchecked copy")
    func oldFormatDataHealthStillLoads() throws {
        let model = PressureEngine.buildModel(from: snapshot(), detailRefreshOutcome: .completed)
        var json = try #require(JSONSerialization.jsonObject(with: stableJSONData(model)) as? [String: Any])
        var facets = try #require(json["facetSnapshots"] as? [String: Any])
        facets["dataHealth"] = try JSONSerialization.jsonObject(with: Data(legacyDataHealthJSON.utf8))
        json["facetSnapshots"] = facets

        let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.rankedAttentionItems == model.rankedAttentionItems)
        #expect(decoded.facetSnapshots.freshness == model.facetSnapshots.freshness)
        #expect(decoded.facetSnapshots.dataHealth.access.state == .unverified)
        #expect(decoded.facetSnapshots.dataHealth.status == .degraded)
        #expect(decoded.facetSnapshots.dataHealth.lastFailure == nil)
        let rendered = String(decoding: try stableJSONData(MenuDescriptorRenderer.render(model: decoded)), as: UTF8.self)
        #expect(!rendered.contains("pdt-list-symbol-prices"))
        #expect(!rendered.contains("Claude"))
    }

    @Test("Applying read state updates Data health read count")
    func applyingReadStateUpdatesDataHealthReadCount() throws {
        let model = PressureEngine.buildModel(from: snapshot())
        let pulse = PulseLifecycleResult(
            unfilteredModel: model,
            model: model,
            snapshotCommit: SnapshotCommit(written: false, path: "/tmp/pdtbar-data-health-test", asOf: "2026-06-25"),
            descriptor: MenuDescriptorRenderer.render(model: model),
            source: .fetchedSnapshot
        )

        let updated = pulse.applyingReadState(PulseReadState(readFingerprints: ["one", "two"]))

        #expect(updated.model.facetSnapshots.dataHealth.readState.readFingerprintCount == 2)
        #expect(healthRow(in: updated.descriptor)?.children.first { $0.id == "dataHealth.readState" }?.detail == "2 read")
    }

    @Test("A running sync over a healthy pulse shows its progress and keeps the pulse's own facts")
    func runningSyncShowsProgressOverHealthyPulse() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-overlay-insert")
        let fetched = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: snapshot()),
            snapshotStore: store
        ).applyingReadState(PulseReadState(readFingerprints: ["one"]))
        #expect(healthRow(in: fetched.descriptor) == nil)

        let refreshing = fetched.descriptor(in: DataHealthRuntime(
            access: .connected,
            sync: .running(BackgroundDetailRefreshProgress(phase: .priceHistory, completedUnitCount: 2, totalUnitCount: 9))
        ))
        let idle = fetched.descriptor(in: DataHealthRuntime(access: .connected))

        #expect(healthRow(in: refreshing)?.detail == "Refreshing")
        #expect(healthDetail("source", in: refreshing) == "PDT, read-only; fetched this session")
        #expect(healthDetail("detailFill", in: refreshing) == "Price history 2/9")
        #expect(healthDetail("readState", in: refreshing) == "1 read")
        #expect(refreshing.statusTitle == fetched.descriptor.statusTitle)
        #expect(refreshing.sections.map(\.id) == fetched.descriptor.sections.map(\.id))
        #expect(healthRow(in: idle) == nil)
    }

    @Test("The running app's sync state replaces the pulse's detail fill and failure, and nothing else")
    func runtimeSyncReplacesOnlyDetailFillAndFailure() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-overlay")
        let failure = PDTSyncFailure(phase: .priceHistory, endpoint: .pricesBatch, kind: .server(status: 503), requestCount: 1)
        let degraded = try PressureRunner.refreshedPulse(
            snapshot: snapshot(),
            priorSnapshot: nil,
            snapshotStore: store,
            detailRefreshOutcome: .degraded,
            lastSyncFailure: failure
        )

        let refreshing = degraded.descriptor(in: DataHealthRuntime(
            access: .connected,
            sync: .running(BackgroundDetailRefreshProgress(phase: .priceHistory, completedUnitCount: 1, totalUnitCount: 3))
        ))
        let idle = degraded.descriptor(in: DataHealthRuntime(access: .connected))
        let failedWithoutRecord = degraded.descriptor(in: DataHealthRuntime(access: .connected, sync: .failed(nil)))

        #expect(healthRow(in: refreshing)?.detail == "Refreshing")
        #expect(healthDetail("cache", in: refreshing) == "Last sync 2026-06-25")
        #expect(healthDetail("detailFill", in: refreshing) == "Price history 1/3")
        #expect(healthDetail("diagnostic", in: refreshing) == "Price history: PDT server problem; try again later")

        #expect(healthRow(in: idle)?.detail == "Detail fill incomplete")
        #expect(healthDetail("detailFill", in: idle) == "Degraded")
        #expect(healthDetail("diagnostic", in: idle) == "Price history: PDT server problem; try again later")

        #expect(healthRow(in: failedWithoutRecord)?.detail == "Detail fill failed")
        #expect(healthDetail("cache", in: failedWithoutRecord) == "Last sync 2026-06-25")
        #expect(healthDetail("detailFill", in: failedWithoutRecord) == "Failed")
        #expect(healthDetail("diagnostic", in: failedWithoutRecord) == "None recorded")
    }

    @Test("Quiet overview surfaces degraded price data signal")
    func quietOverviewSurfacesDegradedPriceDataSignal() throws {
        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(
                from: snapshot(
                    holdings: [
                        holding("Stale One", quoteId: 1, priceAsOf: "2026-06-22"),
                        holding("Stale Two", quoteId: 2, priceAsOf: "2026-06-22"),
                    ],
                    sectors: []
                ),
                detailRefreshOutcome: .completed
            )
        )
        let overviewPrices = try #require(descriptor.sections
            .first { $0.id == "pulse" }?
            .rows
            .first { $0.id == "pulse.quiet" }?
            .children
            .first { $0.id == "pulse.quiet.freshness" })

        #expect(overviewPrices.title == "Prices")
        #expect(overviewPrices.detail == "2 stale")
    }

    @Test("Partial price data shows only useful supporting facts")
    func partialPriceDataShowsOnlyUsefulSupportingFacts() throws {
        var partial = snapshot()
        partial.latestCompleteDetailFillAsOf = "2026-06-24"
        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: partial, detailRefreshOutcome: .degraded)
        )
        let prices = try #require(pricesRow(in: descriptor))

        #expect(prices.detail == "Partial; oldest 2026-06-24")
        #expect(prices.children.map(\.id) == [
            "freshness.oldestPrice",
            "freshness.detailFill",
            "freshness.price.1",
        ])
        #expect(healthRow(in: descriptor) != nil)
    }
}

private func healthRow(in descriptor: MenuDescriptor) -> MenuRow? {
    dataSection(in: descriptor)?
        .rows
        .first { $0.id == "dataHealth" }
}

private func healthDetail(_ row: String, in descriptor: MenuDescriptor) -> String? {
    healthRow(in: descriptor)?.children.first { $0.id == "dataHealth.\(row)" }?.detail
}

/// `dataHealth` as builds before the PDT API path wrote it.
private let legacyDataHealthJSON = #"""
{
  "status": "degraded",
  "source": {
    "claude": "ready", "pdtMCP": "ready", "readTools": "available",
    "requiredReadToolCount": 7, "availableReadToolCount": 7, "missingReadTools": [],
    "readOnlyPolicy": "enforced", "detail": "Claude ready; PDT ready; 7/7 read tools; read-only"
  },
  "cache": {
    "pulseSource": "refreshedSnapshot", "cachedPulseAvailable": true,
    "lastSuccessfulCompleteFetchAsOf": "2026-06-25", "summary": "Last complete 2026-06-25"
  },
  "detailFill": {"outcome": "degraded", "detail": "Degraded"},
  "freshness": {"status": "partial", "staleHoldingCount": 0, "oldestPriceAsOf": "2026-06-24", "detail": "Partial; oldest 2026-06-24"},
  "readState": {"readFingerprintCount": 0, "detail": "0 read"},
  "diagnostic": {
    "available": true,
    "detail": "pdt-list-symbol-prices; priceHistory; transientFailure",
    "copyText": "PDTBar data health\ntool: pdt-list-symbol-prices\nargument_keys: symbol_quote_id"
  }
}
"""#

private func dataSection(in descriptor: MenuDescriptor) -> MenuSection? {
    descriptor
        .sections
        .first { $0.id == "freshness" }
}

private func pricesRow(in descriptor: MenuDescriptor) -> MenuRow? {
    dataSection(in: descriptor)?
        .rows
        .first { $0.id == "freshness.summary" }
}

private func freshness(
    status: FreshnessState = .fresh,
    staleHoldingCount: Int,
    oldestPriceAsOf: String?
) -> FreshnessSnapshot {
    FreshnessSnapshot(
        status: status,
        worstPriceAsOf: oldestPriceAsOf,
        stale: status == .stale,
        staleHoldingCount: staleHoldingCount,
        oldestPriceAsOf: oldestPriceAsOf,
        oldestRows: [],
        latestCompleteDetailFillAsOf: status == .unknown ? nil : "2026-06-25",
        sourceCaveats: []
    )
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var fixedSnapshot: PortfolioSnapshot

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        fixedSnapshot
    }
}

private func snapshot(
    holdings: [NormalizedHolding]? = nil,
    sectors: [DistributionSummary]? = nil
) -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: "2026-06-25",
        totalValue: Money(value: "1000.00", currency: "EUR"),
        openHoldings: holdings ?? [holding("Example Holding", quoteId: 1, priceAsOf: "2026-06-24")],
        sectors: sectors ?? [
            DistributionSummary(
                name: "Technology",
                percentage: 100,
                totalValue: Money(value: "1000.00", currency: "EUR")
            ),
        ],
        assetTypes: [],
        xRayHoldings: [],
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: []
    )
}

private func holding(_ name: String, quoteId: Int, priceAsOf: String) -> NormalizedHolding {
    NormalizedHolding(
        name: name,
        quoteId: quoteId,
        weight: 0.1,
        worth: Money(value: "100.00", currency: "EUR"),
        price: Money(value: "10.00", currency: "EUR"),
        priceAsOf: priceAsOf
    )
}
