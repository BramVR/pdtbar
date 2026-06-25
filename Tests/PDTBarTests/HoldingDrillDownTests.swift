import Foundation
import Testing
import PDTBarCore

@Suite("Holding drill-downs")
struct HoldingDrillDownTests {
    @Test("Descriptor shows next joined income event in holding drill-down")
    func descriptorShowsNextJoinedIncomeEvent() throws {
        var snapshot = try quietSnapshot()
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Nova Lithography",
                estimated: false,
                quoteId: 9001
            ),
        ]

        let holdingRow = try holdingRow(for: 9001, snapshot: snapshot)

        #expect(holdingRow.children.first { $0.id == "allocation.9001.nextIncome" }?.title == "Next income")
        #expect(
            holdingRow.children.first { $0.id == "allocation.9001.nextIncome" }?.detail
                == "Ex-dividend date on 2026-06-25; confirmed"
        )
    }

    @Test("Descriptor labels estimated holding income events quietly")
    func descriptorLabelsEstimatedHoldingIncomeEventsQuietly() throws {
        var snapshot = try quietSnapshot()
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-26",
                kind: "payment-dividend",
                symbolName: "Nova Lithography",
                estimated: true,
                quoteId: 9001
            ),
        ]

        let holdingRow = try holdingRow(for: 9001, snapshot: snapshot)
        let incomeRow = holdingRow.children.first { $0.id == "allocation.9001.nextIncome" }

        #expect(incomeRow?.detail == "Dividend payment date on 2026-06-26; estimated")
        #expect(incomeRow?.detail?.localizedCaseInsensitiveContains("pressure") == false)
        #expect(incomeRow?.detail?.localizedCaseInsensitiveContains("urgent") == false)
    }

    @Test("Descriptor omits holding income row when no joined event is certain")
    func descriptorOmitsHoldingIncomeRowWithoutCertainJoin() throws {
        var snapshot = try quietSnapshot()
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Symbol-only Income Co",
                estimated: false,
                symbolId: 5001
            ),
            IncomeEventSummary(
                date: "not-a-date",
                kind: "payment-dividend",
                symbolName: "Nova Lithography",
                estimated: false,
                quoteId: 9001
            ),
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Unheld Income Co",
                estimated: false,
                quoteId: 9999
            ),
        ]

        let holdingRow = try holdingRow(for: 9001, snapshot: snapshot)

        #expect(holdingRow.children.contains { $0.id == "allocation.9001.nextIncome" } == false)
    }
}

private func quietSnapshot() throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json"))
}

private func holdingRow(for quoteId: Int, snapshot: PortfolioSnapshot) throws -> MenuRow {
    let model = PressureEngine.buildModel(from: snapshot)
    return try #require(
        MenuDescriptorRenderer.render(model: model)
            .sections
            .first { $0.id == "allocation" }?
            .rows
            .first { $0.id == "allocation.\(quoteId)" }
    )
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
