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
    public var portfolioGlance: PortfolioGlanceContext
    public var facetSnapshots: FacetSnapshots
    public var supportingDataSlots: [SupportingDataSlot]

    public init(
        schemaVersion: Int = 1,
        asOf: String,
        allQuiet: Bool,
        allQuietSignal: AllQuietSignal,
        rankedAttentionItems: [AttentionItem],
        portfolioGlance: PortfolioGlanceContext,
        facetSnapshots: FacetSnapshots,
        supportingDataSlots: [SupportingDataSlot]
    ) {
        self.schemaVersion = schemaVersion
        self.asOf = asOf
        self.allQuiet = allQuiet
        self.allQuietSignal = allQuietSignal
        self.attentionItems = rankedAttentionItems
        self.rankedAttentionItems = rankedAttentionItems
        self.portfolioGlance = portfolioGlance
        self.facetSnapshots = facetSnapshots
        self.supportingDataSlots = supportingDataSlots
    }

    public init(
        schemaVersion: Int = 1,
        asOf: String,
        allQuiet: Bool,
        allQuietSignal: AllQuietSignal,
        rankedAttentionItems: [AttentionItem],
        facetSnapshots: FacetSnapshots,
        supportingDataSlots: [SupportingDataSlot]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            asOf: asOf,
            allQuiet: allQuiet,
            allQuietSignal: allQuietSignal,
            rankedAttentionItems: rankedAttentionItems,
            portfolioGlance: PortfolioGlanceContext(
                totalValue: allQuietSignal.totalValue,
                openHoldingCount: facetSnapshots.allocation.openHoldingCount,
                worstPriceAsOf: facetSnapshots.freshness.worstPriceAsOf
            ),
            facetSnapshots: facetSnapshots,
            supportingDataSlots: supportingDataSlots
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case asOf
        case allQuiet
        case allQuietSignal
        case attentionItems
        case rankedAttentionItems
        case portfolioGlance
        case facetSnapshots
        case supportingDataSlots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        asOf = try container.decode(String.self, forKey: .asOf)
        allQuiet = try container.decode(Bool.self, forKey: .allQuiet)
        allQuietSignal = try container.decode(AllQuietSignal.self, forKey: .allQuietSignal)
        facetSnapshots = try container.decode(FacetSnapshots.self, forKey: .facetSnapshots)
        supportingDataSlots = try container.decode([SupportingDataSlot].self, forKey: .supportingDataSlots)
        rankedAttentionItems = try container.decodeIfPresent([AttentionItem].self, forKey: .rankedAttentionItems)
            ?? container.decode([AttentionItem].self, forKey: .attentionItems)
        attentionItems = try container.decodeIfPresent([AttentionItem].self, forKey: .attentionItems)
            ?? rankedAttentionItems
        portfolioGlance = try container.decodeIfPresent(PortfolioGlanceContext.self, forKey: .portfolioGlance)
            ?? PortfolioGlanceContext(
                totalValue: allQuietSignal.totalValue,
                openHoldingCount: facetSnapshots.allocation.openHoldingCount,
                worstPriceAsOf: facetSnapshots.freshness.worstPriceAsOf
            )
    }
}

public struct PortfolioGlanceContext: Codable, Equatable {
    public var totalValue: Money
    public var openHoldingCount: Int
    public var worstPriceAsOf: String?
    public var priorSnapshotAsOf: String?

