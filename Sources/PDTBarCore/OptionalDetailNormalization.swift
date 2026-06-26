import Foundation

public struct PDTOptionalDistributionsInput: Equatable {
    public var sectors: [PDTDistributionInput]
    public var assetTypes: [PDTDistributionInput]

    public init(sectors: [PDTDistributionInput], assetTypes: [PDTDistributionInput]) {
        self.sectors = sectors
        self.assetTypes = assetTypes
    }
}

public struct PDTDistributionInput: Equatable {
    public var categoryName: String
    public var totalValue: Money
    public var percentage: Double

    public init(categoryName: String, totalValue: Money, percentage: Double) {
        self.categoryName = categoryName
        self.totalValue = totalValue
        self.percentage = percentage
    }
}

public struct PDTXRayHoldingInput: Equatable {
    public var weight: Double

    public init(weight: Double) {
        self.weight = weight
    }
}

public struct PDTCalendarEventInput: Equatable {
    public var date: String
    public var type: String
    public var isEstimated: Bool
    public var symbolId: Int?
    public var symbolName: String?

    public init(date: String, type: String, isEstimated: Bool, symbolId: Int?, symbolName: String?) {
        self.date = date
        self.type = type
        self.isEstimated = isEstimated
        self.symbolId = symbolId
        self.symbolName = symbolName
    }
}

public struct PDTDividendInput: Equatable {
    public var date: String
    public var amount: Money
    public var symbolQuoteId: Int

    public init(date: String, amount: Money, symbolQuoteId: Int) {
        self.date = date
        self.amount = amount
        self.symbolQuoteId = symbolQuoteId
    }
}

public struct PDTPriceInput: Equatable {
    public var date: String
    public var closeAdjusted: String
    public var symbolQuoteId: Int

    public init(date: String, closeAdjusted: String, symbolQuoteId: Int) {
        self.date = date
        self.closeAdjusted = closeAdjusted
        self.symbolQuoteId = symbolQuoteId
    }
}

public struct PDTOptionalDetailNormalization: Equatable {
    public var sectors: [DistributionSummary]
    public var assetTypes: [DistributionSummary]
    public var xRayHoldings: [XRayHoldingSummary]?
    public var incomeEvents: [IncomeEventSummary]
    public var dividendRowCount: Int
    public var priceSeries: [PricePoint]

    public init(
        sectors: [DistributionSummary],
        assetTypes: [DistributionSummary],
        xRayHoldings: [XRayHoldingSummary]?,
        incomeEvents: [IncomeEventSummary],
        dividendRowCount: Int,
        priceSeries: [PricePoint]
    ) {
        self.sectors = sectors
        self.assetTypes = assetTypes
        self.xRayHoldings = xRayHoldings
        self.incomeEvents = incomeEvents
        self.dividendRowCount = dividendRowCount
        self.priceSeries = priceSeries
    }
}

public enum PDTOptionalDetailNormalizer {
    public static func normalize(
        distributions: PDTOptionalDistributionsInput? = nil,
        xRayHoldings: [PDTXRayHoldingInput]? = nil,
        calendarEvents: [PDTCalendarEventInput] = [],
        dividends: [PDTDividendInput] = [],
        quoteIDsBySymbolID: [Int: Int] = [:],
        priceRows: [PDTPriceInput] = []
    ) -> PDTOptionalDetailNormalization {
        let dividendsByQuoteID = Dictionary(grouping: dividends, by: \.symbolQuoteId)
        return PDTOptionalDetailNormalization(
            sectors: distributions?.sectors.map(normalizedDistribution) ?? [],
            assetTypes: distributions?.assetTypes.map(normalizedDistribution) ?? [],
            xRayHoldings: xRayHoldings?.map { XRayHoldingSummary(weight: normalizedXRayPortfolioWeight($0.weight)) },
            incomeEvents: calendarEvents
                .filter { $0.type != "no-events-today" }
                .map {
                    let quoteId = $0.symbolId.flatMap { quoteIDsBySymbolID[$0] }
                    let amount = $0.type == "ex-dividend" && !$0.isEstimated
                        ? latestDividendAmount(for: quoteId, dividendsByQuoteID: dividendsByQuoteID)
                        : nil
                    return IncomeEventSummary(
                        date: $0.date,
                        kind: $0.type,
                        symbolName: $0.symbolName ?? "Portfolio",
                        estimated: $0.isEstimated,
                        symbolId: $0.symbolId,
                        quoteId: quoteId,
                        amount: amount,
                        priorAmount: nil,
                        changePercent: nil
                    )
                },
            dividendRowCount: dividends.count,
            priceSeries: priceRows.map {
                PricePoint(
                    quoteId: $0.symbolQuoteId,
                    date: $0.date,
                    closeAdjusted: $0.closeAdjusted
                )
            }
        )
    }

    public static func normalizeDistributions(_ distributions: PDTOptionalDistributionsInput) -> (
        sectors: [DistributionSummary],
        assetTypes: [DistributionSummary]
    ) {
        let normalized = normalize(distributions: distributions)
        return (normalized.sectors, normalized.assetTypes)
    }

    public static func normalizeXRayHoldings(_ holdings: [PDTXRayHoldingInput]) -> [XRayHoldingSummary] {
        normalize(xRayHoldings: holdings).xRayHoldings ?? []
    }

    public static func normalizeIncomeEvents(
        calendarEvents: [PDTCalendarEventInput],
        dividends: [PDTDividendInput],
        quoteIDsBySymbolID: [Int: Int]
    ) -> (events: [IncomeEventSummary], dividendRowCount: Int) {
        let normalized = normalize(
            calendarEvents: calendarEvents,
            dividends: dividends,
            quoteIDsBySymbolID: quoteIDsBySymbolID
        )
        return (normalized.incomeEvents, normalized.dividendRowCount)
    }

    public static func normalizePriceSeries(_ prices: [PDTPriceInput]) -> [PricePoint] {
        normalize(priceRows: prices).priceSeries
    }

    private static func normalizedDistribution(_ distribution: PDTDistributionInput) -> DistributionSummary {
        DistributionSummary(
            name: distribution.categoryName,
            percentage: distribution.percentage,
            totalValue: distribution.totalValue
        )
    }

    private static func normalizedXRayPortfolioWeight(_ value: Double) -> Double {
        value / 100.0
    }

    private static func latestDividendAmount(
        for quoteId: Int?,
        dividendsByQuoteID: [Int: [PDTDividendInput]]
    ) -> Money? {
        guard let quoteId else {
            return nil
        }
        let dividends = dividendsByQuoteID[quoteId] ?? []
        guard !dividends.contains(where: { (Decimal(string: $0.amount.value) ?? 0) < 0 }) else {
            return nil
        }
        return dividends
            .filter {
                guard let amount = Decimal(string: $0.amount.value),
                      amount > 0
                else { return false }
                return true
            }
            .sorted { $0.date > $1.date }
            .first?
            .amount
    }
}
