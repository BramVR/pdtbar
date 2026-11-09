import Foundation

// REST response rows decoded straight from PDT's envelopes (ADR-0002 live findings).
// PDT may send money values and ratios as JSON numbers or numeric strings, so every
// numeric field goes through `decodeNumber`/`decodeMoney`. Money stays a decimal string.

struct APIHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
    var symbolId: Int?
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
        case symbolId
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
        symbolId = try? container.decodeIfPresent(Int.self, forKey: .symbolId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeMoneyIfPresent(.currentPriceLocal)
        currentExchangeRate = try? container.decodeNumberIfPresent(.currentExchangeRate)
        currentWorth = try? container.decodeMoneyIfPresent(.currentWorth)
        currentWorthLocal = try container.decodeMoney(.currentWorthLocal)
        portfolioWeight = try container.decodeNumber(.portfolioWeight)
        unrealisedBoughtPriceAverageLocal = try? container.decodeMoneyIfPresent(.unrealisedBoughtPriceAverageLocal)
        unrealisedBoughtPriceTotalLocal = try? container.decodeMoneyIfPresent(.unrealisedBoughtPriceTotalLocal)
        unrealisedBoughtShares = try? container.decodeNumberIfPresent(.unrealisedBoughtShares)
        unrealisedGains = try? container.decodeMoneyIfPresent(.unrealisedGains)
        unrealisedGainsPercentage = try? container.decodeNumberIfPresent(.unrealisedGainsPercentage)
        closedAt = try? container.decodeIfPresent(String.self, forKey: .closedAt)
        isin = try? container.decodeIfPresent(String.self, forKey: .isin)
    }

    var baseHoldingInput: PDTBaseHoldingInput {
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
            isin: isin
        )
    }
}

struct APIDistributionsEnvelope: Decodable {
    struct Body: Decodable {
        var sectors: [APIDistribution]
        var assetTypes: [APIDistribution]
    }

    var data: Body

    var optionalDetailInput: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: data.sectors.map(\.optionalDetailInput),
            assetTypes: data.assetTypes.map(\.optionalDetailInput)
        )
    }
}

struct APIDistribution: Decodable {
    var optionalDetailInput: PDTDistributionInput

    enum CodingKeys: String, CodingKey {
        case categoryName
        case totalValue
        case percentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionalDetailInput = try PDTDistributionInput(
            categoryName: container.decode(String.self, forKey: .categoryName),
            totalValue: container.decodeMoney(.totalValue),
            percentage: container.decodeNumber(.percentage)
        )
    }
}

struct APIXRayHolding: Decodable {
    var optionalDetailInput: PDTXRayHoldingInput

    enum CodingKeys: String, CodingKey {
        case weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionalDetailInput = try PDTXRayHoldingInput(weight: container.decodeNumber(.weight))
    }
}

struct APICalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolId: Int?
    var symbolName: String?

    var optionalDetailInput: PDTCalendarEventInput {
        PDTCalendarEventInput(date: date, type: type, isEstimated: isEstimated, symbolId: symbolId, symbolName: symbolName)
    }
}

struct APIDividend: Decodable {
    var optionalDetailInput: PDTDividendInput

    enum CodingKeys: String, CodingKey {
        case date
        case amount
        case symbolQuoteId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionalDetailInput = try PDTDividendInput(
            date: container.decode(String.self, forKey: .date),
            amount: container.decodeMoney(.amount),
            symbolQuoteId: container.decode(Int.self, forKey: .symbolQuoteId)
        )
    }
}

struct APISymbolQuote: Decodable {
    var id: Int
    var code: String?
}

struct APIPricesBatchEnvelope: Decodable {
    struct Body: Decodable {
        var prices: [[APIPrice]]
    }

    var data: Body
}

struct APIPrice: Decodable {
    var optionalDetailInput: PDTPriceInput

    enum CodingKeys: String, CodingKey {
        case date
        case closeAdjusted
        case closeCurrency
        case symbolQuoteId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionalDetailInput = try PDTPriceInput(
            date: container.decode(String.self, forKey: .date),
            closeAdjusted: container.decodeDecimalString(.closeAdjusted),
            symbolQuoteId: container.decode(Int.self, forKey: .symbolQuoteId),
            closeCurrency: try? container.decodeIfPresent(String.self, forKey: .closeCurrency)
        )
    }
}

private struct APIMoney: Decodable {
    var money: Money

    enum CodingKeys: String, CodingKey {
        case value
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        money = try Money(
            value: container.decodeDecimalString(.value),
            currency: container.decode(String.self, forKey: .currency)
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimalString(_ key: Key) throws -> String {
        if let text = try? decode(String.self, forKey: key) {
            guard posixDecimal(text) != nil else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not a decimal string")
            }
            return text
        }
        // Decimal decodes the JSON number's digits, so money never passes through Double.
        return (try decode(Decimal.self, forKey: key) as NSDecimalNumber).stringValue
    }

    func decodeNumber(_ key: Key) throws -> Double {
        if let text = try? decode(String.self, forKey: key) {
            guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not a numeric string")
            }
            return number
        }
        return try decode(Double.self, forKey: key)
    }

    func decodeMoney(_ key: Key) throws -> Money {
        try decode(APIMoney.self, forKey: key).money
    }

    func decodeNumberIfPresent(_ key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        return try decodeNumber(key)
    }

    func decodeMoneyIfPresent(_ key: Key) throws -> Money? {
        try decodeIfPresent(APIMoney.self, forKey: key)?.money
    }
}
