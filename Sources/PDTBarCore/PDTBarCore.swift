import Darwin
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
        self.explanation = explanation ?? Self.legacyExplanation(
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
        explanation = try container.decodeIfPresent(AttentionExplanation.self, forKey: .explanation)
            ?? Self.legacyExplanation(
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
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return PulseReadState()
        }
        if !isDirectory.boolValue {
            try OwnerOnlyLocalStore.protectExistingFile(target)
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
        try OwnerOnlyLocalStore.write(stableJSONData(state), to: stateFile)
    }

    private var stateFile: URL {
        directory.appending(path: "pulse-read-state.json")
    }
}

private enum OwnerOnlyLocalStore {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    static func protectExistingFile(_ target: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return
        }
        try prepareDirectory(target.deletingLastPathComponent())
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: target.path
        )
    }

    static func write(_ data: Data, to target: URL) throws {
        let directory = target.deletingLastPathComponent()
        try prepareDirectory(directory)
        let temporary = directory.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: filePermissions]
        ) else {
            throw POSIXError(.EIO)
        }
        var removeTemporaryOnFailure = true
        defer {
            if removeTemporaryOnFailure {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: temporary.path
        )
        let renameResult = temporary.withUnsafeFileSystemRepresentation { temporaryPath in
            target.withUnsafeFileSystemRepresentation { targetPath in
                guard let temporaryPath, let targetPath else {
                    return -1
                }
                return Int(Darwin.rename(temporaryPath, targetPath))
            }
        }
        guard renameResult == 0 else {
            let failure = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(failure)
        }
        removeTemporaryOnFailure = false
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: target.path
        )
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

public enum FreshnessState: String, Codable, Equatable {
    case fresh
    case stale
    case partial
    case unknown
}

public struct FreshnessHoldingRow: Codable, Equatable {
    public var name: String
    public var quoteId: Int
    public var priceAsOf: String

    public init(name: String, quoteId: Int, priceAsOf: String) {
        self.name = name
        self.quoteId = quoteId
        self.priceAsOf = priceAsOf
    }
}

public struct FreshnessSnapshot: Codable, Equatable {
    public var status: FreshnessState
    public var worstPriceAsOf: String?
    public var stale: Bool
    public var staleHoldingCount: Int
    public var oldestPriceAsOf: String?
    public var oldestRows: [FreshnessHoldingRow]
    public var latestCompleteDetailFillAsOf: String?
    public var sourceCaveats: [String]

    public init(
        status: FreshnessState,
        worstPriceAsOf: String?,
        stale: Bool,
        staleHoldingCount: Int,
        oldestPriceAsOf: String?,
        oldestRows: [FreshnessHoldingRow],
        latestCompleteDetailFillAsOf: String?,
        sourceCaveats: [String]
    ) {
        self.status = status
        self.worstPriceAsOf = worstPriceAsOf
        self.stale = stale
        self.staleHoldingCount = max(0, staleHoldingCount)
        self.oldestPriceAsOf = oldestPriceAsOf
        self.oldestRows = oldestRows
        self.latestCompleteDetailFillAsOf = latestCompleteDetailFillAsOf
        self.sourceCaveats = sourceCaveats
    }

    public init(worstPriceAsOf: String?, stale: Bool) {
        self.init(
            status: stale ? .stale : (worstPriceAsOf == nil ? .unknown : .fresh),
            worstPriceAsOf: worstPriceAsOf,
            stale: stale,
            staleHoldingCount: 0,
            oldestPriceAsOf: worstPriceAsOf,
            oldestRows: [],
            latestCompleteDetailFillAsOf: nil,
            sourceCaveats: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case status
        case worstPriceAsOf
        case stale
        case staleHoldingCount
        case oldestPriceAsOf
        case oldestRows
        case latestCompleteDetailFillAsOf
        case sourceCaveats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let worstPriceAsOf = try container.decodeIfPresent(String.self, forKey: .worstPriceAsOf)
        let stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        self.init(
            status: try container.decodeIfPresent(FreshnessState.self, forKey: .status)
                ?? (stale ? .stale : (worstPriceAsOf == nil ? .unknown : .fresh)),
            worstPriceAsOf: worstPriceAsOf,
            stale: stale,
            staleHoldingCount: try container.decodeIfPresent(Int.self, forKey: .staleHoldingCount) ?? 0,
            oldestPriceAsOf: try container.decodeIfPresent(String.self, forKey: .oldestPriceAsOf) ?? worstPriceAsOf,
            oldestRows: try container.decodeIfPresent([FreshnessHoldingRow].self, forKey: .oldestRows) ?? [],
            latestCompleteDetailFillAsOf: try container.decodeIfPresent(String.self, forKey: .latestCompleteDetailFillAsOf),
            sourceCaveats: try container.decodeIfPresent([String].self, forKey: .sourceCaveats) ?? []
        )
    }
}

public enum FreshnessLedger {
    public static let staleBusinessDayGrace = 1
    public static let oldestRowLimit = 3

    public static func build(
        from snapshot: PortfolioSnapshot,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil
    ) -> FreshnessSnapshot {
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        let datedRows = snapshot.openHoldings.compactMap { holding -> (row: FreshnessHoldingRow, date: Date)? in
            guard let date = freshnessDate(from: holding.priceAsOf) else {
                return nil
            }
            return (
                FreshnessHoldingRow(name: holding.name, quoteId: holding.quoteId, priceAsOf: holding.priceAsOf),
                date
            )
        }
        let sortedRows = datedRows.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            if $0.row.name != $1.row.name {
                return $0.row.name < $1.row.name
            }
            return $0.row.quoteId < $1.row.quoteId
        }
        let staleRows = datedRows.filter {
            isStale(priceDate: $0.date, asOf: snapshot.asOf)
        }
        let oldestRows = Array(sortedRows.prefix(oldestRowLimit).map(\.row))
        let oldestPriceAsOf = sortedRows.first?.row.priceAsOf
        let hasUnknownPriceDates = snapshot.openHoldings.isEmpty || datedRows.count != snapshot.openHoldings.count
        let stale = !staleRows.isEmpty
        let latestCompleteDetailFillAsOf = effectiveDetailRefreshOutcome == .completed
            ? snapshot.latestCompleteDetailFillAsOf ?? snapshot.asOf
            : snapshot.latestCompleteDetailFillAsOf
        let detailFillIncomplete = effectiveDetailRefreshOutcome == .degraded
            || (latestCompleteDetailFillAsOf != nil && latestCompleteDetailFillAsOf != snapshot.asOf)
        let status: FreshnessState
        if hasUnknownPriceDates {
            status = .unknown
        } else if stale {
            status = .stale
        } else if detailFillIncomplete {
            status = .partial
        } else {
            status = .fresh
        }

        return FreshnessSnapshot(
            status: status,
            worstPriceAsOf: oldestPriceAsOf,
            stale: stale,
            staleHoldingCount: staleRows.count,
            oldestPriceAsOf: oldestPriceAsOf,
            oldestRows: oldestRows,
            latestCompleteDetailFillAsOf: latestCompleteDetailFillAsOf,
            sourceCaveats: sourceCaveats(
                status: status,
                openHoldingCount: snapshot.openHoldings.count,
                datedHoldingCount: datedRows.count,
                detailFillIncomplete: detailFillIncomplete
            )
        )
    }

    private static func sourceCaveats(
        status: FreshnessState,
        openHoldingCount: Int,
        datedHoldingCount: Int,
        detailFillIncomplete: Bool
    ) -> [String] {
        var caveats = ["Distribution dates are not reported by PDT"]
        if openHoldingCount == 0 || datedHoldingCount == 0 {
            caveats.append("No open holdings with dated prices")
        } else if datedHoldingCount < openHoldingCount {
            caveats.append("Some holdings have unknown price dates")
        }
        if status == .partial || detailFillIncomplete {
            caveats.append("Optional detail fill incomplete; some detail rows may use prior data")
        }
        return caveats
    }

    private static func isStale(priceDate: Date, asOf: String) -> Bool {
        guard let asOfDate = freshnessDate(from: asOf),
              priceDate < asOfDate
        else {
            return false
        }
        return businessDays(after: priceDate, through: asOfDate) > staleBusinessDayGrace
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

    private static func freshnessDate(from value: String) -> Date? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = freshnessCalendar
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }

    private static var freshnessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}

public enum DataHealthStatus: String, Codable, Equatable {
    case healthy
    case degraded
}

public enum DataHealthSourceStatus: String, Codable, Equatable {
    case ready
    case checking
    case missing
    case failed
    case unknown
}

public enum DataHealthReadToolsStatus: String, Codable, Equatable {
    case available
    case missingRequired
    case unknown
}

public enum DataHealthReadOnlyPolicyStatus: String, Codable, Equatable {
    case enforced
    case unknown
}

public enum DataHealthDetailFillOutcome: String, Codable, Equatable {
    case notStarted
    case inProgress
    case completed
    case degraded
    case failed
}

public enum DataHealthDetailFillInput: Equatable {
    case notStarted
    case inProgress(BackgroundDetailRefreshProgress)
    case completed(asOf: String?)
    case degraded
    case failed
}

public struct DataHealthInput: Equatable {
    public var claudeReadiness: DataHealthSourceStatus
    public var pdtMCPReadiness: DataHealthSourceStatus
    public var availableReadTools: Set<String>?
    public var readOnlyPolicy: DataHealthReadOnlyPolicyStatus
    public var pulseSource: PulseLifecycleSource?
    public var lastSuccessfulCompleteFetchAsOf: String?
    public var cachedPulseAvailable: Bool
    public var detailFill: DataHealthDetailFillInput
    public var freshness: FreshnessSnapshot
    public var readState: PulseReadState?
    public var diagnostic: PDTDetailRefreshFailureDiagnostic?

    public init(
        claudeReadiness: DataHealthSourceStatus,
        pdtMCPReadiness: DataHealthSourceStatus,
        availableReadTools: Set<String>?,
        readOnlyPolicy: DataHealthReadOnlyPolicyStatus,
        pulseSource: PulseLifecycleSource?,
        lastSuccessfulCompleteFetchAsOf: String?,
        cachedPulseAvailable: Bool,
        detailFill: DataHealthDetailFillInput,
        freshness: FreshnessSnapshot,
        readState: PulseReadState?,
        diagnostic: PDTDetailRefreshFailureDiagnostic? = nil
    ) {
        self.claudeReadiness = claudeReadiness
        self.pdtMCPReadiness = pdtMCPReadiness
        self.availableReadTools = availableReadTools
        self.readOnlyPolicy = readOnlyPolicy
        self.pulseSource = pulseSource
        self.lastSuccessfulCompleteFetchAsOf = lastSuccessfulCompleteFetchAsOf
        self.cachedPulseAvailable = cachedPulseAvailable
        self.detailFill = detailFill
        self.freshness = freshness
        self.readState = readState
        self.diagnostic = diagnostic
    }

    public static func `default`(
        freshness: FreshnessSnapshot,
        pulseSource: PulseLifecycleSource? = nil,
        readState: PulseReadState? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        diagnostic: PDTDetailRefreshFailureDiagnostic? = nil
    ) -> DataHealthInput {
        DataHealthInput(
            claudeReadiness: .ready,
            pdtMCPReadiness: .ready,
            availableReadTools: Set(PDTReadTools.requiredV1),
            readOnlyPolicy: .enforced,
            pulseSource: pulseSource,
            lastSuccessfulCompleteFetchAsOf: freshness.latestCompleteDetailFillAsOf,
            cachedPulseAvailable: pulseSource != nil,
            detailFill: detailFillInput(outcome: detailRefreshOutcome, freshness: freshness),
            freshness: freshness,
            readState: readState,
            diagnostic: diagnostic
        )
    }

    private static func detailFillInput(
        outcome: PDTBackgroundDetailRefreshOutcome?,
        freshness: FreshnessSnapshot
    ) -> DataHealthDetailFillInput {
        switch outcome {
        case .completed:
            return .completed(asOf: freshness.latestCompleteDetailFillAsOf)
        case .degraded:
            return .degraded
        case nil:
            if let latestComplete = freshness.latestCompleteDetailFillAsOf {
                return .completed(asOf: latestComplete)
            }
            return .notStarted
        }
    }
}

public struct DataHealthSourceSnapshot: Codable, Equatable {
    public var claude: DataHealthSourceStatus
    public var pdtMCP: DataHealthSourceStatus
    public var readTools: DataHealthReadToolsStatus
    public var requiredReadToolCount: Int
    public var availableReadToolCount: Int?
    public var missingReadTools: [String]
    public var readOnlyPolicy: DataHealthReadOnlyPolicyStatus
    public var detail: String
}

public struct DataHealthCacheSnapshot: Codable, Equatable {
    public var pulseSource: PulseLifecycleSource?
    public var cachedPulseAvailable: Bool
    public var lastSuccessfulCompleteFetchAsOf: String?
    public var summary: String
}

public struct DataHealthDetailFillSnapshot: Codable, Equatable {
    public var outcome: DataHealthDetailFillOutcome
    public var phase: BackgroundDetailRefreshPhase?
    public var completedUnitCount: Int?
    public var totalUnitCount: Int?
    public var asOf: String?
    public var detail: String
}

public struct DataHealthFreshnessSummary: Codable, Equatable {
    public var status: FreshnessState
    public var staleHoldingCount: Int
    public var oldestPriceAsOf: String?
    public var detail: String
}

