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
    public var windowStart: String?
    public var windowEnd: String?
    public var resetsReadState: Bool
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
        windowStart: String? = nil,
        windowEnd: String? = nil,
        resetsReadState: Bool = false,
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
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.resetsReadState = resetsReadState
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
        windowStart = try container.decodeIfPresent(String.self, forKey: .windowStart)
        windowEnd = try container.decodeIfPresent(String.self, forKey: .windowEnd)
        resetsReadState = try container.decodeIfPresent(Bool.self, forKey: .resetsReadState) ?? false
        supportingDataSlotIDs = try container.decode([String].self, forKey: .supportingDataSlotIDs)
    }
}

public extension AttentionItem {
    private var readFingerprintIdentity: String {
        holdingIdentity.map { "quote:\($0.quoteId)" }
            ?? "id:\(fingerprintToken(id))"
    }

    var readFingerprint: String {
        switch facet {
        case "allocation":
            return [
                "pulse:v1:allocation",
                readFingerprintIdentity,
                "threshold-bp:\(fingerprintBasisPoints(threshold))",
                "severity:\(fingerprintToken(severity))",
                "weight-bucket-bp:\(bucketBasisPoints(currentWeight, bucketSize: 100))",
            ].joined(separator: ":")
        case "income":
            return [
                "pulse:v1:income",
                readFingerprintIdentity,
                "date:\(eventDate ?? "unknown")",
                "amount:\(moneyFingerprint(amount))",
                "change-bp:\(fingerprintBasisPoints(changePercent))",
            ].joined(separator: ":")
        case "bigMovers":
            return [
                "pulse:v1:bigMovers",
                readFingerprintIdentity,
                "window:\(windowStart ?? "unknown")..\(windowEnd ?? "unknown")",
                "move-bucket-bp:\(bucketBasisPoints(moveSize, bucketSize: 100))",
            ].joined(separator: ":")
        default:
            return [
                "pulse:v1",
                fingerprintToken(facet),
                readFingerprintIdentity,
                "severity:\(fingerprintToken(severity))",
                "score-bp:\(fingerprintBasisPoints(score))",
            ].joined(separator: ":")
        }
    }

    var staleReadPruningPrefix: String? {
        switch facet {
        case "income":
            return ["pulse:v1:income", readFingerprintIdentity].joined(separator: ":") + ":"
        case "bigMovers":
            return ["pulse:v1:bigMovers", readFingerprintIdentity].joined(separator: ":") + ":"
        default:
            return nil
        }
    }

    var concentrationReadFingerprintPrefix: String? {
        guard facet == "allocation" else {
            return nil
        }
        return [
            "pulse:v1:allocation",
            readFingerprintIdentity,
            "threshold-bp:\(fingerprintBasisPoints(threshold))",
        ].joined(separator: ":") + ":"
    }
}

public struct PulseReadState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var readFingerprints: [String]

    public init(schemaVersion: Int = 1, readFingerprints: [String] = []) {
        self.schemaVersion = schemaVersion
        self.readFingerprints = Array(Set(readFingerprints)).sorted()
    }

    public func contains(_ fingerprint: String) -> Bool {
        Set(readFingerprints).contains(fingerprint)
    }
}

public struct PulseReadStore: Sendable {
    public var directory: URL
    private static let mutationQueue = DispatchQueue(label: "PDTBarCore.PulseReadStore.mutation")

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> PulseReadState {
        try Self.mutationQueue.sync {
            try loadUnlocked()
        }
    }

    public func save(_ state: PulseReadState) throws {
        try Self.mutationQueue.sync {
            try saveUnlocked(state)
        }
    }

    public func markRead(_ fingerprint: String) throws {
        try Self.mutationQueue.sync {
            var state = try loadUnlocked()
            state = PulseReadState(
                schemaVersion: state.schemaVersion,
                readFingerprints: state.readFingerprints + [fingerprint]
            )
            try saveUnlocked(state)
        }
    }

    public func removeReadFingerprints(_ fingerprints: Set<String>) throws -> PulseReadState {
        try Self.mutationQueue.sync {
            let state = try loadUnlocked()
            let resetState = PulseReadState(
                schemaVersion: state.schemaVersion,
                readFingerprints: state.readFingerprints.filter { !fingerprints.contains($0) }
            )
            if resetState != state {
                try saveUnlocked(resetState)
            }
            return resetState
        }
    }

    private func loadUnlocked() throws -> PulseReadState {
        let target = stateFile
        guard FileManager.default.fileExists(atPath: target.path) else {
            return PulseReadState()
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            if !FileManager.default.fileExists(atPath: target.path) {
                return PulseReadState()
            }
            throw error
        }
        guard let state = try? JSONDecoder().decode(PulseReadState.self, from: data) else {
            return PulseReadState()
        }
        return state
    }

    private func saveUnlocked(_ state: PulseReadState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try stableJSONData(state).write(to: stateFile, options: .atomic)
    }

    private var stateFile: URL {
        directory.appending(path: "pulse-read-state.json")
    }
}

public enum PulseReadFilter {
    public static func apply(to model: PortfolioPulseModel, readState: PulseReadState) -> PortfolioPulseModel {
        let visibleItems = model.rankedAttentionItems.filter { !readState.contains($0.readFingerprint) }
        var filtered = model
        filtered.rankedAttentionItems = visibleItems
        filtered.attentionItems = visibleItems
        filtered.allQuiet = visibleItems.isEmpty
        if visibleItems.isEmpty, !model.rankedAttentionItems.isEmpty {
            filtered.allQuietSignal = AllQuietSignal(
                title: "All caught up",
                detail: "No unread items.",
                totalValue: model.allQuietSignal.totalValue
            )
        }
        return filtered
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
    public var price: Money?
    public var copyableIdentifier: String?
    public var recentMove: PriceMoveSummary?
    public var nextIncomeEvent: IncomeEventSummary?
    public var averageBuyPrice: Money?
    public var gainLoss: Money?
    public var gainLossPercentage: Double?
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
            .filter { isIncomeCalendarEventKind($0.kind) }
            .filter { $0.date >= asOf }
            .sorted(by: incomeCalendarEventRanksBefore)
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
                    actionTarget: incomeEventActionTarget(for: event, rowID: "income.next"),
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
        actionTarget: incomeEventActionTarget(for: event, rowID: id),
        title: event.symbolName,
        detail: incomeEventDetail(for: event),
        children: incomeEventChildren(for: event, rowID: id)
    )
}

private func incomeEventChildren(for event: IncomeEventSummary, rowID: String? = nil) -> [MenuRow] {
    let baseID = rowID ?? incomeEventRowID(for: event)
    func child(_ suffix: String, role: MenuRowRole, title: String, detail: String) -> MenuRow {
        let id = "\(baseID).\(suffix)"
        return MenuRow(
            id: id,
            role: role,
            actionTarget: incomeEventActionTarget(for: event, rowID: id),
            title: title,
            detail: detail
        )
    }
    return [
        child("date", role: .incomeEventDate, title: "Date", detail: event.date),
        child("kind", role: .incomeEventKind, title: "Kind", detail: incomeEventKindLabel(for: event.kind)),
        child("state", role: .incomeEventState, title: "State", detail: event.estimated ? "Estimated" : "Confirmed"),
        event.amount.map {
            child("amount", role: .incomeEventAmount, title: "Amount", detail: display($0))
        },
        incomeEventChangeDetail(for: event).map {
            child("change", role: .incomeEventChange, title: "Change", detail: $0)
        },
    ].compactMap { $0 }
}

