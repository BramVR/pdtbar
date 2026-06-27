import Foundation
import Testing
import PDTBarCore

@Suite("Attention explanations")
struct AttentionExplanationTests {
    @Test("Fixture attention items carry structured explanation facts")
    func fixtureAttentionItemsCarryStructuredExplanationFacts() throws {
        let concentration = try model("concentration-pressure")
        let income = try model("income-event")
        let bigMover = try model("big-mover", withPrior: true)

        let concentrationExplanation = try #require(concentration.rankedAttentionItems.first?.explanation)
        #expect(concentrationExplanation.trigger.value == "Concentration line crossed")
        #expect(concentrationExplanation.severity.value == "medium")
        #expect(concentrationExplanation.threshold?.value == "20.0%")
        #expect(concentrationExplanation.currentValue?.value == "24.2%")
        #expect(concentrationExplanation.priorValue == nil)
        #expect(concentrationExplanation.supportingSourceSlots.map(\.id) == ["allocation.holdings"])

        let incomeExplanation = try #require(income.rankedAttentionItems.first { $0.facet == "income" }?.explanation)
        #expect(incomeExplanation.trigger.value == "Ex-dividend date in income window")
        #expect(incomeExplanation.severity.value == "low")
        #expect(incomeExplanation.threshold?.value == "2026-06-22..2026-07-22")
        #expect(incomeExplanation.currentValue?.value == "2026-06-24")
        #expect(incomeExplanation.priorValue == nil)
        #expect(incomeExplanation.supportingSourceSlots.map(\.id) == ["income.calendar"])

        let bigMoverExplanation = try #require(bigMover.rankedAttentionItems.first?.explanation)
        #expect(bigMoverExplanation.trigger.value == "Price move crossed recent-window line")
        #expect(bigMoverExplanation.severity.value == "medium")
        #expect(bigMoverExplanation.threshold?.value == "10.0%")
        #expect(bigMoverExplanation.currentValue?.value == "EUR 612.40")
        #expect(bigMoverExplanation.priorValue?.value == "EUR 545.00")
        #expect(bigMoverExplanation.supportingSourceSlots.map(\.id) == [
            "bigMovers.priorSnapshot",
            "bigMovers.prices",
        ])
    }

    @Test("Descriptor renders explanation facts without facet-specific readout inference")
    func descriptorRendersExplanationFacts() throws {
        let descriptor = MenuDescriptorRenderer.render(model: try model("concentration-pressure"))
        let attentionChildren = try #require(
            descriptor.sections
                .first { $0.id == "pulse" }?
                .rows
                .first { $0.role == .pulseAttention }?
                .children
        )

        #expect(Array(attentionChildren.map(\.id).prefix(5)) == [
            "allocation.concentration.9001.trigger",
            "allocation.concentration.9001.severity",
            "allocation.concentration.9001.threshold",
            "allocation.concentration.9001.currentValue",
            "allocation.concentration.9001.sources",
        ])
        #expect(attentionChildren.first { $0.id.hasSuffix(".trigger") }?.title == "Trigger")
        #expect(attentionChildren.first { $0.id.hasSuffix(".trigger") }?.detail == "Concentration line crossed")
        #expect(attentionChildren.first { $0.id.hasSuffix(".threshold") }?.title == "Threshold")
        #expect(attentionChildren.first { $0.id.hasSuffix(".threshold") }?.detail == "20.0%")
        #expect(attentionChildren.first { $0.id.hasSuffix(".currentValue") }?.title == "Current")
        #expect(attentionChildren.first { $0.id.hasSuffix(".currentValue") }?.detail == "24.2%")
        #expect(attentionChildren.first { $0.id.hasSuffix(".sources") }?.detail == "Open holdings")
    }

    @Test("Legacy attention JSON synthesizes structured explanation facts")
    func legacyAttentionJSONSynthesizesStructuredExplanationFacts() throws {
        let concentration = try legacyItem("""
        {
          "id": "allocation.concentration.9001",
          "facet": "allocation",
          "rank": 1,
          "title": "Nova Lithography concentration",
          "severity": "medium",
          "score": 0.66,
          "currentWeight": 0.242,
          "threshold": 0.2,
          "supportingDataSlotIDs": ["allocation.holdings"]
        }
        """)
        #expect(concentration.explanation.threshold?.value == "20.0%")
        #expect(concentration.explanation.currentValue?.value == "24.2%")

        let bigMover = try legacyItem("""
        {
          "id": "bigMovers.move.9001",
          "facet": "bigMovers",
          "rank": 1,
          "title": "Nova Lithography moved +12.4%",
          "severity": "medium",
          "score": 0.62,
          "threshold": 0.1,
          "beforeValue": 545.0,
          "afterValue": 612.4,
          "moveSize": 0.124,
          "beforeWeight": 0.094,
          "afterWeight": 0.116,
          "valueCurrency": "EUR",
          "supportingDataSlotIDs": ["bigMovers.priorSnapshot", "bigMovers.prices"]
        }
        """)
        #expect(bigMover.explanation.threshold?.value == "10.0%")
        #expect(bigMover.explanation.currentValue?.value == "EUR 612.40")
        #expect(bigMover.explanation.priorValue?.value == "EUR 545.00")

        let income = try legacyItem("""
        {
          "id": "income.ex-dividend.9003",
          "facet": "income",
          "rank": 1,
          "title": "Helio Grid ex-dividend",
          "severity": "low",
          "score": 0.45,
          "eventDate": "2026-06-24",
          "amount": { "value": "78.00", "currency": "EUR" },
          "windowStart": "2026-06-22",
          "windowEnd": "2026-07-22",
          "supportingDataSlotIDs": ["income.calendar"]
        }
        """)
        #expect(income.explanation.threshold?.value == "2026-06-22..2026-07-22")
        #expect(income.explanation.currentValue?.value == "2026-06-24; EUR 78.00")
    }

    private func model(_ fixtureName: String, withPrior: Bool = false) throws -> PortfolioPulseModel {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let prior = withPrior ? try? PDTFixtureDataSource.priorSnapshot(from: fixture) : nil
        return PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
    }

    private func legacyItem(_ json: String) throws -> AttentionItem {
        try JSONDecoder().decode(AttentionItem.self, from: Data(json.utf8))
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
