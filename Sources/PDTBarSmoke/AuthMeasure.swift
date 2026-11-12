import CryptoKit
import Foundation
import PDTBarAppSupport
import PDTBarCore
import PDTBarSmokeProof
import Security

// `pdtbar-smoke auth-measure`: scores the sign-in, credential, and connection
// lifecycle over the real `PDTLaunchRuntime` and `PDTAppConnection`. Everything
// around them is fake: PDT, the Keychain, the browser. Nothing leaves a temp directory.

struct AuthMeasureRun {
    var status: String
    var detail: String
    var artifacts: [String]
}

func authMeasure(arguments: [String]) throws -> AuthMeasureRun {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var artifacts = root.appending(path: ".build/pdtbar-smoke-artifacts")
    guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--artifacts") else {
        throw AuthMeasureError("usage: pdtbar-smoke auth-measure [--artifacts <dir>]")
    }
    if arguments.count == 2 {
        artifacts = URL(fileURLWithPath: arguments[1])
    }
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

    let fixtures = try AuthMeasureFixtures(directory: root.appending(path: "docs/pdt/fixtures/api/full"))
    let scratch = FileManager.default.temporaryDirectory.appending(path: "pdtbar-auth-measure-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let neverSignedIn = PDTLaunchState.notConnected(signInWouldBe: .saved)
    let neverConnected = authMeasureScreen(PDTLaunchMenu.descriptor(for: neverSignedIn), state: neverSignedIn, idle: true)
    guard let silentDetail = neverConnected.statusRow?.detail else {
        throw AuthMeasureError("the not-connected menu has no status detail")
    }

    let report = AuthMeasureReport(scenarios: authMeasureScenarios.map { scenario in
        let world = AuthMeasureWorld(scenario: scenario, fixtures: fixtures, directory: scratch.appending(path: scenario.id))
        var failure: String?
        do {
            try world.run()
        } catch {
            failure = "\(error)".replacingOccurrences(of: scratch.path, with: "<scratch>")
        }
        return AuthMeasureScenario(
            id: scenario.id,
            steps: world.steps,
            goalReached: failure == nil && world.goalReached,
            osPrompts: world.measuredOSPrompts,
            silentDetail: silentDetail,
            error: failure
        )
    })

    var data = try stableJSONData(report)
    data.append(contentsOf: "\n".utf8)
    let file = artifacts.appending(path: "pdtbar-auth-measure.json")
    try data.write(to: file, options: .atomic)
    let totals = report.totals
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return AuthMeasureRun(
        status: report.status,
        detail: "report sha256 \(hash); penalty \(totals.penalty) over \(report.scenarioCount) scenarios: clicks \(totals.clicks), "
            + "silent sign-outs \(totals.silentSignOuts), dead ends \(totals.deadEnds), OS prompts \(totals.osPrompts), "
            + "unnamed states \(totals.unnamedStates), errors \(report.errorCount)",
        artifacts: [file.path]
    )
}

struct AuthMeasureError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Scenarios

private struct AuthScenario {
    enum Store {
        /// `KeychainPDTCredentialStore` over the fake keychain of that build.
        case keychain(AuthMeasureKeychain.Build)
        /// `FilePDTCredentialStore`: the `--pdt-credential-file` dev path.
        case file
    }

    /// What is stored before the first launch, and what PDT thinks of it.
    enum Stored {
        case nothing
        case browserSession(accessExpiresAt: Date, accessLive: Bool, refreshLive: Bool)
        case revokedPersonalToken
    }

    enum Action {
        case launch
        case relaunch
        /// Sign in with PDT, when the menu offers it.
        case signIn
        /// Check again when offered, else a fetch retry or refresh when offered.
        case checkAgainOrRefresh
        case disconnect
        /// The deterministic user: Sign in, else Check again, else retry, until the goal or the click budget.
        case userPolicy
    }