private func incomeEventActionTarget(for event: IncomeEventSummary, rowID: String) -> MenuRowActionTarget {
    let eventID = incomeEventRowID(for: event)
    return MenuRowActionTarget(
        kind: .incomeEvent,
        id: eventID,
        incomeEvent: IncomeEventActionTarget(
            eventID: eventID,
            rowID: rowID,
            date: event.date,
            kind: event.kind,
            symbolName: event.symbolName,
            estimated: event.estimated,
            symbolId: event.symbolId,
            quoteId: event.quoteId
        )
    )
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

private func incomeCalendarEventRanksBefore(_ lhs: IncomeEventSummary, _ rhs: IncomeEventSummary) -> Bool {
    if lhs.date != rhs.date {
        return lhs.date < rhs.date
    }
    let lhsPriority = incomeCalendarEventPriority(lhs.kind)
    let rhsPriority = incomeCalendarEventPriority(rhs.kind)
    if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
    }
    if lhs.symbolName != rhs.symbolName {
        return lhs.symbolName < rhs.symbolName
    }
    return incomeEventRowID(for: lhs) < incomeEventRowID(for: rhs)
}

private func incomeCalendarEventPriority(_ kind: String) -> Int {
    switch kind {
    case "ex-dividend":
        return 0
    case "payment-dividend":
        return 1
    default:
        return 2
    }
}

