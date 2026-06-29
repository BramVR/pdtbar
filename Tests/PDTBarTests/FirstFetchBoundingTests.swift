import Foundation
import Testing
import PDTBarCore

@Suite("First fetch MCP bounding")
struct FirstFetchBoundingTests {
    @Test("Calendar income join limits quote lookups in a large portfolio")
    func calendarIncomeJoinLimitsQuoteLookupsInLargePortfolio() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(largePortfolioHoldingsJSON(count: 80).utf8),
            "pdt-list-calendar-events?date_from=2026-06-26&date_to=2026-07-26&page=1&per_page=250": Data("""
            {
              "data": [
                { "date": "2026-06-29", "type": "ex-dividend", "isEstimated": false, "symbolId": 5079, "symbolName": "Synthetic Holding 79" },
                { "date": "2026-07-02", "type": "payment-dividend", "isEstimated": false, "symbolId": 5080, "symbolName": "Synthetic Holding 80" }
              ],
              "meta": { "last_page": 1 }
            }
            """.utf8),
            "pdt-get-symbol-quote?id=1080": Data(#"{"id":1080,"code":"SYN80","symbolId":5080}"#.utf8),
            "pdt-get-symbol-quote?id=1079": Data(#"{"id":1079,"code":"SYN79","symbolId":5079}"#.utf8),
        ])

        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: true,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: false,
                incomeQuoteLookupScope: .calendarSymbolIDs
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.count == 80)
        #expect(snapshot.incomeEvents.compactMap(\.quoteId).sorted() == [1079, 1080])
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.count == 2)
        #expect(connector.calls.filter { $0 == "pdt-list-symbol-prices" }.isEmpty)
    }
}

private func largePortfolioHoldingsJSON(count: Int) -> String {
    let holdings = (1 ... count).map { index in
        """
        {
          "symbolName": "Synthetic Holding \(index)",
          "symbolQuoteId": \(1000 + index),
          "currentPriceDate": "2026-06-26T21:59:00+00:00",
          "currentPriceLocal": { "value": "\(index).00", "currency": "EUR" },
          "currentWorthLocal": { "value": "100.00", "currency": "EUR" },
          "portfolioWeight": 0.01,
          "closedAt": null
        }
        """
    }.joined(separator: ",")
    return #"{"holdings":["# + holdings + #"]}"#
}
