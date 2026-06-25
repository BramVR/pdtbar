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
    public var xRayHoldings: [XRayHoldingSummary]?
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

public struct XRayHoldingSummary: Codable, Equatable {
    public var weight: Double

    public init(weight: Double) {
        self.weight = weight
    }
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

public struct IncomeCalendarIntent: Codable, Equatable {
    public var asOf: String
    public var summary: IncomeCalendarSummary
    public var nextEvent: IncomeEventSummary?
    public var events: [IncomeEventSummary]

    public var isEmpty: Bool {
        events.isEmpty
    }
}

public struct IncomeCalendarSummary: Codable, Equatable {
    public var eventCount: Int
    public var confirmedCount: Int
    public var estimatedCount: Int
    public var windowStart: String
    public var windowEnd: String?
}

public enum IncomeCalendar {
    public static func build(events: [IncomeEventSummary], asOf: String) -> IncomeCalendarIntent {
        let sortedEvents = events
            .filter { isIncomeCalendarKind($0.kind) }
            .filter { $0.date >= asOf }
            .sorted(by: ranksBefore)
        return IncomeCalendarIntent(
            asOf: asOf,
            summary: IncomeCalendarSummary(
                eventCount: sortedEvents.count,
                confirmedCount: sortedEvents.filter { !$0.estimated }.count,
                estimatedCount: sortedEvents.filter(\.estimated).count,
                windowStart: asOf,
                windowEnd: sortedEvents.map(\.date).max()
            ),
            nextEvent: sortedEvents.first,
            events: sortedEvents
        )
    }

    private static func ranksBefore(_ lhs: IncomeEventSummary, _ rhs: IncomeEventSummary) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        let lhsPriority = eventPriority(lhs.kind)
        let rhsPriority = eventPriority(rhs.kind)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.symbolName != rhs.symbolName {
            return lhs.symbolName < rhs.symbolName
        }
        return incomeEventRowID(for: lhs) < incomeEventRowID(for: rhs)
    }

    private static func eventPriority(_ kind: String) -> Int {
        switch kind {
        case "ex-dividend":
            return 0
        case "payment-dividend":
            return 1
        default:
            return 2
        }
    }

    private static func isIncomeCalendarKind(_ kind: String) -> Bool {
        kind == "ex-dividend" || kind == "payment-dividend"
    }
}

public enum IncomeCalendarDescriptor {
    public static let previewLimit = 3

    public static func rows(for intent: IncomeCalendarIntent) -> [MenuRow] {
        guard let nextEvent = intent.nextEvent else {
            return [
                MenuRow(
                    id: "income.empty",
                    role: .incomeEmpty,
                    title: "No income events",
                    detail: "No calendar events in the next window"
                ),
            ]
        }

        let previewEvents = Array(intent.events.prefix(previewLimit))
        let overflowEvents = Array(intent.events.dropFirst(previewLimit))
        let previewRows = previewEvents.enumerated().map { index, event in
            if index == 0 {
                return MenuRow(
                    id: "income.next",
                    role: .incomeNext,
                    title: "Next income: \(event.symbolName)",
                    detail: incomeEventDetail(for: event),
                    children: incomeEventChildren(for: event)
                )
            }
            return incomeEventRow(for: event, id: incomeEventRowID(for: event))
        }
        let overflowRows = overflowGroups(for: overflowEvents, nextDate: nextEvent.date, asOf: intent.asOf)

        return [
            MenuRow(
                id: "income.summary",
                role: .incomeSummary,
                title: "Income window",
                detail: summaryDetail(for: intent.summary)
            ),
        ] + previewRows + overflowRows
    }

    private static func summaryDetail(for summary: IncomeCalendarSummary) -> String {
        guard summary.eventCount > 0 else {
            return "No calendar events in the next window"
        }

        let eventWord = summary.eventCount == 1 ? "event" : "events"
        let window = summary.windowEnd.map { " through \($0)" } ?? ""
        if summary.estimatedCount == 0 {
            return "\(summary.confirmedCount) confirmed \(eventWord)\(window)"
        }
        if summary.confirmedCount == 0 {
            return "\(summary.estimatedCount) estimated \(eventWord)\(window)"
        }
        return "\(summary.eventCount) \(eventWord)\(window); \(summary.confirmedCount) confirmed, \(summary.estimatedCount) estimated"
    }

    private static func overflowGroups(for events: [IncomeEventSummary], nextDate: String, asOf: String) -> [MenuRow] {
        let buckets = IncomeOverflowBucket.allCases.map { bucket in
            let bucketEvents = events.filter { bucket.contains($0, nextDate: nextDate, asOf: asOf) }
            return (bucket, bucketEvents)
        }

        return buckets.compactMap { bucket, bucketEvents in
            guard !bucketEvents.isEmpty else { return nil }
            let groupID = "income.overflow.\(bucket.id)"
            return MenuRow(
                id: groupID,
                role: .incomeDrillDown,
                title: bucket.title,
                detail: bucketEvents.count == 1 ? "1 event" : "\(bucketEvents.count) events",
                children: bucketEvents.map { event in
                    incomeEventRow(for: event, id: "\(groupID).\(incomeEventRowID(for: event))")
                }
            )
        }
    }
}

private enum IncomeOverflowBucket: CaseIterable {
    case next
    case thisWeek
    case later

    var id: String {
        switch self {
        case .next: "next"
        case .thisWeek: "this-week"
        case .later: "later"
        }
    }

    var title: String {
        switch self {
        case .next: "Next"
        case .thisWeek: "This week"
        case .later: "Later"
        }
    }

    func contains(_ event: IncomeEventSummary, nextDate: String, asOf: String) -> Bool {
        switch self {
        case .next:
            return event.date == nextDate
        case .thisWeek:
            return event.date != nextDate && event.date <= dayString(asOf, addingDays: 7)
        case .later:
            return event.date != nextDate && event.date > dayString(asOf, addingDays: 7)
        }
    }
}

private func incomeEventRow(for event: IncomeEventSummary, id: String) -> MenuRow {
    MenuRow(
        id: id,
        role: .incomeEvent,
        title: event.symbolName,
        detail: incomeEventDetail(for: event),
        children: incomeEventChildren(for: event, rowID: id)
    )
}

private func incomeEventChildren(for event: IncomeEventSummary, rowID: String? = nil) -> [MenuRow] {
    let baseID = rowID ?? incomeEventRowID(for: event)
    return [
        MenuRow(id: "\(baseID).date", title: "Date", detail: event.date),
        MenuRow(id: "\(baseID).kind", title: "Kind", detail: incomeEventKindLabel(for: event.kind)),
        MenuRow(id: "\(baseID).state", title: "State", detail: event.estimated ? "Estimated" : "Confirmed"),
        event.amount.map {
            MenuRow(id: "\(baseID).amount", title: "Amount", detail: display($0))
        },
        incomeEventChangeDetail(for: event).map {
            MenuRow(id: "\(baseID).change", title: "Change", detail: $0)
        },
    ].compactMap { $0 }
}

private func incomeEventDetail(for event: IncomeEventSummary) -> String {
    let parts = [
        "\(incomeEventKindLabel(for: event.kind)) on \(event.date)",
        event.estimated ? "estimated" : "confirmed",
        event.amount.map(display),
        incomeEventChangeDetail(for: event),
    ].compactMap { $0 }
    return parts.joined(separator: "; ")
}

private func incomeEventKindLabel(for kind: String) -> String {
    switch kind {
    case "ex-dividend":
        return "Ex-dividend date"
    case "payment-dividend":
        return "Dividend payment date"
    default:
        return kind
    }
}

private func incomeEventChangeDetail(for event: IncomeEventSummary) -> String? {
    guard let changePercent = event.changePercent,
          let priorAmount = event.priorAmount
    else {
        return nil
    }
    return "\(signedPercent(changePercent)) from \(display(priorAmount))"
}

