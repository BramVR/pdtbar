import Foundation
import Security
import Testing
import PDTBarAppSupport
import PDTBarCore

/// #301 and ADR-0003 decision 3: on a build without the keychain access
/// entitlement the data protection keychain reads as empty (-25300) and refuses
/// every write (-34018). A sign-in there works until PDTBar quits, says it is
/// not saved, and is never signed out by a check.
@Suite("Sign-in persistence")
struct SignInPersistenceTests {
    @Test("Check again after sign-in never signs out, whether or not the Keychain can store the session")
    func checkAgainAfterSignInKeepsTheConnection() throws {
        for keychain in [FakeKeychain.unentitled, .entitled] {
            let persistence = keychain == .entitled ? PDTCredentialPersistence.saved : .thisSessionOnly(.missingEntitlement)
            let driver = try LaunchDriver(keychain: keychain)
            driver.launch()
            #expect(driver.runtime.state == .notConnected, "\(keychain)")

            try #require(driver.signIn(), "\(keychain): sign-in is offered at launch")
            #expect(driver.runtime.state == .connected(.fetching, persistence), "\(keychain)")

            // The first fetch finds the subscription paused, which is a screen that offers Check again.
            driver.endFirstFetch(driver.connection.failure(for: PDTSyncFailure.Kind.accessPaused))
            #expect(driver.runtime.state == .subscriptionPaused, "\(keychain)")
            try #require(driver.checkAgain(), "\(keychain)")
            #expect(driver.runtime.state == .connected(.fetching, persistence), "\(keychain): Check again signed the user out")
            #expect(driver.connection.check().status == .connected(persistence), "\(keychain): a later check lost the session")
        }
    }

