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
                incomeEvent(date: "2026-07-10", kind: "payment-dividend", name: "Helix Pharma A/S", estimated: true, quoteId: 9003),
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Helix Pharma A/S",
                    quoteId: 9003,
                    amount: Money(value: "78.00", currency: "EUR"),
                    priorAmount: Money(value: "66.00", currency: "EUR"),
                    changePercent: 0.1818
                ),
            ],
            asOf: "2026-06-22"
        )

        let rows = IncomeCalendarDescriptor.rows(for: intent)

        #expect(rows.map(\.id) == [
            "income.summary",
            "income.next",
            "income.quote.9003.payment-dividend.2026-07-10",
        ])
        #expect(rows.map(\.accessibilityIdentifier) == [
            "pdtbar.row.income.summary",
            "pdtbar.row.income.next",
            "pdtbar.row.income.quote.9003.payment-dividend.2026-07-10",
        ])
        #expect(rows.first?.role == .incomeSummary)
        #expect(rows.first?.title == "Income window")
        #expect(rows.first?.detail == "2 events through 2026-07-10; 1 confirmed, 1 estimated")
        let nextRow = rows.first { $0.id == "income.next" }
        #expect(nextRow?.role == .incomeNext)
        #expect(nextRow?.title == "Next income: Helix Pharma A/S")
        #expect(nextRow?.detail == "Ex-dividend date on 2026-06-24; confirmed; EUR 78.00; +18.2% from EUR 66.00")
        #expect(nextRow?.children.map(\.id) == [
            "income.quote.9003.ex-dividend.2026-06-24.date",
            "income.quote.9003.ex-dividend.2026-06-24.kind",
            "income.quote.9003.ex-dividend.2026-06-24.state",
            "income.quote.9003.ex-dividend.2026-06-24.amount",
            "income.quote.9003.ex-dividend.2026-06-24.change",
        ])
        #expect(nextRow?.children.first { $0.id.hasSuffix(".kind") }?.detail == "Ex-dividend date")
        #expect(nextRow?.children.first { $0.id.hasSuffix(".change") }?.detail == "+18.2% from EUR 66.00")
        let previewRow = rows.first { $0.id == "income.quote.9003.payment-dividend.2026-07-10" }
        #expect(previewRow?.role == .incomeEvent)
        #expect(previewRow?.title == "Helix Pharma A/S")
        #expect(previewRow?.detail == "Dividend payment date on 2026-07-10; estimated")
        #expect(previewRow?.children.first { $0.id.hasSuffix(".kind") }?.detail == "Dividend payment date")
    }

    @Test("Descriptor preserves income event action targets on event rows and detail children")
    func descriptorPreservesIncomeEventActionTargets() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Targetable Income Co",
                    estimated: true,
                    quoteId: 9230
                ),
            ],
            asOf: "2026-06-22"
        )

        let nextRow = IncomeCalendarDescriptor.rows(for: intent)
            .first { $0.id == "income.next" }
        let target = nextRow?.actionTarget

        #expect(target?.kind == .incomeEvent)
        #expect(target?.id == "income.quote.9230.ex-dividend.2026-06-24")
        #expect(target?.incomeEvent?.eventID == "income.quote.9230.ex-dividend.2026-06-24")
        #expect(target?.incomeEvent?.rowID == "income.next")
        #expect(target?.incomeEvent?.quoteId == 9230)
        #expect(target?.incomeEvent?.date == "2026-06-24")
        #expect(target?.incomeEvent?.kind == "ex-dividend")
        #expect(target?.incomeEvent?.symbolName == "Targetable Income Co")
        #expect(target?.incomeEvent?.estimated == true)
        #expect(nextRow?.children.map(\.role) == [
            .incomeEventDate,
            .incomeEventKind,
            .incomeEventState,
        ])
        #expect(nextRow?.children.allSatisfy { child in
            child.actionTarget?.kind == .incomeEvent
                && child.actionTarget?.incomeEvent?.eventID == target?.incomeEvent?.eventID
                && child.actionTarget?.incomeEvent?.rowID == child.id
        } == true)
    }

    @Test("Descriptor omits unsafe income change details")
    func descriptorOmitsUnsafeIncomeChangeDetails() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(
                    date: "2026-06-24",
                    kind: "ex-dividend",
                    name: "Unsafe Change Co",
                    quoteId: 9220,
                    amount: Money(value: "10.00", currency: "EUR"),
                    changePercent: -0.25
                ),
            ],
            asOf: "2026-06-22"
        )

        let nextRow = IncomeCalendarDescriptor.rows(for: intent)
            .first { $0.id == "income.next" }

        #expect(nextRow?.detail == "Ex-dividend date on 2026-06-24; confirmed; EUR 10.00")
        #expect(nextRow?.children.map(\.id).contains("income.quote.9220.ex-dividend.2026-06-24.change") == false)
    }

    @Test("Descriptor caps long previews and reaches overflow through as-of buckets")
    func descriptorCapsLongPreviewsAndReachesOverflowThroughBuckets() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-06-22", kind: "payment-dividend", name: "Anchor Pay A", quoteId: 9200),
                incomeEvent(date: "2026-06-22", kind: "payment-dividend", name: "Anchor Pay B", quoteId: 9201),
                incomeEvent(date: "2026-06-22", kind: "payment-dividend", name: "Anchor Pay C", quoteId: 9202),
                incomeEvent(date: "2026-06-22", kind: "payment-dividend", name: "Overflow Next", quoteId: 9203),
                incomeEvent(date: "2026-06-23", kind: "ex-dividend", name: "Near Ex", quoteId: 9206),
                incomeEvent(date: "2026-06-26", kind: "ex-dividend", name: "Overflow Week", quoteId: 9204),
                incomeEvent(date: "2026-07-01", kind: "payment-dividend", name: "Overflow Later", quoteId: 9205),
            ],
            asOf: "2026-06-22"
        )

        let rows = IncomeCalendarDescriptor.rows(for: intent)
        let previewRows = rows.filter { $0.role == .incomeNext || $0.role == .incomeEvent }
        let overflowRows = rows.filter { $0.role == .incomeDrillDown }

        #expect(previewRows.map(\.title) == [
            "Next income: Anchor Pay A",
            "Anchor Pay B",
            "Anchor Pay C",
        ])
        #expect(overflowRows.map(\.id) == [
            "income.overflow.next",
            "income.overflow.this-week",
            "income.overflow.later",
        ])
        #expect(overflowRows.first { $0.id == "income.overflow.next" }?.children.map(\.title) == [
            "Overflow Next",
        ])
        #expect(overflowRows.first { $0.id == "income.overflow.this-week" }?.children.map(\.title) == [
            "Near Ex",
            "Overflow Week",
        ])
        #expect(overflowRows.first { $0.id == "income.overflow.later" }?.children.map(\.title) == [
            "Overflow Later",
        ])
        #expect(allRowIDs(in: rows).count == Set(allRowIDs(in: rows)).count)
        #expect(allRowIDs(in: rows).allSatisfy { !$0.isEmpty })
        #expect(allRowIDs(in: rows).allSatisfy { id in
            rowsByID(in: rows)[id]?.accessibilityIdentifier == "pdtbar.row.\(id)"
        })
    }

    @Test("Descriptor assigns future next-date overflow to one bucket")
    func descriptorAssignsFutureNextDateOverflowToOneBucket() {
        let intent = IncomeCalendar.build(
            events: [
                incomeEvent(date: "2026-07-01", kind: "payment-dividend", name: "Future Pay A", quoteId: 9210),
                incomeEvent(date: "2026-07-01", kind: "payment-dividend", name: "Future Pay B", quoteId: 9211),
                incomeEvent(date: "2026-07-01", kind: "payment-dividend", name: "Future Pay C", quoteId: 9212),
                incomeEvent(date: "2026-07-01", kind: "payment-dividend", name: "Future Pay D", quoteId: 9213),
            ],
            asOf: "2026-06-22"
        )

        let overflowRows = IncomeCalendarDescriptor.rows(for: intent)
            .filter { $0.role == .incomeDrillDown }

        #expect(overflowRows.map(\.id) == ["income.overflow.next"])
        #expect(overflowRows.first?.children.map(\.title) == ["Future Pay D"])
        #expect(allRowIDs(in: overflowRows).count == Set(allRowIDs(in: overflowRows)).count)
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
    amount: Money? = nil,
    priorAmount: Money? = nil,
    changePercent: Double? = nil
) -> IncomeEventSummary {
    IncomeEventSummary(
        date: date,
        kind: kind,
        symbolName: name,
        estimated: estimated,
        quoteId: quoteId,
        amount: amount,
        priorAmount: priorAmount,
        changePercent: changePercent
    )
}

private func allRowIDs(in rows: [MenuRow]) -> [String] {
    rows.flatMap { row in
        [row.id] + allRowIDs(in: row.children)
    }
}

private func rowsByID(in rows: [MenuRow]) -> [String: MenuRow] {
    rows.reduce(into: [:]) { result, row in
        result[row.id] = row
        result.merge(rowsByID(in: row.children)) { _, child in child }
    }
}
