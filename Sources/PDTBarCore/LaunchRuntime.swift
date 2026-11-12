import Foundation

public enum PDTBarLaunchMode: Equatable {
    /// The product path: PDT through its REST API with the Keychain credential,
    /// or through an offline script when `scriptedConnection` is set.
    case pdtAPI
    case fixture(URL)
}

public struct PDTBarLaunchOptions: Equatable {
    public var mode: PDTBarLaunchMode
    public var snapshotDirectory: URL?
    public var appSupportDirectory: URL?
    /// `--scripted-pdt <file>`: fake credential store, sign-in, and API replies for
    /// smokes. Accepted only with an isolated app support directory.
    public var scriptedConnection: URL?
    /// `--pdt-credential-file <file>`: dev live proof over the mode-0600 file store
    /// `pdtbar-dev pdt-*` uses, instead of the Keychain (an ad-hoc dev build has no
    /// keychain entitlement). Live PDT; accepted only with an isolated app support directory.
    public var credentialFile: URL?

    public init(
        mode: PDTBarLaunchMode,
        snapshotDirectory: URL? = nil,
        appSupportDirectory: URL? = nil,
        scriptedConnection: URL? = nil,
        credentialFile: URL? = nil
    ) {
        self.mode = mode
        self.snapshotDirectory = snapshotDirectory
        self.appSupportDirectory = appSupportDirectory
        self.scriptedConnection = scriptedConnection
        self.credentialFile = credentialFile
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
        var scriptedConnection: URL?
        var credentialFile: URL?
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
            case "--scripted-pdt" where index + 1 < arguments.count:
                scriptedConnection = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--pdt-credential-file" where index + 1 < arguments.count:
                credentialFile = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            default:
                throw PDTBarLaunchOptionError.usage
            }
        }

        appSupportDirectory = appSupportDirectory
            ?? environment["PDTBAR_APP_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }

        if let fixture {
            guard scriptedConnection == nil, credentialFile == nil else {
                throw PDTBarLaunchOptionError.usage
            }
            let configuredSnapshotDirectory = snapshotDirectory
                ?? environment["PDTBAR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            return PDTBarLaunchOptions(
                mode: .fixture(fixture),
                snapshotDirectory: configuredSnapshotDirectory,
                appSupportDirectory: appSupportDirectory
            )
        }

        // A script or dev credential never runs against the user's real app state.
        let overridesStore = scriptedConnection != nil || credentialFile != nil
        guard snapshotDirectory == nil,
              scriptedConnection == nil || credentialFile == nil,
              !overridesStore || appSupportDirectory != nil
        else {
            throw PDTBarLaunchOptionError.usage
        }
        return PDTBarLaunchOptions(
            mode: .pdtAPI,
            appSupportDirectory: appSupportDirectory,
            scriptedConnection: scriptedConnection,
            credentialFile: credentialFile
        )
    }
}

/// What the menu shows about PDT access and the portfolio sync. A pulse can be
/// on screen in every state except `notConnected`.
public enum PDTLaunchState: Equatable, Sendable {
    case checkingConnection
    case connecting
    case disconnecting
    case notConnected
    case needsReconnect(PDTCredentialKind, PDTReconnectCause)
    case subscriptionPaused
    case keychainUnavailable(PDTKeychainProblem)
    /// How the credential is kept is what the connection said when the last
    /// connection operation or sync ended, so a connection that is not saved
    /// says so on every connected screen.
    case connected(PDTPortfolioSync, PDTCredentialPersistence)

    init(_ status: PDTConnectionStatus) {
        switch status {
        case .notConnected: self = .notConnected
        case let .connected(persistence): self = .connected(.current, persistence)
        case let .needsReconnect(kind, cause): self = .needsReconnect(kind, cause)
        case .subscriptionPaused: self = .subscriptionPaused
        case let .keychainUnavailable(problem): self = .keychainUnavailable(problem)
        }
    }

    /// States whose menu offers Sign in with PDT and the pasted-token fallback.
    var offersSignIn: Bool {
        switch self {
        case .notConnected, .needsReconnect, .subscriptionPaused: true
        default: false
        }
    }

    var offersCheckAgain: Bool {
        switch self {
        case .needsReconnect, .subscriptionPaused, .keychainUnavailable: true
        default: false
        }
    }