private func incomeEventRowID(for event: IncomeEventSummary) -> String {
    let identity = event.quoteId.map { "quote.\($0)" }
        ?? event.symbolId.map { "symbol.\($0)" }
        ?? "portfolio"
    return "income.\(identity).\(event.kind).\(event.date)"
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

public struct StatusVisualState: Codable, Equatable {
    public var barHeights: [Double]
    public var filledBarCount: Int
    public var isDimmed: Bool
    public var statusCopy: String

    public init(
        barHeights: [Double] = [0.5, 1.0, 0.667],
        filledBarCount: Int = 0,
        isDimmed: Bool = false,
        statusCopy: String = ""
    ) {
        self.barHeights = Array(barHeights.prefix(3))
        let fallbackHeights = [0.5, 1.0, 0.667]
        while self.barHeights.count < 3 {
            self.barHeights.append(fallbackHeights[self.barHeights.count])
        }
        if self.barHeights.count > 1 {
            self.barHeights[1] = 1.0
        }
        self.filledBarCount = max(0, min(3, filledBarCount))
        self.isDimmed = isDimmed
        self.statusCopy = statusCopy
    }

    enum CodingKeys: String, CodingKey {
        case barHeights
        case filledBarCount
        case isDimmed
        case statusCopy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            barHeights: try container.decodeIfPresent([Double].self, forKey: .barHeights) ?? [0.5, 1.0, 0.667],
            filledBarCount: try container.decodeIfPresent(Int.self, forKey: .filledBarCount) ?? 0,
            isDimmed: try container.decodeIfPresent(Bool.self, forKey: .isDimmed) ?? false,
            statusCopy: try container.decodeIfPresent(String.self, forKey: .statusCopy) ?? ""
        )
    }

    public func withDimming(_ isDimmed: Bool) -> StatusVisualState {
        StatusVisualState(
            barHeights: barHeights,
            filledBarCount: filledBarCount,
            isDimmed: isDimmed,
            statusCopy: statusCopy
        )
    }
}

public struct MenuDescriptor: Codable, Equatable {
    public var statusTitle: String
    public var statusBadge: String?
    public var statusVisual: StatusVisualState
    public var statusAccessibilityIdentifier: String
    public var sections: [MenuSection]

    public init(
        statusTitle: String,
        statusBadge: String? = nil,
        statusVisual: StatusVisualState = StatusVisualState(),
        statusAccessibilityIdentifier: String = "pdtbar.status",
        sections: [MenuSection]
    ) {
        self.statusTitle = statusTitle
        self.statusBadge = statusBadge
        var visual = statusVisual
        if visual.statusCopy.isEmpty {
            visual.statusCopy = statusBadge.map { "\(statusTitle) [\($0)]" } ?? statusTitle
        }
        self.statusVisual = visual
        self.statusAccessibilityIdentifier = statusAccessibilityIdentifier
        self.sections = sections
    }

    enum CodingKeys: String, CodingKey {
        case statusTitle
        case statusBadge
        case statusVisual
        case statusAccessibilityIdentifier
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusTitle = try container.decode(String.self, forKey: .statusTitle)
        statusBadge = try container.decodeIfPresent(String.self, forKey: .statusBadge)
        statusVisual = try container.decodeIfPresent(StatusVisualState.self, forKey: .statusVisual)
            ?? StatusVisualState()
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
        try container.encode(statusVisual, forKey: .statusVisual)
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
    case setupProbe
    case setupStatus
    case setupLogin
    case setupRetry
    case setupFailure
    case fetchStatus
    case fetchRetry
    case pulseSummary
    case pulseQuiet
    case pulseAttention
    case pulseAttentionExpansion
    case allocationHolding
    case allocationDrillDown
    case incomeEmpty
    case incomeSummary
    case incomeNext
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
    public var children: [MenuRow]

    public init(
        id: String = "",
        role: MenuRowRole = .row,
        accessibilityIdentifier: String? = nil,
        title: String,
        detail: String? = nil,
        children: [MenuRow] = []
    ) {
        self.id = id
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier ?? Self.defaultAccessibilityIdentifier(for: id)
        self.title = title
        self.detail = detail
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case accessibilityIdentifier
        case title
        case detail
        case children
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
        children = try container.decodeIfPresent([MenuRow].self, forKey: .children) ?? []
    }

    private static func defaultAccessibilityIdentifier(for id: String) -> String {
        id.isEmpty ? "" : "pdtbar.row.\(id)"
    }
}

public struct MenuBarSurface: Codable, Equatable {
    public var status: MenuBarStatusSurface
    public var sections: [MenuBarSectionSurface]

    public init(status: MenuBarStatusSurface, sections: [MenuBarSectionSurface]) {
        self.status = status
        self.sections = sections
    }
}

public struct MenuBarStatusSurface: Codable, Equatable {
    public var title: String
    public var badge: String?
    public var menuBarTitle: String
    public var visual: StatusVisualState
    public var accessibilityIdentifier: String
    public var accessibilityLabel: String
    public var toolTip: String

    public init(
        title: String,
        badge: String?,
        menuBarTitle: String,
        visual: StatusVisualState,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        toolTip: String
    ) {
        self.title = title
        self.badge = badge
        self.menuBarTitle = menuBarTitle
        self.visual = visual
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.toolTip = toolTip
    }
}

public struct MenuBarSectionSurface: Codable, Equatable {
    public var id: String
    public var title: String
    public var accessibilityIdentifier: String
    public var rows: [MenuBarRowSurface]

    public init(id: String, title: String, accessibilityIdentifier: String, rows: [MenuBarRowSurface]) {
        self.id = id
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.rows = rows
    }
}

public struct MenuBarRowSurface: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var title: String
    public var accessibilityIdentifier: String
    public var children: [MenuBarRowSurface]

    public init(
        id: String,
        role: MenuRowRole,
        title: String,
        accessibilityIdentifier: String,
        children: [MenuBarRowSurface] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.children = children
    }
}

public enum PDTBarLaunchMode: Equatable {
    case claudeFirst
    case fixture(URL)
}

public struct PDTBarLaunchOptions: Equatable {
    public var mode: PDTBarLaunchMode
    public var snapshotDirectory: URL?
    public var appSupportDirectory: URL?

    public init(
        mode: PDTBarLaunchMode,
        snapshotDirectory: URL? = nil,
        appSupportDirectory: URL? = nil
    ) {
        self.mode = mode
        self.snapshotDirectory = snapshotDirectory
        self.appSupportDirectory = appSupportDirectory
    }
}

public enum PDTBarLaunchOptionError: Error, Equatable {
    case usage
}

public enum PDTBarLaunchOptionParser {
    public static func parse(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PDTBarLaunchOptions {
        var fixture: URL?
        var snapshotDirectory: URL?
        var appSupportDirectory: URL?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--fixture" where index + 1 < arguments.count:
                fixture = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--snapshot-dir" where index + 1 < arguments.count:
                snapshotDirectory = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--app-support-dir" where index + 1 < arguments.count:
                appSupportDirectory = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default:
                throw PDTBarLaunchOptionError.usage
            }
        }

        appSupportDirectory = appSupportDirectory
            ?? environment["PDTBAR_APP_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }

        if let fixture {
            let configuredSnapshotDirectory = snapshotDirectory
                ?? environment["PDTBAR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            return PDTBarLaunchOptions(
                mode: .fixture(fixture),
                snapshotDirectory: configuredSnapshotDirectory,
                appSupportDirectory: appSupportDirectory
            )
        }

        guard snapshotDirectory == nil else {
            throw PDTBarLaunchOptionError.usage
        }
        return PDTBarLaunchOptions(mode: .claudeFirst, appSupportDirectory: appSupportDirectory)
    }
}

public enum ClaudeReadinessProbeResult: Equatable {
    case ready
    case notReady
    case missingClaudeLogin
    case missingPDTMCP
    case failed
}

public final class ClaudeReadinessProbeGate {
    private let lock = NSLock()
    private var inFlight = false

    public init() {}

    public func begin() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !inFlight else {
            return false
        }
        inFlight = true
        return true
    }

    public func finish() {
        lock.lock()
        inFlight = false
        lock.unlock()
    }
}

public final class ClaudeLoginAttemptGate {
    private let lock = NSLock()
    private var nextAttempt = 0
    private var activeAttempt: Int?

    public init() {}

    public func begin() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        nextAttempt += 1
        activeAttempt = nextAttempt
        return nextAttempt
    }

    public func finish(_ attempt: Int) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard activeAttempt == attempt else {
            return false
        }
        activeAttempt = nil
        return true
    }
}

