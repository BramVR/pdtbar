import Foundation

/// The PDT connection over one credential store, and the token provider the
/// API client reads. Every state change goes through
/// `PDTConnectionState.applying` under one lock, so a refresh is single-flight:
/// callers that arrive while it runs wait, then read the rotated token. The
/// store is re-read on every call and written before a new token is returned.
public final class PDTConnection: PDTAPITokenProvider, @unchecked Sendable {
    public static let refreshLeeway: TimeInterval = 300

    private let store: any PDTCredentialStore
    private let tokenEndpoint: PDTTokenEndpoint
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(store: any PDTCredentialStore, tokenEndpoint: PDTTokenEndpoint, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.tokenEndpoint = tokenEndpoint
        self.now = now
    }

    public func state() throws -> PDTConnectionState {
        try locked { try store.load() }
    }

    public func signedIn(_ session: PDTBrowserSession) throws {
        try locked { _ = try transition(.signedIn(session)) }
    }

    public func connect(personalToken: PDTAPIToken) throws {
        try locked { _ = try transition(.personalTokenEntered(personalToken)) }
    }

    /// Deletes the stored credential. PDT has no API revoke for app tokens,
    /// so this returns the page where the user revokes PDTBar's access.
    @discardableResult
    public func disconnect() throws -> URL {
        try locked { _ = try transition(.disconnected) }
        return PDTOAuthEndpoints.connectedApps
    }

    /// Refreshes the browser session now, whatever its expiry.
    public func refresh() throws -> PDTBrowserSession {
        try locked {
            guard case let .browserSession(session) = try connectedCredential() else {
                throw PDTAPIError.invalidRequest
            }
            return try refreshLocked(session)
        }
    }

    public func currentToken() throws -> PDTAPIToken {
        try locked {
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
        let event: PDTConnectionEvent
        do {
            event = try .refreshed(tokenEndpoint.refresh(session.refreshToken))
        } catch PDTTokenEndpointError.invalidGrant {
            if let rotated = try sessionRotatedByAnotherProcess(since: session) {
                return rotated
            }
            event = .refreshRejected
        } catch let PDTTokenEndpointError.unavailable(error) {
            throw error
        } catch let PDTTokenEndpointError.rejected(status, _) {
            throw PDTAPIError.unexpectedStatus(status)
        } catch {
            throw PDTAPIError.invalidResponse
        }
        guard case let .connected(.browserSession(fresh)) = try transition(event) else {
            throw try connectionError(store.load())
        }
        return fresh
    }

    private func sessionRotatedByAnotherProcess(since session: PDTBrowserSession) throws -> PDTBrowserSession? {
        guard case let .connected(.browserSession(stored)) = try store.load(), stored.refreshToken != session.refreshToken else {
            return nil
        }
        return stored
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

    private func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
