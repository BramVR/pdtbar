import Foundation
import Testing
import PDTBarCore

@Suite("Snapshot store protection")
struct SnapshotStoreTests {
    @Test("Snapshot writes create owner-only directory and files")
    func snapshotWritesCreateOwnerOnlyDirectoryAndFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-snapshot-permissions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SnapshotStore(directory: directory)
        let snapshot = try PDTFixtureDataSource.snapshot(
            from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
        )
        _ = try store.commitCurrentSnapshot(snapshot)
        try store.saveLastDetailRefreshDiagnostic(PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-list-symbol-prices",
            phase: .priceHistory,
            attemptCount: 1,
            category: .transientFailure,
            argumentShape: ["date_from", "date_to", "symbol_quote_id"]
        ))
        try PulseReadStore(directory: directory).markRead("pulse:v1:sanitized:fingerprint")

        #expect(try permissions(of: directory) == 0o700)
        #expect(try permissions(of: store.currentSnapshotPath) == 0o600)
        #expect(try permissions(of: directory.appending(path: "latest-detail-refresh-diagnostic.json")) == 0o600)
        #expect(try permissions(of: directory.appending(path: "pulse-read-state.json")) == 0o600)
        #expect(try store.loadPriorSnapshot() == snapshot)
    }

    @Test("Committing a concentration re-crossing clears the old read mark before the snapshot lands")
    func committingRecrossingClearsOldReadMark() throws {
        let crossing = try ConcentrationCrossing()
        _ = try crossing.store.commitCurrentSnapshot(crossing.below)
        try crossing.readStore.markRead(crossing.alert.readFingerprint)

        _ = try crossing.store.commitCurrentSnapshot(crossing.above)

        #expect(!(try crossing.readStore.load()).contains(crossing.alert.readFingerprint))
        #expect(try crossing.store.loadPriorSnapshot() == crossing.above)
    }

    @Test("A mark set after the crossing commit survives later commits of the same holdings")
    func markAfterCrossingSurvivesLaterCommits() throws {
        let crossing = try ConcentrationCrossing()
        _ = try crossing.store.commitCurrentSnapshot(crossing.below)
        _ = try crossing.store.commitCurrentSnapshot(crossing.above)
        try crossing.readStore.markRead(crossing.alert.readFingerprint)

        _ = try crossing.store.commitCurrentSnapshot(crossing.above)

        #expect((try crossing.readStore.load()).contains(crossing.alert.readFingerprint))
    }

    @Test("A commit over a corrupt prior snapshot keeps read marks and replaces the snapshot")
    func commitOverCorruptPriorKeepsReadMarks() throws {
        let crossing = try ConcentrationCrossing()
        try Data("not json".utf8).write(to: crossing.store.currentSnapshotPath)
        try crossing.readStore.markRead(crossing.alert.readFingerprint)

        _ = try crossing.store.commitCurrentSnapshot(crossing.above)

        #expect((try crossing.readStore.load()).contains(crossing.alert.readFingerprint))
        #expect(try crossing.store.loadPriorSnapshot() == crossing.above)
    }

    @Test("Loading an existing broad snapshot tightens permissions")
    func loadingExistingBroadSnapshotTightensPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-legacy-snapshot-permissions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SnapshotStore(directory: directory)
        let snapshot = try PDTFixtureDataSource.snapshot(
            from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
        )
        try JSONEncoder().encode(snapshot).write(to: store.currentSnapshotPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.currentSnapshotPath.path)

        #expect(try store.loadPriorSnapshot() == snapshot)
        #expect(try permissions(of: directory) == 0o700)
        #expect(try permissions(of: store.currentSnapshotPath) == 0o600)
    }

    @Test("Prior snapshot load result classifies missing corrupt and valid history")
    func priorSnapshotLoadResultClassifiesMissingCorruptAndValidHistory() throws {
        let missingStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-missing-prior")
        defer {
            try? FileManager.default.removeItem(at: missingStore.directory)
        }
        #expect(try missingStore.loadPriorSnapshotResult() == .missing)

        let corruptStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-corrupt-prior")
        defer {
            try? FileManager.default.removeItem(at: corruptStore.directory)
        }
        try Data("{".utf8).write(to: corruptStore.currentSnapshotPath)
        #expect(try corruptStore.loadPriorSnapshotResult() == .failed(.decode))

        let unreadableStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-unreadable-prior")
        defer {
            try? FileManager.default.removeItem(at: unreadableStore.directory)
        }
        try FileManager.default.createDirectory(at: unreadableStore.currentSnapshotPath, withIntermediateDirectories: true)
        #expect(try unreadableStore.loadPriorSnapshotResult() == .failed(.io))

        let validStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-valid-prior")
        defer {
            try? FileManager.default.removeItem(at: validStore.directory)
        }
        let snapshot = try PDTFixtureDataSource.snapshot(
            from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
        )
        _ = try validStore.commitCurrentSnapshot(snapshot)
        #expect(try validStore.loadPriorSnapshotResult() == .loaded(snapshot))
    }

    @Test("Runner surfaces corrupt prior history without using it for pressure")
    func runnerSurfacesCorruptPriorHistoryWithoutUsingItForPressure() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-corrupt-prior-runner")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        try Data("{".utf8).write(to: store.currentSnapshotPath)

        let run = try PressureRunner.run(
            dataSource: StaticPortfolioDataSource(snapshot: try PDTFixtureDataSource.snapshot(
                from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
            )),
            snapshotStore: store
        )

        #expect(run.priorSnapshotLoadStatus == .failed(.decode))
        #expect(run.model.portfolioGlance.priorSnapshotAsOf == nil)
        #expect(run.model.facetSnapshots.dataHealth.cache.priorSnapshotStatus == .corrupt)
        #expect(run.model.allQuiet)
    }

    @Test("Failed snapshot writes remove temporary files")
    func failedSnapshotWritesRemoveTemporaryFiles() throws {
        let directory = try SnapshotStore.temporaryTestStore(
            prefix: "pdtbar-failed-snapshot-write"
        ).directory
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SnapshotStore(directory: directory)
        try FileManager.default.createDirectory(
            at: store.currentSnapshotPath,
            withIntermediateDirectories: true
        )
        let snapshot = try PDTFixtureDataSource.snapshot(
            from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
        )

        #expect(throws: (any Error).self) {
            _ = try store.commitCurrentSnapshot(snapshot)
        }
        #expect(try temporarySnapshotFiles(in: directory).isEmpty)
    }
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var snapshot: PortfolioSnapshot

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        snapshot
    }
}

private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let value = try #require(attributes[.posixPermissions] as? NSNumber)
    return value.intValue & 0o777
}

private func temporarySnapshotFiles(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
        $0.hasPrefix(".latest-portfolio-snapshot.json.") && $0.hasSuffix(".tmp")
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// A concentration holding below the threshold in `below` and above it in `above`, with stores in one directory.
private struct ConcentrationCrossing {
    let store: SnapshotStore
    let readStore: PulseReadStore
    let below: PortfolioSnapshot
    let above: PortfolioSnapshot
    let alert: AttentionItem

    init() throws {
        store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-snapshot-recrossing")
        readStore = PulseReadStore(directory: store.directory)
        above = try PDTFixtureDataSource.snapshot(
            from: packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
        )
        let alert = try #require(PressureEngine.buildModel(from: above).rankedAttentionItems.first {
            $0.id.hasPrefix("allocation.concentration.")
        })
        self.alert = alert
        var below = above
        let index = try #require(below.openHoldings.firstIndex { $0.quoteId == alert.holdingIdentity?.quoteId })
        below.openHoldings[index].weight = PressureEngine.concentrationThreshold - 0.01
        self.below = below
    }
}
