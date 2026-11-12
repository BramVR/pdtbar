import Foundation

public enum FreshnessState: String, Codable, Equatable {
    case fresh
    case stale
    case partial
    /// Holdings exist but at least one has no price date.
    case unknown
    /// No open holdings, so there is no price to date.
    case noHoldings
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
    static let noHoldingsDetail = "No holdings to price"
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
        let hasUnknownPriceDates = datedRows.count != snapshot.openHoldings.count
        let stale = !staleRows.isEmpty
        let latestCompleteDetailFillAsOf = effectiveDetailRefreshOutcome == .completed
            ? snapshot.latestCompleteDetailFillAsOf ?? snapshot.asOf
            : snapshot.latestCompleteDetailFillAsOf
        let detailFillIncomplete = effectiveDetailRefreshOutcome == .degraded
            || (latestCompleteDetailFillAsOf != nil && latestCompleteDetailFillAsOf != snapshot.asOf)
        let status: FreshnessState
        if snapshot.openHoldings.isEmpty {
            status = .noHoldings
        } else if hasUnknownPriceDates {
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
    /// The connection is being checked. Set only by `DataHealth.snapshot(_:in:)`.
    case checking
    /// A sync is running. Set only by `DataHealth.snapshot(_:in:)`.
    case refreshing
}

/// Why Data health needs attention, in the order `DataHealth.verdict(of:)` checks.
enum DataHealthAttentionCause: CaseIterable, Equatable, Sendable {
    case notConnected
    case reconnectNeeded
    case subscriptionPaused
    case connectionNotSaved
    case keychainUnavailable
    case detailFillFailed
    case savedCopy
    case notFetched
    case accessNotChecked
    case unknownPriceDates
    case stalePrices
    case detailFillIncomplete
    case failureRecorded

    /// The Data health child row that names this cause.
    var rowID: String {
        switch self {
        case .notConnected, .reconnectNeeded, .subscriptionPaused, .connectionNotSaved, .keychainUnavailable, .accessNotChecked:
            "dataHealth.access"
        case .savedCopy, .notFetched:
            "dataHealth.source"
        case .unknownPriceDates, .stalePrices:
            "dataHealth.freshness"
        case .detailFillFailed, .detailFillIncomplete:
            "dataHealth.detailFill"
        case .failureRecorded:
            "dataHealth.diagnostic"
        }
    }

    func summary(for health: DataHealthSnapshot) -> String {
        switch self {
        case .notConnected: "Not connected"
        case .reconnectNeeded: "Reconnect needed"
        case .subscriptionPaused: "Subscription paused"
        case .connectionNotSaved: "Connection not saved"
        case .keychainUnavailable: "Keychain unavailable"
        case .detailFillFailed: "Detail fill failed"
        case .savedCopy: "Showing a saved copy"
        case .notFetched: "Not fetched this session"
        case .accessNotChecked: "Connection not checked"
        case .unknownPriceDates: "Unknown price dates"
        case .stalePrices:
            switch health.freshness.staleHoldingCount {
            case 1: "1 stale price"
            case let count where count > 1: "\(count) stale prices"
            default: "Stale prices"
            }
        case .detailFillIncomplete: "Detail fill incomplete"
        case .failureRecorded: "Last sync failed"
        }
    }
}

/// `DataHealthStatus` with the cause kept, so attention cannot be shown without one.
enum DataHealthVerdict: Equatable {
    case healthy
    case checking
    case refreshing
    case attention(DataHealthAttentionCause)

    var status: DataHealthStatus {
        switch self {
        case .healthy: .healthy
        case .checking: .checking
        case .refreshing: .refreshing
        case .attention: .degraded
        }
    }
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

/// What PDTBar knows about its PDT connection. No secret, no identifier.
public enum DataHealthAccess: Codable, Equatable, Sendable {
    /// Nothing checked this session: all a pulse built from a saved copy can claim.
    case unverified
    /// Checking, signing in, or disconnecting.
    case checking
    case connected
    case notConnected
    /// The `401` causes and `403 INSUFFICIENT_SCOPE`.
    case reconnect(PDTReconnectCause)
    /// `403 API_ACCESS_PAUSED`.
    case subscriptionPaused
    /// The credential store refused the sign-in or token; PDTBar holds it unsaved.
    case notSaved
    case keychainUnavailable

    /// A pulse fetched in this run just read PDT with the credential; a saved
    /// copy proves nothing about the connection.
    static func assumed(for pulseSource: PulseLifecycleSource?) -> DataHealthAccess {
        switch pulseSource {
        case .fetchedSnapshot, .refreshedSnapshot:
            .connected
        case .cachedSnapshot, nil:
            .unverified
        }
    }