    public init(
        totalValue: Money,
        openHoldingCount: Int,
        worstPriceAsOf: String?,
        priorSnapshotAsOf: String? = nil
    ) {
        self.totalValue = totalValue
        self.openHoldingCount = openHoldingCount
        self.worstPriceAsOf = worstPriceAsOf
        self.priorSnapshotAsOf = priorSnapshotAsOf
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
    public var detail: String
    public var severity: String
    public var score: Double
    public var holdingIdentity: HoldingIdentity?
    public var currentWeight: Double?
    public var threshold: Double?
    public var beforeValue: Double?
    public var afterValue: Double?
    public var moveSize: Double?
    public var beforeWeight: Double?
    public var afterWeight: Double?
    public var valueCurrency: String?
    public var eventDate: String?
    public var amount: Money?
    public var changePercent: Double?
    public var supportingDataSlotIDs: [String]

    public init(
        id: String,
        facet: String,
        rank: Int,
        title: String,
        detail: String = "",
        severity: String,
        score: Double,
        holdingIdentity: HoldingIdentity? = nil,
        currentWeight: Double? = nil,
        threshold: Double? = nil,
        beforeValue: Double? = nil,
        afterValue: Double? = nil,
        moveSize: Double? = nil,
        beforeWeight: Double? = nil,
        afterWeight: Double? = nil,
        valueCurrency: String? = nil,
        eventDate: String? = nil,
        amount: Money? = nil,
        changePercent: Double? = nil,
        supportingDataSlotIDs: [String]
    ) {
        self.id = id
        self.facet = facet
        self.rank = rank
        self.title = title
        self.detail = detail
        self.severity = severity
        self.score = score
        self.holdingIdentity = holdingIdentity
        self.currentWeight = currentWeight
        self.threshold = threshold
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.moveSize = moveSize
        self.beforeWeight = beforeWeight
        self.afterWeight = afterWeight
        self.valueCurrency = valueCurrency
        self.eventDate = eventDate
        self.amount = amount
        self.changePercent = changePercent
        self.supportingDataSlotIDs = supportingDataSlotIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        facet = try container.decode(String.self, forKey: .facet)
        rank = try container.decode(Int.self, forKey: .rank)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        severity = try container.decode(String.self, forKey: .severity)
        score = try container.decode(Double.self, forKey: .score)
        holdingIdentity = try container.decodeIfPresent(HoldingIdentity.self, forKey: .holdingIdentity)
        currentWeight = try container.decodeIfPresent(Double.self, forKey: .currentWeight)
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold)
        beforeValue = try container.decodeIfPresent(Double.self, forKey: .beforeValue)
        afterValue = try container.decodeIfPresent(Double.self, forKey: .afterValue)
        moveSize = try container.decodeIfPresent(Double.self, forKey: .moveSize)
        beforeWeight = try container.decodeIfPresent(Double.self, forKey: .beforeWeight)
        afterWeight = try container.decodeIfPresent(Double.self, forKey: .afterWeight)
        valueCurrency = try container.decodeIfPresent(String.self, forKey: .valueCurrency)
        eventDate = try container.decodeIfPresent(String.self, forKey: .eventDate)
        amount = try container.decodeIfPresent(Money.self, forKey: .amount)
        changePercent = try container.decodeIfPresent(Double.self, forKey: .changePercent)
        supportingDataSlotIDs = try container.decode([String].self, forKey: .supportingDataSlotIDs)
    }
}

public struct HoldingIdentity: Codable, Equatable {
    public var name: String
    public var quoteId: Int

    public init(name: String, quoteId: Int) {
        self.name = name
        self.quoteId = quoteId
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
    public var symbolId: Int?
    public var quoteId: Int?
    public var amount: Money?
    public var priorAmount: Money?
    public var changePercent: Double?

    public init(
        date: String,
        kind: String,
        symbolName: String,
        estimated: Bool,
        symbolId: Int? = nil,
        quoteId: Int? = nil,
        amount: Money? = nil,
        priorAmount: Money? = nil,
        changePercent: Double? = nil
    ) {
        self.date = date
        self.kind = kind
        self.symbolName = symbolName
        self.estimated = estimated
        self.symbolId = symbolId
        self.quoteId = quoteId
        self.amount = amount
        self.priorAmount = priorAmount
        self.changePercent = changePercent
    }
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
    public var statusBadge: String?
    public var statusAccessibilityIdentifier: String
    public var sections: [MenuSection]

    public init(
        statusTitle: String,
        statusBadge: String? = nil,
        statusAccessibilityIdentifier: String = "pdtbar.status",
        sections: [MenuSection]
    ) {
        self.statusTitle = statusTitle
        self.statusBadge = statusBadge
        self.statusAccessibilityIdentifier = statusAccessibilityIdentifier
        self.sections = sections
    }

    enum CodingKeys: String, CodingKey {
        case statusTitle
        case statusBadge
        case statusAccessibilityIdentifier
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusTitle = try container.decode(String.self, forKey: .statusTitle)
        statusBadge = try container.decodeIfPresent(String.self, forKey: .statusBadge)
        statusAccessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .statusAccessibilityIdentifier)
            ?? "pdtbar.status"
        sections = try container.decode([MenuSection].self, forKey: .sections)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusTitle, forKey: .statusTitle)
        if let statusBadge {
            try container.encode(statusBadge, forKey: .statusBadge)
        } else {
            try container.encodeNil(forKey: .statusBadge)
        }
        try container.encode(statusAccessibilityIdentifier, forKey: .statusAccessibilityIdentifier)
        try container.encode(sections, forKey: .sections)
    }
}