private func isIncomeCalendarEventKind(_ kind: String) -> Bool {
    kind == "ex-dividend" || kind == "payment-dividend"
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
    public static let defaultBarHeights = [0.5, 1.0, 0.667]

    public var barHeights: [Double]
    public var filledBarCount: Int
    public var isDimmed: Bool
    public var statusCopy: String

    public init(
        barHeights: [Double] = StatusVisualState.defaultBarHeights,
        filledBarCount: Int = 0,
        isDimmed: Bool = false,
        statusCopy: String = ""
    ) {
        self.barHeights = Array(barHeights.prefix(3))
        while self.barHeights.count < 3 {
            self.barHeights.append(StatusVisualState.defaultBarHeights[self.barHeights.count])
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
            barHeights: try container.decodeIfPresent([Double].self, forKey: .barHeights)
                ?? StatusVisualState.defaultBarHeights,
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
    case pulseMarkRead
    case allocationHolding
    case allocationDrillDown
    case incomeEmpty
    case incomeSummary
    case incomeNext
    case incomeEvent
    case incomeEventDate
    case incomeEventKind
    case incomeEventState
    case incomeEventAmount
    case incomeEventChange
    case incomeDrillDown
    case bigMoverSummary
    case freshnessSummary
    case holdingIdentifierCopy

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

public enum MenuRowActionTargetKind: String, Codable, Equatable {
    case incomeEvent
    case copyHoldingIdentifier
}

public struct IncomeEventActionTarget: Codable, Equatable {
    public var eventID: String
    public var rowID: String
    public var date: String
    public var kind: String
    public var symbolName: String
    public var estimated: Bool
    public var symbolId: Int?
    public var quoteId: Int?

    public init(
        eventID: String,
        rowID: String,
        date: String,
        kind: String,
        symbolName: String,
        estimated: Bool,
        symbolId: Int? = nil,
        quoteId: Int? = nil
    ) {
        self.eventID = eventID
        self.rowID = rowID
        self.date = date
        self.kind = kind
        self.symbolName = symbolName
        self.estimated = estimated
        self.symbolId = symbolId
        self.quoteId = quoteId
    }
}

public struct MenuRowActionTarget: Codable, Equatable {
    public var kind: MenuRowActionTargetKind
    public var id: String
    public var incomeEvent: IncomeEventActionTarget?
    public var copyText: String?

    public init(
        kind: MenuRowActionTargetKind,
        id: String,
        incomeEvent: IncomeEventActionTarget? = nil,
        copyText: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.incomeEvent = incomeEvent
        self.copyText = copyText
    }
}

public struct MenuRow: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var accessibilityIdentifier: String
    public var actionTarget: MenuRowActionTarget?
    public var title: String
    public var detail: String?
    public var actionPayload: String?
    public var children: [MenuRow]

    public init(
        id: String = "",
        role: MenuRowRole = .row,
        accessibilityIdentifier: String? = nil,
        actionTarget: MenuRowActionTarget? = nil,
        title: String,
        detail: String? = nil,
        actionPayload: String? = nil,
        children: [MenuRow] = []
    ) {
        self.id = id
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier ?? Self.defaultAccessibilityIdentifier(for: id)
        self.actionTarget = actionTarget
        self.title = title
        self.detail = detail
        self.actionPayload = actionPayload
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case accessibilityIdentifier
        case actionTarget
        case title
        case detail
        case actionPayload
        case children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let decodedRole = try container.decodeIfPresent(MenuRowRole.self, forKey: .role) ?? .row
        role = id == "quiet" && decodedRole == .pulseAttention ? .pulseQuiet : decodedRole
        accessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .accessibilityIdentifier)
            ?? Self.defaultAccessibilityIdentifier(for: id)
        actionTarget = try container.decodeIfPresent(MenuRowActionTarget.self, forKey: .actionTarget)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        actionPayload = try container.decodeIfPresent(String.self, forKey: .actionPayload)
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
    public var actionTarget: MenuRowActionTarget?
    public var actionPayload: String?
    public var children: [MenuBarRowSurface]

    public init(
        id: String,
        role: MenuRowRole,
        title: String,
        accessibilityIdentifier: String,
        actionTarget: MenuRowActionTarget? = nil,
        actionPayload: String? = nil,
        children: [MenuBarRowSurface] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actionTarget = actionTarget
        self.actionPayload = actionPayload
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

public enum BackgroundDetailRefreshPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case baseHoldings
    case allocation
    case xRay
    case income
    case priceHistory

    public var stepIndex: Int {
        switch self {
        case .baseHoldings:
            1
        case .allocation:
            2
        case .xRay:
            3
        case .income:
            4
        case .priceHistory:
            5
        }
    }

    public var title: String {
        switch self {
        case .baseHoldings:
            "Base holdings"
        case .allocation:
            "Allocation"
        case .xRay:
            "X-ray"
        case .income:
            "Income"
        case .priceHistory:
            "Price history"
        }
    }
}

public struct BackgroundDetailRefreshProgress: Codable, Equatable, Sendable {
    public var phase: BackgroundDetailRefreshPhase
    public var completedUnitCount: Int?
    public var totalUnitCount: Int?

    public init(
        phase: BackgroundDetailRefreshPhase,
        completedUnitCount: Int? = nil,
        totalUnitCount: Int? = nil
    ) {
        self.phase = phase
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
    }
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

    public static func descriptorForBackgroundDetailProgress(
        cachedPulse: MenuDescriptor,
        progress: BackgroundDetailRefreshProgress
    ) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse,
            rows: backgroundDetailProgressRows(progress)
        )
    }

    public static func descriptorForBackgroundDetailDegraded(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse,
            statusVisual: cachedPulse.statusVisual.withDimming(true),
            rows: [
                MenuRow(
                    id: "portfolioFetch.backgroundDegraded",
                    role: .fetchStatus,
                    title: "Details partially filled",
                    detail: "Some optional details can be retried"
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

    private static func backgroundDetailProgressRows(_ progress: BackgroundDetailRefreshProgress) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "portfolioFetch.backgroundProgress",
                role: .fetchStatus,
                title: "Filling details",
                detail: "Keeping last pulse visible"
            ),
            MenuRow(
                id: "portfolioFetch.backgroundProgress.phase",
                role: .fetchStatus,
                title: "Step \(progress.phase.stepIndex)/\(BackgroundDetailRefreshPhase.allCases.count): \(progress.phase.title)"
            ),
        ]
        if progress.phase == .priceHistory,
           let completed = progress.completedUnitCount,
           let total = progress.totalUnitCount
        {
            rows.append(
                MenuRow(
                    id: "portfolioFetch.backgroundProgress.priceHistory",
                    role: .fetchStatus,
                    title: "\(max(0, completed))/\(max(0, total)) price histories checked"
                )
            )
        }
        return rows
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

public enum PDTOnboardingEffect: Equatable {
    case none
    case probeReadiness
    case startLoginHandoff
    case startFirstFetch
}

public struct PDTOnboardingUpdate: Equatable {
    public var state: ClaudeLaunchState
    public var descriptor: MenuDescriptor
    public var effect: PDTOnboardingEffect

    public init(
        state: ClaudeLaunchState,
        descriptor: MenuDescriptor,
        effect: PDTOnboardingEffect = .none
    ) {
        self.state = state
        self.descriptor = descriptor
        self.effect = effect
    }
}

public enum PDTOnboardingLoginResult: Equatable {
    case succeeded
    case failed(ClaudeLoginFailureReason)
}

public enum PDTOnboardingFetchResult: Equatable {
    case succeeded(MenuDescriptor)
    case failed(String)
}

public final class PDTOnboardingCoordinator {
    private var cachedPulse: MenuDescriptor?
    public private(set) var state: ClaudeLaunchState = .probingClaude

    public init(cachedPulse: MenuDescriptor? = nil) {
        self.cachedPulse = cachedPulse
    }

    public func launch(cachedPulse: MenuDescriptor? = nil) -> PDTOnboardingUpdate {
        if let cachedPulse {
            self.cachedPulse = cachedPulse
        }
        return beginReadinessProbe()
    }

    public func beginReadinessProbe() -> PDTOnboardingUpdate {
        update(state: .probingClaude, effect: .probeReadiness)
    }

    public func completeReadinessProbe(_ result: ClaudeReadinessProbeResult) -> PDTOnboardingUpdate {
        let nextState = ClaudeLaunchFlow.state(afterReadinessProbe: result)
        let effect: PDTOnboardingEffect = nextState == .fetchingPortfolio ? .startFirstFetch : .none
        return update(state: nextState, effect: effect)
    }

    public func beginLoginHandoff() -> PDTOnboardingUpdate {
        update(state: .openingClaude, effect: .startLoginHandoff)
    }

    public func completeLoginHandoff(_ result: PDTOnboardingLoginResult) -> PDTOnboardingUpdate {
        switch result {
        case .succeeded:
            switch ClaudeLaunchFlow.action(afterLoginHandoff: .succeeded) {
            case .recheckReadiness:
                return beginReadinessProbe()
            case .showMissingClaude:
                return update(state: .missingClaude)
            }
        case .failed(let reason):
            state = .missingClaude
            return PDTOnboardingUpdate(
                state: state,
                descriptor: ClaudeLaunchFlow.descriptor(forLoginFailure: reason)
            )
        }
    }

    public func beginFirstFetch(fetchingElapsedSeconds: Int? = nil) -> PDTOnboardingUpdate {
        update(state: .fetchingPortfolio, fetchingElapsedSeconds: fetchingElapsedSeconds)
    }

    public func completeFirstFetch(_ result: PDTOnboardingFetchResult) -> PDTOnboardingUpdate {
        switch result {
        case .succeeded(let descriptor):
            cachedPulse = descriptor
            state = .fetchingPortfolio
            return PDTOnboardingUpdate(
                state: state,
                descriptor: ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: descriptor)
            )
        case .failed:
            return update(state: .portfolioFetchFailed)
        }
    }

    public func descriptor(for state: ClaudeLaunchState, fetchingElapsedSeconds: Int? = nil) -> MenuDescriptor {
        ClaudeLaunchFlow.descriptor(
            for: state,
            cachedPulse: cachedPulse,
            fetchingElapsedSeconds: fetchingElapsedSeconds
        )
    }

    private func update(
        state: ClaudeLaunchState,
        effect: PDTOnboardingEffect = .none,
        fetchingElapsedSeconds: Int? = nil
    ) -> PDTOnboardingUpdate {
        self.state = state
        return PDTOnboardingUpdate(
            state: state,
            descriptor: descriptor(for: state, fetchingElapsedSeconds: fetchingElapsedSeconds),
            effect: effect
        )
    }
}

public struct PDTOnboardingRunnerDependencies {
    public var loadCachedPulse: () -> MenuDescriptor?
    public var readinessProbe: () -> ClaudeReadinessProbeResult
    public var loginHandoff: () -> PDTOnboardingLoginResult
    public var firstFetch: () -> PDTOnboardingFetchResult

    public init(
        loadCachedPulse: @escaping () -> MenuDescriptor?,
        readinessProbe: @escaping () -> ClaudeReadinessProbeResult,
        loginHandoff: @escaping () -> PDTOnboardingLoginResult,
        firstFetch: @escaping () -> PDTOnboardingFetchResult
    ) {
        self.loadCachedPulse = loadCachedPulse
        self.readinessProbe = readinessProbe
        self.loginHandoff = loginHandoff
        self.firstFetch = firstFetch
    }
}

public final class PDTOnboardingRunner {
    private let coordinator: PDTOnboardingCoordinator
    private let dependencies: PDTOnboardingRunnerDependencies
    private let render: (PDTOnboardingUpdate) -> Void

    public init(
        coordinator: PDTOnboardingCoordinator = PDTOnboardingCoordinator(),
        dependencies: PDTOnboardingRunnerDependencies,
        render: @escaping (PDTOnboardingUpdate) -> Void
    ) {
        self.coordinator = coordinator
        self.dependencies = dependencies
        self.render = render
    }

    public func launch() {
        handle(coordinator.launch(cachedPulse: dependencies.loadCachedPulse()))
    }

    public func retryReadiness() {
        handle(coordinator.beginReadinessProbe())
    }

    public func loginWithClaude() {
        handle(coordinator.beginLoginHandoff())
    }

    public func retryFirstFetch() {
        handle(coordinator.beginFirstFetch())
        handle(coordinator.completeFirstFetch(dependencies.firstFetch()))
    }

    private func handle(_ update: PDTOnboardingUpdate) {
        render(update)
        switch update.effect {
        case .none:
            return
        case .probeReadiness:
            handle(coordinator.completeReadinessProbe(dependencies.readinessProbe()))
        case .startLoginHandoff:
            handle(coordinator.completeLoginHandoff(dependencies.loginHandoff()))
        case .startFirstFetch:
            handle(coordinator.beginFirstFetch())
            handle(coordinator.completeFirstFetch(dependencies.firstFetch()))
        }
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
            actionTarget: row.actionTarget,
            actionPayload: row.actionPayload,
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
            rounded(StatusVisualState.defaultBarHeights[0] * scale, places: 3),
            StatusVisualState.defaultBarHeights[1],
            min(1.0, rounded(StatusVisualState.defaultBarHeights[2] * scale, places: 3)),
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
        rows.append(
            MenuRow(
                id: "\(item.id).markRead",
                role: .pulseMarkRead,
                title: "Mark as read",
                actionPayload: item.readFingerprint
            )
        )
        return rows
    }

    private static func allocationChildren(for holding: HoldingSummary, attention: AttentionItem?) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "allocation.\(holding.quoteId).worth",
                title: "Worth",
                detail: display(holding.worth)
            ),
        ]
        if let price = holding.price {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).price",
                    title: "Price",
                    detail: display(price)
                )
            )
        }
        if let recentMove = holding.recentMove {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).recentMove",
                    title: "Recent move",
                    detail: "\(signedPercent(recentMove.percentChange)) from \(recentMove.fromDate) to \(recentMove.toDate)"
                )
            )
        }
        if let nextIncomeEvent = holding.nextIncomeEvent {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).nextIncome",
                    title: "Next income",
                    detail: incomeEventDetail(for: nextIncomeEvent)
                )
            )
        }
        if let averageBuyPrice = holding.averageBuyPrice {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).averageBuyPrice",
                    title: "Average buy price",
                    detail: display(averageBuyPrice)
                )
            )
        }
        if let gainLoss = holding.gainLoss {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).gainLoss",
                    title: "Gain/loss",
                    detail: display(gainLoss)
                )
            )
        }
        if let gainLossPercentage = holding.gainLossPercentage {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).gainLossPercentage",
                    title: "Gain/loss %",
                    detail: signedPercent(gainLossPercentage)
                )
            )
        }
        if let copyableIdentifier = holding.copyableIdentifier {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).copyIdentifier",
                    role: .holdingIdentifierCopy,
                    actionTarget: MenuRowActionTarget(
                        kind: .copyHoldingIdentifier,
                        id: "allocation.\(holding.quoteId).copyIdentifier",
                        copyText: copyableIdentifier
                    ),
                    title: "Copy identifier",
                    detail: copyableIdentifier
                )
            )
        }
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

    public static func buildModel(
        from snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot? = nil,
        readState: PulseReadState? = nil
    ) -> PortfolioPulseModel {
        let rankedItems = ranked(
            concentrationItems(from: snapshot, priorSnapshot: priorSnapshot, readState: readState)
                + incomeItems(from: snapshot)
                + bigMoverItems(from: snapshot, priorSnapshot: priorSnapshot)
        )
        let totalValue = snapshot.totalValue
        let worstPriceAsOf = snapshot.openHoldings.map(\.priceAsOf).min()
        let freshnessStale = isFreshnessStale(worstPriceAsOf: worstPriceAsOf, asOf: snapshot.asOf)
        let recentMovesByQuoteID = recentMoves(from: snapshot.priceSeries)
        let nextIncomeEventsByQuoteID = nextIncomeEventsByQuoteID(from: snapshot)
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
                                worth: $0.worth,
                                price: validMoney($0.price),
                                copyableIdentifier: $0.copyableIdentifier,
                                recentMove: recentMovesByQuoteID[$0.quoteId],
                                nextIncomeEvent: nextIncomeEventsByQuoteID[$0.quoteId],
                                averageBuyPrice: $0.averageBuyPrice,
                                gainLoss: $0.gainLoss,
                                gainLossPercentage: $0.gainLossPercentage
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

    private static func concentrationItems(
        from snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        readState: PulseReadState?
    ) -> [AttentionItem] {
        let priorHoldings = priorSnapshot?.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holding
        }
        let readFingerprints = readState.map { Set($0.readFingerprints) } ?? []
        return concentrationMaterialItems(from: snapshot)
            .compactMap { item in
                guard priorSnapshot != nil else { return item }
                let priorWeight = item.holdingIdentity.flatMap { priorHoldings?[$0.quoteId]?.weight } ?? 0
                if priorWeight < concentrationThreshold {
                    var freshItem = item
                    freshItem.resetsReadState = true
                    return freshItem
                }
                guard let prefix = item.concentrationReadFingerprintPrefix else {
                    return nil
                }
                let changedReadFingerprintExists = readFingerprints.contains { fingerprint in
                    fingerprint.hasPrefix(prefix) && fingerprint != item.readFingerprint
                }
                return changedReadFingerprintExists ? item : nil
            }
    }

    private static func concentrationMaterialItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        snapshot.openHoldings
            .filter { $0.weight >= concentrationThreshold }
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

    private static func nextIncomeEventsByQuoteID(from snapshot: PortfolioSnapshot) -> [Int: IncomeEventSummary] {
        guard let asOfDate = dayDate(from: snapshot.asOf) else {
            return [:]
        }

        let openQuoteIDs = Set(snapshot.openHoldings.map(\.quoteId))
        return snapshot.incomeEvents
            .filter { isIncomeCalendarEventKind($0.kind) }
            .filter { event in
                guard let quoteId = event.quoteId,
                      openQuoteIDs.contains(quoteId),
                      let eventDate = dayDate(from: event.date)
                else {
                    return false
                }
                return eventDate >= asOfDate
            }
            .sorted(by: incomeCalendarEventRanksBefore)
            .reduce(into: [Int: IncomeEventSummary]()) { eventsByQuoteID, event in
                guard let quoteId = event.quoteId,
                      eventsByQuoteID[quoteId] == nil
                else {
                    return
                }
                eventsByQuoteID[quoteId] = event
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
                  let priorPrice = priorHolding.price,
                  let price = holding.price,
                  let beforeDecimal = posixDecimal(priorPrice.value),
                  let afterDecimal = posixDecimal(price.value),
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
                detail: "\(holding.name) moved \(signedPercent(moveSize)) from \(price.currency) \(decimalString(String(beforeValue), places: 2)) to \(price.currency) \(decimalString(String(afterValue), places: 2)) while portfolio weight changed \(percent(priorHolding.weight)) -> \(percent(holding.weight)).",
                severity: abs(moveSize) >= 0.20 ? "high" : "medium",
                score: score,
                holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
                beforeValue: beforeValue,
                afterValue: afterValue,
                moveSize: moveSize,
                beforeWeight: priorHolding.weight,
                afterWeight: holding.weight,
                valueCurrency: price.currency,
                windowStart: priorSnapshot.asOf,
                windowEnd: snapshot.asOf,
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

    private static func recentMoves(from prices: [PricePoint]) -> [Int: PriceMoveSummary] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: prices, by: \.quoteId)
                .compactMap { quoteId, points -> (Int, PriceMoveSummary)? in
                    guard let summary = recentMove(quoteId: quoteId, points: points) else {
                        return nil
                    }
                    return (quoteId, summary)
                }
        )
    }

    private static func recentMove(quoteId: Int, points: [PricePoint]) -> PriceMoveSummary? {
        guard points.count >= 2 else { return nil }
        let datedPoints: [(point: PricePoint, date: Date, close: Decimal)] = points.compactMap { point in
            guard let date = dayDate(from: point.date),
                  let close = posixDecimal(point.closeAdjusted),
                  close > 0
            else {
                return nil
            }
            return (point, date, close)
        }
        guard datedPoints.count == points.count else { return nil }

        let sorted = datedPoints.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.point.closeAdjusted < $1.point.closeAdjusted
        }
        guard let first = sorted.first,
              let last = sorted.last,
              first.date < last.date
        else {
            return nil
        }

        let change = (last.close - first.close) / first.close
        return PriceMoveSummary(
            quoteId: quoteId,
            fromDate: first.point.date,
            toDate: last.point.date,
            percentChange: rounded(Double(truncating: change as NSDecimalNumber), places: 4)
        )
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
    private let lock = NSLock()

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
        lock.lock()
        defer {
            lock.unlock()
        }
        availabilityChecks += 1
        return availableTools
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        if let delay = initialCallDelaySeconds, delay > 0 {
            initialCallDelaySeconds = nil
            lock.unlock()
            Thread.sleep(forTimeInterval: delay)
        } else {
            lock.unlock()
        }
        lock.lock()
        defer {
            lock.unlock()
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
    private let pulseReadStore: PulseReadStore?
    private let asOf: String?

    public init(
        dataSource: any PortfolioDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil,
        pulseReadStore: PulseReadStore? = nil
    ) {
        self.dataSource = dataSource
        self.snapshotStore = snapshotStore
        self.asOf = asOf
        self.pulseReadStore = pulseReadStore
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
            asOf: asOf,
            pulseReadStore: pulseReadStore
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

public enum PDTBackgroundDetailRefreshOutcome: String, Codable, Equatable, Sendable {
    case completed
    case degraded
}

public enum PDTDetailRefreshFailureCategory: String, Codable, Equatable, Sendable {
    case setupUnavailable
    case transientFailure
    case missingScriptedResponse
    case decode
    case unavailable
    case exit
}

public struct PDTDetailRefreshFailureDiagnostic: Codable, Equatable, Sendable {
    public var toolName: String
    public var phase: BackgroundDetailRefreshPhase
    public var attemptCount: Int
    public var category: PDTDetailRefreshFailureCategory
    public var argumentShape: [String]

    public init(
        toolName: String,
        phase: BackgroundDetailRefreshPhase,
        attemptCount: Int,
        category: PDTDetailRefreshFailureCategory,
        argumentShape: [String]
    ) {
        self.toolName = toolName
        self.phase = phase
        self.attemptCount = attemptCount
        self.category = category
        self.argumentShape = argumentShape.sorted()
    }
}

public struct PDTBackgroundDetailRefreshOptions: Equatable, Sendable {
    public var priceHistoryConcurrencyLimit: Int
    public var optionalRetryCount: Int
    public var retryBackoffSeconds: Double

    public init(
        priceHistoryConcurrencyLimit: Int = 4,
        optionalRetryCount: Int = 1,
        retryBackoffSeconds: Double = 0.35
    ) {
        self.priceHistoryConcurrencyLimit = max(1, priceHistoryConcurrencyLimit)
        self.optionalRetryCount = max(0, optionalRetryCount)
        self.retryBackoffSeconds = max(0, retryBackoffSeconds)
    }
}

public struct PDTBackgroundDetailRefreshResult: Equatable {
    public var outcome: PDTBackgroundDetailRefreshOutcome
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
    public var diagnostics: [PDTDetailRefreshFailureDiagnostic]
}

public final class PDTBackgroundDetailRefresh: @unchecked Sendable {
    private let connector: any PDTMCPConnector
    private let snapshotStore: SnapshotStore
    private let pulseReadStore: PulseReadStore?
    private let asOf: String?
    private let options: PDTBackgroundDetailRefreshOptions

    public init(
        connector: any PDTMCPConnector,
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        asOf: String? = nil,
        options: PDTBackgroundDetailRefreshOptions = PDTBackgroundDetailRefreshOptions()
    ) {
        self.connector = connector
        self.snapshotStore = snapshotStore
        self.pulseReadStore = pulseReadStore
        self.asOf = asOf
        self.options = options
    }

    public func refresh(
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void = { _ in }
    ) throws -> PDTBackgroundDetailRefreshResult {
        let requiredTools = [
            "pdt-get-portfolio-holdings",
            "pdt-get-portfolio-distributions",
            "pdt-list-x-ray-holdings",
            "pdt-list-calendar-events",
            "pdt-list-dividends",
            "pdt-list-symbol-prices",
        ]
        let availableTools = try connector.availableReadTools(required: Set(requiredTools))
        let missing = requiredTools.filter { !availableTools.contains($0) }
        guard missing.isEmpty else {
            throw PDTMCPConnectorError.missingRequiredReadTools(missing)
        }

        let snapshotAsOf = asOf ?? currentDayString()
        let originalPriorSnapshot = try? snapshotStore.loadPriorSnapshot()
        var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []
        var snapshot: PortfolioSnapshot
        do {
            snapshot = try baseSnapshot(asOf: snapshotAsOf, progress: progress)
        } catch {
            try snapshotStore.saveLastDetailRefreshDiagnostic(
                diagnostic(for: error, tool: "pdt-get-portfolio-holdings", phase: .baseHoldings)
            )
            throw error
        }
        preserveOptionalDetails(in: &snapshot, from: originalPriorSnapshot)
        _ = try snapshotStore.commitCurrentSnapshot(snapshot)

        do {
            progress(BackgroundDetailRefreshProgress(phase: .allocation))
            let distributions: LiveDistributionsEnvelope = try callDecodedWithRetry(
                "pdt-get-portfolio-distributions",
                phase: .allocation,
                arguments: [:]
            )
            snapshot.sectors = distributions.sectors.map(\.summary)
            snapshot.assetTypes = distributions.assetTypes.map(\.summary)
            _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        } catch {
            diagnostics.append(diagnostic(for: error, tool: "pdt-get-portfolio-distributions", phase: .allocation))
        }

        do {
            progress(BackgroundDetailRefreshProgress(phase: .xRay))
            snapshot.xRayHoldings = try xRayHoldings()
            _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        } catch {
            diagnostics.append(diagnostic(for: error, tool: "pdt-list-x-ray-holdings", phase: .xRay, arguments: [
                "limit": "",
                "offset": "",
            ]))
        }

        do {
            progress(BackgroundDetailRefreshProgress(phase: .income))
            let income = try incomeEvents(asOf: snapshotAsOf)
            snapshot.incomeEvents = income.events
            snapshot.dividendRowCount = income.dividendRowCount
            _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        } catch {
            diagnostics.append(diagnostic(for: error, tool: "pdt-list-calendar-events", phase: .income))
        }

        progress(BackgroundDetailRefreshProgress(
            phase: .priceHistory,
            completedUnitCount: 0,
            totalUnitCount: snapshot.openHoldings.count
        ))
        let priceHistory = priceSeries(
            for: snapshot.openHoldings,
            asOf: snapshotAsOf,
            progress: progress
        )
        snapshot.priceSeries = priceSeriesWithPriorFallback(
            refreshed: priceHistory.points,
            failedQuoteIDs: priceHistory.failedQuoteIDs,
            priorSnapshot: originalPriorSnapshot,
            currentQuoteIDs: Set(snapshot.openHoldings.map(\.quoteId))
        ).sorted {
            if $0.quoteId != $1.quoteId {
                return $0.quoteId < $1.quoteId
            }
            return $0.date < $1.date
        }
        diagnostics.append(contentsOf: priceHistory.diagnostics)
        let commit = try snapshotStore.commitCurrentSnapshot(snapshot)

        let loadedReadState = PressureRunner.displayReadState(from: pulseReadStore)
        let rawModel = PressureEngine.buildModel(
            from: snapshot,
            priorSnapshot: originalPriorSnapshot,
            readState: loadedReadState
        )
        let readState = try PressureRunner.readStateAfterResettingReappearedItems(
            in: rawModel,
            loadedReadState: loadedReadState,
            pulseReadStore: pulseReadStore
        )
        let model = PressureRunner.modelAfterApplyingReadState(rawModel, readState: readState)
        let descriptor = MenuDescriptorRenderer.render(model: model)
        let outcome: PDTBackgroundDetailRefreshOutcome = diagnostics.isEmpty ? .completed : .degraded
        if let lastDiagnostic = diagnostics.last {
            try snapshotStore.saveLastDetailRefreshDiagnostic(lastDiagnostic)
        } else {
            try snapshotStore.clearLastDetailRefreshDiagnostic()
        }
        return PDTBackgroundDetailRefreshResult(
            outcome: outcome,
            model: model,
            snapshotCommit: commit,
            descriptor: descriptor,
            diagnostics: diagnostics
        )
    }

    private func baseSnapshot(
        asOf snapshotAsOf: String,
        progress: @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> PortfolioSnapshot {
        progress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        let holdingsEnvelope: LiveHoldingsEnvelope = try callDecodedWithRetry(
            "pdt-get-portfolio-holdings",
            phase: .baseHoldings,
            arguments: [:]
        )
        let openHoldings = holdingsEnvelope.holdings
            .filter { $0.closedAt == nil }
            .map {
                NormalizedHolding(
                    name: $0.symbolName,
                    quoteId: $0.symbolQuoteId,
                    weight: $0.portfolioWeight,
                    worth: $0.currentWorthLocal,
                    price: validMoney($0.currentPriceLocal),
                    priceAsOf: dayPrefix($0.currentPriceDate),
                    averageBuyPrice: averageBuyPrice(
                        explicit: $0.unrealisedBoughtPriceAverageLocal,
                        total: $0.unrealisedBoughtPriceTotalLocal,
                        shares: $0.unrealisedBoughtShares
                    ),
                    gainLoss: validMoney($0.unrealisedGains),
                    gainLossPercentage: finite($0.unrealisedGainsPercentage)
                )
            }
        let currency = openHoldings.first?.worth.currency ?? "EUR"
        return PortfolioSnapshot(
            asOf: snapshotAsOf,
            totalValue: sumWorth(openHoldings, currency: currency),
            openHoldings: openHoldings,
            sectors: [],
            assetTypes: [],
            xRayHoldings: nil,
            incomeEvents: [],
            dividendRowCount: 0,
            priceSeries: []
        )
    }

    private func preserveOptionalDetails(in snapshot: inout PortfolioSnapshot, from priorSnapshot: PortfolioSnapshot?) {
        guard let priorSnapshot else {
            return
        }
        let currentQuoteIDs = Set(snapshot.openHoldings.map(\.quoteId))
        snapshot.sectors = priorSnapshot.sectors
        snapshot.assetTypes = priorSnapshot.assetTypes
        snapshot.xRayHoldings = priorSnapshot.xRayHoldings
        snapshot.incomeEvents = priorSnapshot.incomeEvents
        snapshot.dividendRowCount = priorSnapshot.dividendRowCount
        snapshot.priceSeries = priorSnapshot.priceSeries.filter { currentQuoteIDs.contains($0.quoteId) }
    }

    private func priceSeriesWithPriorFallback(
        refreshed: [PricePoint],
        failedQuoteIDs: Set<Int>,
        priorSnapshot: PortfolioSnapshot?,
        currentQuoteIDs: Set<Int>
    ) -> [PricePoint] {
        guard let priorSnapshot, !failedQuoteIDs.isEmpty else {
            return refreshed
        }
        let refreshedQuoteIDs = Set(refreshed.map(\.quoteId))
        let fallbackQuoteIDs = failedQuoteIDs.subtracting(refreshedQuoteIDs)
        let fallback = priorSnapshot.priceSeries.filter {
            currentQuoteIDs.contains($0.quoteId) && fallbackQuoteIDs.contains($0.quoteId)
        }
        return refreshed + fallback
    }

    private func xRayHoldings() throws -> [XRayHoldingSummary] {
        let limit = 500
        var offset = 0
        var holdings: [XRayHoldingSummary] = []
        while true {
            let arguments = ["limit": String(limit), "offset": String(offset)]
            let envelope: XRayHoldingsEnvelope = try callDecodedWithRetry(
                "pdt-list-x-ray-holdings",
                phase: .xRay,
                arguments: arguments
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

    private func incomeEvents(asOf snapshotAsOf: String) throws -> (events: [IncomeEventSummary], dividendRowCount: Int) {
        let incomeDateRange = [
            "date_from": snapshotAsOf,
            "date_to": dayString(snapshotAsOf, addingDays: 30),
        ]
        let dividendDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -370),
            "date_to": incomeDateRange["date_to"] ?? snapshotAsOf,
        ]
        let calendarEnvelope: LiveCalendarEventsEnvelope = try callDecodedWithRetry(
            "pdt-list-calendar-events",
            phase: .income,
            arguments: incomeDateRange
        )
        let dividends = try liveDividends(arguments: dividendDateRange)
        let dividendsByQuoteID = Dictionary(grouping: dividends, by: \.symbolQuoteId)
        return (
            events: calendarEnvelope.data.filter { $0.type != "no-events-today" }.map {
                IncomeEventSummary(
                    date: $0.date,
                    kind: $0.type,
                    symbolName: $0.symbolName ?? "Portfolio",
                    estimated: $0.isEstimated,
                    symbolId: $0.symbolId,
                    quoteId: nil,
                    amount: latestLiveDividendAmount(for: nil, dividendsByQuoteID: dividendsByQuoteID),
                    priorAmount: nil,
                    changePercent: nil
                )
            },
            dividendRowCount: dividends.count
        )
    }

    private func liveDividends(arguments baseArguments: [String: String]) throws -> [LiveDividend] {
        var page = 1
        var dividends: [LiveDividend] = []
        while true {
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": "250",
            ]) { _, new in new }
            let envelope: LiveDividendsEnvelope = try callDecodedWithRetry(
                "pdt-list-dividends",
                phase: .income,
                arguments: arguments
            )
            dividends.append(contentsOf: envelope.data)
            let lastPage = envelope.meta?.lastPage ?? page
            guard page < lastPage else {
                return dividends
            }
            page += 1
        }
    }

    private func priceSeries(
        for holdings: [NormalizedHolding],
        asOf snapshotAsOf: String,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) -> (points: [PricePoint], diagnostics: [PDTDetailRefreshFailureDiagnostic], failedQuoteIDs: Set<Int>) {
        let priceDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -7),
            "date_to": snapshotAsOf,
        ]
        let semaphore = DispatchSemaphore(value: options.priceHistoryConcurrencyLimit)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "PDTBarCore.background-detail.price-history", attributes: .concurrent)
        let totalCount = holdings.count
        let quoteIDs = holdings.map(\.quoteId)
        let accumulator = PDTPriceHistoryAccumulator()

        for quoteID in quoteIDs {
            semaphore.wait()
            group.enter()
            queue.async { [self] in
                defer {
                    let progressValue = accumulator.markCompleted()
                    progress(BackgroundDetailRefreshProgress(
                        phase: .priceHistory,
                        completedUnitCount: progressValue,
                        totalUnitCount: totalCount
                    ))
                    semaphore.signal()
                    group.leave()
                }
                let arguments = priceDateRange.merging([
                    "symbol_quote_id": String(quoteID),
                ]) { _, new in new }
                do {
                    let prices: LivePricesEnvelope = try callDecodedWithRetry(
                        "pdt-list-symbol-prices",
                        phase: .priceHistory,
                        arguments: arguments
                    )
                    let nextPoints = prices.data.map {
                        PricePoint(
                            quoteId: $0.symbolQuoteId,
                            date: $0.date,
                            closeAdjusted: $0.closeAdjusted
                        )
                    }
                    accumulator.append(points: nextPoints)
                } catch {
                    let diagnostic = diagnostic(
                        for: error,
                        tool: "pdt-list-symbol-prices",
                        phase: .priceHistory,
                        arguments: arguments
                    )
                    accumulator.append(diagnostic: diagnostic, failedQuoteID: quoteID)
                }
            }
        }
        group.wait()
        return accumulator.result()
    }

    private func callDecoded<T: Decodable>(_ tool: String, arguments: [String: String]) throws -> T {
        try decodeLiveTool(tool, data: connector.callReadTool(tool, arguments: arguments))
    }

    private func callDecodedWithRetry<T: Decodable>(
        _ tool: String,
        phase: BackgroundDetailRefreshPhase,
        arguments: [String: String]
    ) throws -> T {
        var attempts = 0
        var lastError: Error?
        repeat {
            attempts += 1
            do {
                return try callDecoded(tool, arguments: arguments)
            } catch {
                lastError = error
                if attempts <= options.optionalRetryCount, options.retryBackoffSeconds > 0 {
                    Thread.sleep(forTimeInterval: options.retryBackoffSeconds)
                }
            }
        } while attempts <= options.optionalRetryCount
        throw PDTDetailRefreshToolError(
            diagnostic: diagnostic(
                for: lastError ?? PDTMCPConnectorError.transientFailure("unknown detail refresh failure"),
                tool: tool,
                phase: phase,
                attempts: attempts,
                arguments: arguments
            )
        )
    }

    private func diagnostic(
        for error: Error,
        tool: String,
        phase: BackgroundDetailRefreshPhase,
        attempts: Int = 1,
        arguments: [String: String] = [:]
    ) -> PDTDetailRefreshFailureDiagnostic {
        if let wrapped = error as? PDTDetailRefreshToolError {
            return wrapped.diagnostic
        }
        return PDTDetailRefreshFailureDiagnostic(
            toolName: tool,
            phase: phase,
            attemptCount: attempts,
            category: failureCategory(error),
            argumentShape: arguments.keys.sorted()
        )
    }

    private func failureCategory(_ error: Error) -> PDTDetailRefreshFailureCategory {
        switch error {
        case PDTMCPConnectorError.setupUnavailable:
            .setupUnavailable
        case PDTMCPConnectorError.transientFailure:
            .transientFailure
        case PDTMCPConnectorError.missingScriptedResponse:
            .missingScriptedResponse
        case PDTLiveDataSourceError.malformedToolResult:
            .decode
        case PDTLiveDataSourceError.unavailableToolResult:
            .unavailable
        default:
            .exit
        }
    }
}

