import Foundation
import PulseCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let quiet = PulseRenderer.render(.quietFixture)
expect(quiet.status.title == "◌", "quiet status title")
expect(quiet.status.badge == nil, "quiet status badge")
expect(quiet.card.title == "All quiet · Portfolio", "quiet card title")
expect(quiet.card.rows.isEmpty, "quiet card rows")
expect(
    quiet.allocationDrillDown?.rows.map(\.detail) == ["19% of portfolio", "8% of portfolio"],
    "quiet fixture renders allocation portfolio context"
)

let pressure = PulseRenderer.render(.pressureFixture)
expect(pressure.status.title == "◌", "pressure status title")
expect(pressure.status.badge == "• 1", "pressure status badge")
expect(pressure.card.title == "Allocation pressure", "pressure card title")
expect(pressure.card.rows.count == 1, "pressure card row count")
expect(pressure.card.rows.first?.title == "NVDA concentration", "pressure row title")
expect(pressure.card.rows.first?.detail == "22% of portfolio; threshold 20%", "pressure row detail")
expect(pressure.card.rows.first?.facet == .allocation, "pressure row facet")
expect(
    pressure.allocationDrillDown?.rows.map(\.title) == ["NVDA", "AAPL"],
    "pressure fixture renders allocation drill-down holdings"
)

let activeAllocationModel = AllocationFacet().model(
    from: PortfolioFacts(
        baseCurrency: "USD",
        liveHoldings: [
            holding(ticker: "NVDA", name: "NVIDIA Corporation", weight: "0.22"),
            holding(ticker: "AAPL", name: "Apple Inc.", weight: "0.18")
        ],
        freshness: []
    )
)
let activeAllocation = PulseRenderer.render(activeAllocationModel)
expect(activeAllocation.status.title == "◌", "active allocation status glyph")
expect(activeAllocation.status.badge == "• 1", "active allocation status count")
expect(activeAllocation.card.title == "Allocation pressure", "active allocation card title")
expect(activeAllocation.card.rows.count == 1, "active allocation pressure row count")
expect(activeAllocation.card.rows.first?.title == "NVDA concentration", "active allocation pressure row title")
expect(activeAllocation.card.rows.first?.detail == "22% of portfolio; threshold 20%", "active allocation pressure row detail")
expect(activeAllocation.allocationDrillDown?.title == "Allocation", "active allocation drill-down title")
expect(
    activeAllocation.allocationDrillDown?.rows.map(\.title) == ["NVDA", "AAPL"],
    "active allocation drill-down lists open holdings"
)
expect(
    activeAllocation.allocationDrillDown?.rows.map(\.detail) == ["22% of portfolio", "18% of portfolio"],
    "active allocation drill-down lists portfolio weights"
)

let quietAllocationModel = AllocationFacet().model(
    from: PortfolioFacts(
        baseCurrency: "USD",
        liveHoldings: [
            holding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19"),
            holding(ticker: "PEP", name: "PepsiCo, Inc.", weight: "0.08")
        ],
        freshness: []
    )
)
let quietAllocation = PulseRenderer.render(quietAllocationModel)
expect(quietAllocation.status.title == "◌", "quiet allocation status glyph")
expect(quietAllocation.status.badge == nil, "quiet allocation has no pressure count")
expect(quietAllocation.card.title == "All quiet · Portfolio", "quiet allocation card title")
expect(quietAllocation.card.rows.isEmpty, "quiet allocation card has no pressure rows")
expect(
    quietAllocation.allocationDrillDown?.rows.map(\.detail) == ["19% of portfolio", "8% of portfolio"],
    "quiet allocation drill-down keeps portfolio context"
)

let coldStartQuiet = PulseRenderer.render(
    AllocationFacet(requiredEODDate: "2026-06-21").model(
        from: PortfolioFacts(
            baseCurrency: "USD",
            liveHoldings: [
                holding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19")
            ],
            freshness: []
        )
    )
)
expect(coldStartQuiet.card.title == "All quiet · Portfolio", "cold-start quiet stays quiet without freshness history")
expect(coldStartQuiet.card.rows.isEmpty, "cold-start quiet has no stale row without PDT freshness facts")

