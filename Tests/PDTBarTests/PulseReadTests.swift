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
        #expect(descriptor.sections.first { $0.id == "allocation" }?.rows.first { $0.title == "Nova Lithography" } != nil)
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
        let changedModel = PressureEngine.buildModel(from: changedSnapshot, priorSnapshot: snapshot)
        let filtered = PulseReadFilter.apply(
            to: changedModel,
            readState: PulseReadState(readFingerprints: [originalItem.readFingerprint])
        )

        #expect(filtered.rankedAttentionItems.first?.holdingIdentity?.quoteId == originalItem.holdingIdentity?.quoteId)
        #expect(filtered.rankedAttentionItems.first?.readFingerprint != originalItem.readFingerprint)
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
