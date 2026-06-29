import Foundation
import Testing
import PDTBarCore

@Suite("Big-mover pressure")
struct BigMoverPressureTests {
    @Test("Cold-start price history emits big-mover pressure")
    func coldStartPriceHistoryEmitsBigMoverPressure() throws {
        let model = try model("big-mover")
        let item = try #require(model.rankedAttentionItems.first { $0.id == "bigMovers.move.9001" })

        #expect(!model.allQuiet)
        #expect(item.holdingIdentity?.name == "Nova Lithography")
        #expect(item.holdingIdentity?.quoteId == 9001)
        #expect(item.beforeValue == 545.00)
        #expect(item.afterValue == 612.40)
        #expect(item.moveSize == 0.1237)
        #expect(item.supportingDataSlotIDs == ["bigMovers.prices"])
        #expect(item.explanation.supportingSourceSlots.map(\.id) == ["bigMovers.prices"])
    }

    @Test("Big-mover summary renders holding name instead of raw quote id")
    func bigMoverSummaryRendersHoldingNameInsteadOfRawQuoteID() throws {
        let descriptor = MenuDescriptorRenderer.render(model: try model("big-mover"))
        let row = try #require(
            descriptor.sections
                .first { $0.id == "bigMovers" }?
                .rows
                .first { $0.id == "bigMovers.summary" }
        )