public struct MenuSection: Codable, Equatable {
    public var id: String
    public var title: String
    public var accessibilityIdentifier: String
    public var rows: [MenuRow]

    public init(id: String, title: String, accessibilityIdentifier: String? = nil, rows: [MenuRow]) {
        self.id = id
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier ?? "pdtbar.section.\(id)"
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case accessibilityIdentifier
        case rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        accessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .accessibilityIdentifier)
            ?? "pdtbar.section.\(id)"
        rows = try container.decode([MenuRow].self, forKey: .rows)
    }
}

public enum MenuRowRole: String, Codable, Equatable {
    case row
    case pulseQuiet
    case pulseAttention
    case pulseAttentionExpansion
    case allocationHolding
    case allocationDrillDown
    case incomeEmpty
    case incomeEvent
    case incomeDrillDown
    case bigMoverSummary
    case freshnessSummary

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let role = MenuRowRole(rawValue: value) {
            self = role
            return
        }
        switch value {
        case "glance":
            self = .pulseAttention
        case "expansion":
            self = .pulseAttentionExpansion
        default:
            self = .row
        }
    }
}

public struct MenuRow: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var accessibilityIdentifier: String
    public var title: String
    public var detail: String?

    public init(
        id: String = "",
        role: MenuRowRole = .row,
        accessibilityIdentifier: String? = nil,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier ?? Self.defaultAccessibilityIdentifier(for: id)
        self.title = title
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case accessibilityIdentifier
        case title
        case detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let decodedRole = try container.decodeIfPresent(MenuRowRole.self, forKey: .role) ?? .row
        role = id == "quiet" && decodedRole == .pulseAttention ? .pulseQuiet : decodedRole
        accessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .accessibilityIdentifier)
            ?? Self.defaultAccessibilityIdentifier(for: id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    private static func defaultAccessibilityIdentifier(for id: String) -> String {
        id.isEmpty ? "" : "pdtbar.row.\(id)"
    }
}

