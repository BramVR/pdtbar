import Foundation

public struct Money: Codable, Equatable {
    public var value: String
    public var currency: String

    public init(value: String, currency: String) {
        self.value = value
        self.currency = currency
    }
}

public struct PortfolioPulseModel: Codable, Equatable {
    public var schemaVersion: Int
    public var asOf: String
    public var allQuiet: Bool
    public var allQuietSignal: AllQuietSignal
    public var attentionItems: [AttentionItem]
    public var rankedAttentionItems: [AttentionItem]
    public var facetSnapshots: FacetSnapshots
    public var supportingDataSlots: [SupportingDataSlot]

    public init(
        schemaVersion: Int = 1,
        asOf: String,
        allQuiet: Bool,
        allQuietSignal: AllQuietSignal,
        rankedAttentionItems: [AttentionItem],
        facetSnapshots: FacetSnapshots,
        supportingDataSlots: [SupportingDataSlot]
    ) {
        self.schemaVersion = schemaVersion
        self.asOf = asOf
        self.allQuiet = allQuiet
        self.allQuietSignal = allQuietSignal
        self.attentionItems = rankedAttentionItems
        self.rankedAttentionItems = rankedAttentionItems
        self.facetSnapshots = facetSnapshots
        self.supportingDataSlots = supportingDataSlots
    }
}

public struct AllQuietSignal: Codable, Equatable {
    public var title: String
    public var detail: String
    public var totalValue: Money

    public init(title: String, detail: String, totalValue: Money) {
        self.title = title
        self.detail = detail
        self.totalValue = totalValue
    }
}

public struct AttentionItem: Codable, Equatable {
    public var id: String
    public var facet: String
    public var rank: Int
    public var title: String
    public var severity: String
    public var score: Double
    public var supportingDataSlotIDs: [String]

    public init(
        id: String,
        facet: String,
        rank: Int,
        title: String,
        severity: String,
        score: Double,
        supportingDataSlotIDs: [String]
    ) {
        self.id = id
        self.facet = facet
        self.rank = rank
        self.title = title
        self.severity = severity
        self.score = score
        self.supportingDataSlotIDs = supportingDataSlotIDs
    }
}

public struct SupportingDataSlot: Codable, Equatable {
    public var id: String
    public var facet: String
    public var label: String
    public var itemCount: Int

    public init(id: String, facet: String, label: String, itemCount: Int) {
        self.id = id
        self.facet = facet
        self.label = label
        self.itemCount = itemCount
    }
}

public struct FacetSnapshots: Codable, Equatable {
    public var allocation: AllocationSnapshot
    public var income: IncomeSnapshot
    public var bigMovers: BigMoversSnapshot
    public var freshness: FreshnessSnapshot

    public init(
        allocation: AllocationSnapshot,
        income: IncomeSnapshot,
        bigMovers: BigMoversSnapshot,
        freshness: FreshnessSnapshot
    ) {
        self.allocation = allocation
        self.income = income
        self.bigMovers = bigMovers
        self.freshness = freshness
    }
}

public struct AllocationSnapshot: Codable, Equatable {
    public var totalValue: Money
    public var openHoldingCount: Int
    public var topHoldings: [HoldingSummary]
    public var sectorBreakdown: [DistributionSummary]
    public var assetTypeBreakdown: [DistributionSummary]
}

public struct HoldingSummary: Codable, Equatable {
    public var name: String
    public var quoteId: Int
    public var weight: Double
    public var worth: Money
}

public struct DistributionSummary: Codable, Equatable {
    public var name: String
    public var percentage: Double
    public var totalValue: Money
}

public struct IncomeSnapshot: Codable, Equatable {
    public var upcomingEvents: [IncomeEventSummary]
    public var dividendRowCount: Int
}

public struct IncomeEventSummary: Codable, Equatable {
    public var date: String
    public var kind: String
    public var symbolName: String
    public var estimated: Bool
}

