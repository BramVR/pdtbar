import Testing
import PDTBarCore

@Suite("PDT snapshot normalization")
struct PDTSnapshotNormalizationTests {
    @Test("Shared snapshot normalizer gives live-shaped and fixture-shaped inputs parity")
    func sharedSnapshotNormalizerGivesLiveShapedAndFixtureShapedInputsParity() {
        let liveShaped = PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: "2026-06-29",
                currency: "EUR",
                holdings: rawHoldings,
                reportedTotalValue: nil,
                symbolQuotes: symbolQuotes,
                distributions: distributions,
                xRayHoldings: xRayHoldings,
                calendarEvents: calendarEvents,
                dividends: dividends,
                priceRows: priceRows
            )
        )

        let fixtureShaped = PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: "2026-06-29",
                currency: "EUR",
                holdings: Array(rawHoldings.reversed()),
                reportedTotalValue: Money(value: "500.00", currency: "EUR"),
                symbolQuotes: Array(symbolQuotes.reversed()),
                distributions: distributions,
                xRayHoldings: xRayHoldings,
                calendarEvents: [
                    PDTCalendarEventInput(
                        date: "2026-06-29",
                        type: "no-events-today",
                        isEstimated: false,
                        symbolId: nil,
                        symbolName: nil
                    ),
                ] + calendarEvents,
                dividends: Array(dividends.reversed()),
                priceRows: priceRows
            )
        )

        #expect(liveShaped == fixtureShaped)
        #expect(liveShaped.openHoldings.map(\.quoteId) == [9101])
        #expect(liveShaped.openHoldings.first?.copyableIdentifier == "PAR")
        #expect(liveShaped.openHoldings.first?.isin == "NL0010273215")
        #expect(liveShaped.sectors.map(\.percentage) == [62.5])
        #expect(liveShaped.xRayHoldings == [XRayHoldingSummary(weight: 0.25)])
        #expect(liveShaped.incomeEvents.map(\.quoteId) == [9101, 9101])
        #expect(liveShaped.incomeEvents.first?.amount == nil)
        #expect(liveShaped.dividendRowCount == 2)
        #expect(liveShaped.priceSeries.map(\.quoteId) == [9101, 9101])
    }

    private var rawHoldings: [PDTBaseHoldingInput] {
        [
            PDTBaseHoldingInput(
                name: "Parity Co",
                quoteId: 9101,
                currentPriceDate: "2026-06-27T21:59:00+00:00",
                currentPriceLocal: Money(value: "10.25", currency: "EUR"),
                currentWorth: Money(value: "500.00", currency: "EUR"),
                currentWorthLocal: Money(value: "500.00", currency: "EUR"),
                portfolioWeight: 0.25,
                unrealisedBoughtPriceAverageLocal: nil,
                unrealisedBoughtPriceTotalLocal: Money(value: "320.00", currency: "EUR"),
                unrealisedBoughtShares: 8,
                unrealisedGains: Money(value: "180.00", currency: "EUR"),
                unrealisedGainsPercentage: 0.5625,
                closedAt: nil
            ),
            PDTBaseHoldingInput(
                name: "Closed Parity Co",
                quoteId: 9102,
                currentPriceDate: "2026-06-27T21:59:00+00:00",
                currentPriceLocal: Money(value: "1.00", currency: "EUR"),
                currentWorth: Money(value: "0.00", currency: "EUR"),
                currentWorthLocal: Money(value: "0.00", currency: "EUR"),
                portfolioWeight: 0.10,
                closedAt: "2026-06-01T00:00:00+00:00"
            ),
        ]
    }

    private var symbolQuotes: [PDTSymbolQuoteNormalizationInput] {
        [
            PDTSymbolQuoteNormalizationInput(
                quoteId: 9101,
                symbolId: 5101,
                copyableIdentifier: "PAR",
                isin: "NL0010273215"
            ),
            PDTSymbolQuoteNormalizationInput(
                quoteId: 9102,
                symbolId: 5102,
                copyableIdentifier: "CLSD",
                isin: nil
            ),
        ]
    }

    private var distributions: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: [
                PDTDistributionInput(
                    categoryName: "Technology",
                    totalValue: Money(value: "500.00", currency: "EUR"),
                    percentage: 62.5
                ),
            ],
            assetTypes: [
                PDTDistributionInput(
                    categoryName: "Stock",
                    totalValue: Money(value: "500.00", currency: "EUR"),
                    percentage: 62.5
                ),
            ]
        )
    }

    private var xRayHoldings: [PDTXRayHoldingInput] {
        [PDTXRayHoldingInput(weight: 25.0)]
    }

    private var calendarEvents: [PDTCalendarEventInput] {
        [
            PDTCalendarEventInput(
                date: "2026-06-30",
                type: "ex-dividend",
                isEstimated: false,
                symbolId: 5101,
                symbolName: "Parity Co"
            ),
            PDTCalendarEventInput(
                date: "2026-07-05",
                type: "payment-dividend",
                isEstimated: true,
                symbolId: 5101,
                symbolName: "Parity Co"
            ),
        ]
    }

    private var dividends: [PDTDividendInput] {
        [
            PDTDividendInput(
                date: "2026-06-01T08:00:00+00:00",
                amount: Money(value: "8.00", currency: "EUR"),
                symbolQuoteId: 9101
            ),
            PDTDividendInput(
                date: "2026-06-02T08:00:00+00:00",
                amount: Money(value: "-8.00", currency: "EUR"),
                symbolQuoteId: 9101
            ),
        ]
    }

    private var priceRows: [PDTPriceInput] {
        [
            PDTPriceInput(date: "2026-06-27", closeAdjusted: "99.00", symbolQuoteId: 9101),
            PDTPriceInput(date: "2026-06-28", closeAdjusted: "101.00", symbolQuoteId: 9101),
        ]
    }
}
