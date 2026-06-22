import Foundation
import PulseCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let activeFacts = PortfolioFacts(
    baseCurrency: "USD",
    liveHoldings: [
        holding(ticker: "NVDA", name: "NVIDIA Corporation", weight: "0.22")
    ],
    freshness: []
)

let activeModel = AllocationFacet().model(from: activeFacts)
expect(
    activeModel.attentionItems == [
        AttentionItem(
            title: "NVDA concentration",
            detail: "22% of portfolio; threshold 20%",
            facet: .allocation,
            severity: .pressure,
            allocation: AllocationAttentionData(
                ticker: "NVDA",
                name: "NVIDIA Corporation",
                portfolioWeightFraction: Decimal(string: "0.22")!,
                thresholdFraction: Decimal(string: "0.20")!
            )
        )
    ],
    "open holding at or above 20% emits one concentration attention item"
)
expect(
    activeModel.allocationSnapshot == AllocationSnapshot(
        state: .activePressure,
        concentrationThresholdFraction: Decimal(string: "0.20")!,
        holdings: [
            AllocationHoldingSnapshot(
                ticker: "NVDA",
                name: "NVIDIA Corporation",
                portfolioWeightFraction: Decimal(string: "0.22")!,
                isConcentrationPressure: true
            )
        ]
    ),
    "active pressure model includes allocation snapshot"
)

let rankedFacts = PortfolioFacts(
    baseCurrency: "USD",
    liveHoldings: [
        holding(ticker: "VTI", name: "Vanguard Total Stock Market ETF", weight: "0.25"),
        holding(ticker: "AAPL", name: "Apple Inc.", weight: "0.31"),
        holding(ticker: "MSFT", name: "Microsoft Corporation", weight: "0.31")
    ],
    freshness: []
)

let rankedModel = AllocationFacet().model(from: rankedFacts)
expect(
    rankedModel.attentionItems.map(\.allocation?.ticker) == ["AAPL", "MSFT", "VTI"],
    "concentration pressure ranks by portfolio weight, then stable ticker fallback"
)
expect(
    rankedModel.attentionItems.map(\.allocation?.portfolioWeightFraction) == [
        Decimal(string: "0.31")!,
        Decimal(string: "0.31")!,
        Decimal(string: "0.25")!
    ],
    "ranked items expose allocation ranking inputs"
)

let quietFacts = PortfolioFacts(
    baseCurrency: "USD",
    liveHoldings: [
        holding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19"),
        holding(ticker: "PEP", name: "PepsiCo, Inc.", weight: "0.08")
    ],
    freshness: []
)

let quietModel = AllocationFacet().model(from: quietFacts)
expect(quietModel.attentionItems.isEmpty, "open holdings below 20% emit no allocation pressure")
expect(
    quietModel.allocationSnapshot == AllocationSnapshot(
        state: .allQuiet,
        concentrationThresholdFraction: Decimal(string: "0.20")!,
        holdings: [
            AllocationHoldingSnapshot(
                ticker: "KO",
                name: "The Coca-Cola Company",
                portfolioWeightFraction: Decimal(string: "0.19")!,
                isConcentrationPressure: false
            ),
            AllocationHoldingSnapshot(
                ticker: "PEP",
                name: "PepsiCo, Inc.",
                portfolioWeightFraction: Decimal(string: "0.08")!,
                isConcentrationPressure: false
            )
        ]
    ),
    "allQuiet allocation snapshot keeps non-pressure holdings available"
)

let staleFacts = PortfolioFacts(
    baseCurrency: "USD",
    liveHoldings: [
        holding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19")
    ],
    freshness: [
        EODFreshnessFact(source: "portfolio.eodDate", date: "2026-06-20"),
        EODFreshnessFact(source: "holding.KO.eodDate", date: "2026-06-20")
    ]
)
let staleModel = AllocationFacet(requiredEODDate: "2026-06-21").model(from: staleFacts)
expect(
    staleModel.eodFreshness == EODFreshnessDisplayFact(
        state: .stale,
        eodDate: "2026-06-20",
        requiredEODDate: "2026-06-21",
        title: "PDT EOD data is stale",
        detail: "Latest PDT EOD date 2026-06-20; expected 2026-06-21"
    ),
    "model exposes stale EOD freshness display facts from PDT freshness dates"
)

let currentFreshnessModel = AllocationFacet(requiredEODDate: "2026-06-21").model(
    from: PortfolioFacts(
        baseCurrency: "USD",
        liveHoldings: [
            holding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19")
        ],
        freshness: [
            EODFreshnessFact(source: "portfolio.eodDate", date: "2026-06-21")
        ]
    )
)
expect(
    currentFreshnessModel.eodFreshness?.state == .current,
    "model exposes current EOD freshness when PDT dates meet the required EOD date"
)

let pdtFixtureWithClosedConcentration = """
{
  "portfolio": {
    "baseCurrency": "USD",
    "eodDate": "2026-06-21",
    "holdings": [
      {
        "ticker": "OPEN",
        "name": "Open Holding",
        "currentWorth": { "value": "900.00", "currency": "USD" },
        "portfolioWeight": "0.09",
        "eodDate": "2026-06-21"
      },
      {
        "ticker": "CLOSED",
        "name": "Closed Holding",
        "currentWorth": { "value": "0.00", "currency": "USD" },
        "portfolioWeight": "0.80",
        "eodDate": "2026-06-21"
      }
    ]
  }
}
""".data(using: .utf8)!

do {
    let facts = try PDTContractAdapter().ingest(pdtFixtureWithClosedConcentration)
    let model = AllocationFacet().model(from: facts)
    expect(model.attentionItems.isEmpty, "closed high-weight PDT holding creates no allocation pressure")
    expect(model.allocationSnapshot?.state == .allQuiet, "closed high-weight PDT holding keeps allocation allQuiet")
    expect(model.allocationSnapshot?.holdings.map(\.ticker) == ["OPEN"], "allocation snapshot excludes closed holdings")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

func holding(ticker: String, name: String?, weight: String) -> PortfolioHoldingFact {
    PortfolioHoldingFact(
        ticker: ticker,
        name: name,
        currentWorth: Money(decimal: Decimal(100), currency: "USD"),
        portfolioWeightFraction: Decimal(string: weight)!,
        eodDate: nil
    )
}
