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
    public var portfolioPerformance: PortfolioPerformanceSummary
    public var facetSnapshots: FacetSnapshots
    public var supportingDataSlots: [SupportingDataSlot]

    public init(
        schemaVersion: Int = 1,
        asOf: String,
        allQuiet: Bool,
        allQuietSignal: AllQuietSignal,
        rankedAttentionItems: [AttentionItem],
        portfolioGlance: PortfolioGlanceContext,
        portfolioPerformance: PortfolioPerformanceSummary = PortfolioPerformanceSummary(),
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
        self.portfolioPerformance = portfolioPerformance
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
            portfolioPerformance: PortfolioPerformanceSummary(),
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
        case portfolioPerformance
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
        portfolioPerformance = try container.decodeIfPresent(PortfolioPerformanceSummary.self, forKey: .portfolioPerformance)
            ?? PortfolioPerformanceSummary()
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

public struct AttentionExplanationFact: Codable, Equatable {
    public var key: String
    public var label: String
    public var value: String
    public var numericValue: Double?
    public var unit: String?

    public init(
        key: String,
        label: String,
        value: String,
        numericValue: Double? = nil,
        unit: String? = nil
    ) {
        self.key = key
        self.label = label
        self.value = value
        self.numericValue = numericValue
        self.unit = unit
    }
}

public struct AttentionExplanationSourceSlot: Codable, Equatable {
    public var id: String
    public var label: String?

    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label
    }
}

public struct AttentionExplanation: Codable, Equatable {
    public var trigger: AttentionExplanationFact
    public var severity: AttentionExplanationFact
    public var threshold: AttentionExplanationFact?
    public var currentValue: AttentionExplanationFact?
    public var priorValue: AttentionExplanationFact?
    public var supportingSourceSlots: [AttentionExplanationSourceSlot]

    public init(
        trigger: AttentionExplanationFact,
        severity: AttentionExplanationFact,
        threshold: AttentionExplanationFact? = nil,
        currentValue: AttentionExplanationFact? = nil,
        priorValue: AttentionExplanationFact? = nil,
        supportingSourceSlots: [AttentionExplanationSourceSlot] = []
    ) {
        self.trigger = trigger
        self.severity = severity
        self.threshold = threshold
        self.currentValue = currentValue
        self.priorValue = priorValue
        self.supportingSourceSlots = supportingSourceSlots
    }

    public static func legacy(
        trigger: String,
        severity: String,
        score: Double,
        supportingDataSlotIDs: [String]
    ) -> AttentionExplanation {
        AttentionExplanation(
            trigger: AttentionExplanationFact(key: "trigger", label: "Trigger", value: trigger),
            severity: AttentionExplanationFact(
                key: "severity",
                label: "Severity",
                value: severity,
                numericValue: score
            ),
            supportingSourceSlots: supportingDataSlotIDs.map { AttentionExplanationSourceSlot(id: $0) }
        )
    }
}

public enum AttentionFacet: Equatable, Sendable, Codable, ExpressibleByStringLiteral {
    case allocation
    case income
    case bigMovers
    case unknown

    public init(legacyValue: String) {
        switch legacyValue {
        case "allocation":
            self = .allocation
        case "income":
            self = .income
        case "bigMovers":
            self = .bigMovers
        default:
            self = .unknown
        }
    }

    public init(stringLiteral value: String) {
        self.init(legacyValue: value)
    }

