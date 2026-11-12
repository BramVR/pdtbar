import Foundation
import Testing
@testable import PDTBarCore

@Suite("Menu overflow fit")
struct MenuOverflowFitTests {
    /// Screen heights from #296: a 1440x900 display and a 1470x956 notched display, less the app's 8 pt margin.
    static let budgets: [Double] = [876 - 8, 919 - 8]
    static let existingFixtures = [
        "concentration-pressure.json", "quiet-no-pressure.json", "income-event.json", "big-mover.json",
    ]

    @Test("The test height model matches the real worst-case menu (1071 pt in menu-measure)")
    func heightModelMatchesCapture() throws {
        #expect(estimatedHeight(try surface("worst-case-height.json")) == 1071)
    }

    @Test("A menu that fits renders unchanged, byte for byte", arguments: existingFixtures)
    func fittingMenuIsUnchanged(fixture: String) throws {
        let original = try surface(fixture)
        for budget in Self.budgets {
            let fitted = original.fitted(within: budget, build: { $0 }, height: estimatedHeight)

            #expect(fitted.steps.isEmpty)
            #expect(try stableJSONData(fitted.built) == stableJSONData(original))
        }
    }

    @Test("The worst case fits small screens, with and without a failed refresh", arguments: budgets)
    func worstCaseFits(budget: Double) throws {
        for original in [try surface("worst-case-height.json"), try refreshFailureSurface("worst-case-height.json")] {
            #expect(estimatedHeight(original) > budget)

            let fitted = original.fitted(within: budget, build: { $0 }, height: estimatedHeight)

            #expect(estimatedHeight(fitted.built) <= budget)
            #expect(fitted.built.sections.first { $0.id == "actions" } == original.sections.first { $0.id == "actions" })
        }
    }

    @Test("Overflow gives up Big movers first, then Income, the chart, and attention items last")
    func cutOrder() throws {
        let original = try refreshFailureSurface("worst-case-height.json")
        let full = estimatedHeight(original)

        let slightlyOver = original.fitted(within: full - 1, build: { $0 }, height: estimatedHeight)
        let tiny = original.fitted(within: 0, build: { $0 }, height: estimatedHeight)

        #expect(slightlyOver.steps == [.foldBigMovers])
        #expect(tiny.steps == MenuOverflowStep.allCases)
    }

    @Test("Every step keeps every row reachable", arguments: MenuOverflowStep.allCases)
    func everyRowStaysReachable(through last: MenuOverflowStep) throws {
        for fixture in Self.existingFixtures + ["worst-case-height.json"] {
            let original = try surface(fixture)
            let compacted = MenuOverflowStep.allCases
                .prefix { $0.rawValue <= last.rawValue }
                .reduce(original) { $0.compacted(by: $1) }

            #expect(rowIDs(compacted).isSuperset(of: rowIDs(original)), "\(fixture) through \(last)")
            #expect(compacted.sections.first { $0.id == "actions" } == original.sections.first { $0.id == "actions" })
        }
    }

    @Test("Folded rows open the rows they replaced")
    func foldedRowsOpenWhatTheyReplaced() throws {
        let original = try surface("worst-case-height.json")
        let compacted = MenuOverflowStep.allCases
            .prefix { $0 != .foldSectionTails }
            .reduce(original) { $0.compacted(by: $1) }
        let allocation = try #require(compacted.sections.first { $0.id == "allocation" })
        let income = try #require(compacted.sections.first { $0.id == "income" })
        let bigMovers = try #require(compacted.sections.first { $0.id == "bigMovers" })

        let details = try #require(allocation.rows.first { $0.role == .portfolioOverviewDetails })
        #expect(details.children.first?.barChart != nil)
        #expect(allocation.rows.last?.title == "2 more attention items")
        #expect(allocation.rows.last?.children.map(\.role) == [.allocationDrillDown, .allocationDrillDown])
        #expect(income.rows.map(\.role) == [.incomeSummary])
        #expect(income.rows[0].children.count == 4)
        #expect(bigMovers.title.isEmpty)
        #expect(bigMovers.rows.map(\.title) == ["Big movers"])
        #expect(bigMovers.rows[0].children.map(\.role) == [.bigMoverSummary])
    }

    @Test("The last resort leaves one row per section and keeps Actions, so a 640 pt Larger Text screen still shows Quit")
    func lastResortKeepsActions() throws {
        let original = try refreshFailureSurface("worst-case-height.json")
        let collapsed = MenuOverflowStep.allCases.reduce(original) { $0.compacted(by: $1) }
        let pulse = try #require(collapsed.sections.first { $0.id == "pulse" })

        #expect(pulse.title.isEmpty)
        #expect(pulse.rows.map(\.title) == ["Pulse"])
        #expect(pulse.rows[0].detail == "Orbit Communications moved +25.0%")
        #expect(collapsed.sections.filter { $0.id != "actions" }.allSatisfy { $0.title.isEmpty })
        #expect(estimatedHeight(collapsed) <= 640 - 8)
        #expect(collapsed.sections.first { $0.id == "actions" } == original.sections.first { $0.id == "actions" })
    }

    private func surface(_ fixture: String) throws -> MenuBarSurface {
        MenuBarSurfaceRenderer.render(descriptor: try descriptor(fixture))
    }

    private func refreshFailureSurface(_ fixture: String) throws -> MenuBarSurface {
        MenuBarSurfaceRenderer.render(
            descriptor: PDTLaunchMenu.descriptorForBackgroundRefreshFailure(cachedPulse: try descriptor(fixture))
        )
    }

    private func descriptor(_ fixture: String) throws -> MenuDescriptor {
        let snapshot = try PDTFixtureDataSource.snapshot(
            from: overflowPackageRoot.appending(path: "docs/pdt/fixtures/\(fixture)")
        )
        var model = PressureEngine.buildModel(from: snapshot)
        // Render as the fixture-mode app does: a pulse fetched this session.
        model.facetSnapshots.dataHealth = DataHealth.build(
            .default(freshness: model.facetSnapshots.freshness, pulseSource: .fetchedSnapshot, snapshotAsOf: snapshot.asOf)
        )
        return MenuDescriptorRenderer.render(model: model)
    }
}

private func rowIDs(_ surface: MenuBarSurface) -> Set<String> {
    func ids(_ row: MenuBarRowSurface) -> [String] { [row.id] + row.children.flatMap(ids) }
    return Set(surface.sections.flatMap { $0.rows.flatMap(ids) })
}

/// Row heights PDTBar's real menu draws at the default text size, read from `menu-measure` captures.
private func estimatedHeight(_ surface: MenuBarSurface) -> Double {
    let menuPadding = 10.0, heading = 28.0, separator = 11.0, quit = 24.0
    return menuPadding + quit + surface.sections.reduce(0) { total, section in
        total + (section.showsHeading ? heading : 0) + separator + section.rows.map(estimatedHeight).reduce(0, +)
    }
}

private func estimatedHeight(_ row: MenuBarRowSurface) -> Double {
    if let summary = row.portfolioSummary { return summary.showsPerformance ? 86 : 46 }
    if row.barChart != nil { return row.detail?.isEmpty == false ? 138 : 124 }
    let actionable: Set<MenuRowRole> = [.fetchRetry, .openPDT, .settings, .connectionDisconnect]
    if row.children.isEmpty, !actionable.contains(row.role) {
        return row.detail == nil ? 30 : 42
    }
    guard let detail = row.detail else { return 24 }
    // A native subtitle wraps to a second line past about 48 characters at 400 pt.
    return detail.count > 48 ? 50 : 36
}

private let overflowPackageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