    public init(_ state: PDTLaunchState) {
        switch state {
        case .checkingConnection, .connecting, .disconnecting:
            self = .checking
        case .notConnected:
            self = .notConnected
        case let .needsReconnect(_, cause):
            self = .reconnect(cause)
        case .subscriptionPaused:
            self = .subscriptionPaused
        case .notSaved:
            self = .notSaved
        case .keychainUnavailable:
            self = .keychainUnavailable
        case .connected:
            self = .connected
        }
    }
}

/// What only the running app knows about Data Health. Everything else comes
/// from the pulse.
public struct DataHealthRuntime: Equatable, Sendable {
    public var access: DataHealthAccess
    public var sync: DataHealthSync

    public init(access: DataHealthAccess, sync: DataHealthSync = .idle) {
        self.access = access
        self.sync = sync
    }
}

public enum DataHealthSync: Equatable, Sendable {
    /// The pulse's own detail fill and failure stand.
    case idle
    /// The pulse's last failure stays visible until the sync ends.
    case running(BackgroundDetailRefreshProgress)
    /// Replaces the pulse's failure; nil clears it.
    case failed(PDTSyncFailure?)
}

/// What a pulse knows about its own health when it is built. `default` is the
/// only way to make one, so every pulse derives access from how it was built.
public struct DataHealthInput: Equatable {
    public var access: DataHealthAccess
    public var pulseSource: PulseLifecycleSource?
    /// `asOf` of the committed snapshot: the last sync whose base holdings succeeded.
    public var lastSyncAsOf: String?
    /// The last sync that also filled every detail.
    public var lastCompleteSyncAsOf: String?
    public var priorSnapshotStatus: PriorSnapshotHealthStatus?
    public var detailFill: DataHealthDetailFillInput
    public var freshness: FreshnessSnapshot
    public var readState: PulseReadState?
    public var lastFailure: PDTSyncFailure?

