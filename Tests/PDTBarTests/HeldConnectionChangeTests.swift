import Foundation
import Testing
@testable import PDTBarCore

/// A change the store refused is held and applied when the store takes a
/// save again. However it is held, it must leave the store where replaying
/// its events one by one through the event table would. It gives way once
/// another process has stored a sign-in, pasted token, or disconnect since.
@Suite("Held connection change")
struct HeldConnectionChangeTests {
    @Test("A held change leaves every stored state where replaying its events one by one would")
    func heldChangeMatchesEventReplay() {
        for events in histories(upTo: 3) {
            let outcomes = storedStates.map { replayed(events, over: $0) }
            for (known, expected) in zip(storedStates, outcomes) {
                let held = events.dropFirst().reduce(PDTConnection.Change(events[0], after: known)) { $0.followed(by: $1) }
                if held.state != expected {
                    Issue.record("\(events) after \(known) leaves this connection at \(held.state)")
                }
                for (stored, expected) in zip(storedStates, outcomes) where held.applied(to: PDTStoredConnection(stored))?.state != expected {
                    Issue.record("\(events) held after \(known), applied to \(stored)")
                }
            }
        }
    }

    @Test("A thousand refreshes behind a sign-in the store refused are held as the newest pair alone")
    func refusedSignInStaysOneStateAcrossRefreshes() {
        var events = [PDTConnectionEvent.signedIn(pair(0))]
        var held = PDTConnection.Change(events[0])
        for hour in 1...1000 {
            let refreshed = PDTConnectionEvent.refreshed(pair(hour), from: pair(hour - 1).refreshToken)
            events.append(refreshed)
            held = held.followed(by: refreshed)
        }

        #expect((held.replay ?? []).isEmpty, "the held change grew with the refreshes")
        #expect(held.state == .connected(.browserSession(pair(1000))))
        for stored in storedStates {
            #expect(held.applied(to: PDTStoredConnection(stored))?.state == replayed(events, over: stored), "\(stored)")
        }
    }