public struct DataHealthReadStateSnapshot: Codable, Equatable {
    public var readFingerprintCount: Int
    public var detail: String
}

public struct DataHealthDiagnosticSummary: Codable, Equatable {
    public var available: Bool
    public var detail: String
    public var copyText: String
}

public struct DataHealthSnapshot: Codable, Equatable {
    public var status: DataHealthStatus
    public var source: DataHealthSourceSnapshot
    public var cache: DataHealthCacheSnapshot
    public var detailFill: DataHealthDetailFillSnapshot
    public var freshness: DataHealthFreshnessSummary
    public var readState: DataHealthReadStateSnapshot
    public var diagnostic: DataHealthDiagnosticSummary?
}

public enum DataHealth {
    public static func build(_ input: DataHealthInput) -> DataHealthSnapshot {
        let requiredTools = PDTReadTools.requiredV1
        let missingTools = input.availableReadTools.map { PDTReadTools.missingRequiredV1Tools(in: $0) } ?? []
        let readToolsStatus: DataHealthReadToolsStatus
        if input.availableReadTools == nil {
            readToolsStatus = .unknown
        } else if missingTools.isEmpty {
            readToolsStatus = .available
        } else {
            readToolsStatus = .missingRequired
        }
        let source = DataHealthSourceSnapshot(
            claude: input.claudeReadiness,
            pdtMCP: input.pdtMCPReadiness,
            readTools: readToolsStatus,
            requiredReadToolCount: requiredTools.count,
            availableReadToolCount: input.availableReadTools?.intersection(requiredTools).count,
            missingReadTools: missingTools,
            readOnlyPolicy: input.readOnlyPolicy,
            detail: sourceDetail(
                claude: input.claudeReadiness,
                pdtMCP: input.pdtMCPReadiness,
                readTools: readToolsStatus,
                availableCount: input.availableReadTools?.intersection(requiredTools).count,
                requiredCount: requiredTools.count,
                missingTools: missingTools,
                readOnlyPolicy: input.readOnlyPolicy
            )
        )
        let cache = DataHealthCacheSnapshot(
            pulseSource: input.pulseSource,
            cachedPulseAvailable: input.cachedPulseAvailable,
            lastSuccessfulCompleteFetchAsOf: input.lastSuccessfulCompleteFetchAsOf,
            summary: cacheSummary(
                cachedPulseAvailable: input.cachedPulseAvailable,
                lastSuccessfulCompleteFetchAsOf: input.lastSuccessfulCompleteFetchAsOf
            )
        )
        let detailFill = detailFillSnapshot(input.detailFill)
        let freshness = DataHealthFreshnessSummary(
            status: input.freshness.status,
            staleHoldingCount: input.freshness.staleHoldingCount,
            oldestPriceAsOf: input.freshness.oldestPriceAsOf,
            detail: freshnessDetail(input.freshness)
        )
        let readState = DataHealthReadStateSnapshot(
            readFingerprintCount: input.readState?.readFingerprints.count ?? 0,
            detail: "\(input.readState?.readFingerprints.count ?? 0) read"
        )
        let diagnostic = input.diagnostic.map(diagnosticSummary)
        return DataHealthSnapshot(
            status: healthStatus(
                source: source,
                detailFill: detailFill,
                freshness: freshness,
                diagnostic: diagnostic
            ),
            source: source,
            cache: cache,
            detailFill: detailFill,
            freshness: freshness,
            readState: readState,
            diagnostic: diagnostic
        )
    }

    private static func healthStatus(
        source: DataHealthSourceSnapshot,
        detailFill: DataHealthDetailFillSnapshot,
        freshness: DataHealthFreshnessSummary,
        diagnostic: DataHealthDiagnosticSummary?
    ) -> DataHealthStatus {
        if source.claude != .ready
            || source.pdtMCP != .ready
            || source.readTools != .available
            || source.readOnlyPolicy != .enforced
            || detailFill.outcome == .degraded
            || detailFill.outcome == .failed
            || freshness.status != .fresh
            || diagnostic != nil
        {
            return .degraded
        }
        return .healthy
    }

    private static func sourceDetail(
        claude: DataHealthSourceStatus,
        pdtMCP: DataHealthSourceStatus,
        readTools: DataHealthReadToolsStatus,
        availableCount: Int?,
        requiredCount: Int,
        missingTools: [String],
        readOnlyPolicy: DataHealthReadOnlyPolicyStatus
    ) -> String {
        let toolCopy: String
        switch readTools {
        case .available:
            toolCopy = "\(availableCount ?? requiredCount)/\(requiredCount) read tools"
        case .missingRequired:
            toolCopy = "\(availableCount ?? 0)/\(requiredCount) read tools; missing \(missingTools.joined(separator: ", "))"
        case .unknown:
            toolCopy = "read tools unknown"
        }
        return [
            "Claude \(statusCopy(claude))",
            "PDT \(statusCopy(pdtMCP))",
            toolCopy,
            readOnlyPolicy == .enforced ? "read-only" : "policy unknown",
        ].joined(separator: "; ")
    }

    private static func statusCopy(_ status: DataHealthSourceStatus) -> String {
        switch status {
        case .ready:
            return "ready"
        case .checking:
            return "checking"
        case .missing:
            return "missing"
        case .failed:
            return "failed"
        case .unknown:
            return "unknown"
        }
    }

    private static func cacheSummary(
        cachedPulseAvailable: Bool,
        lastSuccessfulCompleteFetchAsOf: String?
    ) -> String {
        guard cachedPulseAvailable else {
            return "No cached pulse"
        }
        guard let lastSuccessfulCompleteFetchAsOf else {
            return "Cached pulse available"
        }
        return "Last complete \(lastSuccessfulCompleteFetchAsOf)"
    }

    private static func detailFillSnapshot(_ input: DataHealthDetailFillInput) -> DataHealthDetailFillSnapshot {
        switch input {
        case .notStarted:
            return DataHealthDetailFillSnapshot(
                outcome: .notStarted,
                phase: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                asOf: nil,
                detail: "Not started"
            )
        case .completed(let asOf):
            return DataHealthDetailFillSnapshot(
                outcome: .completed,
                phase: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                asOf: asOf,
                detail: asOf.map { "Completed \($0)" } ?? "Completed"
            )
        case .degraded:
            return DataHealthDetailFillSnapshot(
                outcome: .degraded,
                phase: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                asOf: nil,
                detail: "Degraded"
            )
        case .failed:
            return DataHealthDetailFillSnapshot(
                outcome: .failed,
                phase: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                asOf: nil,
                detail: "Failed"
            )
        case .inProgress(let progress):
            let progressDetail: String
            if let completed = progress.completedUnitCount,
               let total = progress.totalUnitCount
            {
                progressDetail = "\(progress.phase.title) \(max(0, completed))/\(max(0, total))"
            } else {
                progressDetail = progress.phase.title
            }
            return DataHealthDetailFillSnapshot(
                outcome: .inProgress,
                phase: progress.phase,
                completedUnitCount: progress.completedUnitCount,
                totalUnitCount: progress.totalUnitCount,
                asOf: nil,
                detail: progressDetail
            )
        }
    }

    private static func freshnessDetail(_ freshness: FreshnessSnapshot) -> String {
        switch freshness.status {
        case .fresh:
            return freshness.oldestPriceAsOf.map { "Fresh; oldest \($0)" } ?? "Fresh"
        case .stale:
            return "\(freshness.staleHoldingCount) stale"
        case .partial:
            return freshness.oldestPriceAsOf.map { "Partial; oldest \($0)" } ?? "Partial"
        case .unknown:
            return "Unknown"
        }
    }

    private static func diagnosticSummary(_ diagnostic: PDTDetailRefreshFailureDiagnostic) -> DataHealthDiagnosticSummary {
        let argumentKeys = diagnostic.argumentShape.joined(separator: ",")
        let copyText = [
            "PDTBar data health",
            "tool: \(diagnostic.toolName)",
            "phase: \(diagnostic.phase.rawValue)",
            "category: \(diagnostic.category.rawValue)",
            "attempts: \(diagnostic.attemptCount)",
            "argument_keys: \(argumentKeys)",
        ].joined(separator: "\n")
        return DataHealthDiagnosticSummary(
            available: true,
            detail: "\(diagnostic.toolName); \(diagnostic.phase.rawValue); \(diagnostic.category.rawValue)",
            copyText: copyText
        )
    }
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
    case portfolioOverview
    case portfolioOverviewChart
    case portfolioOverviewDetails
    case portfolioOverviewHoldings
    case portfolioOverviewConcentration
    case portfolioOverviewSector
    case portfolioOverviewAssetType
    case portfolioOverviewCash
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
    case freshnessStaleCount
    case freshnessOldestPrice
    case freshnessOldestRows
    case freshnessOldestHolding
    case freshnessDetailFill
    case freshnessCaveats
    case dataHealthSummary
    case dataHealthSource
    case dataHealthCache
    case dataHealthDetailFill
    case dataHealthReadState
    case dataHealthDiagnostic
    case dataHealthDiagnosticCopy
    case holdingIdentifierCopy
    case openPDT

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
    case copyDataHealthDiagnostic
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

public struct MenuRowBarChart: Codable, Equatable {
    public var bars: [Bar]

    public init(bars: [Bar]) {
        self.bars = bars
    }

    public struct Bar: Codable, Equatable {
        public var id: String
        public var label: String
        public var axisLabel: String?
        public var weight: Double
        public var percentageLabel: String
        public var detail: String

        public init(
            id: String,
            label: String,
            axisLabel: String? = nil,
            weight: Double,
            percentageLabel: String,
            detail: String
        ) {
            self.id = id
            self.label = label
            self.axisLabel = axisLabel
            self.weight = weight
            self.percentageLabel = percentageLabel
            self.detail = detail
        }
    }
}

public struct MenuRow: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var accessibilityIdentifier: String
    public var actionTarget: MenuRowActionTarget?
    public var title: String
    public var detail: String?
    public var barChart: MenuRowBarChart?
    public var actionPayload: String?
    public var children: [MenuRow]

    public init(
        id: String = "",
        role: MenuRowRole = .row,
        accessibilityIdentifier: String? = nil,
        actionTarget: MenuRowActionTarget? = nil,
        title: String,
        detail: String? = nil,
        barChart: MenuRowBarChart? = nil,
        actionPayload: String? = nil,
        children: [MenuRow] = []
    ) {
        self.id = id
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier ?? Self.defaultAccessibilityIdentifier(for: id)
        self.actionTarget = actionTarget
        self.title = title
        self.detail = detail
        self.barChart = barChart
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
        case barChart
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
        barChart = try container.decodeIfPresent(MenuRowBarChart.self, forKey: .barChart)
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
    public var detail: String?
    public var accessibilityIdentifier: String
    public var actionTarget: MenuRowActionTarget?
    public var barChart: MenuRowBarChart?
    public var actionPayload: String?
    public var children: [MenuBarRowSurface]

    public init(
        id: String,
        role: MenuRowRole,
        title: String,
        detail: String? = nil,
        accessibilityIdentifier: String,
        actionTarget: MenuRowActionTarget? = nil,
        barChart: MenuRowBarChart? = nil,
        actionPayload: String? = nil,
        children: [MenuBarRowSurface] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.detail = detail
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actionTarget = actionTarget
        self.barChart = barChart
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
    public var claudeLoginBinaryOverride: String?

    public init(
        mode: PDTBarLaunchMode,
        snapshotDirectory: URL? = nil,
        appSupportDirectory: URL? = nil,
        claudeLoginBinaryOverride: String? = nil
    ) {
        self.mode = mode
        self.snapshotDirectory = snapshotDirectory
        self.appSupportDirectory = appSupportDirectory
        self.claudeLoginBinaryOverride = claudeLoginBinaryOverride
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
        var claudeLoginBinaryOverride: String?
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
            case "--scripted-claude-login-bin" where index + 1 < arguments.count:
                claudeLoginBinaryOverride = arguments[index + 1]
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
                appSupportDirectory: appSupportDirectory,
                claudeLoginBinaryOverride: claudeLoginBinaryOverride
            )
        }

        guard snapshotDirectory == nil else {
            throw PDTBarLaunchOptionError.usage
        }
        return PDTBarLaunchOptions(
            mode: .claudeFirst,
            appSupportDirectory: appSupportDirectory,
            claudeLoginBinaryOverride: claudeLoginBinaryOverride
        )
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
                    cachedPulseWithRuntimeHealth(
                        cachedPulse,
                        claudeReadiness: .checking,
                        pdtMCPReadiness: .unknown,
                        detailFill: .notStarted
                    ),
                    rowsFirst: true,
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
                    cachedPulseWithRuntimeHealth(
                        cachedPulse,
                        detailFill: .inProgress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
                    ).withRefreshAction(.inProgress),
                    rowsFirst: true,
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
        var descriptor = cachedPulse.withRefreshAction(.available)
        var addedRefreshAction = false
        descriptor.sections = descriptor.sections.map { section in
            guard section.id == "freshness" else {
                return section
            }
            var section = section
            section.rows = section.rows.map { row in
                guard row.id == "freshness.summary" else {
                    return row
                }
                var row = row
                if !row.children.contains(where: { $0.id == "freshness.refreshDetails" }) {
                    row.children.append(Self.refreshDetailsRow())
                }
                addedRefreshAction = true
                return row
            }
            return section
        }
        guard addedRefreshAction else {
            return cachedPulseDescriptor(
                cachedPulse.withRefreshAction(.available),
                rows: [refreshDetailsRow(id: "portfolioFetch.refreshDetails")]
            )
        }
        return descriptor
    }