public enum ClaudeLaunchState: Equatable {
    case probingClaude
    case loggedOut
    case openingClaude
    case missingClaude
    case missingClaudeLogin
    case missingPDTMCP
    case probeFailed
    case fetchingPortfolio
    case portfolioFetchFailed
}

public enum ClaudeAuthStatusParser {
    public static func isLoggedIn(stdout: String) -> Bool {
        loggedInStatus(stdout: stdout) == true
    }

    public static func loggedInStatus(stdout: String) -> Bool? {
        for line in stdout.split(whereSeparator: \.isNewline) {
            if let loggedIn = loggedInStatusFromJSONObject(String(line)) {
                return loggedIn
            }
        }
        return loggedInStatusFromJSONObject(stdout)
    }

    private static func loggedInStatusFromJSONObject(_ output: String) -> Bool? {
        let jsonOutput = firstJSONObject(in: output) ?? output
        guard let data = jsonOutput.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool
        else {
            return nil
        }
        return loggedIn
    }

    private static func firstJSONObject(in output: String) -> String? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        return String(output[start...end])
    }
}

public enum ClaudeLoginHandoffOutcome: Equatable {
    case succeeded
    case failed
}

public enum ClaudeLoginHandoffAction: Equatable {
    case recheckReadiness
    case showMissingClaude
}

public enum ClaudeLoginFailureReason: Equatable, Sendable {
    case missingBinary
    case timedOut
    case failed
    case launchFailed
}

public enum ClaudeLaunchFlow {
    public static func state(afterReadinessProbe result: ClaudeReadinessProbeResult?) -> ClaudeLaunchState {
        guard let result else {
            return .probingClaude
        }
        switch result {
        case .ready:
            return .fetchingPortfolio
        case .notReady:
            return .loggedOut
        case .missingClaudeLogin:
            return .missingClaudeLogin
        case .missingPDTMCP:
            return .missingPDTMCP
        case .failed:
            return .probeFailed
        }
    }

    public static func action(afterLoginHandoff outcome: ClaudeLoginHandoffOutcome) -> ClaudeLoginHandoffAction {
        switch outcome {
        case .succeeded:
            return .recheckReadiness
        case .failed:
            return .showMissingClaude
        }
    }

    public static func descriptor(
        for state: ClaudeLaunchState,
        cachedPulse: MenuDescriptor? = nil,
        fetchingElapsedSeconds: Int? = nil
    ) -> MenuDescriptor {
        if let cachedPulse {
            switch state {
            case .probingClaude:
                return cachedPulseDescriptor(
                    cachedPulse,
                    rows: [
                        MenuRow(
                            id: "portfolioFetch.probing",
                            role: .fetchStatus,
                            title: "Checking Claude setup",
                            detail: "Keeping last pulse visible"
                        ),
                    ]
                )
            case .fetchingPortfolio:
                return cachedPulseDescriptor(
                    cachedPulse,
                    rows: [
                        MenuRow(
                            id: "portfolioFetch.refreshing",
                            role: .fetchStatus,
                            title: "Refreshing portfolio",
                            detail: fetchingDetail(
                                elapsedSeconds: fetchingElapsedSeconds,
                                fallback: "Keeping last pulse visible"
                            )
                        ),
                    ]
                )
            case .portfolioFetchFailed:
                return descriptorForBackgroundRefreshFailure(cachedPulse: cachedPulse)
            case .loggedOut, .openingClaude, .missingClaude, .missingClaudeLogin, .missingPDTMCP, .probeFailed:
                break
            }
        }

        switch state {
        case .probingClaude:
            return MenuDescriptor(
                statusTitle: "Checking Claude",
                statusVisual: StatusVisualState(isDimmed: true),
                sections: [
                    MenuSection(
                        id: "claudeSetup",
                        title: "Claude",
                        rows: [
                            MenuRow(
                                id: "claudeSetup.probing",
                                role: .setupProbe,
                                title: "Checking Claude setup",
                                detail: "No prompts opened"
                            ),
                            MenuRow(
                                id: "claudeSetup.login",
                                role: .setupLogin,
                                title: "Log in with Claude"
                            ),
                        ]
                    ),
                ]
            )
        case .loggedOut:
            return ClaudeSetupMenuDescriptor.loggedOut()
        case .openingClaude:
            return MenuDescriptor(
                statusTitle: "Signing in with Claude",
                statusVisual: StatusVisualState(isDimmed: true),
                sections: [
                    MenuSection(
                        id: "claudeSetup",
                        title: "Claude",
                        rows: [
                            MenuRow(
                                id: "claudeSetup.opening",
                                role: .setupStatus,
                                title: "Signing in with Claude",
                                detail: "Finish the Claude auth login flow"
                            ),
                            MenuRow(
                                id: "claudeSetup.login",
                                role: .setupLogin,
                                title: "Try login again"
                            ),
                        ]
                    ),
                ]
            )
        case .missingClaude:
            return ClaudeSetupMenuDescriptor.missingClaude()
        case .missingClaudeLogin:
            return ClaudeSetupMenuDescriptor.missingClaudeLogin()
        case .missingPDTMCP:
            return ClaudeSetupMenuDescriptor.missingPDTMCP()
        case .probeFailed:
            return MenuDescriptor(
                statusTitle: "Could not check Claude",
                statusVisual: StatusVisualState(isDimmed: true),
                sections: [
                    MenuSection(
                        id: "claudeSetup",
                        title: "Claude",
                        rows: [
                            MenuRow(
                                id: "claudeSetup.probeFailed",
                                role: .setupFailure,
                                title: "Could not check Claude",
                                detail: "Claude setup can be checked again"
                            ),
                            MenuRow(
                                id: "claudeSetup.login",
                                role: .setupLogin,
                                title: "Log in with Claude"
                            ),
                        ]
                    ),
                ]
            )
        case .fetchingPortfolio:
            let detail = fetchingDetail(
                elapsedSeconds: fetchingElapsedSeconds,
                fallback: "Read-only through Claude"
            )
            let statusTitle = fetchingElapsedSeconds.map {
                "Fetching portfolio \(formatElapsedSeconds($0))"
            } ?? "Fetching portfolio"
            return MenuDescriptor(
                statusTitle: statusTitle,
                statusVisual: StatusVisualState(
                    isDimmed: true,
                    statusCopy: statusTitle
                ),
                sections: [
                    MenuSection(
                        id: "portfolioFetch",
                        title: "Portfolio",
                        rows: [
                            MenuRow(
                                id: "portfolioFetch.status",
                                role: .fetchStatus,
                                title: "Fetching portfolio",
                                detail: detail
                            ),
                        ]
                    ),
                ]
            )
        case .portfolioFetchFailed:
            return MenuDescriptor(
                statusTitle: "Could not fetch portfolio",
                statusVisual: StatusVisualState(isDimmed: true),
                sections: [
                    MenuSection(
                        id: "portfolioFetch",
                        title: "Portfolio",
                        rows: portfolioFetchFailureRows()
                    ),
                ]
            )
        }
    }