    @Test("A token PDT rejected in another process is not handed out or stored again by the process that held it unsaved")
    func heldTokenYieldsToARejectionAnotherProcessRecorded() throws {
        let item = InMemoryPDTCredentialStore()
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved)
        let elsewhere = connection(ProcessStore(item))

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.connect(personalToken: pasted) }
        try elsewhere.connect(personalToken: pasted)
        #expect(try !elsewhere.shouldRetry(afterRejecting: pasted, reason: "revoked"))

        unsaved.takeSaves()
        #expect(throws: PDTAPIError.tokenInvalid(reason: "revoked")) { try here.currentToken() }
        #expect(here.status() == .needsReconnect(.personalToken, .tokenRevoked))
        #expect(try item.load().state == .needsReconnect(.personalToken, .tokenRejected(reason: "revoked")))
    }

    @Test("A sign-in another process stored later is kept, and the process that held an older one unsaved adopts it")
    func heldSignInYieldsToALaterSignInFromAnotherProcess() throws {
        let item = InMemoryPDTCredentialStore()
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved)
        let elsewhere = connection(ProcessStore(item))

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.signedIn(pair(0)) }
        try elsewhere.signedIn(pair(1))

        unsaved.takeSaves()
        #expect(try here.currentToken() == pair(1).accessToken)
        #expect(here.status() == .connected(.saved))
        #expect(try item.load().state == .connected(.browserSession(pair(1))))
    }

    @Test(
        "A token another process disconnected is not handed out or stored again by the process that held it unsaved",
        arguments: [false, true]
    )
    func heldTokenYieldsToADisconnectFromAnotherProcess(onDisk: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-held-change-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let item: any PDTCredentialStore = onDisk ? FilePDTCredentialStore(url: directory.appending(path: "pdt.json")) : InMemoryPDTCredentialStore()
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved)
        let elsewhere = connection(ProcessStore(item))

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.connect(personalToken: pasted) }
        try elsewhere.connect(personalToken: pasted)
        try elsewhere.disconnect()

        unsaved.takeSaves()
        #expect(throws: PDTAPIError.missingToken) { try here.currentToken() }
        #expect(here.status() == .notConnected(signInWouldBe: .saved))
        #expect(try item.load().state == .disconnected)
    }

    @Test("A token another process entered again stays stored, although a disconnect held here was decided while that same token was stored")
    func heldDisconnectYieldsToTheSameTokenEnteredAgainElsewhere() throws {
        let item = InMemoryPDTCredentialStore(.connected(.personalToken(pasted)))
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved)
        let elsewhere = connection(ProcessStore(item))

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.disconnect() }
        try elsewhere.connect(personalToken: pasted)

        unsaved.takeSaves()
        #expect(try here.currentToken() == pasted)
        #expect(here.status() == .connected(.saved))
        #expect(try item.load().state == .connected(.personalToken(pasted)))
    }

    @Test("A sign-in whose save landed without an answer is not taken for another process's: the pair it has since rotated to is stored")
    func ownSaveThatLandedUnansweredIsMovedOn() throws {
        let item = InMemoryPDTCredentialStore()
        let unanswered = ProcessStore(item, saves: .landUnanswered)
        let here = connection(unanswered, tokens: [tokenReply(rotated)])

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.signedIn(expired) }
        #expect(try item.load().state == .connected(.browserSession(expired)))
        #expect(try here.currentToken() == rotated.accessToken)

        unanswered.takeSaves()
        #expect(try here.currentToken() == rotated.accessToken)
        #expect(here.status() == .connected(.saved))
        #expect(try item.load().state == .connected(.browserSession(rotated)))
    }

    @Test("A held sign-in replaces a pair another process stored before it, also when that process has refreshed the pair since")
    func heldSignInReplacesAPairAnotherProcessRefreshed() throws {
        let item = InMemoryPDTCredentialStore(.connected(.browserSession(expired)))
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved)
        let elsewhere = connection(ProcessStore(item), tokens: [tokenReply(rotated)])

        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.signedIn(pair(1)) }
        #expect(try elsewhere.currentToken() == rotated.accessToken)
        #expect(try item.load().state == .connected(.browserSession(rotated)))

        unsaved.takeSaves()
        #expect(try here.currentToken() == pair(1).accessToken)
        #expect(try item.load().state == .connected(.browserSession(pair(1))))
        #expect(try elsewhere.currentToken() == pair(1).accessToken)
    }

    @Test(
        "Another process failing to refresh the stored pair does not end a change held here: a pair rotated here revives the store, and a sign-in made here replaces it",
        arguments: [false, true]
    )
    func heldChangeOutlivesARejectionAnotherProcessRecorded(signedInHere: Bool) throws {
        let item = InMemoryPDTCredentialStore(.connected(.browserSession(expired)))
        let unsaved = ProcessStore(item, saves: .refused)
        let here = connection(unsaved, tokens: signedInHere ? [] : [tokenReply(rotated)])
        let elsewhere = connection(ProcessStore(item), tokens: [invalidGrant])
        let live = signedInHere ? pair(1) : rotated

        if signedInHere {
            #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try here.signedIn(live) }
        } else {
            #expect(try here.currentToken() == live.accessToken)
        }
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try elsewhere.currentToken() }
        #expect(try item.load().state == .needsReconnect(.browserSession, .refreshRejected(expired.refreshToken.fingerprint)))

        unsaved.takeSaves()
        #expect(try here.currentToken() == live.accessToken)
        #expect(try item.load().state == .connected(.browserSession(live)))
        #expect(try elsewhere.currentToken() == live.accessToken)
    }
}

/// An hour before `pair(0)` runs out, so no `pair` is due for a refresh.
private let clock = Date(timeIntervalSince1970: 1_800_000_000 - 3600)

/// The stored pair both processes start from. Its access token has run out, so the next token request refreshes it.
private let expired = PDTBrowserSession(
    accessToken: PDTAPIToken("access-expired"),
    refreshToken: PDTRefreshToken("refresh-expired"),
    accessExpiresAt: clock - 1
)

/// What PDT's token endpoint answers `tokenReply(rotated)` with at `clock`.
private let rotated = PDTBrowserSession(
    accessToken: PDTAPIToken("access-rotated"),
    refreshToken: PDTRefreshToken("refresh-rotated"),
    accessExpiresAt: clock + 3600
)

private func tokenReply(_ session: PDTBrowserSession) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 200,
        body: Data(#"{"access_token":"\#(session.accessToken.secret)","expires_in":3600,"refresh_token":"\#(session.refreshToken.secret)","token_type":"Bearer"}"#.utf8)
    )
}

private var invalidGrant: ScriptedPDTHTTPTransport.Reply {
    .response(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"d"}"#.utf8))
}

private func connection(_ store: ProcessStore, tokens: [ScriptedPDTHTTPTransport.Reply] = []) -> PDTConnection {
    PDTConnection(
        store: store,
        tokenEndpoint: PDTTokenEndpoint(
            client: PDTOAuthClient(id: "test-client", redirectPort: 0),
            transport: ScriptedPDTHTTPTransport(tokens),
            now: { clock }
        ),
        now: { clock }
    )
}

