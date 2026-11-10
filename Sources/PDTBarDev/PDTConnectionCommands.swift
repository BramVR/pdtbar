import Foundation
import PDTBarCore

enum PDTConnectionCommand {
    static let names: Set<String> = ["pdt-sign-in", "pdt-status", "pdt-refresh", "pdt-disconnect"]

    static func run(_ arguments: [String]) throws -> [String] {
        let noBrowser = arguments.count == 4 && arguments[0] == "pdt-sign-in" && arguments[3] == "--no-browser"
        guard arguments.count == 3 || noBrowser, names.contains(arguments[0]), arguments[1] == "--store" else {
            throw CommandError.usage
        }
        let tokenEndpoint = PDTTokenEndpoint(transport: URLSessionPDTHTTPTransport())
        let connection = PDTConnection(
            store: FilePDTCredentialStore(url: URL(fileURLWithPath: arguments[2])),
            tokenEndpoint: tokenEndpoint
        )

        switch arguments[0] {
        case "pdt-sign-in":
            let session = try PDTBrowserSignIn(tokenEndpoint: tokenEndpoint) { url in
                if noBrowser {
                    FileHandle.standardError.write(Data("Open this URL in a browser signed in to PDT and approve PDTBar:\n\(url.absoluteString)\n".utf8))
                    return
                }
                try openInBrowser(url)
                FileHandle.standardError.write(Data("Approve PDTBar in the browser window that opened; waiting for PDT to send you back.\n".utf8))
            }.run()
            try connection.signedIn(session)
            return try describe(connection.state()) + checkMe(connection)
        case "pdt-status":
            return try describe(connection.state())
        case "pdt-refresh":
            let before = try connection.state()
            let session = try connection.refresh()
            var lines = try describe(connection.state())
            if case let .connected(.browserSession(previous)) = before {
                lines.append("refresh-token-rotated: \(previous.refreshToken != session.refreshToken ? "yes" : "no")")
            }
            return try lines + checkMe(connection)
        default:
            let revokeAt = try connection.disconnect()
            return try describe(connection.state()) + ["revoke-at: \(revokeAt.absoluteString)"]
        }
    }

    private static func describe(_ state: PDTConnectionState) -> [String] {
        switch state {
        case .disconnected:
            return ["state: disconnected"]
        case let .needsReconnect(kind, reason):
            let detail = switch reason {
            case .refreshRejected: "refresh-rejected"
            case let .tokenRejected(reason): "token-rejected (\(reason ?? "unknown"))"
            }
            return ["state: needs-reconnect", "credential: \(kind.rawValue)", "reason: \(detail)"]
        case let .connected(.personalToken(token)):
            return ["state: connected", "credential: personalToken", "token: \(token.fingerprint)"]
        case let .connected(.browserSession(session)):
            let minutes = Int(session.accessExpiresAt.timeIntervalSinceNow / 60)
            return [
                "state: connected",
                "credential: browserSession",
                "access-token: \(session.accessToken.fingerprint)",
                "refresh-token: \(session.refreshToken.fingerprint)",
                "access-expires-at: \(ISO8601DateFormatter().string(from: session.accessExpiresAt)) (in \(minutes)m)",
            ]
        }
    }

    private static func checkMe(_ connection: PDTConnection) throws -> [String] {
        let transport = StatusRecordingTransport(URLSessionPDTHTTPTransport())
        let body: Data
        do {
            body = try PDTAPIClient(transport: transport, tokenProvider: connection).get(.me)
        } catch let error as PDTAPIError {
            return ["me-status: \(transport.lastStatus.map(String.init) ?? "none")", "me-error: \(error)"]
        }
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        var lines = [
            "me-status: \(transport.lastStatus.map(String.init) ?? "none")",
            "me-keys: \(object.keys.sorted().joined(separator: ","))",
        ]
        if let data = object["data"] as? [String: Any] {
            lines.append("me-data-keys: \(data.keys.sorted().joined(separator: ","))")
        }
        return lines
    }

    private static func openInBrowser(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PDTSignInError.browserUnavailable
        }
    }
}

private final class StatusRecordingTransport: PDTHTTPTransport, @unchecked Sendable {
    private let base: any PDTHTTPTransport
    private let lock = NSLock()
    private var status: Int?

    init(_ base: any PDTHTTPTransport) {
        self.base = base
    }

    var lastStatus: Int? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        let (data, response) = try base.send(request, cancellation: cancellation)
        lock.lock()
        status = response.statusCode
        lock.unlock()
        return (data, response)
    }
}