    public static func descriptorWithRefreshDetailsAction(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse,
            rows: [
                MenuRow(
                    id: "portfolioFetch.refreshDetails",
                    role: .fetchRetry,
                    title: "Refresh details",
                    detail: "Fill income and detail data"
                ),
            ]
        )
    }

    public static func descriptorForBackgroundRefreshFailure(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse,
            statusVisual: cachedPulse.statusVisual.withDimming(true),
            rows: [
                MenuRow(
                    id: "portfolioFetch.backgroundFailed",
                    role: .fetchStatus,
                    title: "Details fill failed",
                    detail: "Last pulse is still visible"
                ),
                MenuRow(
                    id: "portfolioFetch.retry",
                    role: .fetchRetry,
                    title: "Fill details again"
                ),
            ]
        )
    }

    public static func formatElapsedSeconds(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }

    private static func fetchingDetail(elapsedSeconds: Int?, fallback: String) -> String {
        guard let elapsedSeconds else {
            return fallback
        }
        return "\(fallback) - working for \(formatElapsedSeconds(elapsedSeconds))"
    }

    public static func descriptor(forLoginFailure reason: ClaudeLoginFailureReason) -> MenuDescriptor {
        let title: String
        let detail: String
        switch reason {
        case .missingBinary:
            title = "Claude CLI not found"
            detail = "Install Claude Code CLI"
        case .timedOut:
            title = "Claude login timed out"
            detail = "Try again"
        case .failed:
            title = "Claude login failed"
            detail = "Try again"
        case .launchFailed:
            title = "Could not start claude auth login"
            detail = "Try again"
        }
        return MenuDescriptor(
            statusTitle: title,
            statusVisual: StatusVisualState(isDimmed: true),
            sections: [
                MenuSection(
                    id: "claudeSetup",
                    title: "Claude",
                    rows: [
                        MenuRow(
                            id: "claudeSetup.loginFailure",
                            role: .setupFailure,
                            title: title,
                            detail: detail
                        ),
                        MenuRow(
                            id: "claudeSetup.login",
                            role: .setupLogin,
                            title: "Log in with Claude"
                        ),
                    ]
                ),
            ]
        )
    }

    private static func cachedPulseDescriptor(
        _ cachedPulse: MenuDescriptor,
        statusVisual: StatusVisualState? = nil,
        rows: [MenuRow]
    ) -> MenuDescriptor {
        MenuDescriptor(
            statusTitle: cachedPulse.statusTitle,
            statusBadge: cachedPulse.statusBadge,
            statusVisual: statusVisual ?? cachedPulse.statusVisual,
            statusAccessibilityIdentifier: cachedPulse.statusAccessibilityIdentifier,
            sections: cachedPulse.sections + [
                MenuSection(
                    id: "portfolioFetch",
                    title: "Portfolio",
                    rows: rows
                ),
            ]
        )
    }

    private static func portfolioFetchFailureRows() -> [MenuRow] {
        [
            MenuRow(
                id: "portfolioFetch.failed",
                role: .fetchStatus,
                title: "Could not fetch portfolio",
                detail: "No partial pulse published"
            ),
            MenuRow(
                id: "portfolioFetch.retry",
                role: .fetchRetry,
                title: "Try again"
            ),
            MenuRow(
                id: "claudeSetup.login",
                role: .setupLogin,
                title: "Log in with Claude"
            ),
        ]
    }
}

public enum ClaudeSetupMenuDescriptor {
    public static func loggedOut() -> MenuDescriptor {
        MenuDescriptor(
            statusTitle: "Not connected",
            statusVisual: StatusVisualState(isDimmed: true),
            sections: [
                MenuSection(
                    id: "claudeSetup",
                    title: "Claude",
                    rows: [
                        MenuRow(
                            id: "claudeSetup.status",
                            role: .setupStatus,
                            title: "Not connected",
                            detail: "Use Claude CLI for PDT"
                        ),
                        MenuRow(
                            id: "claudeSetup.login",
                            role: .setupLogin,
                            title: "Log in with Claude"
                        ),
                    ]
                ),
            ]
        )
    }

    public static func missingClaude() -> MenuDescriptor {
        MenuDescriptor(
            statusTitle: "Claude CLI not found",
            statusVisual: StatusVisualState(isDimmed: true),
            sections: [
                MenuSection(
                    id: "claudeSetup",
                    title: "Claude",
                    rows: [
                        MenuRow(
                            id: "claudeSetup.missingClaude",
                            role: .setupFailure,
                            title: "Claude CLI not found",
                            detail: "Install Claude Code CLI"
                        ),
                        MenuRow(
                            id: "claudeSetup.login",
                            role: .setupLogin,
                            title: "Log in with Claude"
                        ),
                    ]
                ),
            ]
        )
    }

    public static func missingClaudeLogin() -> MenuDescriptor {
        MenuDescriptor(
            statusTitle: "Not connected",
            statusVisual: StatusVisualState(isDimmed: true),
            sections: [
                MenuSection(
                    id: "claudeSetup",
                    title: "Claude",
                    rows: [
                        MenuRow(
                            id: "claudeSetup.status",
                            role: .setupStatus,
                            title: "Not connected",
                            detail: "Sign in with Claude CLI"
                        ),
                        MenuRow(
                            id: "claudeSetup.login",
                            role: .setupLogin,
                            title: "Log in with Claude"
                        ),
                        MenuRow(
                            id: "claudeSetup.retry",
                            role: .setupRetry,
                            title: "Check again"
                        ),
                    ]
                ),
            ]
        )
    }

    public static func missingPDTMCP() -> MenuDescriptor {
        MenuDescriptor(
            statusTitle: "Add the PDT MCP server to Claude",
            statusVisual: StatusVisualState(isDimmed: true),
            sections: [
                MenuSection(
                    id: "claudeSetup",
                    title: "Claude",
                    rows: [
                        MenuRow(
                            id: "claudeSetup.missingPDTMCP",
                            role: .setupFailure,
                            title: "Add the PDT MCP server to Claude",
                            detail: "Then check again"
                        ),
                        MenuRow(
                            id: "claudeSetup.login",
                            role: .setupLogin,
                            title: "Log in with Claude"
                        ),
                        MenuRow(
                            id: "claudeSetup.retry",
                            role: .setupRetry,
                            title: "Check again"
                        ),
                    ]
                ),
            ]
        )
    }
}

public enum MenuBarSurfaceRenderer {
    public static func render(descriptor: MenuDescriptor) -> MenuBarSurface {
        let statusTitle = descriptor.statusBadge.map { "\(descriptor.statusTitle) [\($0)]" }
            ?? descriptor.statusTitle
        let statusCopy = descriptor.statusVisual.statusCopy.isEmpty ? statusTitle : descriptor.statusVisual.statusCopy
        return MenuBarSurface(
            status: MenuBarStatusSurface(
                title: descriptor.statusTitle,
                badge: descriptor.statusBadge,
                menuBarTitle: "",
                visual: descriptor.statusVisual,
                accessibilityIdentifier: descriptor.statusAccessibilityIdentifier,
                accessibilityLabel: "PDTBar \(statusCopy)",
                toolTip: "PDTBar \(statusCopy)"
            ),
            sections: descriptor.sections.map { section in
                MenuBarSectionSurface(
                    id: section.id,
                    title: section.title,
                    accessibilityIdentifier: section.accessibilityIdentifier,
                    rows: section.rows.map(renderRow)
                )
            }
        )
    }

    private static func renderRow(_ row: MenuRow) -> MenuBarRowSurface {
        MenuBarRowSurface(
            id: row.id,
            role: row.role,
            title: row.detail.map { "\(row.title) - \($0)" } ?? row.title,
            accessibilityIdentifier: row.accessibilityIdentifier,
            children: row.children.map(renderRow)
        )
    }
}

