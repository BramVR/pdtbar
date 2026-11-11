import Foundation

/// A PDT request trace id that is safe to show and copy. The only way to make
/// one is `init?`, which accepts a canonical UUID or 32 hex digits and nothing
/// else. Decoding runs the same check, so an edited file cannot inject text.
///
/// Shape cannot tell a trace id from another UUID: PDT documents `X-Request-Id`
/// and `error.traceId` as trace ids, and those are the only two fields read.
public struct PDTTraceID: Codable, Equatable, Sendable {
    public let value: String

    public init?(_ raw: String?) {
        guard let raw, Self.isTraceShaped(raw) else {
            return nil
        }
        value = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let traceID = PDTTraceID(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a trace id")
        }
        self = traceID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func isTraceShaped(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        let hyphenOffsets: Set<Int>
        switch bytes.count {
        case 32: hyphenOffsets = []
        case 36: hyphenOffsets = [8, 13, 18, 23]
        default: return false
        }
        return bytes.enumerated().allSatisfy { offset, byte in
            hyphenOffsets.contains(offset) ? byte == UInt8(ascii: "-") : isASCIIHexDigit(byte)
        }
    }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "f"),
             UInt8(ascii: "A")...UInt8(ascii: "F"):
            true
        default:
            false
        }
    }
}

/// Why one PDT request of a sync failed. Every stored property is a closed
/// enum, an Int, or a `PDTTraceID`. No initializer accepts text, so a token,
/// account id, URL or response body has no way in.
public struct PDTSyncFailure: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// `401`, or no usable credential.
        case reconnect
        /// `403 INSUFFICIENT_SCOPE`.
        case readAccessMissing
        /// `403 API_ACCESS_PAUSED`.
        case accessPaused
        /// Any other `403`.
        case forbidden
        /// `429` that outlasted the client's own retries.
        case rateLimited(retryAfterSeconds: Int?)
        /// No HTTP answer.
        case network(urlErrorCode: Int)
        /// `5xx`.
        case server(status: Int)
        /// A body that did not decode, or pagination that broke its contract.
        case unreadableResponse
        /// `404`, `422`, or another answer PDTBar never expects: a PDTBar bug or a PDT contract change.
        case unexpected(status: Int?)
        /// The Keychain or file store failed before the request.
        case credentialStore
        case cancelled

        /// Exhaustive over `PDTAPIError`, no `default`: a new API error does not
        /// compile until someone decides what it means here.
        public init(_ error: any Error) {
            if error is PDTCredentialStoreError {
                self = .credentialStore
                return
            }
            guard let error = error as? PDTAPIError else {
                self = .unexpected(status: nil)
                return
            }
            switch error {
            case .missingToken, .unauthenticated, .tokenInvalid:
                self = .reconnect
            case .insufficientScope:
                self = .readAccessMissing
            case .apiAccessPaused:
                self = .accessPaused
            case .forbidden:
                self = .forbidden
            case let .rateLimited(retryAfter):
                self = .rateLimited(retryAfterSeconds: Self.wholeSeconds(retryAfter))
            case let .transport(code):
                self = .network(urlErrorCode: code)
            case let .server(status, _):
                self = .server(status: status)
            case .invalidResponse, .paginationStalled, .paginationLimitExceeded:
                self = .unreadableResponse
            case .notFound:
                self = .unexpected(status: 404)
            case .validationFailed:
                self = .unexpected(status: 422)
            case let .unexpectedStatus(status):
                self = .unexpected(status: status)
            case .invalidRequest:
                self = .unexpected(status: nil)
            case .cancelled:
                self = .cancelled
            }
        }

        /// Every later request of this sync would fail the same way, so the
        /// remaining phases are skipped: access is gone, or PDT asked PDTBar to
        /// wait longer than the client retries.
        public var endsSync: Bool {
            switch self {
            case .reconnect, .readAccessMissing, .accessPaused, .forbidden, .credentialStore, .rateLimited:
                true
            case .network, .server, .unreadableResponse, .unexpected, .cancelled:
                false
            }
        }

        private static let longestRetryAfterSeconds = 86400.0

        private static func wholeSeconds(_ retryAfter: TimeInterval?) -> Int? {
            guard let retryAfter, !retryAfter.isNaN else {
                return nil
            }
            return Int(min(max(0, retryAfter), longestRetryAfterSeconds).rounded(.up))
        }
    }

    public let phase: BackgroundDetailRefreshPhase
    /// Nil when the sync stopped between requests.
    public let endpoint: PDTAPIEndpoint?
    public let kind: Kind
    public let requestCount: Int
    public let traceID: PDTTraceID?

    public init(
        phase: BackgroundDetailRefreshPhase,
        endpoint: PDTAPIEndpoint?,
        kind: Kind,
        requestCount: Int,
        traceID: PDTTraceID? = nil
    ) {
        self.phase = phase
        self.endpoint = endpoint
        self.kind = kind
        self.requestCount = max(0, requestCount)
        self.traceID = traceID
    }

    /// From a thrown error. A `PDTAPIRequestFailure` supplies the request count
    /// and trace id; a bare error counts as one request with no trace. Only the
    /// error's case and numbers are read, never its text.
    public init(_ error: any Error, resource: PDTAPIResource?, phase: BackgroundDetailRefreshPhase) {
        let requestFailure = error as? PDTAPIRequestFailure
        self.init(
            phase: phase,
            endpoint: resource?.endpoint,
            kind: Kind(requestFailure?.underlyingError ?? error),
            requestCount: requestFailure?.attemptCount ?? 1,
            traceID: requestFailure?.traceID
        )
    }

    /// Menu detail: the step that failed, why, and what to do about it.
    public var menuDetail: String {
        "\(phase.title): \(kind.menuDetail)"
    }

    /// The failure's lines of the "Copy diagnostics" text.
    var reportLines: [String] {
        var lines = ["step: \(phase.title.lowercased())"]
        if let endpoint {
            lines.append("request: GET /v1/\(endpoint.rawValue)")
        }
        lines.append("failure: \(kind.reportLabel)")
        if case let .rateLimited(retryAfterSeconds?) = kind {
            lines.append("retry after: \(retryAfterSeconds) s")
        }
        lines.append("requests sent: \(requestCount)")
        if let traceID {
            lines.append("trace: \(traceID.value)")
        }
        return lines
    }
}

