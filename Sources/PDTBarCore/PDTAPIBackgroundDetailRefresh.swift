import Foundation

public enum PDTBackgroundDetailRefreshOutcome: String, Codable, Equatable, Sendable {
    case completed
    case degraded
}

public struct PDTBackgroundDetailRefreshResult: Equatable {
    public var outcome: PDTBackgroundDetailRefreshOutcome
    public var pulse: PulseLifecycleResult
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
    /// Filled by the Claude refresh only.
    public var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []
    /// Filled by the PDT API refresh only.
    public var failures: [PDTSyncFailure] = []
}

public protocol PDTBackgroundDetailRefreshing: Sendable {
    func refresh(
        cancellation: PDTCancellation?,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void
    ) throws -> PDTBackgroundDetailRefreshResult
}

extension PDTBackgroundDetailRefresh: PDTBackgroundDetailRefreshing {}

/// Background detail refresh over the read-only PDT REST API (ADR-0002).
///
/// Phases run in order and fill one in-memory snapshot. The store is written
/// once, by `PressureRunner.refreshedPulse` after the last phase, so a cancel,
/// a quit, or a failed required base leaves the last good snapshot on disk.
/// A failed optional phase keeps the prior snapshot's facet and degrades the
/// outcome. Once a failure ends the sync (lost access, or a rate limit that
/// outlasts the client's retries), every later phase is skipped, price
/// history included.
public final class PDTAPIBackgroundDetailRefresh: PDTBackgroundDetailRefreshing, @unchecked Sendable {
    private let client: PDTAPIClient
    private let snapshotStore: SnapshotStore
    private let pulseReadStore: PulseReadStore?
    private let asOf: String?
    private let now: @Sendable () -> Date

    public init(
        client: PDTAPIClient,
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        asOf: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.snapshotStore = snapshotStore
        self.pulseReadStore = pulseReadStore
        self.asOf = asOf
        self.now = now
    }

