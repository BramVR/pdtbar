import Foundation
import Security
import Testing
import PDTBarAppSupport
import PDTBarCore

/// #301: on a build without the keychain access entitlement the data protection
/// keychain reads as empty (-25300) and refuses every write (-34018). A sign-in
/// there must not look connected and then vanish on the next Check again.
@Suite("Sign-in persistence")
struct SignInPersistenceTests {
    @Test("Check again after sign-in never signs out, whether or not the Keychain can store the session")
    func checkAgainAfterSignInKeepsTheConnection() throws {
        for keychain in [FakeKeychain.unentitled, .entitled] {
            let driver = try LaunchDriver(keychain: keychain)
            driver.launch()
            #expect(driver.runtime.state != .checkingConnection, "\(keychain)")

            try #require(driver.signIn(), "\(keychain): sign-in is offered at launch")
            #expect(driver.runtime.state != .notConnected, "\(keychain): the sign-in finished")

            if driver.checkAgain() {
                #expect(driver.runtime.state != .notConnected, "\(keychain): Check again signed the user out")
            }
            #expect(driver.connection.check().status != .notConnected, "\(keychain): a later check lost the session")
        }
    }

    @Test("A sign-in the Keychain cannot store says so on the menu that follows it")
    func unstorableSignInIsNamed() throws {
        let driver = try LaunchDriver(keychain: .unentitled)
        driver.launch()
        try #require(driver.signIn())

        let titles = driver.visibleRowText
        #expect(titles.contains { $0.localizedCaseInsensitiveContains("keychain") }, "rows: \(titles)")
    }

    @Test("A sign-in or token the Keychain refuses is named, offers Check again and Disconnect, and sends nothing to PDT")
    func unsavedCredentialIsNamedAndNotUsed() throws {
        let signedIn = try LaunchDriver(keychain: .unentitled)
        signedIn.launch()
        try #require(signedIn.signIn())
        let pasted = try LaunchDriver(keychain: .unentitled)
        pasted.launch()
        try #require(pasted.connect(token: PDTAPIToken("pdt_pasted")))

        let cases: [(LaunchDriver, PDTCredentialKind, String)] = [
            (signedIn, .browserSession, "Sign-in not saved"), (pasted, .personalToken, "PDT token not saved"),
        ]
        for (driver, kind, title) in cases {
            #expect(driver.runtime.state == .notSaved(kind, .missingEntitlement))
            #expect(driver.last?.effect == PDTOnboardingEffect.none, "\(kind): a fetch started behind an unsaved credential")
            #expect(driver.last?.descriptor.statusTitle == title)
            #expect(driver.rows.map(\.id) == ["pdtConnection.status", "pdtConnection.check", "pdtConnection.disconnect"])
            #expect(driver.rows.first?.detail == "This PDTBar build can't save to the Keychain. Quitting PDTBar drops it")
            #expect(driver.runtime.retryFirstFetch() == nil)
            #expect(driver.runtime.beginBackgroundDetailRefresh() == nil)

            #expect(throws: PDTCredentialStoreError.notSaved) { try driver.connection.apiClient().get(.me) }
            #expect(driver.api.requests.isEmpty, "\(kind): an unsaved credential reached PDT")
            #expect(driver.connection.failure(for: PDTCredentialStoreError.notSaved) == .connection(.notSaved(kind, .missingEntitlement)))
        }
    }

    @Test("A store that takes writes again saves the held sign-in on the next check, and the fetch starts")
    func recoveredStoreSavesTheHeldSignIn() throws {
        let store = SwitchableStore()
        let driver = try LaunchDriver(store: store, api: [.response(status: 200, body: Data("{}".utf8))])
        driver.launch()

        store.refuse(saves: true)
        try #require(driver.signIn())
        #expect(driver.runtime.state == .notSaved(.browserSession, .failed))
        #expect(driver.rows.first?.detail == "PDTBar could not save it on this Mac. Check again tries again")
        try #require(driver.checkAgain())
        #expect(driver.runtime.state == .notSaved(.browserSession, .failed))
        #expect(try store.load() == .disconnected)

        store.refuse()
        try #require(driver.checkAgain())
        #expect(driver.runtime.state == .connected(.fetching))
        #expect(driver.last?.effect == .startFirstFetch)
        #expect(try store.load() == .connected(.browserSession(signedInSession)))
        _ = try driver.connection.apiClient().get(.me)
        #expect(driver.api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access"])
    }

    @Test("A sign-in is held when the store lock cannot be taken, and saved once it can")
    func signInSurvivesAStoreLockThatFails() throws {
        let store = SwitchableStore()
        let driver = try LaunchDriver(store: store)

        store.refuse(lock: true)
        #expect(driver.connection.signIn(cancellation: PDTCancellation()).status == .notSaved(.browserSession, .failed))
        #expect(driver.connection.check().status == .notSaved(.browserSession, .failed))

        store.refuse()
        #expect(driver.connection.check().status == .connected)
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
        #expect(first.runtime.state == .notSaved(.browserSession, .missingEntitlement))

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
        #expect(connection.signIn(cancellation: PDTCancellation()).status == .notSaved(.browserSession, .missingEntitlement))
        #expect(connection.check().status == .notSaved(.browserSession, .missingEntitlement))
        #expect(connection.disconnect().status == .notConnected)
        #expect(try script.appConnection(lockDirectory: temporaryDirectory()).check().status == .notConnected)
    }
}

private let signedInSession = PDTBrowserSession(
    accessToken: PDTAPIToken("access"),
    refreshToken: PDTRefreshToken("refresh"),
    accessExpiresAt: .distantFuture
)

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-sign-in-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Runs `PDTLaunchRuntime` effects synchronously against a real `PDTAppConnection`
/// over the Keychain store and a fake SecItem API, or over another store. Fetch
/// effects are left unstarted: these tests stop at the connection.
private final class LaunchDriver {
    let runtime = PDTLaunchRuntime()
    let connection: PDTAppConnection
    let api: ScriptedPDTHTTPTransport
    private(set) var last: PDTOnboardingUpdate?

    convenience init(keychain: FakeKeychain) throws {
        try self.init(store: KeychainPDTCredentialStore(lockDirectory: try temporaryDirectory(), secItem: keychain.api))
    }

    init(store: any PDTCredentialStore, api replies: [ScriptedPDTHTTPTransport.Reply] = []) throws {
        api = ScriptedPDTHTTPTransport(replies)
        connection = PDTAppConnection(
            store: store,
            tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
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

    var rows: [MenuRow] {
        (last?.descriptor.sections ?? []).flatMap(\.rows)
    }

    var visibleRowText: [String] {
        rows.flatMap { [$0.title, $0.detail ?? ""] }
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
