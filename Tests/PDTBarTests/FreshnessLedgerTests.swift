import Foundation
import Testing
import PDTBarCore

@Suite("Freshness ledger")
struct FreshnessLedgerTests {
    @Test("Ledger builds stale detail from holding price dates")
    func ledgerBuildsStaleDetailFromHoldingPriceDates() {
        let ledger = FreshnessLedger.build(
            from: freshnessSnapshot(
                asOf: "2026-06-25",
                holdings: [
                    datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
                    datedHolding("Stale B", quoteId: 2, priceAsOf: "2026-06-22"),
                    datedHolding("Stale C", quoteId: 3, priceAsOf: "2026-06-20"),
                ]
            ),
            detailRefreshOutcome: .completed
        )

        #expect(ledger.status == .stale)
        #expect(ledger.stale)
        #expect(ledger.staleHoldingCount == 2)
        #expect(ledger.worstPriceAsOf == "2026-06-20")
        #expect(ledger.oldestPriceAsOf == "2026-06-20")
        #expect(ledger.oldestRows.map(\.quoteId) == [3, 2, 1])
        #expect(ledger.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(ledger.sourceCaveats.contains("Distribution dates are not reported by PDT"))
    }

    @Test("Ledger can represent partial and unknown freshness")
    func ledgerCanRepresentPartialAndUnknownFreshness() {
        let partial = FreshnessLedger.build(
            from: freshnessSnapshot(
                asOf: "2026-06-25",
                holdings: [
                    datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
                ]
            ),
            detailRefreshOutcome: .degraded
        )
        let unknown = FreshnessLedger.build(
            from: freshnessSnapshot(asOf: "2026-06-25", holdings: []),
            detailRefreshOutcome: nil
        )

        #expect(partial.status == .partial)
        #expect(!partial.stale)
        #expect(partial.latestCompleteDetailFillAsOf == nil)
        #expect(partial.sourceCaveats.contains("Optional detail fill incomplete; some detail rows may use prior data"))
        #expect(unknown.status == .unknown)
        #expect(!unknown.stale)
        #expect(unknown.worstPriceAsOf == nil)
        #expect(unknown.sourceCaveats.contains("No open holdings with dated prices"))
    }

    @Test("Ledger distinguishes mixed unknown price dates")
    func ledgerDistinguishesMixedUnknownPriceDates() {
        let ledger = FreshnessLedger.build(
            from: freshnessSnapshot(
                asOf: "2026-06-25",
                holdings: [
                    datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
                    datedHolding("Unknown B", quoteId: 2, priceAsOf: ""),
                ]
            )
        )

        #expect(ledger.status == .unknown)
        #expect(ledger.oldestRows.map(\.quoteId) == [1])
        #expect(ledger.sourceCaveats.contains("Some holdings have unknown price dates"))
        #expect(!ledger.sourceCaveats.contains("No open holdings with dated prices"))
    }