    var id: String
    var store: Store
    var stored = Stored.nothing
    var cachedPulse = false
    /// PDT revokes every token it issued when this path is first requested.
    var revokeOnRequest: PDTAPIEndpoint?
    /// Brings the scenario to its starting state. Shown in the report, never scored.
    var setup: [Action] = []
    var actions: [Action]
}

private let authMeasureExpired = Date(timeIntervalSince1970: 0)
private let authMeasureFarFuture = Date(timeIntervalSince1970: 4_102_444_800)
private let authMeasureSignedIn: [AuthScenario.Action] = [.launch, .signIn]

private let authMeasureScenarios: [AuthScenario] = [
    AuthScenario(id: "signin-entitled", store: .keychain(.entitled), actions: [.launch, .userPolicy]),
    AuthScenario(id: "signin-unentitled", store: .keychain(.adHoc), actions: [.launch, .userPolicy]),
    AuthScenario(id: "checkagain-entitled", store: .keychain(.entitled), setup: authMeasureSignedIn, actions: [.checkAgainOrRefresh]),
    AuthScenario(id: "checkagain-unentitled", store: .keychain(.adHoc), setup: authMeasureSignedIn, actions: [.checkAgainOrRefresh]),
    AuthScenario(id: "relaunch-entitled", store: .keychain(.entitled), setup: authMeasureSignedIn, actions: [.relaunch, .userPolicy]),
    AuthScenario(id: "relaunch-unentitled", store: .keychain(.adHoc), setup: authMeasureSignedIn, actions: [.relaunch, .userPolicy]),
    AuthScenario(
        id: "expired-refresh-ok", store: .keychain(.entitled),
        stored: .browserSession(accessExpiresAt: authMeasureExpired, accessLive: false, refreshLive: true),
        actions: [.launch, .userPolicy]
    ),
    AuthScenario(
        id: "expired-refresh-fails", store: .keychain(.entitled),
        stored: .browserSession(accessExpiresAt: authMeasureExpired, accessLive: false, refreshLive: false),
        actions: [.launch, .userPolicy]
    ),
    AuthScenario(
        id: "401-base", store: .keychain(.entitled),
        stored: .browserSession(accessExpiresAt: authMeasureFarFuture, accessLive: false, refreshLive: true),
        actions: [.launch, .userPolicy]
    ),
    AuthScenario(
        id: "401-optional", store: .keychain(.entitled),
        stored: .browserSession(accessExpiresAt: authMeasureFarFuture, accessLive: true, refreshLive: true),
        cachedPulse: true, revokeOnRequest: .distributions,
        actions: [.launch, .userPolicy]
    ),
    AuthScenario(id: "revoked", store: .keychain(.entitled), stored: .revokedPersonalToken, actions: [.launch, .userPolicy]),
    AuthScenario(id: "disconnect", store: .keychain(.entitled), setup: authMeasureSignedIn, actions: [.disconnect, .userPolicy]),
    AuthScenario(id: "dev-file", store: .file, setup: authMeasureSignedIn, actions: [.relaunch, .userPolicy]),
]

// MARK: - Fake PDT

/// The `full` API fixture, answered by request path instead of request order,
/// so a product change that sends one request more or less still gets PDT's answer.
private struct AuthMeasureFixtures {
    private let files: [String: Data]

    init(directory: URL) throws {
        files = Dictionary(uniqueKeysWithValues: try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { ($0.deletingPathExtension().lastPathComponent, try Data(contentsOf: $0)) })
    }

    var holdings: Data? { files["01-holdings"] }

