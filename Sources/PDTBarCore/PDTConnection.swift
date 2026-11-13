import Foundation

/// The PDT connection over one credential store, and the token provider the
/// API client reads. Every operation holds the store's exclusive access from
/// load through the token endpoint to save, so a refresh is single-flight
/// across connections and processes: callers that arrive while it runs wait,
/// then read the rotated pair from the store.
///
/// A change the store refuses (a sign-in, a pasted token, a rotated pair, a
/// rejection from PDT, a disconnect) stays in `refused`, and every later
/// operation first tries to store it again. Until the store takes it, `status`,
/// `state`, and every token hand-out answer from it, so a store that reads
/// empty cannot sign the user out, and a credential the store refused works
/// until this process ends (ADR-0003 decision 3). Once another process
/// replaces what the store holds, the refused change is dropped and the store
/// answers again. A refresh that got no answer sets `hold`, and callers inside
/// it share that failure instead of each sending a refresh.
public final class PDTConnection: PDTAPITokenProvider, @unchecked Sendable {
    public static let refreshLeeway: TimeInterval = 300
    private static let refreshRetryBase: TimeInterval = 5
    private static let refreshRetryCap: TimeInterval = 60

    private let store: any PDTCredentialStore
    private let tokenEndpoint: PDTTokenEndpoint
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private(set) var refused: (change: Change, error: Error)?
    private var hold: RefreshHold?

    /// What happened to the connection since the store last agreed with it.
    /// `state` is where that leaves this connection, and `applied(to:)` is
    /// what the store should hold once it takes a save again.
    ///
    /// The change counts only for the store generation it was decided
    /// against. A sign-in, pasted token, or disconnect another process stores
    /// later starts a new generation, and the change then gives way to it:
    /// replaying it would bring back a credential that process replaced,
    /// disconnected, or saw PDT reject. That process can only have the
    /// credential held here by entering it itself, which starts a generation,
    /// so a refresh or rejection it records inside this generation is about
    /// the credential stored before the change. Those keep the generation: a
    /// sign-in held here still replaces a pair that process has only
    /// refreshed, and a pair rotated here still revives one whose refresh
    /// that process saw rejected.
    ///
    /// A sign-in, pasted token, or disconnect replaces any stored state, so
    /// every refresh or rejection after it only moves `state`. Such a change
    /// stays the same size however long the store refuses it.
    ///
    /// Refreshes and rejections of a credential the store holds are kept in
    /// `replay`, oldest first, and go through the event table, which lets a
    /// newer credential from another process win. While the store cannot be
    /// read back, a save may have landed in the middle of the chain, so every
    /// event is kept. Once a read shows what the store holds, `rebased(on:)`
    /// folds the chain from there into one refresh.
    struct Change {
        /// Nil once the change replaces whatever the store holds.
        private(set) var replay: [PDTConnectionEvent]?
        var state: PDTConnectionState
        /// The store generation the change was decided against. Nil until
        /// the store is read: a change made while the store could not be
        /// locked or read is taken as decided against what the first read
        /// finds. Nothing then shows whether another process decided in
        /// between, and giving way would drop a sign-in whenever anything
        /// at all was stored before it.
        var generation: Int?
        /// What the last save of this change wrote. A save can land and
        /// still report an error, so the store may hold it.
        var written: PDTStoredConnection?

        /// `known` is the state the caller just read. A sign-in, pasted token,
        /// or disconnect replaces any state, so those leave it out.
        init(_ event: PDTConnectionEvent, after known: PDTConnectionState = .disconnected) {
            replay = event.replacesAnyState ? nil : [event]
            state = known.applying(event)
        }

        /// This change with `event` after it. A refresh or rejection of a
        /// credential the store never took means nothing over the store alone,
        /// so it is applied behind the change that produced that credential.
        func followed(by event: PDTConnectionEvent) -> Change {
            guard !event.replacesAnyState else {
                return Change(event)
            }
            var next = self
            next.replay = replay.map { $0 + [event] }
            next.state = state.applying(event)
            return next
        }

        /// This change once a read shows the store holds `stored`. No other
        /// process holds a pair this change rotated to, so a pair `stored`
        /// does not name can only reach the store by a later save of this
        /// change. Two refreshes in a row through such a pair fold into one,
        /// unless an earlier event also produced that pair, which keeps a
        /// chain of refreshes at one event however long the store refuses it.
        func rebased(on stored: PDTStoredConnection) -> Change {
            guard let replay else {
                return self
            }
            var kept: [PDTConnectionEvent] = []
            for event in replay {
                if case let .refreshed(session, from) = event,
                   case let .refreshed(previous, origin)? = kept.last,
                   previous.refreshToken == from,
                   !stored.state.names(from),
                   !kept.dropLast().contains(where: { $0.produces(from) }) {
                    kept[kept.count - 1] = .refreshed(session, from: origin)
                } else {
                    kept.append(event)
                }
            }
            var rebased = self
            rebased.replay = kept
            return rebased
        }

