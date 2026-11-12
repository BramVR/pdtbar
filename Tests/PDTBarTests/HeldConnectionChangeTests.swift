import Foundation
import Testing
@testable import PDTBarCore

/// A change the store refused is held and applied when the store takes a
/// save again. However it is held, it must leave the store where replaying
/// its events one by one through the event table would.
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
                for (stored, expected) in zip(storedStates, outcomes) where held.applied(to: stored) != expected {
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
            #expect(held.applied(to: stored) == replayed(events, over: stored), "\(stored)")
        }
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
