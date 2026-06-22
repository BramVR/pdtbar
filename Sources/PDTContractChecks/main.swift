import Foundation
import PulseCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let fixture = """
{
  "portfolio": {
    "baseCurrency": "USD",
    "eodDate": "2026-06-21",
    "holdings": [
      {
        "ticker": "NVDA",
        "name": "NVIDIA Corporation",
        "currentWorth": { "value": "1557.42", "currency": "USD" },
        "portfolioWeight": 0.1557,
        "eodDate": "2026-06-21"
      },
      {
        "ticker": "CLOSED",
        "name": "Closed Position",
        "currentWorth": { "value": "0.00", "currency": "USD" },
        "eodDate": "2026-06-20"
      }
    ]
  }
}
""".data(using: .utf8)!

do {
    let facts = try PDTContractAdapter().ingest(fixture)
    expect(facts.liveHoldings.count == 1, "one live holding")
    let holding = facts.liveHoldings[0]

    expect(holding.ticker == "NVDA", "closed holding excluded from live facts")
    expect(holding.currentWorth == Money(decimal: Decimal(string: "1557.42")!, currency: "USD"), "currency-aware Money object")
    expect(holding.portfolioWeightFraction == Decimal(string: "0.1557")!, "portfolio weight remains a fraction")
    expect(holding.portfolioWeightPercent == Decimal(string: "15.57")!, "0.1557 portfolio weight means 15.57%")
    expect(facts.freshness.contains(EODFreshnessFact(source: "portfolio.eodDate", date: "2026-06-21")), "portfolio EOD freshness")
    expect(facts.freshness.contains(EODFreshnessFact(source: "holding.NVDA.eodDate", date: "2026-06-21")), "holding EOD freshness")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}

let bareNumberMoneyFixture = """
{
  "portfolio": {
    "baseCurrency": "USD",
    "eodDate": "2026-06-21",
    "holdings": [
      {
        "ticker": "NVDA",
        "currentWorth": 1557.42,
        "portfolioWeight": 0.1557
      }
    ]
  }
}
""".data(using: .utf8)!

do {
    _ = try PDTContractAdapter().ingest(bareNumberMoneyFixture)
    FileHandle.standardError.write(Data("FAIL: bare-number currentWorth accepted\n".utf8))
    exit(1)
} catch {
    // Money in the PDT contract is an object with value + currency.
}
