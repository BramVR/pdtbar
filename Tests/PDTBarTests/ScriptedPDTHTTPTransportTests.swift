import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Scripted PDT HTTP transport")
struct ScriptedPDTHTTPTransportTests {
    @Test("A request answers with the reply scripted for it, whatever order requests arrive in")
    func repliesFollowTheRequestNotTheQueue() throws {
        let transport = ScriptedPDTHTTPTransport([
            "GET /v1/portfolio/holdings": ok("holdings"),
            "GET /v1/portfolio/distributions": ok("distributions"),
        ])

        #expect(try body(transport.send(get("portfolio/distributions"), cancellation: nil)) == "distributions")
        #expect(try body(transport.send(get("portfolio/holdings"), cancellation: nil)) == "holdings")
        #expect(transport.scriptErrors.isEmpty)
        #expect(transport.unusedReplies.isEmpty)
    }

    @Test("A request nothing scripts fails as unscripted instead of taking another request's reply")
    func unscriptedRequestFailsLoud() {
        let transport = ScriptedPDTHTTPTransport(["GET /v1/portfolio/holdings": ok("holdings")])

        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.unscriptedRequest("GET https://api.portfoliodividendtracker.com/v1/portfolio/distributions")) {
            try transport.send(get("portfolio/distributions"), cancellation: nil)
        }
        #expect(transport.scriptErrors == [.unscriptedRequest("GET https://api.portfoliodividendtracker.com/v1/portfolio/distributions")])
        #expect(transport.unusedReplies == ["GET /v1/portfolio/holdings"])
    }

    @Test("The client reports an unscripted request as a failure, never as an empty success")
    func clientSeesUnscriptedRequestAsFailure() {
        let transport = ScriptedPDTHTTPTransport(["GET /v1/portfolio/holdings": ok(#"{"data":[]}"#)])
        let client = PDTAPIClient(transport: transport, tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("pdt_test_secret")))

        #expect(throws: PDTAPIError.self) {
            _ = try client.get(.distributions)
        }
        #expect(transport.scriptErrors.count == 1)
    }

    @Test("A key scripted more than once answers in script order, then runs out")
    func repeatedKeyIsASequence() throws {
        let transport = ScriptedPDTHTTPTransport([
            "GET /v1/me": .response(status: 429, body: Data()),
            "GET /v1/me": ok("second"),
        ])

        #expect(try transport.send(get("me"), cancellation: nil).1.statusCode == 429)
        #expect(try body(transport.send(get("me"), cancellation: nil)) == "second")
        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.self) {
            try transport.send(get("me"), cancellation: nil)
        }
    }

    @Test("Query items in a key must be sent; other query items are ignored")
    func queryItemsNarrowAKey() throws {
        let transport = ScriptedPDTHTTPTransport([
            "GET /v1/calendar-events?page=1": ok("first"),
            "GET /v1/calendar-events?page=2": ok("second"),
        ])

        #expect(try body(transport.send(get("calendar-events?dateFrom=2026-06-22&page=2&perPage=100"), cancellation: nil)) == "second")
        #expect(try body(transport.send(get("calendar-events?page=1&perPage=100"), cancellation: nil)) == "first")
        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.self) {
            try transport.send(get("calendar-events?page=3"), cancellation: nil)
        }
    }

    @Test("A request two keys match fails as ambiguous")
    func ambiguousKeysFailLoud() {
        let transport = ScriptedPDTHTTPTransport([
            "GET /v1/calendar-events": ok("any"),
            "GET /v1/calendar-events?page=2": ok("second"),
        ])

        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.ambiguousRequest("GET https://api.portfoliodividendtracker.com/v1/calendar-events?page=2")) {
            try transport.send(get("calendar-events?page=2"), cancellation: nil)
        }
    }

    @Test("Method and origin are part of the key")
    func methodAndOriginMatch() throws {
        let tokens = ScriptedPDTHTTPTransport(["POST https://auth.portfoliodividendtracker.com/oauth/token": ok("token")])
        var post = URLRequest(url: PDTOAuthEndpoints.token)
        post.httpMethod = "POST"
        var get = URLRequest(url: PDTOAuthEndpoints.token)
        get.httpMethod = "GET"
        let otherOrigin = URLRequest(url: URL(string: "https://example.com/v1/me")!)
        let api = ScriptedPDTHTTPTransport(["GET /v1/me": ok("me")])

        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.self) { try tokens.send(get, cancellation: nil) }
        #expect(try body(tokens.send(post, cancellation: nil)) == "token")
        #expect(throws: ScriptedPDTHTTPTransport.ScriptError.self) { try api.send(otherOrigin, cancellation: nil) }
    }

    @Test("Keys round-trip through their text form and reject malformed text")
    func requestTextForm() throws {
        let key: ScriptedPDTHTTPTransport.Request = "GET /v1/prices/batch?symbolQuoteIds[]=51"
        let decoded = try JSONDecoder().decode(ScriptedPDTHTTPTransport.Request.self, from: JSONEncoder().encode(key))

        #expect(decoded == key)
        #expect(key.description == "GET /v1/prices/batch?symbolQuoteIds[]=51")
        #expect(ScriptedPDTHTTPTransport.Request(parsing: "/v1/me") == nil)
        #expect(ScriptedPDTHTTPTransport.Request(parsing: "get /v1/me") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScriptedPDTHTTPTransport.Request.self, from: Data(#""holdings""#.utf8))
        }
    }

    @Test("Every shipped --scripted-pdt script decodes, and each API reply names its request")
    func shippedScriptsDecode() throws {
        let directory = packageRoot.appending(path: "docs/pdt/fixtures/scripted")
        let scripts = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        #expect(scripts.nonEmptyAllSatisfy { url in
            (try? ScriptedPDTConnection.load(url)).map { !$0.api.responses.isEmpty } ?? false
        })
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func get(_ pathAndQuery: String) -> URLRequest {
    URLRequest(url: URL(string: "https://api.portfoliodividendtracker.com/v1/\(pathAndQuery)")!)
}

private func ok(_ body: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(body.utf8))
}

private func body(_ answer: (Data, HTTPURLResponse)) -> String {
    String(decoding: answer.0, as: UTF8.self)
}