    public static func `default`(
        freshness: FreshnessSnapshot,
        pulseSource: PulseLifecycleSource? = nil,
        snapshotAsOf: String? = nil,
        readState: PulseReadState? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        lastSyncFailure: PDTSyncFailure? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
    ) -> DataHealthInput {
        DataHealthInput(
            access: .assumed(for: pulseSource),
            pulseSource: pulseSource,
            lastSyncAsOf: snapshotAsOf,
            lastCompleteSyncAsOf: freshness.latestCompleteDetailFillAsOf,
            priorSnapshotStatus: priorSnapshotLoadStatus.healthStatus,
            detailFill: detailFillInput(outcome: detailRefreshOutcome, freshness: freshness),
            freshness: freshness,
            readState: readState,
            lastFailure: lastSyncFailure
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
    /// Nil when the pulse did not come through a fetch or the saved copy.
    public var pulse: PulseLifecycleSource?
    public var detail: String
}

public struct DataHealthAccessSnapshot: Codable, Equatable {
    public var state: DataHealthAccess
    public var detail: String
}

public struct DataHealthCacheSnapshot: Codable, Equatable {
    public var lastSyncAsOf: String?
    public var lastCompleteSyncAsOf: String?
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

public struct DataHealthSnapshot: Codable, Equatable {
    public var status: DataHealthStatus
    public var source: DataHealthSourceSnapshot
    public var access: DataHealthAccessSnapshot
    public var cache: DataHealthCacheSnapshot
    public var freshness: DataHealthFreshnessSummary
    public var detailFill: DataHealthDetailFillSnapshot
    public var readState: DataHealthReadStateSnapshot
    public var lastFailure: PDTSyncFailure?
}

public enum DataHealth {
    public static func build(_ input: DataHealthInput) -> DataHealthSnapshot {
        var health = DataHealthSnapshot(
            status: .degraded,
            source: DataHealthSourceSnapshot(
                pulse: input.pulseSource,
                detail: sourceDetail(input.pulseSource, lastSyncAsOf: input.lastSyncAsOf)
            ),
            access: accessSnapshot(input.access),
            cache: DataHealthCacheSnapshot(
                lastSyncAsOf: input.lastSyncAsOf,
                lastCompleteSyncAsOf: input.lastCompleteSyncAsOf,
                priorSnapshotStatus: input.priorSnapshotStatus,
                summary: cacheSummary(lastSyncAsOf: input.lastSyncAsOf, lastCompleteSyncAsOf: input.lastCompleteSyncAsOf)
            ),
            freshness: DataHealthFreshnessSummary(
                status: input.freshness.status,
                staleHoldingCount: input.freshness.staleHoldingCount,
                oldestPriceAsOf: input.freshness.oldestPriceAsOf,
                detail: freshnessDetail(input.freshness)
            ),
            detailFill: detailFillSnapshot(input.detailFill, freshness: input.freshness.status),
            readState: DataHealthReadStateSnapshot(
                readFingerprintCount: input.readState?.readFingerprints.count ?? 0,
                detail: "\(input.readState?.readFingerprints.count ?? 0) read"
            ),
            lastFailure: input.lastFailure
        )
        health.status = verdict(of: health).status
        return health
    }

    /// The pulse's health as the running app sees it. Replaces `access`, and
    /// `detailFill` and `lastFailure` per `sync`. Source, cache, freshness and
    /// read state stay the pulse's own: a sync that did not commit a snapshot
    /// cannot move a date.
    public static func snapshot(_ pulse: DataHealthSnapshot, in runtime: DataHealthRuntime) -> DataHealthSnapshot {
        var health = pulse
        health.access = accessSnapshot(runtime.access)
        switch runtime.sync {
        case .idle:
            break
        case let .running(progress):
            health.detailFill = detailFillSnapshot(.inProgress(progress))
        case let .failed(failure):
            health.detailFill = detailFillSnapshot(.failed)
            health.lastFailure = failure
        }
        health.status = verdict(of: health).status
        return health
    }

    /// "Copy diagnostics" text, or nil when no failure is recorded. Built only
    /// from closed enums, Ints and a validated trace id: it has no dates and
    /// reads none of the snapshot's `detail` strings, which can carry PDT text.
    static func diagnosticsText(for health: DataHealthSnapshot) -> String? {
        guard let failure = health.lastFailure else {
            return nil
        }
        return ([
            "PDTBar data health",
            "source: PDT API, read-only",
            "shown: \(shownLabel(health.source.pulse))",
            "access: \(accessLabel(health.access.state))",
            "detail fill: \(detailFillLabel(health.detailFill.outcome))",
        ] + failure.reportLines).joined(separator: "\n")
    }

    /// The first failing check wins; every switch is exhaustive so a new access,
    /// source, outcome or freshness case must name a cause before it compiles.
    /// A saved copy is never healthy, whatever its prices say: nothing in this
    /// run has read PDT yet.
    static func verdict(of health: DataHealthSnapshot) -> DataHealthVerdict {
        verdict(of: health, countingPriceFreshness: true)
    }

    /// `verdict(of:)` with stale and unknown price dates set aside: what Data
    /// health knows beyond what the Prices row already shows.
    static func verdictBeyondPriceFreshness(of health: DataHealthSnapshot) -> DataHealthVerdict {
        verdict(of: health, countingPriceFreshness: false)
    }

    private static func verdict(of health: DataHealthSnapshot, countingPriceFreshness: Bool) -> DataHealthVerdict {
        switch health.access.state {
        case .checking: return .checking
        case .notConnected: return .attention(.notConnected)
        case .reconnect: return .attention(.reconnectNeeded)
        case .subscriptionPaused: return .attention(.subscriptionPaused)
        case .notSaved: return .attention(.connectionNotSaved)
        case .keychainUnavailable: return .attention(.keychainUnavailable)
        case .unverified, .connected: break
        }
        switch health.detailFill.outcome {
        case .inProgress: return .refreshing
        case .failed: return .attention(.detailFillFailed)
        case .notStarted, .completed, .degraded: break
        }
        switch health.source.pulse {
        case .cachedSnapshot: return .attention(.savedCopy)
        case nil: return .attention(.notFetched)
        case .fetchedSnapshot, .refreshedSnapshot: break
        }
        if health.access.state == .unverified {
            return .attention(.accessNotChecked)
        }
        switch health.freshness.status {
        case .unknown where countingPriceFreshness: return .attention(.unknownPriceDates)
        case .stale where countingPriceFreshness: return .attention(.stalePrices)
        case .partial: return .attention(.detailFillIncomplete)
        case .fresh, .noHoldings, .unknown, .stale: break
        }
        if health.detailFill.outcome == .degraded {
            return .attention(.detailFillIncomplete)
        }
        if health.lastFailure != nil {
            return .attention(.failureRecorded)
        }
        return .healthy
    }

    private static func sourceDetail(_ pulse: PulseLifecycleSource?, lastSyncAsOf: String?) -> String {
        switch pulse {
        case .fetchedSnapshot, .refreshedSnapshot:
            "PDT, read-only; fetched this session"
        case .cachedSnapshot:
            "PDT, read-only; saved copy" + (lastSyncAsOf.map { " from \($0)" } ?? "")
        case nil:
            "PDT, read-only; not fetched this session"
        }
    }

    private static func accessSnapshot(_ state: DataHealthAccess) -> DataHealthAccessSnapshot {
        let detail = switch state {
        case .unverified:
            "Not checked this session"
        case .checking:
            "Checking"
        case .connected:
            "Connected"
        case .notConnected:
            "Not connected"
        case let .reconnect(cause):
            "Reconnect needed: \(PDTLaunchMenu.reconnectReason(cause))"
        case .subscriptionPaused:
            "Paused: your PDT subscription has ended"
        case .notSaved:
            "Not saved on this Mac"
        case .keychainUnavailable:
            "Keychain unavailable"
        }
        return DataHealthAccessSnapshot(state: state, detail: detail)
    }

    private static func cacheSummary(lastSyncAsOf: String?, lastCompleteSyncAsOf: String?) -> String {
        guard let lastSyncAsOf else {
            return "No saved portfolio"
        }
        guard let lastCompleteSyncAsOf, lastCompleteSyncAsOf != lastSyncAsOf else {
            return "Last sync \(lastSyncAsOf)"
        }
        return "Last sync \(lastSyncAsOf); last complete \(lastCompleteSyncAsOf)"
    }

    private static func detailFillSnapshot(
        _ input: DataHealthDetailFillInput,
        freshness: FreshnessState? = nil
    ) -> DataHealthDetailFillSnapshot {
        var snapshot = DataHealthDetailFillSnapshot(
            outcome: .notStarted,
            phase: nil,
            completedUnitCount: nil,
            totalUnitCount: nil,
            asOf: nil,
            detail: "Not started"
        )
        switch input {
        case .notStarted:
            break
        case let .completed(asOf):
            snapshot.outcome = .completed
            snapshot.asOf = asOf
            // `partial` here means the last complete fill predates this sync.
            snapshot.detail = freshness == .partial
                ? asOf.map { "Incomplete; last complete \($0)" } ?? "Incomplete"
                : asOf.map { "Completed \($0)" } ?? "Completed"
        case .degraded:
            snapshot.outcome = .degraded
            snapshot.detail = "Degraded"
        case .failed:
            snapshot.outcome = .failed
            snapshot.detail = "Failed"
        case let .inProgress(progress):
            snapshot.outcome = .inProgress
            snapshot.phase = progress.phase
            snapshot.completedUnitCount = progress.completedUnitCount
            snapshot.totalUnitCount = progress.totalUnitCount
            if let completed = progress.completedUnitCount, let total = progress.totalUnitCount {
                snapshot.detail = "\(progress.phase.title) \(max(0, completed))/\(max(0, total))"
            } else {
                snapshot.detail = progress.phase.title
            }
        }
        return snapshot
    }

    /// `partial` means the detail fill is incomplete, which is the Detail fill
    /// row's fact; the prices themselves are current.
    private static func freshnessDetail(_ freshness: FreshnessSnapshot) -> String {
        let oldest = freshness.oldestPriceAsOf.map { "; oldest \($0)" } ?? ""
        switch freshness.status {
        case .fresh, .partial:
            return "Current\(oldest)"
        case .stale:
            return "\(freshness.staleHoldingCount) stale\(oldest)"
        case .unknown:
            return "Unknown"
        case .noHoldings:
            return FreshnessLedger.noHoldingsDetail
        }
    }

    private static func shownLabel(_ pulse: PulseLifecycleSource?) -> String {
        switch pulse {
        case .fetchedSnapshot, .refreshedSnapshot: "fetched this session"
        case .cachedSnapshot: "saved copy"
        case nil: "not fetched this session"
        }
    }

    private static func accessLabel(_ state: DataHealthAccess) -> String {
        switch state {
        case .unverified: "not checked"
        case .checking: "checking"
        case .connected: "connected"
        case .notConnected: "not connected"
        case .reconnect(.signInExpired): "reconnect needed (sign-in expired)"
        case .reconnect(.tokenExpired): "reconnect needed (token expired)"
        case .reconnect(.tokenRevoked): "reconnect needed (token revoked)"
        case .reconnect(.tokenInvalid): "reconnect needed (token rejected)"
        case .reconnect(.readAccessMissing): "reconnect needed (read access missing)"
        case .subscriptionPaused: "paused"
        case .notSaved: "not saved"
        case .keychainUnavailable: "keychain unavailable"
        }
    }

    private static func detailFillLabel(_ outcome: DataHealthDetailFillOutcome) -> String {
        switch outcome {
        case .notStarted: "not started"
        case .inProgress: "in progress"
        case .completed: "completed"
        case .degraded: "degraded"
        case .failed: "failed"
        }
    }
}
