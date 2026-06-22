import Foundation

public struct Money: Equatable, Sendable {
    public var decimal: Decimal
    public var currency: String

    public init(decimal: Decimal, currency: String) {
        self.decimal = decimal
        self.currency = currency
    }
}

public struct PortfolioFacts: Equatable, Sendable {
    public var baseCurrency: String?
    public var liveHoldings: [PortfolioHoldingFact]
    public var freshness: [EODFreshnessFact]

    public init(baseCurrency: String?, liveHoldings: [PortfolioHoldingFact], freshness: [EODFreshnessFact]) {
        self.baseCurrency = baseCurrency
        self.liveHoldings = liveHoldings
        self.freshness = freshness
    }
}

public struct PortfolioHoldingFact: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var currentWorth: Money
    public var portfolioWeightFraction: Decimal
    public var eodDate: String?

    public var portfolioWeightPercent: Decimal {
        portfolioWeightFraction * Decimal(100)
    }

    public init(
        ticker: String,
        name: String?,
        currentWorth: Money,
        portfolioWeightFraction: Decimal,
        eodDate: String?
    ) {
        self.ticker = ticker
        self.name = name
        self.currentWorth = currentWorth
        self.portfolioWeightFraction = portfolioWeightFraction
        self.eodDate = eodDate
    }
}

public struct EODFreshnessFact: Equatable, Sendable {
    public var source: String
    public var date: String

    public init(source: String, date: String) {
        self.source = source
        self.date = date
    }
}

public enum PDTContractError: Error, Equatable, Sendable {
    case invalidDecimal(String)
    case missingPortfolioWeight(String)
}

public struct PDTContractAdapter: Sendable {
    public init() {}

    public func ingest(_ data: Data) throws -> PortfolioFacts {
        let decoded = try JSONDecoder().decode(PDTPayload.self, from: data)
        let portfolio = decoded.portfolio ?? decoded.rootPortfolio

        let liveHoldings = try portfolio.holdings.compactMap { holding -> PortfolioHoldingFact? in
            let currentWorth = try holding.currentWorth.money()
            guard currentWorth.decimal != Decimal(0) else { return nil }
            guard let portfolioWeight = holding.portfolioWeight else {
                throw PDTContractError.missingPortfolioWeight(holding.ticker)
            }

            return PortfolioHoldingFact(
                ticker: holding.ticker,
                name: holding.name,
                currentWorth: currentWorth,
                portfolioWeightFraction: try portfolioWeight.decimal(),
                eodDate: holding.eodDate
            )
        }

        return PortfolioFacts(
            baseCurrency: portfolio.baseCurrency,
            liveHoldings: liveHoldings,
            freshness: portfolio.freshnessFacts()
        )
    }
}

private struct PDTPayload: Decodable {
    var portfolio: PDTPortfolio?
    var rootPortfolio: PDTPortfolio

    enum CodingKeys: String, CodingKey {
        case portfolio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolio = try container.decodeIfPresent(PDTPortfolio.self, forKey: .portfolio)
        rootPortfolio = try PDTPortfolio(from: decoder)
    }
}

private struct PDTPortfolio: Decodable {
    var baseCurrency: String?
    var eodDate: String?
    var asOfDate: String?
    var date: String?
    var holdings: [PDTHolding] = []

    enum CodingKeys: String, CodingKey {
        case baseCurrency
        case eodDate
        case asOfDate
        case date
        case holdings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCurrency = try container.decodeIfPresent(String.self, forKey: .baseCurrency)
        eodDate = try container.decodeIfPresent(String.self, forKey: .eodDate)
        asOfDate = try container.decodeIfPresent(String.self, forKey: .asOfDate)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        holdings = try container.decodeIfPresent([PDTHolding].self, forKey: .holdings) ?? []
    }
}

private struct PDTHolding: Decodable {
    var ticker: String
    var name: String?
    var currentWorth: PDTMoney
    var portfolioWeight: PDTDecimal?
    var eodDate: String?
    var asOfDate: String?
    var date: String?
}

private struct PDTMoney: Decodable {
    var value: PDTDecimal
    var currency: String

    func money() throws -> Money {
        Money(decimal: try value.decimal(), currency: currency)
    }
}

private enum PDTDecimal: Decodable {
    case string(String)
    case number(Decimal)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let decimal = try? container.decode(Decimal.self) {
            self = .number(decimal)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected decimal string or number")
    }

    func decimal() throws -> Decimal {
        switch self {
        case let .string(value):
            guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
                throw PDTContractError.invalidDecimal(value)
            }
            return decimal
        case let .number(value):
            return value
        }
    }
}

private extension PDTPortfolio {
    func freshnessFacts() -> [EODFreshnessFact] {
        var facts: [EODFreshnessFact] = []
        appendFreshness(&facts, source: "portfolio.eodDate", date: eodDate)
        appendFreshness(&facts, source: "portfolio.asOfDate", date: asOfDate)
        appendFreshness(&facts, source: "portfolio.date", date: date)

        for holding in holdings {
            let prefix = "holding.\(holding.ticker)"
            appendFreshness(&facts, source: "\(prefix).eodDate", date: holding.eodDate)
            appendFreshness(&facts, source: "\(prefix).asOfDate", date: holding.asOfDate)
            appendFreshness(&facts, source: "\(prefix).date", date: holding.date)
        }

        return facts
    }

    func appendFreshness(_ facts: inout [EODFreshnessFact], source: String, date: String?) {
        guard let date, isEODDate(date) else { return }
        facts.append(EODFreshnessFact(source: source, date: date))
    }

    func isEODDate(_ date: String) -> Bool {
        date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}