private struct PDTDetailRefreshToolError: Error, CustomStringConvertible {
    var diagnostic: PDTDetailRefreshFailureDiagnostic

    var description: String {
        "PDT detail refresh failed: tool=\(diagnostic.toolName) phase=\(diagnostic.phase.rawValue) category=\(diagnostic.category.rawValue) attempts=\(diagnostic.attemptCount)"
    }
}

private final class PDTPriceHistoryAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    private var points: [PricePoint] = []
    private var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []
    private var failedQuoteIDs: Set<Int> = []

    func markCompleted() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        completed += 1
        return completed
    }

    func append(points newPoints: [PricePoint]) {
        lock.lock()
        points.append(contentsOf: newPoints)
        lock.unlock()
    }

    func append(diagnostic: PDTDetailRefreshFailureDiagnostic, failedQuoteID: Int) {
        lock.lock()
        diagnostics.append(diagnostic)
        failedQuoteIDs.insert(failedQuoteID)
        lock.unlock()
    }

    func result() -> (points: [PricePoint], diagnostics: [PDTDetailRefreshFailureDiagnostic], failedQuoteIDs: Set<Int>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (points, diagnostics, failedQuoteIDs)
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

        var openHoldings = holdingsEnvelope.holdings
            .filter { $0.closedAt == nil }
            .map {
                NormalizedHolding(
                    name: $0.symbolName,
                    quoteId: $0.symbolQuoteId,
                    weight: $0.portfolioWeight,
                    worth: $0.currentWorthLocal,
                    price: validMoney($0.currentPriceLocal),
                    priceAsOf: dayPrefix($0.currentPriceDate),
                    averageBuyPrice: averageBuyPrice(
                        explicit: $0.unrealisedBoughtPriceAverageLocal,
                        total: $0.unrealisedBoughtPriceTotalLocal,
                        shares: $0.unrealisedBoughtShares
                    ),
                    gainLoss: validMoney($0.unrealisedGains),
                    gainLossPercentage: finite($0.unrealisedGainsPercentage)
                )
            }
        let quoteMetadata = options.includeIncomeQuoteLookups
            ? try liveSymbolQuoteMetadata(for: openHoldings)
            : SymbolQuoteMetadata()
        openHoldings = openHoldings.map {
            var holding = $0
            holding.copyableIdentifier = quoteMetadata.codesByQuoteID[holding.quoteId]
            return holding
        }
        let quoteIDsBySymbolID = quoteMetadata.quoteIDsBySymbolID
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

    private func liveSymbolQuoteMetadata(for holdings: [NormalizedHolding]) throws -> SymbolQuoteMetadata {
        var metadata = SymbolQuoteMetadata()
        for holding in holdings {
            let quote: LiveSymbolQuoteEnvelope = try decodeLiveTool(
                "pdt-get-symbol-quote",
                data: toolClient.callReadTool("pdt-get-symbol-quote", arguments: ["id": String(holding.quoteId)])
            )
            metadata.quoteIDsBySymbolID[quote.symbolId] = quote.id
            if let code = safePublicIdentifier(quote.code) {
                metadata.codesByQuoteID[quote.id] = code
            }
        }
        return metadata
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
    public static func cachedPulseDescriptor(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil
    ) throws -> MenuDescriptor? {
        guard let snapshot = try snapshotStore.loadPriorSnapshot() else {
            return nil
        }
        let readState = displayReadState(from: pulseReadStore)
        let rawModel = PressureEngine.buildModel(from: snapshot, readState: readState)
        let model = modelAfterApplyingReadState(rawModel, readState: readState)
        return MenuDescriptorRenderer.render(model: model)
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
        asOf: String? = nil,
        pulseReadStore: PulseReadStore? = nil
    ) throws -> PressureRunResult {
        let snapshot = try dataSource.snapshot(asOf: asOf)
        let priorSnapshot: PortfolioSnapshot?
        do {
            priorSnapshot = try snapshotStore.loadPriorSnapshot()
        } catch {
            priorSnapshot = nil
        }
        let loadedReadState = displayReadState(from: pulseReadStore)
        let rawModel = PressureEngine.buildModel(from: snapshot, priorSnapshot: priorSnapshot, readState: loadedReadState)
        let readState = try readStateAfterResettingReappearedItems(
            in: rawModel,
            loadedReadState: loadedReadState,
            pulseReadStore: pulseReadStore
        )
        let model = modelAfterApplyingReadState(rawModel, readState: readState)
        let commit = try snapshotStore.commitCurrentSnapshot(snapshot)
        let descriptor = MenuDescriptorRenderer.render(model: model)
        return PressureRunResult(model: model, snapshotCommit: commit, descriptor: descriptor)
    }

    static func displayReadState(from pulseReadStore: PulseReadStore?) -> PulseReadState? {
        guard let pulseReadStore else {
            return nil
        }
        return try? pulseReadStore.load()
    }

    public static func run(fixture: URL, snapshotDirectory: URL) throws -> PressureRunResult {
        try run(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: SnapshotStore(directory: snapshotDirectory)
        )
    }

    static func modelAfterApplyingReadState(
        _ model: PortfolioPulseModel,
        readState: PulseReadState?
    ) -> PortfolioPulseModel {
        guard let readState else {
            return model
        }
        return PulseReadFilter.apply(to: model, readState: readState)
    }

    static func readStateAfterResettingReappearedItems(
        in model: PortfolioPulseModel,
        loadedReadState: PulseReadState?,
        pulseReadStore: PulseReadStore?
    ) throws -> PulseReadState? {
        guard let loadedReadState,
              let pulseReadStore
        else {
            return loadedReadState
        }
        let reappearedFingerprints = Set(
            model.rankedAttentionItems
                .filter(\.resetsReadState)
                .map(\.readFingerprint)
        )
        let staleFingerprints = staleReadFingerprints(in: model, readState: loadedReadState)
        let fingerprintsToRemove = reappearedFingerprints.union(staleFingerprints)
        guard !fingerprintsToRemove.isEmpty else {
            return loadedReadState
        }
        return try pulseReadStore.removeReadFingerprints(fingerprintsToRemove)
    }

    private static func staleReadFingerprints(
        in model: PortfolioPulseModel,
        readState: PulseReadState
    ) -> Set<String> {
        var currentFingerprintsByPrefix: [String: Set<String>] = [:]
        for item in model.rankedAttentionItems {
            guard let prefix = item.staleReadPruningPrefix else {
                continue
            }
            currentFingerprintsByPrefix[prefix, default: []].insert(item.readFingerprint)
        }
        guard !currentFingerprintsByPrefix.isEmpty else {
            return []
        }
        return Set(readState.readFingerprints.filter { fingerprint in
            currentFingerprintsByPrefix.contains { prefix, currentFingerprints in
                fingerprint.hasPrefix(prefix) && !currentFingerprints.contains(fingerprint)
            }
        })
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

    public func loadLastDetailRefreshDiagnostic() throws -> PDTDetailRefreshFailureDiagnostic? {
        let target = detailRefreshDiagnosticFile
        guard FileManager.default.fileExists(atPath: target.path) else {
            return nil
        }
        return try JSONDecoder().decode(PDTDetailRefreshFailureDiagnostic.self, from: Data(contentsOf: target))
    }

    public func saveLastDetailRefreshDiagnostic(_ diagnostic: PDTDetailRefreshFailureDiagnostic) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try stableJSONData(diagnostic).write(to: detailRefreshDiagnosticFile, options: .atomic)
    }

    public func clearLastDetailRefreshDiagnostic() throws {
        let target = detailRefreshDiagnosticFile
        guard FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    private var detailRefreshDiagnosticFile: URL {
        directory.appending(path: "latest-detail-refresh-diagnostic.json")
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
    public var price: Money?
    public var priceAsOf: String
    public var copyableIdentifier: String?
    public var averageBuyPrice: Money?
    public var gainLoss: Money?
    public var gainLossPercentage: Double?

    public init(
        name: String,
        quoteId: Int,
        weight: Double,
        worth: Money,
        price: Money?,
        priceAsOf: String,
        copyableIdentifier: String? = nil,
        averageBuyPrice: Money? = nil,
        gainLoss: Money? = nil,
        gainLossPercentage: Double? = nil
    ) {
        self.name = name
        self.quoteId = quoteId
        self.weight = weight
        self.worth = worth
        self.price = price
        self.priceAsOf = priceAsOf
        self.copyableIdentifier = safePublicIdentifier(copyableIdentifier)
        self.averageBuyPrice = averageBuyPrice
        self.gainLoss = gainLoss
        self.gainLossPercentage = gainLossPercentage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        quoteId = try container.decode(Int.self, forKey: .quoteId)
        weight = try container.decode(Double.self, forKey: .weight)
        worth = try container.decode(Money.self, forKey: .worth)
        price = validMoney(try? container.decodeIfPresent(Money.self, forKey: .price))
        priceAsOf = try container.decode(String.self, forKey: .priceAsOf)
        copyableIdentifier = safePublicIdentifier(try? container.decodeIfPresent(String.self, forKey: .copyableIdentifier))
        averageBuyPrice = validMoney(try? container.decodeIfPresent(Money.self, forKey: .averageBuyPrice))
        gainLoss = validMoney(try? container.decodeIfPresent(Money.self, forKey: .gainLoss))
        gainLossPercentage = finite(try? container.decodeIfPresent(Double.self, forKey: .gainLossPercentage))
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
        let quoteCodesByQuoteID = payload.symbolQuotes.reduce(into: [Int: String]()) { codesByQuoteID, quote in
            if let code = safePublicIdentifier(quote.code) {
                codesByQuoteID[quote.id] = code
            }
        }
        let holdings = rawHoldings
            .filter { $0.closedAt == nil && $0.hasLiveWorth }
            .map {
                NormalizedHolding(
                    name: $0.symbolName,
                    quoteId: $0.symbolQuoteId,
                    weight: $0.portfolioWeight,
                    worth: $0.currentWorthLocal,
                    price: validMoney($0.currentPriceLocal),
                    priceAsOf: dayPrefix($0.currentPriceDate),
                    copyableIdentifier: quoteCodesByQuoteID[$0.symbolQuoteId],
                    averageBuyPrice: averageBuyPrice(
                        explicit: $0.unrealisedBoughtPriceAverageLocal,
                        total: $0.unrealisedBoughtPriceTotalLocal,
                        shares: $0.unrealisedBoughtShares
                    ),
                    gainLoss: validMoney($0.unrealisedGains),
                    gainLossPercentage: finite($0.unrealisedGainsPercentage)
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
    var currentPriceLocal: Money?
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var unrealisedBoughtPriceAverageLocal: Money?
    var unrealisedBoughtPriceTotalLocal: Money?
    var unrealisedBoughtShares: Double?
    var unrealisedGains: Money?
    var unrealisedGainsPercentage: Double?
    var closedAt: String?

    enum CodingKeys: String, CodingKey {
        case symbolName
        case symbolQuoteId
        case currentPriceDate
        case currentPriceLocal
        case currentWorthLocal
        case portfolioWeight
        case unrealisedBoughtPriceAverageLocal
        case unrealisedBoughtPriceTotalLocal
        case unrealisedBoughtShares
        case unrealisedGains
        case unrealisedGainsPercentage
        case closedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = validMoney(try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal))
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = validMoney(
            try? container.decodeIfPresent(Money.self, forKey: .unrealisedBoughtPriceAverageLocal)
        )
        unrealisedBoughtPriceTotalLocal = validMoney(
            try? container.decodeIfPresent(Money.self, forKey: .unrealisedBoughtPriceTotalLocal)
        )
        unrealisedBoughtShares = finite(try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares))
        unrealisedGains = validMoney(try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains))
        unrealisedGainsPercentage = finite(try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage))
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
    }
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
    var code: String?
    var symbolId: Int
}

private struct SymbolQuoteMetadata {
    var quoteIDsBySymbolID: [Int: Int] = [:]
    var codesByQuoteID: [Int: String] = [:]
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
    var currentPriceLocal: Money?
    var currentWorth: Money?
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var unrealisedBoughtPriceAverageLocal: Money?
    var unrealisedBoughtPriceTotalLocal: Money?
    var unrealisedBoughtShares: Double?
    var unrealisedGains: Money?
    var unrealisedGainsPercentage: Double?
    var closedAt: String?

    enum CodingKeys: String, CodingKey {
        case symbolName
        case symbolQuoteId
        case currentPriceDate
        case currentPriceLocal
        case currentWorth
        case currentWorthLocal
        case portfolioWeight
        case unrealisedBoughtPriceAverageLocal
        case unrealisedBoughtPriceTotalLocal
        case unrealisedBoughtShares
        case unrealisedGains
        case unrealisedGainsPercentage
        case closedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = validMoney(try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal))
        currentWorth = validMoney(try? container.decodeIfPresent(Money.self, forKey: .currentWorth))
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = validMoney(
            try? container.decodeIfPresent(Money.self, forKey: .unrealisedBoughtPriceAverageLocal)
        )
        unrealisedBoughtPriceTotalLocal = validMoney(
            try? container.decodeIfPresent(Money.self, forKey: .unrealisedBoughtPriceTotalLocal)
        )
        unrealisedBoughtShares = finite(try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares))
        unrealisedGains = validMoney(try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains))
        unrealisedGainsPercentage = finite(try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage))
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
    }
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
    var code: String?
    var symbolId: Int
}