public enum MenuDescriptorRenderer {
    private static let maxPulseAttentionItems = 3

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
                    detail: model.allQuietSignal.detail,
                    children: [
                        MenuRow(
                            id: "pulse.quiet.value",
                            title: "Value",
                            detail: display(model.portfolioGlance.totalValue)
                        ),
                        MenuRow(
                            id: "pulse.quiet.holdings",
                            title: "Open holdings",
                            detail: "\(model.portfolioGlance.openHoldingCount)"
                        ),
                        MenuRow(
                            id: "pulse.quiet.freshness",
                            title: "Latest prices",
                            detail: model.portfolioGlance.worstPriceAsOf ?? "Unknown"
                        ),
                    ]
                ),
            ]
        } else {
            pulseRows = model.rankedAttentionItems.prefix(maxPulseAttentionItems).map { item in
                MenuRow(
                    id: "\(item.id).glance",
                    role: .pulseAttention,
                    title: item.title,
                    detail: item.detail,
                    children: attentionChildren(for: item, supportingDataSlots: model.supportingDataSlots)
                )
            }
        }

        let statusSignal = model.allQuiet
            ? model.allQuietSignal.title
            : model.rankedAttentionItems.first?.title ?? "Attention"
        let statusTitle = "\(display(model.allQuietSignal.totalValue)) - \(statusSignal)"
        let statusVisual = statusVisual(for: model)

        return MenuDescriptor(
            statusTitle: statusTitle,
            statusBadge: model.rankedAttentionItems.isEmpty ? nil : "\(model.rankedAttentionItems.count)",
            statusVisual: statusVisual,
            sections: [
                MenuSection(
                    id: "pulse",
                    title: "Pulse",
                    rows: [
                        MenuRow(
                            id: "pulse.status",
                            role: .pulseSummary,
                            title: statusTitle
                        ),
                    ] + pulseRows
                ),
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: allocation.topHoldings.map { holding in
                        let attention = model.rankedAttentionItems.first { item in
                            item.facet == "allocation" && item.holdingIdentity?.quoteId == holding.quoteId
                        }
                        let drillDownDetail = attention.flatMap { item -> String? in
                            guard let currentWeight = item.currentWeight,
                                  item.threshold != nil
                            else { return nil }
                            return percent(currentWeight)
                        }
                        return MenuRow(
                            id: "allocation.\(holding.quoteId)",
                            role: drillDownDetail == nil ? .allocationHolding : .allocationDrillDown,
                            title: holding.name,
                            detail: drillDownDetail ?? percent(holding.weight),
                            children: allocationChildren(for: holding, attention: attention)
                        )
                    }
                ),
                MenuSection(
                    id: "income",
                    title: "Income",
                    rows: IncomeCalendarDescriptor.rows(
                        for: IncomeCalendar.build(events: income.upcomingEvents, asOf: model.asOf)
                    )
                ),
                MenuSection(
                    id: "bigMovers",
                    title: "Big movers",
                    rows: [
                        MenuRow(
                            id: "bigMovers.summary",
                            role: .bigMoverSummary,
                            title: bigMovers.maxMove.map { "Quote \($0.quoteId)" } ?? "No big movers",
                            detail: bigMovers.maxMove.map { "\(percent($0.percentChange)) over recent window" }
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

    private static func statusVisual(for model: PortfolioPulseModel) -> StatusVisualState {
        StatusVisualState(
            barHeights: concentrationBarHeights(from: model.facetSnapshots.allocation),
            filledBarCount: model.rankedAttentionItems.count,
            isDimmed: model.facetSnapshots.freshness.stale
        )
    }

    private static func concentrationBarHeights(from allocation: AllocationSnapshot) -> [Double] {
        let xRayWeights = (allocation.xRayHoldings ?? []).map(\.weight).filter { $0 > 0 }
        guard !xRayWeights.isEmpty else {
            return StatusVisualState().barHeights
        }
        return concentrationStackShape(fromXRayWeights: xRayWeights)
    }

    private static func concentrationStackShape(fromXRayWeights weights: [Double]) -> [Double] {
        let sortedWeights = weights
            .filter { $0 > 0 }
            .sorted(by: >)
        guard !sortedWeights.isEmpty else {
            return StatusVisualState().barHeights
        }
        let scale = concentrationSideScale(from: sortedWeights)
        return [
            rounded(0.5 * scale, places: 3),
            1.0,
            min(1.0, rounded(0.667 * scale, places: 3)),
        ]
    }

    private static func concentrationSideScale(from portfolioWeights: [Double]) -> Double {
        let hhi = portfolioWeights.reduce(0.0) { $0 + ($1 * $1) }
        let diversifiedHHI = 1.0 / 25.0
        let concentratedHHI = 0.16
        let pressure = max(0.0, min(1.0, (hhi - diversifiedHHI) / (concentratedHHI - diversifiedHHI)))
        return 1.25 - (0.5 * pressure)
    }

    private static func attentionChildren(
        for item: AttentionItem,
        supportingDataSlots: [SupportingDataSlot]
    ) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "\(item.id).severity",
                role: .pulseAttentionExpansion,
                title: "Pressure",
                detail: "\(item.facet) \(item.severity); score \(decimalString(String(item.score), places: 2))"
            ),
        ]
        if let detail = supportDetail(for: item) {
            rows.append(
                MenuRow(
                    id: "\(item.id).readout",
                    role: .pulseAttentionExpansion,
                    title: "Readout",
                    detail: detail
                )
            )
        }
        if !item.supportingDataSlotIDs.isEmpty {
            let slotLabelsByID = supportingDataSlots.reduce(into: [String: String]()) { labelsByID, slot in
                labelsByID[slot.id] = slot.label
            }
            let labels = item.supportingDataSlotIDs.map { slotLabelsByID[$0] ?? $0 }
            rows.append(
                MenuRow(
                    id: "\(item.id).sources",
                    role: .pulseAttentionExpansion,
                    title: "Sources",
                    detail: labels.joined(separator: ", ")
                )
            )
        }
        return rows
    }

    private static func allocationChildren(for holding: HoldingSummary, attention: AttentionItem?) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "allocation.\(holding.quoteId).weight",
                title: "Weight",
                detail: "\(bar(fraction: holding.weight)) \(percent(holding.weight))"
            ),
            MenuRow(
                id: "allocation.\(holding.quoteId).worth",
                title: "Worth",
                detail: display(holding.worth)
            ),
        ]
        if let attention,
           let threshold = attention.threshold
        {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).line",
                    title: "Concentration line",
                    detail: percent(threshold)
                )
            )
        }
        return rows
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
        return "\(bar(fraction: currentWeight)) \(percent(currentWeight)); line \(percent(threshold))"
    }

    private static func bar(fraction: Double) -> String {
        let width = 10
        let clamped = max(0.0, min(1.0, fraction))
        let filled = Int((clamped * Double(width)).rounded())
        return "[\(String(repeating: "#", count: filled))\(String(repeating: "-", count: width - filled))]"
    }
}

public enum PressureEngine {
    public static let concentrationThreshold = 0.20
    public static let bigMoverThreshold = 0.10
    private static let freshnessBusinessDayGrace = 1

    public static func buildModel(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot? = nil) -> PortfolioPulseModel {
        let rankedItems = ranked(
            concentrationItems(from: snapshot, priorSnapshot: priorSnapshot)
                + incomeItems(from: snapshot)
                + bigMoverItems(from: snapshot, priorSnapshot: priorSnapshot)
        )
        let totalValue = snapshot.totalValue
        let worstPriceAsOf = snapshot.openHoldings.map(\.priceAsOf).min()
        let freshnessStale = isFreshnessStale(worstPriceAsOf: worstPriceAsOf, asOf: snapshot.asOf)
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
                detail: "No attention items right now.",
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
                        .sorted(by: ranksByAllocation)
                        .map {
                            HoldingSummary(
                                name: $0.name,
                                quoteId: $0.quoteId,
                                weight: $0.weight,
                                worth: $0.worth
                            )
                        },
                    sectorBreakdown: snapshot.sectors,
                    assetTypeBreakdown: snapshot.assetTypes,
                    xRayHoldings: snapshot.xRayHoldings
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
                    stale: freshnessStale
                )
            ),
            supportingDataSlots: supportingDataSlots
        )
    }

    private static func isFreshnessStale(worstPriceAsOf: String?, asOf: String) -> Bool {
        guard let worstPriceAsOf,
              let priceDate = dayDate(from: worstPriceAsOf),
              let asOfDate = dayDate(from: asOf),
              priceDate < asOfDate
        else {
            return false
        }
        return businessDays(after: priceDate, through: asOfDate) > freshnessBusinessDayGrace
    }

    private static func businessDays(after start: Date, through end: Date) -> Int {
        let calendar = freshnessCalendar
        var date = calendar.date(byAdding: .day, value: 1, to: start)
        var count = 0
        while let current = date, current <= end {
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 {
                count += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: current)
        }
        return count
    }

    private static func dayDate(from value: String) -> Date? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return freshnessCalendar.date(
            from: DateComponents(
                calendar: freshnessCalendar,
                timeZone: freshnessCalendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }

    private static var freshnessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func ranked(_ items: [AttentionItem]) -> [AttentionItem] {
        items
            .sorted(by: ranksBefore)
            .enumerated()
            .map { offset, item in
                var rankedItem = item
                rankedItem.rank = offset + 1
                return rankedItem
            }
    }

    private static func ranksBefore(_ lhs: AttentionItem, _ rhs: AttentionItem) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.facet == "allocation",
           rhs.facet == "allocation",
           let lhsWeight = lhs.currentWeight,
           let rhsWeight = rhs.currentWeight,
           lhsWeight != rhsWeight
        {
            return lhsWeight > rhsWeight
        }
        if lhs.facet == "allocation",
           rhs.facet == "allocation",
           let lhsName = lhs.holdingIdentity?.name,
           let rhsName = rhs.holdingIdentity?.name,
           lhsName != rhsName
        {
            return lhsName < rhsName
        }
        return lhs.id < rhs.id
    }

    private static func concentrationItems(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot?) -> [AttentionItem] {
        let priorHoldings = priorSnapshot?.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holding
        }
        return snapshot.openHoldings
            .filter { holding in
                guard holding.weight >= concentrationThreshold else { return false }
                guard priorSnapshot != nil else { return true }
                return (priorHoldings?[holding.quoteId]?.weight ?? 0) < concentrationThreshold
            }
            .sorted(by: ranksByAllocation)
            .enumerated()
            .map { offset, holding in
                let score = concentrationScore(weight: holding.weight, threshold: concentrationThreshold)
                return AttentionItem(
                    id: "allocation.concentration.\(holding.quoteId)",
                    facet: "allocation",
                    rank: offset + 1,
                    title: "\(holding.name) concentration",
                    detail: percent(holding.weight),
                    severity: score >= 0.8 ? "high" : "medium",
                    score: score,
                    holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
                    currentWeight: holding.weight,
                    threshold: concentrationThreshold,
                    supportingDataSlotIDs: ["allocation.holdings"]
                )
            }
    }

    private static func ranksByAllocation(_ lhs: NormalizedHolding, _ rhs: NormalizedHolding) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight > rhs.weight
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.quoteId < rhs.quoteId
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
                    changePercent: event.priorAmount == nil ? nil : event.changePercent,
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