public struct BigMoversSnapshot: Codable, Equatable {
    public var priceSeriesCount: Int
    public var maxMove: PriceMoveSummary?
}

public struct PriceMoveSummary: Codable, Equatable {
    public var quoteId: Int
    public var fromDate: String
    public var toDate: String
    public var percentChange: Double
}

public struct FreshnessSnapshot: Codable, Equatable {
    public var worstPriceAsOf: String?
    public var stale: Bool
}

public struct MenuDescriptor: Codable, Equatable {
    public var statusTitle: String
    public var sections: [MenuSection]

    public init(statusTitle: String, sections: [MenuSection]) {
        self.statusTitle = statusTitle
        self.sections = sections
    }
}

public struct MenuSection: Codable, Equatable {
    public var id: String
    public var title: String
    public var rows: [MenuRow]
}

public struct MenuRow: Codable, Equatable {
    public var title: String
    public var detail: String?
}

public enum MenuDescriptorRenderer {
    public static func render(model: PortfolioPulseModel) -> MenuDescriptor {
        let allocation = model.facetSnapshots.allocation
        let income = model.facetSnapshots.income
        let bigMovers = model.facetSnapshots.bigMovers

        let pulseRows: [MenuRow]
        if model.allQuiet {
            pulseRows = [
                MenuRow(title: model.allQuietSignal.title, detail: model.allQuietSignal.detail),
            ]
        } else {
            pulseRows = model.rankedAttentionItems.map {
                MenuRow(title: $0.title, detail: "\($0.facet) severity \($0.severity)")
            }
        }

        let statusSignal = model.allQuiet
            ? model.allQuietSignal.title
            : model.rankedAttentionItems.first?.title ?? "Attention"

        return MenuDescriptor(
            statusTitle: "\(display(model.allQuietSignal.totalValue)) - \(statusSignal)",
            sections: [
                MenuSection(id: "pulse", title: "Pulse", rows: pulseRows),
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: allocation.topHoldings.map {
                        MenuRow(title: $0.name, detail: "\(percent($0.weight)) of portfolio")
                    }
                ),
                MenuSection(
                    id: "income",
                    title: "Income",
                    rows: income.upcomingEvents.isEmpty
                        ? [MenuRow(title: "No income events", detail: "No calendar events in fixture")]
                        : income.upcomingEvents.map {
                            MenuRow(title: $0.symbolName, detail: "\($0.kind) on \($0.date)")
                        }
                ),
                MenuSection(
                    id: "bigMovers",
                    title: "Big movers",
                    rows: [
                        MenuRow(
                            title: bigMovers.maxMove.map { "Quote \($0.quoteId)" } ?? "No big movers",
                            detail: bigMovers.maxMove.map { "\(percent($0.percentChange)) over fixture window" }
                                ?? "\(bigMovers.priceSeriesCount) price rows checked"
                        ),
                    ]
                ),
                MenuSection(
                    id: "freshness",
                    title: "Freshness",
                    rows: [
                        MenuRow(
                            title: model.facetSnapshots.freshness.worstPriceAsOf ?? "Unknown price date",
                            detail: model.facetSnapshots.freshness.stale ? "Stale" : "Fresh"
                        ),
                    ]
                ),
            ]
        )
    }
}

