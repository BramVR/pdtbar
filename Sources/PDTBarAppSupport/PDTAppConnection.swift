import Foundation
import PDTBarCore
import Security

/// The app's one PDT connection: credential store, browser sign-in, pasted
/// token, disconnect, and the API client over the same `PDTConnection`. Every
/// method blocks (the store lock can wait on another process's refresh), so
/// call them off the main queue. Every store and API error becomes a
/// `PDTConnectionStatus` or `PDTFetchFailure` here; callers never see an
/// `OSStatus`, `PDTCredentialStoreError`, or `PDTAPIError`.
public final class PDTAppConnection: @unchecked Sendable {
    public typealias SignIn = (PDTCancellation) throws -> PDTBrowserSession

    /// The snapshot date a script pins; nil in production.
    public let asOf: String?
    private let connection: PDTConnection
    private let apiTransport: any PDTHTTPTransport
    private let runSignIn: SignIn
    private let log: (@Sendable (String) -> Void)?

    public init(
        store: any PDTCredentialStore,
        tokenEndpoint: PDTTokenEndpoint,
        apiTransport: any PDTHTTPTransport,
        signIn: @escaping SignIn,
        asOf: String? = nil,
        log: (@Sendable (String) -> Void)? = nil
    ) {
        connection = PDTConnection(store: store, tokenEndpoint: tokenEndpoint)
        self.apiTransport = apiTransport
        runSignIn = signIn
        self.asOf = asOf
        self.log = log
    }

    /// URLSession and browser sign-in over the Keychain store (lock in
    /// `<appSupport>/pdtbar`), or over a dev file store when `credentialFile` is set.
    public static func production(
        appSupportDirectory: URL,
        credentialFile: URL? = nil,
        openBrowser: @escaping @Sendable (URL) throws -> Void
    ) -> PDTAppConnection {
        let transport = URLSessionPDTHTTPTransport()
        let tokenEndpoint = PDTTokenEndpoint(transport: transport)
        let store: any PDTCredentialStore = credentialFile.map { FilePDTCredentialStore(url: $0) }
            ?? KeychainPDTCredentialStore(lockDirectory: appSupportDirectory.appending(path: "pdtbar"))
        return PDTAppConnection(
            store: store,
            tokenEndpoint: tokenEndpoint,
            apiTransport: transport,
            signIn: { cancellation in
                try PDTBrowserSignIn(tokenEndpoint: tokenEndpoint, openBrowser: openBrowser).run(cancellation: cancellation)
            }
        )
    }

    public func check() -> PDTConnectionOutcome {
        log?("check")
        return PDTConnectionOutcome(connection.status())
    }

    public func signIn(cancellation: PDTCancellation) -> PDTConnectionOutcome {
        log?("sign-in")
        let session: PDTBrowserSession
        do {
            session = try runSignIn(cancellation)
        } catch PDTSignInError.cancelled {
            return PDTConnectionOutcome(connection.status())
        } catch let error as PDTSignInError {
            return PDTConnectionOutcome(connection.status(), notice: .signInFailed(PDTSignInFailure(error)))
        } catch {
            return PDTConnectionOutcome(connection.status(), notice: .signInFailed(.failed))
        }
        // A cancel during the code exchange or the wait for the store lock still wins.
        // The connection uses a session the store refuses, and its status says it is not saved.
        _ = try? connection.signedIn(session, unless: cancellation)
        return PDTConnectionOutcome(connection.status())
    }

    public func connect(token: PDTAPIToken) -> PDTConnectionOutcome {
        log?("token")
        try? connection.connect(personalToken: token)
        return PDTConnectionOutcome(connection.status())
    }

    /// Deletes the credential and names the PDT page where the user removes
    /// PDTBar's access: connected apps for a sign-in, Integrations for a token.
    public func disconnect() -> PDTConnectionOutcome {
        log?("disconnect")
        let revokeAt = storedKind() == .personalToken ? PDTOAuthEndpoints.integrations : PDTOAuthEndpoints.connectedApps
        _ = try? connection.disconnect()
        let status = connection.status()
        // The notice says the credential is gone, so it waits for a delete the store took.
        guard case .notConnected = status else {
            return PDTConnectionOutcome(status)
        }
        return PDTConnectionOutcome(status, notice: .disconnected(revokeAt: revokeAt))
    }