    var offersDisconnect: Bool {
        switch self {
        case .needsReconnect, .subscriptionPaused, .connected(.failed, _), .connected(.current, _): true
        default: false
        }
    }
}

public enum PDTPortfolioSync: Equatable, Sendable {
    case fetching
    case failed
    case current
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

/// Menus for every launch state. Connection screens put their rows above a
/// visible pulse; `notConnected` shows setup only.
public enum PDTLaunchMenu {
    public static func descriptor(
        for state: PDTLaunchState,
        cachedPulse: MenuDescriptor? = nil,
        notice: PDTConnectionNotice? = nil,
        fetchingElapsedSeconds: Int? = nil,
        syncFailure: PDTSyncFailure? = nil
    ) -> MenuDescriptor {
        switch state {
        case .connected(.fetching, _):
            guard let cachedPulse else {
                return fetchingDescriptor(elapsedSeconds: fetchingElapsedSeconds, connectionRows: notSavedRows(state))
            }
            return cachedPulseDescriptor(
                cachedPulse.withRefreshAction(.inProgress),
                rowsFirst: true,
                rows: [
                    MenuRow(
                        id: "portfolioFetch.refreshing",
                        role: .fetchStatus,
                        title: "Refreshing portfolio",
                        detail: fetchingDetail(elapsedSeconds: fetchingElapsedSeconds, fallback: "Keeping last pulse visible")
                    ),
                ]
            )
        case .connected(.failed, _):
            guard let cachedPulse else {
                return MenuDescriptor(
                    statusTitle: "Could not fetch portfolio",
                    statusVisual: StatusVisualState(isDimmed: true),
                    sections: [
                        MenuSection(id: "portfolioFetch", title: "Portfolio", rows: portfolioFetchFailureRows(syncFailure)),
                        connectionSection(rows: notSavedRows(state) + [disconnectRow()]),
                    ]
                ).trustingPortfolioValueMetadata()
            }
            return descriptorForBackgroundRefreshFailure(cachedPulse: cachedPulse)
        case .connected(.current, _):
            guard let cachedPulse else {
                return fetchingDescriptor(elapsedSeconds: nil, connectionRows: notSavedRows(state))
            }
            return descriptorWithRefreshDetailsAction(cachedPulse: cachedPulse)
        case .notConnected:
            return connectionDescriptor(state, notice: notice, cachedPulse: nil)
        case .checkingConnection, .connecting, .disconnecting, .needsReconnect, .subscriptionPaused, .keychainUnavailable:
            return connectionDescriptor(state, notice: notice, cachedPulse: cachedPulse)
        }
    }

    static func connectionCopy(_ state: PDTLaunchState) -> (title: String, detail: String) {
        switch state {
        case .checkingConnection:
            ("Checking PDT connection", "No prompts opened")
        case .connecting:
            ("Signing in with PDT", "Approve PDTBar in your browser")
        case .disconnecting:
            ("Disconnecting from PDT", "Removing the stored connection")
        case .notConnected:
            ("Not connected", "PDTBar reads your PDT portfolio read-only")
        case let .needsReconnect(_, cause):
            ("Reconnect to PDT", sentenceCased(reconnectReason(cause)))
        case .subscriptionPaused:
            ("PDT access paused", "Your PDT subscription has ended. Renew it, then check again")
        case .keychainUnavailable(.missingEntitlement):
            ("Keychain unavailable", "This PDTBar build can't use the Keychain. Install the signed release")
        case .keychainUnavailable(.failed):
            ("Could not read the Keychain", "PDTBar could not load its PDT connection")
        case .connected:
            ("Connected to PDT", "Read-only")
        }
    }

    /// Why PDT rejected the connection, worded to follow "Reconnect needed: "
    /// in Data Health or, sentence-cased, to stand alone on the reconnect screen.
    static func reconnectReason(_ cause: PDTReconnectCause) -> String {
        switch cause {
        case .signInExpired: "your PDT sign-in has expired"
        case .tokenExpired: "your PDT token has expired"
        case .tokenRevoked: "PDTBar's access was revoked in PDT"
        case .tokenInvalid: "PDT no longer accepts this connection"
        case .readAccessMissing: "this connection can't read your portfolio"
        }
    }