public enum MenuDescriptorRenderer {
    public static func render(model: PortfolioPulseModel) -> MenuDescriptor {
        let allocation = model.facetSnapshots.allocation
        let income = model.facetSnapshots.income
        let bigMovers = model.facetSnapshots.bigMovers

        let pulseRows: [MenuRow]
        if model.allQuiet {
            pulseRows = [
                MenuRow(
                    id: "pulse.quiet",
                    role: .pulseQuiet,
                    title: model.allQuietSignal.title,
                    detail: model.allQuietSignal.detail
                ),
            ]
        } else {
            pulseRows = model.rankedAttentionItems.flatMap { item in
                [
                    MenuRow(
                        id: "\(item.id).glance",
                        role: .pulseAttention,
                        title: item.title,
                        detail: item.detail
                    ),
                    MenuRow(
                        id: "\(item.id).expansion",
                        role: .pulseAttentionExpansion,
                        title: "\(item.facet) severity \(item.severity)",
                        detail: supportDetail(for: item)
                    ),
                ]
            }
        }

        let statusSignal = model.allQuiet
            ? model.allQuietSignal.title
            : model.rankedAttentionItems.first?.title ?? "Attention"

        return MenuDescriptor(
            statusTitle: "\(display(model.allQuietSignal.totalValue)) - \(statusSignal)",
            statusBadge: model.rankedAttentionItems.isEmpty ? nil : "\(model.rankedAttentionItems.count)",
            sections: [
                MenuSection(id: "pulse", title: "Pulse", rows: pulseRows),
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: allocation.topHoldings.map { holding in
                        let attention = model.rankedAttentionItems.first { item in
                            item.facet == "allocation" && item.holdingIdentity?.quoteId == holding.quoteId
                        }
                        let drillDownDetail = attention.flatMap { item -> String? in
                            guard let currentWeight = item.currentWeight,
                                  let threshold = item.threshold
                            else { return nil }
                            return "\(percent(currentWeight)) of portfolio; concentration line \(percent(threshold))"
                        }
                        return MenuRow(
                            id: "allocation.\(holding.quoteId)",
                            role: drillDownDetail == nil ? .allocationHolding : .allocationDrillDown,
                            title: holding.name,
                            detail: drillDownDetail ?? "\(percent(holding.weight)) of portfolio"
                        )
                    }
                ),
                MenuSection(
                    id: "income",
                    title: "Income",
                    rows: income.upcomingEvents.isEmpty
                        ? [
                            MenuRow(
                                id: "income.empty",
                                role: .incomeEmpty,
                                title: "No income events",
                                detail: "No calendar events in fixture"
                            ),
                        ]
                        : income.upcomingEvents.map {
                            MenuRow(
                                id: "income.\($0.quoteId ?? 0).\($0.kind)",
                                role: $0.amount == nil ? .incomeEvent : .incomeDrillDown,
                                title: $0.symbolName,
                                detail: incomeDetail(for: $0)
                            )
                        }
                ),
                MenuSection(
                    id: "bigMovers",
                    title: "Big movers",
                    rows: [
                        MenuRow(
                            id: "bigMovers.summary",
                            role: .bigMoverSummary,
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
                            id: "freshness.summary",
                            role: .freshnessSummary,
                            title: model.facetSnapshots.freshness.worstPriceAsOf ?? "Unknown price date",
                            detail: model.facetSnapshots.freshness.stale ? "Stale" : "Fresh"
                        ),
                    ]
                ),
            ]
        )
    }

    private static func supportDetail(for item: AttentionItem) -> String? {
        if item.facet == "income",
           let eventDate = item.eventDate
        {
            let amount = item.amount.map(display)
            let change = item.changePercent.map { "change \(signedPercent($0))" }
            return ([eventDate] + [amount, change].compactMap { $0 } + ["score \(decimalString(String(item.score), places: 2))"])
                .joined(separator: "; ")
        }

        if item.facet == "bigMovers",
           let beforeValue = item.beforeValue,
           let afterValue = item.afterValue,
           let moveSize = item.moveSize,
           let currency = item.valueCurrency
        {
            return "\(currency) \(decimalString(String(beforeValue), places: 2)) -> \(currency) \(decimalString(String(afterValue), places: 2)); move \(signedPercent(moveSize)); score \(decimalString(String(item.score), places: 2))"
        }

        guard let currentWeight = item.currentWeight,
              let threshold = item.threshold
        else {
            return "score \(decimalString(String(item.score), places: 2))"
        }
        return "\(percent(currentWeight)) current weight; \(percent(threshold)) threshold; score \(decimalString(String(item.score), places: 2))"
    }

    private static func incomeDetail(for event: IncomeEventSummary) -> String {
        let amount = event.amount.map { "; \(display($0))" } ?? ""
        return "\(event.kind) on \(event.date)\(amount)"
    }
}

public enum PressureEngine {
    public static let concentrationThreshold = 0.20
    public static let bigMoverThreshold = 0.10