    @Test("Ledger preserves latest complete detail fill through cached snapshot reload")
    func ledgerPreservesLatestCompleteDetailFillThroughCachedSnapshotReload() throws {
        let snapshot = freshnessSnapshot(
            asOf: "2026-06-25",
            holdings: [
                datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
            ]
        )
        let store = try SnapshotStore.temporaryTestStore(prefix: "freshness-ledger")

        let refreshed = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: nil,
            snapshotStore: store,
            detailRefreshOutcome: .completed
        )
        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))
        let loaded = try #require(try store.loadPriorSnapshot())
        let rebuilt = FreshnessLedger.build(from: loaded)

        #expect(refreshed.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(cached.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(rebuilt.latestCompleteDetailFillAsOf == "2026-06-25")

        var degradedSnapshot = freshnessSnapshot(
            asOf: "2026-06-26",
            holdings: [
                datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-25"),
            ]
        )
        degradedSnapshot.latestCompleteDetailFillAsOf = loaded.latestCompleteDetailFillAsOf
        let inProgress = FreshnessLedger.build(from: degradedSnapshot)
        let degraded = try PressureRunner.refreshedPulse(
            snapshot: degradedSnapshot,
            priorSnapshot: loaded,
            snapshotStore: store,
            detailRefreshOutcome: .degraded
        )
        let cachedDegraded = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(inProgress.status == .partial)
        #expect(inProgress.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(degraded.model.facetSnapshots.freshness.status == .partial)
        #expect(degraded.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(cachedDegraded.model.facetSnapshots.freshness.status == .partial)
        #expect(cachedDegraded.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
    }

    @Test("Normal full fetch records complete detail fill")
    func normalFullFetchRecordsCompleteDetailFill() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "freshness-full-run")
        var snapshot = freshnessSnapshot(
            asOf: "2026-06-25",
            holdings: [
                datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
            ]
        )
        snapshot.sectors = [
            DistributionSummary(
                name: "Technology",
                percentage: 100,
                totalValue: Money(value: "1000.00", currency: "EUR")
            ),
        ]

        let run = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: snapshot),
            snapshotStore: store
        )
        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(run.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
        #expect(cached.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")

        let baseOnlyStore = try SnapshotStore.temporaryTestStore(prefix: "freshness-base-run")
        var baseOnlySnapshot = freshnessSnapshot(
            asOf: "2026-06-25",
            holdings: [
                datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
            ]
        )
        baseOnlySnapshot.xRayHoldings = []
        let baseOnly = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: baseOnlySnapshot),
            snapshotStore: baseOnlyStore
        )

        #expect(baseOnly.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == nil)

        let priorDetailStore = try SnapshotStore.temporaryTestStore(prefix: "freshness-base-prior-run")
        var priorDetailSnapshot = snapshot
        priorDetailSnapshot.latestCompleteDetailFillAsOf = "2026-06-24"
        priorDetailSnapshot.latestDetailFillOutcome = .completed
        _ = try priorDetailStore.commitCurrentSnapshot(priorDetailSnapshot)
        let baseOnlyWithPrior = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: baseOnlySnapshot),
            snapshotStore: priorDetailStore
        )
        let cachedBaseOnlyWithPrior = try #require(try PressureRunner.cachedPulse(snapshotStore: priorDetailStore))

        #expect(baseOnlyWithPrior.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-24")
        #expect(cachedBaseOnlyWithPrior.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-24")
    }

    @Test("Pulse model carries structured freshness ledger")
    func pulseModelCarriesStructuredFreshnessLedger() throws {
        let model = PressureEngine.buildModel(
            from: freshnessSnapshot(
                asOf: "2026-06-25",
                holdings: [
                    datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
                    datedHolding("Stale B", quoteId: 2, priceAsOf: "2026-06-22"),
                ]
            ),
            detailRefreshOutcome: .completed
        )

        #expect(model.facetSnapshots.freshness.status == .stale)
        #expect(model.facetSnapshots.freshness.staleHoldingCount == 1)
        #expect(model.facetSnapshots.freshness.oldestRows.map(\.name) == ["Stale B", "Fresh A"])
        #expect(model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-06-25")
    }

    @Test("Descriptor renders freshness detail rows from model facts")
    func descriptorRendersFreshnessDetailRowsFromModelFacts() throws {
        let model = PressureEngine.buildModel(
            from: freshnessSnapshot(
                asOf: "2026-06-25",
                holdings: [
                    datedHolding("Fresh A", quoteId: 1, priceAsOf: "2026-06-24"),
                    datedHolding("Stale B", quoteId: 2, priceAsOf: "2026-06-22"),
                ]
            ),
            detailRefreshOutcome: .completed
        )
        let freshnessRows = try #require(MenuDescriptorRenderer.render(model: model)
            .sections
            .first { $0.id == "freshness" }?
            .rows)
        let summary = try #require(freshnessRows.first)

        #expect(summary.id == "freshness.summary")
        #expect(summary.role == .freshnessSummary)
        #expect(summary.title == "Status")
        #expect(summary.detail == "1 stale; oldest 2026-06-22")
        #expect(summary.children.map(\.id) == [
            "freshness.staleCount",
            "freshness.oldestPrice",
            "freshness.oldestRows",
            "freshness.detailFill",
        ])
        #expect(summary.children.first { $0.id == "freshness.oldestRows" }?.children.map(\.id) == [
            "freshness.oldestRows.2",
            "freshness.oldestRows.1",
        ])
    }
}

private func freshnessSnapshot(asOf: String, holdings: [NormalizedHolding]) -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: asOf,
        totalValue: Money(value: "1000.00", currency: "EUR"),
        openHoldings: holdings,
        sectors: [],
        assetTypes: [],
        xRayHoldings: nil,
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: []
    )
}

private func datedHolding(_ name: String, quoteId: Int, priceAsOf: String) -> NormalizedHolding {
    NormalizedHolding(
        name: name,
        quoteId: quoteId,
        weight: 0.10,
        worth: Money(value: "100.00", currency: "EUR"),
        price: Money(value: "10.00", currency: "EUR"),
        priceAsOf: priceAsOf
    )
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var fixedSnapshot: PortfolioSnapshot

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        fixedSnapshot
    }
}
