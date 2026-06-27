import Foundation
import Testing
import PDTBarCore

@Suite("Pulse read state")
struct PulseReadTests {
    @Test("Read store saves and reloads fingerprints beside app state")
    func readStoreSavesAndReloadsFingerprints() throws {
        let store = try temporaryPulseReadStore()

        #expect(try store.load().readFingerprints.isEmpty)

        try store.markRead("pulse:v1:test:fingerprint")

        let reloaded = try PulseReadStore(directory: store.directory).load()
        #expect(reloaded.contains("pulse:v1:test:fingerprint"))
    }

    @Test("Mark read preserves persisted schema version")
    func markReadPreservesSchemaVersion() throws {
        let store = try temporaryPulseReadStore()

        try store.save(PulseReadState(schemaVersion: 2, readFingerprints: ["pulse:v1:existing"]))
        try store.markRead("pulse:v1:new")
        let reloaded = try store.load()

        #expect(reloaded.schemaVersion == 2)
        #expect(reloaded.contains("pulse:v1:existing"))
        #expect(reloaded.contains("pulse:v1:new"))
    }

    @Test("Resetting stale read fingerprints preserves newer read writes")
    func resetPreservesNewerReadWrites() throws {
        let store = try temporaryPulseReadStore()

        try store.save(PulseReadState(readFingerprints: ["pulse:v1:stale"]))
        _ = try store.load()
        try store.markRead("pulse:v1:newer")
        let reset = try store.removeReadFingerprints(["pulse:v1:stale"])

        #expect(!reset.contains("pulse:v1:stale"))
        #expect(reset.contains("pulse:v1:newer"))
        #expect((try store.load()).readFingerprints == ["pulse:v1:newer"])
    }

    @Test("Corrupt read state falls back to empty")
    func corruptReadStateFallsBackToEmpty() throws {
        let store = try temporaryPulseReadStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.directory.appending(path: "pulse-read-state.json"))