    public static func buildModel(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot? = nil) -> PortfolioPulseModel {
        let rankedItems = ranked(
            concentrationItems(from: snapshot)
                + incomeItems(from: snapshot)
                + bigMoverItems(from: snapshot, priorSnapshot: priorSnapshot)
        )
        let totalValue = snapshot.totalValue
        let worstPriceAsOf = snapshot.openHoldings.map(\.priceAsOf).min()
        var supportingDataSlots = [
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
        if let priorSnapshot {
            supportingDataSlots.append(
                SupportingDataSlot(
                    id: "bigMovers.priorSnapshot",
                    facet: "bigMovers",
                    label: "Prior snapshot",
                    itemCount: priorSnapshot.openHoldings.count
                )
            )
        }

        return PortfolioPulseModel(
            asOf: snapshot.asOf,
            allQuiet: rankedItems.isEmpty,
            allQuietSignal: AllQuietSignal(
                title: "All quiet",
                detail: "No ranked attention items from the fixture.",
                totalValue: totalValue
            ),
            rankedAttentionItems: rankedItems,
            portfolioGlance: PortfolioGlanceContext(
                totalValue: totalValue,
                openHoldingCount: snapshot.openHoldings.count,
                worstPriceAsOf: worstPriceAsOf,
                priorSnapshotAsOf: priorSnapshot?.asOf
            ),
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
                    worstPriceAsOf: worstPriceAsOf,
                    stale: false
                )
            ),
            supportingDataSlots: supportingDataSlots
        )
    }

    private static func ranked(_ items: [AttentionItem]) -> [AttentionItem] {
        items
            .sorted {
                if $0.score == $1.score {
                    return $0.id < $1.id
                }
                return $0.score > $1.score
            }
            .enumerated()
            .map { offset, item in
                var rankedItem = item
                rankedItem.rank = offset + 1
                return rankedItem
            }
    }

    private static func concentrationItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        snapshot.openHoldings
            .filter { $0.weight > concentrationThreshold }
            .sorted { $0.weight > $1.weight }
            .enumerated()
            .map { offset, holding in
                let score = concentrationScore(weight: holding.weight, threshold: concentrationThreshold)
                return AttentionItem(
                    id: "allocation.concentration.\(holding.quoteId)",
                    facet: "allocation",
                    rank: offset + 1,
                    title: "\(holding.name) concentration",
                    detail: "\(holding.name) is \(percent(holding.weight)) of the portfolio, above the \(percent(concentrationThreshold)) concentration line.",
                    severity: score >= 0.8 ? "high" : "medium",
                    score: score,
                    holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
                    currentWeight: holding.weight,
                    threshold: concentrationThreshold,
                    supportingDataSlotIDs: ["allocation.holdings"]
                )
            }
    }

    private static func bigMoverItems(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot?) -> [AttentionItem] {
        guard let priorSnapshot else { return [] }

        let priorHoldings = priorSnapshot.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holdings[holding.quoteId] ?? holding
        }
        let moverThreshold = Decimal(string: String(bigMoverThreshold)) ?? 0
        return snapshot.openHoldings.compactMap { holding -> AttentionItem? in
            guard let priorHolding = priorHoldings[holding.quoteId],
                  let beforeDecimal = Decimal(string: priorHolding.price.value),
                  let afterDecimal = Decimal(string: holding.price.value),
                  beforeDecimal != 0
            else { return nil }

            let decimalMove = (afterDecimal - beforeDecimal) / beforeDecimal
            let absoluteDecimalMove = decimalMove < 0 ? -decimalMove : decimalMove
            guard absoluteDecimalMove >= moverThreshold else { return nil }

            let moveSize = rounded(Double(truncating: decimalMove as NSDecimalNumber), places: 4)

            let beforeValue = Double(truncating: beforeDecimal as NSDecimalNumber)
            let afterValue = Double(truncating: afterDecimal as NSDecimalNumber)
            let score = rounded(min(1.0, abs(moveSize) / 0.20), places: 2)
            return AttentionItem(
                id: "bigMovers.move.\(holding.quoteId)",
                facet: "bigMovers",
                rank: 0,
                title: "\(holding.name) moved \(signedPercent(moveSize))",
                detail: "\(holding.name) moved \(signedPercent(moveSize)) from \(holding.price.currency) \(decimalString(String(beforeValue), places: 2)) to \(holding.price.currency) \(decimalString(String(afterValue), places: 2)) while portfolio weight changed \(percent(priorHolding.weight)) -> \(percent(holding.weight)).",
                severity: abs(moveSize) >= 0.20 ? "high" : "medium",
                score: score,
                holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
                beforeValue: beforeValue,
                afterValue: afterValue,
                moveSize: moveSize,
                beforeWeight: priorHolding.weight,
                afterWeight: holding.weight,
                valueCurrency: holding.price.currency,
                supportingDataSlotIDs: ["bigMovers.priorSnapshot", "bigMovers.prices"]
            )
        }
    }

    private static func incomeItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        snapshot.incomeEvents
            .filter { $0.kind == "ex-dividend" && !$0.estimated }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { offset, event in
                let identity = event.quoteId.map {
                    HoldingIdentity(name: event.symbolName, quoteId: $0)
                }
                return AttentionItem(
                    id: incomeItemID(for: event),
                    facet: "income",
                    rank: offset + 1,
                    title: "\(event.symbolName) ex-dividend",
                    detail: incomeCopy(for: event),
                    severity: "low",
                    score: 0.45,
                    holdingIdentity: identity,
                    eventDate: event.date,
                    amount: event.amount,
                    changePercent: event.changePercent,
                    supportingDataSlotIDs: ["income.calendar"]
                )
            }
    }

    private static func incomeItemID(for event: IncomeEventSummary) -> String {
        if let quoteId = event.quoteId {
            return "income.ex-dividend.\(quoteId)"
        }
        if let symbolId = event.symbolId {
            return "income.ex-dividend.symbol.\(symbolId)"
        }
        return "income.ex-dividend.\(event.symbolName)"
    }

    private static func incomeCopy(for event: IncomeEventSummary) -> String {
        let base = "\(event.symbolName) has an ex-dividend date on \(event.date)"
        guard let amount = event.amount else {
            return "\(base)."
        }
        guard let changePercent = event.changePercent,
              let priorAmount = event.priorAmount
        else {
            return "\(base); latest recorded dividend \(display(amount))."
        }

        let direction = changePercent >= 0 ? "up" : "down"
        return "\(base); latest recorded dividend \(display(amount)), \(direction) \(percent(abs(changePercent))) from prior \(display(priorAmount))."
    }

    private static func concentrationScore(weight: Double, threshold: Double) -> Double {
        let relativeExcess = (weight - threshold) / threshold
        return rounded(min(1.0, 0.5 + (relativeExcess * 0.75)), places: 2)
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

public struct PressureRunResult: Codable, Equatable {
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
}

public struct SnapshotCommit: Codable, Equatable {
    public var written: Bool
    public var path: String
    public var asOf: String
}

public enum PressureRunner {
    public static func seedPriorSnapshot(fixture: URL, snapshotDirectory: URL) throws -> SnapshotCommit {
        let priorSnapshot = try PDTFixtureDataSource.priorSnapshot(from: fixture)
        return try SnapshotStore(directory: snapshotDirectory).commitCurrentSnapshot(priorSnapshot)
    }

    public static func run(fixture: URL, snapshotDirectory: URL) throws -> PressureRunResult {
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let snapshotStore = SnapshotStore(directory: snapshotDirectory)
        let priorSnapshot: PortfolioSnapshot?
        do {
            priorSnapshot = try snapshotStore.loadPriorSnapshot()
        } catch {
            priorSnapshot = nil
        }
        let model = PressureEngine.buildModel(from: snapshot, priorSnapshot: priorSnapshot)
        let commit = try snapshotStore.commitCurrentSnapshot(snapshot)
        let descriptor = MenuDescriptorRenderer.render(model: model)
        return PressureRunResult(model: model, snapshotCommit: commit, descriptor: descriptor)
    }
}

public struct SnapshotStore {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func temporaryTestStore(prefix: String = "pdtbar-snapshot-store") throws -> SnapshotStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SnapshotStore(directory: directory)
    }

    public func loadPriorSnapshot() throws -> PortfolioSnapshot? {
        let target = directory.appending(path: "latest-portfolio-snapshot.json")
        guard FileManager.default.fileExists(atPath: target.path) else {
            return nil
        }
        return try JSONDecoder().decode(PortfolioSnapshot.self, from: Data(contentsOf: target))
    }

    public func commitCurrentSnapshot(_ snapshot: PortfolioSnapshot) throws -> SnapshotCommit {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: "latest-portfolio-snapshot.json")
        try stableJSONData(snapshot).write(to: target, options: .atomic)
        return SnapshotCommit(written: true, path: target.path, asOf: snapshot.asOf)
    }

    public func write(snapshot: PortfolioSnapshot) throws -> SnapshotCommit {
        try commitCurrentSnapshot(snapshot)
    }
}