        /// What the store should hold once it takes this change. Nil when
        /// the store has moved to another generation since the change was
        /// decided, which leaves the store as it is.
        func applied(to stored: PDTStoredConnection) -> PDTStoredConnection? {
            if stored == written {
                // The save landed, so the stored generation is this change's own
                // and only what has happened since is left to store.
                return PDTStoredConnection(state, generation: stored.generation)
            }
            guard generation ?? stored.generation == stored.generation else {
                return nil
            }
            guard let replay else {
                // A disconnect that finds no connection stored removes nothing,
                // so it writes nothing and an empty store stays empty.
                let removesNothing = state == .disconnected && stored.state == .disconnected
                return removesNothing ? stored : PDTStoredConnection(state, generation: stored.generation + 1)
            }
            return PDTStoredConnection(replay.reduce(stored.state) { $0.applying($1) }, generation: stored.generation)
        }
    }

    private struct RefreshHold {
        var until: Date
        var failure: PDTAPIError
        var failures: Int
    }

    public init(store: any PDTCredentialStore, tokenEndpoint: PDTTokenEndpoint, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.tokenEndpoint = tokenEndpoint
        self.now = now
    }

    /// The connection as this process knows it: the change the store refused,
    /// else what the store holds.
    public func state() throws -> PDTConnectionState {
        try locked { try current() }
    }

    /// What the menu may say. A change the store refused answers before the
    /// store does, also when the store cannot be locked or read, so a
    /// credential held here is never reported as not connected.
    public func status() -> PDTConnectionStatus {
        lock.lock()
        defer { lock.unlock() }
        let stored = Result {
            try store.withExclusiveAccess {
                settle()
                return try current()
            }
        }
        if let refused {
            return PDTConnectionStatus(refused: refused.change.state, PDTKeychainProblem(storeError: refused.error))
        }
        do {
            return PDTConnectionStatus(stored: try stored.get(), signInWouldBe: store.persistence)
        } catch {
            return PDTConnectionStatus(storeError: error)
        }
    }

    /// Stores the session unless `cancellation` fired first. The check runs
    /// inside the store lock, so a cancel that wins the race stores nothing.
    /// Throws the store's error when it refused the session, which this
    /// connection then holds and uses until the store takes it or the process
    /// ends.
    @discardableResult
    public func signedIn(_ session: PDTBrowserSession, unless cancellation: PDTCancellation? = nil) throws -> Bool {
        try replace(with: .signedIn(session), unless: cancellation)
    }

    public func connect(personalToken: PDTAPIToken) throws {
        _ = try replace(with: .personalTokenEntered(personalToken))
    }

    /// Deletes the stored credential, and drops one this connection holds at
    /// once. PDT has no API revoke for app tokens, so this returns the page
    /// where the user revokes PDTBar's access. Throws while the credential is
    /// still stored.
    @discardableResult
    public func disconnect() throws -> URL {
        _ = try replace(with: .disconnected)
        return PDTOAuthEndpoints.connectedApps
    }

    /// Refreshes the browser session now, whatever its expiry.
    public func refresh() throws -> PDTBrowserSession {
        try locked {
            guard case let .browserSession(session) = try credential() else {
                throw PDTAPIError.invalidRequest
            }
            return try refreshLocked(session)
        }
    }

    public func currentToken() throws -> PDTAPIToken {
        try locked {
            let credential = try credential()
            guard case let .browserSession(session) = credential,
                  now() >= session.accessExpiresAt.addingTimeInterval(-Self.refreshLeeway)
            else {
                return credential.accessToken
            }
            do {
                return try refreshLocked(session).accessToken
            } catch let error as PDTAPIError where error.isRetryable && now() < session.accessExpiresAt {
                return session.accessToken
            }
        }
    }

    public func shouldRetry(afterRejecting token: PDTAPIToken, reason: String?) throws -> Bool {
        try locked {
            let credential = try credential()
            if credential.accessToken != token {
                return true
            }
            // PDT's guide: any TOKEN_INVALID triggers a refresh; only a failed refresh needs a new sign-in.
            if case let .browserSession(session) = credential {
                _ = try refreshLocked(session)
                return true
            }
            // A rejection the store refuses is held, so the rejected token is not read back and sent again.
            _ = record(.tokenRejected(token, reason: reason), after: .connected(credential))
            return false
        }
    }

    private func refreshLocked(_ session: PDTBrowserSession) throws -> PDTBrowserSession {
        if let hold, now() < hold.until {
            throw hold.failure
        }
        let known = PDTConnectionState.connected(.browserSession(session))
        let rotated: PDTBrowserSession
        do {
            rotated = try tokenEndpoint.refresh(session.refreshToken)
        } catch PDTTokenEndpointError.invalidGrant {
            // The table ignores a rejection of a pair another process has already rotated past.
            let state = record(.refreshRejected(session.refreshToken), after: known)
            if case let .connected(.browserSession(rotated)) = state {
                return rotated
            }
            throw connectionError(state)
        } catch let PDTTokenEndpointError.unavailable(failure) {
            let failures = (hold?.failures ?? 0) + 1
            let delay = failure.retryAfter ?? min(Self.refreshRetryBase * pow(2, Double(failures - 1)), Self.refreshRetryCap)
            hold = RefreshHold(until: now().addingTimeInterval(delay), failure: failure, failures: failures)
            throw failure
        } catch let PDTTokenEndpointError.rejected(status, _) {
            throw PDTAPIError.unexpectedStatus(status)
        } catch {
            throw PDTAPIError.invalidResponse
        }
        hold = nil
        // PDT has already killed the old pair, so the rotated pair is used
        // whether or not the store takes it: it is the only live one.
        let state = record(.refreshed(rotated, from: session.refreshToken), after: known)
        guard case let .connected(.browserSession(fresh)) = state else {
            throw connectionError(state)
        }
        return fresh
    }

