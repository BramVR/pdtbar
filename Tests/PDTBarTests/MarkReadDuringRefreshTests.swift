import Foundation
import Testing
@testable import PDTBarCore

@Suite("Mark as read during a background refresh")
struct MarkReadDuringRefreshTests {
    @Test("Refresh progress keeps flowing after a row is marked read")
    func refreshProgressKeepsFlowingAfterMarkRead() throws {
        let app = try ReturningLaunch()
        let item = try #require(app.cachedPulse.model.rankedAttentionItems.first)

        let marked = try app.markRead(item)
        let progress = app.runtime.backgroundDetailRefreshProgress(
            BackgroundDetailRefreshProgress(phase: .priceHistory, completedUnitCount: 12, totalUnitCount: 19)
        )

        #expect(rowTitles(in: marked.descriptor).contains("Filling details"))
        #expect(!markReadPayloads(in: marked.descriptor).contains(item.id))
        let progressDescriptor = try #require(progress?.descriptor)
        #expect(rowTitles(in: progressDescriptor).contains("12/19 price histories checked"))
        #expect(!markReadPayloads(in: progressDescriptor).contains(item.id))
        #expect(app.runtime.beginBackgroundDetailRefresh() == nil)
    }

    @Test("A row marked read stays read when the refresh finishes")
    func rowMarkedReadStaysReadWhenRefreshFinishes() throws {
        let app = try ReturningLaunch()
        let item = try #require(app.cachedPulse.model.rankedAttentionItems.first)
        let refreshedBeforeMark = app.cachedPulse

        _ = try app.markRead(item)
        let finished = app.runtime.completeBackgroundDetailRefresh(
            .succeeded(refreshedBeforeMark, outcome: .completed)
        )

        #expect(!markReadPayloads(in: finished.descriptor).contains(item.id))
        #expect(app.runtime.currentPulse?.model.rankedAttentionItems.contains { $0.id == item.id } == false)
    }

    @Test("A row marked read stays read when a degraded refresh finishes")
    func rowMarkedReadStaysReadWhenDegradedRefreshFinishes() throws {
        let app = try ReturningLaunch()
        let item = try #require(app.cachedPulse.model.rankedAttentionItems.first)

        _ = try app.markRead(item)
        let finished = app.runtime.completeBackgroundDetailRefresh(
            .succeeded(app.cachedPulse, outcome: .degraded)
        )
        let markedAfter = try app.markRead(item)

        #expect(!markReadPayloads(in: finished.descriptor).contains(item.id))
        #expect(rowTitles(in: markedAfter.descriptor).contains("Details partially filled"))
    }
}

/// A returning launch with a cached concentration pulse, ready readiness, and a background refresh in flight.
private struct ReturningLaunch {
    let readStore: PulseReadStore
    let cachedPulse: PulseLifecycleResult
    let runtime: PDTLaunchRuntime

    init() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
        let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-mark-read-during-refresh")
        let readStore = PulseReadStore(directory: snapshotStore.directory)
        _ = try PressureRunner.run(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: snapshotStore,
            pulseReadStore: readStore
        )
        self.readStore = readStore
        cachedPulse = try #require(try PressureRunner.cachedPulse(
            snapshotStore: snapshotStore,
            pulseReadStore: readStore,
            today: "2026-06-22"
        ))
        runtime = PDTLaunchRuntime()
        _ = runtime.launch(cachedPulse: cachedPulse)
        let ready = runtime.completeReadinessProbe(.ready, for: runtime.readinessAttempt)
        try #require(ready.effect == .startBackgroundDetailRefresh)
    }

    /// What the app does when the user clicks a row's Mark as read item.
    func markRead(_ item: AttentionItem) throws -> PDTOnboardingUpdate {
        try readStore.markRead(item.readFingerprint)
        let current = try #require(runtime.currentPulse)
        return runtime.publishPulse(current.applyingReadState(try readStore.load()))
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func allRows(in descriptor: MenuDescriptor) -> [MenuRow] {
    func flatten(_ rows: [MenuRow]) -> [MenuRow] {
        rows.flatMap { [$0] + flatten($0.children) }
    }
    return flatten(descriptor.sections.flatMap(\.rows))
}

private func rowTitles(in descriptor: MenuDescriptor) -> [String] {
    allRows(in: descriptor).map(\.title)
}

private func markReadPayloads(in descriptor: MenuDescriptor) -> [String] {
    allRows(in: descriptor).filter { $0.role == .pulseMarkRead }.compactMap(\.actionPayload)
}