public typealias SnapshotFileStore = SnapshotStore

public struct PortfolioSnapshot: Codable, Equatable {
    public var asOf: String
    public var totalValue: Money
    public var openHoldings: [NormalizedHolding]
    public var sectors: [DistributionSummary]
    public var assetTypes: [DistributionSummary]
    public var incomeEvents: [IncomeEventSummary]
    public var dividendRowCount: Int
    public var priceSeries: [PricePoint]
}

public struct NormalizedHolding: Codable, Equatable {
    public var name: String
    public var quoteId: Int
    public var weight: Double
    public var worth: Money
    public var price: Money
    public var priceAsOf: String

    public init(name: String, quoteId: Int, weight: Double, worth: Money, price: Money, priceAsOf: String) {
        self.name = name
        self.quoteId = quoteId
        self.weight = weight
        self.worth = worth
        self.price = price
        self.priceAsOf = priceAsOf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        quoteId = try container.decode(Int.self, forKey: .quoteId)
        weight = try container.decode(Double.self, forKey: .weight)
        worth = try container.decode(Money.self, forKey: .worth)
        price = try container.decodeIfPresent(Money.self, forKey: .price)
            ?? Money(value: "0.00", currency: worth.currency)
        priceAsOf = try container.decode(String.self, forKey: .priceAsOf)
    }
}

