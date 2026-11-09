import Foundation

public struct PDTAPIDataSourceOptions: Equatable, Sendable {
    public var includeDistributions: Bool
    public var includeXRayHoldings: Bool
    public var includeIncomeEvents: Bool
    public var includeDividends: Bool
    public var includeQuoteCodes: Bool
    public var includePriceSeries: Bool

    public init(
        includeDistributions: Bool = true,
        includeXRayHoldings: Bool = true,
        includeIncomeEvents: Bool = true,
        includeDividends: Bool = true,
        includeQuoteCodes: Bool = true,
        includePriceSeries: Bool = true
    ) {
        self.includeDistributions = includeDistributions
        self.includeXRayHoldings = includeXRayHoldings
        self.includeIncomeEvents = includeIncomeEvents
        self.includeDividends = includeDividends
        self.includeQuoteCodes = includeQuoteCodes
        self.includePriceSeries = includePriceSeries
    }

    public static var firstFetch: PDTAPIDataSourceOptions {
        PDTAPIDataSourceOptions(
            includeDistributions: false,
            includeXRayHoldings: false,
            includeIncomeEvents: false,
            includeDividends: false,
            includeQuoteCodes: false,
            includePriceSeries: false
        )
    }
}

/// `PortfolioDataSource` over the read-only PDT REST API (ADR-0002). Holdings are
/// required; every other facet is optional and degrades the snapshot on failure.
/// Requests run sequentially in a fixed order.
public struct PDTAPIDataSource: PortfolioDataSource {
    public var client: PDTAPIClient
    public var options: PDTAPIDataSourceOptions
    public var onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)?
    private let now: @Sendable () -> Date

    public init(
        client: PDTAPIClient,
        options: PDTAPIDataSourceOptions = PDTAPIDataSourceOptions(),
        onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.options = options
        self.onOptionalFacetFailure = onOptionalFacetFailure
        self.now = now
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        let snapshotAsOf = asOf ?? dayString(from: now())
        let incomeEnd = dayString(snapshotAsOf, addingDays: 30)
        let rows: [APIHolding] = try client.getAll(.holdings())

        var degraded = false
        var setupUnavailable = false
        func optionalFacet<T>(
            _ enabled: Bool,
            _ resource: PDTAPIResource,
            phase: BackgroundDetailRefreshPhase,
            fetch: () throws -> T
        ) -> T? {
            guard enabled, !setupUnavailable else {
                return nil
            }
            do {
                return try fetch()
            } catch {
                degraded = true
                let diagnostic = PDTDetailRefreshFailureDiagnostic(
                    toolName: resource.path,
                    phase: phase,
                    attemptCount: 1,
                    category: pdtDetailRefreshFailureCategory(for: error),
                    argumentShape: resource.argumentShape
                )
                onOptionalFacetFailure?(diagnostic)
                setupUnavailable = diagnostic.category.indicatesUnavailableSetup
                return nil
            }
        }

        let distributions = optionalFacet(options.includeDistributions, .distributions, phase: .allocation) {
            try decodeAPIResponse(APIDistributionsEnvelope.self, from: client.get(.distributions)).optionalDetailInput
        }
        let xRayHoldings = optionalFacet(options.includeXRayHoldings, .xRay, phase: .xRay) {
            try client.getAll(.xRay, as: APIXRayHolding.self).map(\.optionalDetailInput)
        }
        let calendarResource = PDTAPIResource.calendarEvents(dateFrom: snapshotAsOf, dateTo: incomeEnd)
        let calendarEvents = optionalFacet(options.includeIncomeEvents, calendarResource, phase: .income) {
            try client.getAll(calendarResource, as: APICalendarEvent.self).map(\.optionalDetailInput)
        }
        let dividendsResource = PDTAPIResource.dividends(
            dateFrom: dayString(snapshotAsOf, addingDays: -370),
            dateTo: incomeEnd
        )
        let dividends = optionalFacet(options.includeDividends, dividendsResource, phase: .income) {
            try client.getAll(dividendsResource, as: APIDividend.self).map(\.optionalDetailInput)
        }

        let holdingInputs = rows.map(\.baseHoldingInput)
        let currency = PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR")
        let openQuoteIDs = PDTBaseHoldingNormalizer.normalize(holdingInputs, currency: currency)
            .openHoldings.map(\.quoteId)
        let symbolIDsByQuoteID = Dictionary(
            rows.compactMap { row in row.symbolId.map { (row.symbolQuoteId, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        let codesByQuoteID = optionalFacet(
            options.includeQuoteCodes,
            .symbolQuotes(symbolId: 0),
            phase: .income
        ) {
            try quoteCodes(for: openQuoteIDs, symbolIDsByQuoteID: symbolIDsByQuoteID)
        }
        let priceRows = optionalFacet(
            options.includePriceSeries,
            .pricesBatch(symbolQuoteIds: [], dateFrom: "", dateTo: ""),
            phase: .priceHistory
        ) {
            try prices(for: openQuoteIDs, asOf: snapshotAsOf)
        }

        return PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: currency,
                holdings: holdingInputs,
                symbolQuotes: openQuoteIDs.compactMap { quoteId in
                    symbolIDsByQuoteID[quoteId].map { symbolId in
                        PDTSymbolQuoteNormalizationInput(
                            quoteId: quoteId,
                            symbolId: symbolId,
                            copyableIdentifier: codesByQuoteID?[quoteId]
                        )
                    }
                },
                distributions: distributions,
                xRayHoldings: xRayHoldings,
                calendarEvents: calendarEvents ?? [],
                dividends: dividends ?? [],
                priceRows: priceRows ?? [],
                latestDetailFillOutcome: degraded ? .degraded : nil
            )
        )
    }

    private func quoteCodes(for quoteIDs: [Int], symbolIDsByQuoteID: [Int: Int]) throws -> [Int: String] {
        var codes: [Int: String] = [:]
        var quotesBySymbolID: [Int: [APISymbolQuote]] = [:]
        for quoteId in quoteIDs {
            guard let symbolId = symbolIDsByQuoteID[quoteId] else {
                continue
            }
            if quotesBySymbolID[symbolId] == nil {
                quotesBySymbolID[symbolId] = try client.getAll(.symbolQuotes(symbolId: symbolId))
            }
            let code = quotesBySymbolID[symbolId]?.first { $0.id == quoteId }?.code
            codes[quoteId] = PDTBaseHoldingNormalizer.safePublicIdentifier(code)
        }
        return codes
    }

    private func prices(for quoteIDs: [Int], asOf: String) throws -> [PDTPriceInput] {
        let dateFrom = dayString(asOf, addingDays: -7)
        return try stride(from: 0, to: quoteIDs.count, by: PDTAPIResource.pricesBatchLimit).flatMap { start in
            let chunk = Array(quoteIDs[start..<min(start + PDTAPIResource.pricesBatchLimit, quoteIDs.count)])
            let body = try client.get(.pricesBatch(symbolQuoteIds: chunk, dateFrom: dateFrom, dateTo: asOf))
            return try decodeAPIResponse(APIPricesBatchEnvelope.self, from: body).data.prices.joined().map(\.optionalDetailInput)
        }
    }
}

extension PDTAPIResource {
    /// Query names only, never values, for redacted refresh diagnostics.
    var argumentShape: [String] {
        let paging: [String] = switch pagination {
        case .none: []
        case .pages: ["page", "perPage"]
        case .offset: ["limit", "offset"]
        }
        let names = switch self {
        case .symbolQuotes: ["symbolId"]
        case .pricesBatch: ["symbolQuoteIds[]", "dateFrom", "dateTo"]
        default: queryItems.map(\.name)
        }
        return names + paging
    }
}

func decodeAPIResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw PDTAPIError.invalidResponse
    }
}