    func body(for url: URL) -> Data? {
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        guard url.path.hasPrefix("/v1/"), let endpoint = PDTAPIEndpoint(rawValue: String(url.path.dropFirst(4))) else {
            return nil
        }
        switch endpoint {
        case .holdings: return files["01-holdings"]
        case .distributions: return files["02-distributions"]
        case .xRay: return files[(query["offset"] ?? "0") == "0" ? "03-x-ray-page-1" : "04-x-ray-page-2"]
        case .calendarEvents: return files[query["page"] == "2" ? "06-calendar-events-page-2" : "05-calendar-events-page-1"]
        case .dividends: return files["07-dividends"]
        case .symbolQuotes: return files.first { $0.key.hasSuffix("-symbol-quotes-\(query["symbolId"] ?? "")") }?.value
        case .pricesBatch: return files["14-prices-batch"]
        case .portfolios, .performance, .gains, .me, .personalAccessTokens: return nil
        }
    }
}

/// PDT's token endpoint and REST API with the server side of every credential:
/// which access and refresh tokens are live. A request with a dead token gets
/// `401 TOKEN_INVALID`, a dead refresh token gets `invalid_grant`, and a live
/// one rotates the pair. Replies are `ScriptedPDTHTTPTransport` replies.
private final class FakePDT: PDTHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let fixtures: AuthMeasureFixtures
    private var revokeOnRequest: PDTAPIEndpoint?
    private var liveAccess: Set<String> = []
    private var accessByLiveRefresh: [String: String] = [:]
    private var deadReasons: [String: String] = [:]
    private var minted = 0
    private var rejectionCount = 0
    private var approvalCount = 0

    init(fixtures: AuthMeasureFixtures, revokeOnRequest: PDTAPIEndpoint?) {
        self.fixtures = fixtures
        self.revokeOnRequest = revokeOnRequest
    }

    var rejections: Int { locked { rejectionCount } }
    var approvals: Int { locked { approvalCount } }

    /// The browser half of Sign in with PDT: the user approves, PDT issues a session.
    func approveSignIn() -> PDTBrowserSession {
        locked {
            approvalCount += 1
            return mint(accessExpiresAt: authMeasureFarFuture, accessLive: true, refreshLive: true)
        }
    }

    func issueSession(accessExpiresAt: Date, accessLive: Bool, refreshLive: Bool) -> PDTBrowserSession {
        locked { mint(accessExpiresAt: accessExpiresAt, accessLive: accessLive, refreshLive: refreshLive) }
    }

    func issueRevokedPersonalToken() -> PDTAPIToken {
        locked {
            deadReasons["fake-personal-token"] = "revoked"
            return PDTAPIToken("fake-personal-token")
        }
    }

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        let reply = locked { request.url == PDTOAuthEndpoints.token ? tokenReply(request) : apiReply(request) }
        return try ScriptedPDTHTTPTransport([reply]).send(request, cancellation: cancellation)
    }

    private func mint(accessExpiresAt: Date, accessLive: Bool, refreshLive: Bool) -> PDTBrowserSession {
        minted += 1
        let access = "fake-access-\(minted)"
        let refresh = "fake-refresh-\(minted)"
        if accessLive {
            liveAccess.insert(access)
        }
        if refreshLive {
            accessByLiveRefresh[refresh] = access
        }
        return PDTBrowserSession(
            accessToken: PDTAPIToken(access), refreshToken: PDTRefreshToken(refresh), accessExpiresAt: accessExpiresAt
        )
    }

    private func tokenReply(_ request: URLRequest) -> ScriptedPDTHTTPTransport.Reply {
        let form = String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&")
        let refresh = form.first { $0.hasPrefix("refresh_token=") }.map { String($0.dropFirst("refresh_token=".count)) }
        guard let refresh, let access = accessByLiveRefresh.removeValue(forKey: refresh) else {
            rejectionCount += 1
            return .response(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        // PDT rotates both tokens and revokes the previous access token at once.
        liveAccess.remove(access)
        _ = mint(accessExpiresAt: authMeasureFarFuture, accessLive: true, refreshLive: true)
        return .response(status: 200, body: Data(
            #"{"access_token":"fake-access-\#(minted)","expires_in":3600,"refresh_token":"fake-refresh-\#(minted)","token_type":"Bearer"}"#.utf8
        ))
    }

    private func apiReply(_ request: URLRequest) -> ScriptedPDTHTTPTransport.Reply {
        guard let url = request.url else {
            return .failure(.badURL)
        }
        if let path = revokeOnRequest?.rawValue, url.path == "/v1/\(path)" {
            revokeOnRequest = nil
            liveAccess = []
            accessByLiveRefresh = [:]
        }
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        guard liveAccess.contains(token) else {
            rejectionCount += 1
            let reason = deadReasons[token] ?? "invalid"
            return .response(status: 401, body: Data(
                #"{"error":{"code":"TOKEN_INVALID","message":"m","details":{"reason":"\#(reason)"},"traceId":"t"}}"#.utf8
            ))
        }
        guard let body = fixtures.body(for: url) else {
            return .response(status: 404, body: Data(#"{"error":{"code":"NOT_FOUND","message":"m","details":{},"traceId":"t"}}"#.utf8))
        }
        return .response(status: 200, body: body)
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Fake keychain

/// `AuthMeasureKeychain` behind the `SecItem` calls `KeychainPDTCredentialStore` makes.
private final class FakeSecItems: @unchecked Sendable {
    private let lock = NSLock()
    private var keychain: AuthMeasureKeychain

    init(build: AuthMeasureKeychain.Build) {
        keychain = AuthMeasureKeychain(build: build)
    }

    var osPrompts: Int { locked { $0.osPrompts } }

    func relaunch() {
        locked { $0.relaunch() }
    }

    var api: KeychainPDTCredentialStore.SecItemAPI {
        KeychainPDTCredentialStore.SecItemAPI(
            copyMatching: { query, result in
                let (status, data) = self.locked { $0.copy(Self.domain(query)) }
                if let data {
                    result?.pointee = data as CFData
                }
                return status
            },
            add: { query in
                self.locked { $0.add(Self.domain(query), data: Self.data(in: query)) }
            },
            update: { query, changes in
                self.locked { $0.update(Self.domain(query), data: Self.data(in: changes)) }
            },
            delete: { query in
                self.locked { $0.delete(Self.domain(query)) }
            },
            isEntitled: locked { $0.build == .entitled }
        )
    }

    private static func domain(_ query: CFDictionary) -> AuthMeasureKeychain.Domain {
        (query as NSDictionary)[kSecUseDataProtectionKeychain as String] as? Bool == true ? .dataProtection : .login
    }

    private static func data(in attributes: CFDictionary) -> Data {
        (attributes as NSDictionary)[kSecValueData as String] as? Data ?? Data()
    }

    private func locked<Value>(_ body: (inout AuthMeasureKeychain) -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body(&keychain)
    }
}

// MARK: - Driver

/// One scenario: PDT, the credential store's backing data, and the app's state
/// directory outlive a relaunch. The runtime and the connection do not.
private final class AuthMeasureWorld: @unchecked Sendable {
    private static let asOf = "2026-06-22"
    private static let clickBudget = 6

    private let scenario: AuthScenario
    private let fixtures: AuthMeasureFixtures
    private let directory: URL
    private let pdt: FakePDT
    private let secItems: FakeSecItems?
    private var runtime = PDTLaunchRuntime()
    private var connection: PDTAppConnection?
    private var everHadCredential = false
    private var userDisconnected = false
    private var inSetup = false
    private var policyClicks = 0
    private var osPromptsBeforeMeasuring = 0
    private var screens: [AuthMeasureScreen] = []
    private(set) var steps: [AuthMeasureStep] = []

    init(scenario: AuthScenario, fixtures: AuthMeasureFixtures, directory: URL) {
        self.scenario = scenario
        self.fixtures = fixtures
        self.directory = directory
        pdt = FakePDT(fixtures: fixtures, revokeOnRequest: scenario.revokeOnRequest)
        if case let .keychain(build) = scenario.store {
            secItems = FakeSecItems(build: build)
        } else {
            secItems = nil
        }
    }

    var goalReached: Bool {
        guard case .connected(.current, _) = runtime.state else {
            return false
        }
        return runtime.currentPulse != nil && isIdle
    }

    var measuredOSPrompts: Int {
        (secItems?.osPrompts ?? 0) - osPromptsBeforeMeasuring
    }

    func run() throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try seed()
        inSetup = true
        try scenario.setup.forEach(perform)
        inSetup = false
        osPromptsBeforeMeasuring = secItems?.osPrompts ?? 0
        try scenario.actions.forEach(perform)
    }

    private var stateDirectory: URL { directory.appending(path: "pdtbar/state") }

    private var isIdle: Bool {
        !runtime.cachedPulseLoading && !runtime.connectionOperationInFlight
            && !runtime.firstFetchInFlight && !runtime.backgroundDetailRefreshInFlight
    }

    private func makeStore() -> any PDTCredentialStore {
        if let secItems {
            return KeychainPDTCredentialStore(lockDirectory: directory.appending(path: "pdtbar"), secItem: secItems.api)
        }
        return FilePDTCredentialStore(url: directory.appending(path: "dev/pdt-credential.json"))
    }

    private func seed() throws {
        switch scenario.stored {
        case .nothing:
            break
        case let .browserSession(accessExpiresAt, accessLive, refreshLive):
            let session = pdt.issueSession(accessExpiresAt: accessExpiresAt, accessLive: accessLive, refreshLive: refreshLive)
            try makeStore().save(.connected(.browserSession(session)))
            everHadCredential = true
        case .revokedPersonalToken:
            try makeStore().save(.connected(.personalToken(pdt.issueRevokedPersonalToken())))
            everHadCredential = true
        }
        guard scenario.cachedPulse else {
            return
        }
        guard let holdings = fixtures.holdings else {
            throw AuthMeasureError("the holdings fixture is missing")
        }
        _ = try PDTCoalescedFirstPortfolioFetch(
            dataSource: PDTAPIDataSource(
                client: PDTAPIClient(
                    transport: ScriptedPDTHTTPTransport([.response(status: 200, body: holdings)]),
                    tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("seed"))
                ),
                options: .firstFetch
            ),
            snapshotStore: SnapshotStore(directory: stateDirectory),
            asOf: Self.asOf,
            pulseReadStore: PulseReadStore(directory: stateDirectory)
        ).fetch()
    }

    private func perform(_ action: AuthScenario.Action) throws {
        switch action {
        case .launch:
            try launch(.launch)
        case .relaunch:
            secItems?.relaunch()
            try launch(.relaunch)
        case .signIn:
            if offers("connectionSignIn") {
                try step(.signIn) { runtime.signIn() }
            }
        case .checkAgainOrRefresh:
            if offers("connectionCheck") {
                try step(.checkAgain) { runtime.checkAgain() }
            } else if offers("fetchRetry") {
                try step(.fetchRetry) { runtime.retryFirstFetch() }
            }
        case .disconnect:
            if offers("connectionDisconnect") {
                try step(.disconnect) { runtime.disconnect() }
            }
        case .userPolicy:
            try runUserPolicy()
        }
    }

    /// A new process: a new runtime and connection over the same store data and state directory.
    private func launch(_ action: AuthMeasureStep.Action) throws {
        let stateDirectory = stateDirectory
        let pdt = pdt
        runtime = PDTLaunchRuntime { try? PulseReadStore(directory: stateDirectory).load() }
        connection = PDTAppConnection(
            store: makeStore(),
            tokenEndpoint: PDTTokenEndpoint(transport: pdt),
            apiTransport: pdt,
            signIn: { _ in pdt.approveSignIn() },
            asOf: Self.asOf
        )
        try step(action) { runtime.launch() }
    }

    private func runUserPolicy() throws {
        // Sign in costs two clicks: the menu row, then the approval in the browser.
        let choices: [(role: String, action: AuthMeasureStep.Action, clicks: Int)] = [
            ("connectionSignIn", .signIn, 2), ("connectionCheck", .checkAgain, 1), ("fetchRetry", .fetchRetry, 1),
        ]
        while !goalReached {
            guard let choice = choices.first(where: { offers($0.role) }),
                  policyClicks + choice.clicks <= Self.clickBudget
            else {
                return
            }
            policyClicks += choice.clicks
            let accepted = try step(choice.action, clicks: choice.clicks) {
                switch choice.action {
                case .signIn: runtime.signIn()
                case .checkAgain: runtime.checkAgain()
                default: runtime.retryFirstFetch()
                }
            }
            guard accepted else {
                return
            }
        }
    }

    private func offers(_ role: String) -> Bool {
        isIdle && steps.last?.screens.last?.rows.contains { $0.role == role && $0.enabled } == true
    }

    /// Runs one launch or click to rest and records it. False when the runtime refused the click.
    @discardableResult
    private func step(_ action: AuthMeasureStep.Action, clicks: Int = 0, _ start: () -> PDTOnboardingUpdate?) throws -> Bool {
        let rejections = pdt.rejections
        let approvals = pdt.approvals
        screens = []
        let update = start()
        try settle(update)
        let approved = pdt.approvals > approvals
        if approved {
            everHadCredential = true
            userDisconnected = false
        }
        if action == .disconnect, update != nil {
            userDisconnected = true
        }
        steps.append(AuthMeasureStep(
            action: action,
            setup: inSetup,
            clicks: clicks,
            causeOwed: everHadCredential && !userDisconnected,
            approvedSignIn: approved,
            pdtRejections: pdt.rejections - rejections,
            screens: screens
        ))
        return update != nil
    }

    /// Runs every effect inline, the way `Sources/PDTBarApp/main.swift` runs them off the main queue.
    private func settle(_ first: PDTOnboardingUpdate?) throws {
        guard let connection else {
            throw AuthMeasureError("a click ran before the first launch")
        }
        var next = first
        var effects = 0
        while let update = next {
            record(update)
            effects += 1
            guard effects < 100 else {
                throw AuthMeasureError("the launch runtime did not come to rest")
            }
            switch update.effect {
            case .none, .cancelSignIn:
                next = nil
            case .loadCachedPulse:
                next = runtime.completeCachedPulseLoad(try? PressureRunner.cachedPulse(
                    snapshotStore: SnapshotStore(directory: stateDirectory),
                    pulseReadStore: PulseReadStore(directory: stateDirectory),
                    // The app reads the current day. Pinned so the report is the same on any day.
                    today: Self.asOf
                ))
            case .checkConnection:
                next = complete(connection.check())
            case .signIn:
                next = complete(connection.signIn(cancellation: PDTCancellation()))
            case let .connectToken(token):
                next = complete(connection.connect(token: token))
            case .disconnect:
                next = complete(connection.disconnect())
            case .startFirstFetch:
                next = runFirstFetch(connection)
            case .startBackgroundDetailRefresh:
                next = runBackgroundRefresh(connection)
            }
        }
    }

    private func complete(_ outcome: PDTConnectionOutcome) -> PDTOnboardingUpdate {
        runtime.completeConnection(outcome, for: runtime.connectionAttempt)
    }

    private func runFirstFetch(_ connection: PDTAppConnection) -> PDTOnboardingUpdate? {
        let snapshotStore = SnapshotStore(directory: stateDirectory)
        snapshotStore.setLastSyncFailure(nil)
        do {
            let pulse = try PDTCoalescedFirstPortfolioFetch(
                dataSource: PDTAPIDataSource(
                    client: connection.apiClient(),
                    options: .firstFetch,
                    onSyncFailure: { snapshotStore.setLastSyncFailure($0) }
                ),
                snapshotStore: snapshotStore,
                asOf: connection.asOf,
                pulseReadStore: PulseReadStore(directory: stateDirectory)
            ).fetch()
            record(runtime.completeFirstFetch(.succeeded(pulse, connection: connection.status(afterSyncEnding: nil))))
            return runtime.beginBackgroundDetailRefresh()
        } catch {
            return runtime.completeFirstFetch(.failed(connection.failure(for: error), failure: snapshotStore.lastSyncFailure()))
        }
    }

    private func runBackgroundRefresh(_ connection: PDTAppConnection) -> PDTOnboardingUpdate? {
        let snapshotStore = SnapshotStore(directory: stateDirectory)
        let refresh = PDTAPIBackgroundDetailRefresh(
            client: connection.apiClient(),
            snapshotStore: snapshotStore,
            pulseReadStore: PulseReadStore(directory: stateDirectory),
            asOf: connection.asOf
        )
        do {
            let result = try refresh.refresh(cancellation: PDTCancellation()) { progress in
                if let update = self.runtime.backgroundDetailRefreshProgress(progress) {
                    self.record(update)
                }
            }
            return runtime.completeBackgroundDetailRefresh(.succeeded(
                result.pulse,
                outcome: result.outcome,
                connection: connection.status(afterSyncEnding: result.failures.last?.kind)
            ))
        } catch {
            return runtime.completeBackgroundDetailRefresh(
                .failed(connection.failure(for: error), failure: snapshotStore.lastSyncFailure())
            )
        }
    }

    private func record(_ update: PDTOnboardingUpdate) {
        screens.append(authMeasureScreen(update.descriptor, state: update.state, idle: isIdle))
    }
}

private func authMeasureScreen(_ descriptor: MenuDescriptor, state: PDTLaunchState, idle: Bool) -> AuthMeasureScreen {
    let (name, kind): (String, AuthMeasureScreen.Kind) = switch state {
    case .checkingConnection: ("checkingConnection", .transient)
    case .connecting: ("connecting", .transient)
    case .disconnecting: ("disconnecting", .transient)
    case .notConnected: ("notConnected", .waiting)
    case let .needsReconnect(credential, cause): ("needsReconnect(\(credential.rawValue),\(cause.rawValue))", .waiting)
    case .subscriptionPaused: ("subscriptionPaused", .waiting)
    case .keychainUnavailable(.missingEntitlement): ("keychainUnavailable(missingEntitlement)", .waiting)
    case .keychainUnavailable(.failed): ("keychainUnavailable(failed)", .waiting)
    case .connected(.fetching, _): ("connected(fetching)", .transient)
    case .connected(.failed, _): ("connected(failed)", .waiting)
    case .connected(.current, _): ("connected(current)", .connectedCurrent)
    }
    // Roles the app wires to a click, in `makeMenuItem(from:)`.
    let clickable: Set<MenuRowRole> = [
        .connectionSignIn, .connectionToken, .connectionCancel, .connectionCheck, .connectionDisconnect, .connectionRevoke, .fetchRetry,
    ]
    let shown = clickable.union([.setupStatus, .setupFailure, .fetchStatus])
    func rows(_ row: MenuRow) -> [AuthMeasureScreen.Row] {
        let own = shown.contains(row.role)
            ? [AuthMeasureScreen.Row(
                id: row.id, role: row.role.rawValue, title: row.title, detail: row.detail, enabled: clickable.contains(row.role)
            )]
            : []
        return own + row.children.flatMap(rows)
    }
    return AuthMeasureScreen(
        state: name,
        kind: kind,
        statusTitle: descriptor.statusTitle,
        idle: idle,
        rows: descriptor.sections.flatMap(\.rows).flatMap(rows)
    )
}