public protocol PortfolioDataSource {
    func snapshot(asOf: String?) throws -> PortfolioSnapshot
}

public extension PortfolioDataSource {
    func snapshot() throws -> PortfolioSnapshot {
        try snapshot(asOf: nil)
    }
}

public protocol PortfolioPriorSnapshotDataSource {
    func priorSnapshot(asOf: String?) throws -> PortfolioSnapshot
}

public extension PortfolioPriorSnapshotDataSource {
    func priorSnapshot() throws -> PortfolioSnapshot {
        try priorSnapshot(asOf: nil)
    }
}

public protocol PDTLiveToolClient {
    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data
}

public enum PDTReadTools {
    public static let requiredV1 = [
        "pdt-get-portfolio-holdings",
        "pdt-get-portfolio-distributions",
        "pdt-list-x-ray-holdings",
        "pdt-list-calendar-events",
        "pdt-list-dividends",
        "pdt-list-symbol-prices",
        "pdt-get-symbol-quote",
    ]

    public static func missingRequiredV1Tools(in availableTools: Set<String>) -> [String] {
        requiredV1.filter { !availableTools.contains($0) }
    }
}

public protocol PDTMCPConnector {
    func availableReadTools() throws -> Set<String>
    func availableReadTools(required: Set<String>) throws -> Set<String>
    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data
}

public extension PDTMCPConnector {
    func availableReadTools(required: Set<String>) throws -> Set<String> {
        try availableReadTools().intersection(required)
    }
}

public enum PDTMCPConnectorError: Error, CustomStringConvertible, Equatable {
    case missingRequiredReadTools([String])
    case setupUnavailable(String)
    case transientFailure(String)
    case nonReadTool(String)
    case missingScriptedResponse(String)

    public var description: String {
        switch self {
        case .missingRequiredReadTools(let tools):
            "PDT MCP connector missing required read tools: \(tools.joined(separator: ", "))"
        case .setupUnavailable(let message):
            "PDT MCP connector setup unavailable: \(message)"
        case .transientFailure(let message):
            "PDT MCP connector transient failure: \(message)"
        case .nonReadTool(let tool):
            "PDT MCP connector refused non-v1 read tool: \(tool)"
        case .missingScriptedResponse(let key):
            "PDT MCP connector missing scripted response for \(key)"
        }
    }
}

public struct PDTMCPConnectorDataSource: PortfolioDataSource {
    public var connector: any PDTMCPConnector
    public var liveOptions: PDTLiveDataSourceOptions

    public init(
        connector: any PDTMCPConnector,
        liveOptions: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions()
    ) {
        self.connector = connector
        self.liveOptions = liveOptions
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        let requiredTools = Set(liveOptions.requiredReadTools)
        let availableTools = try connector.availableReadTools(required: requiredTools)
        let missing = liveOptions.requiredReadTools.filter { !availableTools.contains($0) }
        guard missing.isEmpty else {
            throw PDTMCPConnectorError.missingRequiredReadTools(missing)
        }
        return try PDTLiveDataSource(
            toolClient: PDTMCPConnectorToolClient(connector: connector),
            options: liveOptions
        ).snapshot(asOf: asOf)
    }
}

public struct PDTMCPConnectorToolClient: PDTLiveToolClient {
    public var connector: any PDTMCPConnector

    public init(connector: any PDTMCPConnector) {
        self.connector = connector
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        guard PDTReadTools.requiredV1.contains(name) else {
            throw PDTMCPConnectorError.nonReadTool(name)
        }
        return try connector.callReadTool(name, arguments: arguments)
    }
}

public final class ScriptedPDTMCPConnector: PDTMCPConnector {
    public var availableTools: Set<String>
    public var responses: [String: Data]
    public var failure: PDTMCPConnectorError?
    public var initialCallDelaySeconds: Double?
    public private(set) var availabilityChecks = 0
    public private(set) var calls: [String] = []

    public init(
        availableTools: Set<String> = Set(PDTReadTools.requiredV1),
        responses: [String: Data],
        failure: PDTMCPConnectorError? = nil,
        initialCallDelaySeconds: Double? = nil
    ) {
        self.availableTools = availableTools
        self.responses = responses
        self.failure = failure
        self.initialCallDelaySeconds = initialCallDelaySeconds
    }

    public func availableReadTools() throws -> Set<String> {
        availabilityChecks += 1
        return availableTools
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        calls.append(name)
        if let delay = initialCallDelaySeconds, delay > 0 {
            initialCallDelaySeconds = nil
            Thread.sleep(forTimeInterval: delay)
        }
        if let failure {
            throw failure
        }
        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(key)
        }
        return response
    }
}

public enum ScriptedPDTMCPConnectorConfigurationError: Error, Equatable {
    case emptyResponses
}

public struct ScriptedPDTMCPConnectorConfiguration: Codable, Equatable, Sendable {
    public var availableTools: [String]?
    public var responses: [String: String]
    public var asOf: String?
    public var failure: String?
    public var failureMessage: String?
    public var initialCallDelaySeconds: Double?

    public init(
        availableTools: [String]? = nil,
        responses: [String: String],
        asOf: String? = nil,
        failure: String? = nil,
        failureMessage: String? = nil,
        initialCallDelaySeconds: Double? = nil
    ) {
        self.availableTools = availableTools
        self.responses = responses
        self.asOf = asOf
        self.failure = failure
        self.failureMessage = failureMessage
        self.initialCallDelaySeconds = initialCallDelaySeconds
    }

    public func connector() throws -> ScriptedPDTMCPConnector {
        guard !responses.isEmpty else {
            throw ScriptedPDTMCPConnectorConfigurationError.emptyResponses
        }
        return ScriptedPDTMCPConnector(
            availableTools: Set(availableTools ?? PDTReadTools.requiredV1),
            responses: responses.mapValues { Data($0.utf8) },
            failure: scriptedFailure(),
            initialCallDelaySeconds: initialCallDelaySeconds
        )
    }

    private func scriptedFailure() -> PDTMCPConnectorError? {
        guard let failure else {
            return nil
        }
        let message = failureMessage ?? "scripted PDT MCP failure"
        switch failure {
        case "setupUnavailable", "authSetupError":
            return .setupUnavailable(message)
        case "transientFailure":
            return .transientFailure(message)
        default:
            return .transientFailure(message)
        }
    }
}

public final class PDTCoalescedFirstPortfolioFetch {
    private let lock = NSLock()
    private var result: PressureRunResult?
    private let dataSource: any PortfolioDataSource
    private let snapshotStore: SnapshotStore
    private let asOf: String?

