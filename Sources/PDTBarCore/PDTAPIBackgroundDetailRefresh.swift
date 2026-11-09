import Foundation

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
/// outcome. Once a phase sees an auth or setup outage, every later phase is
/// skipped, price history included.
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
        try throwIfCancelled(cancellation, .holdings(), phase: .baseHoldings)
        try? snapshotStore.clearLastDetailRefreshDiagnostic()

        let snapshotAsOf = asOf ?? dayString(from: now())
        let priorSnapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        let priorSnapshot = priorSnapshotLoad.snapshot

        progress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        let rows: [APIHolding]
        do {
            rows = try client.getAll(.holdings(), cancellation: cancellation)
        } catch {
            try throwIfCancelled(cancellation, .holdings(), phase: .baseHoldings)
            try snapshotStore.saveLastDetailRefreshDiagnostic(diagnostic(for: error, .holdings(), phase: .baseHoldings))
            throw error
        }
        try throwIfCancelled(cancellation, .holdings(), phase: .baseHoldings)

        let holdingInputs = rows.map(\.baseHoldingInput)
        var snapshot = PDTSnapshotNormalizer.normalize(PDTSnapshotNormalizationInput(
            asOf: snapshotAsOf,
            currency: PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR"),
            holdings: holdingInputs
        ))
        PDTBackgroundDetailRefresh.preserveOptionalDetails(in: &snapshot, from: priorSnapshot)
        let openQuoteIDs = snapshot.openHoldings.map(\.quoteId)

        var diagnostics: [PDTDetailRefreshFailureDiagnostic] = []
        var setupUnavailable = false
        func record(_ failure: PDTDetailRefreshFailureDiagnostic) {
            diagnostics.append(failure)
            if failure.category.indicatesUnavailableSetup {
                setupUnavailable = true
            }
        }
        func optionalPhase(_ phase: BackgroundDetailRefreshPhase, _ fill: () throws -> Void) throws {
            guard !setupUnavailable else {
                return
            }
            progress(BackgroundDetailRefreshProgress(phase: phase))
            do {
                try fill()
            } catch let failure as PDTDetailRefreshToolError {
                try throwIfCancelled(cancellation, phase: phase)
                record(failure.diagnostic)
            }
            try throwIfCancelled(cancellation, phase: phase)
        }

        try optionalPhase(.allocation) {
            let distributions = try fetch(.distributions, phase: .allocation, cancellation: cancellation) {
                try decodeAPIResponse(APIDistributionsEnvelope.self, from: client.get(.distributions, cancellation: cancellation))
            }
            let normalized = PDTOptionalDetailNormalizer.normalizeDistributions(distributions.optionalDetailInput)
            snapshot.sectors = normalized.sectors
            snapshot.assetTypes = normalized.assetTypes
        }

        try optionalPhase(.xRay) {
            let xRayRows = try fetch(.xRay, phase: .xRay, cancellation: cancellation) {
                try client.getAll(.xRay, as: APIXRayHolding.self, cancellation: cancellation)
            }
            snapshot.xRayHoldings = PDTOptionalDetailNormalizer.normalizeXRayHoldings(xRayRows.map(\.optionalDetailInput))
        }

        try optionalPhase(.income) {
            let incomeEnd = dayString(snapshotAsOf, addingDays: 30)
            let calendarResource = PDTAPIResource.calendarEvents(dateFrom: snapshotAsOf, dateTo: incomeEnd)
            let calendarEvents = try fetch(calendarResource, phase: .income, cancellation: cancellation) {
                try client.getAll(calendarResource, as: APICalendarEvent.self, cancellation: cancellation)
            }
            let dividendsResource = PDTAPIResource.dividends(
                dateFrom: dayString(snapshotAsOf, addingDays: -370),
                dateTo: incomeEnd
            )
            let dividends = try fetch(dividendsResource, phase: .income, cancellation: cancellation) {
                try client.getAll(dividendsResource, as: APIDividend.self, cancellation: cancellation)
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

        if !setupUnavailable {
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
                if setupUnavailable {
                    failedQuoteIDs.formUnion(chunk)
                } else {
                    do {
                        let priceRows = try fetch(resource, phase: .priceHistory, cancellation: cancellation) {
                            try decodeAPIResponse(APIPricesBatchEnvelope.self, from: client.get(resource, cancellation: cancellation))
                                .data.prices.joined().map(\.optionalDetailInput)
                        }
                        points += PDTOptionalDetailNormalizer.normalizePriceSeries(priceRows)
                    } catch let failure as PDTDetailRefreshToolError {
                        try throwIfCancelled(cancellation, resource, phase: .priceHistory)
                        record(failure.diagnostic)
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
            try throwIfCancelled(cancellation, phase: .priceHistory)
            snapshot.priceSeries = PDTBackgroundDetailRefresh.priceSeriesWithPriorFallback(
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
        try throwIfCancelled(cancellation, phase: .performance)

        let outcome: PDTBackgroundDetailRefreshOutcome = diagnostics.isEmpty ? .completed : .degraded
        let pulse = try PressureRunner.refreshedPulse(
            snapshot: snapshot,
            priorSnapshot: priorSnapshot,
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            detailRefreshOutcome: outcome,
            detailRefreshDiagnostic: diagnostics.last,
            priorSnapshotLoadStatus: priorSnapshotLoad.status
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

    private func fetch<T>(
        _ resource: PDTAPIResource,
        phase: BackgroundDetailRefreshPhase,
        cancellation: PDTCancellation,
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch {
            try throwIfCancelled(cancellation, resource, phase: phase)
            throw PDTDetailRefreshToolError(diagnostic: diagnostic(for: error, resource, phase: phase))
        }
    }

    private func diagnostic(
        for error: Error,
        _ resource: PDTAPIResource,
        phase: BackgroundDetailRefreshPhase
    ) -> PDTDetailRefreshFailureDiagnostic {
        PDTDetailRefreshFailureDiagnostic(
            toolName: resource.path,
            phase: phase,
            attemptCount: 1,
            category: pdtDetailRefreshFailureCategory(for: error),
            argumentShape: resource.argumentShape
        )
    }

    private func throwIfCancelled(
        _ cancellation: PDTCancellation,
        _ resource: PDTAPIResource? = nil,
        phase: BackgroundDetailRefreshPhase
    ) throws {
        guard cancellation.isCancelled else {
            return
        }
        throw PDTDetailRefreshToolError(diagnostic: PDTDetailRefreshFailureDiagnostic(
            toolName: resource?.path ?? phase.rawValue,
            phase: phase,
            attemptCount: 0,
            category: .timeout,
            argumentShape: resource?.argumentShape ?? []
        ))
    }
}

/// Offline replay script for the app's scripted background refresh
/// (`PDTBAR_SCRIPTED_BACKGROUND_REFRESH=1` plus `scripted-pdt-api.json`).
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