extension PDTSyncFailure.Kind {
    /// What failed and the next action, lower-case to follow a step title.
    var menuDetail: String {
        switch self {
        case .reconnect:
            "PDT rejected the connection; reconnect"
        case .readAccessMissing:
            "no read access; reconnect"
        case .accessPaused:
            "PDT access paused; renew your subscription"
        case .forbidden:
            "PDT refused the request; reconnect"
        case let .rateLimited(retryAfterSeconds):
            "PDT rate limit; try again \(Self.waitCopy(retryAfterSeconds))"
        case .network:
            "could not reach PDT; check your connection"
        case .server:
            "PDT server problem; try again later"
        case .unreadableResponse:
            "PDT data could not be read; update PDTBar"
        case .unexpected:
            "unexpected PDT answer; update PDTBar"
        case .credentialStore:
            "stored connection unreadable; try again"
        case .cancelled:
            "stopped before finishing; try again"
        }
    }

    fileprivate var reportLabel: String {
        switch self {
        case .reconnect:
            "reconnect needed (HTTP 401 or no stored credential)"
        case .readAccessMissing:
            "read access missing (HTTP 403)"
        case .accessPaused:
            "access paused (HTTP 403)"
        case .forbidden:
            "forbidden (HTTP 403)"
        case .rateLimited:
            "rate limited (HTTP 429)"
        case let .network(urlErrorCode):
            "network (URLError \(urlErrorCode))"
        case let .server(status):
            "server (HTTP \(status))"
        case .unreadableResponse:
            "unreadable response"
        case let .unexpected(status?):
            "unexpected (HTTP \(status))"
        case .unexpected(nil):
            "unexpected"
        case .credentialStore:
            "credential store"
        case .cancelled:
            "cancelled"
        }
    }

    /// Fixed when the failure is recorded: the menu shows no live countdown.
    private static func waitCopy(_ retryAfterSeconds: Int?) -> String {
        guard let retryAfterSeconds, retryAfterSeconds > 0 else {
            return "later"
        }
        let minutes = (retryAfterSeconds + 59) / 60
        return minutes < 60 ? "in \(minutes) min" : "in \((minutes + 59) / 60) h"
    }
}