    public static func descriptorForBackgroundRefreshFailure(
        cachedPulse: MenuDescriptor,
        diagnostic: PDTDetailRefreshFailureDiagnostic? = nil
    ) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulseWithRuntimeHealth(cachedPulse, detailFill: .failed, diagnostic: diagnostic, clearsDiagnostic: true)
                .withRefreshAction(.available),
            statusVisual: cachedPulse.statusVisual.withDimming(true),
            rowsFirst: true,
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
            cachedPulseWithRuntimeHealth(cachedPulse, detailFill: .inProgress(progress))
                .withRefreshAction(.inProgress),
            rowsFirst: true,
            rows: backgroundDetailProgressRows(progress)
        )
    }

    public static func descriptorForBackgroundDetailDegraded(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulseWithRuntimeHealth(cachedPulse, detailFill: .degraded)
                .withRefreshAction(.available),
            statusVisual: cachedPulse.statusVisual.withDimming(true),
            rowsFirst: true,
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
        rowsFirst: Bool = false,
        rows: [MenuRow]
    ) -> MenuDescriptor {
        let fetchSection = MenuSection(
            id: "portfolioFetch",
            title: "Portfolio",
            rows: rows
        )
        return MenuDescriptor(
            statusTitle: cachedPulse.statusTitle,
            statusBadge: cachedPulse.statusBadge,
            statusVisual: statusVisual ?? cachedPulse.statusVisual,
            statusAccessibilityIdentifier: cachedPulse.statusAccessibilityIdentifier,
            sections: rowsFirst ? [fetchSection] + cachedPulse.sections : cachedPulse.sections + [fetchSection]
        )
    }

    private static func cachedPulseWithRuntimeHealth(
        _ cachedPulse: MenuDescriptor,
        claudeReadiness: DataHealthSourceStatus = .ready,
        pdtMCPReadiness: DataHealthSourceStatus = .ready,
        detailFill: DataHealthDetailFillInput,
        diagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        clearsDiagnostic: Bool = false
    ) -> MenuDescriptor {
        var descriptor = cachedPulse
        let sourceDetail = runtimeDataHealthSourceDetail(claudeReadiness: claudeReadiness, pdtMCPReadiness: pdtMCPReadiness)
        let detailFillDetail = runtimeDataHealthDetailFillDetail(detailFill)
        let summaryDetail = runtimeDataHealthSummaryDetail(
            detailFill,
            claudeReadiness: claudeReadiness,
            pdtMCPReadiness: pdtMCPReadiness
        )
        let diagnosticRow = runtimeDataHealthDiagnosticRow(for: diagnostic)
            ?? (clearsDiagnostic ? MenuDescriptorRenderer.dataHealthDiagnosticRow(for: nil) : nil)

        descriptor.sections = descriptor.sections.map { section in
            guard section.id == "freshness" else {
                return section
            }
            var section = section
            section.rows = section.rows.map { row in
                guard row.id == "dataHealth" else {
                    return row
                }
                var row = row
                if let summaryDetail {
                    row.detail = summaryDetail
                }
                row.children = row.children.map { child in
                    var child = child
                    if child.id == "dataHealth.source", let sourceDetail {
                        child.detail = sourceDetail
                    } else if child.id == "dataHealth.detailFill" {
                        child.detail = detailFillDetail
                    } else if child.id == "dataHealth.diagnostic", let diagnosticRow {
                        child = diagnosticRow
                    }
                    return child
                }
                return row
            }
            return section
        }
        return descriptor
    }

    private static func runtimeDataHealthDiagnosticRow(
        for diagnostic: PDTDetailRefreshFailureDiagnostic?
    ) -> MenuRow? {
        guard let diagnostic else {
            return nil
        }
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: Set(PDTReadTools.requiredV1),
                readOnlyPolicy: .enforced,
                pulseSource: .cachedSnapshot,
                lastSuccessfulCompleteFetchAsOf: nil,
                cachedPulseAvailable: true,
                detailFill: .failed,
                freshness: FreshnessSnapshot(worstPriceAsOf: nil, stale: false),
                readState: nil,
                diagnostic: diagnostic
            )
        )
        return MenuDescriptorRenderer.dataHealthDiagnosticRow(for: health.diagnostic)
    }

    private static func runtimeDataHealthSourceDetail(
        claudeReadiness: DataHealthSourceStatus,
        pdtMCPReadiness: DataHealthSourceStatus
    ) -> String? {
        guard claudeReadiness != .ready || pdtMCPReadiness != .ready else {
            return nil
        }
        return DataHealth.build(
            DataHealthInput(
                claudeReadiness: claudeReadiness,
                pdtMCPReadiness: pdtMCPReadiness,
                availableReadTools: Set(PDTReadTools.requiredV1),
                readOnlyPolicy: .enforced,
                pulseSource: .cachedSnapshot,
                lastSuccessfulCompleteFetchAsOf: nil,
                cachedPulseAvailable: true,
                detailFill: .notStarted,
                freshness: FreshnessSnapshot(worstPriceAsOf: nil, stale: false),
                readState: nil
            )
        ).source.detail
    }

    private static func runtimeDataHealthDetailFillDetail(_ detailFill: DataHealthDetailFillInput) -> String {
        switch detailFill {
        case .notStarted:
            return "Not started"
        case .completed(let asOf):
            return asOf.map { "Completed \($0)" } ?? "Completed"
        case .degraded:
            return "Degraded"
        case .failed:
            return "Failed"
        case .inProgress(let progress):
            if let completed = progress.completedUnitCount,
               let total = progress.totalUnitCount
            {
                return "\(progress.phase.title) \(max(0, completed))/\(max(0, total))"
            }
            return progress.phase.title
        }
    }

    private static func runtimeDataHealthSummaryDetail(
        _ detailFill: DataHealthDetailFillInput,
        claudeReadiness: DataHealthSourceStatus,
        pdtMCPReadiness: DataHealthSourceStatus
    ) -> String? {
        if claudeReadiness == .checking || pdtMCPReadiness == .checking {
            return "Checking"
        }
        if claudeReadiness != .ready || pdtMCPReadiness != .ready {
            return "Needs attention"
        }
        switch detailFill {
        case .degraded, .failed:
            return "Needs attention"
        case .inProgress:
            return "Refreshing"
        case .completed, .notStarted:
            return nil
        }
    }

    private static func refreshDetailsRow(id: String = "freshness.refreshDetails") -> MenuRow {
        MenuRow(
            id: id,
            role: .fetchRetry,
            title: "Refresh details",
            detail: "Fill income and detail data"
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

private extension MenuDescriptor {
    func withRefreshAction(_ state: MenuRefreshActionState) -> MenuDescriptor {
        MenuDescriptorRenderer.descriptorWithTopLevelActions(self, refreshState: state)
    }
}

public enum PDTOnboardingEffect: Equatable {
    case none
    case probeReadiness
    case startLoginHandoff
    case startFirstFetch
    case startBackgroundDetailRefresh
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

public enum PDTLaunchFetchResult: Equatable {
    case succeeded(PulseLifecycleResult)
    case failed(String)
}

public enum PDTLaunchBackgroundDetailRefreshResult: Equatable {
    case succeeded(PulseLifecycleResult, outcome: PDTBackgroundDetailRefreshOutcome)
    case failed(String, diagnostic: PDTDetailRefreshFailureDiagnostic? = nil)
}

public final class PDTLaunchRuntime {
    public private(set) var currentPulse: PulseLifecycleResult?
    public private(set) var state: ClaudeLaunchState = .probingClaude
    public private(set) var readinessProbeInFlight = false
    public private(set) var readinessAttemptID = 0
    public private(set) var firstFetchInFlight = false
    public private(set) var backgroundDetailRefreshInFlight = false
    private var lastDescriptor: MenuDescriptor?

    public init() {}

    public func launch(cachedPulse: PulseLifecycleResult?) -> PDTOnboardingUpdate {
        currentPulse = cachedPulse
        return beginReadinessProbe()
    }

    public func retryReadiness() -> PDTOnboardingUpdate? {
        guard !readinessProbeInFlight else {
            return nil
        }
        return beginReadinessProbe()
    }

    public func completeReadinessProbe(
        _ result: ClaudeReadinessProbeResult,
        attemptID: Int? = nil,
        allowsBackgroundDetailRefresh: Bool = true
    ) -> PDTOnboardingUpdate {
        if let attemptID, attemptID != readinessAttemptID {
            return currentUpdate()
        }
        readinessProbeInFlight = false
        let nextState = ClaudeLaunchFlow.state(afterReadinessProbe: result)
        if nextState == .fetchingPortfolio {
            guard !firstFetchInFlight, !backgroundDetailRefreshInFlight else {
                return currentUpdate()
            }
            if let currentPulse, allowsBackgroundDetailRefresh {
                return startBackgroundDetailRefresh(with: currentPulse)
            }
            firstFetchInFlight = true
            return update(state: nextState, effect: .startFirstFetch)
        }
        return update(state: nextState)
    }

    public func beginLoginHandoff() -> PDTOnboardingUpdate {
        update(state: .openingClaude, effect: .startLoginHandoff)
    }

    public func completeLoginHandoff(_ result: PDTOnboardingLoginResult) -> PDTOnboardingUpdate {
        switch result {
        case .succeeded:
            return beginReadinessProbe()
        case .failed(let reason):
            state = .missingClaude
            let descriptor = ClaudeLaunchFlow.descriptor(forLoginFailure: reason)
            lastDescriptor = descriptor
            return PDTOnboardingUpdate(
                state: state,
                descriptor: descriptor
            )
        }
    }

    public func retryFirstFetch() -> PDTOnboardingUpdate? {
        guard !firstFetchInFlight, !backgroundDetailRefreshInFlight else {
            return nil
        }
        if let currentPulse {
            return startBackgroundDetailRefresh(with: currentPulse)
        }
        firstFetchInFlight = true
        return update(state: .fetchingPortfolio, effect: .startFirstFetch)
    }

    public func firstFetchProgress(fetchingElapsedSeconds: Int) -> PDTOnboardingUpdate? {
        guard firstFetchInFlight else {
            return nil
        }
        return update(state: .fetchingPortfolio, fetchingElapsedSeconds: fetchingElapsedSeconds)
    }

    public func completeFirstFetch(_ result: PDTLaunchFetchResult) -> PDTOnboardingUpdate {
        firstFetchInFlight = false
        switch result {
        case .succeeded(let pulse):
            return publishPulse(pulse)
        case .failed:
            return update(state: .portfolioFetchFailed)
        }
    }

    public func beginBackgroundDetailRefresh() -> PDTOnboardingUpdate? {
        guard let currentPulse, !firstFetchInFlight, !backgroundDetailRefreshInFlight else {
            return nil
        }
        return startBackgroundDetailRefresh(with: currentPulse)
    }

    public func backgroundDetailRefreshProgress(_ progress: BackgroundDetailRefreshProgress) -> PDTOnboardingUpdate? {
        guard backgroundDetailRefreshInFlight, let pulse = currentPulse else {
            return nil
        }
        state = .fetchingPortfolio
        let descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: pulse.descriptor,
            progress: progress
        )
        lastDescriptor = descriptor
        return PDTOnboardingUpdate(
            state: state,
            descriptor: descriptor
        )
    }

    public func completeBackgroundDetailRefresh(
        _ result: PDTLaunchBackgroundDetailRefreshResult
    ) -> PDTOnboardingUpdate {
        backgroundDetailRefreshInFlight = false
        switch result {
        case let .succeeded(pulse, outcome):
            currentPulse = pulse
            state = .fetchingPortfolio
            let descriptor: MenuDescriptor
            if outcome == .degraded {
                descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: pulse.descriptor)
            } else {
                descriptor = ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: pulse.descriptor)
            }
            lastDescriptor = descriptor
            return PDTOnboardingUpdate(
                state: state,
                descriptor: descriptor
            )
        case .failed(_, let diagnostic):
            guard let pulse = currentPulse else {
                return update(state: .portfolioFetchFailed)
            }
            state = .portfolioFetchFailed
            let descriptor = ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(
                cachedPulse: pulse.descriptor,
                diagnostic: diagnostic
            )
            lastDescriptor = descriptor
            return PDTOnboardingUpdate(
                state: state,
                descriptor: descriptor
            )
        }
    }

    public func replaceCurrentPulse(_ pulse: PulseLifecycleResult) {
        currentPulse = pulse
    }

    public func publishPulse(_ pulse: PulseLifecycleResult) -> PDTOnboardingUpdate {
        backgroundDetailRefreshInFlight = false
        currentPulse = pulse
        state = .fetchingPortfolio
        let descriptor = ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: pulse.descriptor)
        lastDescriptor = descriptor
        return PDTOnboardingUpdate(
            state: state,
            descriptor: descriptor
        )
    }

    private func beginReadinessProbe() -> PDTOnboardingUpdate {
        readinessAttemptID += 1
        readinessProbeInFlight = true
        return update(state: .probingClaude, effect: .probeReadiness)
    }

    private func startBackgroundDetailRefresh(with pulse: PulseLifecycleResult) -> PDTOnboardingUpdate {
        firstFetchInFlight = false
        backgroundDetailRefreshInFlight = true
        state = .fetchingPortfolio
        let descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: pulse.descriptor,
            progress: BackgroundDetailRefreshProgress(phase: .baseHoldings)
        )
        lastDescriptor = descriptor
        return PDTOnboardingUpdate(
            state: state,
            descriptor: descriptor,
            effect: .startBackgroundDetailRefresh
        )
    }

    private func update(
        state: ClaudeLaunchState,
        effect: PDTOnboardingEffect = .none,
        fetchingElapsedSeconds: Int? = nil
    ) -> PDTOnboardingUpdate {
        self.state = state
        let descriptor = ClaudeLaunchFlow.descriptor(
            for: state,
            cachedPulse: currentPulse?.descriptor,
            fetchingElapsedSeconds: fetchingElapsedSeconds
        )
        lastDescriptor = descriptor
        return PDTOnboardingUpdate(
            state: state,
            descriptor: descriptor,
            effect: effect
        )
    }

    private func currentUpdate() -> PDTOnboardingUpdate {
        if let lastDescriptor {
            return PDTOnboardingUpdate(
                state: state,
                descriptor: lastDescriptor
            )
        }
        return update(state: state)
    }
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
        case .startBackgroundDetailRefresh:
            return
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
            title: row.title,
            detail: row.detail,
            accessibilityIdentifier: row.accessibilityIdentifier,
            actionTarget: row.actionTarget,
            barChart: row.barChart,
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
        let freshness = model.facetSnapshots.freshness
        let dataHealth = model.facetSnapshots.dataHealth

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
                        model.facetSnapshots.allocation.portfolioOverview.topNConcentration.map {
                            MenuRow(
                                id: "pulse.quiet.topAllocation",
                                title: "Top \($0.rankCount)",
                                detail: percent($0.weight)
                            )
                        },
                        MenuRow(
                            id: "pulse.quiet.freshness",
                            title: "Latest prices",
                            detail: model.portfolioGlance.worstPriceAsOf ?? "Unknown"
                        ),
                    ].compactMap { $0 }
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
                    rows: [
                        portfolioOverviewChartRow(for: allocation.portfolioOverview),
                        portfolioOverviewDetailsRow(for: allocation, model: model),
                    ] + allocationPressureRows(for: allocation)
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
                        freshnessSummaryRow(for: freshness),
                        dataHealthRow(for: dataHealth),
                    ]
                ),
                topLevelActionsSection(refreshState: .available),
            ]
        )
    }

    static func descriptorWithTopLevelActions(
        _ descriptor: MenuDescriptor,
        refreshState: MenuRefreshActionState
    ) -> MenuDescriptor {
        var descriptor = descriptor
        let actions = topLevelActionsSection(refreshState: refreshState)
        if let index = descriptor.sections.firstIndex(where: { $0.id == actions.id }) {
            descriptor.sections[index] = actions
        } else {
            descriptor.sections.append(actions)
        }
        return descriptor
    }

    private static func topLevelActionsSection(refreshState: MenuRefreshActionState) -> MenuSection {
        MenuSection(
            id: "actions",
            title: "Actions",
            rows: [
                refreshActionRow(state: refreshState),
                MenuRow(
                    id: "actions.openPDT",
                    role: .openPDT,
                    title: "Open PDT"
                ),
            ]
        )
    }

    private static func refreshActionRow(state: MenuRefreshActionState) -> MenuRow {
        switch state {
        case .available:
            return MenuRow(
                id: "actions.refreshNow",
                role: .fetchRetry,
                title: "Refresh now",
                detail: "Fill latest details"
            )
        case .inProgress:
            return MenuRow(
                id: "actions.refreshNow",
                role: .fetchStatus,
                title: "Refreshing now",
                detail: "Already in progress"
            )
        }
    }

    private static func portfolioOverviewChildren(for overview: PortfolioOverviewSummary) -> [MenuRow] {
        [
            portfolioOverviewHoldingsRow(for: overview),
            portfolioOverviewConcentrationRow(for: overview),
            portfolioOverviewDistributionRow(
                id: "allocation.portfolio.sectors",
                role: .portfolioOverviewSector,
                title: "Sectors",
                summaries: overview.sectorSummary
            ),
            portfolioOverviewDistributionRow(
                id: "allocation.portfolio.assetTypes",
                role: .portfolioOverviewAssetType,
                title: "Asset types",
                summaries: overview.assetTypeSummary
            ),
            overview.cashSummary.map(portfolioOverviewCashRow),
        ].compactMap { $0 }
    }

    private static func portfolioOverviewChartRow(for overview: PortfolioOverviewSummary) -> MenuRow {
        return MenuRow(
            id: "allocation.portfolio",
            role: .portfolioOverviewChart,
            title: "Portfolio",
            barChart: portfolioOverviewBarChart(for: overview)
        )
    }

    private static func portfolioOverviewDetailsRow(
        for allocation: AllocationSnapshot,
        model: PortfolioPulseModel
    ) -> MenuRow {
        let overview = allocation.portfolioOverview
        return MenuRow(
            id: "allocation.portfolio.details",
            role: .portfolioOverviewDetails,
            title: "Detailed info",
            detail: "Full allocation list",
            children: portfolioOverviewChildren(for: overview) + allocationHoldingRows(
                for: allocation.topHoldings,
                model: model
            )
        )
    }

    private static func portfolioOverviewBarChart(for overview: PortfolioOverviewSummary) -> MenuRowBarChart? {
        let bars = overview.topHoldings.map { holding in
            MenuRowBarChart.Bar(
                id: "allocation.portfolio.chart.\(holding.quoteId)",
                label: holdingChartLabel(holding),
                axisLabel: holdingChartAxisLabel(holding),
                weight: holding.weight,
                percentageLabel: percent(holding.weight),
                detail: "\(holding.name) \(percent(holding.weight)); \(display(holding.worth))"
            )
        }
        guard !bars.isEmpty else {
            return nil
        }
        return MenuRowBarChart(bars: Array(bars))
    }

    private static func allocationHoldingRows(
        for holdings: [HoldingSummary],
        model: PortfolioPulseModel
    ) -> [MenuRow] {
        holdings.map { holding in
            let attention = model.rankedAttentionItems.first { item in
                item.facet == "allocation" && item.holdingIdentity?.quoteId == holding.quoteId
            }
            let drillDownDetail = attention?.explanation.currentValue?.value
            return MenuRow(
                id: "allocation.\(holding.quoteId)",
                role: drillDownDetail == nil ? .allocationHolding : .allocationDrillDown,
                title: holding.name,
                detail: drillDownDetail ?? percent(holding.weight),
                children: allocationChildren(for: holding, attention: attention)
            )
        }
    }

    private static func allocationPressureRows(for allocation: AllocationSnapshot) -> [MenuRow] {
        allocation.allocationPressureItems.map { item in
            MenuRow(
                id: "\(item.id).allocation",
                role: .allocationDrillDown,
                title: item.title,
                detail: item.detail,
                children: explanationRows(for: item.explanation, itemID: "\(item.id).allocation")
            )
        }
    }

    private static func holdingChartLabel(_ holding: HoldingSummary) -> String {
        if let copyableIdentifier = holding.copyableIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !copyableIdentifier.isEmpty
        {
            return copyableIdentifier
        }
        if let shortName = shortHoldingName(holding.name) {
            return shortName
        }
        return "\(holding.quoteId)"
    }

    private static func shortHoldingName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "/,("))
        guard let token = trimmed
            .components(separatedBy: separators)
            .map({ $0.trimmingCharacters(in: .punctuationCharacters) })
            .first(where: { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil })
        else {
            return nil
        }
        return String(token.prefix(12))
    }

    private static func holdingChartAxisLabel(_ holding: HoldingSummary) -> String {
        let publicLabel = holdingChartLabel(holding)
        if let first = publicLabel.first(where: { $0.isLetter }) {
            return String(first).uppercased()
        }
        if let first = holding.name.first(where: { $0.isLetter }) {
            return String(first).uppercased()
        }
        if let first = publicLabel.first(where: { $0.isNumber }) ?? holding.name.first(where: { $0.isNumber }) {
            return String(first)
        }
        return "?"
    }

    private static func portfolioOverviewHoldingsRow(for overview: PortfolioOverviewSummary) -> MenuRow {
        let topRows = overview.topHoldings.prefix(PortfolioOverview.topHoldingLimit).map {
            MenuRow(
                id: "allocation.portfolio.holdings.\($0.quoteId)",
                role: .allocationHolding,
                title: $0.name,
                detail: "\(percent($0.weight)); \(display($0.worth))"
            )
        }
        let topHolding = overview.topHoldings.first.map { "top \($0.name) \(percent($0.weight))" }
        return MenuRow(
            id: "allocation.portfolio.holdings",
            role: .portfolioOverviewHoldings,
            title: "Holdings",
            detail: (["\(overview.openHoldingCount) open"] + [topHolding].compactMap { $0 }).joined(separator: "; "),
            children: Array(topRows)
        )
    }

    private static func portfolioOverviewConcentrationRow(for overview: PortfolioOverviewSummary) -> MenuRow? {
        guard let concentration = overview.topNConcentration else {
            return nil
        }
        return MenuRow(
            id: "allocation.portfolio.concentration",
            role: .portfolioOverviewConcentration,
            title: "Top \(concentration.rankCount) concentration",
            detail: percent(concentration.weight)
        )
    }

    private static func portfolioOverviewDistributionRow(
        id: String,
        role: MenuRowRole,
        title: String,
        summaries: [DistributionSummary]
    ) -> MenuRow? {
        guard let first = summaries.first else {
            return nil
        }
        let rows = summaries.prefix(PortfolioOverview.topHoldingLimit).map {
            MenuRow(
                id: "\(id).\(stableIDToken($0.name))",
                role: role,
                title: distributionLabel($0.name),
                detail: "\(percent($0.percentage / 100.0)); \(display($0.totalValue))"
            )
        }
        return MenuRow(
            id: id,
            role: role,
            title: title,
            detail: "\(distributionLabel(first.name)) \(percent(first.percentage / 100.0))",
            children: Array(rows)
        )
    }

    private static func portfolioOverviewCashRow(_ cash: PortfolioCashSummary) -> MenuRow {
        MenuRow(
            id: "allocation.portfolio.cash",
            role: .portfolioOverviewCash,
            title: "Cash",
            detail: "\(display(cash.value)); \(percent(cash.weight))"
        )
    }

    private static func freshnessSummaryRow(for freshness: FreshnessSnapshot) -> MenuRow {
        MenuRow(
            id: "freshness.summary",
            role: .freshnessSummary,
            title: "Status",
            detail: freshnessSummaryDetail(for: freshness),
            children: freshnessDetailRows(for: freshness)
        )
    }

    static func dataHealthRow(for health: DataHealthSnapshot) -> MenuRow {
        MenuRow(
            id: "dataHealth",
            role: .dataHealthSummary,
            title: "Data health",
            detail: dataHealthSummaryDetail(for: health),
            children: dataHealthRows(for: health)
        )
    }

    static func descriptorByReplacingDataHealth(
        in descriptor: MenuDescriptor,
        with health: DataHealthSnapshot
    ) -> MenuDescriptor {
        var descriptor = descriptor
        let replacement = dataHealthRow(for: health)
        var replaced = false
        descriptor.sections = descriptor.sections.map { section in
            guard section.id == "freshness" else {
                return section
            }
            var section = section
            section.rows = section.rows.map { row in
                guard row.id == "dataHealth" else {
                    return row
                }
                replaced = true
                return replacement
            }
            if !replaced {
                section.rows.append(replacement)
            }
            return section
        }
        return descriptor
    }

    private static func dataHealthRows(for health: DataHealthSnapshot) -> [MenuRow] {
        [
            MenuRow(
                id: "dataHealth.source",
                role: .dataHealthSource,
                title: "Source",
                detail: health.source.detail
            ),
            MenuRow(
                id: "dataHealth.cache",
                role: .dataHealthCache,
                title: "Cache",
                detail: health.cache.summary
            ),
            MenuRow(
                id: "dataHealth.detailFill",
                role: .dataHealthDetailFill,
                title: "Detail fill",
                detail: health.detailFill.detail
            ),
            MenuRow(
                id: "dataHealth.readState",
                role: .dataHealthReadState,
                title: "Read state",
                detail: health.readState.detail
            ),
            dataHealthDiagnosticRow(for: health.diagnostic),
        ]
    }

    static func dataHealthDiagnosticRow(for diagnostic: DataHealthDiagnosticSummary?) -> MenuRow {
        guard let diagnostic else {
            return MenuRow(
                id: "dataHealth.diagnostic",
                role: .dataHealthDiagnostic,
                title: "Diagnostics",
                detail: "None recorded"
            )
        }
        return MenuRow(
            id: "dataHealth.diagnostic",
            role: .dataHealthDiagnostic,
            title: "Diagnostics",
            detail: diagnostic.detail,
            children: [
                MenuRow(
                    id: "dataHealth.diagnostic.copy",
                    role: .dataHealthDiagnosticCopy,
                    actionTarget: MenuRowActionTarget(
                        kind: .copyDataHealthDiagnostic,
                        id: "dataHealth.diagnostic.copy",
                        copyText: diagnostic.copyText
                    ),
                    title: "Copy diagnostics",
                    detail: "Redacted"
                ),
            ]
        )
    }

    private static func dataHealthSummaryDetail(for health: DataHealthSnapshot) -> String {
        switch health.status {
        case .healthy:
            return "Healthy"
        case .degraded:
            return "Needs attention"
        }
    }

    private static func freshnessDetailRows(for freshness: FreshnessSnapshot) -> [MenuRow] {
        [
            MenuRow(
                id: "freshness.staleCount",
                role: .freshnessStaleCount,
                title: "Stale holdings",
                detail: "\(freshness.staleHoldingCount)"
            ),
            MenuRow(
                id: "freshness.oldestPrice",
                role: .freshnessOldestPrice,
                title: "Oldest price",
                detail: freshness.oldestPriceAsOf ?? "Unknown"
            ),
            freshness.oldestRows.isEmpty ? nil : MenuRow(
                id: "freshness.oldestRows",
                role: .freshnessOldestRows,
                title: "Oldest rows",
                detail: freshness.oldestRows.count == 1 ? "1 holding" : "\(freshness.oldestRows.count) holdings",
                children: freshness.oldestRows.map {
                    MenuRow(
                        id: "freshness.oldestRows.\($0.quoteId)",
                        role: .freshnessOldestHolding,
                        title: $0.name,
                        detail: $0.priceAsOf
                    )
                }
            ),
            MenuRow(
                id: "freshness.detailFill",
                role: .freshnessDetailFill,
                title: "Latest complete detail fill",
                detail: freshness.latestCompleteDetailFillAsOf ?? "Not recorded"
            ),
        ].compactMap { $0 }
    }

    private static func freshnessSummaryDetail(for freshness: FreshnessSnapshot) -> String {
        switch freshness.status {
        case .fresh:
            return "Fresh"
        case .stale:
            let oldest = freshness.oldestPriceAsOf.map { "; oldest \($0)" } ?? ""
            return "\(freshness.staleHoldingCount) stale\(oldest)"
        case .partial:
            return freshness.oldestPriceAsOf.map { "Partial; oldest \($0)" } ?? "Partial"
        case .unknown:
            return "Unknown price dates"
        }
    }

    private static func statusVisual(for model: PortfolioPulseModel) -> StatusVisualState {
        StatusVisualState(
            barHeights: concentrationBarHeights(from: model.facetSnapshots.allocation),
            filledBarCount: model.rankedAttentionItems.count,
            isDimmed: model.facetSnapshots.freshness.status != .fresh
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
        var rows = explanationRows(for: item.explanation, itemID: item.id)
        if let sources = sourceSlotsDetail(for: item, supportingDataSlots: supportingDataSlots) {
            rows.append(
                MenuRow(
                    id: "\(item.id).sources",
                    role: .pulseAttentionExpansion,
                    title: "Sources",
                    detail: sources
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

    private static func explanationRows(for explanation: AttentionExplanation, itemID: String) -> [MenuRow] {
        [
            ("trigger", explanation.trigger),
            ("severity", explanation.severity),
            ("threshold", explanation.threshold),
            ("currentValue", explanation.currentValue),
            ("priorValue", explanation.priorValue),
        ].compactMap { suffix, fact in
            guard let fact else { return nil }
            return MenuRow(
                id: "\(itemID).\(suffix)",
                role: .pulseAttentionExpansion,
                title: fact.label,
                detail: factDetail(fact)
            )
        }
    }

    private static func factDetail(_ fact: AttentionExplanationFact) -> String {
        if fact.key == "severity",
           let score = fact.numericValue
        {
            return "\(fact.value); score \(decimalString(String(score), places: 2))"
        }
        return fact.value
    }

    private static func sourceSlotsDetail(
        for item: AttentionItem,
        supportingDataSlots: [SupportingDataSlot]
    ) -> String? {
        let labelsByID = supportingDataSlots.reduce(into: [String: String]()) { labelsByID, slot in
            labelsByID[slot.id] = slot.label
        }
        let explanationSlots = item.explanation.supportingSourceSlots
        let slots = explanationSlots.isEmpty
            ? item.supportingDataSlotIDs.map { AttentionExplanationSourceSlot(id: $0) }
            : explanationSlots
        let labels = slots.map { slot in
            slot.label ?? labelsByID[slot.id] ?? slot.id
        }
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
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
        if let isin = holding.isin {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).isin",
                    title: "ISIN",
                    detail: isin
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
        if let threshold = attention?.explanation.threshold {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).line",
                    title: threshold.label,
                    detail: threshold.value
                )
            )
        }
        return rows
    }

}

enum MenuRefreshActionState {
    case available
    case inProgress
}

public enum PressureEngine {
    public static let concentrationThreshold = 0.20
    public static let sectorConcentrationThreshold = 0.30
    public static let cashDragThreshold = 0.10
    public static let concentrationDriftThreshold = 0.05
    public static let bigMoverThreshold = 0.10

    public static func buildModel(
        from snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot? = nil,
        readState: PulseReadState? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil
    ) -> PortfolioPulseModel {
        let portfolioOverview = PortfolioOverview.build(from: snapshot)
        let priorPortfolioOverview = priorSnapshot.map(PortfolioOverview.build)
        let allocationItems = ranked(
            concentrationItems(from: snapshot, priorSnapshot: priorSnapshot, readState: readState)
                + sectorConcentrationItems(from: portfolioOverview)
                + cashDragItems(from: portfolioOverview)
                + concentrationDriftItems(from: portfolioOverview, priorOverview: priorPortfolioOverview)
        )
        let rankedItems = ranked(
            allocationItems
                + incomeItems(from: snapshot)
                + bigMoverItems(from: snapshot, priorSnapshot: priorSnapshot)
        )
        let totalValue = snapshot.totalValue
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        let freshness = FreshnessLedger.build(from: snapshot, detailRefreshOutcome: effectiveDetailRefreshOutcome)
        let recentMovesByQuoteID = recentMoves(from: snapshot.priceSeries)
        let nextIncomeEventsByQuoteID = nextIncomeEventsByQuoteID(from: snapshot)
        let topHoldingSummaries = snapshot.openHoldings
            .sorted(by: ranksByAllocation)
            .map {
                HoldingSummary(
                    name: $0.name,
                    quoteId: $0.quoteId,
                    weight: $0.weight,
                    worth: $0.worth,
                    price: validMoney($0.price),
                    copyableIdentifier: $0.copyableIdentifier,
                    isin: $0.isin,
                    recentMove: recentMovesByQuoteID[$0.quoteId],
                    nextIncomeEvent: nextIncomeEventsByQuoteID[$0.quoteId],
                    averageBuyPrice: $0.averageBuyPrice,
                    gainLoss: $0.gainLoss,
                    gainLossPercentage: $0.gainLossPercentage
                )
            }
        var supportingDataSlots = [
            SupportingDataSlot(
                id: "allocation.overview",
                facet: "allocation",
                label: "Portfolio overview",
                itemCount: portfolioOverview.openHoldingCount
            ),
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
            supportingDataSlots.append(
                SupportingDataSlot(
                    id: "allocation.priorSnapshot",
                    facet: "allocation",
                    label: "Prior allocation snapshot",
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
                worstPriceAsOf: freshness.worstPriceAsOf,
                priorSnapshotAsOf: priorSnapshot?.asOf
            ),
            facetSnapshots: FacetSnapshots(
                allocation: AllocationSnapshot(
                    totalValue: totalValue,
                    openHoldingCount: snapshot.openHoldings.count,
                    topHoldings: topHoldingSummaries,
                    sectorBreakdown: snapshot.sectors,
                    assetTypeBreakdown: snapshot.assetTypes,
                    xRayHoldings: snapshot.xRayHoldings,
                    portfolioOverview: portfolioOverview,
                    allocationPressureItems: allocationItems
                ),
                income: IncomeSnapshot(
                    upcomingEvents: snapshot.incomeEvents.sorted { $0.date < $1.date },
                    dividendRowCount: snapshot.dividendRowCount
                ),
                bigMovers: BigMoversSnapshot(
                    priceSeriesCount: snapshot.priceSeries.count,
                    maxMove: maxMove(from: snapshot.priceSeries)
                ),
                freshness: freshness,
                dataHealth: DataHealth.build(
                    DataHealthInput.default(
                        freshness: freshness,
                        readState: readState,
                        detailRefreshOutcome: effectiveDetailRefreshOutcome
                    )
                )
            ),
            supportingDataSlots: supportingDataSlots
        )
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

    private static func dayDate(from value: String) -> Date? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return dateCalendar.date(
            from: DateComponents(
                calendar: dateCalendar,
                timeZone: dateCalendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }

    private static var dateCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
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
                var itemWithPrior = item
                itemWithPrior.explanation.priorValue = AttentionExplanationFact(
                    key: "priorValue",
                    label: "Prior",
                    value: percent(priorWeight),
                    numericValue: priorWeight,
                    unit: "fraction"
                )
                if priorWeight < concentrationThreshold {
                    var freshItem = itemWithPrior
                    freshItem.resetsReadState = true
                    return freshItem
                }
                guard let prefix = itemWithPrior.concentrationReadFingerprintPrefix else {
                    return nil
                }
                let changedReadFingerprintExists = readFingerprints.contains { fingerprint in
                    fingerprint.hasPrefix(prefix) && fingerprint != itemWithPrior.readFingerprint
                }
                return changedReadFingerprintExists ? itemWithPrior : nil
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
                    supportingDataSlotIDs: ["allocation.holdings"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Concentration line crossed"
                        ),
                        severity: explanationSeverity(
                            severity: score >= 0.8 ? "high" : "medium",
                            score: score
                        ),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: percent(concentrationThreshold),
                            numericValue: concentrationThreshold,
                            unit: "fraction"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: percent(holding.weight),
                            numericValue: holding.weight,
                            unit: "fraction"
                        ),
                        supportingSourceSlots: explanationSourceSlots(["allocation.holdings"])
                    )
                )
            }
    }

    private static func sectorConcentrationItems(from overview: PortfolioOverviewSummary) -> [AttentionItem] {
        overview.sectorSummary
            .filter { ($0.percentage / 100.0) >= sectorConcentrationThreshold }
            .enumerated()
            .map { offset, sector in
                let weight = sector.percentage / 100.0
                let score = concentrationScore(weight: weight, threshold: sectorConcentrationThreshold)
                let title = "\(distributionLabel(sector.name)) sector concentration"
                return AttentionItem(
                    id: "allocation.sector.\(stableIDToken(sector.name))",
                    facet: "allocation",
                    rank: offset + 1,
                    title: title,
                    detail: percent(weight),
                    severity: score >= 0.8 ? "high" : "medium",
                    score: score,
                    currentWeight: weight,
                    threshold: sectorConcentrationThreshold,
                    supportingDataSlotIDs: ["allocation.sectors"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Sector concentration line crossed"
                        ),
                        severity: explanationSeverity(
                            severity: score >= 0.8 ? "high" : "medium",
                            score: score
                        ),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: percent(sectorConcentrationThreshold),
                            numericValue: sectorConcentrationThreshold,
                            unit: "fraction"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: percent(weight),
                            numericValue: weight,
                            unit: "fraction"
                        ),
                        supportingSourceSlots: explanationSourceSlots(["allocation.sectors"])
                    )
                )
            }
    }

    private static func cashDragItems(from overview: PortfolioOverviewSummary) -> [AttentionItem] {
        guard let cash = overview.cashSummary,
              cash.weight >= cashDragThreshold
        else {
            return []
        }
        let score = concentrationScore(weight: cash.weight, threshold: cashDragThreshold)
        return [
            AttentionItem(
                id: "allocation.cashDrag",
                facet: "allocation",
                rank: 1,
                title: "Cash drag",
                detail: "\(percent(cash.weight)); \(display(cash.value))",
                severity: score >= 0.8 ? "high" : "medium",
                score: score,
                currentWeight: cash.weight,
                threshold: cashDragThreshold,
                supportingDataSlotIDs: ["allocation.overview"],
                explanation: AttentionExplanation(
                    trigger: AttentionExplanationFact(
                        key: "trigger",
                        label: "Trigger",
                        value: "Cash allocation line crossed"
                    ),
                    severity: explanationSeverity(
                        severity: score >= 0.8 ? "high" : "medium",
                        score: score
                    ),
                    threshold: AttentionExplanationFact(
                        key: "threshold",
                        label: "Threshold",
                        value: percent(cashDragThreshold),
                        numericValue: cashDragThreshold,
                        unit: "fraction"
                    ),
                    currentValue: AttentionExplanationFact(
                        key: "currentValue",
                        label: "Current",
                        value: "\(percent(cash.weight)); \(display(cash.value))",
                        numericValue: cash.weight,
                        unit: "fraction"
                    ),
                    supportingSourceSlots: explanationSourceSlots(["allocation.overview"])
                )
            ),
        ]
    }

    private static func concentrationDriftItems(
        from overview: PortfolioOverviewSummary,
        priorOverview: PortfolioOverviewSummary?
    ) -> [AttentionItem] {
        guard let current = overview.topNConcentration,
              let prior = priorOverview?.topNConcentration,
              current.rankCount == prior.rankCount
        else {
            return []
        }
        let drift = current.weight - prior.weight
        guard drift >= concentrationDriftThreshold else {
            return []
        }
        let score = concentrationScore(weight: drift, threshold: concentrationDriftThreshold)
        return [
            AttentionItem(
                id: "allocation.concentrationDrift.top\(current.rankCount)",
                facet: "allocation",
                rank: 1,
                title: "Top \(current.rankCount) concentration drift",
                detail: "\(percent(prior.weight)) -> \(percent(current.weight))",
                severity: score >= 0.8 ? "high" : "medium",
                score: score,
                currentWeight: current.weight,
                threshold: concentrationDriftThreshold,
                beforeWeight: prior.weight,
                afterWeight: current.weight,
                supportingDataSlotIDs: ["allocation.overview", "allocation.priorSnapshot"],
                explanation: AttentionExplanation(
                    trigger: AttentionExplanationFact(
                        key: "trigger",
                        label: "Trigger",
                        value: "Top concentration drift crossed"
                    ),
                    severity: explanationSeverity(
                        severity: score >= 0.8 ? "high" : "medium",
                        score: score
                    ),
                    threshold: AttentionExplanationFact(
                        key: "threshold",
                        label: "Threshold",
                        value: percent(concentrationDriftThreshold),
                        numericValue: concentrationDriftThreshold,
                        unit: "fraction"
                    ),
                    currentValue: AttentionExplanationFact(
                        key: "currentValue",
                        label: "Current",
                        value: percent(current.weight),
                        numericValue: current.weight,
                        unit: "fraction"
                    ),
                    priorValue: AttentionExplanationFact(
                        key: "priorValue",
                        label: "Prior",
                        value: percent(prior.weight),
                        numericValue: prior.weight,
                        unit: "fraction"
                    ),
                    supportingSourceSlots: explanationSourceSlots(["allocation.overview", "allocation.priorSnapshot"])
                )
            ),
        ]
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

    private struct BigMoverSignal {
        var beforeDecimal: Decimal
        var afterDecimal: Decimal
        var absoluteDecimalMove: Decimal
        var moveSize: Double
        var currency: String?
        var windowStart: String
        var windowEnd: String
    }

    private enum PriorBigMoverSignal {
        case triggered(BigMoverSignal)
        case belowThreshold
        case unavailable
    }

    private static func bigMoverItems(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot?) -> [AttentionItem] {
        let priorHoldings = priorSnapshot?.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holdings[holding.quoteId] ?? holding
        } ?? [:]
        let priceHistorySignals = bigMoverSignals(from: snapshot.priceSeries)
        let moverThreshold = Decimal(string: String(bigMoverThreshold)) ?? 0
        return snapshot.openHoldings.compactMap { holding -> AttentionItem? in
            var canUsePriceHistory = priorHoldings[holding.quoteId] == nil
            if let priorHolding = priorHoldings[holding.quoteId] {
                switch priorSnapshotSignal(
                   holding: holding,
                   priorHolding: priorHolding,
                   priorSnapshot: priorSnapshot,
                   currentAsOf: snapshot.asOf,
                   threshold: moverThreshold
                ) {
                case .triggered(let signal):
                    return bigMoverItem(
                        holding: holding,
                        signal: signal,
                        beforeWeight: priorHolding.weight,
                        sourceSlotIDs: ["bigMovers.priorSnapshot", "bigMovers.prices"]
                    )
                case .belowThreshold:
                    return nil
                case .unavailable:
                    canUsePriceHistory = true
                }
            }

            guard canUsePriceHistory,
                  let signal = priceHistorySignals[holding.quoteId],
                  signal.absoluteDecimalMove >= moverThreshold
            else { return nil }

            return bigMoverItem(
                holding: holding,
                signal: signal,
                beforeWeight: nil,
                sourceSlotIDs: ["bigMovers.prices"]
            )
        }
    }

    private static func priorSnapshotSignal(
        holding: NormalizedHolding,
        priorHolding: NormalizedHolding,
        priorSnapshot: PortfolioSnapshot?,
        currentAsOf: String,
        threshold: Decimal
    ) -> PriorBigMoverSignal {
        guard let priorSnapshot,
              let priorPrice = priorHolding.price,
              let price = holding.price,
              let beforeDecimal = posixDecimal(priorPrice.value),
              let afterDecimal = posixDecimal(price.value),
              beforeDecimal != 0
        else { return .unavailable }

        let decimalMove = (afterDecimal - beforeDecimal) / beforeDecimal
        let absoluteDecimalMove = decimalMove < 0 ? -decimalMove : decimalMove
        guard absoluteDecimalMove >= threshold else { return .belowThreshold }

        return .triggered(BigMoverSignal(
            beforeDecimal: beforeDecimal,
            afterDecimal: afterDecimal,
            absoluteDecimalMove: absoluteDecimalMove,
            moveSize: rounded(Double(truncating: decimalMove as NSDecimalNumber), places: 4),
            currency: price.currency,
            windowStart: priorSnapshot.asOf,
            windowEnd: currentAsOf
        ))
    }

    private static func bigMoverSignals(from priceSeries: [PricePoint]) -> [Int: BigMoverSignal] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: priceSeries, by: \.quoteId)
                .compactMap { quoteId, points -> (Int, BigMoverSignal)? in
                    guard let signal = bigMoverSignal(points: points) else {
                        return nil
                    }
                    return (quoteId, signal)
                }
        )
    }

    private static func bigMoverSignal(points: [PricePoint]) -> BigMoverSignal? {
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
            return $0.close < $1.close
        }
        guard let first = sorted.first,
              let last = sorted.last,
              first.date < last.date
        else {
            return nil
        }

        let change = (last.close - first.close) / first.close
        let absoluteChange = change < 0 ? -change : change
        return BigMoverSignal(
            beforeDecimal: first.close,
            afterDecimal: last.close,
            absoluteDecimalMove: absoluteChange,
            moveSize: rounded(Double(truncating: change as NSDecimalNumber), places: 4),
            currency: last.point.closeCurrency ?? first.point.closeCurrency,
            windowStart: first.point.date,
            windowEnd: last.point.date
        )
    }

    private static func bigMoverItem(
        holding: NormalizedHolding,
        signal: BigMoverSignal,
        beforeWeight: Double?,
        sourceSlotIDs: [String]
    ) -> AttentionItem? {
        guard let price = holding.price else { return nil }

        let currency = signal.currency ?? price.currency
        let beforeValue = Double(truncating: signal.beforeDecimal as NSDecimalNumber)
        let afterValue = Double(truncating: signal.afterDecimal as NSDecimalNumber)
        let score = rounded(min(1.0, abs(signal.moveSize) / 0.20), places: 2)
        let valueCopy = "from \(currency) \(decimalString(String(beforeValue), places: 2)) to \(currency) \(decimalString(String(afterValue), places: 2))"
        let detailSuffix = beforeWeight.map {
            " while portfolio weight changed \(percent($0)) -> \(percent(holding.weight))."
        } ?? " over price history window."
        return AttentionItem(
            id: "bigMovers.move.\(holding.quoteId)",
            facet: "bigMovers",
            rank: 0,
            title: "\(holding.name) moved \(signedPercent(signal.moveSize))",
            detail: "\(holding.name) moved \(signedPercent(signal.moveSize)) \(valueCopy)\(detailSuffix)",
            severity: abs(signal.moveSize) >= 0.20 ? "high" : "medium",
            score: score,
            holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
            beforeValue: beforeValue,
            afterValue: afterValue,
            moveSize: signal.moveSize,
            beforeWeight: beforeWeight,
            afterWeight: holding.weight,
            valueCurrency: currency,
            windowStart: signal.windowStart,
            windowEnd: signal.windowEnd,
            supportingDataSlotIDs: sourceSlotIDs,
            explanation: AttentionExplanation(
                trigger: AttentionExplanationFact(
                    key: "trigger",
                    label: "Trigger",
                    value: "Price move crossed recent-window line"
                ),
                severity: explanationSeverity(
                    severity: abs(signal.moveSize) >= 0.20 ? "high" : "medium",
                    score: score
                ),
                threshold: AttentionExplanationFact(
                    key: "threshold",
                    label: "Threshold",
                    value: percent(bigMoverThreshold),
                    numericValue: bigMoverThreshold,
                    unit: "fraction"
                ),
                currentValue: AttentionExplanationFact(
                    key: "currentValue",
                    label: "Current",
                    value: "\(currency) \(decimalString(String(afterValue), places: 2))",
                    numericValue: afterValue,
                    unit: currency
                ),
                priorValue: AttentionExplanationFact(
                    key: "priorValue",
                    label: "Prior",
                    value: "\(currency) \(decimalString(String(beforeValue), places: 2))",
                    numericValue: beforeValue,
                    unit: currency
                ),
                supportingSourceSlots: explanationSourceSlots(sourceSlotIDs)
            )
        )
    }

    private static func incomeItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        let incomeWindowEnd = dayString(daysFrom: snapshot.asOf, days: 30) ?? snapshot.asOf
        guard let incomeWindowStartDate = dayDate(from: snapshot.asOf),
              let incomeWindowEndDate = dayDate(from: incomeWindowEnd)
        else {
            return []
        }
        return snapshot.incomeEvents
            .filter { $0.kind == "ex-dividend" && !$0.estimated }
            .filter { event in
                guard let eventDate = dayDate(from: event.date) else {
                    return false
                }
                return eventDate >= incomeWindowStartDate && eventDate <= incomeWindowEndDate
            }
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
                    windowStart: snapshot.asOf,
                    windowEnd: incomeWindowEnd,
                    supportingDataSlotIDs: ["income.calendar"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Ex-dividend date in income window"
                        ),
                        severity: explanationSeverity(severity: "low", score: 0.45),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: "\(snapshot.asOf)..\(incomeWindowEnd)"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: event.date
                        ),
                        priorValue: event.priorAmount.map {
                            AttentionExplanationFact(
                                key: "priorValue",
                                label: "Prior",
                                value: display($0)
                            )
                        },
                        supportingSourceSlots: explanationSourceSlots(["income.calendar"])
                    )
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

    private static func explanationSeverity(severity: String, score: Double) -> AttentionExplanationFact {
        AttentionExplanationFact(
            key: "severity",
            label: "Severity",
            value: severity,
            numericValue: score
        )
    }

    private static func explanationSourceSlots(_ ids: [String]) -> [AttentionExplanationSourceSlot] {
        ids.map {
            AttentionExplanationSourceSlot(id: $0, label: explanationSourceLabel(for: $0))
        }
    }

    private static func explanationSourceLabel(for id: String) -> String? {
        switch id {
        case "allocation.overview":
            return "Portfolio overview"
        case "allocation.holdings":
            return "Open holdings"
        case "allocation.sectors":
            return "Sector breakdown"
        case "allocation.priorSnapshot":
            return "Prior allocation snapshot"
        case "income.calendar":
            return "Calendar events"
        case "bigMovers.priorSnapshot":
            return "Prior snapshot"
        case "bigMovers.prices":
            return "Price rows"
        default:
            return nil
        }
    }

    private static func dayString(daysFrom value: String, days: Int) -> String? {
        guard let date = dayDate(from: value),
              let result = dateCalendar.date(byAdding: .day, value: days, to: date)
        else {
            return nil
        }
        let components = dateCalendar.dateComponents([.year, .month, .day], from: result)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
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

public enum PulseLifecycleSource: String, Codable, Equatable {
    case cachedSnapshot
    case fetchedSnapshot
    case refreshedSnapshot
}

public struct PulseLifecycleResult: Codable, Equatable {
    public var unfilteredModel: PortfolioPulseModel
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
    public var readState: PulseReadState?
    public var source: PulseLifecycleSource

    public init(
        unfilteredModel: PortfolioPulseModel,
        model: PortfolioPulseModel,
        snapshotCommit: SnapshotCommit,
        descriptor: MenuDescriptor,
        readState: PulseReadState? = nil,
        source: PulseLifecycleSource
    ) {
        self.unfilteredModel = unfilteredModel
        self.model = model
        self.snapshotCommit = snapshotCommit
        self.descriptor = descriptor
        self.readState = readState
        self.source = source
    }

    public func applyingReadState(_ readState: PulseReadState?) -> PulseLifecycleResult {
        var model = PressureRunner.modelAfterApplyingReadState(unfilteredModel, readState: readState)
        var dataHealth = model.facetSnapshots.dataHealth
        let readFingerprintCount = readState?.readFingerprints.count ?? 0
        dataHealth.readState = DataHealthReadStateSnapshot(
            readFingerprintCount: readFingerprintCount,
            detail: "\(readFingerprintCount) read"
        )
        model.facetSnapshots.dataHealth = dataHealth
        return PulseLifecycleResult(
            unfilteredModel: unfilteredModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model),
            readState: readState,
            source: source
        )
    }
}

