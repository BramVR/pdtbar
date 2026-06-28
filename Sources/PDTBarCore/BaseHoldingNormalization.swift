import Foundation

public struct PDTBaseHoldingInput: Equatable {
    public var name: String
    public var quoteId: Int
    public var currentPriceDate: String
    public var currentPriceLocal: Money?
    public var currentWorth: Money?
    public var currentWorthLocal: Money
    public var portfolioWeight: Double
    public var unrealisedBoughtPriceAverageLocal: Money?
    public var unrealisedBoughtPriceTotalLocal: Money?
    public var unrealisedBoughtShares: Double?
    public var unrealisedGains: Money?
    public var unrealisedGainsPercentage: Double?
    public var closedAt: String?
    public var copyableIdentifier: String?
    public var isin: String?

    public init(
        name: String,
        quoteId: Int,
        currentPriceDate: String,
        currentPriceLocal: Money?,
        currentWorth: Money? = nil,
        currentWorthLocal: Money,
        portfolioWeight: Double,
        unrealisedBoughtPriceAverageLocal: Money? = nil,
        unrealisedBoughtPriceTotalLocal: Money? = nil,
        unrealisedBoughtShares: Double? = nil,
        unrealisedGains: Money? = nil,
        unrealisedGainsPercentage: Double? = nil,
        closedAt: String?,
        copyableIdentifier: String? = nil,
        isin: String? = nil
    ) {
        self.name = name
        self.quoteId = quoteId
        self.currentPriceDate = currentPriceDate
        self.currentPriceLocal = currentPriceLocal
        self.currentWorth = currentWorth
        self.currentWorthLocal = currentWorthLocal
        self.portfolioWeight = portfolioWeight
        self.unrealisedBoughtPriceAverageLocal = unrealisedBoughtPriceAverageLocal
        self.unrealisedBoughtPriceTotalLocal = unrealisedBoughtPriceTotalLocal
        self.unrealisedBoughtShares = unrealisedBoughtShares
        self.unrealisedGains = unrealisedGains
        self.unrealisedGainsPercentage = unrealisedGainsPercentage
        self.closedAt = closedAt
        self.copyableIdentifier = copyableIdentifier
        self.isin = isin
    }
}

public struct PDTBaseHoldingNormalization: Equatable {
    public var openHoldings: [NormalizedHolding]
    public var totalValue: Money

    public init(openHoldings: [NormalizedHolding], totalValue: Money) {
        self.openHoldings = openHoldings
        self.totalValue = totalValue
    }
}

public enum PDTBaseHoldingNormalizer {
    public static func normalize(
        _ holdings: [PDTBaseHoldingInput],
        currency: String,
        reportedTotalValue: Money? = nil
    ) -> PDTBaseHoldingNormalization {
        let openHoldings = holdings.compactMap(normalizedHolding)
        let summedCurrency = openHoldings.first?.worth.currency ?? currency
        let totalValue = validMoney(reportedTotalValue)
            ?? sumWorth(openHoldings, currency: summedCurrency)
        return PDTBaseHoldingNormalization(openHoldings: openHoldings, totalValue: totalValue)
    }

    public static func safePublicIdentifier(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 24,
              trimmed.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return trimmed
    }

    public static func safeISIN(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.range(of: #"^[A-Z]{2}[A-Z0-9]{9}[0-9]$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return trimmed
    }

    public static func validMoney(_ money: Money?) -> Money? {
        guard let money,
              !money.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              posixDecimal(money.value) != nil
        else {
            return nil
        }
        return money
    }

    public static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }
        return value
    }

    public static func averageBuyPrice(explicit: Money?, total: Money?, shares: Double?) -> Money? {
        if let explicit = validMoney(explicit) {
            return explicit
        }
        guard let total = validMoney(total),
              let shares = finite(shares),
              shares > 0,
              let totalValue = posixDecimal(total.value),
              let shareValue = posixDecimal(String(shares))
        else {
            return nil
        }
        let average = totalValue / shareValue
        return Money(value: canonicalDecimalString(average, places: 4), currency: total.currency)
    }

    private static func normalizedHolding(_ holding: PDTBaseHoldingInput) -> NormalizedHolding? {
        guard holding.closedAt == nil,
              let worth = validMoney(holding.currentWorthLocal),
              worth.isPositive,
              holding.currentWorth.map({ validMoney($0) != nil && $0.isPositive }) ?? true
        else {
            return nil
        }
        return NormalizedHolding(
            name: holding.name,
            quoteId: holding.quoteId,
            weight: holding.portfolioWeight,
            worth: worth,
            price: validMoney(holding.currentPriceLocal),
            priceAsOf: dayPrefix(holding.currentPriceDate),
            copyableIdentifier: safePublicIdentifier(holding.copyableIdentifier),
            isin: safeISIN(holding.isin),
            averageBuyPrice: averageBuyPrice(
                explicit: holding.unrealisedBoughtPriceAverageLocal,
                total: holding.unrealisedBoughtPriceTotalLocal,
                shares: holding.unrealisedBoughtShares
            ),
            gainLoss: validMoney(holding.unrealisedGains),
            gainLossPercentage: finite(holding.unrealisedGainsPercentage)
        )
    }

    private static func sumWorth(_ holdings: [NormalizedHolding], currency: String) -> Money {
        let total = holdings.reduce(Decimal(0)) { partial, holding in
            partial + (posixDecimal(holding.worth.value) ?? 0)
        }
        return Money(value: canonicalDecimalString(total, places: 2), currency: currency)
    }

    private static func posixDecimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func dayPrefix(_ dateTime: String) -> String {
        String(dateTime.prefix(10))
    }

    private static func canonicalDecimalString(_ value: Decimal, places: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        return formatter.string(from: value as NSDecimalNumber) ?? (value as NSDecimalNumber).stringValue
    }
}

private extension Money {
    var isPositive: Bool {
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            return false
        }
        return amount > 0
    }
}
