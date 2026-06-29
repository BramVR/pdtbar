import Foundation
import AppKit
import Testing
import PDTBarCore
import PDTBarAppSupport

@Suite("Portfolio overview")
struct PortfolioOverviewTests {
    @Test("Module builds whole-portfolio overview from normalized facts")
    func moduleBuildsWholePortfolioOverview() throws {
        let overview = PortfolioOverview.build(from: try quietSnapshot())

        #expect(overview.totalValue == Money(value: "51200.00", currency: "EUR"))
        #expect(overview.openHoldingCount == 9)
        #expect(Array(overview.topHoldings.map(\.quoteId).prefix(3)) == [9001, 9002, 9003])
        #expect(overview.topHoldings.first?.isin == "NL0000000001")
        #expect(overview.topNConcentration == PortfolioTopNConcentrationSummary(rankCount: 3, weight: 0.34765625))
        #expect(overview.sectorSummary.first?.name == "information-technology")
        #expect(overview.sectorSummary.first?.percentage == 22.4609375)
        #expect(overview.assetTypeSummary.map(\.name).contains("common-stock"))
        #expect(overview.cashSummary == PortfolioCashSummary(
            value: Money(value: "1895.00", currency: "EUR"),
            weight: 0.03701172
        ))
    }

    @Test("Module omits absent or malformed optional overview facts")
    func moduleOmitsAbsentOrMalformedFacts() {
        let snapshot = PortfolioSnapshot(
            asOf: "2026-06-22",
            totalValue: Money(value: "1000.00", currency: "EUR"),
            openHoldings: [
                NormalizedHolding(
                    name: "Valid Holding",
                    quoteId: 1,
                    weight: 0.60,
                    worth: Money(value: "600.00", currency: "EUR"),
                    price: nil,
                    priceAsOf: "2026-06-22"
                ),
                NormalizedHolding(
                    name: "Broken Holding",
                    quoteId: 2,
                    weight: .nan,
                    worth: Money(value: "400.00", currency: "EUR"),
                    price: nil,
                    priceAsOf: "2026-06-22"
                ),
                NormalizedHolding(
                    name: "Overweight Holding",
                    quoteId: 3,
                    weight: 1.20,
                    worth: Money(value: "1200.00", currency: "EUR"),
                    price: nil,
                    priceAsOf: "2026-06-22"
                ),
            ],
            sectors: [
                DistributionSummary(
                    name: "valid-sector",
                    percentage: 60,
                    totalValue: Money(value: "600.00", currency: "EUR")
                ),
                DistributionSummary(
                    name: "bad-sector",
                    percentage: .infinity,
                    totalValue: Money(value: "400.00", currency: "EUR")
                ),
                DistributionSummary(
                    name: "overrange-sector",
                    percentage: 120,
                    totalValue: Money(value: "1200.00", currency: "EUR")
                ),
            ],
            assetTypes: [
                DistributionSummary(
                    name: "cash",
                    percentage: 150,
                    totalValue: Money(value: "1500.00", currency: "EUR")
                ),
            ],
            xRayHoldings: nil,
            incomeEvents: [],
            dividendRowCount: 0,
            priceSeries: []
        )

        let overview = PortfolioOverview.build(from: snapshot)

        #expect(overview.topHoldings.map(\.name) == ["Valid Holding"])
        #expect(overview.topNConcentration == PortfolioTopNConcentrationSummary(rankCount: 1, weight: 0.60))
        #expect(overview.sectorSummary.map(\.name) == ["valid-sector"])
        #expect(overview.assetTypeSummary.isEmpty)
        #expect(overview.cashSummary == nil)
    }

    @Test("Top-N concentration ranks public input before prefixing")
    func topNConcentrationRanksPublicInputBeforePrefixing() {
        let holdings = [
            HoldingSummary(
                name: "Small",
                quoteId: 3,
                weight: 0.10,
                worth: Money(value: "100.00", currency: "EUR"),
                price: nil
            ),
            HoldingSummary(
                name: "Large",
                quoteId: 1,
                weight: 0.50,
                worth: Money(value: "500.00", currency: "EUR"),
                price: nil
            ),
            HoldingSummary(
                name: "Medium",
                quoteId: 2,
                weight: 0.30,
                worth: Money(value: "300.00", currency: "EUR"),
                price: nil
            ),
        ]

        #expect(PortfolioOverview.topNConcentration(from: holdings, rankCount: 2) == PortfolioTopNConcentrationSummary(
            rankCount: 2,
            weight: 0.80
        ))
    }

    @Test("Pulse model carries structured portfolio overview")
    func pulseModelCarriesStructuredPortfolioOverview() throws {
        let model = PressureEngine.buildModel(from: try quietSnapshot())
        let overview = model.facetSnapshots.allocation.portfolioOverview

        #expect(overview.openHoldingCount == model.facetSnapshots.allocation.openHoldingCount)
        #expect(overview.topHoldings.first?.name == "Nova Lithography")
        #expect(overview.topNConcentration?.rankCount == 3)
        #expect(overview.cashSummary?.value == Money(value: "1895.00", currency: "EUR"))
    }

    @Test("Legacy model JSON defaults missing portfolio overview")
    func legacyModelJSONDefaultsMissingPortfolioOverview() throws {
        let model = PressureEngine.buildModel(from: try quietSnapshot())
        var object = try #require(JSONSerialization.jsonObject(with: try stableJSONData(model)) as? [String: Any])
        var facetSnapshots = try #require(object["facetSnapshots"] as? [String: Any])
        var allocation = try #require(facetSnapshots["allocation"] as? [String: Any])
        allocation.removeValue(forKey: "portfolioOverview")
        allocation["sectorBreakdown"] = [
            [
                "name": "low-sector",
                "percentage": 10.0,
                "totalValue": ["value": "100.00", "currency": "EUR"],
            ],
            [
                "name": "bad-sector",
                "percentage": 20.0,
                "totalValue": ["value": "not-money", "currency": "EUR"],
            ],
            [
                "name": "high-sector",
                "percentage": 30.0,
                "totalValue": ["value": "300.00", "currency": "EUR"],
            ],
        ]
        facetSnapshots["allocation"] = allocation
        object["facetSnapshots"] = facetSnapshots

        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: legacyData)
        let overview = decoded.facetSnapshots.allocation.portfolioOverview

        #expect(overview.openHoldingCount == 9)
        #expect(overview.topNConcentration == PortfolioTopNConcentrationSummary(rankCount: 3, weight: 0.34765625))
        #expect(overview.sectorSummary.map(\.name) == ["high-sector", "low-sector"])
        #expect(overview.cashSummary?.value == Money(value: "1895.00", currency: "EUR"))
    }

    @Test("Descriptor renders portfolio chart before detailed allocation info")
    func descriptorRendersPortfolioChartBeforeDetailedAllocationInfo() throws {
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: try quietSnapshot()))
        let allocationRows = try #require(descriptor.sections.first { $0.id == "allocation" }?.rows)
        let chartRow = try #require(allocationRows.first)
        let detailsRow = try #require(allocationRows.dropFirst().first)

        #expect(chartRow.id == "allocation.portfolio")
        #expect(chartRow.role == .portfolioOverviewChart)
        #expect(chartRow.title == "Portfolio")
        #expect(chartRow.detail == nil)
        #expect(chartRow.children.isEmpty)
        #expect(detailsRow.id == "allocation.portfolio.details")
        #expect(detailsRow.role == .portfolioOverviewDetails)
        #expect(detailsRow.title == "Detailed info")
        #expect(detailsRow.children.map(\.id) == [
            "allocation.9001",
            "allocation.9002",
            "allocation.9003",
            "allocation.9009",
            "allocation.9011",
            "allocation.9005",
            "allocation.9004",
            "allocation.9012",
            "allocation.9010",
            "allocation.portfolio.sectors",
            "allocation.portfolio.assetTypes",
        ])
        #expect(detailsRow.children.contains { $0.id == "allocation.portfolio.holdings" } == false)
        #expect(detailsRow.children.contains { $0.id == "allocation.portfolio.concentration" } == false)
        #expect(detailsRow.children.contains { $0.id == "allocation.portfolio.cash" } == false)
        #expect(detailsRow.children.filter { $0.title == "Cash" }.map(\.id) == ["allocation.9010"])
        #expect(detailsRow.children.suffix(2).allSatisfy { !$0.children.isEmpty })
    }

    @Test("Portfolio allocation chart carries holding bars and detailed info drills into holdings")
    func portfolioAllocationChartCarriesHoldingBarsAndDetailedInfoDrillsIntoHoldings() throws {
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: try quietSnapshot()))
        let allocationRows = try #require(descriptor.sections.first { $0.id == "allocation" }?.rows)
        let chartRow = try #require(allocationRows.first)
        let chart = try #require(chartRow.barChart)

        #expect(chart.bars.map(\.id) == [
            "allocation.portfolio.chart.9001",
            "allocation.portfolio.chart.9002",
            "allocation.portfolio.chart.9003",
            "allocation.portfolio.chart.9009",
            "allocation.portfolio.chart.9011",
            "allocation.portfolio.chart.9005",
            "allocation.portfolio.chart.9004",
            "allocation.portfolio.chart.9012",
            "allocation.portfolio.chart.9010",
        ])
        #expect(chart.bars.map(\.label) == [
            "Nova",
            "Orbit",
            "Helix",
            "Atlas",
            "Axis",
            "Caldera",
            "Meridian",
            "Zephyr",
            "Cash",
        ])
        #expect(chart.bars.map(\.axisLabel) == ["N", "O", "H", "A", "A", "C", "M", "Z", "C"])
        #expect(chart.bars.map(\.weight) == [
            0.1171875,
            0.1171875,
            0.11328125,
            0.10742188,
            0.10742188,
            0.10552734,
            0.10160156,
            0.09570313,
            0.03701172,
        ])
        #expect(chart.bars.map(\.percentageLabel) == [
            "11.7%",
            "11.7%",
            "11.3%",
            "10.7%",
            "10.7%",
            "10.6%",
            "10.2%",
            "9.6%",
            "3.7%",
        ])
        #expect(chart.bars.first?.detail == "Nova Lithography 11.7%; EUR 6,000.00")

        let detailsRow = try #require(allocationRows.first { $0.id == "allocation.portfolio.details" })
        let novaRow = try #require(detailsRow.children.first { $0.id == "allocation.9001" })
        #expect(novaRow.id == "allocation.9001")
        #expect(novaRow.role == .allocationHolding)
        #expect(novaRow.children.map(\.id).contains("allocation.9001.worth"))
        #expect(novaRow.children.map(\.id).contains("allocation.9001.price"))
        #expect(novaRow.children.first { $0.id == "allocation.9001.isin" }?.detail == "NL0000000001")

        let cashRow = try #require(detailsRow.children.first { $0.id == "allocation.9010" })
        #expect(cashRow.children.contains { $0.id == "allocation.9010.isin" } == false)

        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let surfaceOverviewRow = try #require(surface.sections.first { $0.id == "allocation" }?.rows.first)
        #expect(surfaceOverviewRow.barChart == chart)
    }

    @Test("Portfolio allocation chart includes every positive holding in a many-holding portfolio")
    func portfolioAllocationChartIncludesEveryPositiveHoldingInManyHoldingPortfolio() throws {
        let snapshot = try manyPositiveHoldingsSnapshot()
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
        let allocationRows = try #require(descriptor.sections.first { $0.id == "allocation" }?.rows)
        let chart = try #require(allocationRows.first?.barChart)

        #expect(chart.bars.count == 20)
        #expect(chart.bars.map(\.id) == snapshot.openHoldings
            .sorted { $0.weight == $1.weight ? $0.name < $1.name : $0.weight > $1.weight }
            .map { "allocation.portfolio.chart.\($0.quoteId)" })
        #expect(chart.bars.allSatisfy { $0.weight > 0 })
        #expect(chart.bars.last?.percentageLabel == "0.1%")
    }

    @Test("Portfolio allocation layout keeps twenty labels aligned and tiny positive bars visible")
    func portfolioAllocationLayoutKeepsTwentyLabelsAlignedAndTinyPositiveBarsVisible() {
        let weights = [
            0.18, 0.15, 0.12, 0.10, 0.08,
            0.07, 0.06, 0.05, 0.04, 0.03,
            0.025, 0.020, 0.015, 0.010, 0.008,
            0.006, 0.004, 0.002, 0.0015, 0.001,
        ]
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: 280,
            height: PortfolioAllocationChartLayout.chartHeight
        )
        let layout = PortfolioAllocationChartLayout(bounds: bounds, weights: weights)

        #expect(PortfolioAllocationChartLayout.contentWidth(viewportWidth: 280, barCount: weights.count) == 280)
        #expect(PortfolioAllocationChartLayout.barCornerRadius == 2)
        #expect(layout.totalSlotCount == 30)
        #expect(layout.leadingSlotCount == 5)

        for index in weights.indices {
            let barRect = layout.barRect(at: index)
            let labelRect = layout.labelRect(at: index, axisHeight: 16)

            #expect(abs(barRect.midX - labelRect.midX) < 0.001)
            #expect(barRect.height >= PortfolioAllocationChartLayout.minimumPositiveBarHeight)
            #expect(barRect.width >= 6)
            #expect(barRect.width < 10)
        }
    }

    @Test("Portfolio allocation layout centers sparse charts and scrolls dense charts")
    func portfolioAllocationLayoutCentersSparseChartsAndScrollsDenseCharts() {
        let twoBarLayout = PortfolioAllocationChartLayout(
            bounds: NSRect(x: 0, y: 0, width: 280, height: PortfolioAllocationChartLayout.chartHeight),
            weights: [0.60, 0.40]
        )
        #expect(PortfolioAllocationChartLayout.contentWidth(viewportWidth: 280, barCount: 2) == 280)
        #expect(twoBarLayout.totalSlotCount == 30)
        #expect(twoBarLayout.leadingSlotCount == 14)
        #expect(twoBarLayout.barRect(at: 0).midX < twoBarLayout.barRect(at: 1).midX)

        let manyWeights = Array(repeating: 0.02, count: 45)
        let denseContentWidth = PortfolioAllocationChartLayout.contentWidth(
            viewportWidth: 280,
            barCount: manyWeights.count
        )
        let denseLayout = PortfolioAllocationChartLayout(
            bounds: NSRect(x: 0, y: 0, width: denseContentWidth, height: PortfolioAllocationChartLayout.chartHeight),
            weights: manyWeights
        )
        #expect(denseContentWidth == 420)
        #expect(denseLayout.totalSlotCount == 45)
        #expect(denseLayout.leadingSlotCount == 0)
        #expect(denseLayout.barRect(at: 0).midX < denseLayout.barRect(at: 44).midX)
    }
}

private func quietSnapshot() throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json"))
}

private func manyPositiveHoldingsSnapshot() throws -> PortfolioSnapshot {
    var snapshot = try quietSnapshot()
    let seedHoldings = try #require(!snapshot.openHoldings.isEmpty ? snapshot.openHoldings : nil)
    let weights = [
        0.18, 0.15, 0.12, 0.10, 0.08,
        0.07, 0.06, 0.05, 0.04, 0.03,
        0.025, 0.020, 0.015, 0.010, 0.008,
        0.006, 0.004, 0.002, 0.0015, 0.001,
    ]
    snapshot.openHoldings = weights.enumerated().map { index, weight in
        var holding = seedHoldings[index % seedHoldings.count]
        holding.name = String(format: "Synthetic Holding %02d", index + 1)
        holding.quoteId = 9100 + index
        holding.weight = weight
        holding.worth = Money(value: String(format: "%.2f", weight * 100_000), currency: "EUR")
        holding.copyableIdentifier = "synthetic-holding-\(index + 1)"
        return holding
    }
    return snapshot
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