public typealias PressureRunResult = PulseLifecycleResult

public struct SnapshotCommit: Codable, Equatable {
    public var written: Bool
    public var path: String
    public var asOf: String

    public init(written: Bool, path: String, asOf: String) {
        self.written = written
        self.path = path
        self.asOf = asOf
    }
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
    public static let allowedV1 = requiredV1 + ["pdt-get-symbol"]

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
        guard PDTReadTools.allowedV1.contains(name) else {
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
    public var pulse: PulseLifecycleResult
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
        try? snapshotStore.clearLastDetailRefreshDiagnostic()
        let requiredTools = [
            "pdt-get-portfolio-holdings",
            "pdt-get-portfolio-distributions",
            "pdt-list-x-ray-holdings",
            "pdt-list-calendar-events",
            "pdt-list-dividends",
            "pdt-list-symbol-prices",
            "pdt-get-symbol-quote",
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
            let normalized = PDTOptionalDetailNormalizer.normalizeDistributions(distributions.optionalDetailInput)
            snapshot.sectors = normalized.sectors
            snapshot.assetTypes = normalized.assetTypes
            _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        } catch {
            diagnostics.append(diagnostic(for: error, tool: "pdt-get-portfolio-distributions", phase: .allocation))
        }

        do {
            progress(BackgroundDetailRefreshProgress(phase: .xRay))
            snapshot.xRayHoldings = PDTOptionalDetailNormalizer.normalizeXRayHoldings(try xRayHoldings())
            _ = try snapshotStore.commitCurrentSnapshot(snapshot)
        } catch {
            diagnostics.append(diagnostic(for: error, tool: "pdt-list-x-ray-holdings", phase: .xRay, arguments: [
                "limit": "",
                "offset": "",
            ]))
        }

        do {
            progress(BackgroundDetailRefreshProgress(phase: .income))
            let income = try incomeEvents(asOf: snapshotAsOf, holdings: snapshot.openHoldings)
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
        let outcome: PDTBackgroundDetailRefreshOutcome = diagnostics.isEmpty ? .completed : .degraded
        let pulse = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: originalPriorSnapshot,
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            detailRefreshOutcome: outcome,
            detailRefreshDiagnostic: diagnostics.last
        )
        if let lastDiagnostic = diagnostics.last {
            try snapshotStore.saveLastDetailRefreshDiagnostic(lastDiagnostic)
        } else {
            try snapshotStore.clearLastDetailRefreshDiagnostic()
        }
        return PDTBackgroundDetailRefreshResult(
            outcome: outcome,
            pulse: pulse,
            model: pulse.model,
            snapshotCommit: pulse.snapshotCommit,
            descriptor: pulse.descriptor,
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
        let normalization = PDTBaseHoldingNormalizer.normalize(
            holdingsEnvelope.holdings.map(\.baseHoldingInput),
            currency: "EUR"
        )
        return PortfolioSnapshot(
            asOf: snapshotAsOf,
            totalValue: normalization.totalValue,
            openHoldings: normalization.openHoldings,
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
        snapshot.latestCompleteDetailFillAsOf = priorSnapshot.latestCompleteDetailFillAsOf
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

    private func xRayHoldings() throws -> [PDTXRayHoldingInput] {
        let limit = 500
        var offset = 0
        var holdings: [PDTXRayHoldingInput] = []
        while true {
            let arguments = ["limit": String(limit), "offset": String(offset)]
            let envelope: XRayHoldingsEnvelope = try callDecodedWithRetry(
                "pdt-list-x-ray-holdings",
                phase: .xRay,
                arguments: arguments
            )
            holdings.append(contentsOf: envelope.items.map(\.optionalDetailInput))
            guard envelope.hasMore == true, !envelope.items.isEmpty else {
                return holdings
            }
            offset += limit
        }
    }

    private func incomeEvents(
        asOf snapshotAsOf: String,
        holdings: [NormalizedHolding]
    ) throws -> (events: [IncomeEventSummary], dividendRowCount: Int) {
        let incomeDateRange = [
            "date_from": snapshotAsOf,
            "date_to": dayString(snapshotAsOf, addingDays: 30),
        ]
        let dividendDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -370),
            "date_to": incomeDateRange["date_to"] ?? snapshotAsOf,
        ]
        let paginatedCalendarEvents = try liveCalendarEvents(arguments: incomeDateRange)
        let dividends = try liveDividends(arguments: dividendDateRange)
        let calendarEvents = paginatedCalendarEvents.filter { $0.type != "no-events-today" }
        let quoteIDsBySymbolID = try incomeQuoteIDsBySymbolID(for: calendarEvents, holdings: holdings)
        let normalized = PDTOptionalDetailNormalizer.normalizeIncomeEvents(
            calendarEvents: calendarEvents.map(\.optionalDetailInput),
            dividends: dividends.map(\.optionalDetailInput),
            quoteIDsBySymbolID: quoteIDsBySymbolID
        )
        return (
            events: normalized.events,
            dividendRowCount: normalized.dividendRowCount
        )
    }

    private func liveCalendarEvents(arguments baseArguments: [String: String]) throws -> [LiveCalendarEvent] {
        var page = 1
        var events: [LiveCalendarEvent] = []
        while true {
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": "250",
            ]) { _, new in new }
            let envelope: LiveCalendarEventsEnvelope = try callDecodedWithRetry(
                "pdt-list-calendar-events",
                phase: .income,
                arguments: arguments
            )
            events.append(contentsOf: envelope.data)
            let lastPage = envelope.meta?.lastPage ?? page
            guard page < lastPage else {
                return events
            }
            page += 1
        }
    }

    private func incomeQuoteIDsBySymbolID(
        for calendarEvents: [LiveCalendarEvent],
        holdings: [NormalizedHolding]
    ) throws -> [Int: Int] {
        var neededSymbolIDs = Set(calendarEvents.compactMap(\.symbolId))
        guard !neededSymbolIDs.isEmpty else {
            return [:]
        }
        var quoteIDsBySymbolID: [Int: Int] = [:]
        for holding in holdings.reversed() {
            let quote: LiveSymbolQuoteEnvelope = try callDecodedWithRetry(
                "pdt-get-symbol-quote",
                phase: .income,
                arguments: ["id": String(holding.quoteId)]
            )
            guard neededSymbolIDs.remove(quote.symbolId) != nil else {
                continue
            }
            quoteIDsBySymbolID[quote.symbolId] = quote.id
            if neededSymbolIDs.isEmpty {
                break
            }
        }
        return quoteIDsBySymbolID
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
                    let nextPoints = PDTOptionalDetailNormalizer.normalizePriceSeries(
                        prices.data.map(\.optionalDetailInput)
                    )
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
            calendarEvents = try liveCalendarEvents(arguments: incomeDateRange)
        } else {
            calendarEvents = []
        }
        let dividends = options.includeDividends ? try liveDividends(arguments: dividendDateRange) : []

        let baseNormalization = PDTBaseHoldingNormalizer.normalize(
            holdingsEnvelope.holdings.map(\.baseHoldingInput),
            currency: "EUR"
        )
        var openHoldings = baseNormalization.openHoldings
        let quoteMetadata = options.includeIncomeQuoteLookups
            ? try liveSymbolQuoteMetadata(for: openHoldings)
            : SymbolQuoteMetadata()
        openHoldings = openHoldings.map {
            var holding = $0
            holding.copyableIdentifier = quoteMetadata.codesByQuoteID[holding.quoteId]
            holding.isin = quoteMetadata.isinsByQuoteID[holding.quoteId] ?? holding.isin
            return holding
        }
        let quoteIDsBySymbolID = quoteMetadata.quoteIDsBySymbolID
        let priceSeries = options.includePriceSeries
            ? try livePriceRows(for: openHoldings, asOf: snapshotAsOf)
            : []
        let optionalDetails = PDTOptionalDetailNormalizer.normalize(
            distributions: distributionsEnvelope?.optionalDetailInput,
            xRayHoldings: xRayHoldings,
            calendarEvents: calendarEvents.map(\.optionalDetailInput),
            dividends: dividends.map(\.optionalDetailInput),
            quoteIDsBySymbolID: quoteIDsBySymbolID,
            priceRows: priceSeries
        )

        return PortfolioSnapshot(
            asOf: snapshotAsOf,
            totalValue: baseNormalization.totalValue,
            openHoldings: openHoldings,
            sectors: optionalDetails.sectors,
            assetTypes: optionalDetails.assetTypes,
            xRayHoldings: optionalDetails.xRayHoldings,
            incomeEvents: optionalDetails.incomeEvents,
            dividendRowCount: optionalDetails.dividendRowCount,
            priceSeries: optionalDetails.priceSeries
        )
    }

    private func liveSymbolQuoteMetadata(for holdings: [NormalizedHolding]) throws -> SymbolQuoteMetadata {
        var metadata = SymbolQuoteMetadata()
        var attemptedSymbolIDs = Set<Int>()
        var isinsBySymbolID: [Int: String] = [:]
        var symbolLookupUnavailable = false
        for holding in holdings {
            let quote: LiveSymbolQuoteEnvelope = try decodeLiveTool(
                "pdt-get-symbol-quote",
                data: toolClient.callReadTool("pdt-get-symbol-quote", arguments: ["id": String(holding.quoteId)])
            )
            metadata.quoteIDsBySymbolID[quote.symbolId] = quote.id
            if let code = safePublicIdentifier(quote.code) {
                metadata.codesByQuoteID[quote.id] = code
            }
            guard holding.isin == nil, !symbolLookupUnavailable else {
                continue
            }
            if let isin = isinsBySymbolID[quote.symbolId] {
                metadata.isinsByQuoteID[quote.id] = isin
                continue
            }
            guard attemptedSymbolIDs.insert(quote.symbolId).inserted else {
                continue
            }
            do {
                let symbol: LiveSymbolEnvelope = try decodeLiveTool(
                    "pdt-get-symbol",
                    data: toolClient.callReadTool("pdt-get-symbol", arguments: ["id": String(quote.symbolId)])
                )
                if let isin = PDTBaseHoldingNormalizer.safeISIN(symbol.isin) {
                    isinsBySymbolID[quote.symbolId] = isin
                    metadata.isinsByQuoteID[quote.id] = isin
                }
            } catch {
                symbolLookupUnavailable = shouldStopOptionalSymbolLookups(after: error)
            }
        }
        return metadata
    }

    private func shouldStopOptionalSymbolLookups(after error: Error) -> Bool {
        switch error {
        case is PDTMCPConnectorError:
            return true
        case PDTLiveDataSourceError.unavailableToolResult:
            return true
        default:
            return false
        }
    }

    private func liveXRayHoldings() throws -> [PDTXRayHoldingInput] {
        let limit = 500
        var offset = 0
        var holdings: [PDTXRayHoldingInput] = []
        while true {
            let envelope: XRayHoldingsEnvelope = try decodeLiveTool(
                "pdt-list-x-ray-holdings",
                data: toolClient.callReadTool(
                    "pdt-list-x-ray-holdings",
                    arguments: ["limit": String(limit), "offset": String(offset)]
                )
            )
            holdings.append(contentsOf: envelope.items.map(\.optionalDetailInput))
            guard envelope.hasMore == true, !envelope.items.isEmpty else {
                return holdings
            }
            offset += limit
        }
    }

    private func liveCalendarEvents(arguments baseArguments: [String: String]) throws -> [LiveCalendarEvent] {
        var page = 1
        var events: [LiveCalendarEvent] = []
        while true {
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": "250",
            ]) { _, new in new }
            let envelope: LiveCalendarEventsEnvelope = try decodeLiveTool(
                "pdt-list-calendar-events",
                data: toolClient.callReadTool("pdt-list-calendar-events", arguments: arguments)
            )
            events.append(contentsOf: envelope.data)
            let lastPage = envelope.meta?.lastPage ?? page
            guard page < lastPage else {
                return events
            }
            page += 1
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

    private func livePriceRows(for holdings: [NormalizedHolding], asOf: String) throws -> [PDTPriceInput] {
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
            return prices.data.map(\.optionalDetailInput)
        }
    }
}