    public init(
        dataSource: any PortfolioDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil
    ) {
        self.dataSource = dataSource
        self.snapshotStore = snapshotStore
        self.asOf = asOf
    }

    public func fetch() throws -> PressureRunResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        if let result {
            return result
        }
        let freshResult = try PressureRunner.run(
            dataSource: dataSource,
            snapshotStore: snapshotStore,
            asOf: asOf
        )
        result = freshResult
        return freshResult
    }
}

public enum PDTLiveDataSourceError: Error, CustomStringConvertible {
    case malformedToolResult(String)
    case unavailableToolResult(String)

    public var shouldSkipLiveSmoke: Bool {
        switch self {
        case .unavailableToolResult:
            true
        case .malformedToolResult:
            false
        }
    }

    public var description: String {
        switch self {
        case .malformedToolResult(let tool):
            "live PDT tool \(tool) did not return the expected read-only JSON shape"
        case .unavailableToolResult(let tool):
            "live PDT tool \(tool) reported missing auth or unavailable local access"
        }
    }
}

public enum PDTLiveUnavailableClassifier {
    public static func shouldSkip(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            return unavailableTexts(in: object).contains(where: containsUnavailablePhrase)
        }
        return containsUnavailablePhrase(trimmed)
    }

    private static func containsUnavailablePhrase(_ value: String) -> Bool {
        let lower = value.lowercased()
        return unavailablePhrases.contains { lower.contains($0) }
    }

    private static let unavailablePhrases = [
        "not authenticated",
        "authentication required",
        "oauth",
        "missing credential",
        "credentials not found",
        "login required",
        "please login",
        "not logged in",
        "token expired",
        "session expired",
        "unauthorized",
        "forbidden",
        "offline",
        "connection refused",
        "failed to connect",
        "could not connect",
        "econnrefused",
        "server not found",
        "server unavailable",
    ]

    private static let errorTextKeys = Set([
        "error",
        "message",
        "detail",
        "details",
        "description",
        "status",
        "code",
    ])

    private static func unavailableTexts(in object: Any, forceErrorContext: Bool = false) -> [String] {
        if let string = object as? String {
            if forceErrorContext {
                return [string]
            }
            if let data = string.data(using: .utf8),
               let nested = try? JSONSerialization.jsonObject(with: data)
            {
                return unavailableTexts(in: nested)
            }
            return []
        }
        if let array = object as? [Any] {
            return forceErrorContext ? array.flatMap { unavailableTexts(in: $0, forceErrorContext: true) } : []
        }
        guard let dictionary = object as? [String: Any] else {
            return []
        }

        let isError = forceErrorContext || dictionary["isError"] as? Bool == true || dictionary["is_error"] as? Bool == true
        var texts: [String] = []
        for (key, value) in dictionary {
            if errorTextKeys.contains(key) {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            } else if key == "content", isError {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            } else if isError && (key == "text" || key == "title") {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            }
        }
        return texts
    }
}

public struct PDTLiveDataSourceOptions: Equatable, Sendable {
    public var includeDistributions: Bool
    public var includeXRayHoldings: Bool
    public var includeIncomeEvents: Bool
    public var includeDividends: Bool
    public var includeIncomeQuoteLookups: Bool
    public var includePriceSeries: Bool

    public init(
        includeDistributions: Bool = true,
        includeXRayHoldings: Bool = true,
        includeIncomeEvents: Bool = true,
        includeDividends: Bool = true,
        includeIncomeQuoteLookups: Bool = true,
        includePriceSeries: Bool = true
    ) {
        self.includeDistributions = includeDistributions
        self.includeXRayHoldings = includeXRayHoldings
        self.includeIncomeEvents = includeIncomeEvents
        self.includeDividends = includeDividends
        self.includeIncomeQuoteLookups = includeIncomeQuoteLookups
        self.includePriceSeries = includePriceSeries
    }

    public var requiredReadTools: [String] {
        var tools = ["pdt-get-portfolio-holdings"]
        if includeDistributions {
            tools.append("pdt-get-portfolio-distributions")
        }
        if includeXRayHoldings {
            tools.append("pdt-list-x-ray-holdings")
        }
        if includeIncomeEvents {
            tools.append("pdt-list-calendar-events")
        }
        if includeDividends {
            tools.append("pdt-list-dividends")
        }
        if includeIncomeQuoteLookups {
            tools.append("pdt-get-symbol-quote")
        }
        if includePriceSeries {
            tools.append("pdt-list-symbol-prices")
        }
        return tools
    }
}

public struct PDTLiveDataSource: PortfolioDataSource {
    public var toolClient: any PDTLiveToolClient
    public var options: PDTLiveDataSourceOptions

    public init(
        toolClient: any PDTLiveToolClient,
        options: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions()
    ) {
        self.toolClient = toolClient
        self.options = options
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        let snapshotAsOf = asOf ?? currentDayString()
        let incomeDateRange = [
            "date_from": snapshotAsOf,
            "date_to": dayString(snapshotAsOf, addingDays: 30),
        ]
        let dividendDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -370),
            "date_to": incomeDateRange["date_to"] ?? snapshotAsOf,
        ]
        let holdingsEnvelope: LiveHoldingsEnvelope = try decodeLiveTool(
            "pdt-get-portfolio-holdings",
            data: toolClient.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        )
        let distributionsEnvelope: LiveDistributionsEnvelope? = options.includeDistributions
            ? try decodeLiveTool(
                "pdt-get-portfolio-distributions",
                data: toolClient.callReadTool("pdt-get-portfolio-distributions", arguments: [:])
            )
            : nil
        let xRayHoldings = options.includeXRayHoldings ? try liveXRayHoldings() : []
        let calendarEvents: [LiveCalendarEvent]
        if options.includeIncomeEvents {
            let calendarEnvelope: LiveCalendarEventsEnvelope = try decodeLiveTool(
                "pdt-list-calendar-events",
                data: toolClient.callReadTool("pdt-list-calendar-events", arguments: incomeDateRange)
            )
            calendarEvents = calendarEnvelope.data
        } else {
            calendarEvents = []
        }
        let dividends = options.includeDividends ? try liveDividends(arguments: dividendDateRange) : []

        let openHoldings = holdingsEnvelope.holdings
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
        let quoteIDsBySymbolID = options.includeIncomeQuoteLookups
            ? try liveQuoteIDsBySymbolID(for: openHoldings)
            : [:]
        let dividendsByQuoteID = Dictionary(
            grouping: dividends,
            by: \.symbolQuoteId
        )
        let currency = openHoldings.first?.worth.currency ?? "EUR"
        let priceSeries = options.includePriceSeries
            ? try livePriceSeries(for: openHoldings, asOf: snapshotAsOf)
            : []

        return PortfolioSnapshot(
            asOf: snapshotAsOf,
            totalValue: sumWorth(openHoldings, currency: currency),
            openHoldings: openHoldings,
            sectors: distributionsEnvelope?.sectors.map(\.summary) ?? [],
            assetTypes: distributionsEnvelope?.assetTypes.map(\.summary) ?? [],
            xRayHoldings: xRayHoldings,
            incomeEvents: calendarEvents.filter { $0.type != "no-events-today" }.map {
                let quoteId = $0.symbolId.flatMap { quoteIDsBySymbolID[$0] }
                let amount = $0.type == "ex-dividend" && !$0.isEstimated
                    ? latestLiveDividendAmount(for: quoteId, dividendsByQuoteID: dividendsByQuoteID)
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
            priceSeries: priceSeries
        )
    }

    private func liveQuoteIDsBySymbolID(for holdings: [NormalizedHolding]) throws -> [Int: Int] {
        var idsBySymbolID: [Int: Int] = [:]
        for holding in holdings {
            let quote: LiveSymbolQuoteEnvelope = try decodeLiveTool(
                "pdt-get-symbol-quote",
                data: toolClient.callReadTool("pdt-get-symbol-quote", arguments: ["id": String(holding.quoteId)])
            )
            idsBySymbolID[quote.symbolId] = quote.id
        }
        return idsBySymbolID
    }

    private func liveXRayHoldings() throws -> [XRayHoldingSummary] {
        let limit = 500
        var offset = 0
        var holdings: [XRayHoldingSummary] = []
        while true {
            let envelope: XRayHoldingsEnvelope = try decodeLiveTool(
                "pdt-list-x-ray-holdings",
                data: toolClient.callReadTool(
                    "pdt-list-x-ray-holdings",
                    arguments: ["limit": String(limit), "offset": String(offset)]
                )
            )
            holdings.append(contentsOf: envelope.items.map {
                XRayHoldingSummary(weight: normalizedXRayPortfolioWeight($0.weight))
            })
            guard envelope.hasMore == true, !envelope.items.isEmpty else {
                return holdings
            }
            offset += limit
        }
    }

    private func liveDividends(arguments baseArguments: [String: String]) throws -> [LiveDividend] {
        var page = 1
        var dividends: [LiveDividend] = []
        while true {
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": "250",
            ]) { _, new in new }
            let envelope: LiveDividendsEnvelope = try decodeLiveTool(
                "pdt-list-dividends",
                data: toolClient.callReadTool("pdt-list-dividends", arguments: arguments)
            )
            dividends.append(contentsOf: envelope.data)
            let lastPage = envelope.meta?.lastPage ?? page
            guard page < lastPage else {
                return dividends
            }
            page += 1
        }
    }

    private func livePriceSeries(for holdings: [NormalizedHolding], asOf: String) throws -> [PricePoint] {
        let priceDateRange = [
            "date_from": dayString(asOf, addingDays: -7),
            "date_to": asOf,
        ]
        return try holdings.flatMap { holding in
            let prices: LivePricesEnvelope = try decodeLiveTool(
                "pdt-list-symbol-prices",
                data: toolClient.callReadTool(
                    "pdt-list-symbol-prices",
                    arguments: priceDateRange.merging(["symbol_quote_id": String(holding.quoteId)]) { _, new in new }
                )
            )
            return prices.data.map {
                PricePoint(
                    quoteId: $0.symbolQuoteId,
                    date: $0.date,
                    closeAdjusted: $0.closeAdjusted
                )
            }
        }
    }
}

