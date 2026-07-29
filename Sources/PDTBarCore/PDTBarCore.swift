// swiftlint:disable file_length
// Tracked debt: finding 05 will split this monolith.
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
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        today: String? = nil
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
        let staleReferenceAsOf = staleReferenceDay(asOf: snapshot.asOf, today: today)
        let staleRows = datedRows.filter {
            isStale(priceDate: $0.date, asOf: staleReferenceAsOf)
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

    /// Staleness is judged against the later of the snapshot's own `asOf` and the
    /// caller-supplied current day, so a cached snapshot from a prior day cannot
    /// keep reporting day-one prices as fresh.
    static func staleReferenceDay(asOf: String, today: String?) -> String {
        guard let today, let todayDate = freshnessDate(from: today) else {
            return asOf
        }
        guard let asOfDate = freshnessDate(from: asOf), asOfDate >= todayDate else {
            return today
        }
        return asOf
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

public enum DataHealthSourceStatus: String, Codable, Equatable, Sendable {
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

public enum DataHealthReadOnlyPolicyStatus: String, Codable, Equatable, Sendable {
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

public enum PriorSnapshotHealthStatus: String, Codable, Equatable, Sendable {
    case unknown
    case missing
    case available
    case corrupt
    case unreadable
}

private extension PriorSnapshotLoadStatus {
    var healthStatus: PriorSnapshotHealthStatus? {
        switch self {
        case .notRequested:
            return nil
        case .missing:
            return .missing
        case .loaded:
            return .available
        case .failed(.decode):
            return .corrupt
        case .failed(.io):
            return .unreadable
        }
    }
}

/// What the runtime actually knows about the Claude/PDT source right now.
/// Cached snapshots alone prove nothing about connectivity, read tools, or
/// policy; only a live fetch through the connector verifies all of them.
public struct DataHealthRuntimeSourceState: Equatable, Sendable {
    public var claudeReadiness: DataHealthSourceStatus
    public var pdtMCPReadiness: DataHealthSourceStatus
    public var availableReadTools: Set<String>?
    public var readOnlyPolicy: DataHealthReadOnlyPolicyStatus

    public init(
        claudeReadiness: DataHealthSourceStatus,
        pdtMCPReadiness: DataHealthSourceStatus,
        availableReadTools: Set<String>?,
        readOnlyPolicy: DataHealthReadOnlyPolicyStatus
    ) {
        self.claudeReadiness = claudeReadiness
        self.pdtMCPReadiness = pdtMCPReadiness
        self.availableReadTools = availableReadTools
        self.readOnlyPolicy = readOnlyPolicy
    }

    /// Facts proven by a live fetch through the Claude/PDT read-only connector.
    public static let liveFetchVerified = DataHealthRuntimeSourceState(
        claudeReadiness: .ready,
        pdtMCPReadiness: .ready,
        availableReadTools: Set(PDTReadTools.requiredV1),
        readOnlyPolicy: .enforced
    )

    /// Nothing verified in this session; the honest state for cache-only pulses.
    public static let unverified = DataHealthRuntimeSourceState(
        claudeReadiness: .unknown,
        pdtMCPReadiness: .unknown,
        availableReadTools: nil,
        readOnlyPolicy: .unknown
    )

    /// The source facts a pulse can truthfully assume from how it was built:
    /// fetched/refreshed pulses just came through the live connector, while a
    /// cached snapshot or an unknown source proves nothing about the current
    /// connection, so optimistic facts are never the silent fallback.
    public static func assumed(for pulseSource: PulseLifecycleSource?) -> DataHealthRuntimeSourceState {
        switch pulseSource {
        case .fetchedSnapshot, .refreshedSnapshot:
            return .liveFetchVerified
        case .cachedSnapshot, nil:
            return .unverified
        }
    }
}

public struct DataHealthInput: Equatable {
    public var claudeReadiness: DataHealthSourceStatus
    public var pdtMCPReadiness: DataHealthSourceStatus
    public var availableReadTools: Set<String>?
    public var readOnlyPolicy: DataHealthReadOnlyPolicyStatus
    public var pulseSource: PulseLifecycleSource?
    public var lastSuccessfulCompleteFetchAsOf: String?
    public var cachedPulseAvailable: Bool
    public var priorSnapshotStatus: PriorSnapshotHealthStatus?
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
        priorSnapshotStatus: PriorSnapshotHealthStatus? = nil,
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
        self.priorSnapshotStatus = priorSnapshotStatus
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
        diagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
    ) -> DataHealthInput {
        let runtimeSourceState = DataHealthRuntimeSourceState.assumed(for: pulseSource)
        return DataHealthInput(
            claudeReadiness: runtimeSourceState.claudeReadiness,
            pdtMCPReadiness: runtimeSourceState.pdtMCPReadiness,
            availableReadTools: runtimeSourceState.availableReadTools,
            readOnlyPolicy: runtimeSourceState.readOnlyPolicy,
            pulseSource: pulseSource,
            lastSuccessfulCompleteFetchAsOf: freshness.latestCompleteDetailFillAsOf,
            cachedPulseAvailable: pulseSource != nil,
            priorSnapshotStatus: priorSnapshotLoadStatus.healthStatus,
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
    public var priorSnapshotStatus: PriorSnapshotHealthStatus?
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
        let source = sourceSnapshot(
            DataHealthRuntimeSourceState(
                claudeReadiness: input.claudeReadiness,
                pdtMCPReadiness: input.pdtMCPReadiness,
                availableReadTools: input.availableReadTools,
                readOnlyPolicy: input.readOnlyPolicy
            )
        )
        let cache = DataHealthCacheSnapshot(
            pulseSource: input.pulseSource,
            cachedPulseAvailable: input.cachedPulseAvailable,
            lastSuccessfulCompleteFetchAsOf: input.lastSuccessfulCompleteFetchAsOf,
            priorSnapshotStatus: input.priorSnapshotStatus,
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

    /// Rebuilds the source facts of an already-built health snapshot from what
    /// the runtime currently knows, then recomputes the overall status. Used
    /// when a cached pulse is republished after the launch flow has learned
    /// real Claude/PDT readiness.
    public static func applyingRuntimeSourceState(
        _ state: DataHealthRuntimeSourceState,
        to snapshot: DataHealthSnapshot
    ) -> DataHealthSnapshot {
        var snapshot = snapshot
        snapshot.source = sourceSnapshot(state)
        snapshot.status = healthStatus(
            source: snapshot.source,
            detailFill: snapshot.detailFill,
            freshness: snapshot.freshness,
            diagnostic: snapshot.diagnostic
        )
        return snapshot
    }

    static func sourceSnapshot(_ state: DataHealthRuntimeSourceState) -> DataHealthSourceSnapshot {
        let requiredTools = PDTReadTools.requiredV1
        let missingTools = state.availableReadTools.map { PDTReadTools.missingRequiredV1Tools(in: $0) } ?? []
        let readToolsStatus: DataHealthReadToolsStatus
        if state.availableReadTools == nil {
            readToolsStatus = .unknown
        } else if missingTools.isEmpty {
            readToolsStatus = .available
        } else {
            readToolsStatus = .missingRequired
        }
        return DataHealthSourceSnapshot(
            claude: state.claudeReadiness,
            pdtMCP: state.pdtMCPReadiness,
            readTools: readToolsStatus,
            requiredReadToolCount: requiredTools.count,
            availableReadToolCount: state.availableReadTools?.intersection(requiredTools).count,
            missingReadTools: missingTools,
            readOnlyPolicy: state.readOnlyPolicy,
            detail: sourceDetail(
                claude: state.claudeReadiness,
                pdtMCP: state.pdtMCPReadiness,
                readTools: readToolsStatus,
                availableCount: state.availableReadTools?.intersection(requiredTools).count,
                requiredCount: requiredTools.count,
                missingTools: missingTools,
                readOnlyPolicy: state.readOnlyPolicy
            )
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

public enum PulseLifecycleSource: String, Codable, Equatable {
    case cachedSnapshot
    case fetchedSnapshot
    case refreshedSnapshot
}

public enum PriorSnapshotLoadFailureKind: String, Codable, Equatable, Sendable {
    case decode
    case io
}

public enum PriorSnapshotLoadStatus: Codable, Equatable, Sendable {
    case notRequested
    case missing
    case loaded
    case failed(PriorSnapshotLoadFailureKind)
}

public enum PriorSnapshotLoadResult: Codable, Equatable {
    case missing
    case loaded(PortfolioSnapshot)
    case failed(PriorSnapshotLoadFailureKind)

    public var snapshot: PortfolioSnapshot? {
        guard case .loaded(let snapshot) = self else {
            return nil
        }
        return snapshot
    }

    public var status: PriorSnapshotLoadStatus {
        switch self {
        case .missing:
            return .missing
        case .loaded:
            return .loaded
        case .failed(let kind):
            return .failed(kind)
        }
    }
}

public struct PriorSnapshotLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    public var kind: PriorSnapshotLoadFailureKind

    public init(kind: PriorSnapshotLoadFailureKind) {
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .decode:
            return "Prior snapshot could not be decoded"
        case .io:
            return "Prior snapshot could not be read"
        }
    }
}

public struct PulseLifecycleResult: Codable, Equatable {
    public var unfilteredModel: PortfolioPulseModel
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
    public var readState: PulseReadState?
    public var source: PulseLifecycleSource
    public var priorSnapshotLoadStatus: PriorSnapshotLoadStatus?

    public init(
        unfilteredModel: PortfolioPulseModel,
        model: PortfolioPulseModel,
        snapshotCommit: SnapshotCommit,
        descriptor: MenuDescriptor,
        readState: PulseReadState? = nil,
        source: PulseLifecycleSource,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
    ) {
        self.unfilteredModel = unfilteredModel
        self.model = model
        self.snapshotCommit = snapshotCommit
        self.descriptor = descriptor
        self.readState = readState
        self.source = source
        self.priorSnapshotLoadStatus = priorSnapshotLoadStatus
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
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus ?? .notRequested
        )
    }

    public func rendered(settings: PortfolioValueDisplaySettings) -> PulseLifecycleResult {
        PulseLifecycleResult(
            unfilteredModel: unfilteredModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model, settings: settings),
            readState: readState,
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus ?? .notRequested
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
    public static let performance = [
        "pdt-get-portfolio-performance",
        "pdt-get-portfolio-gains",
    ]
    public static let allowedV1 = requiredV1 + ["pdt-get-symbol"] + performance

    public static func missingRequiredV1Tools(in availableTools: Set<String>) -> [String] {
        requiredV1.filter { !availableTools.contains($0) }
    }
}

/// Single source of truth for the Claude CLI `--disallowedTools` denylist used
/// during read-only PDT syncs. Both the production connection
/// (`ClaudeLocalConnection`) and the `manual-claude-pdt` smoke must consume
/// this policy so the smoke keeps exercising the exact read-only policy the
/// app ships with. Production additionally denies non-requested PDT read
/// tools per call on top of this base list.
public enum ClaudePDTReadOnlyToolPolicy {
    /// Built-in Claude CLI tools denied during read-only PDT sync calls.
    /// ToolSearch is intentionally absent: it stays allowed so Claude can
    /// hydrate deferred remote MCP tools.
    public static let disallowedBuiltInTools = [
        "AskUserQuestion",
        "Bash",
        "CronCreate",
        "CronDelete",
        "CronList",
        "DesignSync",
        "Edit",
        "EnterPlanMode",
        "EnterWorktree",
        "ExitPlanMode",
        "ExitWorktree",
        "ListMcpResourcesTool",
        "Monitor",
        "NotebookEdit",
        "PushNotification",
        "Read",
        "ReadMcpResourceTool",
        "RemoteTrigger",
        "ScheduleWakeup",
        "Skill",
        "Task",
        "TaskCreate",
        "TaskGet",
        "TaskList",
        "TaskOutput",
        "TaskStop",
        "TaskUpdate",
        "WebFetch",
        "WebSearch",
        "Workflow",
        "Write",
    ]

    /// Wildcard selectors denying every known PDT mutating tool name shape.
    public static let disallowedPDTMutationSelectors = [
        "mcp__*__pdt-add-*",
        "mcp__*__pdt-create-*",
        "mcp__*__pdt-delete-*",
        "mcp__*__pdt-patch-*",
        "mcp__*__pdt-post-*",
        "mcp__*__pdt-put-*",
        "mcp__*__pdt-remove-*",
        "mcp__*__pdt-set-*",
        "mcp__*__pdt-update-*",
    ]

    /// The full shared denylist: denied built-ins plus PDT mutator selectors.
    public static let disallowedTools = disallowedBuiltInTools + disallowedPDTMutationSelectors
}

public protocol PDTMCPConnector {
    func availableReadTools() throws -> Set<String>
    func availableReadTools(required: Set<String>) throws -> Set<String>
    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data
    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?
    ) throws -> PDTMCPConnectorCallResult
    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?,
        cancellation: PDTCancellation?
    ) throws -> PDTMCPConnectorCallResult
}

public protocol PDTMCPConnectorProgressReporting {
    func availableReadTools(
        required: Set<String>,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String>
    func availableReadTools(
        required: Set<String>,
        cancellation: PDTCancellation?,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String>
}

public extension PDTMCPConnectorProgressReporting {
    func availableReadTools(
        required: Set<String>,
        cancellation: PDTCancellation? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String> {
        guard cancellation?.isCancelled != true else {
            throw PDTMCPConnectorError.timeout("PDT tool discovery cancelled")
        }
        let tools = try availableReadTools(required: required, progress: progress)
        guard cancellation?.isCancelled != true else {
            throw PDTMCPConnectorError.timeout("PDT tool discovery cancelled")
        }
        return tools
    }
}

public extension PDTMCPConnector {
    func availableReadTools(required: Set<String>) throws -> Set<String> {
        try availableReadTools().intersection(required)
    }

    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?
    ) throws -> PDTMCPConnectorCallResult {
        if let retryDeadline, Date() >= retryDeadline {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
            throw PDTMCPConnectorCallFailure(underlyingError: timeout, attemptCount: 0)
        }
        do {
            let data = try callReadTool(name, arguments: arguments)
            if let retryDeadline, Date() >= retryDeadline {
                throw PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
            }
            return PDTMCPConnectorCallResult(data: data, attemptCount: 1)
        } catch {
            let deadlineExpired = retryDeadline.map { Date() >= $0 } ?? false
            let underlyingError = deadlineExpired && pdtDetailRefreshFailureCategory(for: error).isRetryable
                ? PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
                : error
            throw PDTMCPConnectorCallFailure(underlyingError: underlyingError, attemptCount: 1)
        }
    }

    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?,
        cancellation: PDTCancellation? = nil
    ) throws -> PDTMCPConnectorCallResult {
        guard cancellation?.isCancelled != true else {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call cancelled")
            throw PDTMCPConnectorCallFailure(underlyingError: timeout, attemptCount: 0)
        }
        let result = try callReadToolReportingAttempts(
            name,
            arguments: arguments,
            retryDeadline: retryDeadline
        )
        guard cancellation?.isCancelled != true else {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call cancelled")
            throw PDTMCPConnectorCallFailure(
                underlyingError: timeout,
                attemptCount: result.attemptCount
            )
        }
        return result
    }
}

public struct PDTMCPConnectorCallResult: Sendable {
    public var data: Data
    public var attemptCount: Int

    public init(data: Data, attemptCount: Int) {
        self.data = data
        self.attemptCount = max(0, attemptCount)
    }
}

public struct PDTMCPConnectorCallFailure: Error {
    public var underlyingError: any Error
    public var attemptCount: Int

    public init(underlyingError: any Error, attemptCount: Int) {
        self.underlyingError = underlyingError
        self.attemptCount = max(0, attemptCount)
    }
}

public enum PDTMCPConnectorError: Error, CustomStringConvertible, Equatable {
    case missingRequiredReadTools([String])
    case setupUnavailable(String)
    case transientFailure(String)
    case timeout(String)
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
        case .timeout(let message):
            "PDT MCP connector timeout: \(message)"
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
    public var onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)?

    public init(
        connector: any PDTMCPConnector,
        liveOptions: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions(),
        onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)? = nil
    ) {
        self.connector = connector
        self.liveOptions = liveOptions
        self.onOptionalFacetFailure = onOptionalFacetFailure
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
            options: liveOptions,
            onOptionalFacetFailure: onOptionalFacetFailure
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
    case transientUnavailableToolResult(String)

    public var shouldSkipLiveSmoke: Bool {
        switch self {
        case .unavailableToolResult, .transientUnavailableToolResult:
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
        case .transientUnavailableToolResult(let tool):
            "live PDT tool \(tool) reported a transient unavailable response"
        }
    }
}

public enum PDTLiveUnavailableKind: Equatable, Sendable {
    case authOrSetup
    case transient
}

public enum PDTLiveUnavailableClassifier {
    public static func shouldSkip(_ value: String) -> Bool {
        unavailableKind(in: value) != nil
    }

    public static func unavailableKind(in value: String) -> PDTLiveUnavailableKind? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            return unavailableKind(in: object)
        }
        return unavailableKind(inText: trimmed)
    }

    static func shouldSkipObject(_ object: Any) -> Bool {
        unavailableKind(in: object) != nil
    }

    static func shouldSkipErrorPayload(_ object: Any) -> Bool {
        unavailableKind(in: object, forceErrorContext: true) != nil
    }

    static func unavailableKind(in object: Any, forceErrorContext: Bool = false) -> PDTLiveUnavailableKind? {
        var sawTransient = false
        for text in unavailableTexts(in: object, forceErrorContext: forceErrorContext) {
            switch unavailableKind(inText: text) {
            case .authOrSetup:
                return .authOrSetup
            case .transient:
                sawTransient = true
            case nil:
                continue
            }
        }
        return sawTransient ? .transient : nil
    }

    private static func unavailableKind(inText value: String) -> PDTLiveUnavailableKind? {
        let lower = value.lowercased()
        if authOrSetupPhrases.contains(where: { lower.contains($0) }) {
            return .authOrSetup
        }
        if transientUnavailablePhrases.contains(where: { lower.contains($0) }) {
            return .transient
        }
        return nil
    }

    private static let authOrSetupPhrases = [
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
        "server not found",
        "unknown mcp server",
        "setup required",
        "setup unavailable",
        "missing setup",
        "needs setup",
    ]

    private static let transientUnavailablePhrases = [
        "offline",
        "connection refused",
        "failed to connect",
        "could not connect",
        "econnrefused",
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
    case timeout
    case exit
}

public extension PDTDetailRefreshFailureCategory {
    /// True transients where a fresh Claude CLI run can plausibly succeed.
    /// Deterministic failures (stable-input decode mismatches, missing scripted
    /// responses) and Claude/PDT setup or auth outages repeat identically, so
    /// retrying them only spawns more full CLI runs.
    var isRetryable: Bool {
        switch self {
        case .transientFailure, .timeout, .exit:
            true
        case .setupUnavailable, .unavailable, .decode, .missingScriptedResponse:
            false
        }
    }

    /// Claude/PDT auth or setup outages that would fail every remaining detail
    /// phase the same way; once observed, later phases should be skipped.
    var indicatesUnavailableSetup: Bool {
        switch self {
        case .setupUnavailable, .unavailable:
            true
        case .transientFailure, .timeout, .exit, .decode, .missingScriptedResponse:
            false
        }
    }
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

func pdtDetailRefreshFailureCategory(for error: Error) -> PDTDetailRefreshFailureCategory {
    if let failure = error as? PDTMCPConnectorCallFailure {
        return pdtDetailRefreshFailureCategory(for: failure.underlyingError)
    }
    return switch error {
    case PDTMCPConnectorError.setupUnavailable:
        .setupUnavailable
    case PDTMCPConnectorError.transientFailure:
        .transientFailure
    case PDTMCPConnectorError.timeout:
        .timeout
    case PDTMCPConnectorError.missingScriptedResponse:
        .missingScriptedResponse
    case PDTLiveDataSourceError.malformedToolResult:
        .decode
    case PDTLiveDataSourceError.unavailableToolResult:
        .unavailable
    case PDTLiveDataSourceError.transientUnavailableToolResult:
        .transientFailure
    default:
        .exit
    }
}

private struct PDTListPage<Cursor, Item> {
    var items: [Item]
    var nextCursor: Cursor?
}

private let pdtMaximumPagesPerList = 50

public enum PDTListPaginationPolicy {
    /// Both PDT list-tool schemas document "max: 100" for `per_page`;
    /// observed live on 2026-07-29.
    public static let pageSize = 100
}

private enum PDTListPaginationTruncation {
    case pageCap
    case deadline
}

private struct PDTListPaginationResult<Item> {
    var items: [Item]
    var pageCount: Int
    var truncation: PDTListPaginationTruncation?

    func truncationDiagnostic(
        toolName: String,
        phase: BackgroundDetailRefreshPhase,
        argumentShape: [String]
    ) -> PDTDetailRefreshFailureDiagnostic? {
        guard truncation != nil else {
            return nil
        }
        return PDTDetailRefreshFailureDiagnostic(
            toolName: toolName,
            phase: phase,
            attemptCount: max(1, pageCount),
            category: .timeout,
            argumentShape: argumentShape
        )
    }
}

private func paginatePDTList<Cursor, Item>(
    initialCursor: Cursor,
    maxPages: Int,
    deadline: Date,
    now: @Sendable () -> Date,
    treatErrorAsDeadline: (Error) -> Bool = { _ in false },
    fetchPage: (Cursor) throws -> PDTListPage<Cursor, Item>
) throws -> PDTListPaginationResult<Item> {
    var cursor = initialCursor
    var items: [Item] = []
    var pageCount = 0
    while true {
        guard now() < deadline else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        let page: PDTListPage<Cursor, Item>
        do {
            page = try fetchPage(cursor)
        } catch {
            guard now() >= deadline, treatErrorAsDeadline(error) else {
                throw error
            }
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        pageCount += 1
        items.append(contentsOf: page.items)
        // Empty pages terminate even when stale server metadata claims more.
        guard !page.items.isEmpty, let nextCursor = page.nextCursor else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: nil)
        }
        guard pageCount < maxPages else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .pageCap)
        }
        guard now() < deadline else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        cursor = nextCursor
    }
}

private func pdtPaginationErrorIsRetryable(_ error: Error) -> Bool {
    if let wrapped = error as? PDTDetailRefreshToolError {
        return wrapped.diagnostic.category.isRetryable
    }
    return pdtDetailRefreshFailureCategory(for: error).isRetryable
}

public struct PDTBackgroundDetailRefreshOptions: Equatable, Sendable {
    public var priceHistoryConcurrencyLimit: Int
    public var priceHistoryTimeoutSeconds: Double
    public var incomeQuoteLookupTimeoutSeconds: Double
    public var paginationTimeoutSeconds: Double
    public var maxPagesPerList: Int
    /// Extra refresh-layer retries. Keep this at zero because the connector
    /// owns retry classification. Setting it to N composes multiplicatively:
    /// `(N + 1) * connector max attempts` CLI runs, capped by the phase deadline.
    public var optionalRetryCount: Int
    public var retryBackoffSeconds: Double

    public init(
        priceHistoryConcurrencyLimit: Int = 4,
        priceHistoryTimeoutSeconds: Double = 240,
        incomeQuoteLookupTimeoutSeconds: Double = 240,
        paginationTimeoutSeconds: Double = 240,
        maxPagesPerList: Int = 50,
        optionalRetryCount: Int = 0,
        retryBackoffSeconds: Double = 0.35
    ) {
        self.priceHistoryConcurrencyLimit = max(1, priceHistoryConcurrencyLimit)
        self.priceHistoryTimeoutSeconds = max(0.01, priceHistoryTimeoutSeconds)
        self.incomeQuoteLookupTimeoutSeconds = max(0.01, incomeQuoteLookupTimeoutSeconds)
        self.paginationTimeoutSeconds = max(0.01, paginationTimeoutSeconds)
        self.maxPagesPerList = min(pdtMaximumPagesPerList, max(1, maxPagesPerList))
        self.optionalRetryCount = max(0, optionalRetryCount)
        self.retryBackoffSeconds = max(0, retryBackoffSeconds)
    }

    public func effectivePriceHistoryTimeoutSeconds(holdingCount: Int) -> Double {
        guard priceHistoryTimeoutSeconds >= 240 else {
            return priceHistoryTimeoutSeconds
        }
        let waveCount = Int(ceil(Double(max(0, holdingCount)) / Double(priceHistoryConcurrencyLimit)))
        return max(priceHistoryTimeoutSeconds, Double(waveCount) * 30.0)
    }

    public var effectivePaginationTimeoutSeconds: Double {
        paginationTimeoutSeconds
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
    private let now: @Sendable () -> Date

    public init(
        connector: any PDTMCPConnector,
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        asOf: String? = nil,
        options: PDTBackgroundDetailRefreshOptions = PDTBackgroundDetailRefreshOptions(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.connector = connector
        self.snapshotStore = snapshotStore
        self.pulseReadStore = pulseReadStore
        self.asOf = asOf
        self.options = options
        self.now = now
    }

    public func refresh(
        cancellation: PDTCancellation? = nil,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void = { _ in }
    ) throws -> PDTBackgroundDetailRefreshResult {
        let cancellation = cancellation ?? PDTCancellation()
        try throwIfCancelled(
            cancellation,
            tool: "pdt-get-portfolio-holdings",
            phase: .baseHoldings
        )
        try? snapshotStore.clearLastDetailRefreshDiagnostic()
        progress(BackgroundDetailRefreshProgress(phase: .baseHoldings, detail: "Checking PDT tools"))
        let requiredTools = [
            "pdt-get-portfolio-holdings",
            "pdt-get-portfolio-distributions",
            "pdt-list-x-ray-holdings",
            "pdt-list-calendar-events",
            "pdt-list-dividends",
            "pdt-list-symbol-prices",
            "pdt-get-symbol-quote",
        ]
        let availableTools = try availableReadTools(
            required: Set(requiredTools + PDTReadTools.performance),
            cancellation: cancellation,
            progress: progress
        )
        let missing = requiredTools.filter { !availableTools.contains($0) }
        guard missing.isEmpty else {
            throw PDTMCPConnectorError.missingRequiredReadTools(missing)
        }

        let snapshotAsOf = asOf ?? currentDayString()
        let originalPriorSnapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        let originalPriorSnapshot = originalPriorSnapshotLoad.snapshot
        var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []
        var snapshot: PortfolioSnapshot
        do {
            snapshot = try baseSnapshot(
                asOf: snapshotAsOf,
                cancellation: cancellation,
                progress: progress
            )
        } catch {
            try throwIfCancelled(
                cancellation,
                tool: "pdt-get-portfolio-holdings",
                phase: .baseHoldings
            )
            try snapshotStore.saveLastDetailRefreshDiagnostic(
                diagnostic(for: error, tool: "pdt-get-portfolio-holdings", phase: .baseHoldings)
            )
            throw error
        }
        try throwIfCancelled(
            cancellation,
            tool: "pdt-get-portfolio-holdings",
            phase: .baseHoldings
        )
        preserveOptionalDetails(in: &snapshot, from: originalPriorSnapshot)
        _ = try snapshotStore.commitCurrentSnapshot(snapshot)

        // Once one optional phase fails because Claude/PDT is unavailable
        // (auth or setup outage), every remaining phase would burn the same
        // full Claude CLI runs on the same outage, so they are skipped and the
        // refresh degrades with the unavailable diagnostic instead.
        var skipRemainingPhasesForUnavailableSetup = false
        func recordOptionalPhaseFailure(
            _ error: Error,
            tool: String,
            phase: BackgroundDetailRefreshPhase,
            arguments: [String: String] = [:]
        ) {
            let failure = diagnostic(for: error, tool: tool, phase: phase, arguments: arguments)
            diagnostics.append(failure)
            if failure.category.indicatesUnavailableSetup {
                skipRemainingPhasesForUnavailableSetup = true
            }
        }

        if !skipRemainingPhasesForUnavailableSetup {
            do {
                progress(BackgroundDetailRefreshProgress(phase: .allocation))
                let distributions: LiveDistributionsEnvelope = try callDecodedWithRetry(
                    "pdt-get-portfolio-distributions",
                    phase: .allocation,
                    arguments: [:],
                    progress: progress,
                    retryDeadline: now().addingTimeInterval(options.effectivePaginationTimeoutSeconds),
                    cancellation: cancellation
                )
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-get-portfolio-distributions",
                    phase: .allocation
                )
                let normalized = PDTOptionalDetailNormalizer.normalizeDistributions(distributions.optionalDetailInput)
                snapshot.sectors = normalized.sectors
                snapshot.assetTypes = normalized.assetTypes
                _ = try snapshotStore.commitCurrentSnapshot(snapshot)
            } catch {
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-get-portfolio-distributions",
                    phase: .allocation
                )
                recordOptionalPhaseFailure(error, tool: "pdt-get-portfolio-distributions", phase: .allocation)
            }
        }

        if !skipRemainingPhasesForUnavailableSetup {
            do {
                progress(BackgroundDetailRefreshProgress(phase: .xRay))
                let xRay = try xRayHoldings(
                    cancellation: cancellation,
                    progress: progress
                )
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-list-x-ray-holdings",
                    phase: .xRay
                )
                snapshot.xRayHoldings = PDTOptionalDetailNormalizer.normalizeXRayHoldings(xRay.holdings)
                _ = try snapshotStore.commitCurrentSnapshot(snapshot)
                if let diagnostic = xRay.diagnostic {
                    diagnostics.append(diagnostic)
                }
            } catch {
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-list-x-ray-holdings",
                    phase: .xRay
                )
                recordOptionalPhaseFailure(error, tool: "pdt-list-x-ray-holdings", phase: .xRay, arguments: [
                    "limit": "",
                    "offset": "",
                ])
            }
        }

        if !skipRemainingPhasesForUnavailableSetup {
            do {
                progress(BackgroundDetailRefreshProgress(phase: .income))
                let income = try incomeEvents(
                    asOf: snapshotAsOf,
                    holdings: snapshot.openHoldings,
                    priorSnapshot: originalPriorSnapshot,
                    cancellation: cancellation,
                    progress: progress
                )
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-list-calendar-events",
                    phase: .income
                )
                snapshot.incomeEvents = income.events
                snapshot.dividendRowCount = income.dividendRowCount
                _ = try snapshotStore.commitCurrentSnapshot(snapshot)
                diagnostics.append(contentsOf: income.diagnostics)
            } catch {
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-list-calendar-events",
                    phase: .income
                )
                recordOptionalPhaseFailure(error, tool: "pdt-list-calendar-events", phase: .income)
            }
        }

        if !skipRemainingPhasesForUnavailableSetup {
            progress(BackgroundDetailRefreshProgress(
                phase: .priceHistory,
                completedUnitCount: 0,
                totalUnitCount: snapshot.openHoldings.count
            ))
            let priceHistory = priceSeries(
                for: snapshot.openHoldings,
                asOf: snapshotAsOf,
                cancellation: cancellation,
                progress: progress
            )
            try throwIfCancelled(
                cancellation,
                tool: "pdt-list-symbol-prices",
                phase: .priceHistory
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
        }
        if !skipRemainingPhasesForUnavailableSetup,
           Set(PDTReadTools.performance).isSubset(of: availableTools)
        {
            do {
                progress(BackgroundDetailRefreshProgress(phase: .performance))
                let performance = try performanceSummary(
                    cancellation: cancellation,
                    progress: progress
                )
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-get-portfolio-performance",
                    phase: .performance
                )
                snapshot.performance = performance
                _ = try snapshotStore.commitCurrentSnapshot(snapshot)
            } catch {
                try throwIfCancelled(
                    cancellation,
                    tool: "pdt-get-portfolio-performance",
                    phase: .performance
                )
                snapshot.performance = nil
                let failure = diagnostic(
                    for: error,
                    tool: "pdt-get-portfolio-performance",
                    phase: .performance
                )
                if failure.category == .timeout {
                    diagnostics.append(failure)
                }
                progress(BackgroundDetailRefreshProgress(phase: .performance, detail: "Performance unavailable"))
            }
        } else {
            progress(BackgroundDetailRefreshProgress(phase: .performance, detail: "Performance unavailable"))
        }
        try throwIfCancelled(
            cancellation,
            tool: "pdt-get-portfolio-performance",
            phase: .performance
        )
        let outcome: PDTBackgroundDetailRefreshOutcome = diagnostics.isEmpty ? .completed : .degraded
        let pulse = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: originalPriorSnapshot,
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            detailRefreshOutcome: outcome,
            detailRefreshDiagnostic: diagnostics.last,
            priorSnapshotLoadStatus: originalPriorSnapshotLoad.status
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
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> PortfolioSnapshot {
        progress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        let holdingsEnvelope: LiveHoldingsEnvelope = try callDecodedWithRetry(
            "pdt-get-portfolio-holdings",
            phase: .baseHoldings,
            arguments: [:],
            progress: progress,
            retryDeadline: now().addingTimeInterval(options.effectivePaginationTimeoutSeconds),
            cancellation: cancellation
        )
        let holdingInputs = holdingsEnvelope.holdings.map(\.baseHoldingInput)
        let portfolioCurrency = PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR")
        return PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: portfolioCurrency,
                holdings: holdingInputs
            )
        )
    }

    private func availableReadTools(
        required: Set<String>,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> Set<String> {
        if let progressReportingConnector = connector as? any PDTMCPConnectorProgressReporting {
            return try progressReportingConnector.availableReadTools(
                required: required,
                cancellation: cancellation
            ) { detail in
                progress(BackgroundDetailRefreshProgress(phase: .baseHoldings, detail: detail))
            }
        }
        try throwIfCancelled(
            cancellation,
            tool: "pdt-get-portfolio-holdings",
            phase: .baseHoldings
        )
        let tools = try connector.availableReadTools(required: required)
        try throwIfCancelled(
            cancellation,
            tool: "pdt-get-portfolio-holdings",
            phase: .baseHoldings
        )
        return tools
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
        // Performance is period-bound to the latest report date. Do not carry
        // an older period forward as if it described the refreshed portfolio.
        snapshot.latestCompleteDetailFillAsOf = priorSnapshot.latestCompleteDetailFillAsOf
    }

    private func performanceSummary(
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> PortfolioPerformanceSummary {
        progress(BackgroundDetailRefreshProgress(phase: .performance, detail: "Calling pdt-get-portfolio-performance"))
        let performance: LivePortfolioPerformanceEnvelope = try callPerformanceDecoded(
            "pdt-get-portfolio-performance",
            arguments: [:],
            cancellation: cancellation
        )
        guard let periodStart = performance.oldestPortfolioDate,
              let periodEnd = performance.latestPortfolioDate
        else {
            return PortfolioPerformanceSummary()
        }
        progress(BackgroundDetailRefreshProgress(phase: .performance, detail: "Calling pdt-get-portfolio-gains"))
        let gains: LivePortfolioGainsEnvelope = try callPerformanceDecoded(
            "pdt-get-portfolio-gains",
            arguments: ["date_from": periodStart, "date_to": periodEnd],
            cancellation: cancellation
        )
        return PortfolioPerformanceSummary.build(
            totalGainPercentage: gains.totalGainsPercentage,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }

    private func callPerformanceDecoded<T: Decodable>(
        _ tool: String,
        arguments: [String: String],
        cancellation: PDTCancellation
    ) throws -> T {
        do {
            return try callDecoded(
                tool,
                arguments: arguments,
                cancellation: cancellation
            )
        } catch {
            throw PDTDetailRefreshToolError(diagnostic: diagnostic(
                for: error,
                tool: tool,
                phase: .performance,
                arguments: arguments
            ))
        }
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

    private func xRayHoldings(
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> (holdings: [PDTXRayHoldingInput], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let limit = 500
        let deadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        let pagination = try paginatePDTList(
            initialCursor: 0,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { offset in
            let arguments = ["limit": String(limit), "offset": String(offset)]
            progress(BackgroundDetailRefreshProgress(phase: .xRay, detail: "Fetching pdt-list-x-ray-holdings batch \(offset / limit + 1)"))
            let envelope: XRayHoldingsEnvelope = try callDecodedWithRetry(
                "pdt-list-x-ray-holdings",
                phase: .xRay,
                arguments: arguments,
                progress: progress,
                retryDeadline: deadline,
                cancellation: cancellation
            )
            return PDTListPage(
                items: envelope.items.map(\.optionalDetailInput),
                nextCursor: envelope.hasMore == true ? offset + limit : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-x-ray-holdings",
                phase: .xRay,
                argumentShape: ["limit", "offset"]
            )
        )
    }

    private func incomeEvents(
        asOf snapshotAsOf: String,
        holdings: [NormalizedHolding],
        priorSnapshot: PortfolioSnapshot?,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> (events: [IncomeEventSummary], dividendRowCount: Int, diagnostics: [PDTDetailRefreshFailureDiagnostic]) {
        let incomeDateRange = [
            "date_from": snapshotAsOf,
            "date_to": dayString(snapshotAsOf, addingDays: 30),
        ]
        let dividendDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -370),
            "date_to": incomeDateRange["date_to"] ?? snapshotAsOf,
        ]
        let paginationDeadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        let calendarPagination = try liveCalendarEvents(
            arguments: incomeDateRange,
            deadline: paginationDeadline,
            cancellation: cancellation,
            progress: progress
        )
        let dividendPagination = try liveDividends(
            arguments: dividendDateRange,
            deadline: paginationDeadline,
            cancellation: cancellation,
            progress: progress
        )
        let calendarEvents = calendarPagination.events.filter { $0.type != "no-events-today" }
        let quoteLookup = try incomeQuoteIDsBySymbolID(
            for: calendarEvents,
            holdings: holdings,
            priorSnapshot: priorSnapshot,
            cancellation: cancellation,
            progress: progress
        )
        let normalized = PDTOptionalDetailNormalizer.normalizeIncomeEvents(
            calendarEvents: calendarEvents.map(\.optionalDetailInput),
            dividends: dividendPagination.dividends.map(\.optionalDetailInput),
            quoteIDsBySymbolID: quoteLookup.quoteIDsBySymbolID
        )
        return (
            events: normalized.events,
            dividendRowCount: normalized.dividendRowCount,
            diagnostics: [calendarPagination.diagnostic, dividendPagination.diagnostic]
                .compactMap { $0 } + quoteLookup.diagnostics
        )
    }

    private func liveCalendarEvents(
        arguments baseArguments: [String: String],
        deadline: Date,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> (events: [LiveCalendarEvent], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            progress(BackgroundDetailRefreshProgress(phase: .income, detail: "Fetching pdt-list-calendar-events page \(page)"))
            let envelope: LiveCalendarEventsEnvelope = try callDecodedWithRetry(
                "pdt-list-calendar-events",
                phase: .income,
                arguments: arguments,
                progress: progress,
                retryDeadline: deadline,
                cancellation: cancellation
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-calendar-events",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
    }

    private func incomeQuoteIDsBySymbolID(
        for calendarEvents: [LiveCalendarEvent],
        holdings: [NormalizedHolding],
        priorSnapshot: PortfolioSnapshot?,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> (quoteIDsBySymbolID: [Int: Int], diagnostics: [PDTDetailRefreshFailureDiagnostic]) {
        let neededSymbolIDs = Set(calendarEvents.compactMap(\.symbolId))
        guard !neededSymbolIDs.isEmpty else {
            return ([:], [])
        }
        let holdingQuoteIDsByName = Dictionary(
            grouping: holdings,
            by: { normalizedIncomeSymbolName($0.name) }
        ).compactMapValues { matches -> Int? in
            matches.count == 1 ? matches[0].quoteId : nil
        }
        let currentQuoteIDs = Set(holdings.map(\.quoteId))
        var quoteIDsBySymbolID = calendarEvents.reduce(into: [Int: Int]()) { result, event in
            guard let symbolId = event.symbolId,
                  neededSymbolIDs.contains(symbolId),
                  let symbolName = event.symbolName,
                  let quoteId = holdingQuoteIDsByName[normalizedIncomeSymbolName(symbolName)]
            else {
                return
            }
            result[symbolId] = quoteId
        }
        if let priorSnapshot {
            priorSnapshot.incomeEvents.forEach { event in
                guard let symbolId = event.symbolId,
                      neededSymbolIDs.contains(symbolId),
                      quoteIDsBySymbolID[symbolId] == nil,
                      let quoteId = event.quoteId,
                      currentQuoteIDs.contains(quoteId)
                else {
                    return
                }
                quoteIDsBySymbolID[symbolId] = quoteId
            }
        }
        var unresolvedSymbolIDs = neededSymbolIDs.subtracting(quoteIDsBySymbolID.keys)
        guard !unresolvedSymbolIDs.isEmpty else {
            return (quoteIDsBySymbolID, [])
        }
        // The sequential per-holding scan is one full Claude CLI run per quote
        // lookup, so it is deadline-bounded like the price-history phase; on
        // timeout the phase keeps the partial mapping and degrades instead of
        // holding the whole refresh in "Syncing". The deadline is checked
        // between lookups and before every retry, so one in-flight call may
        // overshoot it by at most the connector's own budget; that keeps the
        // scan bounded without parking another thread per refresh in a timed
        // group wait.
        let deadline = now().addingTimeInterval(options.incomeQuoteLookupTimeoutSeconds)
        for holding in holdings {
            guard !unresolvedSymbolIDs.isEmpty else {
                break
            }
            guard now() < deadline else {
                return (quoteIDsBySymbolID, [Self.incomeQuoteScanTimeoutDiagnostic()])
            }
            let quote: LiveSymbolQuoteEnvelope
            do {
                quote = try callDecodedWithRetry(
                    "pdt-get-symbol-quote",
                    phase: .income,
                    arguments: ["id": String(holding.quoteId)],
                    progress: progress,
                    retryDeadline: deadline,
                    cancellation: cancellation
                )
            } catch {
                // A transient lookup failure once the budget ran out degrades
                // the scan like any other deadline hit. Non-transient
                // failures (auth/setup outages, decode mismatches) keep their
                // real diagnostics even past the deadline so the caller can
                // classify them and short-circuit the remaining phases.
                let category = (error as? PDTDetailRefreshToolError)?.diagnostic.category
                if now() >= deadline, category?.isRetryable == true {
                    return (quoteIDsBySymbolID, [Self.incomeQuoteScanTimeoutDiagnostic()])
                }
                throw error
            }
            guard unresolvedSymbolIDs.remove(quote.symbolId) != nil else {
                continue
            }
            quoteIDsBySymbolID[quote.symbolId] = quote.id
        }
        return (quoteIDsBySymbolID, [])
    }

    private static func incomeQuoteScanTimeoutDiagnostic() -> PDTDetailRefreshFailureDiagnostic {
        PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-get-symbol-quote",
            phase: .income,
            attemptCount: 1,
            category: .timeout,
            argumentShape: ["id"]
        )
    }

    private func normalizedIncomeSymbolName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func liveDividends(
        arguments baseArguments: [String: String],
        deadline: Date,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> (dividends: [LiveDividend], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            progress(BackgroundDetailRefreshProgress(phase: .income, detail: "Fetching pdt-list-dividends page \(page)"))
            let envelope: LiveDividendsEnvelope = try callDecodedWithRetry(
                "pdt-list-dividends",
                phase: .income,
                arguments: arguments,
                progress: progress,
                retryDeadline: deadline,
                cancellation: cancellation
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-dividends",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
    }

    private func priceSeries(
        for holdings: [NormalizedHolding],
        asOf snapshotAsOf: String,
        cancellation: PDTCancellation,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) -> (points: [PricePoint], diagnostics: [PDTDetailRefreshFailureDiagnostic], failedQuoteIDs: Set<Int>) {
        let priceDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -7),
            "date_to": snapshotAsOf,
        ]
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "PDTBarCore.background-detail.price-history", attributes: .concurrent)
        let totalCount = holdings.count
        let quoteIDs = holdings.map(\.quoteId)
        let accumulator = PDTPriceHistoryAccumulator()
        let workTracker = PDTPriceHistoryWorkTracker(quoteIDs: quoteIDs)
        let priceCancellation = PDTCancellation(parent: cancellation)
        let workerCount = min(options.priceHistoryConcurrencyLimit, quoteIDs.count)
        let timeoutSeconds = options.effectivePriceHistoryTimeoutSeconds(holdingCount: totalCount)
        let deadline = now().addingTimeInterval(timeoutSeconds)

        for _ in 0 ..< workerCount {
            group.enter()
            queue.async { [self] in
                defer {
                    group.leave()
                }
                // Stop pulling new holdings once any price call reports a
                // Claude/PDT auth or setup outage; the remaining holdings
                // would each burn another doomed full CLI run.
                while now() < deadline,
                      !priceCancellation.isCancelled,
                      accumulator.unavailableSetupCategory() == nil,
                      let quoteID = workTracker.nextQuoteID()
                {
                    let arguments = priceDateRange.merging([
                        "symbol_quote_id": String(quoteID),
                    ]) { _, new in new }
                    do {
                        let prices: LivePricesEnvelope = try callDecodedWithRetry(
                            "pdt-list-symbol-prices",
                            phase: .priceHistory,
                            arguments: arguments,
                            progress: { detailProgress in
                                progress(BackgroundDetailRefreshProgress(
                                    phase: .priceHistory,
                                    detail: detailProgress.detail,
                                    completedUnitCount: accumulator.completedCount(),
                                    totalUnitCount: totalCount
                                ))
                            },
                            retryDeadline: deadline,
                            cancellation: priceCancellation
                        )
                        let nextPoints = PDTOptionalDetailNormalizer.normalizePriceSeries(
                            prices.data.map(\.optionalDetailInput)
                        )
                        if workTracker.complete(quoteID, record: {
                            accumulator.append(points: nextPoints)
                        }) {
                            let progressValue = accumulator.markCompleted()
                            progress(BackgroundDetailRefreshProgress(
                                phase: .priceHistory,
                                completedUnitCount: progressValue,
                                totalUnitCount: totalCount
                            ))
                        }
                    } catch {
                        let diagnostic = diagnostic(
                            for: error,
                            tool: "pdt-list-symbol-prices",
                            phase: .priceHistory,
                            arguments: arguments
                        )
                        if workTracker.complete(quoteID, record: {
                            accumulator.append(diagnostic: diagnostic, failedQuoteID: quoteID)
                        }) {
                            let progressValue = accumulator.markCompleted()
                            progress(BackgroundDetailRefreshProgress(
                                phase: .priceHistory,
                                completedUnitCount: progressValue,
                                totalUnitCount: totalCount
                            ))
                        }
                    }
                }
            }
        }
        let timedOut = group.wait(timeout: .now() + timeoutSeconds) == .timedOut
            || now() >= deadline
        let cancelled = cancellation.isCancelled
        let unavailableSetupCategory = accumulator.unavailableSetupCategory()
        var abandonedQuoteIDs: [Int] = []
        if timedOut || cancelled {
            priceCancellation.cancel()
            abandonedQuoteIDs = workTracker.markAbandoned()
            // The command runner polls cancellation before allowing its
            // existing two-second SIGTERM grace. Leave enough room for that
            // sweep to reach SIGKILL before the refresh completion can fire.
            _ = group.wait(timeout: .now() + 3.0)
        } else if unavailableSetupCategory != nil {
            abandonedQuoteIDs = workTracker.markAbandoned()
        }
        if !abandonedQuoteIDs.isEmpty {
            let abandonedCategory = unavailableSetupCategory ?? .timeout
            for quoteID in abandonedQuoteIDs {
                let arguments = priceDateRange.merging([
                    "symbol_quote_id": String(quoteID),
                ]) { _, new in new }
                accumulator.append(
                    diagnostic: PDTDetailRefreshFailureDiagnostic(
                        toolName: "pdt-list-symbol-prices",
                        phase: .priceHistory,
                        attemptCount: 1,
                        category: abandonedCategory,
                        argumentShape: arguments.keys.sorted()
                    ),
                    failedQuoteID: quoteID
                )
                let progressValue = accumulator.markCompleted()
                progress(BackgroundDetailRefreshProgress(
                    phase: .priceHistory,
                    completedUnitCount: progressValue,
                    totalUnitCount: totalCount
                ))
            }
        }
        return accumulator.result()
    }

    private func callDecoded<T: Decodable>(
        _ tool: String,
        arguments: [String: String],
        retryDeadline: Date? = nil,
        cancellation: PDTCancellation
    ) throws -> T {
        let connectorDeadline = retryDeadline.map {
            Date().addingTimeInterval(max(0, $0.timeIntervalSince(now())))
        }
        let result = try connector.callReadToolReportingAttempts(
            tool,
            arguments: arguments,
            retryDeadline: connectorDeadline,
            cancellation: cancellation
        )
        do {
            return try decodeLiveTool(tool, data: result.data)
        } catch {
            throw PDTMCPConnectorCallFailure(
                underlyingError: error,
                attemptCount: result.attemptCount
            )
        }
    }

    private func callDecodedWithRetry<T: Decodable>(
        _ tool: String,
        phase: BackgroundDetailRefreshPhase,
        arguments: [String: String],
        progress: (@Sendable (BackgroundDetailRefreshProgress) -> Void)? = nil,
        retryDeadline: Date,
        cancellation: PDTCancellation
    ) throws -> T {
        var outerAttempts = 0
        var totalAttempts = 0
        while true {
            try throwIfCancelled(
                cancellation,
                tool: tool,
                phase: phase,
                attempts: totalAttempts,
                arguments: arguments
            )
            guard now() < retryDeadline else {
                throw PDTDetailRefreshToolError(diagnostic: PDTDetailRefreshFailureDiagnostic(
                    toolName: tool,
                    phase: phase,
                    attemptCount: totalAttempts,
                    category: .timeout,
                    argumentShape: arguments.keys.sorted()
                ))
            }
            outerAttempts += 1
            let detail = outerAttempts == 1 ? "Calling \(tool)" : "Retrying \(tool)"
            progress?(BackgroundDetailRefreshProgress(phase: phase, detail: detail))
            do {
                return try callDecoded(
                    tool,
                    arguments: arguments,
                    retryDeadline: retryDeadline,
                    cancellation: cancellation
                )
            } catch {
                totalAttempts += (error as? PDTMCPConnectorCallFailure)?.attemptCount ?? 1
                let failure = diagnostic(
                    for: error,
                    tool: tool,
                    phase: phase,
                    attempts: totalAttempts,
                    arguments: arguments
                )
                // The connector owns retry by default. This optional outer
                // layer remains available for explicit callers, but never
                // starts another composed call after the phase deadline.
                guard outerAttempts <= options.optionalRetryCount,
                      failure.category.isRetryable,
                      !cancellation.isCancelled,
                      now() < retryDeadline
                else {
                    throw PDTDetailRefreshToolError(diagnostic: failure)
                }
                // The backoff never sleeps past the caller's deadline, and a
                // backoff that lands on the deadline ends the attempt instead
                // of launching another full run past the budget.
                if options.retryBackoffSeconds > 0 {
                    let remainingBudget = max(0, retryDeadline.timeIntervalSince(now()))
                    let backoff = min(options.retryBackoffSeconds, remainingBudget)
                    if backoff > 0 {
                        Thread.sleep(forTimeInterval: backoff)
                    }
                }
                try throwIfCancelled(
                    cancellation,
                    tool: tool,
                    phase: phase,
                    attempts: totalAttempts,
                    arguments: arguments
                )
            }
        }
    }

    private func throwIfCancelled(
        _ cancellation: PDTCancellation,
        tool: String,
        phase: BackgroundDetailRefreshPhase,
        attempts: Int = 0,
        arguments: [String: String] = [:]
    ) throws {
        guard cancellation.isCancelled else {
            return
        }
        throw PDTDetailRefreshToolError(diagnostic: PDTDetailRefreshFailureDiagnostic(
            toolName: tool,
            phase: phase,
            attemptCount: attempts,
            category: .timeout,
            argumentShape: arguments.keys.sorted()
        ))
    }

    private func diagnostic(
        for error: Error,
        tool: String,
        phase: BackgroundDetailRefreshPhase,
        attempts: Int? = nil,
        arguments: [String: String] = [:]
    ) -> PDTDetailRefreshFailureDiagnostic {
        if let wrapped = error as? PDTDetailRefreshToolError {
            return wrapped.diagnostic
        }
        let reportedAttempts = attempts
            ?? (error as? PDTMCPConnectorCallFailure)?.attemptCount
            ?? 1
        return PDTDetailRefreshFailureDiagnostic(
            toolName: tool,
            phase: phase,
            attemptCount: reportedAttempts,
            category: pdtDetailRefreshFailureCategory(for: error),
            argumentShape: arguments.keys.sorted()
        )
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
    private var firstUnavailableSetupCategory: PDTDetailRefreshFailureCategory?

    func markCompleted() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        completed += 1
        return completed
    }

    func completedCount() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return completed
    }

    func unavailableSetupCategory() -> PDTDetailRefreshFailureCategory? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return firstUnavailableSetupCategory
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
        if firstUnavailableSetupCategory == nil, diagnostic.category.indicatesUnavailableSetup {
            firstUnavailableSetupCategory = diagnostic.category
        }
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

private final class PDTPriceHistoryWorkTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingQuoteIDs: [Int]
    private var runningQuoteIDs: Set<Int> = []
    private var finishedQuoteIDs: Set<Int> = []
    private var abandonedQuoteIDs: Set<Int> = []

    init(quoteIDs: [Int]) {
        pendingQuoteIDs = quoteIDs.reversed()
    }

    func nextQuoteID() -> Int? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let quoteID = pendingQuoteIDs.popLast() else {
            return nil
        }
        runningQuoteIDs.insert(quoteID)
        return quoteID
    }

    func complete(_ quoteID: Int, record: () -> Void) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        runningQuoteIDs.remove(quoteID)
        guard !abandonedQuoteIDs.contains(quoteID), finishedQuoteIDs.insert(quoteID).inserted else {
            return false
        }
        record()
        return true
    }

    func markAbandoned() -> [Int] {
        lock.lock()
        defer {
            lock.unlock()
        }
        let unfinished = Set(pendingQuoteIDs)
            .union(runningQuoteIDs)
            .subtracting(finishedQuoteIDs)
            .subtracting(abandonedQuoteIDs)
        pendingQuoteIDs.removeAll()
        runningQuoteIDs.subtract(unfinished)
        abandonedQuoteIDs.formUnion(unfinished)
        return unfinished.sorted()
    }
}

public enum PDTIncomeQuoteLookupScope: Equatable, Sendable {
    case allOpenHoldings
    case calendarSymbolIDs
}

public struct PDTLiveDataSourceOptions: Equatable, Sendable {
    public var includeDistributions: Bool
    public var includeXRayHoldings: Bool
    public var includeIncomeEvents: Bool
    public var includeDividends: Bool
    public var includeIncomeQuoteLookups: Bool
    public var includePriceSeries: Bool
    public var paginationTimeoutSeconds: Double
    public var maxPagesPerList: Int
    public var incomeQuoteLookupScope: PDTIncomeQuoteLookupScope

    public init(
        includeDistributions: Bool = true,
        includeXRayHoldings: Bool = true,
        includeIncomeEvents: Bool = true,
        includeDividends: Bool = true,
        includeIncomeQuoteLookups: Bool = true,
        includePriceSeries: Bool = true,
        paginationTimeoutSeconds: Double = 240,
        maxPagesPerList: Int = 50,
        incomeQuoteLookupScope: PDTIncomeQuoteLookupScope = .allOpenHoldings
    ) {
        self.includeDistributions = includeDistributions
        self.includeXRayHoldings = includeXRayHoldings
        self.includeIncomeEvents = includeIncomeEvents
        self.includeDividends = includeDividends
        self.includeIncomeQuoteLookups = includeIncomeQuoteLookups
        self.includePriceSeries = includePriceSeries
        self.paginationTimeoutSeconds = max(0.01, paginationTimeoutSeconds)
        self.maxPagesPerList = min(pdtMaximumPagesPerList, max(1, maxPagesPerList))
        self.incomeQuoteLookupScope = incomeQuoteLookupScope
    }

    public static var firstFetch: PDTLiveDataSourceOptions {
        PDTLiveDataSourceOptions(
            includeDistributions: false,
            includeXRayHoldings: false,
            includeIncomeEvents: false,
            includeDividends: false,
            includeIncomeQuoteLookups: false,
            includePriceSeries: false,
            incomeQuoteLookupScope: .calendarSymbolIDs
        )
    }

    public var effectivePaginationTimeoutSeconds: Double {
        paginationTimeoutSeconds
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
    public var onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)?
    private let now: @Sendable () -> Date

    public init(
        toolClient: any PDTLiveToolClient,
        options: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions(),
        onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.toolClient = toolClient
        self.options = options
        self.onOptionalFacetFailure = onOptionalFacetFailure
        self.now = now
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

        var optionalFacetFailed = false
        var skipRemainingOptionalFacets = false
        func recordOptionalFacetFailure(
            _ error: Error,
            tool: String,
            phase: BackgroundDetailRefreshPhase,
            argumentShape: [String] = []
        ) {
            optionalFacetFailed = true
            let diagnostic = PDTDetailRefreshFailureDiagnostic(
                toolName: tool,
                phase: phase,
                attemptCount: 1,
                category: pdtDetailRefreshFailureCategory(for: error),
                argumentShape: argumentShape
            )
            onOptionalFacetFailure?(diagnostic)
            if diagnostic.category.indicatesUnavailableSetup {
                skipRemainingOptionalFacets = true
            }
        }
        func recordPaginationTruncation(_ diagnostic: PDTDetailRefreshFailureDiagnostic?) {
            guard let diagnostic else {
                return
            }
            optionalFacetFailed = true
            onOptionalFacetFailure?(diagnostic)
        }

        var distributionsEnvelope: LiveDistributionsEnvelope?
        if options.includeDistributions, !skipRemainingOptionalFacets {
            do {
                distributionsEnvelope = try decodeLiveTool(
                    "pdt-get-portfolio-distributions",
                    data: toolClient.callReadTool("pdt-get-portfolio-distributions", arguments: [:])
                )
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-get-portfolio-distributions",
                    phase: .allocation
                )
            }
        }

        var xRayHoldings: [PDTXRayHoldingInput]?
        if options.includeXRayHoldings, !skipRemainingOptionalFacets {
            do {
                let xRay = try liveXRayHoldings()
                xRayHoldings = xRay.holdings
                recordPaginationTruncation(xRay.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-x-ray-holdings",
                    phase: .xRay,
                    argumentShape: ["limit", "offset"]
                )
            }
        }

        let incomePaginationDeadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        var calendarEvents: [LiveCalendarEvent] = []
        if options.includeIncomeEvents, !skipRemainingOptionalFacets {
            do {
                let calendarPagination = try liveCalendarEvents(
                    arguments: incomeDateRange,
                    deadline: incomePaginationDeadline
                )
                calendarEvents = calendarPagination.events
                recordPaginationTruncation(calendarPagination.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-calendar-events",
                    phase: .income,
                    argumentShape: Array(incomeDateRange.keys) + ["page", "per_page"]
                )
            }
        }

        var dividends: [LiveDividend] = []
        if options.includeDividends, !skipRemainingOptionalFacets {
            do {
                let dividendPagination = try liveDividends(
                    arguments: dividendDateRange,
                    deadline: incomePaginationDeadline
                )
                dividends = dividendPagination.dividends
                recordPaginationTruncation(dividendPagination.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-dividends",
                    phase: .income,
                    argumentShape: Array(dividendDateRange.keys) + ["page", "per_page"]
                )
            }
        }

        let holdingInputs = holdingsEnvelope.holdings.map(\.baseHoldingInput)
        let portfolioCurrency = PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR")
        let baseSnapshot = PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: portfolioCurrency,
                holdings: holdingInputs
            )
        )
        let neededCalendarSymbolIDs = Set(calendarEvents.filter { $0.type != "no-events-today" }.compactMap(\.symbolId))
        var quoteMetadata = SymbolQuoteMetadata()
        if options.includeIncomeQuoteLookups, !skipRemainingOptionalFacets {
            do {
                quoteMetadata = try liveSymbolQuoteMetadata(
                    for: baseSnapshot.openHoldings,
                    neededCalendarSymbolIDs: neededCalendarSymbolIDs
                )
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-get-symbol-quote",
                    phase: .income,
                    argumentShape: ["id"]
                )
            }
        }

        var priceSeries: [PDTPriceInput] = []
        if options.includePriceSeries, !skipRemainingOptionalFacets {
            do {
                priceSeries = try livePriceRows(for: baseSnapshot.openHoldings, asOf: snapshotAsOf)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-symbol-prices",
                    phase: .priceHistory,
                    argumentShape: ["date_from", "date_to", "symbol_quote_id"]
                )
            }
        }
        return PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: portfolioCurrency,
                holdings: holdingInputs,
                symbolQuotes: quoteMetadata.snapshotNormalizationInputs,
                distributions: distributionsEnvelope?.optionalDetailInput,
                xRayHoldings: xRayHoldings,
                calendarEvents: calendarEvents.map(\.optionalDetailInput),
                dividends: dividends.map(\.optionalDetailInput),
                priceRows: priceSeries,
                latestDetailFillOutcome: optionalFacetFailed ? .degraded : nil
            )
        )
    }

    private func liveSymbolQuoteMetadata(
        for holdings: [NormalizedHolding],
        neededCalendarSymbolIDs: Set<Int>
    ) throws -> SymbolQuoteMetadata {
        var metadata = SymbolQuoteMetadata()
        var remainingCalendarSymbolIDs = neededCalendarSymbolIDs
        var attemptedSymbolIDs = Set<Int>()
        var isinsBySymbolID: [Int: String] = [:]
        var symbolLookupUnavailable = false
        let lookupHoldings: [NormalizedHolding]
        switch options.incomeQuoteLookupScope {
        case .allOpenHoldings:
            lookupHoldings = holdings
        case .calendarSymbolIDs:
            guard !remainingCalendarSymbolIDs.isEmpty else {
                return metadata
            }
            lookupHoldings = Array(holdings.reversed())
        }
        for holding in lookupHoldings {
            let quote: LiveSymbolQuoteEnvelope = try decodeLiveTool(
                "pdt-get-symbol-quote",
                data: toolClient.callReadTool("pdt-get-symbol-quote", arguments: ["id": String(holding.quoteId)])
            )
            if options.incomeQuoteLookupScope == .calendarSymbolIDs {
                guard remainingCalendarSymbolIDs.remove(quote.symbolId) != nil else {
                    continue
                }
            }
            metadata.quoteIDsBySymbolID[quote.symbolId] = quote.id
            if let code = safePublicIdentifier(quote.code) {
                metadata.codesByQuoteID[quote.id] = code
            }
            if options.incomeQuoteLookupScope == .calendarSymbolIDs, remainingCalendarSymbolIDs.isEmpty {
                break
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
        case PDTLiveDataSourceError.unavailableToolResult,
             PDTLiveDataSourceError.transientUnavailableToolResult:
            return true
        default:
            return false
        }
    }

    private func liveXRayHoldings()
        throws -> (holdings: [PDTXRayHoldingInput], diagnostic: PDTDetailRefreshFailureDiagnostic?)
    {
        let limit = 500
        let deadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        let pagination = try paginatePDTList(
            initialCursor: 0,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { offset in
            let arguments = ["limit": String(limit), "offset": String(offset)]
            let envelope: XRayHoldingsEnvelope = try decodeLiveTool(
                "pdt-list-x-ray-holdings",
                data: toolClient.callReadTool(
                    "pdt-list-x-ray-holdings",
                    arguments: arguments
                )
            )
            return PDTListPage(
                items: envelope.items.map(\.optionalDetailInput),
                nextCursor: envelope.hasMore == true ? offset + limit : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-x-ray-holdings",
                phase: .xRay,
                argumentShape: ["limit", "offset"]
            )
        )
    }

    private func liveCalendarEvents(
        arguments baseArguments: [String: String],
        deadline: Date
    ) throws -> (events: [LiveCalendarEvent], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            let envelope: LiveCalendarEventsEnvelope = try decodeLiveTool(
                "pdt-list-calendar-events",
                data: toolClient.callReadTool("pdt-list-calendar-events", arguments: arguments)
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-calendar-events",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
    }

    private func liveDividends(
        arguments baseArguments: [String: String],
        deadline: Date
    ) throws -> (dividends: [LiveDividend], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            let envelope: LiveDividendsEnvelope = try decodeLiveTool(
                "pdt-list-dividends",
                data: toolClient.callReadTool("pdt-list-dividends", arguments: arguments)
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-dividends",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
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
    /// Rebuilds a pulse from the cached snapshot. Freshness is evaluated
    /// against `today` (defaulting to the current day), never only against the
    /// cached snapshot's own asOf, so a snapshot from a prior day cannot be
    /// relabeled fresh on relaunch. Tests inject `today` for determinism.
    public static func cachedPulse(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        today: String? = nil
    ) throws -> PulseLifecycleResult? {
        let snapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        guard case .loaded(let snapshot) = snapshotLoad else {
            if case .failed(let kind) = snapshotLoad {
                throw PriorSnapshotLoadError(kind: kind)
            }
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
            detailRefreshDiagnostic: cachedDetailRefreshDiagnostic(for: snapshot, snapshotStore: snapshotStore),
            priorSnapshotLoadStatus: snapshotLoad.status,
            today: today ?? currentDayString()
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
        pulseReadStore: PulseReadStore? = nil,
        today: String? = nil
    ) throws -> MenuDescriptor? {
        try cachedPulse(
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            today: today
        )?.descriptor
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
        let priorSnapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        let priorSnapshot = priorSnapshotLoad.snapshot
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
            resetsReappearedReadState: true,
            priorSnapshotLoadStatus: priorSnapshotLoad.status
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
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
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
            detailRefreshDiagnostic: detailRefreshDiagnostic,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus
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
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested,
        today: String? = nil
    ) throws -> PulseLifecycleResult {
        let displayReadState = loadedReadState ?? displayReadState(from: pulseReadStore)
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        var rawModel = PressureEngine.buildModel(
            from: snapshot,
            priorSnapshot: priorSnapshot,
            readState: displayReadState,
            detailRefreshOutcome: effectiveDetailRefreshOutcome,
            today: today
        )
        rawModel.facetSnapshots.dataHealth = DataHealth.build(
            DataHealthInput.default(
                freshness: rawModel.facetSnapshots.freshness,
                pulseSource: source,
                readState: displayReadState,
                detailRefreshOutcome: effectiveDetailRefreshOutcome,
                diagnostic: detailRefreshDiagnostic,
                priorSnapshotLoadStatus: priorSnapshotLoadStatus
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
                diagnostic: detailRefreshDiagnostic,
                priorSnapshotLoadStatus: priorSnapshotLoadStatus
            )
        )
        return PulseLifecycleResult(
            unfilteredModel: rawModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model),
            readState: readState,
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus
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
        switch try loadPriorSnapshotResult() {
        case .missing:
            return nil
        case .loaded(let snapshot):
            return snapshot
        case .failed(let kind):
            throw PriorSnapshotLoadError(kind: kind)
        }
    }

    public func loadPriorSnapshotResult() throws -> PriorSnapshotLoadResult {
        let target = currentSnapshotPath
        guard FileManager.default.fileExists(atPath: target.path) else {
            return .missing
        }
        do {
            try OwnerOnlyLocalStore.protectExistingFile(target)
        } catch {
            return .failed(.io)
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            return .failed(.io)
        }
        do {
            return .loaded(try JSONDecoder().decode(PortfolioSnapshot.self, from: data))
        } catch {
            return .failed(.decode)
        }
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
        PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: asOf,
                currency: payload.meta.portfolioCurrency,
                holdings: rawHoldings.map { $0.baseHoldingInput(copyableIdentifier: nil) },
                reportedTotalValue: payload.meta.portfolioCurrentWorthEUR.map {
                    Money(value: $0, currency: payload.meta.portfolioCurrency)
                },
                symbolQuotes: payload.symbolQuotes.map(\.snapshotNormalizationInput),
                distributions: payload.getPortfolioDistributions?.optionalDetailInput,
                xRayHoldings: payload.listXRayHoldings?.items.map(\.optionalDetailInput),
                calendarEvents: payload.listCalendarEvents?.data.map(\.optionalDetailInput) ?? [],
                dividends: payload.listDividends?.data.map(\.optionalDetailInput) ?? [],
                priceRows: payload.listSymbolPrices?.data.map(\.optionalDetailInput) ?? [],
                performance: PortfolioPerformanceSummary.build(
                    totalGainPercentage: payload.getPortfolioGains?.totalGainsPercentage,
                    periodStart: payload.getPortfolioPerformance?.oldestPortfolioDate,
                    periodEnd: payload.getPortfolioPerformance?.latestPortfolioDate
                )
            )
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
    var getPortfolioPerformance: LivePortfolioPerformanceEnvelope?
    var getPortfolioGains: LivePortfolioGainsEnvelope?

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
        case getPortfolioPerformance
        case getPortfolioGains
    }
}

private struct LivePortfolioPerformanceEnvelope: Decodable {
    var oldestPortfolioDate: String?
    var latestPortfolioDate: String?
}

private struct LivePortfolioGainsEnvelope: Decodable {
    var totalGainsPercentage: Double?
}

private struct LiveHoldingsEnvelope: Decodable {
    var holdings: [LiveHolding]
}

private struct LiveHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
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
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentExchangeRate = try? container.decodeIfPresent(Double.self, forKey: .currentExchangeRate)
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

private extension SymbolQuoteMetadata {
    var snapshotNormalizationInputs: [PDTSymbolQuoteNormalizationInput] {
        quoteIDsBySymbolID.map { symbolId, quoteId in
            PDTSymbolQuoteNormalizationInput(
                quoteId: quoteId,
                symbolId: symbolId,
                copyableIdentifier: codesByQuoteID[quoteId],
                isin: isinsByQuoteID[quoteId]
            )
        }
    }
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
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentExchangeRate = try? container.decodeIfPresent(Double.self, forKey: .currentExchangeRate)
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

private extension SymbolQuoteEnvelope {
    var snapshotNormalizationInput: PDTSymbolQuoteNormalizationInput {
        PDTSymbolQuoteNormalizationInput(
            quoteId: id,
            symbolId: symbolId,
            copyableIdentifier: code
        )
    }
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
    let extraction = extractLiveToolPayload(from: data)
    if let decoded = try? JSONDecoder().decode(T.self, from: extraction.payloadData) {
        return decoded
    }
    let unavailableKind = extraction.unavailableKind ?? unavailableTextPayloadKind(extraction.payloadData)
    if unavailableKind == .authOrSetup {
        throw PDTLiveDataSourceError.unavailableToolResult(tool)
    }
    if unavailableKind == .transient {
        throw PDTLiveDataSourceError.transientUnavailableToolResult(tool)
    }
    throw PDTLiveDataSourceError.malformedToolResult(tool)
}

private struct LiveToolPayloadExtraction {
    var payloadData: Data
    var unavailableKind: PDTLiveUnavailableKind?
}

private struct ExtractedMCPPayload {
    var data: Data
    var unavailableKind: PDTLiveUnavailableKind?
}

private func extractLiveToolPayload(from data: Data) -> LiveToolPayloadExtraction {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
        return LiveToolPayloadExtraction(
            payloadData: data,
            unavailableKind: unavailableTextPayloadKind(data)
        )
    }
    let extracted = extractedMCPPayload(from: object)
    return LiveToolPayloadExtraction(
        payloadData: extracted?.data ?? data,
        unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: object) ?? extracted?.unavailableKind
    )
}

private func extractedMCPPayload(from object: Any) -> ExtractedMCPPayload? {
    if let dictionary = object as? [String: Any] {
        if let content = dictionary["content"] as? [Any] {
            for item in content {
                guard let item = item as? [String: Any],
                      item["type"] as? String == "text",
                      let text = item["text"] as? String,
                      let textData = text.data(using: .utf8)
                else { continue }
                return ExtractedMCPPayload(data: textData, unavailableKind: nil)
            }
        }
        guard let nested = dictionary["result"],
              let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
        else {
            guard let nested = dictionary["data"] as? [String: Any],
                  let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
            else { return nil }
            return ExtractedMCPPayload(
                data: nestedData,
                unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: nested, forceErrorContext: true)
            )
        }
        return ExtractedMCPPayload(
            data: nestedData,
            unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: nested, forceErrorContext: true)
        )
    }
    return nil
}

private func unavailableTextPayload(_ data: Data) -> Bool {
    unavailableTextPayloadKind(data) != nil
}

private func unavailableTextPayloadKind(_ data: Data) -> PDTLiveUnavailableKind? {
    guard let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return PDTLiveUnavailableClassifier.unavailableKind(in: text)
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