public enum PressureRunner {
    public static func cachedPulse(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil
    ) throws -> PulseLifecycleResult? {
        guard let snapshot = try snapshotStore.loadPriorSnapshot() else {
            return nil
        }
        let commit = SnapshotCommit(
            written: false,
            path: snapshotStore.currentSnapshotPath.path,
            asOf: snapshot.asOf
        )
        return try lifecycleResult(
            snapshot: snapshot,
            priorSnapshot: nil,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .cachedSnapshot,
            resetsReappearedReadState: false,
            detailRefreshDiagnostic: cachedDetailRefreshDiagnostic(for: snapshot, snapshotStore: snapshotStore)
        )
    }

    private static func cachedDetailRefreshDiagnostic(
        for snapshot: PortfolioSnapshot,
        snapshotStore: SnapshotStore
    ) -> PDTDetailRefreshFailureDiagnostic? {
        guard snapshot.latestDetailFillOutcome == .degraded else {
            return nil
        }
        return try? snapshotStore.loadLastDetailRefreshDiagnostic()
    }

    public static func cachedPulseDescriptor(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil
    ) throws -> MenuDescriptor? {
        try cachedPulse(snapshotStore: snapshotStore, pulseReadStore: pulseReadStore)?.descriptor
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
        var snapshot = try dataSource.snapshot(asOf: asOf)
        let priorSnapshot: PortfolioSnapshot?
        do {
            priorSnapshot = try snapshotStore.loadPriorSnapshot()
        } catch {
            priorSnapshot = nil
        }
        if hasOptionalDetailSlice(snapshot) {
            snapshot.latestCompleteDetailFillAsOf = snapshot.asOf
            snapshot.latestDetailFillOutcome = .completed
        } else if let priorSnapshot {
            snapshot.latestCompleteDetailFillAsOf = snapshot.latestCompleteDetailFillAsOf
                ?? priorSnapshot.latestCompleteDetailFillAsOf
            snapshot.latestDetailFillOutcome = snapshot.latestDetailFillOutcome
                ?? priorSnapshot.latestDetailFillOutcome
        }
        let loadedReadState = displayReadState(from: pulseReadStore)
        let commit = try snapshotStore.commitCurrentSnapshot(snapshot)
        return try lifecycleResult(
            snapshot: snapshot,
            priorSnapshot: priorSnapshot,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .fetchedSnapshot,
            loadedReadState: loadedReadState,
            resetsReappearedReadState: true
        )
    }

