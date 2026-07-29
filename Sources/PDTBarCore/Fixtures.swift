import Foundation

public struct PDTFixtureDataSource: PortfolioDataSource, PortfolioPriorSnapshotDataSource {
    public var fixture: URL

    public init(fixture: URL) {
        self.fixture = fixture
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        try Self.snapshot(from: fixture, asOf: asOf)
    }

    public func priorSnapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        try Self.priorSnapshot(from: fixture, asOf: asOf)
    }

    public static func snapshot(from url: URL, asOf: String? = nil) throws -> PortfolioSnapshot {
        let payload = try JSONDecoder().decode(PDTFixturePayload.self, from: Data(contentsOf: url))
        return makeSnapshot(
            from: payload,
            holdings: payload.primaryHoldings,
            asOf: asOf ?? payload.meta.asOf
        )
    }

    public static func priorSnapshot(from url: URL, asOf: String? = nil) throws -> PortfolioSnapshot {
        let payload = try JSONDecoder().decode(PDTFixturePayload.self, from: Data(contentsOf: url))
        guard let prior = payload.getPortfolioPriorSnapshot else {
            throw FixtureError.missingPriorSnapshot
        }
        return makeSnapshot(
            from: payload,
            holdings: prior.holdings,
            asOf: asOf ?? prior.query?.date ?? payload.meta.asOf
        )
    }

    private static func makeSnapshot(
        from payload: PDTFixturePayload,
        holdings rawHoldings: [FixtureHolding],
        asOf: String
    ) -> PortfolioSnapshot {
        PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: asOf,
                currency: payload.meta.portfolioCurrency,
                holdings: rawHoldings.map { $0.baseHoldingInput(copyableIdentifier: nil) },
                reportedTotalValue: payload.meta.portfolioCurrentWorthEUR.map {
                    Money(value: $0, currency: payload.meta.portfolioCurrency)
                },
                symbolQuotes: payload.symbolQuotes.map(\.snapshotNormalizationInput),
                distributions: payload.getPortfolioDistributions?.optionalDetailInput,
                xRayHoldings: payload.listXRayHoldings?.items.map(\.optionalDetailInput),
                calendarEvents: payload.listCalendarEvents?.data.map(\.optionalDetailInput) ?? [],
                dividends: payload.listDividends?.data.map(\.optionalDetailInput) ?? [],
                priceRows: payload.listSymbolPrices?.data.map(\.optionalDetailInput) ?? [],
                performance: PortfolioPerformanceSummary.build(
                    totalGainPercentage: payload.getPortfolioGains?.totalGainsPercentage,
                    periodStart: payload.getPortfolioPerformance?.oldestPortfolioDate,
                    periodEnd: payload.getPortfolioPerformance?.latestPortfolioDate
                )
            )
        )
    }
}

public enum FixtureError: Error {
    case missingPriorSnapshot
}

public func stableJSONData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
}

private struct PDTFixturePayload: Decodable {
    var meta: FixtureMeta
    var getPortfolioHoldings: HoldingsEnvelope?
    var getPortfolioHoldingsCurrent: HoldingsEnvelope?
    var getPortfolioPriorSnapshot: HoldingsEnvelope?
    var getPortfolioDistributions: DistributionsEnvelope?
    var listXRayHoldings: XRayHoldingsEnvelope?
    var listCalendarEvents: CalendarEventsEnvelope?
    var listDividends: DividendsEnvelope?
    var listSymbolPrices: PricesEnvelope?
    var getSymbolQuote: SymbolQuoteEnvelope?
    var getSymbolQuotes: [SymbolQuoteEnvelope]?
    var getPortfolioPerformance: LivePortfolioPerformanceEnvelope?
    var getPortfolioGains: LivePortfolioGainsEnvelope?

    var symbolQuotes: [SymbolQuoteEnvelope] {
        (getSymbolQuote.map { [$0] } ?? []) + (getSymbolQuotes ?? [])
    }

    var primaryHoldings: [FixtureHolding] {
        getPortfolioHoldings?.holdings
            ?? getPortfolioHoldingsCurrent?.holdings
            ?? getPortfolioPriorSnapshot?.holdings
            ?? []
    }

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case getPortfolioHoldings
        case getPortfolioHoldingsCurrent
        case getPortfolioPriorSnapshot
        case getPortfolioDistributions
        case listXRayHoldings
        case listCalendarEvents
        case listDividends
        case listSymbolPrices
        case getSymbolQuote
        case getSymbolQuotes
        case getPortfolioPerformance
        case getPortfolioGains
    }
}

private struct FixtureMeta: Decodable {
    var asOf: String
    var portfolioCurrency: String
    var portfolioCurrentWorthEUR: String?
}

