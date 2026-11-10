import Foundation
import Testing
import PDTBarCore

@Suite("PDT base holding normalization")
struct BaseHoldingNormalizationTests {
    @Test("Shared interface normalizes open base holding facts")
    func sharedInterfaceNormalizesOpenBaseHoldingFacts() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Open Public Co",
                    quoteId: 1001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.25", currency: "EUR"),
                    currentWorth: Money(value: "500.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "500.00", currency: "EUR"),
                    portfolioWeight: 0.25,
                    unrealisedBoughtPriceAverageLocal: nil,
                    unrealisedBoughtPriceTotalLocal: Money(value: "320.00", currency: "EUR"),
                    unrealisedBoughtShares: 8,
                    unrealisedGains: Money(value: "180.00", currency: "EUR"),
                    unrealisedGainsPercentage: 0.5625,
                    closedAt: nil,
                    copyableIdentifier: " PUBC ",
                    isin: " nl0010273215 "
                ),
                PDTBaseHoldingInput(
                    name: "Closed Co",
                    quoteId: 1002,
                    currentPriceDate: "2026-06-25T21:59:00+00:00",
                    currentPriceLocal: Money(value: "1.00", currency: "EUR"),
                    currentWorth: Money(value: "0.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "0.00", currency: "EUR"),
                    portfolioWeight: 0.10,
                    closedAt: "2026-06-01T00:00:00+00:00",
                    copyableIdentifier: "CLSD"
                ),
                PDTBaseHoldingInput(
                    name: "Zero Worth",
                    quoteId: 1003,
                    currentPriceDate: "2026-06-24T21:59:00+00:00",
                    currentPriceLocal: Money(value: "2.00", currency: "EUR"),
                    currentWorth: Money(value: "0.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "0.00", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "ZERO"
                ),
                PDTBaseHoldingInput(
                    name: "Negative Worth",
                    quoteId: 1005,
                    currentPriceDate: "2026-06-24T21:59:00+00:00",
                    currentPriceLocal: Money(value: "2.00", currency: "EUR"),
                    currentWorth: Money(value: "-10.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "-10.00", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "NEGV"
                ),
                PDTBaseHoldingInput(
                    name: "Invalid Money",
                    quoteId: 1004,
                    currentPriceDate: "2026-06-23T21:59:00+00:00",
                    currentPriceLocal: Money(value: "bad", currency: "EUR"),
                    currentWorth: Money(value: "bad", currency: "EUR"),
                    currentWorthLocal: Money(value: "bad", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "123456"
                ),
            ],
            currency: "EUR",
            reportedTotalValue: Money(value: "not-money", currency: "EUR")
        )

        #expect(normalized.openHoldings.map(\.quoteId) == [1001])
        let holding = normalized.openHoldings[0]
        #expect(holding.worth == Money(value: "500.00", currency: "EUR"))
        #expect(holding.price == Money(value: "10.25", currency: "EUR"))
        #expect(holding.priceAsOf == "2026-06-26")
        #expect(holding.copyableIdentifier == "PUBC")
        #expect(holding.isin == "NL0010273215")
        #expect(holding.averageBuyPrice == Money(value: "40.0000", currency: "EUR"))
        #expect(holding.gainLoss == Money(value: "180.00", currency: "EUR"))
        #expect(holding.gainLossPercentage == 0.5625)
        #expect(normalized.totalValue == Money(value: "500.00", currency: "EUR"))
    }

    @Test("Multi-currency holdings total in the portfolio currency")
    func multiCurrencyHoldingsTotalInThePortfolioCurrency() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "US Traded Co",
                    quoteId: 2001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "347.66", currency: "EUR"),
                    currentExchangeRate: 1.154,
                    currentWorth: Money(value: "9347.40", currency: "USD"),
                    currentWorthLocal: Money(value: "8100.00", currency: "EUR"),
                    portfolioWeight: 0.34,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "EU Traded Co",
                    quoteId: 2002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "612.40", currency: "EUR"),
                    currentExchangeRate: 1,
                    currentWorth: Money(value: "15500.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "15500.00", currency: "EUR"),
                    portfolioWeight: 0.66,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        #expect(normalized.openHoldings.map(\.quoteId) == [2001, 2002])
        #expect(normalized.totalValue == Money(value: "23600.00", currency: "EUR"))
    }

    @Test("Portfolio currency inference requires a local-currency consensus")
    func portfolioCurrencyInferenceRequiresLocalCurrencyConsensus() {
        let usdHoldings = [
            testHolding(quoteId: 6101, localWorth: Money(value: "500.00", currency: "USD")),
            testHolding(quoteId: 6102, localWorth: Money(value: "250.00", currency: "USD")),
        ]
        let mixedHoldings = [
            testHolding(
                quoteId: 6201,
                currentWorth: Money(value: "250.00", currency: "DKK"),
                localWorth: Money(value: "250.00", currency: "DKK")
            ),
            testHolding(quoteId: 6202, localWorth: Money(value: "500.00", currency: "EUR")),
        ]

        #expect(PDTBaseHoldingNormalizer.portfolioCurrency(from: usdHoldings, fallback: "EUR") == "USD")
        #expect(PDTBaseHoldingNormalizer.portfolioCurrency(from: mixedHoldings, fallback: "EUR") == "EUR")
    }

    @Test("Headline total prefers each holding's portfolio-currency worth over the first holding's currency")
    func headlineTotalPrefersEachHoldingsPortfolioCurrencyWorth() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Trading Currency Local",
                    quoteId: 3001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "50.00", currency: "USD"),
                    currentWorth: Money(value: "400.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "500.00", currency: "USD"),
                    portfolioWeight: 0.30,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 3002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.70,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // 400.00 EUR + 1000.00 EUR; never 500 USD + 1000 EUR labeled "USD".
        #expect(normalized.openHoldings.map(\.quoteId) == [3001, 3002])
        #expect(normalized.totalValue == Money(value: "1400.00", currency: "EUR"))
    }

    @Test("Headline total converts trading-only worth with the holding exchange rate")
    func headlineTotalConvertsTradingOnlyWorthWithTheHoldingExchangeRate() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Danish Traded Co",
                    quoteId: 4001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "25.00", currency: "DKK"),
                    currentExchangeRate: 2.0,
                    currentWorth: Money(value: "250.00", currency: "DKK"),
                    currentWorthLocal: Money(value: "250.00", currency: "DKK"),
                    portfolioWeight: 0.20,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 4002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.80,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // 250.00 DKK / 2.0 = 125.00 EUR, plus 1000.00 EUR.
        #expect(normalized.openHoldings.map(\.quoteId) == [4001, 4002])
        #expect(normalized.totalValue == Money(value: "1125.00", currency: "EUR"))
    }

    @Test("Headline total keeps the portfolio currency when a worth cannot be converted")
    func headlineTotalKeepsThePortfolioCurrencyWhenAWorthCannotBeConverted() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Unconvertible Co",
                    quoteId: 5001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "25.00", currency: "USD"),
                    currentWorthLocal: Money(value: "250.00", currency: "USD"),
                    portfolioWeight: 0.20,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 5002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.80,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // The USD-only worth stays visible as a holding but is excluded from the
        // headline total instead of being mixed into an EUR-labeled sum.
        #expect(normalized.openHoldings.map(\.quoteId) == [5001, 5002])
        #expect(normalized.openHoldings[0].worth == Money(value: "250.00", currency: "USD"))
        #expect(normalized.totalValue == Money(value: "1000.00", currency: "EUR"))
    }

    @Test("Fixture-backed Pulse scenarios keep their normalized behavior")
    func fixtureBackedPulseScenariosKeepTheirNormalizedBehavior() throws {
        let concentration = try model("concentration-pressure")
        let income = try model("income-event")
        let bigMover = try model("big-mover", withPrior: true)
        let quiet = try model("quiet-no-pressure")

        #expect(concentration.rankedAttentionItems.first?.facet == "allocation")
        #expect(concentration.facetSnapshots.allocation.openHoldingCount == 12)
        #expect(income.rankedAttentionItems.contains { $0.facet == "income" })
        #expect(income.facetSnapshots.income.upcomingEvents.count == 5)
        #expect(bigMover.supportingDataSlots.contains { $0.facet == "bigMovers" })
        #expect(bigMover.facetSnapshots.bigMovers.priceSeriesCount == 5)
        #expect(quiet.allQuiet)
        #expect(quiet.rankedAttentionItems.isEmpty)
    }

    private func model(_ fixtureName: String, withPrior: Bool = false) throws -> PortfolioPulseModel {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let prior = withPrior ? try? PDTFixtureDataSource.priorSnapshot(from: fixture) : nil
        return PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
    }

    private func testHolding(
        quoteId: Int,
        currentWorth: Money? = nil,
        localWorth: Money
    ) -> PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: "Test Holding \(quoteId)",
            quoteId: quoteId,
            currentPriceDate: "2026-06-26T21:59:00+00:00",
            currentPriceLocal: localWorth,
            currentWorth: currentWorth ?? localWorth,
            currentWorthLocal: localWorth,
            portfolioWeight: 0.5,
            closedAt: nil
        )
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
