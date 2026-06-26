import Testing
import PDTBarCore

@Suite("PDT optional detail normalization")
struct OptionalDetailNormalizationTests {
    @Test("Shared interface normalizes live-shaped and fixture-shaped optional details equivalently")
    func sharedInterfaceNormalizesLiveShapedAndFixtureShapedOptionalDetailsEquivalently() {
        let quoteIDsBySymbolID = [5101: 9101]
        let expected = PDTOptionalDetailNormalizer.normalize(
            distributions: PDTOptionalDistributionsInput(
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
            ),
            xRayHoldings: [
                PDTXRayHoldingInput(weight: 25.0),
                PDTXRayHoldingInput(weight: 0.5),
            ],
            calendarEvents: [
                PDTCalendarEventInput(
                    date: "2026-06-29",
                    type: "no-events-today",
                    isEstimated: false,
                    symbolId: nil,
                    symbolName: nil
                ),
                PDTCalendarEventInput(
                    date: "2026-06-30",
                    type: "ex-dividend",
                    isEstimated: false,
                    symbolId: 5101,
                    symbolName: "Optional Detail Co"
                ),
                PDTCalendarEventInput(
                    date: "2026-07-05",
                    type: "payment-dividend",
                    isEstimated: true,
                    symbolId: 5101,
                    symbolName: "Optional Detail Co"
                ),
            ],
            dividends: [
                PDTDividendInput(
                    date: "2026-06-01T08:00:00+00:00",
                    amount: Money(value: "8.00", currency: "EUR"),
                    symbolQuoteId: 9101
                ),
                PDTDividendInput(
                    date: "2026-03-01T08:00:00+00:00",
                    amount: Money(value: "7.50", currency: "EUR"),
                    symbolQuoteId: 9101
                ),
            ],
            quoteIDsBySymbolID: quoteIDsBySymbolID,
            priceRows: [
                PDTPriceInput(date: "2026-06-27", closeAdjusted: "99.00", symbolQuoteId: 9101),
                PDTPriceInput(date: "2026-06-28", closeAdjusted: "101.00", symbolQuoteId: 9101),
            ]
        )

        let liveShaped = PDTOptionalDetailNormalizer.normalize(
            distributions: PDTOptionalDistributionsInput(
                sectors: expected.sectors.map {
                    PDTDistributionInput(categoryName: $0.name, totalValue: $0.totalValue, percentage: $0.percentage)
                },
                assetTypes: expected.assetTypes.map {
                    PDTDistributionInput(categoryName: $0.name, totalValue: $0.totalValue, percentage: $0.percentage)
                }
            ),
            xRayHoldings: [25.0, 0.5].map { PDTXRayHoldingInput(weight: $0) },
            calendarEvents: [
                PDTCalendarEventInput(
                    date: "2026-06-30",
                    type: "ex-dividend",
                    isEstimated: false,
                    symbolId: 5101,
                    symbolName: "Optional Detail Co"
                ),
                PDTCalendarEventInput(
                    date: "2026-07-05",
                    type: "payment-dividend",
                    isEstimated: true,
                    symbolId: 5101,
                    symbolName: "Optional Detail Co"
                ),
            ],
            dividends: [
                PDTDividendInput(
                    date: "2026-06-01T08:00:00+00:00",
                    amount: Money(value: "8.00", currency: "EUR"),
                    symbolQuoteId: 9101
                ),
                PDTDividendInput(
                    date: "2026-03-01T08:00:00+00:00",
                    amount: Money(value: "7.50", currency: "EUR"),
                    symbolQuoteId: 9101
                ),
            ],
            quoteIDsBySymbolID: quoteIDsBySymbolID,
            priceRows: [
                PDTPriceInput(date: "2026-06-27", closeAdjusted: "99.00", symbolQuoteId: 9101),
                PDTPriceInput(date: "2026-06-28", closeAdjusted: "101.00", symbolQuoteId: 9101),
            ]
        )

        #expect(liveShaped == expected)
        #expect(expected.xRayHoldings == [
            XRayHoldingSummary(weight: 0.25),
            XRayHoldingSummary(weight: 0.005),
        ])
        #expect(expected.incomeEvents.map(\.quoteId) == [9101, 9101])
        #expect(expected.incomeEvents.first?.amount == Money(value: "8.00", currency: "EUR"))
        #expect(expected.incomeEvents.last?.amount == nil)
        #expect(expected.dividendRowCount == 2)
        #expect(expected.priceSeries.map { [$0.quoteId.description, $0.date, $0.closeAdjusted] } == [
            ["9101", "2026-06-27", "99.00"],
            ["9101", "2026-06-28", "101.00"],
        ])
    }

    @Test("Negative dividend corrections suppress unsafe displayed amounts")
    func negativeDividendCorrectionsSuppressUnsafeDisplayedAmounts() {
        let normalized = PDTOptionalDetailNormalizer.normalize(
            distributions: nil,
            xRayHoldings: nil,
            calendarEvents: [
                PDTCalendarEventInput(
                    date: "2026-06-30",
                    type: "ex-dividend",
                    isEstimated: false,
                    symbolId: 5101,
                    symbolName: "Correction Co"
                ),
            ],
            dividends: [
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
            ],
            quoteIDsBySymbolID: [5101: 9101],
            priceRows: []
        )

        #expect(normalized.incomeEvents.first?.amount == nil)
        #expect(normalized.dividendRowCount == 2)
    }
}
