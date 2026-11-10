import Foundation

/// The PDT connection over one credential store, and the token provider the
/// API client reads. Every operation holds the store's exclusive access from
/// load through the token endpoint to save, so a refresh is single-flight
/// across connections and processes: callers that arrive while it runs wait,
/// then read the rotated pair from the store. A rotated pair the store
/// refused stays in `unpersisted` until it is stored or a sign-in, token, or
/// disconnect replaces it in the store, because PDT has already killed the old
/// one. A refresh that got no answer sets `hold`, and callers inside it share
/// that failure instead of each sending a refresh.
public final class PDTConnection: PDTAPITokenProvider, @unchecked Sendable {
    public static let refreshLeeway: TimeInterval = 300
    private static let refreshRetryBase: TimeInterval = 5
    private static let refreshRetryCap: TimeInterval = 60

    private let store: any PDTCredentialStore
    private let tokenEndpoint: PDTTokenEndpoint
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var unpersisted: (session: PDTBrowserSession, from: PDTRefreshToken)?
    private var hold: RefreshHold?

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

    public func state() throws -> PDTConnectionState {
        try locked { try store.load() }
    }

    /// Stores the session unless `cancellation` fired first. The check runs
    /// inside the store lock, so a cancel that wins the race stores nothing.
    @discardableResult
    public func signedIn(_ session: PDTBrowserSession, unless cancellation: PDTCancellation? = nil) throws -> Bool {
        try locked {
            if cancellation?.isCancelled == true {
                return false
            }
            try replace(with: .signedIn(session))
            return true
        }
    }

    public func connect(personalToken: PDTAPIToken) throws {
        try locked { try replace(with: .personalTokenEntered(personalToken)) }
    }

    /// Deletes the stored credential. PDT has no API revoke for app tokens,
    /// so this returns the page where the user revokes PDTBar's access.
    @discardableResult
    public func disconnect() throws -> URL {
        try locked { try replace(with: .disconnected) }
        return PDTOAuthEndpoints.connectedApps
    }

    /// Refreshes the browser session now, whatever its expiry.
    public func refresh() throws -> PDTBrowserSession {
        try locked {
            try persistUnpersisted()
            guard case let .browserSession(session) = try connectedCredential() else {
                throw PDTAPIError.invalidRequest
            }
            return try refreshLocked(session)
        }
    }

    public func currentToken() throws -> PDTAPIToken {
        try locked {
            try persistUnpersisted()
            let credential = try connectedCredential()
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
            try persistUnpersisted()
            let credential = try connectedCredential()
            if credential.accessToken != token {
                return true
            }
            // PDT's guide: any TOKEN_INVALID triggers a refresh; only a failed refresh needs a new sign-in.
            if case let .browserSession(session) = credential {
                _ = try refreshLocked(session)
                return true
            }
            _ = try transition(.tokenRejected(token, reason: reason))
            return false
        }
    }

    private func refreshLocked(_ session: PDTBrowserSession) throws -> PDTBrowserSession {
        if let hold, now() < hold.until {
            throw hold.failure
        }
        let rotated: PDTBrowserSession
        do {
            rotated = try tokenEndpoint.refresh(session.refreshToken)
        } catch PDTTokenEndpointError.invalidGrant {
            // The table ignores a rejection of a pair another process has already rotated past.
            let state = try transition(.refreshRejected(session.refreshToken))
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
        unpersisted = (rotated, session.refreshToken)
        return try persist(rotated, from: session.refreshToken)
    }

    private func persistUnpersisted() throws {
        if let unpersisted {
            _ = try persist(unpersisted.session, from: unpersisted.from)
        }
    }

    private func persist(_ rotated: PDTBrowserSession, from: PDTRefreshToken) throws -> PDTBrowserSession {
        let state = try transition(.refreshed(rotated, from: from))
        unpersisted = nil
        guard case let .connected(.browserSession(fresh)) = state else {
            throw connectionError(state)
        }
        return fresh
    }

    private func replace(with event: PDTConnectionEvent) throws {
        // Cleared only once the replacement is stored: until then the pending pair is the only live one.
        _ = try transition(event)
        unpersisted = nil
        hold = nil
    }

    private func connectedCredential() throws -> PDTCredential {
        let state = try store.load()
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

    private func transition(_ event: PDTConnectionEvent) throws -> PDTConnectionState {
        let next = try store.load().applying(event)
        try store.save(next)
        return next
    }

    private func locked<Value>(_ body: () throws -> Value) throws -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try store.withExclusiveAccess(body)
    }
}
