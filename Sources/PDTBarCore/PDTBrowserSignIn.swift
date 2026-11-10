import Foundation
import Network

public enum PDTSignInError: Error, Equatable, Sendable {
    /// Another process holds the registered loopback port.
    case portBusy(port: UInt16)
    case listenerFailed
    case browserUnavailable
    /// The user pressed Deny on PDT's consent screen (`error=access_denied`).
    case accessDenied
    /// PDT redirected back with another OAuth error code, such as `invalid_scope`.
    case authorizationFailed(error: String)
    case stateMismatch
    case missingCode
    case timedOut
    case cancelled
    case tokenExchange(PDTTokenEndpointError)
}

/// Browser sign-in: S256 PKCE, a random `state`, one callback on a loopback
/// listener, then the code exchange. Opening the browser is injected.
public struct PDTBrowserSignIn {
    private let tokenEndpoint: PDTTokenEndpoint
    private let openBrowser: (URL) throws -> Void
    private let timeout: TimeInterval

    public init(tokenEndpoint: PDTTokenEndpoint, timeout: TimeInterval = 300, openBrowser: @escaping (URL) throws -> Void) {
        self.tokenEndpoint = tokenEndpoint
        self.timeout = timeout
        self.openBrowser = openBrowser
    }

    public func run(cancellation: PDTCancellation? = nil) throws -> PDTBrowserSession {
        let client = tokenEndpoint.client
        let pkce = PDTPKCE.generate()
        let state = PDTOAuthState.generate()
        let listener = try PDTLoopbackCallbackListener(port: client.redirectPort)
        defer { listener.close() }
        let redirectURI = PDTOAuthClient.redirectURI(port: listener.port)

        var authorize = URLComponents(url: PDTOAuthEndpoints.authorize, resolvingAgainstBaseURL: false)!
        authorize.queryItems = [
            URLQueryItem(name: "client_id", value: client.id),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: PDTOAuthClient.scope),
            URLQueryItem(name: "state", value: state.value),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        do {
            try openBrowser(authorize.url!)
        } catch {
            throw PDTSignInError.browserUnavailable
        }

        let callback = try listener.waitForCallback(timeout: timeout, cancellation: cancellation)
        guard state.matches(callback["state"]) else {
            throw PDTSignInError.stateMismatch
        }
        if let error = callback["error"] {
            throw error == "access_denied" ? PDTSignInError.accessDenied : PDTSignInError.authorizationFailed(error: error)
        }
        guard let code = callback["code"], !code.isEmpty else {
            throw PDTSignInError.missingCode
        }
        do {
            return try tokenEndpoint.exchange(code: code, verifier: pkce, redirectURI: redirectURI, cancellation: cancellation)
        } catch let error as PDTTokenEndpointError {
            throw PDTSignInError.tokenExchange(error)
        }
    }
}

final class PDTLoopbackCallbackListener: @unchecked Sendable {
    private(set) var port: UInt16 = 0

    private let listener: NWListener
    private let queue = DispatchQueue(label: "pdtbar.pdt-sign-in.callback")
    private let lock = NSLock()
    private var callback: [String: String]?
    private let arrived = DispatchSemaphore(value: 0)

    init(port requestedPort: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: requestedPort == 0 ? .any : NWEndpoint.Port(rawValue: requestedPort)!
        )
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw PDTSignInError.listenerFailed
        }

        let started = StartResult()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                started.finish(nil)
            case let .failed(error), let .waiting(error):
                started.finish(error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        let failure = started.wait(seconds: 5)
        if let failure {
            listener.cancel()
            if case .posix(.EADDRINUSE) = failure {
                throw PDTSignInError.portBusy(port: requestedPort)
            }
            throw PDTSignInError.listenerFailed
        }
        guard let bound = listener.port?.rawValue else {
            listener.cancel()
            throw PDTSignInError.listenerFailed
        }
        port = bound
    }

    func waitForCallback(timeout: TimeInterval, cancellation: PDTCancellation?) throws -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)
        while arrived.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation?.isCancelled == true {
                throw PDTSignInError.cancelled
            }
            if Date() >= deadline {
                throw PDTSignInError.timedOut
            }
        }
        lock.lock()
        defer { lock.unlock() }
        return callback ?? [:]
    }

    func close() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffered: Data())
    }

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            let buffer = buffered + (data ?? Data())
            if let target = Self.requestTarget(buffer) {
                respond(on: connection, to: target)
            } else if isComplete || error != nil || buffer.count > 16384 {
                connection.cancel()
            } else {
                receive(on: connection, buffered: buffer)
            }
        }
    }

    private func respond(on connection: NWConnection, to target: URLComponents) {
        let isCallback = target.path == "/callback" && deliver(target.queryItems ?? [])
        let status = isCallback ? "200 OK" : "404 Not Found"
        let body = isCallback
            ? "<!doctype html><meta charset=utf-8><title>PDTBar</title><p>Return to PDTBar to finish signing in. You can close this tab.</p>"
            : "<!doctype html><meta charset=utf-8><title>PDTBar</title><p>Not found.</p>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if isCallback {
            listener.cancel()
        }
    }

    private func deliver(_ items: [URLQueryItem]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard callback == nil else {
            return false
        }
        callback = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        arrived.signal()
        return true
    }

    private static func requestTarget(_ buffer: Data) -> URLComponents? {
        // Byte search: Swift's String treats "\r\n" as one Character.
        guard buffer.range(of: Data("\r\n\r\n".utf8)) != nil,
              let lineEnd = buffer.range(of: Data("\r\n".utf8))
        else {
            return nil
        }
        let parts = String(decoding: buffer[..<lineEnd.lowerBound], as: UTF8.self).split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/") else {
            return URLComponents(string: "/")
        }
        return URLComponents(string: String(parts[1])) ?? URLComponents(string: "/")
    }

    private final class StartResult: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var finished = false
        private var error: NWError?

        func finish(_ error: NWError?) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else {
                return
            }
            finished = true
            self.error = error
            done.signal()
        }

        func wait(seconds: TimeInterval) -> NWError? {
            guard done.wait(timeout: .now() + seconds) == .success else {
                return .posix(.ETIMEDOUT)
            }
            lock.lock()
            defer { lock.unlock() }
            return error
        }
    }
}