    @Test("A sign-in or token the Keychain refuses connects for the session: the fetch starts, the menu says it is not saved, and requests carry it")
    func unsavedCredentialConnectsForTheSession() throws {
        let ok = ScriptedPDTHTTPTransport.Reply.response(status: 200, body: Data("{}".utf8))
        let signedIn = try LaunchDriver(keychain: .unentitled, api: [ok])
        signedIn.launch()
        try #require(signedIn.signIn())
        let pasted = try LaunchDriver(keychain: .unentitled, api: [ok])
        pasted.launch()
        try #require(pasted.connect(token: PDTAPIToken("pdt_pasted")))

        for (driver, authorization) in [(signedIn, "Bearer access"), (pasted, "Bearer pdt_pasted")] {
            #expect(driver.runtime.state == .connected(.fetching, .thisSessionOnly(.missingEntitlement)), "\(authorization)")
            #expect(driver.last?.effect == .startFirstFetch, "\(authorization)")
            #expect(driver.last?.descriptor.statusTitle == "Fetching portfolio", "\(authorization)")
            #expect(driver.rows.map(\.id) == ["portfolioFetch.status", "pdtConnection.notSaved"], "\(authorization)")
            #expect(driver.rows.last?.title == "Connection not saved", "\(authorization)")
            #expect(
                driver.rows.last?.detail == "This PDTBar build can't save to the Keychain. You stay connected until you quit",
                "\(authorization)"
            )

            _ = try driver.connection.apiClient().get(.me)
            #expect(driver.api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [authorization])
            #expect(driver.connection.status(afterSyncEnding: nil) == .connected(.thisSessionOnly(.missingEntitlement)), "\(authorization)")
        }
    }

    @Test("A session the Keychain cannot store survives a token PDT stops accepting: it refreshes, retries, and stays connected")
    func unsavedSessionRefreshesAfterA401() throws {
        let driver = try LaunchDriver(
            keychain: .unentitled,
            api: [tokenInvalid("expired"), .response(status: 200, body: Data("{}".utf8)), .response(status: 200, body: Data("{}".utf8))],
            tokens: [tokenReply(access: "access-2", refresh: "refresh-2")]
        )
        driver.launch()
        try #require(driver.signIn())

        _ = try driver.connection.apiClient().get(.me)
        _ = try driver.connection.apiClient().get(.me)

        #expect(driver.api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access", "Bearer access-2", "Bearer access-2"])
        #expect(driver.tokens.requests.count == 1)
        #expect(driver.connection.check().status == .connected(.thisSessionOnly(.missingEntitlement)))
    }

    @Test("PDT rejecting a credential the Keychain never saved asks for a reconnect and never sends it again")
    func rejectedUnsavedCredentialNeedsReconnect() throws {
        let signedIn = try LaunchDriver(keychain: .unentitled, api: [tokenInvalid("revoked")], tokens: [oauthError("invalid_grant")])
        signedIn.launch()
        try #require(signedIn.signIn())
        let pasted = try LaunchDriver(keychain: .unentitled, api: [tokenInvalid("revoked")])
        pasted.launch()
        try #require(pasted.connect(token: PDTAPIToken("pdt_pasted")))

        let cases: [(LaunchDriver, PDTConnectionStatus, PDTLaunchState)] = [
            (signedIn, .needsReconnect(.browserSession, .signInExpired), .needsReconnect(.browserSession, .signInExpired)),
            (pasted, .needsReconnect(.personalToken, .tokenRevoked), .needsReconnect(.personalToken, .tokenRevoked)),
        ]
        for (driver, reconnect, screen) in cases {
            do {
                _ = try driver.connection.apiClient().get(.me)
                Issue.record("\(reconnect): PDT rejected the credential and the request still succeeded")
            } catch {
                driver.endFirstFetch(driver.connection.failure(for: error))
            }

            #expect(driver.runtime.state == screen)
            #expect(driver.rows.map(\.id).contains("pdtConnection.signIn"), "\(reconnect)")
            #expect(driver.connection.check().status == reconnect)
            #expect(throws: PDTAPIError.self) { try driver.connection.apiClient().get(.me) }
            #expect(driver.api.requests.count == 1, "\(reconnect): a rejected credential reached PDT again")
        }
    }

    @Test("A store that takes writes again saves the held sign-in on the next request, and the connection reads as saved")
    func recoveredStoreSavesTheHeldSignIn() throws {
        let ok = ScriptedPDTHTTPTransport.Reply.response(status: 200, body: Data("{}".utf8))
        let store = SwitchableStore()
        let driver = try LaunchDriver(store: store, api: [ok, ok])
        driver.launch()

        store.refuse(saves: true)
        try #require(driver.signIn())
        #expect(driver.runtime.state == .connected(.fetching, .thisSessionOnly(.failed)))
        #expect(driver.rows.last?.detail == "PDTBar could not save it on this Mac. You stay connected until you quit")
        _ = try driver.connection.apiClient().get(.me)
        #expect(try store.load() == .disconnected)

        store.refuse()
        _ = try driver.connection.apiClient().get(.me)
        #expect(try store.load() == .connected(.browserSession(signedInSession)))
        #expect(driver.connection.status(afterSyncEnding: nil) == .connected(.saved))
        #expect(driver.api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access", "Bearer access"])
    }

    @Test("A sign-in is held when the store lock cannot be taken, and saved once it can")
    func signInSurvivesAStoreLockThatFails() throws {
        let store = SwitchableStore()
        let driver = try LaunchDriver(store: store)

        store.refuse(lock: true)
        #expect(driver.connection.signIn(cancellation: PDTCancellation()).status == .connected(.thisSessionOnly(.failed)))
        #expect(driver.connection.check().status == .connected(.thisSessionOnly(.failed)))

        store.refuse()
        #expect(driver.connection.check().status == .connected(.saved))
        #expect(try store.load() == .connected(.browserSession(signedInSession)))
    }

    @Test("Disconnect drops a credential the Keychain never saved and names the PDT page for its kind")
    func disconnectDropsAnUnsavedCredential() throws {
        let signedIn = try LaunchDriver(keychain: .unentitled)
        signedIn.launch()
        try #require(signedIn.signIn())
        let pasted = try LaunchDriver(keychain: .unentitled)
        pasted.launch()
        try #require(pasted.connect(token: PDTAPIToken("pdt_pasted")))

        for (driver, page) in [(signedIn, PDTOAuthEndpoints.connectedApps), (pasted, PDTOAuthEndpoints.integrations)] {
            // Disconnect is offered once the fetch is over; a failed one keeps the not-saved row beside it.
            driver.endFirstFetch(driver.connection.failure(for: PDTAPIError.transport(code: URLError.timedOut.rawValue)))
            #expect(driver.rows.map(\.id).suffix(2) == ["pdtConnection.notSaved", "pdtConnection.disconnect"])
            try #require(driver.disconnect())

            #expect(driver.runtime.state == .notConnected)
            #expect(driver.rows.first { $0.id == "pdtConnection.revoke" }?.actionPayload == page.absoluteString)
            #expect(driver.connection.check() == PDTConnectionOutcome(.notConnected))
            #expect(throws: PDTAPIError.missingToken) { try driver.connection.apiClient().get(.me) }
            #expect(driver.api.requests.isEmpty)
        }
    }

    @Test("A delete the store refuses never reads as removed, stops the credential being used, and lands on a later check")
    func refusedDeleteIsNotClaimedAsRemoved() throws {
        let stored = PDTConnectionState.connected(.personalToken(PDTAPIToken("pdt_stored")))
        let store = SwitchableStore(stored)
        let driver = try LaunchDriver(store: store)

        store.refuse(saves: true)
        #expect(driver.connection.disconnect() == PDTConnectionOutcome(.keychainUnavailable(.failed)))
        #expect(driver.connection.check().status == .keychainUnavailable(.failed))
        #expect(try store.load() == stored)
        #expect(throws: PDTAPIError.missingToken) { try driver.connection.apiClient().get(.me) }
        #expect(driver.api.requests.isEmpty, "a credential the user disconnected reached PDT")

        store.refuse()
        #expect(driver.connection.check().status == .notConnected)
        #expect(try store.load() == .disconnected)
    }

    @Test("A relaunch on a build that cannot save starts not connected and offers sign-in again")
    func relaunchWithoutASavedSignInStartsNotConnected() throws {
        let first = try LaunchDriver(keychain: .unentitled)
        first.launch()
        try #require(first.signIn())
        #expect(first.runtime.state == .connected(.fetching, .thisSessionOnly(.missingEntitlement)))

        let relaunched = try LaunchDriver(keychain: .unentitled)
        relaunched.launch()

        #expect(relaunched.runtime.state == .notConnected)
        #expect(relaunched.rows.contains { $0.id == "pdtConnection.signIn" })
    }

    @Test("A Keychain that refuses the read is an access error, not an empty store")
    func refusedReadIsKeychainUnavailable() throws {
        let driver = try LaunchDriver(store: KeychainPDTCredentialStore(
            lockDirectory: try temporaryDirectory(),
            secItem: KeychainPDTCredentialStore.SecItemAPI(
                copyMatching: { _, _ in errSecMissingEntitlement },
                add: { _ in errSecMissingEntitlement },
                update: { _, _ in errSecMissingEntitlement },
                delete: { _ in errSecMissingEntitlement }
            )
        ))
        driver.launch()

        #expect(driver.runtime.state == .keychainUnavailable(.missingEntitlement))
        #expect(driver.rows.map(\.id) == ["pdtConnection.status", "pdtConnection.check"])
    }

    @Test("A script can model the unentitled Keychain: reads find nothing, writes are refused")
    func scriptedUnentitledKeychain() throws {
        let script = try JSONDecoder().decode(
            ScriptedPDTConnection.self,
            from: Data(#"{"connection":"notConnected","keychain":"unentitled","api":{"responses":[]}}"#.utf8)
        )
        #expect(script == ScriptedPDTConnection(connection: .notConnected, keychain: .unentitled))
        let connection = try script.appConnection(lockDirectory: temporaryDirectory())

        #expect(connection.check().status == .notConnected)
        #expect(connection.signIn(cancellation: PDTCancellation()).status == .connected(.thisSessionOnly(.missingEntitlement)))
        #expect(connection.check().status == .connected(.thisSessionOnly(.missingEntitlement)))
        #expect(connection.disconnect().status == .notConnected)
        #expect(try script.appConnection(lockDirectory: temporaryDirectory()).check().status == .notConnected)
    }
}