    private static func hasOptionalDetailSlice(_ snapshot: PortfolioSnapshot) -> Bool {
        !snapshot.sectors.isEmpty
            || !snapshot.assetTypes.isEmpty
            || !(snapshot.xRayHoldings ?? []).isEmpty
            || !snapshot.incomeEvents.isEmpty
            || snapshot.dividendRowCount > 0
            || !snapshot.priceSeries.isEmpty
    }

    public static func refreshedPulse(
        snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil
    ) throws -> PulseLifecycleResult {
        let loadedReadState = displayReadState(from: pulseReadStore)
        var committedSnapshot = snapshot
        if let detailRefreshOutcome {
            committedSnapshot.latestDetailFillOutcome = detailRefreshOutcome
        }
        if detailRefreshOutcome == .completed {
            committedSnapshot.latestCompleteDetailFillAsOf = committedSnapshot.asOf
        }
        let commit = try snapshotStore.commitCurrentSnapshot(committedSnapshot)
        return try lifecycleResult(
            snapshot: committedSnapshot,
            priorSnapshot: priorSnapshot,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .refreshedSnapshot,
            loadedReadState: loadedReadState,
            resetsReappearedReadState: true,
            detailRefreshOutcome: detailRefreshOutcome,
            detailRefreshDiagnostic: detailRefreshDiagnostic
        )
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

    static func lifecycleResult(
        snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        snapshotCommit: SnapshotCommit,
        pulseReadStore: PulseReadStore?,
        source: PulseLifecycleSource,
        loadedReadState: PulseReadState? = nil,
        resetsReappearedReadState: Bool,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil
    ) throws -> PulseLifecycleResult {
        let displayReadState = loadedReadState ?? displayReadState(from: pulseReadStore)
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        var rawModel = PressureEngine.buildModel(
            from: snapshot,
            priorSnapshot: priorSnapshot,
            readState: displayReadState,
            detailRefreshOutcome: effectiveDetailRefreshOutcome
        )
        rawModel.facetSnapshots.dataHealth = DataHealth.build(
            DataHealthInput.default(
                freshness: rawModel.facetSnapshots.freshness,
                pulseSource: source,
                readState: displayReadState,
                detailRefreshOutcome: effectiveDetailRefreshOutcome,
                diagnostic: detailRefreshDiagnostic
            )
        )
        let readState = resetsReappearedReadState
            ? try readStateAfterResettingReappearedItems(
                in: rawModel,
                loadedReadState: displayReadState,
                pulseReadStore: pulseReadStore
            )
            : displayReadState
        var model = modelAfterApplyingReadState(rawModel, readState: readState)
        model.facetSnapshots.dataHealth = DataHealth.build(
            DataHealthInput.default(
                freshness: model.facetSnapshots.freshness,
                pulseSource: source,
                readState: readState,
                detailRefreshOutcome: effectiveDetailRefreshOutcome,
                diagnostic: detailRefreshDiagnostic
            )
        )
        return PulseLifecycleResult(
            unfilteredModel: rawModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model),
            readState: readState,
            source: source
        )
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
        try OwnerOnlyLocalStore.prepareDirectory(directory)
        return SnapshotStore(directory: directory)
    }

