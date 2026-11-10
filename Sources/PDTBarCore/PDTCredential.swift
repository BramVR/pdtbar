import CryptoKit
import Foundation

/// A refresh token from PDT's token endpoint. Redacted like `PDTAPIToken`.
public struct PDTRefreshToken: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let secret: String

    public init(_ secret: String) {
        self.secret = secret
    }

    public init(from decoder: Decoder) throws {
        secret = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(secret)
    }

    public var fingerprint: PDTSecretFingerprint { PDTSecretFingerprint(secret) }
    public var description: String { "PDTRefreshToken(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// The only non-secret view of a secret: its SHA-256 and length. It names a
/// token in stored state and diagnostics; `description` shows a prefix.
public struct PDTSecretFingerprint: Sendable, Equatable, Codable, CustomStringConvertible {
    public let sha256: String
    public let length: Int

    init(_ secret: String) {
        sha256 = SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        length = secret.utf8.count
    }

    public var description: String { "sha256:\(sha256.prefix(8)) len=\(length)" }
}

/// What browser sign-in yields. PDT rotates both tokens on every refresh and
/// revokes the previous access token at once.
public struct PDTBrowserSession: Sendable, Equatable, Codable {
    public let accessToken: PDTAPIToken
    public let refreshToken: PDTRefreshToken
    public let accessExpiresAt: Date

    public init(accessToken: PDTAPIToken, refreshToken: PDTRefreshToken, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
    }
}

public enum PDTCredential: Sendable, Equatable, Codable {
    case browserSession(PDTBrowserSession)
    /// A pasted read-only personal access token. It cannot be refreshed.
    case personalToken(PDTAPIToken)

    public var kind: PDTCredentialKind {
        switch self {
        case .browserSession: .browserSession
        case .personalToken: .personalToken
        }
    }

    public var accessToken: PDTAPIToken {
        switch self {
        case let .browserSession(session): session.accessToken
        case let .personalToken(token): token
        }
    }
}

public enum PDTCredentialKind: String, Sendable, Equatable, Codable {
    case browserSession
    case personalToken
}

public enum PDTReconnectReason: Sendable, Equatable, Codable {
    /// The token endpoint answered `invalid_grant` for the refresh token with
    /// this fingerprint: the sign-in was revoked or lapsed.
    case refreshRejected(PDTSecretFingerprint)
    /// PDT answered `401 TOKEN_INVALID` for the current token and it could not
    /// be refreshed. `reason` is PDT's `details.reason`.
    case tokenRejected(reason: String?)
}

/// The stored PDT connection. A credential store holds exactly one of these;
/// `disconnected` is the absence of a stored item.
public enum PDTConnectionState: Sendable, Equatable, Codable {
    case disconnected
    case connected(PDTCredential)
    /// The stored credential no longer works. Its secrets are dropped; only
    /// the kind remains so copy can offer the matching way back.
    case needsReconnect(PDTCredentialKind, PDTReconnectReason)
}

public enum PDTConnectionEvent: Sendable {
    case signedIn(PDTBrowserSession)
    case personalTokenEntered(PDTAPIToken)
    /// `from` is the refresh token PDT rotated to produce the session.
    case refreshed(PDTBrowserSession, from: PDTRefreshToken)
    /// The token endpoint answered `invalid_grant` for this refresh token.
    case refreshRejected(PDTRefreshToken)
    case tokenRejected(PDTAPIToken, reason: String?)
    case disconnected
}

public extension PDTConnectionState {
    /// Every connection transition. Events about a credential that is no
    /// longer current (a refresh after a disconnect, a rejection of a token
    /// that was already rotated, a refresh of a pair the store has moved past)
    /// leave the state alone. A refresh PDT accepted proves the chain is live,
    /// so it wins over a concurrent `refreshRejected` of the pair it rotated,
    /// and only of that pair: a rejection names the pair it lost, so a pair
    /// from a sign-in the user has since replaced cannot reconnect it.
    func applying(_ event: PDTConnectionEvent) -> PDTConnectionState {
        switch (self, event) {
        case let (_, .signedIn(session)):
            return .connected(.browserSession(session))
        case let (_, .personalTokenEntered(token)):
            return .connected(.personalToken(token))
        case (_, .disconnected):
            return .disconnected
        case let (.connected(.browserSession(current)), .refreshed(session, from)) where current.refreshToken == from:
            return .connected(.browserSession(session))
        case let (.needsReconnect(.browserSession, .refreshRejected(rejected)), .refreshed(session, from)) where from.fingerprint == rejected:
            return .connected(.browserSession(session))
        case let (.connected(.browserSession(current)), .refreshRejected(rejected)) where current.refreshToken == rejected:
            return .needsReconnect(.browserSession, .refreshRejected(rejected.fingerprint))
        case let (.connected(credential), .tokenRejected(token, reason)) where credential.accessToken == token:
            return .needsReconnect(credential.kind, .tokenRejected(reason: reason))
        case (_, .refreshed), (_, .refreshRejected), (_, .tokenRejected):
            return self
        }
    }
}

public enum PDTPersonalTokenError: Error, Equatable, Sendable {
    case empty
    case malformed
}

public extension PDTAPIToken {
    /// Parses a pasted personal access token. Older tokens have no `pdt_`
    /// prefix, so only blank or non-printable input is refused.
    static func personal(pasted: String) throws -> PDTAPIToken {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PDTPersonalTokenError.empty
        }
        guard trimmed.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw PDTPersonalTokenError.malformed
        }
        return PDTAPIToken(trimmed)
    }
}
