import Foundation
import Testing
import PDTBarCore

@Suite("Allocation pressure")
struct AllocationPressureTests {
    @Test("Sector concentration crosses deterministic threshold with explanation facts")
    func sectorConcentrationCrossesThreshold() throws {
        let model = PressureEngine.buildModel(from: try fixtureSnapshot("concentration-pressure.json"))
        let item = try #require(model.rankedAttentionItems.first { $0.id == "allocation.sector.information-technology" })

        #expect(item.title == "Information Technology sector concentration")
        #expect(item.detail == "30.9%")
        #expect(item.explanation.trigger.value == "Sector concentration line crossed")
        #expect(item.explanation.threshold?.value == "30.0%")
        #expect(item.explanation.currentValue?.value == "30.9%")
        #expect(item.explanation.supportingSourceSlots.map(\.id) == ["allocation.sectors"])
        #expect(model.facetSnapshots.allocation.allocationPressureItems.map(\.id).contains(item.id))
    }

    @Test("Cash drag surfaces only when cash data is present and crosses threshold")
    func cashDragSurfacesOnlyWithPresentHighCash() throws {
        var snapshot = try fixtureSnapshot("quiet-no-pressure.json")
        snapshot.openHoldings[snapshot.openHoldings.count - 1].weight = 0.12
        snapshot.openHoldings[snapshot.openHoldings.count - 1].worth = Money(value: "6144.00", currency: "EUR")
        snapshot.assetTypes = [
            DistributionSummary(
                name: "cash",
                percentage: 12.0,
                totalValue: Money(value: "6144.00", currency: "EUR")
            ),
        ]

        let highCash = PressureEngine.buildModel(from: snapshot)
        let item = try #require(highCash.rankedAttentionItems.first { $0.id == "allocation.cashDrag" })
        #expect(item.title == "Cash drag")
        #expect(item.detail == "12.0%; EUR 6,144.00")
        #expect(item.explanation.trigger.value == "Cash allocation line crossed")
        #expect(item.explanation.threshold?.value == "10.0%")
        #expect(item.explanation.currentValue?.value == "12.0%; EUR 6,144.00")
        #expect(item.explanation.supportingSourceSlots.map(\.id) == ["allocation.overview"])

        snapshot.openHoldings.removeLast()
        snapshot.assetTypes = []
        let missingCash = PressureEngine.buildModel(from: snapshot)
        #expect(!missingCash.rankedAttentionItems.contains { $0.id == "allocation.cashDrag" })
    }

    @Test("Top concentration drift uses previous complete snapshot when available")
    func concentrationDriftUsesPreviousCompleteSnapshot() {
        let current = driftSnapshot(weights: [0.20, 0.15, 0.10])
        let prior = driftSnapshot(weights: [0.18, 0.12, 0.08], asOf: "2026-06-21")
        let model = PressureEngine.buildModel(from: current, priorSnapshot: prior)
        let item = model.rankedAttentionItems.first { $0.id == "allocation.concentrationDrift.top3" }

        #expect(item?.title == "Top 3 concentration drift")
        #expect(item?.detail == "38.0% -> 45.0%")
        #expect(item?.explanation.trigger.value == "Top concentration drift crossed")
        #expect(item?.explanation.threshold?.value == "5.0%")
        #expect(item?.explanation.currentValue?.value == "45.0%")
        #expect(item?.explanation.priorValue?.value == "38.0%")
        #expect(item?.explanation.supportingSourceSlots.map(\.id) == [
            "allocation.overview",
            "allocation.priorSnapshot",
        ])
    }

    @Test("Allocation pressure stays quiet for below-threshold and missing-data cases")
    func allocationPressureQuietCases() {
        let quietSector = PortfolioSnapshot(
            asOf: "2026-06-22",
            totalValue: Money(value: "1000.00", currency: "EUR"),
            openHoldings: [
                holding("A", quoteId: 1, weight: 0.12),
                holding("B", quoteId: 2, weight: 0.11),
            ],
            sectors: [
                DistributionSummary(
                    name: "technology",
                    percentage: 29.9,
                    totalValue: Money(value: "299.00", currency: "EUR")
                ),
            ],
            assetTypes: [
                DistributionSummary(
                    name: "cash",
                    percentage: 9.9,
                    totalValue: Money(value: "99.00", currency: "EUR")
                ),
            ],
            incomeEvents: [],
            dividendRowCount: 0,
            priceSeries: []
        )
        let quiet = PressureEngine.buildModel(from: quietSector)
        #expect(quiet.rankedAttentionItems.isEmpty)
        #expect(quiet.facetSnapshots.allocation.allocationPressureItems.isEmpty)

        let driftBelowThreshold = PressureEngine.buildModel(
            from: driftSnapshot(weights: [0.20, 0.15, 0.10]),
            priorSnapshot: driftSnapshot(weights: [0.19, 0.13, 0.085], asOf: "2026-06-21")
        )
        #expect(!driftBelowThreshold.rankedAttentionItems.contains { $0.id == "allocation.concentrationDrift.top3" })

        let driftMissingPrior = PressureEngine.buildModel(from: driftSnapshot(weights: [0.20, 0.15, 0.10]))
        #expect(!driftMissingPrior.rankedAttentionItems.contains { $0.id == "allocation.concentrationDrift.top3" })
    }

    @Test("Descriptor places allocation pressure in Pulse and Allocation without hiding details")
    func descriptorPlacesAllocationPressureRows() throws {
        let model = PressureEngine.buildModel(from: try fixtureSnapshot("concentration-pressure.json"))
        let descriptor = MenuDescriptorRenderer.render(model: model)
        let pulseIDs = descriptor.sections.first { $0.id == "pulse" }?.rows.map(\.id) ?? []
        let allocationRows = try #require(descriptor.sections.first { $0.id == "allocation" }?.rows)
        let detailsRow = try #require(allocationRows.first { $0.id == "allocation.portfolio.details" })

        #expect(pulseIDs.contains("allocation.sector.information-technology.glance"))
        #expect(allocationRows.contains { $0.id == "allocation.sector.information-technology.allocation" })
        #expect(detailsRow.children.contains { $0.id == "allocation.portfolio.sectors" })
        #expect(detailsRow.children.contains { $0.id == "allocation.9001" })
    }
}

private func fixtureSnapshot(_ name: String) throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/\(name)"))
}

private func driftSnapshot(weights: [Double], asOf: String = "2026-06-22") -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: asOf,
        totalValue: Money(value: "1000.00", currency: "EUR"),
        openHoldings: weights.enumerated().map { offset, weight in
            holding("Holding \(offset + 1)", quoteId: offset + 1, weight: weight)
        },
        sectors: [],
        assetTypes: [],
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: []
    )
}

private func holding(_ name: String, quoteId: Int, weight: Double) -> NormalizedHolding {
    NormalizedHolding(
        name: name,
        quoteId: quoteId,
        weight: weight,
        worth: Money(value: String(format: "%.2f", weight * 1000), currency: "EUR"),
        price: nil,
        priceAsOf: "2026-06-22"
    )
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