private let signedInSession = PDTBrowserSession(
    accessToken: PDTAPIToken("access"),
    refreshToken: PDTRefreshToken("refresh"),
    accessExpiresAt: .distantFuture
)

private func tokenReply(access: String, refresh: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 200,
        body: Data(#"{"access_token":"\#(access)","expires_in":3600,"refresh_token":"\#(refresh)","token_type":"Bearer"}"#.utf8)
    )
}

private func oauthError(_ error: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 400, body: Data(#"{"error":"\#(error)","error_description":"d"}"#.utf8))
}

private func tokenInvalid(_ reason: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 401,
        body: Data(#"{"error":{"code":"TOKEN_INVALID","message":"m","details":{"reason":"\#(reason)"},"traceId":"t"}}"#.utf8)
    )
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-sign-in-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Runs `PDTLaunchRuntime` effects synchronously against a real `PDTAppConnection`
/// over the Keychain store and a fake SecItem API, or over another store. Fetch
/// effects are left unstarted: a test sends its own requests through the
/// connection and ends the first fetch with `endFirstFetch`.
private final class LaunchDriver {
    let runtime = PDTLaunchRuntime()
    let connection: PDTAppConnection
    let api: ScriptedPDTHTTPTransport
    let tokens: ScriptedPDTHTTPTransport
    private(set) var last: PDTOnboardingUpdate?

    convenience init(
        keychain: FakeKeychain,
        api: [ScriptedPDTHTTPTransport.Reply] = [],
        tokens: [ScriptedPDTHTTPTransport.Reply] = []
    ) throws {
        try self.init(
            store: KeychainPDTCredentialStore(lockDirectory: try temporaryDirectory(), secItem: keychain.api),
            api: api,
            tokens: tokens
        )
    }

    init(
        store: any PDTCredentialStore,
        api replies: [ScriptedPDTHTTPTransport.Reply] = [],
        tokens tokenReplies: [ScriptedPDTHTTPTransport.Reply] = []
    ) throws {
        api = ScriptedPDTHTTPTransport(replies)
        tokens = ScriptedPDTHTTPTransport(tokenReplies)
        connection = PDTAppConnection(
            store: store,
            tokenEndpoint: PDTTokenEndpoint(transport: tokens),
            apiTransport: api,
            signIn: { _ in signedInSession }
        )
    }

    func launch() {
        run(runtime.launch())
    }

    @discardableResult
    func signIn() -> Bool {
        run(runtime.signIn())
    }

    @discardableResult
    func checkAgain() -> Bool {
        run(runtime.checkAgain())
    }

    @discardableResult
    func connect(token: PDTAPIToken) -> Bool {
        run(runtime.connect(token: token))
    }

    @discardableResult
    func disconnect() -> Bool {
        run(runtime.disconnect())
    }

    /// The first fetch the last sign-in, token, or check started ends this way.
    func endFirstFetch(_ failure: PDTFetchFailure) {
        run(runtime.completeFirstFetch(.failed(failure)))
    }

    var rows: [MenuRow] {
        (last?.descriptor.sections ?? []).flatMap(\.rows)
    }

    @discardableResult
    private func run(_ update: PDTOnboardingUpdate?) -> Bool {
        guard var update else {
            return false
        }
        while true {
            last = update
            let attempt = runtime.connectionAttempt
            let next: PDTOnboardingUpdate?
            switch update.effect {
            case .loadCachedPulse:
                next = runtime.completeCachedPulseLoad(nil)
            case .checkConnection:
                next = runtime.completeConnection(connection.check(), for: attempt)
            case .signIn:
                next = runtime.completeConnection(connection.signIn(cancellation: PDTCancellation()), for: attempt)
            case let .connectToken(token):
                next = runtime.completeConnection(connection.connect(token: token), for: attempt)
            case .disconnect:
                next = runtime.completeConnection(connection.disconnect(), for: attempt)
            default:
                next = nil
            }
            guard let next else {
                return true
            }
            update = next
        }
    }
}

/// The Keychain as an unentitled build sees it (measured with an ad-hoc signed
/// probe: reads -25300, writes -34018), or as an entitled one.
private enum FakeKeychain: CustomStringConvertible {
    case unentitled
    case entitled

    var description: String {
        self == .unentitled ? "unentitled Keychain" : "entitled Keychain"
    }

    var api: KeychainPDTCredentialStore.SecItemAPI {
        switch self {
        case .unentitled:
            return KeychainPDTCredentialStore.SecItemAPI(
                copyMatching: { _, _ in errSecItemNotFound },
                add: { _ in errSecMissingEntitlement },
                update: { _, _ in errSecMissingEntitlement },
                delete: { _ in errSecMissingEntitlement }
            )
        case .entitled:
            let item = KeychainItem()
            return KeychainPDTCredentialStore.SecItemAPI(
                copyMatching: { _, result in item.copy(into: result) },
                add: { query in item.set((query as NSDictionary)[kSecValueData as String] as? Data) },
                update: { _, attributes in item.update((attributes as NSDictionary)[kSecValueData as String] as? Data) },
                delete: { _ in item.set(nil) == errSecSuccess ? errSecSuccess : errSecItemNotFound }
            )
        }
    }
}

private final class KeychainItem: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func copy(into result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let data else {
            return errSecItemNotFound
        }
        result?.pointee = data as CFData
        return errSecSuccess
    }

    func set(_ value: Data?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        data = value
        return errSecSuccess
    }

    func update(_ value: Data?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard data != nil else {
            return errSecItemNotFound
        }
        data = value
        return errSecSuccess
    }
}

/// An in-memory store whose saves, or whose lock, can be switched off and
/// back on: a store that is unwritable for a while.
private final class SwitchableStore: PDTCredentialStore, @unchecked Sendable {
    private let backing: InMemoryPDTCredentialStore
    private let lock = NSLock()
    private var refusesSaves = false
    private var refusesLock = false

    init(_ state: PDTConnectionState = .disconnected) {
        backing = InMemoryPDTCredentialStore(state)
    }

    /// With no argument the store works again.
    func refuse(saves: Bool = false, lock refusesLock: Bool = false) {
        lock.lock()
        refusesSaves = saves
        self.refusesLock = refusesLock
        lock.unlock()
    }

    func load() throws -> PDTConnectionState {
        try backing.load()
    }

    func save(_ state: PDTConnectionState) throws {
        if refuses(\.refusesSaves) {
            throw PDTCredentialStoreError.writeFailed(code: EIO)
        }
        try backing.save(state)
    }

    func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        if refuses(\.refusesLock) {
            throw PDTCredentialStoreError.lockFailed(code: EACCES)
        }
        return try backing.withExclusiveAccess(body)
    }

    private func refuses(_ flag: KeyPath<SwitchableStore, Bool>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self[keyPath: flag]
    }
}
