import Foundation
import Testing
import PDTBarCore
import PDTBarAppSupport

@Suite("Portfolio performance summary")
struct PortfolioSummaryTests {
    @Test("Performance summary keeps direct total return separate from derived CAGR")
    func performanceSummarySeparatesReturnAndCAGR() throws {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: 0.21,
            periodStart: "2024-01-01",
            periodEnd: "2026-01-01"
        )

        #expect(summary.totalPercentageIncrease == 0.21)
        #expect(abs(try #require(summary.cagr) - 0.10) < 0.0001)
        #expect(summary.periodStart == "2024-01-01")
        #expect(summary.periodEnd == "2026-01-01")
    }

    @Test(arguments: [
        (0.21, nil, "2026-01-01"),
        (0.21, "bad-date", "2026-01-01"),
        (0.21, "2026-01-01", "2025-01-01"),
        (-1.01, "2025-01-01", "2026-01-01"),
    ] as [(Double, String?, String?)])
    func incompleteOrInvalidPeriodsNeverFabricateCAGR(_ total: Double, _ start: String?, _ end: String?) {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: total,
            periodStart: start,
            periodEnd: end
        )

        #expect(summary.totalPercentageIncrease == total)
        #expect(summary.cagr == nil)
    }

    @Test("Exact total loss annualizes to negative one hundred percent")
    func exactTotalLossAnnualizes() {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: -1,
            periodStart: "2025-01-01",
            periodEnd: "2026-01-01"
        )

        #expect(summary.cagr == -1)
    }

    @Test(arguments: [0.25, -0.25, 0.0])
    func summaryFormatsPositiveNegativeAndZeroReturns(_ value: Double) throws {
        var snapshot = try quietSnapshotForSummary()
        snapshot.performance = PortfolioPerformanceSummary(
            totalPercentageIncrease: value,
            cagr: value,
            periodStart: "2025-01-01",
            periodEnd: "2026-01-01"
        )

        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
        let summary = try #require(descriptor.sections.first?.rows.first?.portfolioSummary)
        let expected = value > 0 ? "+25.0%" : (value < 0 ? "-25.0%" : "0.0%")

        #expect(summary.cagr == expected)
        #expect(summary.totalIncrease == expected)
    }

    @Test("Summary is above overview and owns all three portfolio metrics")
    func summaryPrecedesOverviewWithoutDuplicates() throws {
        var snapshot = try quietSnapshotForSummary()
        snapshot.performance = PortfolioPerformanceSummary(
            totalPercentageIncrease: 0.21,
            cagr: 0.10,
            periodStart: "2024-01-01",
            periodEnd: "2026-01-01"
        )
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))

        #expect(descriptor.sections.map(\.id).prefix(2) == ["summary", "pulse"])
        #expect(descriptor.sections.first?.rows.map(\.id) == ["summary.performance"])
        let allRows = descriptor.sections.flatMap(\.rows).flatMap(flatten)
        #expect(allRows.filter { $0.id == "summary.performance" }.count == 1)
        #expect(allRows.contains { $0.id == "pulse.quiet.value" } == false)
        #expect(descriptor.statusTitle.contains("51,200") == false)
        #expect(descriptor.sections.firstIndex { $0.id == "summary" }! < descriptor.sections.firstIndex { $0.id == "allocation" }!)
    }

    @Test("Missing performance data stays explicitly unavailable")
    func missingPerformanceIsUnavailable() throws {
        var snapshot = try quietSnapshotForSummary()
        snapshot.performance = nil
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
        let row = try #require(descriptor.sections.first?.rows.first)
        let summary = try #require(row.portfolioSummary)

        #expect(summary.totalValue == "EUR 51,200.00")
        #expect(summary.cagr == "Unavailable")
        #expect(summary.totalIncrease == "Unavailable")
        #expect(summary.accessibilityLabel == "Total portfolio value, EUR 51,200.00; CAGR, Unavailable; Total increase, Unavailable")
        #expect(!row.accessibilityIdentifier.isEmpty)
    }

    @Test("Grid keeps columns in compact and larger menus and stacks for large text")
    func gridAdaptsWithoutOverlap() {
        #expect(PortfolioSummaryGridLayout(width: 280).mode == .columns)
        #expect(PortfolioSummaryGridLayout(width: 400).mode == .columns)
        #expect(PortfolioSummaryGridLayout(width: 280, textScale: 1.6).mode == .stacked)
        #expect(PortfolioSummaryGridLayout(width: 400).rowHeight < PortfolioSummaryGridLayout(width: 280, textScale: 1.6).rowHeight)
    }
}

private func flatten(_ row: MenuRow) -> [MenuRow] {
    [row] + row.children.flatMap(flatten)
}

private func quietSnapshotForSummary() throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(
        from: summaryPackageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    )
}

private let summaryPackageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
