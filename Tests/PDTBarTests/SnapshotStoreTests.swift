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