    /// A log line for a fetch error that carries no server text: PDT's
    /// `details.reason` and decode messages can echo request data.
    public static func logLabel(for error: Error) -> String {
        let error = (error as? PDTAPIRequestFailure)?.underlyingError ?? error
        switch error {
        case PDTAPIError.tokenInvalid:
            return "tokenInvalid"
        case let error as PDTAPIError:
            return "\(error)"
        case let error as PDTCredentialStoreError:
            return "\(error)"
        default:
            return String(describing: type(of: error))
        }
    }

    public func apiClient() -> PDTAPIClient {
        PDTAPIClient(transport: apiTransport, tokenProvider: connection)
    }

    /// Sorts a thrown fetch error. Only the fact a `PDTSyncFailure.Kind` drops
    /// is read here: PDT's token-invalid reason.
    public func failure(for error: Error) -> PDTFetchFailure {
        let error = (error as? PDTAPIRequestFailure)?.underlyingError ?? error
        if case let .tokenInvalid(reason)? = error as? PDTAPIError {
            return rejected(PDTReconnectCause(tokenInvalidReason: reason))
        }
        return failure(for: PDTSyncFailure.Kind(error))
    }

    /// What a failed request means for the connection, whichever phase it ran
    /// in. `PDTConnection` has already stored or held `needsReconnect` for a
    /// rejected refresh or token, so its status decides those. Every other
    /// failure, a plain `403` included, is retryable while the connection
    /// still says connected, and reports how the credential is kept.
    public func failure(for kind: PDTSyncFailure.Kind) -> PDTFetchFailure {
        switch kind {
        case .accessPaused:
            return .connection(.subscriptionPaused)
        case .readAccessMissing:
            return .connection(.needsReconnect(storedKind() ?? .personalToken, .readAccessMissing))
        case .reconnect:
            return rejected(.tokenInvalid)
        case .credentialStore, .forbidden, .rateLimited, .network, .server, .unreadableResponse, .unexpected, .cancelled:
            let status = connection.status()
            guard case let .connected(persistence) = status else {
                return .connection(status)
            }
            return .unavailable(persistence)
        }
    }

    private func rejected(_ cause: PDTReconnectCause) -> PDTFetchFailure {
        let status = connection.status()
        guard case .connected = status else {
            return .connection(status)
        }
        return .connection(.needsReconnect(storedKind() ?? .personalToken, cause))
    }

    /// What the connection is after a sync that committed a snapshot: the
    /// state its ending failure names when an optional phase lost access,
    /// else what `PDTConnection` says now. With `failure(for:)` this is where
    /// every finished sync reports the connection, so a credential that is
    /// not saved is never reported as saved.
    public func status(afterSyncEnding failure: PDTSyncFailure.Kind?) -> PDTConnectionStatus {
        if let failure, case let .connection(status) = self.failure(for: failure) {
            return status
        }
        return connection.status()
    }

    private func storedKind() -> PDTCredentialKind? {
        switch try? connection.state() {
        case let .connected(credential): credential.kind
        case let .needsReconnect(kind, _): kind
        case .disconnected, nil: nil
        }
    }
}

/// `--scripted-pdt <file>`: an offline connection for smokes. It never builds
/// the production store, URLSession, or browser: the credential lives in
/// memory, or in the Keychain store over a fake SecItem API (`keychain`, or
/// `keychainStatus` answered to every call), never the real Keychain. Sign-in
/// is scripted, and API replies come from `api` in request order.
public struct ScriptedPDTConnection: Codable, Equatable, Sendable {
    public enum StoredConnection: String, Codable, Sendable {
        case notConnected, browserSession, personalToken, signInExpired, tokenRevoked
    }

    public enum SignInOutcome: String, Codable, Sendable {
        case succeeds, denied, portBusy, timedOut, waitsForCancel
    }

    /// The Keychain as a kind of build sees it. It starts empty, whatever `connection` says.
    public enum Keychain: String, Codable, Sendable {
        /// Measured on an ad-hoc signed build: a read finds nothing (-25300),
        /// every write is refused (-34018), and the signature has no
        /// `keychain-access-groups`.
        case unentitled
    }

    public var connection: StoredConnection
    public var keychainStatus: Int32?
    public var keychain: Keychain?
    public var signIn: SignInOutcome?
    public var signInDelaySeconds: Double?
    public var api: ScriptedPDTAPIConfiguration
    /// Appends one line per check, sign-in, token, disconnect, and API request path.
    public var eventLog: String?