private func safePublicIdentifier(_ raw: String?) -> String? {
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

private func averageBuyPrice(explicit: Money?, total: Money?, shares: Double?) -> Money? {
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

private func validMoney(_ money: Money?) -> Money? {
    guard let money,
          !money.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          posixDecimal(money.value) != nil
    else {
        return nil
    }
    return money
}

private func posixDecimal(_ value: String) -> Decimal? {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}

private func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else {
        return nil
    }
    return value
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

private func fingerprintToken(_ value: String) -> String {
    value.lowercased()
        .map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        .reduce(into: "") { result, character in
            if character == "-", result.last == "-" {
                return
            }
            result.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

private func moneyFingerprint(_ money: Money?) -> String {
    guard let money else {
        return "none"
    }
    let value = Decimal(string: money.value).map { canonicalDecimalString($0, places: 2) } ?? money.value
    return "\(money.currency):\(value)"
}

private func fingerprintBasisPoints(_ value: Double?) -> String {
    guard let value else {
        return "missing"
    }
    return String(basisPoints(value))
}

private func basisPoints(_ value: Double) -> Int {
    return Int((value * 10_000).rounded())
}

private func bucketBasisPoints(_ value: Double?, bucketSize: Int) -> String {
    guard let value else {
        return "missing"
    }
    guard bucketSize > 0 else {
        return String(basisPoints(value))
    }
    let points = basisPoints(value)
    return String(Int((Double(points) / Double(bucketSize)).rounded()) * bucketSize)
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