private struct HoldingsEnvelope: Decodable {
    var query: FixtureQuery?
    var holdings: [FixtureHolding]

    enum CodingKeys: String, CodingKey {
        case query = "_query"
        case holdings
    }
}

private struct FixtureQuery: Decodable {
    var date: String?
}

private struct FixtureHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
    var currentPriceDate: String
    var currentPriceLocal: Money?
    var currentExchangeRate: Double?
    var currentWorth: Money?
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var unrealisedBoughtPriceAverageLocal: Money?
    var unrealisedBoughtPriceTotalLocal: Money?
    var unrealisedBoughtShares: Double?
    var unrealisedGains: Money?
    var unrealisedGainsPercentage: Double?
    var closedAt: String?
    var isin: String?

    enum CodingKeys: String, CodingKey {
        case symbolName
        case symbolQuoteId
        case currentPriceDate
        case currentPriceLocal
        case currentExchangeRate
        case currentWorth
        case currentWorthLocal
        case portfolioWeight
        case unrealisedBoughtPriceAverageLocal
        case unrealisedBoughtPriceTotalLocal
        case unrealisedBoughtShares
        case unrealisedGains
        case unrealisedGainsPercentage
        case closedAt
        case isin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentExchangeRate = try? container.decodeIfPresent(Double.self, forKey: .currentExchangeRate)
        currentWorth = try? container.decodeIfPresent(Money.self, forKey: .currentWorth)
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceAverageLocal
        )
        unrealisedBoughtPriceTotalLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceTotalLocal
        )
        unrealisedBoughtShares = try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares)
        unrealisedGains = try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains)
        unrealisedGainsPercentage = try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
    }
}

private extension FixtureHolding {
    func baseHoldingInput(copyableIdentifier: String?) -> PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: symbolName,
            quoteId: symbolQuoteId,
            currentPriceDate: currentPriceDate,
            currentPriceLocal: currentPriceLocal,
            currentExchangeRate: currentExchangeRate,
            currentWorth: currentWorth,
            currentWorthLocal: currentWorthLocal,
            portfolioWeight: portfolioWeight,
            unrealisedBoughtPriceAverageLocal: unrealisedBoughtPriceAverageLocal,
            unrealisedBoughtPriceTotalLocal: unrealisedBoughtPriceTotalLocal,
            unrealisedBoughtShares: unrealisedBoughtShares,
            unrealisedGains: unrealisedGains,
            unrealisedGainsPercentage: unrealisedGainsPercentage,
            closedAt: closedAt,
            copyableIdentifier: copyableIdentifier,
            isin: isin
        )
    }
}

private struct DistributionsEnvelope: Decodable {
    var sectors: [FixtureDistribution]?
    var assetTypes: [FixtureDistribution]?

    var optionalDetailInput: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: (sectors ?? []).map(\.optionalDetailInput),
            assetTypes: (assetTypes ?? []).map(\.optionalDetailInput)
        )
    }
}

private struct FixtureDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var optionalDetailInput: PDTDistributionInput {
        PDTDistributionInput(categoryName: categoryName, totalValue: totalValue, percentage: percentage)
    }
}

private struct CalendarEventsEnvelope: Decodable {
    var data: [FixtureCalendarEvent]
}

private struct FixtureCalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolId: Int?
    var symbolName: String?

    var optionalDetailInput: PDTCalendarEventInput {
        PDTCalendarEventInput(
            date: date,
            type: type,
            isEstimated: isEstimated,
            symbolId: symbolId,
            symbolName: symbolName
        )
    }
}

private struct DividendsEnvelope: Decodable {
    var data: [FixtureDividend]
}

private struct FixtureDividend: Decodable {
    var date: String
    var amount: Money
    var symbolQuoteId: Int

    var optionalDetailInput: PDTDividendInput {
        PDTDividendInput(date: date, amount: amount, symbolQuoteId: symbolQuoteId)
    }
}

private struct SymbolQuoteEnvelope: Decodable {
    var id: Int
    var code: String?
    var symbolId: Int
}

private extension SymbolQuoteEnvelope {
    var snapshotNormalizationInput: PDTSymbolQuoteNormalizationInput {
        PDTSymbolQuoteNormalizationInput(
            quoteId: id,
            symbolId: symbolId,
            copyableIdentifier: code
        )
    }
}


private struct PricesEnvelope: Decodable {
    var data: [FixturePrice]
}

private struct FixturePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var closeCurrency: String?
    var symbolQuoteId: Int

    var optionalDetailInput: PDTPriceInput {
        PDTPriceInput(date: date, closeAdjusted: closeAdjusted, symbolQuoteId: symbolQuoteId, closeCurrency: closeCurrency)
    }
}

