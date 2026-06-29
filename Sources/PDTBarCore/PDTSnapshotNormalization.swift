public struct PDTSymbolQuoteNormalizationInput: Equatable {
    public var quoteId: Int
    public var symbolId: Int
    public var copyableIdentifier: String?
    public var isin: String?

    public init(
        quoteId: Int,
        symbolId: Int,
        copyableIdentifier: String? = nil,
        isin: String? = nil
    ) {
        self.quoteId = quoteId
        self.symbolId = symbolId
        self.copyableIdentifier = copyableIdentifier
        self.isin = isin
    }
}

public struct PDTSnapshotNormalizationInput: Equatable {
    public var asOf: String
    public var currency: String
    public var holdings: [PDTBaseHoldingInput]
    public var reportedTotalValue: Money?
    public var symbolQuotes: [PDTSymbolQuoteNormalizationInput]
    public var distributions: PDTOptionalDistributionsInput?
    public var xRayHoldings: [PDTXRayHoldingInput]?
    public var calendarEvents: [PDTCalendarEventInput]
    public var dividends: [PDTDividendInput]
    public var priceRows: [PDTPriceInput]
    public var latestCompleteDetailFillAsOf: String?
    public var latestDetailFillOutcome: PDTBackgroundDetailRefreshOutcome?

    public init(
        asOf: String,
        currency: String,
        holdings: [PDTBaseHoldingInput],
        reportedTotalValue: Money? = nil,
        symbolQuotes: [PDTSymbolQuoteNormalizationInput] = [],
        distributions: PDTOptionalDistributionsInput? = nil,
        xRayHoldings: [PDTXRayHoldingInput]? = nil,
        calendarEvents: [PDTCalendarEventInput] = [],
        dividends: [PDTDividendInput] = [],
        priceRows: [PDTPriceInput] = [],
        latestCompleteDetailFillAsOf: String? = nil,
        latestDetailFillOutcome: PDTBackgroundDetailRefreshOutcome? = nil
    ) {
        self.asOf = asOf
        self.currency = currency
        self.holdings = holdings
        self.reportedTotalValue = reportedTotalValue
        self.symbolQuotes = symbolQuotes
        self.distributions = distributions
        self.xRayHoldings = xRayHoldings
        self.calendarEvents = calendarEvents
        self.dividends = dividends
        self.priceRows = priceRows
        self.latestCompleteDetailFillAsOf = latestCompleteDetailFillAsOf
        self.latestDetailFillOutcome = latestDetailFillOutcome
    }
}

public enum PDTSnapshotNormalizer {
    public static func normalize(_ input: PDTSnapshotNormalizationInput) -> PortfolioSnapshot {
        let symbolQuotesByQuoteID = input.symbolQuotes.reduce(into: [Int: PDTSymbolQuoteNormalizationInput]()) {
            symbolQuotesByQuoteID, symbolQuote in
            symbolQuotesByQuoteID[symbolQuote.quoteId] = symbolQuote
        }
        let holdings = input.holdings.map { holding in
            enrichedHolding(holding, with: symbolQuotesByQuoteID[holding.quoteId])
        }
        let baseNormalization = PDTBaseHoldingNormalizer.normalize(
            holdings,
            currency: input.currency,
            reportedTotalValue: input.reportedTotalValue
        )
        let optionalDetails = PDTOptionalDetailNormalizer.normalize(
            distributions: input.distributions,
            xRayHoldings: input.xRayHoldings,
            calendarEvents: input.calendarEvents,
            dividends: input.dividends,
            quoteIDsBySymbolID: quoteIDsBySymbolID(from: input.symbolQuotes),
            priceRows: input.priceRows
        )

        return PortfolioSnapshot(
            asOf: input.asOf,
            totalValue: baseNormalization.totalValue,
            openHoldings: baseNormalization.openHoldings,
            sectors: optionalDetails.sectors,
            assetTypes: optionalDetails.assetTypes,
            xRayHoldings: optionalDetails.xRayHoldings,
            incomeEvents: optionalDetails.incomeEvents,
            dividendRowCount: optionalDetails.dividendRowCount,
            priceSeries: optionalDetails.priceSeries,
            latestCompleteDetailFillAsOf: input.latestCompleteDetailFillAsOf,
            latestDetailFillOutcome: input.latestDetailFillOutcome
        )
    }

    private static func enrichedHolding(
        _ holding: PDTBaseHoldingInput,
        with symbolQuote: PDTSymbolQuoteNormalizationInput?
    ) -> PDTBaseHoldingInput {
        guard let symbolQuote else {
            return holding
        }
        var enriched = holding
        enriched.copyableIdentifier = symbolQuote.copyableIdentifier ?? enriched.copyableIdentifier
        enriched.isin = symbolQuote.isin ?? enriched.isin
        return enriched
    }

    private static func quoteIDsBySymbolID(
        from symbolQuotes: [PDTSymbolQuoteNormalizationInput]
    ) -> [Int: Int] {
        symbolQuotes.reduce(into: [Int: Int]()) { quoteIDsBySymbolID, symbolQuote in
            quoteIDsBySymbolID[symbolQuote.symbolId] = symbolQuote.quoteId
        }
    }
}