    /// A sign-in, pasted token, or disconnect. It takes the place of whatever
    /// this connection holds, and a store lock that cannot be taken refuses it
    /// like a failed save.
    private func replace(with event: PDTConnectionEvent, unless cancellation: PDTCancellation? = nil) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var storeLocked = false
        do {
            return try store.withExclusiveAccess {
                storeLocked = true
                if cancellation?.isCancelled == true {
                    return false
                }
                hold = nil
                _ = commit(Change(event))
                if let refused {
                    throw refused.error
                }
                return true
            }
        } catch where !storeLocked && cancellation?.isCancelled != true {
            hold = nil
            refused = (Change(event), error)
            throw error
        }
    }

    /// What `event` did to the state `current()` just returned: stored, or
    /// held behind whatever the store already refused. Returns where that
    /// leaves this connection.
    private func record(_ event: PDTConnectionEvent, after known: PDTConnectionState) -> PDTConnectionState {
        commit(refused?.change.followed(by: event) ?? Change(event, after: known))
    }

    /// Replays `change` over what the store holds now and saves the result.
    /// Nothing is left to save when the store already holds it, or when the
    /// event table says a newer credential has overtaken it. Returns where
    /// that leaves this connection. A change the store refuses is kept in
    /// `refused` with the store's error. A change another process has decided
    /// past is dropped, and the stored state is returned.
    private func commit(_ change: Change) -> PDTConnectionState {
        var change = change
        var attempted: PDTStoredConnection?
        do {
            let stored = try store.load()
            guard let next = change.applied(to: stored) else {
                refused = nil
                return stored.state
            }
            change.state = next.state
            change.generation = stored.generation
            if next != stored {
                change.written = next
                attempted = next
                try store.save(next)
            }
        } catch {
            // A save can land and still report an error. Only this attempt's
            // whole record proves it: a token entered again writes the same
            // state with a new generation, and an earlier attempt's write is
            // older than the change now held. A read that shows it did not
            // land shows what the store holds instead.
            guard let attempted, let reread = try? store.load() else {
                refused = (change, error)
                return change.state
            }
            guard reread == attempted else {
                refused = (change.rebased(on: reread), error)
                return change.state
            }
        }
        refused = nil
        return change.state
    }

    /// Runs first in every operation: one more try at storing the refused change.
    private func settle() {
        if let refused {
            _ = commit(refused.change)
        }
    }

    private func current() throws -> PDTConnectionState {
        try refused?.change.state ?? store.load().state
    }

    /// The credential the API may use: the one the store refused while this
    /// connection holds it, else the stored one. A held rejection or
    /// disconnect answers like a stored one, so a credential PDT rejected or
    /// the user disconnected is never sent again.
    private func credential() throws -> PDTCredential {
        let state = try current()
        guard case let .connected(credential) = state else {
            throw connectionError(state)
        }
        return credential
    }

    private func connectionError(_ state: PDTConnectionState) -> PDTAPIError {
        switch state {
        case .disconnected, .connected:
            .missingToken
        case .needsReconnect(_, .refreshRejected):
            .tokenInvalid(reason: nil)
        case let .needsReconnect(_, .tokenRejected(reason)):
            .tokenInvalid(reason: reason)
        }
    }

    private func locked<Value>(_ body: () throws -> Value) throws -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try store.withExclusiveAccess {
            settle()
            return try body()
        }
    }
}

private extension PDTConnectionStatus {
    /// What a change the store refused means for the menu.
    init(refused state: PDTConnectionState, _ problem: PDTKeychainProblem) {
        switch state {
        case .connected:
            self = .connected(.thisSessionOnly(problem))
        case let .needsReconnect(kind, reason):
            self = .needsReconnect(kind, PDTReconnectCause(reason))
        case .disconnected:
            // The delete was refused and the credential is still stored.
            self = .keychainUnavailable(problem)
        }
    }
}

private extension PDTConnectionState {
    /// Whether the event table can move this state with a refresh or
    /// rejection of `refreshToken`.
    func names(_ refreshToken: PDTRefreshToken) -> Bool {
        switch self {
        case let .connected(.browserSession(session)):
            session.refreshToken == refreshToken
        case let .needsReconnect(.browserSession, .refreshRejected(rejected)):
            rejected == refreshToken.fingerprint
        default:
            false
        }
    }
}

private extension PDTConnectionEvent {
    func produces(_ refreshToken: PDTRefreshToken) -> Bool {
        guard case let .refreshed(session, _) = self else {
            return false
        }
        return session.refreshToken == refreshToken
    }
}
