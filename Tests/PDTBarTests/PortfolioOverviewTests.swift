import Foundation
import Testing
import PDTBarCore

@Suite("Portfolio overview")
struct PortfolioOverviewTests {
    @Test("Module builds whole-portfolio overview from normalized facts")
    func moduleBuildsWholePortfolioOverview() throws {
        let overview = PortfolioOverview.build(from: try quietSnapshot())

        #expect(overview.totalValue == Money(value: "51200.00", currency: "EUR"))
        #expect(overview.openHoldingCount == 9)
        #expect(Array(overview.topHoldings.map(\.quoteId).prefix(3)) == [9001, 9002, 9003])
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
            ],
            assetTypes: [],
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

    @Test("Descriptor renders portfolio allocation row before holdings")
    func descriptorRendersPortfolioAllocationRowBeforeHoldings() throws {
        let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: try quietSnapshot()))
        let allocationRows = try #require(descriptor.sections.first { $0.id == "allocation" }?.rows)
        let overviewRow = try #require(allocationRows.first)

        #expect(overviewRow.id == "allocation.portfolio")
        #expect(overviewRow.role == .portfolioOverview)
        #expect(overviewRow.title == "Portfolio allocation")
        #expect(allocationRows.dropFirst().first?.id == "allocation.9001")
        #expect(overviewRow.children.map(\.id) == [
            "allocation.portfolio.holdings",
            "allocation.portfolio.concentration",
            "allocation.portfolio.sectors",
            "allocation.portfolio.assetTypes",
            "allocation.portfolio.cash",
        ])
    }
}

private func quietSnapshot() throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json"))
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
