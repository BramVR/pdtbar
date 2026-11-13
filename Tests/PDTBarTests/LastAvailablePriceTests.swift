import Foundation
import PDTBarCore
import Testing

@Suite("Last available price")
struct LastAvailablePriceTests {
    @Test("The Prices submenu lists every holding's last available price with its own date while PDT lags a day")
    func pricesSubmenuListsLastAvailablePrices() throws {
        let prices = try pricesRow(in: MenuDescriptorRenderer.render(model: laggingModel()))
        let priceRows = prices.children.filter { $0.id.hasPrefix("freshness.price.") }

        #expect(priceRows.count == 19)
        for quoteId in 1...18 {
            let row = try #require(priceRows.first { $0.id == "freshness.price.\(quoteId)" })
            #expect(row.title == "Holding \(quoteId)")
            #expect(row.detail == "EUR 12.50 on 2026-11-12")
        }
        #expect(priceRows.first { $0.id == "freshness.price.19" }?.detail == "No price from PDT")
    }

    @Test("Hidden portfolio values hide the price and keep its date")
    func hiddenValuesKeepThePriceDate() throws {
        let descriptor = MenuDescriptorRenderer.render(
            model: laggingModel(),
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let row = try #require(try pricesRow(in: descriptor).children.first { $0.id == "freshness.price.1" })

        #expect(row.detail == "\(PortfolioValueDisplaySettings.hiddenPlaceholder) on 2026-11-12")
    }
}

private func pricesRow(in descriptor: MenuDescriptor) throws -> MenuRow {
    try #require(descriptor.sections.first { $0.id == "freshness" }?.rows.first { $0.id == "freshness.summary" })
}

/// Bram's live shape on Friday 2026-11-13: prices and history through 2026-11-12, nothing for today, one holding unpriced.
private func laggingModel() -> PortfolioPulseModel {
    let priced = (1...18).map { quoteId in
        NormalizedHolding(
            name: "Holding \(quoteId)",
            quoteId: quoteId,
            weight: 0.05,
            worth: Money(value: "500.00", currency: "EUR"),
            price: Money(value: "12.50", currency: "EUR"),
            priceAsOf: "2026-11-12"
        )
    }
    let unpriced = NormalizedHolding(
        name: "Holding 19",
        quoteId: 19,
        weight: 0.01,
        worth: Money(value: "100.00", currency: "EUR"),
        price: nil,
        priceAsOf: ""
    )
    let points = (1...18).flatMap { quoteId in
        ["2026-11-06", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12"].map {
            #"{"quoteId":\#(quoteId),"date":"\#($0)","closeAdjusted":"12.50","closeCurrency":"EUR"}"#
        }
    }
    let history = try! JSONDecoder().decode([PricePoint].self, from: Data("[\(points.joined(separator: ","))]".utf8))
    let snapshot = PortfolioSnapshot(
        asOf: "2026-11-13",
        totalValue: Money(value: "9100.00", currency: "EUR"),
        openHoldings: priced + [unpriced],
        sectors: [],
        assetTypes: [],
        xRayHoldings: nil,
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: history
    )
    return PressureEngine.buildModel(from: snapshot, detailRefreshOutcome: .completed, today: "2026-11-13")
}
