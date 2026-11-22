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

    struct Change {
        private(set) var replay: [PDTConnectionEvent]?
        var state: PDTConnectionState
        var generation: Int?
        var written: PDTStoredConnection?

        init(_ event: PDTConnectionEvent, after known: PDTConnectionState = .disconnected) {
            replay = event.replacesAnyState ? nil : [event]
            state = known.applying(event)
        }

        func followed(by event: PDTConnectionEvent) -> Change {
            guard !event.replacesAnyState else {
                return Change(event)
            }
            var next = self
            next.replay = replay.map { $0 + [event] }
            next.state = state.applying(event)
            return next
        }

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

        func applied(to stored: PDTStoredConnection) -> PDTStoredConnection? {
            if stored == written {
                return PDTStoredConnection(state, generation: stored.generation)
            }
            guard generation ?? stored.generation == stored.generation else {
                return nil
            }
            guard let replay else {
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

    private func record(_ event: PDTConnectionEvent, after known: PDTConnectionState) -> PDTConnectionState {
        commit(refused?.change.followed(by: event) ?? Change(event, after: known))
    }

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

    private func settle() {
        if let refused {
            _ = commit(refused.change)
        }
    }

    private func current() throws -> PDTConnectionState {
        try refused?.change.state ?? store.load().state
    }

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
    init(refused state: PDTConnectionState, _ problem: PDTKeychainProblem) {
        switch state {
        case .connected:
            self = .connected(.thisSessionOnly(problem))
        case let .needsReconnect(kind, reason):
            self = .needsReconnect(kind, PDTReconnectCause(reason))
        case .disconnected:
            self = .keychainUnavailable(problem)
        }
    }
}

private extension PDTConnectionState {
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