/// One stored item as one of two PDTBar processes sees it: both read the same
/// item under the same lock, and this one's saves can fail.
private final class ProcessStore: PDTCredentialStore, @unchecked Sendable {
    enum Saves {
        case taken
        case refused
        /// The save lands and reports an error, and the item cannot be read until `takeSaves()`.
        case landUnanswered
    }

    private let item: any PDTCredentialStore
    private let lock = NSLock()
    private var saves: Saves
    private var unreadable = false

    init(_ item: any PDTCredentialStore, saves: Saves = .taken) {
        self.item = item
        self.saves = saves
    }

    func takeSaves() {
        lock.lock()
        saves = .taken
        unreadable = false
        lock.unlock()
    }

    var persistence: PDTCredentialPersistence { item.persistence }

    func load() throws -> PDTStoredConnection {
        lock.lock()
        let unreadable = unreadable
        lock.unlock()
        if unreadable {
            throw PDTCredentialStoreError.unreadable
        }
        return try item.load()
    }

    func save(_ connection: PDTStoredConnection) throws {
        lock.lock()
        let saves = saves
        unreadable = saves == .landUnanswered
        lock.unlock()
        if saves != .refused {
            try item.save(connection)
        }
        if saves != .taken {
            throw PDTCredentialStoreError.writeFailed(code: EIO)
        }
    }

    func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try item.withExclusiveAccess(body)
    }
}

private func replayed(_ events: [PDTConnectionEvent], over stored: PDTConnectionState) -> PDTConnectionState {
    events.reduce(stored) { $0.applying($1) }
}

private func pair(_ index: Int) -> PDTBrowserSession {
    PDTBrowserSession(
        accessToken: PDTAPIToken("access-\(index)"),
        refreshToken: PDTRefreshToken("refresh-\(index)"),
        accessExpiresAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 3600)
    )
}

private let pasted = PDTAPIToken("pdt_pasted")

/// Every event over three pairs and one pasted token: each replacement, the
/// refreshes that chain the pairs and one that skips a pair, and a rejection
/// of every token.
private let alphabet: [PDTConnectionEvent] = [
    .signedIn(pair(0)),
    .personalTokenEntered(pasted),
    .disconnected,
    .refreshed(pair(1), from: pair(0).refreshToken),
    .refreshed(pair(2), from: pair(1).refreshToken),
    .refreshed(pair(2), from: pair(0).refreshToken),
    .refreshRejected(pair(0).refreshToken),
    .refreshRejected(pair(1).refreshToken),
    .refreshRejected(pair(2).refreshToken),
    .tokenRejected(pair(1).accessToken, reason: "revoked"),
    .tokenRejected(pair(2).accessToken, reason: "revoked"),
    .tokenRejected(pasted, reason: "revoked"),
]

private func histories(upTo length: Int) -> [[PDTConnectionEvent]] {
    var all: [[PDTConnectionEvent]] = []
    var longest = alphabet.map { [$0] }
    for _ in 1..<length {
        all += longest
        longest = longest.flatMap { history in alphabet.map { history + [$0] } }
    }
    return all + longest
}

/// Every stored state the event table tells apart for those events, and one
/// it does not know for each kind: the table compares a stored session's
/// refresh token and access token separately, a rejected refresh token by
/// fingerprint, and a stored token by value.
private let storedStates: [PDTConnectionState] = {
    let foreign = PDTBrowserSession(
        accessToken: PDTAPIToken("access-elsewhere"),
        refreshToken: PDTRefreshToken("refresh-elsewhere"),
        accessExpiresAt: .distantFuture
    )
    let pairs = [pair(0), pair(1), pair(2), foreign]
    var states: [PDTConnectionState] = [
        .disconnected,
        .connected(.personalToken(pasted)),
        .connected(.personalToken(PDTAPIToken("pdt_elsewhere"))),
        .needsReconnect(.browserSession, .tokenRejected(reason: "revoked")),
        .needsReconnect(.personalToken, .tokenRejected(reason: "revoked")),
    ]
    for refresh in pairs {
        states.append(.needsReconnect(.browserSession, .refreshRejected(refresh.refreshToken.fingerprint)))
        for access in pairs {
            states.append(.connected(.browserSession(PDTBrowserSession(
                accessToken: access.accessToken,
                refreshToken: refresh.refreshToken,
                accessExpiresAt: refresh.accessExpiresAt
            ))))
        }
    }
    return states
}()
