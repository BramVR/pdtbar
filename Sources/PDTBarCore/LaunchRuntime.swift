import Foundation

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
    case performance

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
        case .performance:
            6
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
        case .performance:
            "Performance"
        }
    }
}

public struct BackgroundDetailRefreshProgress: Codable, Equatable, Sendable {
    public var phase: BackgroundDetailRefreshPhase
    public var detail: String?
    public var completedUnitCount: Int?
    public var totalUnitCount: Int?

    public init(
        phase: BackgroundDetailRefreshPhase,
        detail: String? = nil,
        completedUnitCount: Int? = nil,
        totalUnitCount: Int? = nil
    ) {
        self.phase = phase
        self.detail = detail
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

    /// Maps the launch flow's last-known readiness probe result to the source
    /// facts a republished cached pulse may truthfully claim. A probe verifies
    /// Claude and the PDT MCP server only; read-tool availability and the
    /// read-only policy are proven by live fetches, not probes.
    public static func runtimeSourceState(
        afterReadinessProbe result: ClaudeReadinessProbeResult?
    ) -> DataHealthRuntimeSourceState {
        switch result {
        case nil, .failed:
            return .unverified
        case .ready:
            return DataHealthRuntimeSourceState(
                claudeReadiness: .ready,
                pdtMCPReadiness: .ready,
                availableReadTools: nil,
                readOnlyPolicy: .unknown
            )
        case .notReady, .missingClaudeLogin:
            return DataHealthRuntimeSourceState(
                claudeReadiness: .missing,
                pdtMCPReadiness: .unknown,
                availableReadTools: nil,
                readOnlyPolicy: .unknown
            )
        case .missingPDTMCP:
            return DataHealthRuntimeSourceState(
                claudeReadiness: .ready,
                pdtMCPReadiness: .missing,
                availableReadTools: nil,
                readOnlyPolicy: .unknown
            )
        }
    }

    /// Applies the runtime's known source facts to a cached pulse before it is
    /// republished, so Data health never claims connector readiness from cache
    /// alone. Fetched and refreshed pulses keep their live-verified facts.
    public static func pulseApplyingRuntimeSourceState(
        _ runtimeSourceState: DataHealthRuntimeSourceState,
        to pulse: PulseLifecycleResult
    ) -> PulseLifecycleResult {
        guard pulse.source == .cachedSnapshot else {
            return pulse
        }
        var pulse = pulse
        let health = DataHealth.applyingRuntimeSourceState(
            runtimeSourceState,
            to: pulse.model.facetSnapshots.dataHealth
        )
        pulse.model.facetSnapshots.dataHealth = health
        pulse.unfilteredModel.facetSnapshots.dataHealth = DataHealth.applyingRuntimeSourceState(
            runtimeSourceState,
            to: pulse.unfilteredModel.facetSnapshots.dataHealth
        )
        pulse.descriptor = MenuDescriptorRenderer.descriptorByReplacingDataHealth(
            in: pulse.descriptor,
            with: health
        )
        return pulse
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
                    ).withRefreshAction(.waitingForSetup),
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
            ).trustingPortfolioValueMetadata()
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
            ).trustingPortfolioValueMetadata()
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
            ).trustingPortfolioValueMetadata()
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
            ).trustingPortfolioValueMetadata()
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
            ).trustingPortfolioValueMetadata()
        }
    }

    public static func descriptorWithRefreshDetailsAction(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        var descriptor = cachedPulse.withRefreshAction(.available)
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
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
        descriptor.portfolioValueProtectionState = portfolioValueProtectionState
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
        progress: BackgroundDetailRefreshProgress,
        cachedSnapshotAsOf: String? = nil
    ) -> MenuDescriptor {
        let statusCopy = progress.detail.map { "Syncing portfolio - \($0)" }
            ?? "Syncing portfolio - \(progress.phase.title)"
        return cachedPulseDescriptor(
            cachedPulseWithRuntimeHealth(cachedPulse, detailFill: .inProgress(progress))
                .withRefreshAction(.inProgress),
            statusVisual: cachedPulse.statusVisual.withStatusCopy(statusCopy),
            rowsFirst: true,
            rows: backgroundDetailProgressRows(progress, cachedSnapshotAsOf: cachedSnapshotAsOf)
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
        ).trustingPortfolioValueMetadata()
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
        var descriptor = MenuDescriptor(
            statusTitle: cachedPulse.statusTitle,
            statusBadge: cachedPulse.statusBadge,
            statusVisual: statusVisual ?? cachedPulse.statusVisual,
            statusAccessibilityIdentifier: cachedPulse.statusAccessibilityIdentifier,
            sections: rowsFirst ? [fetchSection] + cachedPulse.sections : cachedPulse.sections + [fetchSection]
        )
        descriptor.portfolioValueProtectionState = cachedPulse.portfolioValueProtectionState
        return descriptor
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
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
        let sourceDetail = runtimeDataHealthSourceDetail(claudeReadiness: claudeReadiness, pdtMCPReadiness: pdtMCPReadiness)
        let detailFillDetail = runtimeDataHealthDetailFillDetail(detailFill)
        let summaryDetail = runtimeDataHealthSummaryDetail(
            detailFill,
            claudeReadiness: claudeReadiness,
            pdtMCPReadiness: pdtMCPReadiness
        )
        let diagnosticRow = runtimeDataHealthDiagnosticRow(for: diagnostic)
            ?? (clearsDiagnostic ? MenuDescriptorRenderer.dataHealthDiagnosticRow(for: nil) : nil)

        var replacedDataHealth = false
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
                replacedDataHealth = true
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
            if !replacedDataHealth {
                var row = runtimeDataHealthRow(
                    claudeReadiness: claudeReadiness,
                    pdtMCPReadiness: pdtMCPReadiness,
                    detailFill: detailFill,
                    diagnostic: diagnostic
                )
                if let summaryDetail {
                    row.detail = summaryDetail
                }
                section.rows.append(row)
            }
            return section
        }
        descriptor.portfolioValueProtectionState = portfolioValueProtectionState
        return descriptor
    }

    private static func runtimeDataHealthRow(
        claudeReadiness: DataHealthSourceStatus,
        pdtMCPReadiness: DataHealthSourceStatus,
        detailFill: DataHealthDetailFillInput,
        diagnostic: PDTDetailRefreshFailureDiagnostic?
    ) -> MenuRow {
        let sourceReady = claudeReadiness == .ready && pdtMCPReadiness == .ready
        let health = DataHealth.build(
            DataHealthInput(
                claudeReadiness: claudeReadiness,
                pdtMCPReadiness: pdtMCPReadiness,
                availableReadTools: sourceReady ? Set(PDTReadTools.requiredV1) : nil,
                readOnlyPolicy: sourceReady ? .enforced : .unknown,
                pulseSource: .cachedSnapshot,
                lastSuccessfulCompleteFetchAsOf: nil,
                cachedPulseAvailable: true,
                detailFill: detailFill,
                freshness: FreshnessSnapshot(
                    status: .fresh,
                    worstPriceAsOf: nil,
                    stale: false,
                    staleHoldingCount: 0,
                    oldestPriceAsOf: nil,
                    oldestRows: [],
                    latestCompleteDetailFillAsOf: nil,
                    sourceCaveats: []
                ),
                readState: nil,
                diagnostic: diagnostic
            )
        )
        var row = MenuDescriptorRenderer.dataHealthRow(for: health)
        row.children.removeAll { $0.id == "dataHealth.readState" }
        return row
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
        return DataHealth.sourceSnapshot(
            DataHealthRuntimeSourceState(
                claudeReadiness: claudeReadiness,
                pdtMCPReadiness: pdtMCPReadiness,
                availableReadTools: nil,
                readOnlyPolicy: .unknown
            )
        ).detail
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

    private static func backgroundDetailProgressRows(
        _ progress: BackgroundDetailRefreshProgress,
        cachedSnapshotAsOf: String?
    ) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "portfolioFetch.backgroundProgress.cached",
                role: .fetchStatus,
                title: "Cached data visible",
                detail: cachedSnapshotAsOf.map { "Last snapshot \($0)" } ?? "Last pulse is still visible"
            ),
            MenuRow(
                id: "portfolioFetch.backgroundProgress",
                role: .fetchStatus,
                title: "Filling details",
                detail: "Sync in progress"
            ),
            MenuRow(
                id: "portfolioFetch.backgroundProgress.phase",
                role: .fetchStatus,
                title: "Step \(progress.phase.stepIndex)/\(BackgroundDetailRefreshPhase.allCases.count): \(progress.phase.title)",
                detail: progress.detail
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

/// One readiness check. Only `PDTLaunchRuntime` makes these, and every probe
/// result must name the attempt it answers. An attempt from another runtime never matches.
public struct PDTReadinessAttempt: Equatable, Sendable {
    fileprivate let runtime: UUID
    fileprivate let number: Int
}

/// The pulse the menu shows. `show` is the only way to set it, and it applies the
/// read store's current state last, so no caller can display a worker's older copy.
private struct DisplayedPulse {
    private let loadReadState: () -> PulseReadState?
    private(set) var pulse: PulseLifecycleResult?

    init(loadReadState: @escaping () -> PulseReadState?) {
        self.loadReadState = loadReadState
    }

    /// An unreadable store returns nil, and the pulse keeps the read state it was built with.
    mutating func show(_ pulse: PulseLifecycleResult?) {
        self.pulse = pulse.map { pulse in loadReadState().map(pulse.applyingReadState) ?? pulse }
    }
}

public final class PDTLaunchRuntime {
    /// Progress of `readinessAttempt`. `completeReadinessProbe` drops results
    /// for any other attempt before they can reach these cases.
    private enum ReadinessProbe: Equatable {
        case idle
        case running
        /// `ready` arrived before the cached pulse load finished; applied once it does,
        /// so a returning user gets a background refresh instead of a full first fetch.
        case readyAwaitingCachedPulse
    }

    /// What the menu shows around `currentPulse`. The descriptor is rendered from this on
    /// every update, so a pulse change such as a mark-read keeps the surrounding rows.
    private enum Screen {
        case launchState(fetchingElapsedSeconds: Int?)
        case loginFailed(ClaudeLoginFailureReason)
        case detailProgress(BackgroundDetailRefreshProgress)
        case detailDegraded
        case detailFailed(PDTDetailRefreshFailureDiagnostic?)
        case refreshed
    }

    private var displayed: DisplayedPulse
    public var currentPulse: PulseLifecycleResult? { displayed.pulse }
    public private(set) var state: ClaudeLaunchState = .probingClaude
    private var readinessProbe = ReadinessProbe.idle
    private var cachedPulseLoading = false
    public private(set) var readinessAttempt = PDTReadinessAttempt(runtime: UUID(), number: 0)
    public private(set) var firstFetchInFlight = false
    public private(set) var backgroundDetailRefreshInFlight = false
    public private(set) var lastKnownReadiness: ClaudeReadinessProbeResult?
    private var screen = Screen.launchState(fetchingElapsedSeconds: nil)

    /// `loadReadState` reads the pulse read store; see `DisplayedPulse.show`.
    public init(loadReadState: @escaping () -> PulseReadState? = { nil }) {
        displayed = DisplayedPulse(loadReadState: loadReadState)
    }

    public func launch(cachedPulse: PulseLifecycleResult?) -> PDTOnboardingUpdate {
        show(cachedPulse)
        cachedPulseLoading = false
        return beginReadinessProbe()
    }

    /// Launch before the cached pulse is decoded. Call `completeCachedPulseLoad` when it is.
    public func launchWhileLoadingCachedPulse() -> PDTOnboardingUpdate {
        let update = launch(cachedPulse: nil)
        cachedPulseLoading = true
        return update
    }

    public func completeCachedPulseLoad(
        _ pulse: PulseLifecycleResult?,
        allowsBackgroundDetailRefresh: @autoclosure () -> Bool = true
    ) -> PDTOnboardingUpdate? {
        cachedPulseLoading = false
        let cachedUpdate = pulse.flatMap(installCachedPulse)
        guard readinessProbe == .readyAwaitingCachedPulse else {
            return cachedUpdate
        }
        return applyReadiness(.ready, allowsBackgroundDetailRefresh: allowsBackgroundDetailRefresh())
    }

    private func installCachedPulse(_ pulse: PulseLifecycleResult) -> PDTOnboardingUpdate? {
        if let currentPulse, currentPulse.source != .cachedSnapshot {
            return nil
        }
        show(pulse)
        screen = backgroundDetailRefreshInFlight
            ? .detailProgress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
            : .launchState(fetchingElapsedSeconds: nil)
        return currentUpdate()
    }

    public func retryReadiness() -> PDTOnboardingUpdate? {
        guard readinessProbe == .idle else {
            return nil
        }
        return beginReadinessProbe()
    }

    public func completeReadinessProbe(
        _ result: ClaudeReadinessProbeResult,
        for attempt: PDTReadinessAttempt,
        allowsBackgroundDetailRefresh: @autoclosure () -> Bool = true
    ) -> PDTOnboardingUpdate {
        guard readinessProbe == .running, attempt == readinessAttempt else {
            return currentUpdate()
        }
        if result == .ready, cachedPulseLoading {
            readinessProbe = .readyAwaitingCachedPulse
            return currentUpdate()
        }
        return applyReadiness(result, allowsBackgroundDetailRefresh: allowsBackgroundDetailRefresh())
    }

    /// `allowsBackgroundDetailRefresh` is read only when a pulse exists, so a cold
    /// launch never loads the refresh configuration.
    private func applyReadiness(
        _ result: ClaudeReadinessProbeResult,
        allowsBackgroundDetailRefresh: @autoclosure () -> Bool
    ) -> PDTOnboardingUpdate {
        readinessProbe = .idle
        lastKnownReadiness = result
        show(currentPulse)
        let nextState = ClaudeLaunchFlow.state(afterReadinessProbe: result)
        if nextState == .fetchingPortfolio {
            guard !firstFetchInFlight, !backgroundDetailRefreshInFlight else {
                return currentUpdate()
            }
            if let currentPulse, allowsBackgroundDetailRefresh() {
                return startBackgroundDetailRefresh(with: currentPulse)
            }
            firstFetchInFlight = true
            return update(state: nextState, effect: .startFirstFetch)
        }
        return update(state: nextState)
    }

    public func beginLoginHandoff() -> PDTOnboardingUpdate {
        readinessProbe = .idle
        return update(state: .openingClaude, effect: .startLoginHandoff)
    }

    public func completeLoginHandoff(_ result: PDTOnboardingLoginResult) -> PDTOnboardingUpdate {
        switch result {
        case .succeeded:
            return beginReadinessProbe()
        case .failed(let reason):
            state = .missingClaude
            screen = .loginFailed(reason)
            return currentUpdate()
        }
    }

    /// Accepted only after readiness came back ready, so no fetch runs behind a setup screen.
    public func retryFirstFetch() -> PDTOnboardingUpdate? {
        guard state == .fetchingPortfolio || state == .portfolioFetchFailed,
              !firstFetchInFlight, !backgroundDetailRefreshInFlight else {
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
            return publishFetchedPulse(pulse)
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
        guard backgroundDetailRefreshInFlight, currentPulse != nil else {
            return nil
        }
        state = .fetchingPortfolio
        screen = .detailProgress(progress)
        return currentUpdate()
    }

    public func completeBackgroundDetailRefresh(
        _ result: PDTLaunchBackgroundDetailRefreshResult
    ) -> PDTOnboardingUpdate {
        backgroundDetailRefreshInFlight = false
        switch result {
        case let .succeeded(pulse, outcome):
            show(pulse)
            state = .fetchingPortfolio
            screen = outcome == .degraded ? .detailDegraded : .refreshed
            return currentUpdate()
        case .failed(_, let diagnostic):
            guard currentPulse != nil else {
                return update(state: .portfolioFetchFailed)
            }
            state = .portfolioFetchFailed
            screen = .detailFailed(diagnostic)
            return currentUpdate()
        }
    }

    public func replaceCurrentPulse(_ pulse: PulseLifecycleResult) {
        show(pulse)
    }

    /// Call after the read store changes. Only the pulse rows change; the
    /// launch state and any running fetch or refresh are left as they are.
    public func pulseReadStateDidChange() -> PDTOnboardingUpdate? {
        guard let pulse = currentPulse else {
            return nil
        }
        show(pulse)
        return currentUpdate()
    }

    private func publishFetchedPulse(_ pulse: PulseLifecycleResult) -> PDTOnboardingUpdate {
        show(pulse)
        // A setup check started during the fetch still decides what happens next.
        if state == .probingClaude {
            return update(state: .probingClaude)
        }
        state = .fetchingPortfolio
        screen = .refreshed
        return currentUpdate()
    }

    private func show(_ pulse: PulseLifecycleResult?) {
        displayed.show(pulse.map(pulseApplyingLastKnownReadiness))
    }

    /// Cached pulses only claim the source facts the runtime has actually
    /// verified; fetched and refreshed pulses pass through unchanged.
    private func pulseApplyingLastKnownReadiness(_ pulse: PulseLifecycleResult) -> PulseLifecycleResult {
        ClaudeLaunchFlow.pulseApplyingRuntimeSourceState(
            ClaudeLaunchFlow.runtimeSourceState(afterReadinessProbe: lastKnownReadiness),
            to: pulse
        )
    }

    private func beginReadinessProbe() -> PDTOnboardingUpdate {
        readinessAttempt = PDTReadinessAttempt(runtime: readinessAttempt.runtime, number: readinessAttempt.number + 1)
        readinessProbe = .running
        return update(state: .probingClaude, effect: .probeReadiness)
    }

    private func startBackgroundDetailRefresh(with pulse: PulseLifecycleResult) -> PDTOnboardingUpdate {
        firstFetchInFlight = false
        backgroundDetailRefreshInFlight = true
        state = .fetchingPortfolio
        screen = .detailProgress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        return currentUpdate(effect: .startBackgroundDetailRefresh)
    }

    private func update(
        state: ClaudeLaunchState,
        effect: PDTOnboardingEffect = .none,
        fetchingElapsedSeconds: Int? = nil
    ) -> PDTOnboardingUpdate {
        self.state = state
        screen = .launchState(fetchingElapsedSeconds: fetchingElapsedSeconds)
        return currentUpdate(effect: effect)
    }

    private func currentUpdate(effect: PDTOnboardingEffect = .none) -> PDTOnboardingUpdate {
        PDTOnboardingUpdate(state: state, descriptor: descriptor(for: screen), effect: effect)
    }

    private func descriptor(for screen: Screen) -> MenuDescriptor {
        guard let pulse = currentPulse else {
            if case .loginFailed(let reason) = screen {
                return ClaudeLaunchFlow.descriptor(forLoginFailure: reason)
            }
            if case .launchState(let fetchingElapsedSeconds) = screen {
                return ClaudeLaunchFlow.descriptor(for: state, fetchingElapsedSeconds: fetchingElapsedSeconds)
            }
            return ClaudeLaunchFlow.descriptor(for: state)
        }
        switch screen {
        case .launchState(let fetchingElapsedSeconds):
            return ClaudeLaunchFlow.descriptor(
                for: state,
                cachedPulse: pulse.descriptor,
                fetchingElapsedSeconds: fetchingElapsedSeconds
            )
        case .loginFailed(let reason):
            return ClaudeLaunchFlow.descriptor(forLoginFailure: reason)
        case .detailProgress(let progress):
            return ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
                cachedPulse: pulse.descriptor,
                progress: progress,
                cachedSnapshotAsOf: pulse.model.asOf
            )
        case .detailDegraded:
            return ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: pulse.descriptor)
        case .detailFailed(let diagnostic):
            return ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(
                cachedPulse: pulse.descriptor,
                diagnostic: diagnostic
            )
        case .refreshed:
            return ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: pulse.descriptor)
        }
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
        ).trustingPortfolioValueMetadata()
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
        ).trustingPortfolioValueMetadata()
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
        ).trustingPortfolioValueMetadata()
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
        ).trustingPortfolioValueMetadata()
    }
}