        #expect(row.title == "Nova Lithography")
    }

    @Test("Cold-start price history thresholds on exact move before rounding")
    func coldStartPriceHistoryThresholdsOnExactMoveBeforeRounding() throws {
        var snapshot = try snapshot("big-mover")
        snapshot.priceSeries = try priceSeries("""
        [
          { "quoteId": 9001, "date": "2026-06-15", "closeAdjusted": "100.00" },
          { "quoteId": 9001, "date": "2026-06-19", "closeAdjusted": "109.995" }
        ]
        """)

        let model = PressureEngine.buildModel(from: snapshot)

        #expect(!model.rankedAttentionItems.contains { $0.id == "bigMovers.move.9001" })
    }

    @Test("Cold-start price history uses price row currency")
    func coldStartPriceHistoryUsesPriceRowCurrency() throws {
        var snapshot = try snapshot("big-mover")
        snapshot.openHoldings[0].price = Money(value: "999.00", currency: "EUR")
        snapshot.priceSeries = try priceSeries("""
        [
          { "quoteId": 9001, "date": "2026-06-15", "closeAdjusted": "100.00", "closeCurrency": "USD" },
          { "quoteId": 9001, "date": "2026-06-19", "closeAdjusted": "112.00", "closeCurrency": "USD" }
        ]
        """)

        let item = try #require(
            PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first { $0.id == "bigMovers.move.9001" }
        )

        #expect(item.valueCurrency == "USD")
        #expect(item.explanation.currentValue?.value == "USD 112.00")
        #expect(item.explanation.priorValue?.value == "USD 100.00")
    }

    @Test("Cold-start price history emits without current holding price")
    func coldStartPriceHistoryEmitsWithoutCurrentHoldingPrice() throws {
        var snapshot = try snapshot("big-mover")
        snapshot.openHoldings[0].price = nil
        snapshot.priceSeries = try priceSeries("""
        [
          { "quoteId": 9001, "date": "2026-06-15", "closeAdjusted": "100.00", "closeCurrency": "USD" },
          { "quoteId": 9001, "date": "2026-06-19", "closeAdjusted": "112.00", "closeCurrency": "USD" }
        ]
        """)

        let item = try #require(
            PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first { $0.id == "bigMovers.move.9001" }
        )

        #expect(item.valueCurrency == "USD")
        #expect(item.beforeValue == 100.00)
        #expect(item.afterValue == 112.00)
        #expect(item.supportingDataSlotIDs == ["bigMovers.prices"])
    }

    @Test("Same-day price history tie break uses numeric close")
    func sameDayPriceHistoryTieBreakUsesNumericClose() throws {
        var snapshot = try snapshot("big-mover")
        snapshot.priceSeries = try priceSeries("""
        [
          { "quoteId": 9001, "date": "2026-06-15", "closeAdjusted": "10.00" },
          { "quoteId": 9001, "date": "2026-06-15", "closeAdjusted": "9.00" },
          { "quoteId": 9001, "date": "2026-06-19", "closeAdjusted": "11.00" }
        ]
        """)

        let item = try #require(
            PressureEngine.buildModel(from: snapshot).rankedAttentionItems.first { $0.id == "bigMovers.move.9001" }
        )

        #expect(item.beforeValue == 9.00)
        #expect(item.afterValue == 11.00)
        #expect(item.moveSize == 0.2222)
    }

    @Test("Seeded prior snapshot still emits big-mover pressure")
    func seededPriorSnapshotStillEmitsBigMoverPressure() throws {
        let model = try model("big-mover", withPrior: true)
        let item = try #require(model.rankedAttentionItems.first { $0.id == "bigMovers.move.9001" })

        #expect(item.detail == "Nova Lithography moved +12.4% from EUR 545.00 to EUR 612.40 while portfolio weight changed 9.4% -> 11.6%.")
        #expect(item.beforeWeight == 0.0942)
        #expect(item.afterWeight == 0.1158)
        #expect(item.supportingDataSlotIDs == ["bigMovers.priorSnapshot", "bigMovers.prices"])
    }

    @Test("Prior snapshot and price history do not duplicate the same move")
    func priorSnapshotAndPriceHistoryDoNotDuplicateTheSameMove() throws {
        let model = try model("big-mover", withPrior: true)
        let bigMoverItems = model.rankedAttentionItems.filter { $0.id == "bigMovers.move.9001" }

        #expect(bigMoverItems.count == 1)
    }

    @Test("Prior-present below-threshold move ignores fallback price history pressure")
    func priorPresentBelowThresholdMoveIgnoresFallbackPriceHistoryPressure() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
        var snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let prior = try PDTFixtureDataSource.priorSnapshot(from: fixture)
        snapshot.openHoldings[0].price = prior.openHoldings[0].price

        let model = PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)

        #expect(!model.rankedAttentionItems.contains { $0.id == "bigMovers.move.9001" })
    }

    @Test("Prior snapshot missing a quote uses price history pressure")
    func priorSnapshotMissingQuoteUsesPriceHistoryPressure() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        var prior = try PDTFixtureDataSource.priorSnapshot(from: fixture)
        prior.openHoldings.removeAll { $0.quoteId == 9001 }

        let item = try #require(
            PressureEngine.buildModel(from: snapshot, priorSnapshot: prior).rankedAttentionItems.first { $0.id == "bigMovers.move.9001" }
        )

        #expect(item.beforeWeight == nil)
        #expect(item.supportingDataSlotIDs == ["bigMovers.prices"])
    }

    @Test("Prior snapshot with unusable price uses price history pressure")
    func priorSnapshotWithUnusablePriceUsesPriceHistoryPressure() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        var prior = try PDTFixtureDataSource.priorSnapshot(from: fixture)
        prior.openHoldings[0].price = nil

        let item = try #require(
            PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
                .rankedAttentionItems
                .first { $0.id == "bigMovers.move.9001" }
        )

        #expect(item.beforeWeight == nil)
        #expect(item.supportingDataSlotIDs == ["bigMovers.prices"])
    }

    @Test("All-quiet fixture remains quiet")
    func allQuietFixtureRemainsQuiet() throws {
        let model = try model("quiet-no-pressure")

        #expect(model.allQuiet)
        #expect(model.rankedAttentionItems.isEmpty)
    }

    private func model(_ fixtureName: String, withPrior: Bool = false) throws -> PortfolioPulseModel {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        let snapshot = try snapshot(fixtureName)
        let prior = withPrior ? try? PDTFixtureDataSource.priorSnapshot(from: fixture) : nil
        return PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
    }

    private func snapshot(_ fixtureName: String) throws -> PortfolioSnapshot {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        return try PDTFixtureDataSource.snapshot(from: fixture)
    }

    private func priceSeries(_ json: String) throws -> [PricePoint] {
        try JSONDecoder().decode([PricePoint].self, from: Data(json.utf8))
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
