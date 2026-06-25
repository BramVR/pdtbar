import Foundation
import Testing
import PDTBarCore

@Suite("Income calendar")
struct IncomeCalendarTests {
    @Test("Intent summarizes events and picks next event by date then priority")
    func intentSummarizesEventsAndPicksNextByDateThenPriority() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-06-28", kind: "payment-dividend", name: "Later Income Co", quoteId: 9102),
                incomeEvent(date: "2026-06-24", kind: "payment-dividend", name: "Same Day Pay", quoteId: 9101),
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Same Day Ex",
                    estimated: true,
                    quoteId: 9100
                ),
            ],
            asOf: "2026-06-22"
        )

        #expect(intent.summary.eventCount == 3)
        #expect(intent.summary.confirmedCount == 2)
        #expect(intent.summary.estimatedCount == 1)
        #expect(intent.summary.windowStart == "2026-06-22")
        #expect(intent.summary.windowEnd == "2026-06-28")
        #expect(intent.nextEvent?.symbolName == "Same Day Ex")
        #expect(intent.events.map(\.symbolName) == ["Same Day Ex", "Same Day Pay", "Later Income Co"])
    }

    @Test("Intent excludes neutral calendar kinds from income next and summary")
    func intentExcludesNeutralCalendarKinds() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-06-23", kind: "earnings-release", name: "Not Income Co", quoteId: 9104),
                incomeEvent(date: "2026-06-24", kind: "payment-dividend", name: "Cash Landing Co", quoteId: 9105),
            ],
            asOf: "2026-06-22"
        )

        #expect(intent.summary.eventCount == 1)
        #expect(intent.nextEvent?.symbolName == "Cash Landing Co")
        #expect(intent.events.map(\.kind) == ["payment-dividend"])
    }

    @Test("Intent excludes income events before the as-of window")
    func intentExcludesIncomeEventsBeforeAsOf() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-06-21", kind: "ex-dividend", name: "Stale Income Co", quoteId: 9107),
                incomeEvent(date: "2026-06-22", kind: "payment-dividend", name: "Current Income Co", quoteId: 9108),
            ],
            asOf: "2026-06-22"
        )

        #expect(intent.summary.eventCount == 1)
        #expect(intent.nextEvent?.symbolName == "Current Income Co")
        #expect(intent.events.map(\.symbolName) == ["Current Income Co"])
    }

    @Test("Descriptor summarizes a single estimated event")
    func descriptorSummarizesSingleEstimatedEvent() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Estimated Income Co",
                    estimated: true,
                    quoteId: 9106
                ),
            ],
            asOf: "2026-06-22"
        )

        let rows = IncomeCalendarDescriptor.rows(for: intent)

        #expect(rows.first?.id == "income.summary")
        #expect(rows.first?.detail == "1 estimated event through 2026-06-24")
        #expect(rows.last?.id == "income.next")
        #expect(rows.last?.children.first { $0.id.hasSuffix(".state") }?.detail == "Estimated")
    }

    @Test("Descriptor renders summary and next-event rows with stable IDs")
    func descriptorRendersSummaryAndNextRows() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-07-10", kind: "payment-dividend", name: "Helix Pharma A/S", quoteId: 9003),
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Helix Pharma A/S",
                    quoteId: 9003,
                    amount: Money(value: "78.00", currency: "EUR")
                ),
            ],
            asOf: "2026-06-22"
        )

        let rows = IncomeCalendarDescriptor.rows(for: intent)

        #expect(rows.map(\.id) == ["income.summary", "income.next"])
        #expect(rows.map(\.accessibilityIdentifier) == ["pdtbar.row.income.summary", "pdtbar.row.income.next"])
        #expect(rows.first?.role == .incomeSummary)
        #expect(rows.first?.title == "Income window")
        #expect(rows.first?.detail == "2 confirmed events through 2026-07-10")
        #expect(rows.last?.role == .incomeNext)
        #expect(rows.last?.title == "Next income: Helix Pharma A/S")
        #expect(rows.last?.detail == "ex-dividend on 2026-06-24; EUR 78.00")
        #expect(rows.last?.children.map(\.id) == [
            "income.quote.9003.ex-dividend.2026-06-24.date",
            "income.quote.9003.ex-dividend.2026-06-24.kind",
            "income.quote.9003.ex-dividend.2026-06-24.state",
            "income.quote.9003.ex-dividend.2026-06-24.amount",
        ])
    }

    @Test("Descriptor preserves explicit empty state")
    func descriptorPreservesExplicitEmptyState() {
        let rows = IncomeCalendarDescriptor.rows(for: IncomeCalendar.build(events: [], asOf: "2026-06-22"))

        #expect(rows.count == 1)
        #expect(rows.first?.id == "income.empty")
        #expect(rows.first?.role == .incomeEmpty)
        #expect(rows.first?.title == "No income events")
        #expect(rows.first?.detail == "No calendar events in the next window")
    }
}

private func incomeEvent(
    date: String,
    kind: String,
    name: String,
    estimated: Bool = false,
    quoteId: Int,
    amount: Money? = nil
) -> IncomeEventSummary {
    IncomeEventSummary(
        date: date,
        kind: kind,
        symbolName: name,
        estimated: estimated,
        quoteId: quoteId,
        amount: amount
    )
}
