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

    /// Keychain store with its lock in `<appSupport>/pdtbar`, URLSession, and browser sign-in.
    public static func production(
        appSupportDirectory: URL,
        openBrowser: @escaping @Sendable (URL) throws -> Void
    ) -> PDTAppConnection {
        let transport = URLSessionPDTHTTPTransport()
        let tokenEndpoint = PDTTokenEndpoint(transport: transport)
        return PDTAppConnection(
            store: KeychainPDTCredentialStore(lockDirectory: appSupportDirectory.appending(path: "pdtbar")),
            tokenEndpoint: tokenEndpoint,
            apiTransport: transport,
            signIn: { cancellation in
                try PDTBrowserSignIn(tokenEndpoint: tokenEndpoint, openBrowser: openBrowser).run(cancellation: cancellation)
            }
        )
    }

    public func check() -> PDTConnectionOutcome {
        log?("check")
        return PDTConnectionOutcome(status())
    }

    public func signIn(cancellation: PDTCancellation) -> PDTConnectionOutcome {
        log?("sign-in")
        let session: PDTBrowserSession
        do {
            session = try runSignIn(cancellation)
        } catch PDTSignInError.cancelled {
            return PDTConnectionOutcome(status())
        } catch let error as PDTSignInError {
            return PDTConnectionOutcome(status(), notice: .signInFailed(PDTSignInFailure(error)))
        } catch {
            return PDTConnectionOutcome(status(), notice: .signInFailed(.failed))
        }
        do {
            try connection.signedIn(session)
        } catch {
            return PDTConnectionOutcome(PDTConnectionStatus(storeError: error))
        }
        return PDTConnectionOutcome(status())
    }

    public func connect(token: PDTAPIToken) -> PDTConnectionOutcome {
        log?("token")
        do {
            try connection.connect(personalToken: token)
        } catch {
            return PDTConnectionOutcome(PDTConnectionStatus(storeError: error))
        }
        return PDTConnectionOutcome(status())
    }

    /// Deletes the credential and names the PDT page where the user removes
    /// PDTBar's access: connected apps for a sign-in, Integrations for a token.
    public func disconnect() -> PDTConnectionOutcome {
        log?("disconnect")
        do {
            let revokeAt = storedKind() == .personalToken ? PDTOAuthEndpoints.integrations : PDTOAuthEndpoints.connectedApps
            try connection.disconnect()
            return PDTConnectionOutcome(status(), notice: .disconnected(revokeAt: revokeAt))
        } catch {
            return PDTConnectionOutcome(PDTConnectionStatus(storeError: error))
        }
    }

    public func apiClient() -> PDTAPIClient {
        PDTAPIClient(transport: apiTransport, tokenProvider: connection)
    }

    /// Sorts a fetch error. `PDTConnection` has already stored `needsReconnect`
    /// for a rejected refresh or token, so the stored state decides those.
    public func failure(for error: Error) -> PDTFetchFailure {
        let error = (error as? PDTAPIRequestFailure)?.underlyingError ?? error
        if error is PDTCredentialStoreError {
            return .connection(PDTConnectionStatus(storeError: error))
        }
        switch error as? PDTAPIError {
        case .apiAccessPaused:
            return .connection(.subscriptionPaused)
        case .insufficientScope:
            return .connection(.needsReconnect(storedKind() ?? .personalToken, .readAccessMissing))
        case .tokenInvalid(let reason):
            return rejected(PDTReconnectCause(tokenInvalidReason: reason))
        case .missingToken, .unauthenticated:
            return rejected(.tokenInvalid)
        default:
            return .unavailable
        }
    }

    private func rejected(_ cause: PDTReconnectCause) -> PDTFetchFailure {
        let status = status()
        guard status == .connected else {
            return .connection(status)
        }
        return .connection(.needsReconnect(storedKind() ?? .personalToken, cause))
    }

    private func status() -> PDTConnectionStatus {
        do {
            return PDTConnectionStatus(stored: try connection.state())
        } catch {
            return PDTConnectionStatus(storeError: error)
        }
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
/// memory (or in the Keychain store over a SecItem API that answers
/// `keychainStatus` to every call, never the real Keychain), sign-in is
/// scripted, and API replies come from `api` in request order.
public struct ScriptedPDTConnection: Codable, Equatable, Sendable {
    public enum StoredConnection: String, Codable, Sendable {
        case notConnected, browserSession, personalToken, signInExpired, tokenRevoked
    }

    public enum SignInOutcome: String, Codable, Sendable {
        case succeeds, denied, portBusy, timedOut, waitsForCancel
    }

    public var connection: StoredConnection
    public var keychainStatus: Int32?
    public var signIn: SignInOutcome?
    public var signInDelaySeconds: Double?
    public var api: ScriptedPDTAPIConfiguration
    /// Appends one line per check, sign-in, token, disconnect, and API request path.
    public var eventLog: String?

    public init(
        connection: StoredConnection,
        keychainStatus: Int32? = nil,
        signIn: SignInOutcome? = nil,
        signInDelaySeconds: Double? = nil,
        api: ScriptedPDTAPIConfiguration = ScriptedPDTAPIConfiguration(responses: []),
        eventLog: String? = nil
    ) {
        self.connection = connection
        self.keychainStatus = keychainStatus
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
        if let keychainStatus {
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
        Self(copyMatching: { _, _ in status }, add: { _ in status }, update: { _, _ in status }, delete: { _ in status })
    }
}