    public func loadPriorSnapshot() throws -> PortfolioSnapshot? {
        let target = currentSnapshotPath
        guard FileManager.default.fileExists(atPath: target.path) else {
            return nil
        }
        try OwnerOnlyLocalStore.protectExistingFile(target)
        return try JSONDecoder().decode(PortfolioSnapshot.self, from: Data(contentsOf: target))
    }

    public func commitCurrentSnapshot(_ snapshot: PortfolioSnapshot) throws -> SnapshotCommit {
        let target = currentSnapshotPath
        try OwnerOnlyLocalStore.write(stableJSONData(snapshot), to: target)
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
        try OwnerOnlyLocalStore.protectExistingFile(target)
        return try JSONDecoder().decode(PDTDetailRefreshFailureDiagnostic.self, from: Data(contentsOf: target))
    }

    public func saveLastDetailRefreshDiagnostic(_ diagnostic: PDTDetailRefreshFailureDiagnostic) throws {
        try OwnerOnlyLocalStore.write(stableJSONData(diagnostic), to: detailRefreshDiagnosticFile)
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

    public var currentSnapshotPath: URL {
        directory.appending(path: "latest-portfolio-snapshot.json")
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
            if let code = PDTBaseHoldingNormalizer.safePublicIdentifier(quote.code) {
                codesByQuoteID[quote.id] = code
            }
        }
        let normalization = PDTBaseHoldingNormalizer.normalize(
            rawHoldings.map { $0.baseHoldingInput(copyableIdentifier: quoteCodesByQuoteID[$0.symbolQuoteId]) },
            currency: payload.meta.portfolioCurrency,
            reportedTotalValue: payload.meta.portfolioCurrentWorthEUR.map {
                Money(value: $0, currency: payload.meta.portfolioCurrency)
            }
        )
        let holdings = normalization.openHoldings

        let quoteIDsBySymbolID = payload.symbolQuotes.reduce(into: [Int: Int]()) { idsBySymbolID, quote in
            idsBySymbolID[quote.symbolId] = quote.id
        }
        let optionalDetails = PDTOptionalDetailNormalizer.normalize(
            distributions: payload.getPortfolioDistributions?.optionalDetailInput,
            xRayHoldings: payload.listXRayHoldings?.items.map(\.optionalDetailInput),
            calendarEvents: payload.listCalendarEvents?.data.map(\.optionalDetailInput) ?? [],
            dividends: payload.listDividends?.data.map(\.optionalDetailInput) ?? [],
            quoteIDsBySymbolID: quoteIDsBySymbolID,
            priceRows: payload.listSymbolPrices?.data.map(\.optionalDetailInput) ?? []
        )

        return PortfolioSnapshot(
            asOf: asOf,
            totalValue: normalization.totalValue,
            openHoldings: holdings,
            sectors: optionalDetails.sectors,
            assetTypes: optionalDetails.assetTypes,
            xRayHoldings: optionalDetails.xRayHoldings,
            incomeEvents: optionalDetails.incomeEvents,
            dividendRowCount: optionalDetails.dividendRowCount,
            priceSeries: optionalDetails.priceSeries
        )
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
        case isin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentWorth = try? container.decodeIfPresent(Money.self, forKey: .currentWorth)
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceAverageLocal
        )
        unrealisedBoughtPriceTotalLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceTotalLocal
        )
        unrealisedBoughtShares = try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares)
        unrealisedGains = try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains)
        unrealisedGainsPercentage = try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
    }
}