    public func refresh(
        cancellation: PDTCancellation? = nil,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void = { _ in }
    ) throws -> PDTBackgroundDetailRefreshResult {
        let cancellation = cancellation ?? PDTCancellation()
        try throwIfCancelled(cancellation)
        // Cleared first so a refresh that ends without recording a failure
        // (a cancel, a store error) cannot be explained by an older one.
        snapshotStore.setLastSyncFailure(nil)

        let snapshotAsOf = asOf ?? dayString(from: now())
        let priorSnapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        let priorSnapshot = priorSnapshotLoad.snapshot

        progress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        let rows: [APIHolding]
        do {
            rows = try client.getAllReportingAttempts(.holdings(), as: APIHolding.self, cancellation: cancellation).value
        } catch let failure as PDTAPIRequestFailure {
            try throwIfCancelled(cancellation)
            snapshotStore.setLastSyncFailure(PDTSyncFailure(failure, resource: .holdings(), phase: .baseHoldings))
            throw failure.underlyingError
        }
        try throwIfCancelled(cancellation)

        let holdingInputs = rows.map(\.baseHoldingInput)
        var snapshot = PDTSnapshotNormalizer.normalize(PDTSnapshotNormalizationInput(
            asOf: snapshotAsOf,
            currency: PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR"),
            holdings: holdingInputs
        ))
        Self.preserveOptionalDetails(in: &snapshot, from: priorSnapshot)
        let openQuoteIDs = snapshot.openHoldings.map(\.quoteId)

        var failures: [PDTSyncFailure] = []
        var syncEnded = false
        func record(_ failure: PDTSyncFailure) {
            failures.append(failure)
            if failure.kind.endsSync {
                syncEnded = true
            }
        }
        func optionalPhase(_ phase: BackgroundDetailRefreshPhase, _ fill: () throws -> Void) throws {
            guard !syncEnded else {
                return
            }
            progress(BackgroundDetailRefreshProgress(phase: phase))
            do {
                try fill()
            } catch let failed as PhaseFailed {
                record(failed.failure)
            }
            try throwIfCancelled(cancellation)
        }

        try optionalPhase(.allocation) {
            let distributions = try fetch(.distributions, phase: .allocation, cancellation: cancellation) {
                try client.getReportingAttempts(.distributions, as: APIDistributionsEnvelope.self, cancellation: cancellation)
            }
            let normalized = PDTOptionalDetailNormalizer.normalizeDistributions(distributions.optionalDetailInput)
            snapshot.sectors = normalized.sectors
            snapshot.assetTypes = normalized.assetTypes
        }

        try optionalPhase(.xRay) {
            let xRayRows = try fetch(.xRay, phase: .xRay, cancellation: cancellation) {
                try client.getAllReportingAttempts(.xRay, as: APIXRayHolding.self, cancellation: cancellation)
            }
            snapshot.xRayHoldings = PDTOptionalDetailNormalizer.normalizeXRayHoldings(xRayRows.map(\.optionalDetailInput))
        }

        try optionalPhase(.income) {
            let incomeEnd = dayString(snapshotAsOf, addingDays: 30)
            let calendarResource = PDTAPIResource.calendarEvents(dateFrom: snapshotAsOf, dateTo: incomeEnd)
            let calendarEvents = try fetch(calendarResource, phase: .income, cancellation: cancellation) {
                try client.getAllReportingAttempts(calendarResource, as: APICalendarEvent.self, cancellation: cancellation)
            }
            let dividendsResource = PDTAPIResource.dividends(
                dateFrom: dayString(snapshotAsOf, addingDays: -370),
                dateTo: incomeEnd
            )
            let dividends = try fetch(dividendsResource, phase: .income, cancellation: cancellation) {
                try client.getAllReportingAttempts(dividendsResource, as: APIDividend.self, cancellation: cancellation)
            }
            // REST holdings carry symbolId, so income events join to open
            // holdings without the per-holding symbol-quote scan.
            let openQuoteIDSet = Set(openQuoteIDs)
            let quoteIDsBySymbolID = Dictionary(
                rows.compactMap { row in
                    row.symbolId.flatMap { openQuoteIDSet.contains(row.symbolQuoteId) ? ($0, row.symbolQuoteId) : nil }
                },
                uniquingKeysWith: { first, _ in first }
            )
            let income = PDTOptionalDetailNormalizer.normalizeIncomeEvents(
                calendarEvents: calendarEvents.map(\.optionalDetailInput),
                dividends: dividends.map(\.optionalDetailInput),
                quoteIDsBySymbolID: quoteIDsBySymbolID
            )
            snapshot.incomeEvents = income.events
            snapshot.dividendRowCount = income.dividendRowCount
        }

        if !syncEnded {
            progress(BackgroundDetailRefreshProgress(
                phase: .priceHistory,
                completedUnitCount: 0,
                totalUnitCount: openQuoteIDs.count
            ))
            let dateFrom = dayString(snapshotAsOf, addingDays: -7)
            var points: [PricePoint] = []
            var failedQuoteIDs: Set<Int> = []
            var completed = 0
            for start in stride(from: 0, to: openQuoteIDs.count, by: PDTAPIResource.pricesBatchLimit) {
                let chunk = Array(openQuoteIDs[start ..< min(start + PDTAPIResource.pricesBatchLimit, openQuoteIDs.count)])
                let resource = PDTAPIResource.pricesBatch(symbolQuoteIds: chunk, dateFrom: dateFrom, dateTo: snapshotAsOf)
                if syncEnded {
                    failedQuoteIDs.formUnion(chunk)
                } else {
                    do {
                        let batch = try fetch(resource, phase: .priceHistory, cancellation: cancellation) {
                            try client.getReportingAttempts(resource, as: APIPricesBatchEnvelope.self, cancellation: cancellation)
                        }
                        points += PDTOptionalDetailNormalizer.normalizePriceSeries(
                            batch.data.prices.joined().map(\.optionalDetailInput)
                        )
                    } catch let failed as PhaseFailed {
                        record(failed.failure)
                        failedQuoteIDs.formUnion(chunk)
                    }
                }
                completed += chunk.count
                progress(BackgroundDetailRefreshProgress(
                    phase: .priceHistory,
                    completedUnitCount: completed,
                    totalUnitCount: openQuoteIDs.count
                ))
            }
            try throwIfCancelled(cancellation)
            snapshot.priceSeries = Self.priceSeriesWithPriorFallback(
                refreshed: points,
                failedQuoteIDs: failedQuoteIDs,
                priorSnapshot: priorSnapshot,
                currentQuoteIDs: Set(openQuoteIDs)
            ).sorted {
                $0.quoteId != $1.quoteId ? $0.quoteId < $1.quoteId : $0.date < $1.date
            }
        }

        // REST performance and gains shapes are not mapped yet (#246 scope),
        // so this phase reports unavailable without degrading, like a Claude
        // setup whose performance tools are missing.
        progress(BackgroundDetailRefreshProgress(phase: .performance, detail: "Performance unavailable"))
        try throwIfCancelled(cancellation)

        let outcome: PDTBackgroundDetailRefreshOutcome = failures.isEmpty ? .completed : .degraded
        let pulse = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: priorSnapshot,
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            detailRefreshOutcome: outcome,
            lastSyncFailure: failures.last,
            priorSnapshotLoadStatus: priorSnapshotLoad.status
        )
        snapshotStore.setLastSyncFailure(failures.last)
        return PDTBackgroundDetailRefreshResult(
            outcome: outcome,
            pulse: pulse,
            model: pulse.model,
            snapshotCommit: pulse.snapshotCommit,
            descriptor: pulse.descriptor,
            failures: failures
        )
    }

    static func preserveOptionalDetails(in snapshot: inout PortfolioSnapshot, from priorSnapshot: PortfolioSnapshot?) {
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

    static func priceSeriesWithPriorFallback(
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

    private func fetch<T>(
        _ resource: PDTAPIResource,
        phase: BackgroundDetailRefreshPhase,
        cancellation: PDTCancellation,
        _ request: () throws -> PDTAPIResult<T>
    ) throws -> T {
        do {
            return try request().value
        } catch let failure as PDTAPIRequestFailure {
            try throwIfCancelled(cancellation)
            throw PhaseFailed(failure: PDTSyncFailure(failure, resource: resource, phase: phase))
        }
    }

    private func throwIfCancelled(_ cancellation: PDTCancellation) throws {
        if cancellation.isCancelled {
            throw PDTAPIError.cancelled
        }
    }

    /// One failed request of an optional phase, on its way to the phase's record.
    private struct PhaseFailed: Error {
        let failure: PDTSyncFailure
    }
}

/// Offline API replies for the app's `--scripted-pdt` connection
/// (`ScriptedPDTConnection.api`).
/// Responses are served in request order.
public struct ScriptedPDTAPIConfiguration: Codable, Equatable, Sendable {
    public struct Response: Codable, Equatable, Sendable {
        public var status: Int
        public var body: String
        public var headers: [String: String]?

        public init(status: Int = 200, body: String, headers: [String: String]? = nil) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    public var responses: [Response]
    public var asOf: String?
    public var initialRequestDelaySeconds: Double?

    public init(responses: [Response], asOf: String? = nil, initialRequestDelaySeconds: Double? = nil) {
        self.responses = responses
        self.asOf = asOf
        self.initialRequestDelaySeconds = initialRequestDelaySeconds
    }

    public func transport() -> ScriptedPDTHTTPTransport {
        ScriptedPDTHTTPTransport(
            responses.map { .response(status: $0.status, body: Data($0.body.utf8), headers: $0.headers ?? [:]) },
            initialDelaySeconds: initialRequestDelaySeconds ?? 0
        )
    }
}
