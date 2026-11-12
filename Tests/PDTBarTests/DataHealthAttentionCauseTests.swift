import Foundation
import Testing
@testable import PDTBarCore

@Suite("Data health attention cause")
struct DataHealthAttentionCauseTests {
    @Test("Every attention cause names itself in the summary and in its own row", arguments: DataHealthAttentionCause.allCases)
    func everyCauseIsNamed(cause: DataHealthAttentionCause) {
        let example = example(of: cause)
        let health = DataHealth.build(example.input)
        let row = MenuDescriptorRenderer.dataHealthRow(for: health)
        let baseline = MenuDescriptorRenderer.dataHealthRow(for: DataHealth.build(healthyInput()))
        let named = row.children.first { $0.id == cause.rowID }

        #expect(health.status == .degraded)
        #expect(row.detail == example.summary)
        #expect(named?.detail == example.rowDetail)
        #expect(named?.detail != baseline.children.first { $0.id == cause.rowID }?.detail)
        #expect(row.children.map(\.id) == [
            "dataHealth.source",
            "dataHealth.access",
            "dataHealth.cache",
            "dataHealth.freshness",
            "dataHealth.detailFill",
            "dataHealth.readState",
            "dataHealth.diagnostic",
        ])
    }

    @Test("Concentration-pressure in the running app shows its stale prices once, in the Prices row")
    func concentrationPressureShowsStalePricesOnce() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-cause-concentration")
        let run = try PressureRunner.run(dataSource: PDTFixtureDataSource(fixture: concentrationFixture), snapshotStore: store)

        #expect(run.model.facetSnapshots.dataHealth.status == .degraded)
        for descriptor in [run.descriptor, run.descriptor(in: DataHealthRuntime(access: .connected))] {
            let rows = dataRows(in: descriptor)
            #expect(rows.map(\.id) == ["freshness.summary"])
            #expect(rows.first?.detail == "2 stale; oldest 2026-06-18")
        }
    }

    @Test("Stale prices with a recorded sync failure still show Data health, summary unchanged")
    func stalePricesWithRecordedFailureKeepDataHealth() throws {
        let rows = dataRows(in: try menu(showing: staleWithRecordedFailure))

        #expect(rows.map(\.id) == ["freshness.summary", "dataHealth"])
        #expect(rows.first?.detail == "2 stale; oldest 2026-06-18")
        #expect(rows.last?.detail == "2 stale prices")
        #expect(rows.last?.children.first { $0.id == "dataHealth.diagnostic" }?.detail
            == "Price history: PDT server problem; try again later")
    }

    @Test("A saved copy with stale prices still shows Data health")
    func savedCopyWithStalePricesKeepsDataHealth() throws {
        var input = staleOnly
        input.pulseSource = .cachedSnapshot
        let rows = dataRows(in: try menu(showing: input))

        #expect(rows.map(\.id) == ["freshness.summary", "dataHealth"])
        #expect(rows.last?.detail == "Showing a saved copy")
    }

    @Test("The running app's Data health replacement hides and shows the row by the same rule")
    func runtimeReplacementFollowsTheSameRule() throws {
        var unknownOnly = healthyInput()
        unknownOnly.freshness = freshness(.unknown, staleCount: 0, oldest: nil)
        let replacedRows = { (menu: MenuDescriptor, health: DataHealthSnapshot) in
            dataRows(in: MenuDescriptorRenderer.descriptorByReplacingDataHealth(in: menu, with: health))
        }

        for menu in [try menu(showing: staleOnly), try menu(showing: staleWithRecordedFailure)] {
            for priceFreshnessOnly in [staleOnly, unknownOnly] {
                #expect(replacedRows(menu, DataHealth.build(priceFreshnessOnly)).map(\.id) == ["freshness.summary"])
            }

            let failed = replacedRows(menu, DataHealth.build(staleWithRecordedFailure))
            #expect(failed.map(\.id) == ["freshness.summary", "dataHealth"])
            #expect(failed.last?.detail == "2 stale prices")

            let refreshing = replacedRows(menu, DataHealth.snapshot(
                DataHealth.build(staleOnly),
                in: DataHealthRuntime(access: .connected, sync: .running(BackgroundDetailRefreshProgress(phase: .priceHistory)))
            ))
            #expect(refreshing.map(\.id) == ["freshness.summary", "dataHealth"])
            #expect(refreshing.last?.detail == "Refreshing")
        }
    }

    @Test("An empty portfolio in the running app raises no Data health cause")
    func emptyPortfolioIsNotADataHealthProblem() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "data-health-cause-empty-portfolio")
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/income-event.json")
        let run = try PressureRunner.run(dataSource: PDTFixtureDataSource(fixture: fixture), snapshotStore: store)
        let descriptor = run.descriptor(in: DataHealthRuntime(access: .connected))
        let section = try #require(descriptor.sections.first { $0.id == "freshness" })

        #expect(run.model.portfolioGlance.openHoldingCount == 0)
        #expect(section.rows.map(\.id) == ["freshness.summary"])
    }

    @Test("A blocked connection is named before a saved copy or stale prices")
    func blockedAccessIsNamedFirst() {
        var input = healthyInput()
        input.pulseSource = .cachedSnapshot
        input.freshness = staleFreshness
        #expect(MenuDescriptorRenderer.dataHealthRow(for: DataHealth.build(input)).detail == "Showing a saved copy")

        input.access = .reconnect(.tokenRevoked)
        #expect(MenuDescriptorRenderer.dataHealthRow(for: DataHealth.build(input)).detail == "Reconnect needed")
    }
}