    private static func sentenceCased(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func connectionDescriptor(
        _ state: PDTLaunchState,
        notice: PDTConnectionNotice?,
        cachedPulse: MenuDescriptor?
    ) -> MenuDescriptor {
        let copy = connectionCopy(state)
        var rows = [MenuRow(id: "pdtConnection.status", role: .setupStatus, title: copy.title, detail: copy.detail)]
        rows += noticeRows(notice)
        if state == .connecting {
            rows.append(MenuRow(id: "pdtConnection.cancel", role: .connectionCancel, title: "Cancel sign-in"))
        }
        if state.offersSignIn {
            rows.append(MenuRow(id: "pdtConnection.signIn", role: .connectionSignIn, title: "Sign in with PDT"))
            rows.append(MenuRow(id: "pdtConnection.token", role: .connectionToken, title: "Use a PDT token…"))
        }
        if state.offersCheckAgain {
            rows.append(MenuRow(id: "pdtConnection.check", role: .connectionCheck, title: "Check again"))
        }
        if state.offersDisconnect {
            rows.append(disconnectRow())
        }
        guard let cachedPulse else {
            return MenuDescriptor(
                statusTitle: copy.title,
                statusVisual: StatusVisualState(isDimmed: true),
                sections: [connectionSection(rows: rows)]
            ).trustingPortfolioValueMetadata()
        }
        var descriptor = cachedPulseDescriptor(
            cachedPulse.withRefreshAction(.waitingForSetup),
            statusVisual: cachedPulse.statusVisual.withDimming(true).withStatusCopy(copy.title),
            rowsFirst: true,
            rows: []
        )
        descriptor.sections[0] = connectionSection(rows: rows)
        return descriptor
    }

    private static func noticeRows(_ notice: PDTConnectionNotice?) -> [MenuRow] {
        switch notice {
        case nil:
            return []
        case let .signInFailed(failure):
            let detail = switch failure {
            case .portBusy: "Another app is using PDTBar's sign-in port. Try again, or use a token"
            case .browserUnavailable: "PDTBar could not open your browser"
            case .denied: "PDT sign-in was declined"
            case .timedOut: "PDT sign-in timed out"
            case .failed: "PDT sign-in did not finish"
            }
            return [MenuRow(id: "pdtConnection.signInFailed", role: .setupFailure, title: "Sign-in failed", detail: detail)]
        case let .disconnected(revokeAt):
            return [
                MenuRow(
                    id: "pdtConnection.revoke",
                    role: .connectionRevoke,
                    title: "Remove PDTBar in PDT…",
                    detail: "Disconnected here. PDT keeps the access until you remove it",
                    actionPayload: revokeAt.absoluteString
                ),
            ]
        }
    }

    private static func connectionSection(rows: [MenuRow]) -> MenuSection {
        MenuSection(id: "pdtConnection", title: "PDT", rows: rows)
    }

    private static func disconnectRow() -> MenuRow {
        MenuRow(id: "pdtConnection.disconnect", role: .connectionDisconnect, title: "Disconnect from PDT")
    }

    /// The one row that names a connection kept for this session only. Every
    /// connected screen shows it where its Disconnect row lives: the PDT
    /// section without a pulse, Actions with one.
    fileprivate static func notSavedRows(_ state: PDTLaunchState) -> [MenuRow] {
        guard case let .connected(_, .thisSessionOnly(problem)) = state else {
            return []
        }
        return [
            MenuRow(
                id: "pdtConnection.notSaved",
                role: .setupStatus,
                title: "Connection not saved",
                detail: problem == .missingEntitlement
                    ? "This PDTBar build can't save to the Keychain. You stay connected until you quit"
                    : "PDTBar could not save it on this Mac. You stay connected until you quit"
            ),
        ]
    }

    private static func fetchingDescriptor(elapsedSeconds: Int?, connectionRows: [MenuRow]) -> MenuDescriptor {
        let statusTitle = elapsedSeconds.map { "Fetching portfolio \(formatElapsedSeconds($0))" } ?? "Fetching portfolio"
        let fetchSection = MenuSection(
            id: "portfolioFetch",
            title: "Portfolio",
            rows: [
                MenuRow(
                    id: "portfolioFetch.status",
                    role: .fetchStatus,
                    title: "Fetching portfolio",
                    detail: fetchingDetail(elapsedSeconds: elapsedSeconds, fallback: "Read-only from PDT")
                ),
            ]
        )
        return MenuDescriptor(
            statusTitle: statusTitle,
            statusVisual: StatusVisualState(isDimmed: true, statusCopy: statusTitle),
            sections: [fetchSection] + (connectionRows.isEmpty ? [] : [connectionSection(rows: connectionRows)])
        ).trustingPortfolioValueMetadata()
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

    public static func descriptorForBackgroundRefreshFailure(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse.withRefreshAction(.retryOfferedAbove),
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
            cachedPulse.withRefreshAction(.inProgress),
            statusVisual: cachedPulse.statusVisual.withStatusCopy(statusCopy),
            rowsFirst: true,
            rows: backgroundDetailProgressRows(progress, cachedSnapshotAsOf: cachedSnapshotAsOf)
        )
    }

    public static func descriptorForBackgroundDetailDegraded(cachedPulse: MenuDescriptor) -> MenuDescriptor {
        cachedPulseDescriptor(
            cachedPulse.withRefreshAction(.retryOfferedAbove),
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

    private static func cachedPulseDescriptor(
        _ cachedPulse: MenuDescriptor,
        statusVisual: StatusVisualState? = nil,
        rowsFirst: Bool = false,
        rows: [MenuRow]
    ) -> MenuDescriptor {
        // Above the pulse the notice rows name themselves; a heading is only needed below Actions.
        let fetchSection = MenuSection(
            id: "portfolioFetch",
            title: rowsFirst ? "" : "Portfolio",
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

    private static func portfolioFetchFailureRows(_ syncFailure: PDTSyncFailure?) -> [MenuRow] {
        [
            MenuRow(
                id: "portfolioFetch.failed",
                role: .fetchStatus,
                title: "Could not fetch portfolio",
                detail: syncFailure.map { sentenceCased($0.kind.menuDetail) } ?? "No partial pulse published"
            ),
            MenuRow(
                id: "portfolioFetch.retry",
                role: .fetchRetry,
                title: "Try again"
            ),
        ]
    }
}

private extension MenuDescriptor {
    func withRefreshAction(_ state: MenuRefreshActionState) -> MenuDescriptor {
        MenuDescriptorRenderer.descriptorWithTopLevelActions(self, refreshState: state)
    }

    /// What a connected pulse screen adds to Actions: the connection that is
    /// not saved, and Disconnect where the state offers it.
    func withConnectionActions(for state: PDTLaunchState) -> MenuDescriptor {
        var rows = PDTLaunchMenu.notSavedRows(state)
        if state.offersDisconnect {
            rows.append(MenuRow(id: "actions.disconnect", role: .connectionDisconnect, title: "Disconnect from PDT"))
        }
        var descriptor = self
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
        guard let index = descriptor.sections.firstIndex(where: { $0.id == "actions" }) else {
            return self
        }
        let present = Set(descriptor.sections[index].rows.map(\.id))
        descriptor.sections[index].rows += rows.filter { !present.contains($0.id) }
        descriptor.portfolioValueProtectionState = portfolioValueProtectionState
        return descriptor
    }
}

public enum PDTOnboardingEffect: Equatable {
    case none
    case loadCachedPulse
    case checkConnection
    case signIn
    case connectToken(PDTAPIToken)
    case cancelSignIn
    case disconnect
    case startFirstFetch
    case startBackgroundDetailRefresh
}

public struct PDTOnboardingUpdate: Equatable {
    public var state: PDTLaunchState
    public var descriptor: MenuDescriptor
    public var effect: PDTOnboardingEffect

    public init(state: PDTLaunchState, descriptor: MenuDescriptor, effect: PDTOnboardingEffect = .none) {
        self.state = state
        self.descriptor = descriptor
        self.effect = effect
    }
}

public enum PDTLaunchFetchResult: Equatable {
    /// `connection`: as for a committed background refresh.
    case succeeded(PulseLifecycleResult, connection: PDTConnectionStatus)
    /// `failure`: the typed record of the holdings request, which the menu names.
    case failed(PDTFetchFailure, failure: PDTSyncFailure? = nil)
}

public enum PDTLaunchBackgroundDetailRefreshResult: Equatable {
    /// The snapshot was committed. `connection` is what the connection says
    /// after the sync (`PDTAppConnection.status(afterSyncEnding:)`), and it has
    /// no default: an optional phase that lost access after the base holdings
    /// succeeded leaves a committed pulse and a connection that is gone, and a
    /// connection that is not saved must not read as saved.
    case succeeded(
        PulseLifecycleResult,
        outcome: PDTBackgroundDetailRefreshOutcome,
        connection: PDTConnectionStatus
    )
    case failed(PDTFetchFailure, failure: PDTSyncFailure? = nil)
}

/// One connection operation (check, sign-in, pasted token, disconnect). Only
/// `PDTLaunchRuntime` makes these, and every outcome must name the attempt it
/// answers. An attempt from another runtime never matches.
public struct PDTConnectionAttempt: Equatable, Sendable {
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

/// The launch state machine. Every call runs on the main queue and returns the
/// menu plus at most one effect for the app to run. Work never overlaps: a
/// connection operation, a first fetch, and a background refresh each refuse to
/// start while another runs, and the menu only offers actions that would start.
public final class PDTLaunchRuntime {
    /// What the menu shows around `currentPulse` once connected. The descriptor is
    /// rendered from this on every update, so a pulse change such as a mark-read
    /// keeps the surrounding rows.
    private enum Screen {
        case launchState(fetchingElapsedSeconds: Int?)
        case detailProgress(BackgroundDetailRefreshProgress)
        case detailDegraded
        case refreshed
    }

    /// A sync that ended without committing a snapshot, so no pulse carries its
    /// record. It outlives connection screens and connection operations, so a
    /// reconnect screen can still copy its trace id; the next sync replaces it.
    private struct UncommittedSync {
        var failure: PDTSyncFailure?
    }

    private var displayed: DisplayedPulse
    public var currentPulse: PulseLifecycleResult? { displayed.pulse }
    public private(set) var state: PDTLaunchState = .checkingConnection
    public private(set) var connectionAttempt = PDTConnectionAttempt(runtime: UUID(), number: 0)
    public private(set) var connectionOperationInFlight = false
    public private(set) var cachedPulseLoading = false
    public private(set) var firstFetchInFlight = false
    public private(set) var backgroundDetailRefreshInFlight = false
    private var notice: PDTConnectionNotice?
    private var screen = Screen.launchState(fetchingElapsedSeconds: nil)
    private var uncommittedSync: UncommittedSync?

    /// `loadReadState` reads the pulse read store; see `DisplayedPulse.show`.
    public init(loadReadState: @escaping () -> PulseReadState? = { nil }) {
        displayed = DisplayedPulse(loadReadState: loadReadState)
    }

    /// The cached pulse loads first, then the connection check starts, so a
    /// connected result always knows whether a pulse is on screen.
    public func launch() -> PDTOnboardingUpdate {
        cachedPulseLoading = true
        return update(state: .checkingConnection, effect: .loadCachedPulse)
    }

    public func completeCachedPulseLoad(_ pulse: PulseLifecycleResult?) -> PDTOnboardingUpdate? {
        guard cachedPulseLoading else {
            return nil
        }
        cachedPulseLoading = false
        if let pulse, currentPulse == nil {
            show(pulse)
        }
        return beginConnectionOperation(.checkingConnection, effect: .checkConnection)
    }

    public func completeConnection(_ outcome: PDTConnectionOutcome, for attempt: PDTConnectionAttempt) -> PDTOnboardingUpdate {
        guard connectionOperationInFlight, attempt == connectionAttempt else {
            return currentUpdate()
        }
        connectionOperationInFlight = false
        notice = outcome.notice
        return apply(outcome.status)
    }

    public func signIn() -> PDTOnboardingUpdate? {
        guard isIdle, state.offersSignIn else {
            return nil
        }
        return beginConnectionOperation(.connecting, effect: .signIn)
    }

    public func connect(token: PDTAPIToken) -> PDTOnboardingUpdate? {
        guard isIdle, state.offersSignIn else {
            return nil
        }
        return beginConnectionOperation(.checkingConnection, effect: .connectToken(token))
    }

    /// The sign-in worker still owns the operation until it reports back.
    public func cancelSignIn() -> PDTOnboardingUpdate? {
        guard state == .connecting, connectionOperationInFlight else {
            return nil
        }
        return currentUpdate(effect: .cancelSignIn)
    }

    public func checkAgain() -> PDTOnboardingUpdate? {
        guard isIdle, state.offersCheckAgain else {
            return nil
        }
        return beginConnectionOperation(.checkingConnection, effect: .checkConnection)
    }

    public func disconnect() -> PDTOnboardingUpdate? {
        guard isIdle, state.offersDisconnect else {
            return nil
        }
        return beginConnectionOperation(.disconnecting, effect: .disconnect)
    }

    /// Accepted only while connected, so no fetch runs behind a connection screen.
    public func retryFirstFetch() -> PDTOnboardingUpdate? {
        guard case let .connected(_, persistence) = state, isIdle else {
            return nil
        }
        if let currentPulse {
            return startBackgroundDetailRefresh(with: currentPulse, persistence)
        }
        return startFirstFetch(persistence)
    }

    public func firstFetchProgress(fetchingElapsedSeconds: Int) -> PDTOnboardingUpdate? {
        guard firstFetchInFlight else {
            return nil
        }
        return update(state: state, fetchingElapsedSeconds: fetchingElapsedSeconds)
    }

    public func completeFirstFetch(_ result: PDTLaunchFetchResult) -> PDTOnboardingUpdate {
        guard firstFetchInFlight else {
            return currentUpdate()
        }
        firstFetchInFlight = false
        switch result {
        case let .succeeded(pulse, connection):
            show(pulse)
            return endCommitted(connection, screen: .refreshed)
        case .failed(let fetchFailure, let failure):
            return endUncommitted(fetchFailure, failure: failure)
        }
    }

    public func beginBackgroundDetailRefresh() -> PDTOnboardingUpdate? {
        guard let currentPulse, case let .connected(_, persistence) = state, isIdle else {
            return nil
        }
        return startBackgroundDetailRefresh(with: currentPulse, persistence)
    }

    public func backgroundDetailRefreshProgress(_ progress: BackgroundDetailRefreshProgress) -> PDTOnboardingUpdate? {
        guard backgroundDetailRefreshInFlight, currentPulse != nil else {
            return nil
        }
        screen = .detailProgress(progress)
        return currentUpdate()
    }

    public func completeBackgroundDetailRefresh(_ result: PDTLaunchBackgroundDetailRefreshResult) -> PDTOnboardingUpdate {
        guard backgroundDetailRefreshInFlight else {
            return currentUpdate()
        }
        backgroundDetailRefreshInFlight = false
        switch result {
        case let .succeeded(pulse, outcome, connection):
            show(pulse)
            return endCommitted(connection, screen: outcome == .degraded ? .detailDegraded : .refreshed)
        case let .failed(fetchFailure, failure):
            return endUncommitted(fetchFailure, failure: failure)
        }
    }

    /// Returns the menu for the pulse as shown, joined with the read store.
    public func replaceCurrentPulse(_ pulse: PulseLifecycleResult) -> MenuDescriptor? {
        show(pulse)
        return currentPulse?.descriptor
    }

    /// Call after the read store changes. Only the pulse rows change; the
    /// launch state and any running work are left as they are.
    public func pulseReadStateDidChange() -> PDTOnboardingUpdate? {
        guard let pulse = currentPulse else {
            return nil
        }
        show(pulse)
        return currentUpdate()
    }

    private var isIdle: Bool {
        !cachedPulseLoading && !connectionOperationInFlight && !firstFetchInFlight && !backgroundDetailRefreshInFlight
    }

    /// A connected result starts the one fetch that fits: a background refresh
    /// over a pulse on screen, or a first fetch when there is none.
    private func apply(_ status: PDTConnectionStatus) -> PDTOnboardingUpdate {
        guard case let .connected(persistence) = status else {
            return update(state: PDTLaunchState(status))
        }
        notice = nil
        if let currentPulse {
            return startBackgroundDetailRefresh(with: currentPulse, persistence)
        }
        return startFirstFetch(persistence)
    }

    /// A sync that committed a snapshot, with its pulse already shown: stay
    /// connected the way the connection now says, or show the connection
    /// screen that says why access is gone. The committed pulse carries the
    /// failure that lost it.
    private func endCommitted(_ connection: PDTConnectionStatus, screen: Screen) -> PDTOnboardingUpdate {
        guard case let .connected(persistence) = connection else {
            return update(state: PDTLaunchState(connection))
        }
        state = .connected(.current, persistence)
        self.screen = screen
        return currentUpdate()
    }

    /// A sync that committed nothing: keep its record, then show the connection
    /// state it found or the retryable failure.
    private func endUncommitted(_ fetchFailure: PDTFetchFailure, failure: PDTSyncFailure?) -> PDTOnboardingUpdate {
        uncommittedSync = UncommittedSync(failure: failure)
        switch fetchFailure {
        case .connection(let status):
            return apply(status)
        case .unavailable(let persistence):
            return update(state: .connected(.failed, persistence))
        }
    }

    private func startFirstFetch(_ persistence: PDTCredentialPersistence) -> PDTOnboardingUpdate {
        uncommittedSync = nil
        firstFetchInFlight = true
        return update(state: .connected(.fetching, persistence), effect: .startFirstFetch)
    }

    private func beginConnectionOperation(_ state: PDTLaunchState, effect: PDTOnboardingEffect) -> PDTOnboardingUpdate {
        if state != .checkingConnection || effect != .checkConnection {
            notice = nil
        }
        connectionAttempt = PDTConnectionAttempt(runtime: connectionAttempt.runtime, number: connectionAttempt.number + 1)
        connectionOperationInFlight = true
        return update(state: state, effect: effect)
    }

    private func show(_ pulse: PulseLifecycleResult?) {
        displayed.show(pulse)
    }

    private func startBackgroundDetailRefresh(
        with pulse: PulseLifecycleResult,
        _ persistence: PDTCredentialPersistence
    ) -> PDTOnboardingUpdate {
        uncommittedSync = nil
        backgroundDetailRefreshInFlight = true
        state = .connected(.fetching, persistence)
        screen = .detailProgress(BackgroundDetailRefreshProgress(phase: .baseHoldings))
        return currentUpdate(effect: .startBackgroundDetailRefresh)
    }

    private func update(
        state: PDTLaunchState,
        effect: PDTOnboardingEffect = .none,
        fetchingElapsedSeconds: Int? = nil
    ) -> PDTOnboardingUpdate {
        self.state = state
        screen = .launchState(fetchingElapsedSeconds: fetchingElapsedSeconds)
        return currentUpdate(effect: effect)
    }

    private func currentUpdate(effect: PDTOnboardingEffect = .none) -> PDTOnboardingUpdate {
        PDTOnboardingUpdate(state: state, descriptor: descriptor(), effect: effect)
    }

    private func descriptor() -> MenuDescriptor {
        // The only pulse menu this function may use: every screen that keeps a
        // pulse shows Data Health as this run knows it, never the pulse's own guess.
        guard let pulse = currentPulse else {
            return PDTLaunchMenu.descriptor(
                for: state,
                notice: notice,
                fetchingElapsedSeconds: screenElapsedSeconds,
                syncFailure: uncommittedSync?.failure
            )
        }
        let pulseMenu = pulse.descriptor(in: healthRuntime())
        guard case .connected = state else {
            return PDTLaunchMenu.descriptor(for: state, cachedPulse: pulseMenu, notice: notice)
        }
        let descriptor: MenuDescriptor
        switch screen {
        case .launchState(let elapsed):
            descriptor = PDTLaunchMenu.descriptor(for: state, cachedPulse: pulseMenu, fetchingElapsedSeconds: elapsed)
        case .detailProgress(let progress):
            descriptor = PDTLaunchMenu.descriptorForBackgroundDetailProgress(
                cachedPulse: pulseMenu,
                progress: progress,
                cachedSnapshotAsOf: pulse.model.asOf
            )
        case .detailDegraded:
            descriptor = PDTLaunchMenu.descriptorForBackgroundDetailDegraded(cachedPulse: pulseMenu)
        case .refreshed:
            descriptor = PDTLaunchMenu.descriptorWithRefreshDetailsAction(cachedPulse: pulseMenu)
        }
        return descriptor.withConnectionActions(for: state)
    }

    private var screenElapsedSeconds: Int? {
        if case let .launchState(elapsed) = screen {
            return elapsed
        }
        return nil
    }

    private var isFetching: Bool {
        if case .connected(.fetching, _) = state {
            return true
        }
        return false
    }

    private func healthRuntime() -> DataHealthRuntime {
        let sync: DataHealthSync = switch (screen, uncommittedSync) {
        case (.detailProgress(let progress), _):
            .running(progress)
        case (_, let uncommitted?):
            .failed(uncommitted.failure)
        case (_, nil):
            isFetching ? .running(BackgroundDetailRefreshProgress(phase: .baseHoldings)) : .idle
        }
        return DataHealthRuntime(access: DataHealthAccess(state), sync: sync)
    }
}
