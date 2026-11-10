import CryptoKit
import Foundation

/// PDT's app sign-in endpoints. Discovery only describes the MCP flow, so
/// these are fixed (ADR-0002).
public enum PDTOAuthEndpoints {
    public static let authorize = URL(string: "https://auth.portfoliodividendtracker.com/oauth/authorize")!
    public static let token = URL(string: "https://auth.portfoliodividendtracker.com/oauth/token")!
    /// PDT offers no API revoke for app tokens; users revoke here.
    public static let connectedApps = URL(string: "https://app.portfoliodividendtracker.com/account/integrations/authorizations")!

    static func isTokenRequest(_ request: URLRequest) -> Bool {
        request.httpMethod == "POST" && request.url == token
    }
}

/// The registered public PDT app. No client secret; the `read` scope only.
public struct PDTOAuthClient: Sendable, Equatable {
    public static let pdtbar = PDTOAuthClient(id: "01a1c518-271d-73cb-b279-9d2207283ce2", redirectPort: 47245)

    public let id: String
    /// PDT matches the registered redirect exactly. `0` binds any free port
    /// and exists for tests and smokes only.
    public let redirectPort: UInt16

    public init(id: String, redirectPort: UInt16) {
        self.id = id
        self.redirectPort = redirectPort
    }

    static let scope = "read"

    static func redirectURI(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/callback")!
    }
}

struct PDTPKCE: CustomStringConvertible, CustomReflectable {
    let verifier: String

    static func generate() -> PDTPKCE {
        PDTPKCE(verifier: randomURLSafeString(byteCount: 32))
    }

    var challenge: String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    var description: String { "PDTPKCE(redacted)" }
    var customMirror: Mirror { Mirror(self, children: []) }
}

struct PDTOAuthState: CustomStringConvertible, CustomReflectable {
    let value: String

    static func generate() -> PDTOAuthState {
        PDTOAuthState(value: randomURLSafeString(byteCount: 32))
    }

    func matches(_ candidate: String?) -> Bool {
        let expected = Array(value.utf8)
        let actual = Array((candidate ?? "").utf8)
        var difference = UInt8(expected.count == actual.count ? 0 : 1)
        for index in expected.indices {
            difference |= expected[index] ^ (index < actual.count ? actual[index] : 0)
        }
        return difference == 0
    }

    var description: String { "PDTOAuthState(redacted)" }
    var customMirror: Mirror { Mirror(self, children: []) }
}

private func randomURLSafeString(byteCount: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

public enum PDTTokenEndpointError: Error, Equatable, Sendable {
    /// The code or refresh token is no longer valid.
    case invalidGrant
    /// Another OAuth error response. `error` is the OAuth error code, never a description.
    case rejected(status: Int, error: String?)
    /// The request did not complete: transport failure, rate limit, server error, or cancel.
    case unavailable(PDTAPIError)
    case invalidResponse
}

/// Exchanges codes and refresh tokens at PDT's token endpoint over the same
/// `PDTHTTPTransport` as the API client.
public struct PDTTokenEndpoint {
    let client: PDTOAuthClient
    private let transport: any PDTHTTPTransport
    private let now: @Sendable () -> Date
    private let requestTimeout: TimeInterval

    public init(
        client: PDTOAuthClient = .pdtbar,
        transport: any PDTHTTPTransport,
        requestTimeout: TimeInterval = 20,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.now = now
    }

    func exchange(code: String, verifier: PDTPKCE, redirectURI: URL, cancellation: PDTCancellation?) throws -> PDTBrowserSession {
        try requestSession([
            "grant_type": "authorization_code",
            "client_id": client.id,
            "redirect_uri": redirectURI.absoluteString,
            "code": code,
            "code_verifier": verifier.verifier,
        ], cancellation: cancellation)
    }

    func refresh(_ refreshToken: PDTRefreshToken) throws -> PDTBrowserSession {
        try requestSession([
            "grant_type": "refresh_token",
            "client_id": client.id,
            "refresh_token": refreshToken.secret,
        ], cancellation: nil)
    }

    private func requestSession(_ form: KeyValuePairs<String, String>, cancellation: PDTCancellation?) throws -> PDTBrowserSession {
        var request = URLRequest(url: PDTOAuthEndpoints.token, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PDTUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(form.map { "\(formEncode($0))=\(formEncode($1))" }.joined(separator: "&").utf8)

        let requestedAt = now()
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try transport.sendClassifyingFailures(request, cancellation: cancellation)
        } catch let error as PDTAPIError {
            throw PDTTokenEndpointError.unavailable(error)
        }
        switch response.statusCode {
        case 200..<300:
            return try parseSession(data, requestedAt: requestedAt)
        case 429, 500...599:
            throw PDTTokenEndpointError.unavailable(
                PDTAPIError.classify(status: response.statusCode, body: data, headers: response.lowercasedHeaders, now: requestedAt)
            )
        default:
            let error = (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.error
            if error == "invalid_grant" {
                throw PDTTokenEndpointError.invalidGrant
            }
            throw PDTTokenEndpointError.rejected(status: response.statusCode, error: error)
        }
    }

    private func parseSession(_ data: Data, requestedAt: Date) throws -> PDTBrowserSession {
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: data),
              body.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !body.accessToken.isEmpty,
              !body.refreshToken.isEmpty,
              body.expiresIn > 0
        else {
            throw PDTTokenEndpointError.invalidResponse
        }
        return PDTBrowserSession(
            accessToken: PDTAPIToken(body.accessToken),
            refreshToken: PDTRefreshToken(body.refreshToken),
            accessExpiresAt: requestedAt.addingTimeInterval(TimeInterval(body.expiresIn))
        )
    }

    private static let formUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.formUnreserved) ?? ""
    }

    private struct TokenBody: Decodable {
        var accessToken: String
        var refreshToken: String
        var tokenType: String
        var expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }

    private struct OAuthErrorBody: Decodable {
        var error: String?
    }
}
