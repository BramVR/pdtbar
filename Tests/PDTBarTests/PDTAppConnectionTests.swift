import Foundation
import Security
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("PDT app connection")
struct PDTAppConnectionTests {
    @Test("Each stored connection reports its status")
    func storedConnectionStatus() throws {
        let cases: [(ScriptedPDTConnection.StoredConnection, PDTConnectionStatus)] = [
            (.notConnected, .notConnected),
            (.browserSession, .connected),
            (.personalToken, .connected),
            (.signInExpired, .needsReconnect(.browserSession, .signInExpired)),
            (.tokenRevoked, .needsReconnect(.personalToken, .tokenRevoked)),
        ]
        for (stored, status) in cases {
            let connection = try ScriptedPDTConnection(connection: stored).appConnection(lockDirectory: temporaryDirectory())
            #expect(connection.check() == PDTConnectionOutcome(status), "\(stored)")
        }
    }

    @Test("401 TOKEN_INVALID on a token moves to reconnect with PDT's reason")
    func tokenInvalidNeedsReconnect() throws {
        for (reason, cause) in [("revoked", PDTReconnectCause.tokenRevoked), ("expired", .tokenExpired), ("invalid", .tokenInvalid)] {
            let run = try firstFetch(stored: personalToken, replies: [apiError(401, "TOKEN_INVALID", details: #"{"reason":"\#(reason)"}"#)])

            #expect(run.failure == .connection(.needsReconnect(.personalToken, cause)), "\(reason)")
            #expect(run.connection.check().status == .needsReconnect(.personalToken, cause), "\(reason)")
        }
    }

    @Test("A browser sign-in PDT no longer refreshes moves to reconnect as an expired sign-in")
    func rejectedRefreshNeedsReconnect() throws {
        let run = try firstFetch(
            stored: .connected(.browserSession(browserSession)),
            replies: [apiError(401, "TOKEN_INVALID", details: #"{"reason":"expired"}"#)],
            tokenReplies: [.response(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"d"}"#.utf8))]
        )

        #expect(run.failure == .connection(.needsReconnect(.browserSession, .signInExpired)))
        #expect(run.connection.check().status == .needsReconnect(.browserSession, .signInExpired))
    }

    @Test("403 API_ACCESS_PAUSED reports a paused subscription and keeps the credential")
    func apiAccessPausedKeepsCredential() throws {
        let store = InMemoryPDTCredentialStore(personalToken)
        let run = try firstFetch(store: store, replies: [apiError(403, "API_ACCESS_PAUSED")])

        #expect(run.failure == .connection(.subscriptionPaused))
        #expect(try store.load() == personalToken)
        #expect(run.connection.check().status == .connected)
    }

    @Test("403 INSUFFICIENT_SCOPE asks to reconnect with read access")
    func insufficientScopeNeedsReadAccess() throws {
        let run = try firstFetch(stored: personalToken, replies: [apiError(403, "INSUFFICIENT_SCOPE")])

        #expect(run.failure == .connection(.needsReconnect(.personalToken, .readAccessMissing)))
    }

    @Test("Server and network failures are retryable with the connection kept")
    func serverAndTransportFailuresAreUnavailable() throws {
        let serverError = ScriptedPDTHTTPTransport.Reply.response(status: 503, body: Data("{}".utf8), headers: ["retry-after": "0"])
        for replies in [[serverError, serverError, serverError], [.failure(.notConnectedToInternet)]] {
            let run = try firstFetch(stored: personalToken, replies: replies)

            #expect(run.failure == .unavailable)
            #expect(run.connection.check().status == .connected)
        }
    }

    @Test("A Keychain that refuses every call reports it, holds a token or sign-in it could not save, and never falls back to the login keychain")
    func missingKeychainEntitlement() throws {
        let keychain = RecordingSecItems(status: errSecMissingEntitlement)
        let connection = PDTAppConnection(
            store: KeychainPDTCredentialStore(lockDirectory: try temporaryDirectory(), secItem: keychain.api),
            tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
            apiTransport: ScriptedPDTHTTPTransport([]),
            signIn: { _ in browserSession }
        )

        #expect(connection.check().status == .keychainUnavailable(.missingEntitlement))
        #expect(connection.connect(token: PDTAPIToken("pdt_pasted")).status == .notSaved(.personalToken, .missingEntitlement))
        #expect(connection.signIn(cancellation: PDTCancellation()).status == .notSaved(.browserSession, .missingEntitlement))
        #expect(connection.check().status == .notSaved(.browserSession, .missingEntitlement))
        #expect(!keychain.queries.isEmpty)
        #expect(keychain.queries.allSatisfy { $0[kSecUseDataProtectionKeychain as String] as? Bool == true })
    }

    @Test("A scripted Keychain status drives the real Keychain store, including during a fetch")
    func scriptedKeychainStatus() throws {
        let connection = try ScriptedPDTConnection(connection: .personalToken, keychainStatus: errSecMissingEntitlement)
            .appConnection(lockDirectory: temporaryDirectory())

        #expect(connection.check().status == .keychainUnavailable(.missingEntitlement))
        do {
            _ = try PDTAPIDataSource(client: connection.apiClient(), options: .firstFetch).snapshot(asOf: asOf)
            Issue.record("the fetch read a credential from a Keychain that refused every call")
        } catch {
            #expect(connection.failure(for: error) == .connection(.keychainUnavailable(.missingEntitlement)))
        }
    }

    @Test("A scripted unentitled Keychain reads as signed out and refuses to store a sign-in")
    func scriptedUnentitledKeychain() throws {
        let script = try JSONDecoder().decode(
            ScriptedPDTConnection.self,
            from: Data(#"{"connection":"notConnected","keychain":"unentitled","api":{"responses":[]}}"#.utf8)
        )
        let connection = try script.appConnection(lockDirectory: temporaryDirectory())

        #expect(script.keychain == .unentitled)
        #expect(connection.check().status == .notConnected)
        #expect(connection.signIn(cancellation: PDTCancellation()).status == .keychainUnavailable(.missingEntitlement))
        #expect(connection.connect(token: PDTAPIToken("pdt_pasted")).status == .keychainUnavailable(.missingEntitlement))
        #expect(connection.check().status == .notConnected)
    }

    @Test("Browser sign-in stores the session; a declined or blocked sign-in names why")
    func browserSignInOutcomes() throws {
        let cases: [(ScriptedPDTConnection.SignInOutcome, PDTConnectionOutcome)] = [
            (.succeeds, PDTConnectionOutcome(.connected)),
            (.denied, PDTConnectionOutcome(.notConnected, notice: .signInFailed(.denied))),
            (.portBusy, PDTConnectionOutcome(.notConnected, notice: .signInFailed(.portBusy))),
            (.timedOut, PDTConnectionOutcome(.notConnected, notice: .signInFailed(.timedOut))),
        ]
        for (scripted, outcome) in cases {
            let connection = try ScriptedPDTConnection(connection: .notConnected, signIn: scripted)
                .appConnection(lockDirectory: temporaryDirectory())

            #expect(connection.signIn(cancellation: PDTCancellation()) == outcome, "\(scripted)")
            #expect(connection.check().status == outcome.status, "\(scripted)")
        }
    }

    @Test("A cancelled sign-in ends quietly with nothing stored")
    func cancelledSignIn() throws {
        let connection = try ScriptedPDTConnection(connection: .notConnected, signIn: .waitsForCancel)
            .appConnection(lockDirectory: temporaryDirectory())
        let cancellation = PDTCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancellation.cancel() }

        let started = Date()
        let outcome = connection.signIn(cancellation: cancellation)

        #expect(outcome == PDTConnectionOutcome(.notConnected))
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("A cancel that lands after PDT approved the sign-in still stores nothing")
    func cancelAfterApprovalStoresNothing() throws {
        let store = InMemoryPDTCredentialStore()
        let cancellation = PDTCancellation()
        let connection = PDTAppConnection(
            store: store,
            tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
            apiTransport: ScriptedPDTHTTPTransport([]),
            signIn: { _ in
                cancellation.cancel()
                return browserSession
            }
        )

        #expect(connection.signIn(cancellation: cancellation) == PDTConnectionOutcome(.notConnected))
        #expect(try store.load() == .disconnected)
    }

    @Test("Fetch errors log without PDT's free-text reason")
    func logLabelDropsServerText() {
        let echoed = "pdt_echoed_secret"
        let labels = [
            PDTAppConnection.logLabel(for: PDTAPIError.tokenInvalid(reason: echoed)),
            PDTAppConnection.logLabel(for: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: echoed))),
        ]

        #expect(labels.allSatisfy { !$0.contains(echoed) })
        #expect(labels[0] == "tokenInvalid")
        #expect(PDTAppConnection.logLabel(for: PDTAPIError.server(status: 503, retryAfter: nil)).contains("503"))
    }

    @Test("A pasted token is stored and sent as the bearer token")
    func pastedTokenIsUsed() throws {
        let transport = ScriptedPDTHTTPTransport([try holdingsReply()])
        let connection = PDTAppConnection(
            store: InMemoryPDTCredentialStore(),
            tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
            apiTransport: transport,
            signIn: { _ in throw PDTSignInError.accessDenied }
        )

        #expect(connection.connect(token: PDTAPIToken("pdt_pasted")) == PDTConnectionOutcome(.connected))
        _ = try PDTAPIDataSource(client: connection.apiClient(), options: .firstFetch).snapshot(asOf: asOf)

        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer pdt_pasted")
    }

    @Test("Disconnect deletes the credential and names the page where PDT access is removed")
    func disconnectDeletesCredential() throws {
        let cases: [(PDTConnectionState, URL)] = [
            (.connected(.browserSession(browserSession)), PDTOAuthEndpoints.connectedApps),
            (personalToken, PDTOAuthEndpoints.integrations),
            (.needsReconnect(.personalToken, .tokenRejected(reason: "revoked")), PDTOAuthEndpoints.integrations),
        ]
        for (stored, page) in cases {
            let store = InMemoryPDTCredentialStore(stored)
            let connection = appConnection(store: store, replies: [])

            #expect(connection.disconnect() == PDTConnectionOutcome(.notConnected, notice: .disconnected(revokeAt: page)))
            #expect(try store.load() == .disconnected)
        }
    }
}

@Suite("PDT first fetch through the launch runtime")
struct PDTFirstFetchRuntimeTests {
    @Test("A failed holdings fetch publishes nothing and writes no snapshot")
    func failedHoldingsFetchPublishesNothing() throws {
        let serverError = ScriptedPDTHTTPTransport.Reply.response(status: 503, body: Data("{}".utf8), headers: ["retry-after": "0"])
        let cases: [([ScriptedPDTHTTPTransport.Reply], PDTLaunchState)] = [
            ([serverError, serverError, serverError], .connected(.failed)),
            ([apiError(401, "TOKEN_INVALID", details: #"{"reason":"revoked"}"#)], .needsReconnect(.personalToken, .tokenRevoked)),
            ([apiError(403, "API_ACCESS_PAUSED")], .subscriptionPaused),
        ]
        for (replies, state) in cases {
            let snapshots = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-first-fetch-failure")
            defer { try? FileManager.default.removeItem(at: snapshots.directory) }
            let connection = appConnection(store: InMemoryPDTCredentialStore(personalToken), replies: replies)
            let runtime = PDTLaunchRuntime()

            let start = connectedLaunch(runtime)
            #expect(start.effect == .startFirstFetch)
            let finished = runtime.completeFirstFetch(runFirstFetch(connection, snapshots: snapshots))

            #expect(finished.state == state)
            #expect(runtime.currentPulse == nil)
            #expect(!FileManager.default.fileExists(atPath: snapshots.currentSnapshotPath.path))
            if state == .connected(.failed) {
                #expect(finished.descriptor.statusTitle == "Could not fetch portfolio")
            }
        }
    }

    @Test("A successful first fetch persists the snapshot before the pulse is published")
    func successfulFirstFetchPersistsBeforePublish() throws {
        let snapshots = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-first-fetch-success")
        defer { try? FileManager.default.removeItem(at: snapshots.directory) }
        let connection = appConnection(store: InMemoryPDTCredentialStore(personalToken), replies: [try holdingsReply()])
        let runtime = PDTLaunchRuntime()
        _ = connectedLaunch(runtime)

        let result = runFirstFetch(connection, snapshots: snapshots)

        #expect(FileManager.default.fileExists(atPath: snapshots.currentSnapshotPath.path))
        #expect(runtime.currentPulse == nil)
        let published = runtime.completeFirstFetch(result)
        #expect(published.state == .connected(.current))
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(published.descriptor.sections.map(\.id).contains("pulse"))
    }
}

private let asOf = "2026-06-22"
private let personalToken = PDTConnectionState.connected(.personalToken(PDTAPIToken("pdt_stored")))
private let browserSession = PDTBrowserSession(
    accessToken: PDTAPIToken("access"),
    refreshToken: PDTRefreshToken("refresh"),
    accessExpiresAt: .distantFuture
)

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private struct FirstFetchRun {
    var connection: PDTAppConnection
    var failure: PDTFetchFailure?
}

private func firstFetch(
    stored: PDTConnectionState,
    replies: [ScriptedPDTHTTPTransport.Reply],
    tokenReplies: [ScriptedPDTHTTPTransport.Reply] = []
) throws -> FirstFetchRun {
    try firstFetch(store: InMemoryPDTCredentialStore(stored), replies: replies, tokenReplies: tokenReplies)
}

private func firstFetch(
    store: InMemoryPDTCredentialStore,
    replies: [ScriptedPDTHTTPTransport.Reply],
    tokenReplies: [ScriptedPDTHTTPTransport.Reply] = []
) throws -> FirstFetchRun {
    let connection = appConnection(store: store, replies: replies, tokenReplies: tokenReplies)
    do {
        _ = try PDTAPIDataSource(client: connection.apiClient(), options: .firstFetch).snapshot(asOf: asOf)
        return FirstFetchRun(connection: connection, failure: nil)
    } catch {
        return FirstFetchRun(connection: connection, failure: connection.failure(for: error))
    }
}

private func appConnection(
    store: any PDTCredentialStore,
    replies: [ScriptedPDTHTTPTransport.Reply],
    tokenReplies: [ScriptedPDTHTTPTransport.Reply] = []
) -> PDTAppConnection {
    PDTAppConnection(
        store: store,
        tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport(tokenReplies)),
        apiTransport: ScriptedPDTHTTPTransport(replies),
        signIn: { _ in throw PDTSignInError.accessDenied }
    )
}

/// What the app does for `.startFirstFetch`: the coalesced fetch persists, then returns the pulse.
private func runFirstFetch(_ connection: PDTAppConnection, snapshots: SnapshotStore) -> PDTLaunchFetchResult {
    do {
        let pulse = try PDTCoalescedFirstPortfolioFetch(
            dataSource: PDTAPIDataSource(client: connection.apiClient(), options: .firstFetch),
            snapshotStore: snapshots,
            asOf: asOf,
            pulseReadStore: PulseReadStore(directory: snapshots.directory)
        ).fetch()
        return .succeeded(pulse)
    } catch {
        return .failed(connection.failure(for: error))
    }
}

private func connectedLaunch(_ runtime: PDTLaunchRuntime) -> PDTOnboardingUpdate {
    _ = runtime.launch()
    _ = runtime.completeCachedPulseLoad(nil)
    return runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
}

private func holdingsReply() throws -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: try Data(contentsOf: packageRoot.appending(path: "docs/pdt/fixtures/api/full/01-holdings.json")))
}

private func apiError(_ status: Int, _ code: String, details: String = "{}") -> ScriptedPDTHTTPTransport.Reply {
    .response(status: status, body: Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details),"traceId":"t"}}"#.utf8))
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-app-connection-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Answers every SecItem call with one status and records each query.
private final class RecordingSecItems: @unchecked Sendable {
    private let lock = NSLock()
    private let status: OSStatus
    private var recorded: [[String: Any]] = []

    init(status: OSStatus) {
        self.status = status
    }

    var queries: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var api: KeychainPDTCredentialStore.SecItemAPI {
        KeychainPDTCredentialStore.SecItemAPI(
            copyMatching: { query, _ in self.record(query) },
            add: { query in self.record(query) },
            update: { query, _ in self.record(query) },
            delete: { query in self.record(query) }
        )
    }

    private func record(_ query: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(query as NSDictionary as! [String: Any])
        return status
    }
}
