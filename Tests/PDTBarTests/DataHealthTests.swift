import Foundation
import Testing
import PDTBarCore

@Suite("Data health")
struct DataHealthTests {
    @Test("Health composes complete runtime and source state")
    func healthComposesCompleteRuntimeAndSourceState() {
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: Set(PDTReadTools.requiredV1),
                readOnlyPolicy: .enforced,
                pulseSource: .fetchedSnapshot,
                lastSuccessfulCompleteFetchAsOf: "2026-06-25",
                cachedPulseAvailable: true,
                detailFill: .completed(asOf: "2026-06-25"),
                freshness: freshness(staleHoldingCount: 0, oldestPriceAsOf: "2026-06-24"),
                readState: PulseReadState(readFingerprints: ["one", "two"])
            )
        )

        #expect(health.status == .healthy)
        #expect(health.source.claude == .ready)
        #expect(health.source.pdtMCP == .ready)
        #expect(health.source.missingReadTools.isEmpty)
        #expect(health.source.readOnlyPolicy == .enforced)
        #expect(health.cache.cachedPulseAvailable)
        #expect(health.cache.lastSuccessfulCompleteFetchAsOf == "2026-06-25")
        #expect(health.detailFill.outcome == .completed)
        #expect(health.readState.readFingerprintCount == 2)
        #expect(health.diagnostic == nil)
    }

    @Test("Health degrades when required read tools are missing")
    func healthDegradesWhenRequiredReadToolsAreMissing() {
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: Set(PDTReadTools.requiredV1).subtracting(["pdt-list-dividends"]),
                readOnlyPolicy: .enforced,
                pulseSource: nil,
                lastSuccessfulCompleteFetchAsOf: nil,
                cachedPulseAvailable: false,
                detailFill: .notStarted,
                freshness: freshness(status: .unknown, staleHoldingCount: 0, oldestPriceAsOf: nil),
                readState: PulseReadState()
            )
        )

        #expect(health.status == .degraded)
        #expect(health.source.readTools == .missingRequired)
        #expect(health.source.missingReadTools == ["pdt-list-dividends"])
        #expect(health.cache.summary == "No cached pulse")
    }

    @Test("Health degrades when read-tool availability is unknown")
    func healthDegradesWhenReadToolAvailabilityIsUnknown() {
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: nil,
                readOnlyPolicy: .enforced,
                pulseSource: .cachedSnapshot,
                lastSuccessfulCompleteFetchAsOf: "2026-06-25",
                cachedPulseAvailable: true,
                detailFill: .completed(asOf: "2026-06-25"),
                freshness: freshness(staleHoldingCount: 0, oldestPriceAsOf: "2026-06-24"),
                readState: PulseReadState()
            )
        )

        #expect(health.status == .degraded)
        #expect(health.source.readTools == .unknown)
    }

    @Test("Diagnostics are redacted and copyable")
    func diagnosticsAreRedactedAndCopyable() throws {
        let diagnostic = PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-list-symbol-prices",
            phase: .priceHistory,
            attemptCount: 2,
            category: .transientFailure,
            argumentShape: ["symbol_quote_id", "date_to", "date_from"]
        )
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: Set(PDTReadTools.requiredV1),
                readOnlyPolicy: .enforced,
                pulseSource: .refreshedSnapshot,
                lastSuccessfulCompleteFetchAsOf: "2026-06-25",
                cachedPulseAvailable: true,
                detailFill: .degraded,
                freshness: freshness(status: .partial, staleHoldingCount: 0, oldestPriceAsOf: "2026-06-24"),
                readState: PulseReadState(),
                diagnostic: diagnostic
            )
        )

        let summary = try #require(health.diagnostic)
        #expect(summary.available)
        #expect(summary.detail == "pdt-list-symbol-prices; priceHistory; transientFailure")
        #expect(summary.copyText.contains("tool: pdt-list-symbol-prices"))
        #expect(summary.copyText.contains("argument_keys: date_from,date_to,symbol_quote_id"))
        #expect(!summary.copyText.contains("/Users/"))
        #expect(!summary.copyText.localizedCaseInsensitiveContains("portfolio"))
    }

    @Test("Descriptor exposes Data health submenu rows")
    func descriptorExposesDataHealthSubmenuRows() throws {
        let model = PressureEngine.buildModel(
            from: snapshot(),
            readState: PulseReadState(readFingerprints: ["read-one"]),
            detailRefreshOutcome: .completed
        )
        let dataHealth = try #require(MenuDescriptorRenderer.render(model: model)
            .sections
            .first { $0.id == "freshness" }?
            .rows
            .first { $0.id == "dataHealth" })

        #expect(dataHealth.title == "Data health")
        #expect(dataHealth.role == .dataHealthSummary)
        #expect(dataHealth.children.map(\.id) == [
            "dataHealth.source",
            "dataHealth.cache",
            "dataHealth.detailFill",
            "dataHealth.readState",
            "dataHealth.diagnostic",
        ])
        #expect(dataHealth.children.first { $0.id == "dataHealth.source" }?.detail == "Claude unknown; PDT unknown; read tools unknown; policy unknown")
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

    @Test("Cached pulse ignores stale diagnostic after completed detail fill")
    func cachedPulseIgnoresStaleDiagnosticAfterCompletedDetailFill() throws {
        var snapshot = snapshot()
        snapshot.latestDetailFillOutcome = .completed
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-stale-diagnostic")
        try store.saveLastDetailRefreshDiagnostic(
            PDTDetailRefreshFailureDiagnostic(
                toolName: "pdt-list-symbol-prices",
                phase: .priceHistory,
                attemptCount: 1,
                category: .transientFailure,
                argumentShape: ["symbol_quote_id"]
            )
        )
        _ = try store.commitCurrentSnapshot(snapshot)

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store))

        #expect(healthRow(in: cached.descriptor)?.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Completed 2026-06-25")
        #expect(healthRow(in: cached.descriptor)?.children.first { $0.id == "dataHealth.diagnostic" }?.detail == "None recorded")
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

    @Test("Cached refresh and degraded descriptors preserve pulse while surfacing health")
    func cachedRefreshAndDegradedDescriptorsPreservePulseWhileSurfacingHealth() throws {
        let cached = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot()))
        let refreshing = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: cached,
            progress: BackgroundDetailRefreshProgress(
                phase: .priceHistory,
                completedUnitCount: 2,
                totalUnitCount: 9
            )
        )
        let degraded = ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: cached)

        #expect(refreshing.statusTitle == cached.statusTitle)
        #expect(refreshing.sections.map(\.id).contains("pulse"))
        #expect(healthRow(in: refreshing)?.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Price history 2/9")
        #expect(degraded.statusTitle == cached.statusTitle)
        #expect(degraded.statusVisual.filledBarCount == cached.statusVisual.filledBarCount)
        #expect(healthRow(in: degraded)?.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Degraded")

        let probing = ClaudeLaunchFlow.descriptor(for: .probingClaude, cachedPulse: cached)
        #expect(healthRow(in: probing)?.detail == "Checking")
        #expect(healthRow(in: probing)?.children.first { $0.id == "dataHealth.source" }?.detail == "Claude checking; PDT unknown; read tools unknown; policy unknown")
    }

    @Test("Cached pulse does not claim connector readiness from cache alone")
    func cachedPulseDoesNotClaimConnectorReadinessFromCacheAlone() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-cached-truth")
        _ = try store.commitCurrentSnapshot(snapshot())

        let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-06-25"))
        let source = cached.model.facetSnapshots.dataHealth.source

        #expect(source.claude == .unknown)
        #expect(source.pdtMCP == .unknown)
        #expect(source.readTools == .unknown)
        #expect(source.readOnlyPolicy == .unknown)
        #expect(cached.model.facetSnapshots.dataHealth.status == .degraded)
        #expect(healthRow(in: cached.descriptor)?.detail == "Needs attention")
        #expect(healthRow(in: cached.descriptor)?.children.first { $0.id == "dataHealth.source" }?.detail == "Claude unknown; PDT unknown; read tools unknown; policy unknown")
    }

    @Test("Fetched pulse keeps live-verified source facts")
    func fetchedPulseKeepsLiveVerifiedSourceFacts() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-fetched-truth")

        let fetched = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(fixedSnapshot: snapshot()),
            snapshotStore: store
        )
        let source = fetched.model.facetSnapshots.dataHealth.source

        #expect(fetched.source == .fetchedSnapshot)
        #expect(source.claude == .ready)
        #expect(source.pdtMCP == .ready)
        #expect(source.readTools == .available)
        #expect(source.readOnlyPolicy == .enforced)
        #expect(healthRow(in: fetched.descriptor)?.children.first { $0.id == "dataHealth.source" }?.detail == "Claude ready; PDT ready; 7/7 read tools; read-only")
    }

    @Test("Runtime health overlay preserves cached diagnostics and cache state")
    func runtimeHealthOverlayPreservesCachedDiagnosticsAndCacheState() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-overlay")
        let diagnostic = PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-list-symbol-prices",
            phase: .priceHistory,
            attemptCount: 1,
            category: .transientFailure,
            argumentShape: ["symbol_quote_id"]
        )
        let cached = try PressureRunner.refreshedPulse(
            snapshot: snapshot(),
            priorSnapshot: nil,
            snapshotStore: store,
            detailRefreshOutcome: .degraded,
            detailRefreshDiagnostic: diagnostic
        ).descriptor

        let refreshing = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: cached,
            progress: BackgroundDetailRefreshProgress(phase: .priceHistory, completedUnitCount: 1, totalUnitCount: 3)
        )
        let degraded = ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: cached)
        let failedWithoutDiagnostic = ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(cachedPulse: cached)

        let refreshingHealth = try #require(healthRow(in: refreshing))
        #expect(refreshingHealth.detail == "Refreshing")
        #expect(refreshingHealth.children.first { $0.id == "dataHealth.cache" }?.detail == "Cached pulse available")
        #expect(refreshingHealth.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Price history 1/3")
        #expect(refreshingHealth.children.first { $0.id == "dataHealth.diagnostic" }?.detail == "pdt-list-symbol-prices; priceHistory; transientFailure")
        #expect(refreshingHealth.children.first { $0.id == "dataHealth.diagnostic" }?.children.first?.title == "Copy diagnostics")

        let degradedHealth = try #require(healthRow(in: degraded))
        #expect(degradedHealth.detail == "Needs attention")
        #expect(degradedHealth.children.first { $0.id == "dataHealth.cache" }?.detail == "Cached pulse available")
        #expect(degradedHealth.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Degraded")
        #expect(degradedHealth.children.first { $0.id == "dataHealth.diagnostic" }?.children.first?.actionTarget?.copyText?.contains("argument_keys: symbol_quote_id") == true)

        let failedHealth = try #require(healthRow(in: failedWithoutDiagnostic))
        #expect(failedHealth.children.first { $0.id == "dataHealth.detailFill" }?.detail == "Failed")
        #expect(failedHealth.children.first { $0.id == "dataHealth.diagnostic" }?.detail == "None recorded")
    }
}

private func healthRow(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor
        .sections
        .first { $0.id == "freshness" }?
        .rows
        .first { $0.id == "dataHealth" }
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

private func snapshot() -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: "2026-06-25",
        totalValue: Money(value: "1000.00", currency: "EUR"),
        openHoldings: [
            NormalizedHolding(
                name: "Example Holding",
                quoteId: 1,
                weight: 0.1,
                worth: Money(value: "100.00", currency: "EUR"),
                price: Money(value: "10.00", currency: "EUR"),
                priceAsOf: "2026-06-24"
            ),
        ],
        sectors: [
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
