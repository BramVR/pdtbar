import Foundation

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