    public var rawValue: String {
        switch self {
        case .allocation:
            return "allocation"
        case .income:
            return "income"
        case .bigMovers:
            return "bigMovers"
        case .unknown:
            return "unknown"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(legacyValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public func == (lhs: AttentionFacet, rhs: String) -> Bool {
    lhs.rawValue == rhs
}

public func == (lhs: String, rhs: AttentionFacet) -> Bool {
    lhs == rhs.rawValue
}

public func != (lhs: AttentionFacet, rhs: String) -> Bool {
    !(lhs == rhs)
}

public enum AttentionSeverity: Equatable, Sendable, Codable, ExpressibleByStringLiteral {
    case low
    case medium
    case high

    public init(legacyValue: String) {
        switch legacyValue {
        case "high":
            self = .high
        case "medium":
            self = .medium
        case "low":
            self = .low
        default:
            self = .low
        }
    }

    public init(stringLiteral value: String) {
        self.init(legacyValue: value)
    }

    public var rawValue: String {
        switch self {
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(legacyValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public func == (lhs: AttentionSeverity, rhs: String) -> Bool {
    lhs.rawValue == rhs
}

public func == (lhs: String, rhs: AttentionSeverity) -> Bool {
    lhs == rhs.rawValue
}

public func != (lhs: AttentionSeverity, rhs: String) -> Bool {
    !(lhs == rhs)
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
    public var explanation: AttentionExplanation

    public var typedFacet: AttentionFacet {
        get { AttentionFacet(legacyValue: facet) }
        set { facet = newValue.rawValue }
    }

    public var typedSeverity: AttentionSeverity {
        get { AttentionSeverity(legacyValue: severity) }
        set { severity = newValue.rawValue }
    }

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
        supportingDataSlotIDs: [String],
        explanation: AttentionExplanation? = nil
    ) {
        self.id = id
        self.facet = AttentionFacet(legacyValue: facet).rawValue
        self.rank = rank
        self.title = title
        self.detail = detail
        self.severity = AttentionSeverity(legacyValue: severity).rawValue
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
        if let explanation {
            self.explanation = Self.normalizedExplanation(explanation, severity: self.severity)
        } else {
            self.explanation = Self.legacyExplanation(
                title: title,
                severity: self.severity,
                score: score,
                currentWeight: currentWeight,
                threshold: threshold,
                beforeValue: beforeValue,
                afterValue: afterValue,
                moveSize: moveSize,
                beforeWeight: beforeWeight,
                valueCurrency: valueCurrency,
                eventDate: eventDate,
                amount: amount,
                windowStart: windowStart,
                windowEnd: windowEnd,
                supportingDataSlotIDs: supportingDataSlotIDs
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        facet = AttentionFacet(legacyValue: try container.decode(String.self, forKey: .facet)).rawValue
        rank = try container.decode(Int.self, forKey: .rank)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        severity = AttentionSeverity(legacyValue: try container.decode(String.self, forKey: .severity)).rawValue
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
        if let decodedExplanation = try container.decodeIfPresent(AttentionExplanation.self, forKey: .explanation) {
            explanation = Self.normalizedExplanation(decodedExplanation, severity: severity)
        } else {
            explanation = Self.legacyExplanation(
                title: title,
                severity: severity,
                score: score,
                currentWeight: currentWeight,
                threshold: threshold,
                beforeValue: beforeValue,
                afterValue: afterValue,
                moveSize: moveSize,
                beforeWeight: beforeWeight,
                valueCurrency: valueCurrency,
                eventDate: eventDate,
                amount: amount,
                windowStart: windowStart,
                windowEnd: windowEnd,
                supportingDataSlotIDs: supportingDataSlotIDs
            )
        }
    }

    private static func normalizedExplanation(
        _ explanation: AttentionExplanation,
        severity: String
    ) -> AttentionExplanation {
        var explanation = explanation
        explanation.severity.value = severity
        return explanation
    }

    private static func legacyExplanation(
        title: String,
        severity: String,
        score: Double,
        currentWeight: Double?,
        threshold: Double?,
        beforeValue: Double?,
        afterValue: Double?,
        moveSize: Double?,
        beforeWeight: Double?,
        valueCurrency: String?,
        eventDate: String?,
        amount: Money?,
        windowStart: String?,
        windowEnd: String?,
        supportingDataSlotIDs: [String]
    ) -> AttentionExplanation {
        var explanation = AttentionExplanation.legacy(
            trigger: title,
            severity: severity,
            score: score,
            supportingDataSlotIDs: supportingDataSlotIDs
        )
        if let threshold {
            explanation.threshold = AttentionExplanationFact(
                key: "threshold",
                label: "Threshold",
                value: percent(threshold),
                numericValue: threshold,
                unit: "fraction"
            )
        } else if let windowStart,
                  let windowEnd
        {
            explanation.threshold = AttentionExplanationFact(
                key: "threshold",
                label: "Threshold",
                value: "\(windowStart)..\(windowEnd)"
            )
        }
        if let currentWeight {
            explanation.currentValue = AttentionExplanationFact(
                key: "currentValue",
                label: "Current",
                value: percent(currentWeight),
                numericValue: currentWeight,
                unit: "fraction"
            )
        } else if let afterValue,
                  let valueCurrency
        {
            explanation.currentValue = AttentionExplanationFact(
                key: "currentValue",
                label: "Current",
                value: "\(valueCurrency) \(decimalString(String(afterValue), places: 2))",
                numericValue: afterValue,
                unit: valueCurrency
            )
        } else if let moveSize {
            explanation.currentValue = AttentionExplanationFact(
                key: "currentValue",
                label: "Current",
                value: signedPercent(moveSize),
                numericValue: moveSize,
                unit: "fraction"
            )
        } else if let eventDate {
            let amountDetail = amount.map { "; \(display($0))" } ?? ""
            explanation.currentValue = AttentionExplanationFact(
                key: "currentValue",
                label: "Current",
                value: "\(eventDate)\(amountDetail)"
            )
        }
        if let beforeValue,
           let valueCurrency
        {
            explanation.priorValue = AttentionExplanationFact(
                key: "priorValue",
                label: "Prior",
                value: "\(valueCurrency) \(decimalString(String(beforeValue), places: 2))",
                numericValue: beforeValue,
                unit: valueCurrency
            )
        } else if let beforeWeight {
            explanation.priorValue = AttentionExplanationFact(
                key: "priorValue",
                label: "Prior",
                value: percent(beforeWeight),
                numericValue: beforeWeight,
                unit: "fraction"
            )
        }
        return explanation
    }
}

public extension AttentionItem {
    private var readFingerprintIdentity: String {
        holdingIdentity.map { "quote:\($0.quoteId)" }
            ?? "id:\(fingerprintToken(id))"
    }

    var readFingerprint: String {
        switch typedFacet {
        case .allocation:
            return [
                "pulse:v1:allocation",
                readFingerprintIdentity,
                "threshold-bp:\(fingerprintBasisPoints(threshold))",
                "severity:\(fingerprintToken(severity))",
                "weight-bucket-bp:\(bucketBasisPoints(currentWeight, bucketSize: 100))",
            ].joined(separator: ":")
        case .income:
            return [
                "pulse:v1:income",
                readFingerprintIdentity,
                "date:\(eventDate ?? "unknown")",
                "amount:\(moneyFingerprint(amount))",
                "change-bp:\(fingerprintBasisPoints(changePercent))",
            ].joined(separator: ":")
        case .bigMovers:
            return [
                "pulse:v1:bigMovers",
                readFingerprintIdentity,
                "window:\(windowStart ?? "unknown")..\(windowEnd ?? "unknown")",
                "move-bucket-bp:\(bucketBasisPoints(moveSize, bucketSize: 100))",
            ].joined(separator: ":")
        case .unknown:
            return [
                "pulse:v1",
                fingerprintToken(typedFacet.rawValue),
                readFingerprintIdentity,
                "severity:\(fingerprintToken(severity))",
                "score-bp:\(fingerprintBasisPoints(score))",
            ].joined(separator: ":")
        }
    }

    var staleReadPruningPrefix: String? {
        switch typedFacet {
        case .income:
            return ["pulse:v1:income", readFingerprintIdentity].joined(separator: ":") + ":"
        case .bigMovers:
            return ["pulse:v1:bigMovers", readFingerprintIdentity].joined(separator: ":") + ":"
        case .allocation, .unknown:
            return nil
        }
    }

    var concentrationReadFingerprintPrefix: String? {
        guard typedFacet == .allocation else {
            return nil
        }
        return [
            "pulse:v1:allocation",
            readFingerprintIdentity,
            "threshold-bp:\(fingerprintBasisPoints(threshold))",
        ].joined(separator: ":") + ":"
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
    public var dataHealth: DataHealthSnapshot

    public init(
        allocation: AllocationSnapshot,
        income: IncomeSnapshot,
        bigMovers: BigMoversSnapshot,
        freshness: FreshnessSnapshot,
        dataHealth: DataHealthSnapshot? = nil
    ) {
        self.allocation = allocation
        self.income = income
        self.bigMovers = bigMovers
        self.freshness = freshness
        self.dataHealth = dataHealth ?? DataHealth.build(
            DataHealthInput.default(freshness: freshness)
        )
    }

    enum CodingKeys: String, CodingKey {
        case allocation
        case income
        case bigMovers
        case freshness
        case dataHealth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allocation = try container.decode(AllocationSnapshot.self, forKey: .allocation)
        income = try container.decode(IncomeSnapshot.self, forKey: .income)
        bigMovers = try container.decode(BigMoversSnapshot.self, forKey: .bigMovers)
        freshness = try container.decode(FreshnessSnapshot.self, forKey: .freshness)
        dataHealth = try container.decodeIfPresent(DataHealthSnapshot.self, forKey: .dataHealth)
            ?? DataHealth.build(DataHealthInput.default(freshness: freshness))
    }
}

public struct AllocationSnapshot: Codable, Equatable {
    public var totalValue: Money
    public var openHoldingCount: Int
    public var topHoldings: [HoldingSummary]
    public var sectorBreakdown: [DistributionSummary]
    public var assetTypeBreakdown: [DistributionSummary]
    public var xRayHoldings: [XRayHoldingSummary]?
    public var portfolioOverview: PortfolioOverviewSummary
    public var allocationPressureItems: [AttentionItem]

    public init(
        totalValue: Money,
        openHoldingCount: Int,
        topHoldings: [HoldingSummary],
        sectorBreakdown: [DistributionSummary],
        assetTypeBreakdown: [DistributionSummary],
        xRayHoldings: [XRayHoldingSummary]? = nil,
        portfolioOverview: PortfolioOverviewSummary? = nil,
        allocationPressureItems: [AttentionItem] = []
    ) {
        self.totalValue = totalValue
        self.openHoldingCount = openHoldingCount
        self.topHoldings = topHoldings
        self.sectorBreakdown = sectorBreakdown
        self.assetTypeBreakdown = assetTypeBreakdown
        self.xRayHoldings = xRayHoldings
        self.portfolioOverview = portfolioOverview ?? PortfolioOverview.build(
            totalValue: totalValue,
            openHoldingCount: openHoldingCount,
            topHoldings: topHoldings,
            sectorBreakdown: sectorBreakdown,
            assetTypeBreakdown: assetTypeBreakdown
        )
        self.allocationPressureItems = allocationPressureItems
    }

    enum CodingKeys: String, CodingKey {
        case totalValue
        case openHoldingCount
        case topHoldings
        case sectorBreakdown
        case assetTypeBreakdown
        case xRayHoldings
        case portfolioOverview
        case allocationPressureItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let totalValue = try container.decode(Money.self, forKey: .totalValue)
        let openHoldingCount = try container.decode(Int.self, forKey: .openHoldingCount)
        let topHoldings = try container.decode([HoldingSummary].self, forKey: .topHoldings)
        let sectorBreakdown = try container.decode([DistributionSummary].self, forKey: .sectorBreakdown)
        let assetTypeBreakdown = try container.decode([DistributionSummary].self, forKey: .assetTypeBreakdown)
        let xRayHoldings = try container.decodeIfPresent([XRayHoldingSummary].self, forKey: .xRayHoldings)
        self.init(
            totalValue: totalValue,
            openHoldingCount: openHoldingCount,
            topHoldings: topHoldings,
            sectorBreakdown: sectorBreakdown,
            assetTypeBreakdown: assetTypeBreakdown,
            xRayHoldings: xRayHoldings,
            portfolioOverview: try container.decodeIfPresent(
                PortfolioOverviewSummary.self,
                forKey: .portfolioOverview
            ),
            allocationPressureItems: try container.decodeIfPresent(
                [AttentionItem].self,
                forKey: .allocationPressureItems
            ) ?? []
        )
    }
}

public struct HoldingSummary: Codable, Equatable {
    public var name: String
    public var quoteId: Int
    public var weight: Double
    public var worth: Money
    public var price: Money?
    public var copyableIdentifier: String?
    public var isin: String?
    public var recentMove: PriceMoveSummary?
    public var nextIncomeEvent: IncomeEventSummary?
    public var averageBuyPrice: Money?
    public var gainLoss: Money?
    public var gainLossPercentage: Double?

    public init(
        name: String,
        quoteId: Int,
        weight: Double,
        worth: Money,
        price: Money?,
        copyableIdentifier: String? = nil,
        isin: String? = nil,
        recentMove: PriceMoveSummary? = nil,
        nextIncomeEvent: IncomeEventSummary? = nil,
        averageBuyPrice: Money? = nil,
        gainLoss: Money? = nil,
        gainLossPercentage: Double? = nil
    ) {
        self.name = name
        self.quoteId = quoteId
        self.weight = weight
        self.worth = worth
        self.price = price
        self.copyableIdentifier = copyableIdentifier
        self.isin = PDTBaseHoldingNormalizer.safeISIN(isin)
        self.recentMove = recentMove
        self.nextIncomeEvent = nextIncomeEvent
        self.averageBuyPrice = averageBuyPrice
        self.gainLoss = gainLoss
        self.gainLossPercentage = gainLossPercentage
    }
}

public struct DistributionSummary: Codable, Equatable {
    public var name: String
    public var percentage: Double
    public var totalValue: Money

    public init(name: String, percentage: Double, totalValue: Money) {
        self.name = name
        self.percentage = percentage
        self.totalValue = totalValue
    }
}

public struct PortfolioOverviewSummary: Codable, Equatable {
    public var totalValue: Money
    public var openHoldingCount: Int
    public var topHoldings: [HoldingSummary]
    public var topNConcentration: PortfolioTopNConcentrationSummary?
    public var sectorSummary: [DistributionSummary]
    public var assetTypeSummary: [DistributionSummary]
    public var cashSummary: PortfolioCashSummary?

    public init(
        totalValue: Money,
        openHoldingCount: Int,
        topHoldings: [HoldingSummary],
        topNConcentration: PortfolioTopNConcentrationSummary?,
        sectorSummary: [DistributionSummary],
        assetTypeSummary: [DistributionSummary],
        cashSummary: PortfolioCashSummary?
    ) {
        self.totalValue = totalValue
        self.openHoldingCount = openHoldingCount
        self.topHoldings = topHoldings
        self.topNConcentration = topNConcentration
        self.sectorSummary = sectorSummary
        self.assetTypeSummary = assetTypeSummary
        self.cashSummary = cashSummary
    }
}

public struct PortfolioTopNConcentrationSummary: Codable, Equatable {
    public var rankCount: Int
    public var weight: Double

    public init(rankCount: Int, weight: Double) {
        self.rankCount = rankCount
        self.weight = weight
    }
}

public struct PortfolioCashSummary: Codable, Equatable {
    public var value: Money
    public var weight: Double

    public init(value: Money, weight: Double) {
        self.value = value
        self.weight = weight
    }
}

public enum PortfolioOverview {
    public static let topHoldingLimit = 5
    public static let concentrationRankCount = 3

    public static func build(from snapshot: PortfolioSnapshot) -> PortfolioOverviewSummary {
        let topHoldings = snapshot.openHoldings
            .compactMap(holdingSummary)
            .sorted(by: ranksByAllocation)
        return build(
            totalValue: snapshot.totalValue,
            openHoldingCount: snapshot.openHoldings.count,
            topHoldings: topHoldings,
            sectorBreakdown: snapshot.sectors,
            assetTypeBreakdown: snapshot.assetTypes
        )
    }

    public static func build(
        totalValue: Money,
        openHoldingCount: Int,
        topHoldings: [HoldingSummary],
        sectorBreakdown: [DistributionSummary],
        assetTypeBreakdown: [DistributionSummary]
    ) -> PortfolioOverviewSummary {
        let topHoldings = topHoldings
            .filter { validWeight($0.weight) && validMoney($0.worth) }
            .sorted(by: ranksByAllocation)
        let sectors = summaryDistributions(sectorBreakdown)
        let assetTypes = summaryDistributions(assetTypeBreakdown)
        return PortfolioOverviewSummary(
            totalValue: totalValue,
            openHoldingCount: openHoldingCount,
            topHoldings: topHoldings,
            topNConcentration: topNConcentration(from: topHoldings),
            sectorSummary: sectors,
            assetTypeSummary: assetTypes,
            cashSummary: cashSummary(from: topHoldings, assetTypes: assetTypes)
        )
    }

    public static func topNConcentration(
        from holdings: [HoldingSummary],
        rankCount: Int = concentrationRankCount
    ) -> PortfolioTopNConcentrationSummary? {
        let top = Array(holdings
            .filter { validWeight($0.weight) }
            .sorted(by: ranksByAllocation)
            .prefix(max(0, rankCount)))
        guard !top.isEmpty else {
            return nil
        }
        return PortfolioTopNConcentrationSummary(
            rankCount: top.count,
            weight: top.reduce(0.0) { $0 + $1.weight }
        )
    }

    public static func cashSummary(
        from holdings: [HoldingSummary],
        assetTypes: [DistributionSummary]
    ) -> PortfolioCashSummary? {
        if let holding = holdings.first(where: { $0.name.caseInsensitiveCompare("Cash") == .orderedSame }),
           validWeight(holding.weight),
           validMoney(holding.worth)
        {
            return PortfolioCashSummary(value: holding.worth, weight: holding.weight)
        }
        guard let cashAssetType = assetTypes.first(where: { $0.name.caseInsensitiveCompare("cash") == .orderedSame }),
              validPercentage(cashAssetType.percentage),
              validMoney(cashAssetType.totalValue)
        else {
            return nil
        }
        return PortfolioCashSummary(value: cashAssetType.totalValue, weight: cashAssetType.percentage / 100.0)
    }

    private static func holdingSummary(_ holding: NormalizedHolding) -> HoldingSummary? {
        guard validWeight(holding.weight),
              validMoney(holding.worth)
        else {
            return nil
        }
        return HoldingSummary(
            name: holding.name,
            quoteId: holding.quoteId,
            weight: holding.weight,
            worth: holding.worth,
            price: sanitizedMoney(holding.price),
            copyableIdentifier: holding.copyableIdentifier,
            isin: holding.isin,
            averageBuyPrice: sanitizedMoney(holding.averageBuyPrice),
            gainLoss: sanitizedMoney(holding.gainLoss),
            gainLossPercentage: holding.gainLossPercentage?.isFinite == true ? holding.gainLossPercentage : nil
        )
    }

    private static func summaryDistributions(_ distributions: [DistributionSummary]) -> [DistributionSummary] {
        distributions
            .filter { validPercentage($0.percentage) && validMoney($0.totalValue) }
            .sorted {
                if $0.percentage != $1.percentage {
                    return $0.percentage > $1.percentage
                }
                return $0.name < $1.name
            }
    }

    private static func ranksByAllocation(_ lhs: HoldingSummary, _ rhs: HoldingSummary) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight > rhs.weight
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.quoteId < rhs.quoteId
    }

    // Overview rows render weights as fractions and distributions as 0...100 percentages.
    // Over-range upstream facts are treated as malformed instead of being clamped.
    private static func validWeight(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 1
    }

    private static func validPercentage(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 100
    }

    private static func validMoney(_ money: Money?) -> Bool {
        guard let money,
              !money.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Decimal(string: money.value, locale: Locale(identifier: "en_US_POSIX")) != nil
        else {
            return false
        }
        return true
    }

    private static func sanitizedMoney(_ money: Money?) -> Money? {
        validMoney(money) ? money : nil
    }
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
    public var performance: PortfolioPerformanceSummary?
    public var latestCompleteDetailFillAsOf: String?
    public var latestDetailFillOutcome: PDTBackgroundDetailRefreshOutcome?

    public init(
        asOf: String,
        totalValue: Money,
        openHoldings: [NormalizedHolding],
        sectors: [DistributionSummary],
        assetTypes: [DistributionSummary],
        xRayHoldings: [XRayHoldingSummary]? = nil,
        incomeEvents: [IncomeEventSummary],
        dividendRowCount: Int,
        priceSeries: [PricePoint],
        performance: PortfolioPerformanceSummary? = nil,
        latestCompleteDetailFillAsOf: String? = nil,
        latestDetailFillOutcome: PDTBackgroundDetailRefreshOutcome? = nil
    ) {
        self.asOf = asOf
        self.totalValue = totalValue
        self.openHoldings = openHoldings
        self.sectors = sectors
        self.assetTypes = assetTypes
        self.xRayHoldings = xRayHoldings
        self.incomeEvents = incomeEvents
        self.dividendRowCount = dividendRowCount
        self.priceSeries = priceSeries
        self.performance = performance
        self.latestCompleteDetailFillAsOf = latestCompleteDetailFillAsOf
        self.latestDetailFillOutcome = latestDetailFillOutcome
    }
}

public struct NormalizedHolding: Codable, Equatable {
    public var name: String
    public var quoteId: Int
    public var weight: Double
    public var worth: Money
    public var price: Money?
    public var priceAsOf: String
    public var copyableIdentifier: String?
    public var isin: String?
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
        isin: String? = nil,
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
        self.isin = PDTBaseHoldingNormalizer.safeISIN(isin)
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
        isin = PDTBaseHoldingNormalizer.safeISIN(try? container.decodeIfPresent(String.self, forKey: .isin))
        averageBuyPrice = validMoney(try? container.decodeIfPresent(Money.self, forKey: .averageBuyPrice))
        gainLoss = validMoney(try? container.decodeIfPresent(Money.self, forKey: .gainLoss))
        gainLossPercentage = finite(try? container.decodeIfPresent(Double.self, forKey: .gainLossPercentage))
    }
}

public struct PricePoint: Codable, Equatable {
    public var quoteId: Int
    public var date: String
    public var closeAdjusted: String
    public var closeCurrency: String?
}

func validMoney(_ money: Money?) -> Money? {
    PDTBaseHoldingNormalizer.validMoney(money)
}

func posixDecimal(_ value: String) -> Decimal? {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}

func finite(_ value: Double?) -> Double? {
    PDTBaseHoldingNormalizer.finite(value)
}