public struct PricePoint: Codable, Equatable {
    public var quoteId: Int
    public var date: String
    public var closeAdjusted: String
}

public enum PDTFixtureDataSource {
    public static func snapshot(from url: URL) throws -> PortfolioSnapshot {
        let payload = try JSONDecoder().decode(PDTFixturePayload.self, from: Data(contentsOf: url))
        return makeSnapshot(
            from: payload,
            holdings: payload.primaryHoldings,
            asOf: payload.meta.asOf
        )
    }

    public static func priorSnapshot(from url: URL) throws -> PortfolioSnapshot {
        let payload = try JSONDecoder().decode(PDTFixturePayload.self, from: Data(contentsOf: url))
        guard let prior = payload.getPortfolioPriorSnapshot else {
            throw FixtureError.missingPriorSnapshot
        }
        return makeSnapshot(
            from: payload,
            holdings: prior.holdings,
            asOf: prior.query?.date ?? payload.meta.asOf
        )
    }

    private static func makeSnapshot(
        from payload: PDTFixturePayload,
        holdings rawHoldings: [FixtureHolding],
        asOf: String
    ) -> PortfolioSnapshot {
        let holdings = rawHoldings
            .filter { $0.closedAt == nil }
            .map {
                NormalizedHolding(
                    name: $0.symbolName,
                    quoteId: $0.symbolQuoteId,
                    weight: $0.portfolioWeight,
                    worth: $0.currentWorthLocal,
                    price: $0.currentPriceLocal,
                    priceAsOf: dayPrefix($0.currentPriceDate)
                )
            }

        let totalValue = payload.meta.portfolioCurrentWorthEUR.map {
            Money(value: $0, currency: payload.meta.portfolioCurrency)
        } ?? sumWorth(holdings, currency: payload.meta.portfolioCurrency)
        let quoteIDsBySymbolID = payload.symbolQuotes.reduce(into: [Int: Int]()) { idsBySymbolID, quote in
            idsBySymbolID[quote.symbolId] = quote.id
        }
        let dividendsByQuoteID = Dictionary(
            grouping: payload.listDividends?.data ?? [],
            by: \.symbolQuoteId
        )

        return PortfolioSnapshot(
            asOf: asOf,
            totalValue: totalValue,
            openHoldings: holdings,
            sectors: (payload.getPortfolioDistributions?.sectors ?? []).map(\.summary),
            assetTypes: (payload.getPortfolioDistributions?.assetTypes ?? []).map(\.summary),
            incomeEvents: payload.listCalendarEvents?.data.map {
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

    private static func latestDividendAmount(
        for quoteId: Int?,
        dividendsByQuoteID: [Int: [FixtureDividend]]
    ) -> Money? {
        guard let quoteId else {
            return nil
        }
        let dividends = dividendsByQuoteID[quoteId] ?? []
        // Correction pairs need a stable pairing key before their amounts are safe to display.
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
    var listCalendarEvents: CalendarEventsEnvelope?
    var listDividends: DividendsEnvelope?
    var listSymbolPrices: PricesEnvelope?
    var getSymbolQuote: SymbolQuoteEnvelope?
    var getSymbolQuotes: [SymbolQuoteEnvelope]?

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
        case listCalendarEvents
        case listDividends
        case listSymbolPrices
        case getSymbolQuote
        case getSymbolQuotes
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
    var currentPriceLocal: Money
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
    var symbolId: Int?
    var symbolName: String?
}

private struct DividendsEnvelope: Decodable {
    var data: [FixtureDividend]
}

private struct FixtureDividend: Decodable {
    var date: String
    var amount: Money
    var symbolQuoteId: Int
}

private struct SymbolQuoteEnvelope: Decodable {
    var id: Int
    var symbolId: Int
}

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

private func signedPercent(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : ""
    return "\(sign)\(percent(value))"
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