        #expect(try store.load().readFingerprints.isEmpty)
    }

    @Test("Unreadable read state aborts mutation instead of resetting")
    func unreadableReadStateAbortsMutationInsteadOfResetting() throws {
        let store = try temporaryPulseReadStore()
        try FileManager.default.createDirectory(
            at: store.directory.appending(path: "pulse-read-state.json"),
            withIntermediateDirectories: true
        )

        #expect(throws: (any Error).self) {
            try store.markRead("pulse:v1:new")
        }
    }

    @Test("Unreadable read state does not block pulse rendering")
    func unreadableReadStateDoesNotBlockPulseRendering() throws {
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-unreadable-read-render-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)
        try FileManager.default.createDirectory(
            at: snapshotStore.directory.appending(path: "pulse-read-state.json"),
            withIntermediateDirectories: true
        )

        let run = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: fixtureSnapshot("concentration-pressure.json")),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )

        #expect(!run.model.rankedAttentionItems.isEmpty)
        #expect(run.descriptor.statusBadge != nil)
    }

    @Test("Same fingerprint hides attention but keeps facet drill-down facts visible")
    func sameFingerprintHidesAttentionOnly() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        let rawModel = PressureEngine.buildModel(from: snapshot)
        let item = try #require(rawModel.rankedAttentionItems.first)
        let readState = PulseReadState(readFingerprints: [item.readFingerprint])

        let filtered = PulseReadFilter.apply(to: rawModel, readState: readState)
        let descriptor = MenuDescriptorRenderer.render(model: filtered)

        #expect(filtered.rankedAttentionItems.isEmpty)
        #expect(descriptor.statusBadge == nil)
        #expect(descriptor.statusVisual.filledBarCount == 0)
        #expect(descriptor.statusTitle.contains("All caught up"))
        #expect(descriptor.sections.first { $0.id == "allocation" }?
            .rows.first { $0.id == "allocation.portfolio.details" }?
            .children.first { $0.title == "Nova Lithography" } != nil)
        #expect(descriptor.sections.first { $0.id == "income" } != nil)
        #expect(descriptor.sections.first { $0.id == "bigMovers" } != nil)
    }

    @Test("Changed material concentration fingerprint resurfaces")
    func changedMaterialConcentrationFingerprintResurfaces() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        let originalModel = PressureEngine.buildModel(from: snapshot)
        let originalItem = try #require(originalModel.rankedAttentionItems.first)

        var changedSnapshot = snapshot
        changedSnapshot.openHoldings[0].weight = 0.265
        let changedModel = PressureEngine.buildModel(
            from: changedSnapshot,
            priorSnapshot: snapshot,
            readState: PulseReadState(readFingerprints: [originalItem.readFingerprint])
        )
        let filtered = PulseReadFilter.apply(
            to: changedModel,
            readState: PulseReadState(readFingerprints: [originalItem.readFingerprint])
        )

        #expect(filtered.rankedAttentionItems.first?.holdingIdentity?.quoteId == originalItem.holdingIdentity?.quoteId)
        #expect(filtered.rankedAttentionItems.first?.readFingerprint != originalItem.readFingerprint)
    }

    @Test("Changed concentration severity resurfaces")
    func changedConcentrationSeverityResurfaces() throws {
        var snapshot = try fixtureSnapshot("concentration-pressure.json")
        snapshot.openHoldings[0].weight = 0.270
        let originalItem = try #require(PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first)
        var changedSnapshot = snapshot
        changedSnapshot.openHoldings[0].weight = 0.290
        let readState = PulseReadState(readFingerprints: [originalItem.readFingerprint])

        let changedModel = PressureEngine.buildModel(
            from: changedSnapshot,
            priorSnapshot: snapshot,
            readState: readState
        )
        let filtered = PulseReadFilter.apply(to: changedModel, readState: readState)

        #expect(originalItem.severity == "medium")
        #expect(filtered.rankedAttentionItems.first?.severity == "high")
        #expect(filtered.rankedAttentionItems.first?.holdingIdentity?.quoteId == originalItem.holdingIdentity?.quoteId)
    }

    @Test("Unread concentration drift stays quiet when already above threshold")
    func unreadConcentrationDriftStaysQuietWhenAlreadyAboveThreshold() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        var changedSnapshot = snapshot
        changedSnapshot.openHoldings[0].weight = 0.265

        let changedModel = PressureEngine.buildModel(from: changedSnapshot, priorSnapshot: snapshot)

        #expect(changedModel.rankedAttentionItems.allSatisfy { $0.holdingIdentity?.quoteId != 9001 })
    }

    @Test("Fresh concentration re-crossing resets old read state")
    func freshConcentrationRecrossingResetsOldReadState() throws {
        var readSnapshot = try fixtureSnapshot("concentration-pressure.json")
        readSnapshot.openHoldings[0].weight = 0.240
        let originalItem = try #require(PressureEngine.buildModel(from: readSnapshot).rankedAttentionItems.first)
        var priorSnapshot = readSnapshot
        priorSnapshot.openHoldings[0].weight = 0.190
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-recross-read-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)

        try readStore.markRead(originalItem.readFingerprint)
        _ = try snapshotStore.commitCurrentSnapshot(priorSnapshot)
        let refresh = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: readSnapshot),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )

        #expect(refresh.model.rankedAttentionItems.first?.readFingerprint == originalItem.readFingerprint)
        #expect(!((try readStore.load()).contains(originalItem.readFingerprint)))
    }

    @Test("Changed income fingerprint resurfaces and prunes stale read")
    func changedIncomeFingerprintResurfacesAndPrunesStaleRead() throws {
        let originalSnapshot = try fixtureSnapshot("income-event.json")
        let originalItem = try #require(
            PressureEngine.buildModel(from: originalSnapshot)
                .rankedAttentionItems
                .first { $0.facet == "income" }
        )
        var changedSnapshot = originalSnapshot
        let eventIndex = try #require(
            changedSnapshot.incomeEvents.firstIndex { $0.kind == "ex-dividend" && !$0.estimated }
        )
        changedSnapshot.incomeEvents[eventIndex].date = "2026-07-01"
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-income-stale-read-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)

        try readStore.markRead(originalItem.readFingerprint)
        let run = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: changedSnapshot),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let changedItem = try #require(run.model.rankedAttentionItems.first { $0.facet == "income" })
        let readState = try readStore.load()

        #expect(changedItem.readFingerprint != originalItem.readFingerprint)
        #expect(run.source == .fetchedSnapshot)
        #expect(run.readState?.contains(originalItem.readFingerprint) == false)
        #expect(!readState.contains(originalItem.readFingerprint))
        #expect(!readState.contains(changedItem.readFingerprint))
    }

    @Test("Same material concentration remains read after prior-aware refresh and cached relaunch")
    func sameMaterialConcentrationRemainsReadAfterRefreshAndRelaunch() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        let originalItem = try #require(PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first)
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-read-refresh-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)

        try readStore.markRead(originalItem.readFingerprint)
        _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        let refresh = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: snapshot),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let maybeCached = try PressureRunner.cachedPulse(
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let cached = try #require(maybeCached)

        #expect(refresh.model.rankedAttentionItems.isEmpty)
        #expect(refresh.source == .fetchedSnapshot)
        #expect(try readStore.load().contains(originalItem.readFingerprint))
        #expect(cached.source == .cachedSnapshot)
        #expect(cached.descriptor.statusBadge == nil)
        #expect(cached.descriptor.statusTitle.contains("All caught up"))
    }

    @Test("Cached relaunch returns the same lifecycle result shape as first fetch")
    func cachedRelaunchReturnsPulseLifecycleResult() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        let originalItem = try #require(PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first)
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-read-lifecycle-cache-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)

        try readStore.markRead(originalItem.readFingerprint)
        _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        let maybeCached = try PressureRunner.cachedPulse(
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let cached = try #require(maybeCached)

        #expect(cached.source == .cachedSnapshot)
        #expect(cached.snapshotCommit.written == false)
        #expect(cached.snapshotCommit.asOf == snapshot.asOf)
        #expect(cached.model.rankedAttentionItems.isEmpty)
        #expect(cached.readState?.contains(originalItem.readFingerprint) == true)
        #expect(cached.descriptor.statusBadge == nil)
        #expect(cached.descriptor.statusTitle.contains("All caught up"))
    }

    @Test("Refreshed snapshot returns lifecycle result with commit read state and descriptor")
    func refreshedSnapshotReturnsPulseLifecycleResult() throws {
        let snapshot = try fixtureSnapshot("concentration-pressure.json")
        let originalItem = try #require(PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first)
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-read-lifecycle-refresh-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)
        var priorSnapshot = snapshot
        priorSnapshot.openHoldings[0].weight = 0.190

        try readStore.markRead(originalItem.readFingerprint)
        let refreshed = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: priorSnapshot,
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let committed = try #require(try snapshotStore.loadPriorSnapshot())

        #expect(refreshed.source == .refreshedSnapshot)
        #expect(refreshed.snapshotCommit.written)
        #expect(refreshed.snapshotCommit.asOf == snapshot.asOf)
        #expect(committed.asOf == snapshot.asOf)
        #expect(refreshed.model.rankedAttentionItems.contains {
            $0.readFingerprint == originalItem.readFingerprint
        })
        #expect(refreshed.readState?.contains(originalItem.readFingerprint) == false)
        #expect(!((try readStore.load()).contains(originalItem.readFingerprint)))
        #expect(refreshed.descriptor == MenuDescriptorRenderer.render(model: refreshed.model))
    }

    @Test("Cached relaunch does not prune prior-dependent big-mover read state")
    func cachedRelaunchDoesNotPruneBigMoverReadState() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-big-mover-read-relaunch-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)
        _ = try PressureRunner.seedPriorSnapshot(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: snapshotStore,
            asOf: "2026-06-15"
        )
        let run = try PressureRunner.run(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: snapshotStore,
            asOf: "2026-06-22",
            pulseReadStore: readStore
        )
        let bigMover = try #require(run.model.rankedAttentionItems.first { $0.facet == "bigMovers" })

        try readStore.markRead(bigMover.readFingerprint)
        _ = try PressureRunner.cachedPulse(snapshotStore: snapshotStore, pulseReadStore: readStore)

        #expect(try readStore.load().contains(bigMover.readFingerprint))
    }

    @Test("Applying read state to current lifecycle keeps unread prior-dependent movers")
    func applyingReadStateToCurrentLifecycleKeepsUnreadBigMovers() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
        let dataSource = PDTFixtureDataSource(fixture: fixture)
        var priorSnapshot = try dataSource.priorSnapshot(asOf: "2026-06-15")
        var currentSnapshot = try dataSource.snapshot(asOf: "2026-06-22")
        var priorSecondMover = try #require(priorSnapshot.openHoldings.first)
        priorSecondMover.name = "Orion Software"
        priorSecondMover.quoteId = 9002
        priorSecondMover.weight = 0.060
        priorSecondMover.worth = Money(value: "3000.00", currency: "EUR")
        priorSecondMover.price = Money(value: "100.00", currency: "EUR")
        var currentSecondMover = priorSecondMover
        currentSecondMover.weight = 0.070
        currentSecondMover.worth = Money(value: "3450.00", currency: "EUR")
        currentSecondMover.price = Money(value: "115.00", currency: "EUR")
        priorSnapshot.openHoldings.append(priorSecondMover)
        currentSnapshot.openHoldings.append(currentSecondMover)
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-current-lifecycle-big-mover-read-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)

        _ = try snapshotStore.commitCurrentSnapshot(priorSnapshot)
        let run = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: currentSnapshot),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let bigMovers = run.model.rankedAttentionItems.filter { $0.facet == "bigMovers" }
        let readMover = try #require(bigMovers.first)
        let unreadMover = try #require(bigMovers.dropFirst().first)

        try readStore.markRead(readMover.readFingerprint)
        let refreshed = run.applyingReadState(try readStore.load())
        let visibleFingerprints = Set(refreshed.model.rankedAttentionItems.map(\.readFingerprint))

        #expect(!visibleFingerprints.contains(readMover.readFingerprint))
        #expect(visibleFingerprints.contains(unreadMover.readFingerprint))
    }

    @Test("Partial refresh preserves omitted facet read state")
    func partialRefreshPreservesOmittedFacetReadState() throws {
        let incomeItem = try #require(
            PressureEngine.buildModel(from: fixtureSnapshot("income-event.json"))
                .rankedAttentionItems
                .first { $0.facet == "income" }
        )
        let bigMover = try #require(
            bigMoverRun().model.rankedAttentionItems.first { $0.facet == "bigMovers" }
        )
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-partial-refresh-read-test")
        let readStore = PulseReadStore(directory: snapshotStore.directory)
        var partialSnapshot = try fixtureSnapshot("concentration-pressure.json")
        partialSnapshot.incomeEvents = []
        partialSnapshot.dividendRowCount = 0
        partialSnapshot.priceSeries = []

        try readStore.markRead(incomeItem.readFingerprint)
        try readStore.markRead(bigMover.readFingerprint)
        _ = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: partialSnapshot),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        let readState = try readStore.load()

        #expect(readState.contains(incomeItem.readFingerprint))
        #expect(readState.contains(bigMover.readFingerprint))
    }

    @Test("Fingerprints include facet material facts")
    func fingerprintsIncludeFacetMaterialFacts() throws {
        let concentration = try #require(
            PressureEngine.buildModel(from: fixtureSnapshot("concentration-pressure.json"))
                .rankedAttentionItems
                .first { $0.facet == "allocation" }
        )
        let income = AttentionItem(
            id: "income.ex-dividend.9003",
            facet: "income",
            rank: 1,
            title: "Helix Pharma A/S ex-dividend",
            severity: "low",
            score: 0.45,
            holdingIdentity: HoldingIdentity(name: "Helix Pharma A/S", quoteId: 9003),
            eventDate: "2026-06-24",
            amount: Money(value: "78.00", currency: "EUR"),
            changePercent: 0.1818,
            supportingDataSlotIDs: ["income.calendar"]
        )
        let bigMoverRun = try bigMoverRun()
        let bigMover = try #require(bigMoverRun.model.rankedAttentionItems.first { $0.facet == "bigMovers" })

        #expect(concentration.readFingerprint.contains("quote:9001"))
        #expect(concentration.readFingerprint.contains("threshold-bp:2000"))
        #expect(concentration.readFingerprint.contains("weight-bucket-bp:2400"))
        #expect(income.readFingerprint.contains("quote:9003"))
        #expect(income.readFingerprint.contains("date:2026-06-24"))
        #expect(income.readFingerprint.contains("amount:EUR:78.00"))
        #expect(income.readFingerprint.contains("change-bp:1818"))
        #expect(bigMover.readFingerprint.contains("quote:9001"))
        #expect(bigMover.readFingerprint.contains("window:2026-06-15..2026-06-22"))
        #expect(bigMover.readFingerprint.contains("move-bucket-bp:1200"))
    }

    @Test("Fingerprint identity ignores non-material holding name changes")
    func fingerprintIdentityIgnoresNonMaterialHoldingNameChanges() {
        let first = AttentionItem(
            id: "allocation.concentration.9003",
            facet: "allocation",
            rank: 1,
            title: "Helix Pharma A/S concentration",
            severity: "medium",
            score: 0.7,
            holdingIdentity: HoldingIdentity(name: "Helix Pharma A/S", quoteId: 9003),
            currentWeight: 0.24,
            threshold: 0.20,
            supportingDataSlotIDs: ["allocation.openHoldings"]
        )
        var renamed = first
        renamed.holdingIdentity = HoldingIdentity(name: "Helix Pharma AS", quoteId: 9003)

        #expect(first.readFingerprint == renamed.readFingerprint)
        #expect(!first.readFingerprint.contains("Helix"))
    }

    @Test("Missing numeric fingerprint facts differ from real zero")
    func missingNumericFingerprintFactsDifferFromRealZero() {
        let missingChange = AttentionItem(
            id: "income.ex-dividend.9003",
            facet: "income",
            rank: 1,
            title: "Helix Pharma A/S ex-dividend",
            severity: "low",
            score: 0.45,
            holdingIdentity: HoldingIdentity(name: "Helix Pharma A/S", quoteId: 9003),
            eventDate: "2026-06-24",
            amount: Money(value: "78.00", currency: "EUR"),
            changePercent: nil,
            supportingDataSlotIDs: ["income.calendar"]
        )
        var zeroChange = missingChange
        zeroChange.changePercent = 0.0

        #expect(missingChange.readFingerprint.contains("change-bp:missing"))
        #expect(zeroChange.readFingerprint.contains("change-bp:0"))
        #expect(missingChange.readFingerprint != zeroChange.readFingerprint)
    }

    @Test("Renderer exposes one mark-as-read action per attention row")
    func rendererExposesMarkAsReadAction() throws {
        let model = PressureEngine.buildModel(from: try fixtureSnapshot("concentration-pressure.json"))
        let item = try #require(model.rankedAttentionItems.first)
        let descriptor = MenuDescriptorRenderer.render(model: model)
        let action = descriptor.sections
            .flatMap(\.rows)
            .flatMap(\.children)
            .first { $0.role == .pulseMarkRead }

        #expect(action?.title == "Mark as read")
        #expect(action?.actionPayload == item.readFingerprint)
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func fixtureSnapshot(_ name: String) throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/\(name)"))
}

private func bigMoverRun() throws -> PressureRunResult {
    let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-big-mover-test")
    _ = try PressureRunner.seedPriorSnapshot(
        dataSource: PDTFixtureDataSource(fixture: fixture),
        snapshotStore: store,
        asOf: "2026-06-15"
    )
    return try PressureRunner.run(
        dataSource: PDTFixtureDataSource(fixture: fixture),
        snapshotStore: store,
        asOf: "2026-06-22"
    )
}

private func temporaryPulseReadStore() throws -> PulseReadStore {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-pulse-read-tests-\(UUID().uuidString)")
    return PulseReadStore(directory: directory)
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var fixedSnapshot: PortfolioSnapshot

    init(snapshot: PortfolioSnapshot) {
        fixedSnapshot = snapshot
    }

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        fixedSnapshot
    }
}
