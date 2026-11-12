import Foundation

/// What the menu may say about PDT access. A projection of the
/// `PDTConnectionState` this process knows plus what PDT answered; it holds no
/// secret.
public enum PDTConnectionStatus: Equatable, Sendable {
    case notConnected
    case connected(PDTCredentialPersistence)
    case needsReconnect(PDTCredentialKind, PDTReconnectCause)
    /// `403 API_ACCESS_PAUSED`: the subscription ended. The token stays valid and stored.
    case subscriptionPaused
    /// The store could not be read, or it refused a disconnect and still
    /// holds the credential.
    case keychainUnavailable(PDTKeychainProblem)
}

/// Whether the credential this process is connected with outlives the process.
public enum PDTCredentialPersistence: Equatable, Sendable {
    case saved
    /// The credential store refused it (ADR-0003 decision 3). PDTBar uses it
    /// from memory until it quits and tries the save again on every operation.
    case thisSessionOnly(PDTKeychainProblem)
}

public enum PDTReconnectCause: String, Codable, Equatable, Sendable {
    /// The token endpoint answered `invalid_grant`: the browser sign-in lapsed or was revoked.
    case signInExpired
    case tokenExpired
    case tokenRevoked
    case tokenInvalid
    /// `403 INSUFFICIENT_SCOPE`: the credential cannot read the portfolio.
    case readAccessMissing
}

public enum PDTKeychainProblem: Equatable, Sendable {
    /// `errSecMissingEntitlement` (-34018): this build lacks the keychain access entitlement.
    case missingEntitlement
    case failed
}

public enum PDTSignInFailure: Equatable, Sendable {
    case portBusy
    case browserUnavailable
    case denied
    case timedOut
    case failed
}

/// A one-off message shown with the next connection screen.
public enum PDTConnectionNotice: Equatable, Sendable {
    case signInFailed(PDTSignInFailure)
    /// The credential was deleted. PDT has no revoke API for it, so the row opens this page.
    case disconnected(revokeAt: URL)
}

/// How every connection operation (check, sign-in, pasted token, disconnect) ends.
public struct PDTConnectionOutcome: Equatable, Sendable {
    public var status: PDTConnectionStatus
    public var notice: PDTConnectionNotice?

    public init(_ status: PDTConnectionStatus, notice: PDTConnectionNotice? = nil) {
        self.status = status
        self.notice = notice
    }
}

/// Why a fetch failed: a connection problem moves the menu to that connection
/// state; anything else (network, 5xx, 429, decode) is retryable with the
/// credential still connected, kept the way the connection says after the
/// fetch.
public enum PDTFetchFailure: Equatable, Sendable {
    case connection(PDTConnectionStatus)
    case unavailable(PDTCredentialPersistence)
}

extension PDTConnectionStatus {
    init(stored state: PDTConnectionState) {
        switch state {
        case .disconnected:
            self = .notConnected
        case .connected:
            self = .connected(.saved)
        case let .needsReconnect(kind, .refreshRejected):
            self = .needsReconnect(kind, .signInExpired)
        case let .needsReconnect(kind, .tokenRejected(reason)):
            self = .needsReconnect(kind, PDTReconnectCause(tokenInvalidReason: reason))
        }
    }

    init(storeError error: Error) {
        self = .keychainUnavailable(PDTKeychainProblem(storeError: error))
    }
}

extension PDTKeychainProblem {
    init(storeError error: Error) {
        self = error as? PDTCredentialStoreError == .missingKeychainEntitlement ? .missingEntitlement : .failed
    }
}

public extension PDTReconnectCause {
    /// PDT's `details.reason` on `401 TOKEN_INVALID`.
    init(tokenInvalidReason reason: String?) {
        switch reason {
        case "expired": self = .tokenExpired
        case "revoked": self = .tokenRevoked
        default: self = .tokenInvalid
        }
    }
}

public extension PDTSignInFailure {
    init(_ error: PDTSignInError) {
        switch error {
        case .portBusy: self = .portBusy
        case .browserUnavailable: self = .browserUnavailable
        case .accessDenied: self = .denied
        case .timedOut: self = .timedOut
        case .listenerFailed, .authorizationFailed, .cancelled, .tokenExchange: self = .failed
        }
    }
}