private extension LiveHolding {
    var baseHoldingInput: PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: symbolName,
            quoteId: symbolQuoteId,
            currentPriceDate: currentPriceDate,
            currentPriceLocal: currentPriceLocal,
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

private struct XRayHoldingsEnvelope: Decodable {
    var items: [XRayHolding]
    var hasMore: Bool?
}

private struct XRayHolding: Decodable {
    var weight: Double

    var optionalDetailInput: PDTXRayHoldingInput {
        PDTXRayHoldingInput(weight: weight)
    }
}

private struct LiveDistributionsEnvelope: Decodable {
    var sectors: [LiveDistribution]
    var assetTypes: [LiveDistribution]

    var optionalDetailInput: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: sectors.map(\.optionalDetailInput),
            assetTypes: assetTypes.map(\.optionalDetailInput)
        )
    }
}

private struct LiveDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var optionalDetailInput: PDTDistributionInput {
        PDTDistributionInput(categoryName: categoryName, totalValue: totalValue, percentage: percentage)
    }
}

private struct LiveCalendarEventsEnvelope: Decodable {
    var data: [LiveCalendarEvent]
    var meta: LivePaginationMeta?
}

private struct LiveCalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolId: Int?
    var symbolName: String?

    var optionalDetailInput: PDTCalendarEventInput {
        PDTCalendarEventInput(
            date: date,
            type: type,
            isEstimated: isEstimated,
            symbolId: symbolId,
            symbolName: symbolName
        )
    }
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

    var optionalDetailInput: PDTDividendInput {
        PDTDividendInput(date: date, amount: amount, symbolQuoteId: symbolQuoteId)
    }
}

private struct LiveSymbolQuoteEnvelope: Decodable {
    var id: Int
    var code: String?
    var symbolId: Int
}

private struct LiveSymbolEnvelope: Decodable {
    var isin: String?
}

private struct SymbolQuoteMetadata {
    var quoteIDsBySymbolID: [Int: Int] = [:]
    var codesByQuoteID: [Int: String] = [:]
    var isinsByQuoteID: [Int: String] = [:]
}

private struct LivePricesEnvelope: Decodable {
    var data: [LivePrice]
}

private struct LivePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var closeCurrency: String?
    var symbolQuoteId: Int

    var optionalDetailInput: PDTPriceInput {
        PDTPriceInput(date: date, closeAdjusted: closeAdjusted, symbolQuoteId: symbolQuoteId, closeCurrency: closeCurrency)
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
    var isin: String?

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
        case isin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentWorth = try? container.decodeIfPresent(Money.self, forKey: .currentWorth)
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceAverageLocal
        )
        unrealisedBoughtPriceTotalLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceTotalLocal
        )
        unrealisedBoughtShares = try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares)
        unrealisedGains = try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains)
        unrealisedGainsPercentage = try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
    }
}

private extension FixtureHolding {
    func baseHoldingInput(copyableIdentifier: String?) -> PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: symbolName,
            quoteId: symbolQuoteId,
            currentPriceDate: currentPriceDate,
            currentPriceLocal: currentPriceLocal,
            currentWorth: currentWorth,
            currentWorthLocal: currentWorthLocal,
            portfolioWeight: portfolioWeight,
            unrealisedBoughtPriceAverageLocal: unrealisedBoughtPriceAverageLocal,
            unrealisedBoughtPriceTotalLocal: unrealisedBoughtPriceTotalLocal,
            unrealisedBoughtShares: unrealisedBoughtShares,
            unrealisedGains: unrealisedGains,
            unrealisedGainsPercentage: unrealisedGainsPercentage,
            closedAt: closedAt,
            copyableIdentifier: copyableIdentifier,
            isin: isin
        )
    }
}

private struct DistributionsEnvelope: Decodable {
    var sectors: [FixtureDistribution]?
    var assetTypes: [FixtureDistribution]?

    var optionalDetailInput: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: (sectors ?? []).map(\.optionalDetailInput),
            assetTypes: (assetTypes ?? []).map(\.optionalDetailInput)
        )
    }
}

private struct FixtureDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var optionalDetailInput: PDTDistributionInput {
        PDTDistributionInput(categoryName: categoryName, totalValue: totalValue, percentage: percentage)
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

    var optionalDetailInput: PDTCalendarEventInput {
        PDTCalendarEventInput(
            date: date,
            type: type,
            isEstimated: isEstimated,
            symbolId: symbolId,
            symbolName: symbolName
        )
    }
}

private struct DividendsEnvelope: Decodable {
    var data: [FixtureDividend]
}

private struct FixtureDividend: Decodable {
    var date: String
    var amount: Money
    var symbolQuoteId: Int

    var optionalDetailInput: PDTDividendInput {
        PDTDividendInput(date: date, amount: amount, symbolQuoteId: symbolQuoteId)
    }
}

private struct SymbolQuoteEnvelope: Decodable {
    var id: Int
    var code: String?
    var symbolId: Int
}

private func safePublicIdentifier(_ raw: String?) -> String? {
    PDTBaseHoldingNormalizer.safePublicIdentifier(raw)
}

private struct PricesEnvelope: Decodable {
    var data: [FixturePrice]
}

private struct FixturePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var closeCurrency: String?
    var symbolQuoteId: Int

    var optionalDetailInput: PDTPriceInput {
        PDTPriceInput(date: date, closeAdjusted: closeAdjusted, symbolQuoteId: symbolQuoteId, closeCurrency: closeCurrency)
    }
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

private func validMoney(_ money: Money?) -> Money? {
    PDTBaseHoldingNormalizer.validMoney(money)
}

private func posixDecimal(_ value: String) -> Decimal? {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}

private func finite(_ value: Double?) -> Double? {
    PDTBaseHoldingNormalizer.finite(value)
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

private func stableIDToken(_ value: String) -> String {
    let token = fingerprintToken(value)
    return token.isEmpty ? "unknown" : token
}

private func distributionLabel(_ value: String) -> String {
    value
        .split(separator: "-")
        .map { part in
            if part.uppercased() == "ETF" {
                return "ETF"
            }
            guard let first = part.first else {
                return ""
            }
            return first.uppercased() + part.dropFirst()
        }
        .joined(separator: " ")
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