private struct CauseExample {
    var input: DataHealthInput
    var summary: String
    var rowDetail: String
}

private func example(of cause: DataHealthAttentionCause) -> CauseExample {
    var input = healthyInput()
    switch cause {
    case .notConnected:
        input.access = .notConnected
        return CauseExample(input: input, summary: "Not connected", rowDetail: "Not connected")
    case .reconnectNeeded:
        input.access = .reconnect(.tokenRevoked)
        return CauseExample(
            input: input,
            summary: "Reconnect needed",
            rowDetail: "Reconnect needed: PDTBar's access was revoked in PDT"
        )
    case .subscriptionPaused:
        input.access = .subscriptionPaused
        return CauseExample(
            input: input,
            summary: "Subscription paused",
            rowDetail: "Paused: your PDT subscription has ended"
        )
    case .connectionNotSaved:
        input.access = .notSaved
        return CauseExample(input: input, summary: "Connection not saved", rowDetail: "Not saved on this Mac")
    case .keychainUnavailable:
        input.access = .keychainUnavailable
        return CauseExample(input: input, summary: "Keychain unavailable", rowDetail: "Keychain unavailable")
    case .detailFillFailed:
        input.detailFill = .failed
        return CauseExample(input: input, summary: "Detail fill failed", rowDetail: "Failed")
    case .savedCopy:
        input.pulseSource = .cachedSnapshot
        return CauseExample(
            input: input,
            summary: "Showing a saved copy",
            rowDetail: "PDT, read-only; saved copy from 2026-06-25"
        )
    case .notFetched:
        input.pulseSource = nil
        return CauseExample(
            input: input,
            summary: "Not fetched this session",
            rowDetail: "PDT, read-only; not fetched this session"
        )
    case .accessNotChecked:
        input.access = .unverified
        return CauseExample(input: input, summary: "Connection not checked", rowDetail: "Not checked this session")
    case .unknownPriceDates:
        input.freshness = freshness(.unknown, staleCount: 0, oldest: nil)
        return CauseExample(input: input, summary: "Unknown price dates", rowDetail: "Unknown")
    case .stalePrices:
        input.freshness = staleFreshness
        return CauseExample(
            input: input,
            summary: "2 stale prices",
            rowDetail: "2 stale; oldest 2026-06-18"
        )
    case .detailFillIncomplete:
        input.freshness = freshness(.partial, staleCount: 0, oldest: "2026-06-24")
        input.detailFill = .completed(asOf: "2026-06-20")
        return CauseExample(
            input: input,
            summary: "Detail fill incomplete",
            rowDetail: "Incomplete; last complete 2026-06-20"
        )
    case .failureRecorded:
        input.lastFailure = PDTSyncFailure(phase: .priceHistory, endpoint: .pricesBatch, kind: .server(status: 503), requestCount: 1)
        return CauseExample(
            input: input,
            summary: "Last sync failed",
            rowDetail: "Price history: PDT server problem; try again later"
        )
    }
}

private func healthyInput() -> DataHealthInput {
    DataHealthInput(
        access: .connected,
        pulseSource: .fetchedSnapshot,
        lastSyncAsOf: "2026-06-25",
        lastCompleteSyncAsOf: "2026-06-25",
        priorSnapshotStatus: nil,
        detailFill: .completed(asOf: "2026-06-25"),
        freshness: freshness(.fresh, staleCount: 0, oldest: "2026-06-24"),
        readState: nil,
        lastFailure: nil
    )
}

private var staleFreshness: FreshnessSnapshot {
    freshness(.stale, staleCount: 2, oldest: "2026-06-18")
}

private var staleOnly: DataHealthInput {
    var input = healthyInput()
    input.freshness = staleFreshness
    return input
}

private var staleWithRecordedFailure: DataHealthInput {
    var input = staleOnly
    input.lastFailure = PDTSyncFailure(phase: .priceHistory, endpoint: .pricesBatch, kind: .server(status: 503), requestCount: 1)
    return input
}

/// The concentration-pressure menu, whose Prices row reads "2 stale; oldest 2026-06-18", with this Data health.
private func menu(showing input: DataHealthInput) throws -> MenuDescriptor {
    var model = PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: concentrationFixture))
    model.facetSnapshots.dataHealth = DataHealth.build(input)
    return MenuDescriptorRenderer.render(model: model)
}

private func dataRows(in descriptor: MenuDescriptor) -> [MenuRow] {
    descriptor.sections.first { $0.id == "freshness" }?.rows ?? []
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let concentrationFixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")

private func freshness(_ status: FreshnessState, staleCount: Int, oldest: String?) -> FreshnessSnapshot {
    FreshnessSnapshot(
        status: status,
        worstPriceAsOf: oldest,
        stale: status == .stale,
        staleHoldingCount: staleCount,
        oldestPriceAsOf: oldest,
        oldestRows: [],
        latestCompleteDetailFillAsOf: "2026-06-25",
        sourceCaveats: []
    )
}