    public init(
        connection: StoredConnection,
        keychainStatus: Int32? = nil,
        keychain: Keychain? = nil,
        signIn: SignInOutcome? = nil,
        signInDelaySeconds: Double? = nil,
        api: ScriptedPDTAPIConfiguration = ScriptedPDTAPIConfiguration(responses: []),
        eventLog: String? = nil
    ) {
        self.connection = connection
        self.keychainStatus = keychainStatus
        self.keychain = keychain
        self.signIn = signIn
        self.signInDelaySeconds = signInDelaySeconds
        self.api = api
        self.eventLog = eventLog
    }

    public static func load(_ url: URL) throws -> ScriptedPDTConnection {
        try JSONDecoder().decode(ScriptedPDTConnection.self, from: Data(contentsOf: url))
    }

    public func appConnection(lockDirectory: URL) throws -> PDTAppConnection {
        let log = eventLog.map(ScriptedEventLog.init(path:))
        let store: any PDTCredentialStore
        if keychain == .unentitled {
            store = KeychainPDTCredentialStore(lockDirectory: lockDirectory, secItem: .unentitled)
        } else if let keychainStatus {
            store = KeychainPDTCredentialStore(lockDirectory: lockDirectory, secItem: .answering(keychainStatus))
        } else {
            store = InMemoryPDTCredentialStore(Self.storedState(connection))
        }
        let outcome = signIn ?? .succeeds
        let delay = signInDelaySeconds ?? 0
        var record: (@Sendable (String) -> Void)?
        if let log {
            record = { line in log.append(line) }
        }
        return PDTAppConnection(
            store: store,
            tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
            apiTransport: LoggingPDTHTTPTransport(base: api.transport(), log: log),
            signIn: { cancellation in try ScriptedPDTConnection.scriptedSignIn(outcome, delay: delay, cancellation: cancellation) },
            asOf: api.asOf,
            log: record
        )
    }

    static func storedState(_ connection: StoredConnection) -> PDTConnectionState {
        switch connection {
        case .notConnected:
            .disconnected
        case .browserSession:
            .connected(.browserSession(scriptedSession))
        case .personalToken:
            .connected(.personalToken(PDTAPIToken("scripted-personal-token")))
        case .signInExpired:
            .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("scripted-refresh").fingerprint))
        case .tokenRevoked:
            .needsReconnect(.personalToken, .tokenRejected(reason: "revoked"))
        }
    }

    private static var scriptedSession: PDTBrowserSession {
        PDTBrowserSession(
            accessToken: PDTAPIToken("scripted-access"),
            refreshToken: PDTRefreshToken("scripted-refresh"),
            accessExpiresAt: Date.distantFuture
        )
    }

    private static func scriptedSignIn(_ outcome: SignInOutcome, delay: Double, cancellation: PDTCancellation) throws -> PDTBrowserSession {
        let deadline = Date().addingTimeInterval(outcome == .waitsForCancel ? 600 : delay)
        while Date() < deadline {
            if cancellation.isCancelled {
                throw PDTSignInError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        switch outcome {
        case .succeeds: return scriptedSession
        case .denied: throw PDTSignInError.accessDenied
        case .portBusy: throw PDTSignInError.portBusy(port: PDTOAuthClient.pdtbar.redirectPort)
        case .timedOut, .waitsForCancel: throw PDTSignInError.timedOut
        }
    }
}

private final class ScriptedEventLog: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    init(path: String) {
        url = URL(fileURLWithPath: path)
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}

private struct LoggingPDTHTTPTransport: PDTHTTPTransport {
    let base: any PDTHTTPTransport
    let log: ScriptedEventLog?

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        log?.append("request \(request.url?.path ?? "")")
        return try base.send(request, cancellation: cancellation)
    }
}

private extension KeychainPDTCredentialStore.SecItemAPI {
    static func answering(_ status: OSStatus) -> Self {
        Self(
            copyMatching: { _, _ in status }, add: { _ in status }, update: { _, _ in status }, delete: { _ in status },
            isEntitled: status != errSecMissingEntitlement
        )
    }

    static let unentitled = Self(
        copyMatching: { _, _ in errSecItemNotFound },
        add: { _ in errSecMissingEntitlement },
        update: { _, _ in errSecMissingEntitlement },
        delete: { _ in errSecMissingEntitlement },
        isEntitled: false
    )
}