public enum PressureRunner {
    public static func cachedPulseDescriptor(snapshotStore: SnapshotStore) throws -> MenuDescriptor? {
        guard let snapshot = try snapshotStore.loadPriorSnapshot() else {
            return nil
        }
        return MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
    }

    public static func seedPriorSnapshot(
        dataSource: any PortfolioPriorSnapshotDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil
    ) throws -> SnapshotCommit {
        let priorSnapshot = try dataSource.priorSnapshot(asOf: asOf)
        return try snapshotStore.commitCurrentSnapshot(priorSnapshot)
    }

    public static func seedPriorSnapshot(fixture: URL, snapshotDirectory: URL) throws -> SnapshotCommit {
        try seedPriorSnapshot(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: SnapshotStore(directory: snapshotDirectory)
        )
    }

    public static func run(
        dataSource: any PortfolioDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil
    ) throws -> PressureRunResult {
        let snapshot = try dataSource.snapshot(asOf: asOf)
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

    public static func run(fixture: URL, snapshotDirectory: URL) throws -> PressureRunResult {
        try run(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: SnapshotStore(directory: snapshotDirectory)
        )
    }
}

public struct SnapshotStore: Sendable {
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
    public var xRayHoldings: [XRayHoldingSummary]?
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
        let holdings = rawHoldings
            .filter { $0.closedAt == nil && $0.hasLiveWorth }
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
            xRayHoldings: payload.listXRayHoldings?.items.map { XRayHoldingSummary(weight: normalizedXRayPortfolioWeight($0.weight)) },
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
    var listXRayHoldings: XRayHoldingsEnvelope?
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
        case listXRayHoldings
        case listCalendarEvents
        case listDividends
        case listSymbolPrices
        case getSymbolQuote
        case getSymbolQuotes
    }
}

private struct LiveHoldingsEnvelope: Decodable {
    var holdings: [LiveHolding]
}

private struct LiveHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
    var currentPriceDate: String
    var currentPriceLocal: Money
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var closedAt: String?
}

private struct XRayHoldingsEnvelope: Decodable {
    var items: [XRayHolding]
    var hasMore: Bool?
}

private struct XRayHolding: Decodable {
    var weight: Double
}

private struct LiveDistributionsEnvelope: Decodable {
    var sectors: [LiveDistribution]
    var assetTypes: [LiveDistribution]
}

private struct LiveDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var summary: DistributionSummary {
        DistributionSummary(name: categoryName, percentage: percentage, totalValue: totalValue)
    }
}

private struct LiveCalendarEventsEnvelope: Decodable {
    var data: [LiveCalendarEvent]
}

private struct LiveCalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolId: Int?
    var symbolName: String?
}

private struct LiveDividendsEnvelope: Decodable {
    var data: [LiveDividend]
    var meta: LivePaginationMeta?
}

private struct LivePaginationMeta: Decodable {
    var lastPage: Int

    enum CodingKeys: String, CodingKey {
        case lastPage
        case lastPageSnake = "last_page"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPageSnake)
            ?? container.decodeIfPresent(Int.self, forKey: .lastPage)
            ?? 1
    }
}

private struct LiveDividend: Decodable {
    var date: String
    var amount: Money
    var symbolQuoteId: Int
}

private struct LiveSymbolQuoteEnvelope: Decodable {
    var id: Int
    var symbolId: Int
}

private struct LivePricesEnvelope: Decodable {
    var data: [LivePrice]
}

private struct LivePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var symbolQuoteId: Int
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
    var currentWorth: Money?
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var closedAt: String?
}

private extension FixtureHolding {
    var hasLiveWorth: Bool {
        !currentWorthLocal.isZero && !(currentWorth?.isZero ?? false)
    }
}

private extension Money {
    var isZero: Bool {
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            return false
        }
        return amount == 0
    }
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

private func decodeLiveTool<T: Decodable>(_ tool: String, data: Data) throws -> T {
    var diagnosticPayloads = [String(data: data, encoding: .utf8)].compactMap { $0 }
    if let payloadData = try? extractedMCPPayloadData(from: data),
       let decoded = try? JSONDecoder().decode(T.self, from: payloadData)
    {
        return decoded
    } else if let payloadData = try? extractedMCPPayloadData(from: data),
              let diagnostic = String(data: payloadData, encoding: .utf8)
    {
        diagnosticPayloads.append(diagnostic)
    }
    if let decoded = try? JSONDecoder().decode(T.self, from: data) {
        return decoded
    }
    if diagnosticPayloads.contains(where: PDTLiveUnavailableClassifier.shouldSkip) {
        throw PDTLiveDataSourceError.unavailableToolResult(tool)
    }
    throw PDTLiveDataSourceError.malformedToolResult(tool)
}

private func extractedMCPPayloadData(from data: Data) throws -> Data? {
    let object = try JSONSerialization.jsonObject(with: data)
    return extractedMCPPayloadData(from: object)
}

private func extractedMCPPayloadData(from object: Any) -> Data? {
    if let dictionary = object as? [String: Any] {
        if let content = dictionary["content"] as? [Any] {
            for item in content {
                guard let item = item as? [String: Any],
                      let text = item["text"] as? String,
                      let textData = text.data(using: .utf8)
                else { continue }
                return textData
            }
        }
        for key in ["result", "data"] {
            guard let nested = dictionary[key],
                  let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
            else { continue }
            return nestedData
        }
    }
    return nil
}

private func latestLiveDividendAmount(
    for quoteId: Int?,
    dividendsByQuoteID: [Int: [LiveDividend]]
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

private func currentDayString() -> String {
    dayString(from: Date())
}

private func dayString(_ day: String, addingDays days: Int) -> String {
    let formatter = dayFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = formatter.date(from: day),
          let shifted = calendar.date(byAdding: .day, value: days, to: date)
    else {
        return day
    }
    return dayString(from: shifted)
}

private func dayString(from date: Date) -> String {
    dayFormatter().string(from: date)
}

private func dayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

private func display(_ money: Money) -> String {
    "\(money.currency) \(decimalString(money.value, places: 2))"
}

private func percent(_ value: Double) -> String {
    "\(decimalString(String(value * 100), places: 1))%"
}

private func normalizedXRayPortfolioWeight(_ value: Double) -> Double {
    value / 100.0
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
