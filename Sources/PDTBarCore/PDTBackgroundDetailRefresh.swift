import Foundation

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

struct PDTDetailRefreshToolError: Error, CustomStringConvertible {
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
