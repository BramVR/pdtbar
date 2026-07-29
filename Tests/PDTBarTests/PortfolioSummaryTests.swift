import Foundation
import Testing
import PDTBarCore
import PDTBarAppSupport

@Suite("Portfolio performance summary")
struct PortfolioSummaryTests {
    @Test("Performance summary annualizes PDT's selected full-period return")
    func performanceSummaryCalculatesCAGR() throws {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: 0.4641,
            periodStart: "2020-01-01",
            periodEnd: "2024-01-01"
        )

        #expect(summary.totalPercentageIncrease == 0.4641)
        #expect(abs(try #require(summary.cagr) - 0.10) < 0.000_000_1)
        #expect(summary.periodStart == "2020-01-01")
        #expect(summary.periodEnd == "2024-01-01")
    }

    @Test(arguments: [
        (0.21, nil, "2026-01-01"),
        (0.21, "bad-date", "2026-01-01"),
        (0.21, "2026-01-01", "2024-01-01"),
        (0.21, "2026-01-01", "2026-01-01"),
        (0.05, "2026-01-01", "2026-01-02"),
        (0.05, "2026-01-01", "2026-01-31"),
        (0.05, "2026-01-01", "2026-03-31"),
        (-1.01, "2025-01-01", "2026-01-01"),
    ] as [(Double, String?, String?)])
    func invalidInputsKeepCAGRUnavailable(_ total: Double, _ start: String?, _ end: String?) {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: total,
            periodStart: start,
            periodEnd: end
        )

        #expect(summary.totalPercentageIncrease == total)
        #expect(summary.cagr == nil)
    }

    @Test("Exact total loss annualizes to an exact total loss")
    func exactTotalLossAnnualizes() {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: -1,
            periodStart: "2025-01-01",
            periodEnd: "2026-01-01"
        )

        #expect(summary.totalPercentageIncrease == -1)
        #expect(summary.cagr == -1)
    }

    @Test("A period just over one quarter annualizes")
    func periodJustOverThresholdAnnualizes() throws {
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: 0.05,
            periodStart: "2026-01-01",
            periodEnd: "2026-04-02"
        )

        #expect(try #require(summary.cagr).isFinite)
    }

    @Test("A 365-day CAGR approximately matches the total return")
    func oneYearCAGRApproximatelyMatchesTotalReturn() throws {
        let totalReturn = 0.21
        let summary = PortfolioPerformanceSummary.build(
            totalGainPercentage: totalReturn,
            periodStart: "2025-01-01",
            periodEnd: "2026-01-01"
        )

        #expect(abs(try #require(summary.cagr) - totalReturn) < 0.000_2)
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

    @Test("Short performance periods explain unavailable CAGR with values shown or hidden")
    func shortPerformancePeriodExplainsUnavailableCAGR() throws {
        var snapshot = try quietSnapshotForSummary()
        snapshot.performance = PortfolioPerformanceSummary.build(
            totalGainPercentage: 0.05,
            periodStart: "2026-01-01",
            periodEnd: "2026-01-31"
        )

        let model = PressureEngine.buildModel(from: snapshot)
        let shown = try #require(
            MenuDescriptorRenderer.render(model: model).sections.first?.rows.first?.portfolioSummary
        )
        let hidden = try #require(
            MenuDescriptorRenderer.render(
                model: model,
                settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
            ).sections.first?.rows.first?.portfolioSummary
        )

        #expect(shown.cagr == "Too short to annualize")
        #expect(shown.totalIncrease == "+5.0%")
        #expect(shown.accessibilityLabel.contains("CAGR, Too short to annualize"))
        #expect(hidden.totalValue == PortfolioValueDisplaySettings.hiddenPlaceholder)
        #expect(hidden.cagr == "Too short to annualize")
        #expect(hidden.totalIncrease == "+5.0%")
        #expect(hidden.accessibilityLabel.contains("CAGR, Too short to annualize"))
    }

    @Test("Grid supplies exact two-column widths and grows for larger system text")
    func gridAdaptsWithoutOverlap() {
        let compact = PortfolioSummaryGridLayout(width: 280)
        let production = PortfolioSummaryGridLayout(width: 400)
        let largerText = PortfolioSummaryGridLayout(width: 280, systemFontSize: 20.8)

        #expect(compact.columnWidth == 120)
        #expect(production.columnWidth == 180)
        #expect(compact.columnWidth * 2 + PortfolioSummaryGridLayout.columnGap + PortfolioSummaryGridLayout.horizontalPadding * 2 == compact.width)
        #expect(production.columnWidth * 2 + PortfolioSummaryGridLayout.columnGap + PortfolioSummaryGridLayout.horizontalPadding * 2 == production.width)
        #expect(largerText.columnWidth == compact.columnWidth)
        #expect(production.rowHeight < largerText.rowHeight)
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