let staleQuiet = PulseRenderer.render(
    PulseModel(
        statusSignal: "Pulse",
        attentionItems: [],
        allocationSnapshot: AllocationSnapshot(
            state: .allQuiet,
            concentrationThresholdFraction: Decimal(string: "0.20")!,
            holdings: [
                AllocationHoldingSnapshot(
                    ticker: "KO",
                    name: "The Coca-Cola Company",
                    portfolioWeightFraction: Decimal(string: "0.19")!,
                    isConcentrationPressure: false
                )
            ]
        ),
        eodFreshness: EODFreshnessDisplayFact(
            state: .stale,
            eodDate: "2026-06-20",
            requiredEODDate: "2026-06-21",
            title: "PDT EOD data is stale",
            detail: "Latest PDT EOD date 2026-06-20; expected 2026-06-21"
        )
    )
)
expect(staleQuiet.card.title == "Data freshness", "stale card title comes from model freshness state")
expect(staleQuiet.card.rows.first?.title == "PDT EOD data is stale", "stale row title comes from model freshness display fact")
expect(staleQuiet.card.rows.first?.detail == "Latest PDT EOD date 2026-06-20; expected 2026-06-21", "stale row detail comes from model freshness display fact")
expect(staleQuiet.card.rows.first?.facet == .freshness, "stale row uses freshness facet")

let crowdedAllocationModel = PulseModel(
    statusSignal: "Pulse",
    attentionItems: [
        allocationItem("AAPL", weight: "0.31"),
        allocationItem("MSFT", weight: "0.30"),
        allocationItem("NVDA", weight: "0.29"),
        allocationItem("VTI", weight: "0.28")
    ],
    allocationSnapshot: AllocationSnapshot(
        state: .activePressure,
        concentrationThresholdFraction: Decimal(string: "0.20")!,
        holdings: []
    )
)
let crowdedAllocation = PulseRenderer.render(crowdedAllocationModel)
expect(crowdedAllocation.status.badge == "• 4", "crowded allocation badge counts all pressure")
expect(crowdedAllocation.card.rows.map(\.title) == ["AAPL concentration", "MSFT concentration", "NVDA concentration"], "glance caps pressure rows in engine order")

assertNoAdviceCopy(in: [
    quiet,
    pressure,
    activeAllocation,
    quietAllocation,
    coldStartQuiet,
    staleQuiet,
    crowdedAllocation
])

func holding(ticker: String, name: String?, weight: String) -> PortfolioHoldingFact {
    PortfolioHoldingFact(
        ticker: ticker,
        name: name,
        currentWorth: Money(decimal: Decimal(100), currency: "USD"),
        portfolioWeightFraction: Decimal(string: weight)!,
        eodDate: nil
    )
}

func allocationItem(_ ticker: String, weight: String) -> AttentionItem {
    AttentionItem(
        title: "\(ticker) concentration",
        detail: "\(percentText(Decimal(string: weight)!)) of portfolio; threshold 20%",
        facet: .allocation,
        severity: .pressure,
        allocation: AllocationAttentionData(
            ticker: ticker,
            name: nil,
            portfolioWeightFraction: Decimal(string: weight)!,
            thresholdFraction: Decimal(string: "0.20")!
        )
    )
}

func percentText(_ fraction: Decimal) -> String {
    let percent = NSDecimalNumber(decimal: fraction * Decimal(100)).doubleValue
    if percent.rounded() == percent {
        return "\(Int(percent))%"
    }

    return String(format: "%.1f%%", percent)
}

func assertNoAdviceCopy(in views: [PulseView]) {
    let advicePattern = #"\b(buy|sell|rebalance|trim|add|reduce|increase|decrease|recommend|should)\b"#
    let regex = try! NSRegularExpression(pattern: advicePattern, options: [.caseInsensitive])

    for text in views.flatMap(renderedCopy) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        expect(regex.firstMatch(in: text, range: range) == nil, "v1 copy is informational, not advice: \(text)")
    }
}

func renderedCopy(from view: PulseView) -> [String] {
    var copy = [
        view.status.title,
        view.status.badge,
        view.card.title
    ].compactMap(\.self)

    for row in view.card.rows {
        copy.append(row.title)
        copy.append(row.detail)
    }

    if let allocationDrillDown = view.allocationDrillDown {
        copy.append(allocationDrillDown.title)
        for row in allocationDrillDown.rows {
            copy.append(row.title)
            copy.append(row.detail)
        }
    }

    return copy
}
