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

    @Test("Legacy facet and severity strings decode to typed safe vocabulary")
    func legacyFacetAndSeverityStringsDecodeToTypedSafeVocabulary() throws {
        let item = try legacyItem("""
        {
          "id": "legacy.typo.1",
          "facet": "allocaton",
          "rank": 1,
          "title": "Legacy typo",
          "severity": "critical",
          "score": 0.9,
          "supportingDataSlotIDs": []
        }
        """)

        #expect(item.facet == .unknown)
        #expect(item.severity == .low)
        #expect(item.readFingerprint.contains("pulse:v1:unknown"))

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        #expect(encoded?["facet"] as? String == "unknown")
        #expect(encoded?["severity"] as? String == "low")
    }

    @Test("Attention item JSON keeps stable facet and severity strings")
    func attentionItemJSONKeepsStableFacetAndSeverityStrings() throws {
        let item = try #require(model("concentration-pressure").rankedAttentionItems.first)
        let data = try JSONEncoder().encode(item)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(AttentionItem.self, from: data)

        #expect(object["facet"] as? String == "allocation")
        #expect(object["severity"] as? String == "medium")
        #expect(decoded == item)
    }

    @Test("Income explanation window only surfaces in-window events")
    func incomeExplanationWindowOnlySurfacesInWindowEvents() {
        let snapshot = PortfolioSnapshot(
            asOf: "2026-06-22",
            totalValue: Money(value: "0.00", currency: "EUR"),
            openHoldings: [],
            sectors: [],
            assetTypes: [],
            incomeEvents: [
                incomeEvent(date: "2026-06-21", name: "Before Window", quoteId: 9101),
                incomeEvent(date: "2026-07-22", name: "Inside Window", quoteId: 9102),
                incomeEvent(date: "2026-07-23", name: "After Window", quoteId: 9103),
            ],
            dividendRowCount: 3,
            priceSeries: []
        )

        let items = PressureEngine.buildModel(from: snapshot)
            .rankedAttentionItems
            .filter { $0.facet == "income" }

        #expect(items.map(\.title) == ["Inside Window ex-dividend"])
        #expect(items.first?.explanation.threshold?.value == "2026-06-22..2026-07-22")
        #expect(items.first?.explanation.currentValue?.value == "2026-07-22")
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

    private func incomeEvent(date: String, name: String, quoteId: Int) -> IncomeEventSummary {
        IncomeEventSummary(
            date: date,
            kind: "ex-dividend",
            symbolName: name,
            estimated: false,
            quoteId: quoteId
        )
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