public enum PressureEngine {
    public static func buildModel(from snapshot: PortfolioSnapshot) -> PortfolioPulseModel {
        let rankedItems: [AttentionItem] = []
        let totalValue = snapshot.totalValue

        return PortfolioPulseModel(
            asOf: snapshot.asOf,
            allQuiet: rankedItems.isEmpty,
            allQuietSignal: AllQuietSignal(
                title: "All quiet",
                detail: "No ranked attention items from the fixture.",
                totalValue: totalValue
            ),
            rankedAttentionItems: rankedItems,
            facetSnapshots: FacetSnapshots(
                allocation: AllocationSnapshot(
                    totalValue: totalValue,
                    openHoldingCount: snapshot.openHoldings.count,
                    topHoldings: snapshot.openHoldings
                        .sorted { $0.weight > $1.weight }
                        .prefix(5)
                        .map {
                            HoldingSummary(
                                name: $0.name,
                                quoteId: $0.quoteId,
                                weight: $0.weight,
                                worth: $0.worth
                            )
                        },
                    sectorBreakdown: snapshot.sectors,
                    assetTypeBreakdown: snapshot.assetTypes
                ),
                income: IncomeSnapshot(
                    upcomingEvents: snapshot.incomeEvents.sorted { $0.date < $1.date },
                    dividendRowCount: snapshot.dividendRowCount
                ),
                bigMovers: BigMoversSnapshot(
                    priceSeriesCount: snapshot.priceSeries.count,
                    maxMove: maxMove(from: snapshot.priceSeries)
                ),
                freshness: FreshnessSnapshot(
                    worstPriceAsOf: snapshot.openHoldings.map(\.priceAsOf).min(),
                    stale: false
                )
            ),
            supportingDataSlots: [
                SupportingDataSlot(
                    id: "allocation.holdings",
                    facet: "allocation",
                    label: "Open holdings",
                    itemCount: snapshot.openHoldings.count
                ),
                SupportingDataSlot(
                    id: "allocation.sectors",
                    facet: "allocation",
                    label: "Sector breakdown",
                    itemCount: snapshot.sectors.count
                ),
                SupportingDataSlot(
                    id: "income.calendar",
                    facet: "income",
                    label: "Calendar events",
                    itemCount: snapshot.incomeEvents.count
                ),
                SupportingDataSlot(
                    id: "bigMovers.prices",
                    facet: "bigMovers",
                    label: "Price rows",
                    itemCount: snapshot.priceSeries.count
                ),
            ]
        )
    }

    private static func maxMove(from prices: [PricePoint]) -> PriceMoveSummary? {
        let grouped = Dictionary(grouping: prices, by: \.quoteId)
        return grouped.compactMap { quoteId, points -> PriceMoveSummary? in
            let sorted = points.sorted { $0.date < $1.date }
            guard let first = sorted.first,
                  let last = sorted.last,
                  let firstClose = Decimal(string: first.closeAdjusted),
                  let lastClose = Decimal(string: last.closeAdjusted),
                  firstClose != 0
            else { return nil }

            let change = (lastClose - firstClose) / firstClose
            return PriceMoveSummary(
                quoteId: quoteId,
                fromDate: first.date,
                toDate: last.date,
                percentChange: rounded(Double(truncating: change as NSDecimalNumber), places: 4)
            )
        }
        .max { abs($0.percentChange) < abs($1.percentChange) }
    }
}

public struct PortfolioSnapshot: Equatable {
    public var asOf: String
    public var totalValue: Money
    public var openHoldings: [NormalizedHolding]
    public var sectors: [DistributionSummary]
    public var assetTypes: [DistributionSummary]
    public var incomeEvents: [IncomeEventSummary]
    public var dividendRowCount: Int
    public var priceSeries: [PricePoint]
}

public struct NormalizedHolding: Equatable {
    public var name: String
    public var quoteId: Int
    public var weight: Double
    public var worth: Money
    public var priceAsOf: String
}

public struct PricePoint: Equatable {
    public var quoteId: Int
    public var date: String
    public var closeAdjusted: String
}

public enum PDTFixtureDataSource {
    public static func snapshot(from url: URL) throws -> PortfolioSnapshot {
        let payload = try JSONDecoder().decode(PDTFixturePayload.self, from: Data(contentsOf: url))
        let holdings = payload.primaryHoldings
            .filter { $0.closedAt == nil }
            .map {
                NormalizedHolding(
                    name: $0.symbolName,
                    quoteId: $0.symbolQuoteId,
                    weight: $0.portfolioWeight,
                    worth: $0.currentWorthLocal,
                    priceAsOf: dayPrefix($0.currentPriceDate)
                )
            }

        let totalValue = payload.meta.portfolioCurrentWorthEUR.map {
            Money(value: $0, currency: payload.meta.portfolioCurrency)
        } ?? sumWorth(holdings, currency: payload.meta.portfolioCurrency)

        return PortfolioSnapshot(
            asOf: payload.meta.asOf,
            totalValue: totalValue,
            openHoldings: holdings,
            sectors: (payload.getPortfolioDistributions?.sectors ?? []).map(\.summary),
            assetTypes: (payload.getPortfolioDistributions?.assetTypes ?? []).map(\.summary),
            incomeEvents: payload.listCalendarEvents?.data.map {
                IncomeEventSummary(
                    date: $0.date,
                    kind: $0.type,
                    symbolName: $0.symbolName ?? "Portfolio",
                    estimated: $0.isEstimated
                )
            } ?? [],
            dividendRowCount: payload.listDividends?.data.count ?? 0,
            priceSeries: payload.listSymbolPrices?.data.map {
                PricePoint(
                    quoteId: $0.symbolQuoteId,
                    date: $0.date,
                    closeAdjusted: $0.closeAdjusted
                )
            } ?? []
        )
    }
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
    var listCalendarEvents: CalendarEventsEnvelope?
    var listDividends: DividendsEnvelope?
    var listSymbolPrices: PricesEnvelope?

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
        case listCalendarEvents
        case listDividends
        case listSymbolPrices
    }
}

private struct FixtureMeta: Decodable {
    var asOf: String
    var portfolioCurrency: String
    var portfolioCurrentWorthEUR: String?
}

private struct HoldingsEnvelope: Decodable {
    var holdings: [FixtureHolding]
}

private struct FixtureHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
    var currentPriceDate: String
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var closedAt: String?
}

private struct DistributionsEnvelope: Decodable {
    var sectors: [FixtureDistribution]?
    var assetTypes: [FixtureDistribution]?
}

private struct FixtureDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var summary: DistributionSummary {
        DistributionSummary(name: categoryName, percentage: percentage, totalValue: totalValue)
    }
}

private struct CalendarEventsEnvelope: Decodable {
    var data: [FixtureCalendarEvent]
}

private struct FixtureCalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolName: String?
}

private struct DividendsEnvelope: Decodable {
    var data: [FixtureDividend]
}

private struct FixtureDividend: Decodable {}

private struct PricesEnvelope: Decodable {
    var data: [FixturePrice]
}

private struct FixturePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var symbolQuoteId: Int
}

private func display(_ money: Money) -> String {
    "\(money.currency) \(decimalString(money.value, places: 2))"
}

private func percent(_ value: Double) -> String {
    "\(decimalString(String(value * 100), places: 1))%"
}

private func decimalString(_ value: String, places: Int) -> String {
    guard let decimal = Decimal(string: value) else { return value }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    return formatter.string(from: decimal as NSDecimalNumber) ?? value
}

private func dayPrefix(_ dateTime: String) -> String {
    String(dateTime.prefix(10))
}

private func sumWorth(_ holdings: [NormalizedHolding], currency: String) -> Money {
    let total = holdings.reduce(Decimal(0)) { partial, holding in
        partial + (Decimal(string: holding.worth.value) ?? 0)
    }
    return Money(value: canonicalDecimalString(total, places: 2), currency: currency)
}

private func rounded(_ value: Double, places: Int) -> Double {
    let multiplier = pow(10.0, Double(places))
    return (value * multiplier).rounded() / multiplier
}

private func canonicalDecimalString(_ value: Decimal, places: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    return formatter.string(from: value as NSDecimalNumber) ?? (value as NSDecimalNumber).stringValue
}
