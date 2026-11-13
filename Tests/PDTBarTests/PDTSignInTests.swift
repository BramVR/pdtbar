import CryptoKit
import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore
import Security

@Suite("PDT browser sign-in")
struct PDTBrowserSignInTests {
    @Test("Approving in the browser exchanges the code with the S256 verifier and closes the listener")
    func approvedSignInExchangesCode() throws {
        let transport = ScriptedPDTHTTPTransport([tokenReply(access: "access-1", refresh: "refresh-1")])
        let browser = FakeBrowser { _ in ["code": "auth-code-1"] }

        let session = try signIn(transport: transport, browser: browser).run()

        #expect(session.accessToken == PDTAPIToken("access-1"))
        #expect(session.refreshToken == PDTRefreshToken("refresh-1"))
        let authorize = try #require(browser.authorizeURL)
        let query = queryItems(authorize)
        #expect(authorize.absoluteString.hasPrefix("https://auth.portfoliodividendtracker.com/oauth/authorize?"))
        #expect(query["client_id"] == "test-client")
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "read")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"]?.hasPrefix("http://127.0.0.1:") == true)
        #expect(query["redirect_uri"]?.hasSuffix("/callback") == true)
        #expect((query["state"]?.count ?? 0) >= 43)

        let request = try #require(transport.requests.only)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://auth.portfoliodividendtracker.com/oauth/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("pdtbar/") == true)
        let form = formItems(request)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["client_id"] == "test-client")
        #expect(form["code"] == "auth-code-1")
        #expect(form["redirect_uri"] == query["redirect_uri"])
        let verifier = try #require(form["code_verifier"])
        #expect((43...128).contains(verifier.count))
        #expect(base64URLSHA256(verifier) == query["code_challenge"])

        #expect(browser.waitForCallbackStatus() == 200)
        #expect(FakeBrowser.get(try #require(URL(string: query["redirect_uri"]! + "?code=again"))) == nil)
    }

    @Test("Requests with a wrong, missing, or repeated state get an error page and the listener keeps waiting for the real callback")
    func strayCallbacksDoNotEndSignIn() throws {
        let transport = ScriptedPDTHTTPTransport([tokenReply(access: "access-1", refresh: "refresh-1")])
        let browser = FakeBrowser(callbacks: { state in
            [
                "code=forged&state=forged-state",
                "code=forged",
                "error=access_denied&state=forged-state",
                "code=forged&state=\(state)&state=forged-state",
                "code=forged&code=other&state=\(state)",
                "state=\(state)",
                "code=auth-code-1&state=\(state)",
            ]
        })

        let session = try signIn(transport: transport, browser: browser).run()

        #expect(session.accessToken == PDTAPIToken("access-1"))
        #expect(browser.waitForCallbackStatuses(count: 7) == [400, 400, 400, 400, 400, 400, 200])
        #expect(formItems(try #require(transport.requests.only))["code"] == "auth-code-1")
    }

    @Test("Deny on the consent screen is access denied; other redirect errors keep their code")
    func deniedAndFailedAuthorization() throws {
        let denied = FakeBrowser { _ in ["error": "access_denied"] }
        #expect(throws: PDTSignInError.accessDenied) {
            try signIn(transport: ScriptedPDTHTTPTransport([]), browser: denied).run()
        }

        let invalidScope = FakeBrowser { _ in ["error": "invalid_scope"] }
        #expect(throws: PDTSignInError.authorizationFailed(error: "invalid_scope")) {
            try signIn(transport: ScriptedPDTHTTPTransport([]), browser: invalidScope).run()
        }
    }

    @Test("A busy loopback port fails before the browser opens")
    func portBusy() throws {
        let holder = try PortHolder()
        defer { holder.close() }
        let browser = FakeBrowser { _ in ["code": "c"] }

        #expect(throws: PDTSignInError.portBusy(port: holder.port)) {
            try signIn(transport: ScriptedPDTHTTPTransport([]), browser: browser, port: holder.port).run()
        }
        #expect(browser.authorizeURL == nil)
    }

    @Test("No callback within the timeout ends sign-in; cancellation ends it too")
    func timeoutAndCancellation() throws {
        let idle = FakeBrowser(respond: nil)
        #expect(throws: PDTSignInError.timedOut) {
            try signIn(transport: ScriptedPDTHTTPTransport([]), browser: idle, timeout: 0.3).run()
        }

        let cancellation = PDTCancellation()
        cancellation.cancel()
        #expect(throws: PDTSignInError.cancelled) {
            try signIn(transport: ScriptedPDTHTTPTransport([]), browser: idle).run(cancellation: cancellation)
        }
    }

    @Test("A rejected code exchange surfaces the token endpoint error")
    func rejectedExchange() throws {
        let transport = ScriptedPDTHTTPTransport([oauthError(400, "invalid_grant")])
        let browser = FakeBrowser { _ in ["code": "stale"] }

        #expect(throws: PDTSignInError.tokenExchange(.invalidGrant)) {
            try signIn(transport: transport, browser: browser).run()
        }
    }

    @Test("The production transport refuses a POST anywhere but the token endpoint")
    func productionTransportRefusesOtherPosts() throws {
        for url in ["https://api.portfoliodividendtracker.com/v1/me", "https://auth.portfoliodividendtracker.com/oauth/revoke"] {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            #expect(throws: PDTAPIError.invalidRequest) {
                try URLSessionPDTHTTPTransport().send(request, cancellation: nil)
            }
        }
    }

    private func signIn(
        transport: ScriptedPDTHTTPTransport,
        browser: FakeBrowser,
        port: UInt16 = 0,
        timeout: TimeInterval = 10
    ) -> PDTBrowserSignIn {
        PDTBrowserSignIn(
            tokenEndpoint: PDTTokenEndpoint(client: PDTOAuthClient(id: "test-client", redirectPort: port), transport: transport),
            timeout: timeout,
            openBrowser: browser.open
        )
    }
}

@Suite("PDT connection and token refresh")
struct PDTConnectionTests {
    @Test("A token near expiry is refreshed, persisted, and used for the request")
    func expiryDrivenRefresh() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 120))))
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2")])
        let api = ScriptedPDTHTTPTransport([ok])
        let connection = connection(store, tokens)

        _ = try PDTAPIClient(transport: api, tokenProvider: connection).get(.me)

        let refresh = formItems(try #require(tokens.requests.only))
        #expect(refresh["grant_type"] == "refresh_token")
        #expect(refresh["refresh_token"] == "refresh-1")
        #expect(refresh["client_id"] == "test-client")
        #expect(api.requests.only?.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
        #expect(try store.load().state == .connected(.browserSession(session("access-2", "refresh-2", expiresAt: testNow + 3600))))
    }

    @Test("A token with time left is used without a refresh")
    func freshTokenNotRefreshed() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 3000))))
        let tokens = ScriptedPDTHTTPTransport([])

        #expect(try connection(store, tokens).currentToken() == PDTAPIToken("access-1"))
        #expect(tokens.requests.isEmpty)
    }

    @Test("Concurrent requests share exactly one network refresh and all use the rotated token")
    func concurrentRefreshIsSingleFlight() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))))
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2")], initialDelaySeconds: 0.3)
        let api = ScriptedPDTHTTPTransport(Array(repeating: ok, count: 8))
        let client = PDTAPIClient(transport: api, tokenProvider: connection(store, tokens))
        let failures = Counter()

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do {
                _ = try client.get(.me)
            } catch {
                failures.increment()
            }
        }

        #expect(failures.value == 0)
        #expect(tokens.requests.count == 1)
        #expect(api.requests.count == 8)
        #expect(api.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-2" })
    }

    @Test("Two connections over one store share one refresh even when the winner's save lands after the loser would have re-read", arguments: [false, true])
    func concurrentConnectionsOverOneStore(onDisk: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = PDTConnectionState.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1)))
        let store: any PDTCredentialStore
        if onDisk {
            let file = FilePDTCredentialStore(url: directory.appending(path: "pdt.json"))
            try file.save(PDTStoredConnection(initial))
            store = file
        } else {
            store = InMemoryPDTCredentialStore(initial)
        }
        let tokens = ArrivalOrderTransport([(0.3, tokenReply(access: "access-2", refresh: "refresh-2")), (0, oauthError(400, "invalid_grant"))])
        let connections = [connection(store, tokens), connection(store, tokens)]
        let results = Results()

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            results.record(Result { try connections[index].currentToken() })
        }

        #expect(results.values.map { try? $0.get() } == [PDTAPIToken("access-2"), PDTAPIToken("access-2")])
        #expect(tokens.requests.count == 1)
        #expect(try store.load().state == .connected(.browserSession(session("access-2", "refresh-2", expiresAt: testNow + 3600))))
    }

    @Test("A refresh PDT accepted wins over a concurrent rejection of the pair it rotated, and a stale refresh or rejection never regresses the store")
    func acceptedRefreshWinsOverRejection() throws {
        let first = session("access-1", "refresh-1", expiresAt: testNow)
        let second = session("access-2", "refresh-2", expiresAt: testNow + 3600)
        let third = session("access-3", "refresh-3", expiresAt: testNow + 7200)
        let refreshedSecond = PDTConnectionEvent.refreshed(second, from: first.refreshToken)
        let firstRejected = PDTConnectionState.needsReconnect(.browserSession, .refreshRejected(first.refreshToken.fingerprint))
        let thirdRejected = PDTConnectionState.needsReconnect(.browserSession, .refreshRejected(third.refreshToken.fingerprint))

        #expect(PDTConnectionState.connected(.browserSession(first)).applying(refreshedSecond) == .connected(.browserSession(second)))
        #expect(PDTConnectionState.connected(.browserSession(first)).applying(.refreshRejected(first.refreshToken)) == firstRejected)
        #expect(firstRejected.applying(refreshedSecond) == .connected(.browserSession(second)))
        #expect(thirdRejected.applying(refreshedSecond) == thirdRejected)
        #expect(PDTConnectionState.connected(.browserSession(third)).applying(refreshedSecond) == .connected(.browserSession(third)))
        #expect(PDTConnectionState.connected(.browserSession(third)).applying(.refreshRejected(first.refreshToken)) == .connected(.browserSession(third)))
        #expect(PDTConnectionState.connected(.personalToken(PDTAPIToken("p"))).applying(refreshedSecond) == .connected(.personalToken(PDTAPIToken("p"))))
        #expect(PDTConnectionState.disconnected.applying(refreshedSecond) == .disconnected)

        let store = UnlockedStore(.connected(.browserSession(first)))
        let tokens = ArrivalOrderTransport([(0.3, tokenReply(access: "access-2", refresh: "refresh-2")), (0, oauthError(400, "invalid_grant"))])
        let connections = [connection(store, tokens), connection(store, tokens)]
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            results.record(Result { try connections[index].currentToken() })
        }

        #expect(results.values.compactMap { try? $0.get() } == [PDTAPIToken("access-2")])
        #expect(try store.load().state == .connected(.browserSession(second)))
        #expect(try connections[1].currentToken() == PDTAPIToken("access-2"))
    }

    @Test("A burst of callers during a failing refresh sends one token request and shares the failure until the backoff ends")
    func failedRefreshIsNotRetriedPerCaller() throws {
        let clock = TestClock()
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 20))))
        let tokens = ScriptedPDTHTTPTransport(Array(repeating: .failure(.timedOut), count: 3) + [tokenReply(access: "access-2", refresh: "refresh-2")])
        let connection = connection(store, tokens, clock: clock)
        let results = Results()

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.record(Result { try connection.currentToken() })
        }

        #expect(results.values.allSatisfy { (try? $0.get()) == PDTAPIToken("access-1") })
        #expect(tokens.requests.count == 1)

        clock.advance(by: 5)
        #expect(try connection.currentToken() == PDTAPIToken("access-1"))
        #expect(tokens.requests.count == 2)
        #expect(try connection.currentToken() == PDTAPIToken("access-1"))
        #expect(tokens.requests.count == 2)

        clock.advance(by: 10)
        #expect(try connection.currentToken() == PDTAPIToken("access-1"))
        #expect(tokens.requests.count == 3)

        clock.advance(by: 5)
        #expect(throws: PDTAPIError.transport(code: URLError.timedOut.rawValue)) { try connection.currentToken() }
        #expect(tokens.requests.count == 3)

        clock.advance(by: 15)
        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        #expect(tokens.requests.count == 4)
    }

    @Test("A rate-limited refresh waits out Retry-After before the next token request")
    func rateLimitedRefreshHonorsRetryAfter() throws {
        let clock = TestClock()
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 60))))
        let tokens = ScriptedPDTHTTPTransport([
            .response(status: 429, body: Data(), headers: ["Retry-After": "20"]),
            tokenReply(access: "access-2", refresh: "refresh-2"),
        ])
        let connection = connection(store, tokens, clock: clock)

        #expect(try connection.currentToken() == PDTAPIToken("access-1"))
        clock.advance(by: 19)
        #expect(try connection.currentToken() == PDTAPIToken("access-1"))
        #expect(tokens.requests.count == 1)
        clock.advance(by: 1)
        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        #expect(tokens.requests.count == 2)
    }

    @Test("A rotated pair the store refuses is used from memory, PDT is not asked again, and the pair is saved once the store takes writes")
    func refusedRotationIsUsedAndSavedLater() throws {
        let stale = PDTConnectionState.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1)))
        let store = FailingSaveStore(stale, failures: .max)
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2")])
        let api = ScriptedPDTHTTPTransport([ok, ok])
        let connection = connection(store, tokens)
        let client = PDTAPIClient(transport: api, tokenProvider: connection)

        _ = try client.get(.me)
        _ = try client.get(.me)
        #expect(api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-2", "Bearer access-2"])
        #expect(connection.status() == .connected(.thisSessionOnly(.failed)))
        #expect(try store.load().state == stale)

        store.recover()
        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        #expect(connection.status() == .connected(.saved))
        #expect(try store.load().state == .connected(.browserSession(session("access-2", "refresh-2", expiresAt: testNow + 3600))))
        #expect(tokens.requests.count == 1)
    }

    @Test(
        "A session the store never takes keeps working across refreshes: each rotated pair replaces the held one, and the newest is saved once the store takes writes",
        arguments: [false, true]
    )
    func unsavedSessionSurvivesRefreshes(signedInHere: Bool) throws {
        let first = session("access-1", "refresh-1", expiresAt: testNow - 1)
        let store = FailingSaveStore(signedInHere ? .disconnected : .connected(.browserSession(first)), failures: .max)
        let tokens = ScriptedPDTHTTPTransport([
            tokenReply(access: "access-2", refresh: "refresh-2"), tokenReply(access: "access-3", refresh: "refresh-3"),
        ])
        let clock = TestClock()
        let connection = connection(store, tokens, clock: clock)
        if signedInHere {
            #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try connection.signedIn(first) }
        }

        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        clock.advance(by: 3600)
        #expect(try connection.currentToken() == PDTAPIToken("access-3"))
        #expect(tokens.requests.map { formItems($0)["refresh_token"] } == ["refresh-1", "refresh-2"])
        #expect(connection.status() == .connected(.thisSessionOnly(.failed)))

        store.recover()
        #expect(connection.status() == .connected(.saved))
        #expect(try store.load().state == .connected(.browserSession(session("access-3", "refresh-3", expiresAt: testNow + 7200))))
        #expect(tokens.requests.count == 2)
    }

    @Test("A store found holding a pair this connection has since rotated again is moved on to the newest pair, which stays in use, also after another process saw that pair rejected")
    func storeHoldingAMiddlePairIsMovedOn() throws {
        let store = FailingSaveStore(
            .connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))),
            failures: .max,
            failedSavesLandUnreadable: true
        )
        let tokens = ScriptedPDTHTTPTransport([
            tokenReply(access: "access-2", refresh: "refresh-2"), tokenReply(access: "access-3", refresh: "refresh-3"),
        ])
        let clock = TestClock()
        let connection = connection(store, tokens, clock: clock)
        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        clock.advance(by: 3600)
        #expect(try connection.currentToken() == PDTAPIToken("access-3"))

        // The first rotated pair's save landed while the store could not be read back, and another process then saw PDT reject it.
        store.recover()
        let middle = try store.load()
        #expect(middle.state == .connected(.browserSession(session("access-2", "refresh-2", expiresAt: testNow + 3600))))
        try store.save(PDTStoredConnection(
            .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-2").fingerprint)),
            generation: middle.generation
        ))

        #expect(try connection.currentToken() == PDTAPIToken("access-3"))
        #expect(try store.load().state == .connected(.browserSession(session("access-3", "refresh-3", expiresAt: testNow + 7200))))
        #expect(connection.status() == .connected(.saved))
        #expect(tokens.requests.count == 2)
    }

    @Test(
        "PDT rejecting a session the store never took ends it: later checks need a reconnect, not a sign-in from scratch, and the pair is not sent again",
        arguments: [false, true]
    )
    func rejectedUnsavedSessionNeedsReconnect(signedInHere: Bool) throws {
        let first = session("access-1", "refresh-1", expiresAt: testNow - 1)
        let store = FailingSaveStore(signedInHere ? .disconnected : .connected(.browserSession(first)), failures: .max)
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2"), oauthError(400, "invalid_grant")])
        let clock = TestClock()
        let connection = connection(store, tokens, clock: clock)
        if signedInHere {
            #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) { try connection.signedIn(first) }
        }

        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        clock.advance(by: 3600)
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try connection.currentToken() }
        #expect(connection.status() == .needsReconnect(.browserSession, .signInExpired))
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try connection.currentToken() }
        #expect(tokens.requests.count == 2)

        store.recover()
        #expect(connection.status() == .needsReconnect(.browserSession, .signInExpired))
        #expect(try store.load().state == .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-2").fingerprint)))
    }

    @Test("invalid_grant moves the connection to needs-reconnect and stops further refreshes")
    func invalidGrantNeedsReconnect() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))))
        let tokens = ScriptedPDTHTTPTransport([oauthError(400, "invalid_grant")])
        let connection = connection(store, tokens)

        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try connection.currentToken() }
        #expect(try connection.state() == .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-1").fingerprint)))
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try connection.currentToken() }
        #expect(tokens.requests.count == 1)
    }

    @Test("A sign-in or disconnect the store refuses takes the place of a rotated pair it also refused, and lands when the store takes writes again", arguments: [false, true])
    func refusedReplacementSupersedesRefusedRotation(signIn: Bool) throws {
        let store = FailingSaveStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))), failures: .max)
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2")])
        let connection = connection(store, tokens)
        let replacement = session("access-9", "refresh-9", expiresAt: testNow + 3600)
        let replaced = signIn ? PDTConnectionState.connected(.browserSession(replacement)) : .disconnected

        #expect(try connection.currentToken() == PDTAPIToken("access-2"))
        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) {
            if signIn {
                try connection.signedIn(replacement)
            } else {
                try connection.disconnect()
            }
        }

        store.recover()
        #expect(try connection.state() == replaced)
        #expect(try store.load().state == replaced)
        if signIn {
            #expect(try connection.currentToken() == PDTAPIToken("access-9"))
        } else {
            #expect(throws: PDTAPIError.missingToken) { try connection.currentToken() }
        }
        #expect(tokens.requests.count == 1)
    }

    @Test("A rejection the store refuses to record still ends the connection: the credential is not sent again and later checks need a reconnect")
    func refusedRejectionIsHeld() throws {
        let personal = FailingSaveStore(.connected(.personalToken(PDTAPIToken("pdt_stored"))), failures: .max)
        let api = ScriptedPDTHTTPTransport([tokenInvalid("revoked")])
        let pasted = connection(personal, ScriptedPDTHTTPTransport([]))

        #expect(throws: PDTAPIError.tokenInvalid(reason: "revoked")) {
            try PDTAPIClient(transport: api, tokenProvider: pasted).get(.me)
        }
        #expect(pasted.status() == .needsReconnect(.personalToken, .tokenRevoked))
        #expect(throws: PDTAPIError.tokenInvalid(reason: "revoked")) { try pasted.currentToken() }
        #expect(api.requests.count == 1)
        #expect(try personal.load().state == .connected(.personalToken(PDTAPIToken("pdt_stored"))))
        personal.recover()
        #expect(pasted.status() == .needsReconnect(.personalToken, .tokenRevoked))
        #expect(try personal.load().state == .needsReconnect(.personalToken, .tokenRejected(reason: "revoked")))

        let browser = FailingSaveStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))), failures: .max)
        let tokens = ScriptedPDTHTTPTransport([oauthError(400, "invalid_grant")])
        let signedIn = connection(browser, tokens)

        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try signedIn.currentToken() }
        #expect(signedIn.status() == .needsReconnect(.browserSession, .signInExpired))
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try signedIn.currentToken() }
        #expect(tokens.requests.count == 1)
        browser.recover()
        #expect(signedIn.status() == .needsReconnect(.browserSession, .signInExpired))
        #expect(try browser.load().state == .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-1").fingerprint)))
    }

    @Test("A pending pair from a sign-in the user disconnected never reconnects it after a later sign-in is rejected")
    func pendingPairFromDisconnectedSignInStaysDropped() throws {
        let store = FailingSaveStore(.connected(.browserSession(session("access-x1", "refresh-x1", expiresAt: testNow - 1))), failures: 1)
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-x2", refresh: "refresh-x2"), oauthError(400, "invalid_grant")])
        let stale = connection(store, tokens)
        let current = connection(store, tokens)
        let laterSignInRejected = PDTConnectionState.needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-y1").fingerprint))

        #expect(try stale.currentToken() == PDTAPIToken("access-x2"))
        try current.disconnect()
        try current.signedIn(session("access-y1", "refresh-y1", expiresAt: testNow - 1))
        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try current.currentToken() }
        #expect(try store.load().state == laterSignInRejected)

        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) { try stale.currentToken() }
        #expect(try store.load().state == laterSignInRejected)
        #expect(tokens.requests.count == 2)
    }

    @Test("invalid_grant after another process already rotated the pair adopts the stored pair")
    func invalidGrantAfterSharedRotation() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow - 1))))
        let rotated = session("access-2", "refresh-2", expiresAt: testNow + 3600)
        let tokens = HookTransport(reply: oauthError(400, "invalid_grant")) {
            try? store.save(PDTStoredConnection(.connected(.browserSession(rotated))))
        }

        #expect(try connection(store, tokens).currentToken() == PDTAPIToken("access-2"))
        #expect(try store.load().state == .connected(.browserSession(rotated)))
    }

    @Test("A 401 expired on a token that looked valid refreshes once and retries")
    func expiredRejectionRefreshes() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 3000))))
        let tokens = ScriptedPDTHTTPTransport([tokenReply(access: "access-2", refresh: "refresh-2")])
        let api = ScriptedPDTHTTPTransport([tokenInvalid("expired"), ok])

        _ = try PDTAPIClient(transport: api, tokenProvider: connection(store, tokens)).get(.me)

        #expect(tokens.requests.count == 1)
        #expect(api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-1", "Bearer access-2"])
    }

    @Test("A 401 revoked on a token another caller already rotated retries with the current token")
    func revokedStaleTokenRetriesWithCurrent() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 3000))))
        let api = HookTransport(replies: [tokenInvalid("revoked"), ok]) {
            try? store.save(PDTStoredConnection(.connected(.browserSession(session("access-2", "refresh-2", expiresAt: testNow + 3600)))))
        }

        _ = try PDTAPIClient(transport: api, tokenProvider: connection(store, ScriptedPDTHTTPTransport([]))).get(.me)

        #expect(api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-1", "Bearer access-2"])
    }

    @Test("A 401 revoked on the current token refreshes; a rejected refresh then needs a reconnect")
    func revokedCurrentTokenRefreshesThenNeedsReconnect() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 3000))))
        let tokens = ScriptedPDTHTTPTransport([oauthError(400, "invalid_grant")])
        let api = ScriptedPDTHTTPTransport([tokenInvalid("revoked")])

        #expect(throws: PDTAPIError.tokenInvalid(reason: nil)) {
            try PDTAPIClient(transport: api, tokenProvider: connection(store, tokens)).get(.me)
        }
        #expect(formItems(try #require(tokens.requests.only))["refresh_token"] == "refresh-1")
        #expect(api.requests.count == 1)
        #expect(try store.load().state == .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-1").fingerprint)))
    }

    @Test("A transient refresh failure keeps using an access token that has not expired yet")
    func transientRefreshFailureFallsBack() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 60))))
        let tokens = ScriptedPDTHTTPTransport([.failure(.timedOut)])

        #expect(try connection(store, tokens).currentToken() == PDTAPIToken("access-1"))
        #expect(try store.load().state == .connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 60))))
    }

    @Test("A pasted personal token is stored, sent as is, and needs a reconnect when PDT rejects it")
    func personalTokenPath() throws {
        let store = InMemoryPDTCredentialStore()
        let tokens = ScriptedPDTHTTPTransport([])
        let connection = connection(store, tokens)
        let api = ScriptedPDTHTTPTransport([ok, tokenInvalid("expired")])
        let client = PDTAPIClient(transport: api, tokenProvider: connection)

        try connection.connect(personalToken: PDTAPIToken.personal(pasted: "  1|legacyTokenWithoutPrefix\n"))
        _ = try client.get(.me)
        #expect(throws: PDTAPIError.tokenInvalid(reason: "expired")) { try client.get(.me) }

        #expect(api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer 1|legacyTokenWithoutPrefix", "Bearer 1|legacyTokenWithoutPrefix",
        ])
        #expect(tokens.requests.isEmpty)
        #expect(try connection.state() == .needsReconnect(.personalToken, .tokenRejected(reason: "expired")))
    }

    @Test("Pasted tokens accept the pdt_ prefix or none, and refuse blank or non-printable input")
    func personalTokenParsing() throws {
        #expect(try PDTAPIToken.personal(pasted: "pdt_abc123") == PDTAPIToken("pdt_abc123"))
        #expect(try PDTAPIToken.personal(pasted: "abc123") == PDTAPIToken("abc123"))
        #expect(throws: PDTPersonalTokenError.empty) { try PDTAPIToken.personal(pasted: " \n ") }
        #expect(throws: PDTPersonalTokenError.malformed) { try PDTAPIToken.personal(pasted: "pdt_abc 123") }
        #expect(throws: PDTPersonalTokenError.malformed) { try PDTAPIToken.personal(pasted: "pdt_abc€") }
    }

    @Test("Disconnect deletes the credential and points to PDT's connected apps")
    func disconnect() throws {
        let store = InMemoryPDTCredentialStore(.connected(.browserSession(session("access-1", "refresh-1", expiresAt: testNow + 3000))))
        let connection = connection(store, ScriptedPDTHTTPTransport([]))

        let revokeAt = try connection.disconnect()

        #expect(revokeAt.absoluteString == "https://app.portfoliodividendtracker.com/account/integrations/authorizations")
        #expect(try store.load().state == .disconnected)
        #expect(throws: PDTAPIError.missingToken) { try connection.currentToken() }
    }

    @Test("Sign-in replaces a needs-reconnect state")
    func signInAfterReconnect() throws {
        let store = InMemoryPDTCredentialStore(.needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken("refresh-1").fingerprint)))
        let connection = connection(store, ScriptedPDTHTTPTransport([]))

        try connection.signedIn(session("access-9", "refresh-9", expiresAt: testNow + 3600))

        #expect(try connection.currentToken() == PDTAPIToken("access-9"))
    }

    private func connection(_ store: any PDTCredentialStore, _ tokens: any PDTHTTPTransport, clock: TestClock = TestClock()) -> PDTConnection {
        PDTConnection(
            store: store,
            tokenEndpoint: PDTTokenEndpoint(client: PDTOAuthClient(id: "test-client", redirectPort: 0), transport: tokens, now: { clock.now }),
            now: { clock.now }
        )
    }
}

@Suite("PDT credential storage and redaction")
struct PDTCredentialStorageTests {
    @Test("The dev file store round-trips with mode 0600, keeps only the generation after a disconnect, and deletes the file when emptied")
    func fileStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePDTCredentialStore(url: directory.appending(path: "nested/pdt.json"))
        let stored = PDTStoredConnection(
            .connected(.browserSession(session("access-1", "refresh-1", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))),
            generation: 1
        )

        #expect(try store.load() == .empty)
        try store.save(stored)
        #expect(try store.load() == stored)
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try store.save(PDTStoredConnection(.disconnected, generation: 2))
        #expect(try String(contentsOf: store.url, encoding: .utf8) == #"{"disconnected":{},"generation":2}"#)
        #expect(try store.load() == PDTStoredConnection(.disconnected, generation: 2))
        try store.save(.empty)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        try store.save(.empty)
    }

    @Test("Stored data from before generations reads as generation 0, and a build from before them reads what is stored now")
    func storedFormatAcrossBuilds() throws {
        let before = JSONDecoder()
        before.dateDecodingStrategy = .iso8601
        let beforeWriter = JSONEncoder()
        beforeWriter.dateEncodingStrategy = .iso8601
        beforeWriter.outputFormatting = [.sortedKeys]
        let states: [(PDTConnectionState, writtenBefore: String)] = [
            (.connected(.personalToken(PDTAPIToken("pdt_stored"))), #"{"connected":{"_0":{"personalToken":{"_0":"pdt_stored"}}}}"#),
            (
                .connected(.browserSession(session("access-1", "refresh-1", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))),
                #"{"connected":{"_0":{"browserSession":{"_0":{"accessExpiresAt":"2027-01-15T08:00:00Z","accessToken":"access-1","refreshToken":"refresh-1"}}}}}"#
            ),
            (.needsReconnect(.personalToken, .tokenRejected(reason: "revoked")), #"{"needsReconnect":{"_0":"personalToken","_1":{"tokenRejected":{"reason":"revoked"}}}}"#),
        ]
        for (state, writtenBefore) in states {
            #expect(try String(decoding: beforeWriter.encode(state), as: UTF8.self) == writtenBefore)
            #expect(try PDTStoredConnection(storedData: Data(writtenBefore.utf8)) == PDTStoredConnection(state))

            let now = try PDTStoredConnection(state, generation: 3).storedData()
            #expect(try PDTStoredConnection(storedData: now) == PDTStoredConnection(state, generation: 3))
            #expect(try before.decode(PDTConnectionState.self, from: now) == state)
        }
        #expect(try before.decode(PDTConnectionState.self, from: Data(#"{"disconnected":{},"generation":2}"#.utf8)) == .disconnected)
    }

    @Test("A disconnect leaves no secret behind: the file or Keychain item then holds the generation alone", arguments: [false, true])
    func disconnectLeavesNoSecret(inKeychain: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-disconnect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = FakeSecItems()
        let store: any PDTCredentialStore = inKeychain
            ? KeychainPDTCredentialStore(lockDirectory: directory, secItem: keychain.api)
            : FilePDTCredentialStore(url: directory.appending(path: "pdt.json"))
        let connection = PDTConnection(store: store, tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])))

        try connection.signedIn(session("access-1", "refresh-1", expiresAt: .distantFuture))
        try connection.disconnect()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
        let left = (files + [keychain.item].compactMap { $0 }).map { String(decoding: $0, as: UTF8.self) }.filter { !$0.isEmpty }
        #expect(left == [#"{"disconnected":{},"generation":2}"#])
    }

    @Test("The dev file store finishes short and interrupted writes and never reports a zero-byte write as success")
    func fileStoreWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "pdt.json")
        let stored = PDTStoredConnection(.connected(.browserSession(
            session("access-1", "refresh-1", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        )))
        let calls = Counter()
        let choppy = FilePDTCredentialStore(url: url) { descriptor, bytes, count in
            calls.increment()
            if calls.value % 2 == 1 {
                errno = EINTR
                return -1
            }
            return Darwin.write(descriptor, bytes, min(count, 7))
        }

        try choppy.save(stored)
        #expect(try FilePDTCredentialStore(url: url).load() == stored)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)

        let stalled = FilePDTCredentialStore(url: url) { _, _, _ in 0 }
        #expect(throws: PDTCredentialStoreError.writeFailed(code: EIO)) {
            try stalled.save(PDTStoredConnection(.connected(.personalToken(PDTAPIToken("pdt_other")))))
        }
        #expect(try FilePDTCredentialStore(url: url).load() == stored)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "pdt.json" }.isEmpty)
    }

    @Test("The Keychain store keeps one device-only item in the data protection keychain, with only the generation in it after a disconnect")
    func keychainQueries() throws {
        let keychain = FakeSecItems()
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-keychain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeychainPDTCredentialStore(lockDirectory: directory, secItem: keychain.api)
        let stored = PDTStoredConnection(.connected(.personalToken(PDTAPIToken("pdt_keychain"))), generation: 1)
        let disconnected = PDTStoredConnection(.disconnected, generation: 2)

        #expect(try store.load() == .empty)
        try store.save(stored)
        try store.save(stored)
        #expect(try store.load() == stored)
        try store.save(disconnected)
        #expect(try store.load() == disconnected)
        try store.save(.empty)
        #expect(try store.load() == .empty)

        let queries = keychain.queries
        #expect(queries.count == 9)
        for query in queries {
            #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
            #expect(query[kSecAttrService as String] as? String == KeychainPDTCredentialStore.service)
        }
        #expect(keychain.added.map { $0[kSecAttrAccessible as String] as? String } == [kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String])
    }

    @Test("An unentitled build fails with the missing-entitlement error and never retries outside the data protection keychain")
    func keychainMissingEntitlement() throws {
        let keychain = FakeSecItems(status: errSecMissingEntitlement)
        let directory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-keychain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeychainPDTCredentialStore(lockDirectory: directory, secItem: keychain.api)

        #expect(throws: PDTCredentialStoreError.missingKeychainEntitlement) { try store.load() }
        #expect(throws: PDTCredentialStoreError.missingKeychainEntitlement) {
            try store.save(PDTStoredConnection(.connected(.personalToken(PDTAPIToken("pdt_keychain")))))
        }
        #expect(throws: PDTCredentialStoreError.missingKeychainEntitlement) { try store.save(.empty) }
        let connection = PDTConnection(store: store, tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])))
        #expect(throws: PDTCredentialStoreError.missingKeychainEntitlement) { try connection.state() }

        #expect(keychain.queries.count == 4)
        #expect(keychain.queries.allSatisfy { $0[kSecUseDataProtectionKeychain as String] as? Bool == true })
        #expect(keychain.added.isEmpty)
    }

    @Test("Tokens, sessions, states, and fingerprints never print a secret")
    func secretFreeDescriptions() throws {
        let secrets = ["access-secret-value", "refresh-secret-value", "pdt_personal-secret"]
        let browser = session(secrets[0], secrets[1], expiresAt: Date())
        let values: [Any] = [
            PDTAPIToken(secrets[0]),
            PDTRefreshToken(secrets[1]),
            browser,
            PDTCredential.browserSession(browser),
            PDTConnectionState.connected(.browserSession(browser)),
            PDTConnectionState.connected(.personalToken(PDTAPIToken(secrets[2]))),
            PDTConnectionState.needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken(secrets[1]).fingerprint)),
            PDTConnectionEvent.signedIn(browser),
            PDTAPIToken(secrets[0]).fingerprint,
        ]
        for value in values {
            var dumped = ""
            dump(value, to: &dumped)
            for text in [String(describing: value), String(reflecting: value), dumped] {
                #expect(secrets.allSatisfy { !text.contains($0) }, "leaked through \(type(of: value))")
            }
        }
        #expect(PDTAPIToken(secrets[0]).fingerprint.description.hasPrefix("sha256:"))
        #expect(PDTAPIToken(secrets[0]).fingerprint.length == secrets[0].count)
    }
}

private var ok: ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(#"{"data":{}}"#.utf8))
}

private func tokenReply(access: String, refresh: String, expiresIn: Int = 3600) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 200,
        body: Data(#"{"access_token":"\#(access)","expires_in":\#(expiresIn),"refresh_token":"\#(refresh)","token_type":"Bearer"}"#.utf8)
    )
}

private func oauthError(_ status: Int, _ error: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: status, body: Data(#"{"error":"\#(error)","error_description":"d"}"#.utf8))
}

private func tokenInvalid(_ reason: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 401,
        body: Data(#"{"error":{"code":"TOKEN_INVALID","message":"m","details":{"reason":"\#(reason)"},"traceId":"t"}}"#.utf8)
    )
}

private func session(_ access: String, _ refresh: String, expiresAt: Date) -> PDTBrowserSession {
    PDTBrowserSession(accessToken: PDTAPIToken(access), refreshToken: PDTRefreshToken(refresh), accessExpiresAt: expiresAt)
}

private func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private func formItems(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    return queryItems(URL(string: "x:?\(body)")!)
}

private func base64URLSHA256(_ value: String) -> String {
    Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

private final class FakeBrowser: @unchecked Sendable {
    private let lock = NSLock()
    private let callbacks: (@Sendable (_ state: String) -> [String])?
    private var opened: URL?
    private var statuses: [Int?] = []

    init(callbacks: (@Sendable (_ state: String) -> [String])?) {
        self.callbacks = callbacks
    }

    convenience init(respond: (@Sendable ([String: String]) -> [String: String])?) {
        guard let respond else {
            self.init(callbacks: nil)
            return
        }
        self.init(callbacks: { state in
            let parameters = ["state": state].merging(respond([:])) { _, override in override }
            var query = URLComponents()
            query.queryItems = parameters.map { URLQueryItem(name: $0, value: $1) }
            return [query.percentEncodedQuery ?? ""]
        })
    }

    var authorizeURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    func waitForCallbackStatus() -> Int? {
        waitForCallbackStatuses(count: 1).first ?? nil
    }

    func waitForCallbackStatuses(count: Int) -> [Int?] {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            lock.lock()
            let current = statuses
            lock.unlock()
            if current.count >= count {
                return current
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return []
    }

    func open(_ url: URL) throws {
        lock.lock()
        opened = url
        lock.unlock()
        guard let callbacks else {
            return
        }
        let query = queryItems(url)
        let urls = callbacks(query["state"]!).map { URL(string: query["redirect_uri"]! + "?" + $0)! }
        DispatchQueue.global().async {
            for callbackURL in urls {
                let result = Self.get(callbackURL)
                self.lock.lock()
                self.statuses.append(result)
                self.lock.unlock()
            }
        }
    }

    static func get(_ url: URL) -> Int? {
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: url) { _, response, _ in
            result.status = (response as? HTTPURLResponse)?.statusCode
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        session.invalidateAndCancel()
        return result.status
    }

    private final class Box: @unchecked Sendable {
        var status: Int?
    }
}

private struct PortHolder {
    let descriptor: Int32
    let port: UInt16

    init() throws {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, length) == 0 && listen(socketDescriptor, 1) == 0
            }
        }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketDescriptor, $0, &length) == 0 }
        }
        guard bound, named else {
            Darwin.close(socketDescriptor)
            throw POSIXError(.EADDRNOTAVAIL)
        }
        descriptor = socketDescriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    func close() {
        Darwin.close(descriptor)
    }
}

private let testNow = Date(timeIntervalSince1970: 1_800_000_000)

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = testNow

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Result<PDTAPIToken, Error>] = []

    func record(_ result: Result<PDTAPIToken, Error>) {
        lock.lock()
        recorded.append(result)
        lock.unlock()
    }

    var values: [Result<PDTAPIToken, Error>] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class FailingSaveStore: PDTCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private let backing: InMemoryPDTCredentialStore
    private var failures: Int
    /// A failed save lands anyway, and the store cannot be read until `recover()`.
    private let failedSavesLandUnreadable: Bool
    private var unreadable = false

    init(_ state: PDTConnectionState, failures: Int, failedSavesLandUnreadable: Bool = false) {
        backing = InMemoryPDTCredentialStore(state)
        self.failures = failures
        self.failedSavesLandUnreadable = failedSavesLandUnreadable
    }

    var persistence: PDTCredentialPersistence { backing.persistence }

    func load() throws -> PDTStoredConnection {
        lock.lock()
        let unreadable = unreadable
        lock.unlock()
        if unreadable {
            throw PDTCredentialStoreError.unreadable
        }
        return try backing.load()
    }

    /// Ends the failures early: the store takes writes again.
    func recover() {
        lock.lock()
        failures = 0
        unreadable = false
        lock.unlock()
    }

    func save(_ connection: PDTStoredConnection) throws {
        lock.lock()
        defer { lock.unlock() }
        guard failures == 0 else {
            failures -= 1
            if failedSavesLandUnreadable {
                try backing.save(connection)
                unreadable = true
            }
            throw PDTCredentialStoreError.writeFailed(code: EIO)
        }
        try backing.save(connection)
    }

    func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try backing.withExclusiveAccess(body)
    }
}

/// A store whose exclusive access excludes nothing, like two processes whose
/// lock files do not meet. Only the transition rules protect the pair.
private final class UnlockedStore: PDTCredentialStore, @unchecked Sendable {
    private let backing: InMemoryPDTCredentialStore

    init(_ state: PDTConnectionState) {
        backing = InMemoryPDTCredentialStore(state)
    }

    var persistence: PDTCredentialPersistence { backing.persistence }

    func load() throws -> PDTStoredConnection {
        try backing.load()
    }

    func save(_ connection: PDTStoredConnection) throws {
        try backing.save(connection)
    }

    func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try body()
    }
}

/// The first caller gets the first reply after its delay, even when a later
/// caller is answered first.
private final class ArrivalOrderTransport: PDTHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let replies: [(delay: TimeInterval, reply: ScriptedPDTHTTPTransport.Reply)]
    private var recorded: [URLRequest] = []

    init(_ replies: [(TimeInterval, ScriptedPDTHTTPTransport.Reply)]) {
        self.replies = replies.map { (delay: $0.0, reply: $0.1) }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        lock.lock()
        let arrival = recorded.count
        recorded.append(request)
        lock.unlock()
        guard arrival < replies.count else {
            throw URLError(.resourceUnavailable)
        }
        Thread.sleep(forTimeInterval: replies[arrival].delay)
        return try ScriptedPDTHTTPTransport([replies[arrival].reply]).send(request, cancellation: cancellation)
    }
}

private final class HookTransport: PDTHTTPTransport, @unchecked Sendable {
    private let scripted: ScriptedPDTHTTPTransport
    private let lock = NSLock()
    private var hook: (() -> Void)?

    init(replies: [ScriptedPDTHTTPTransport.Reply], beforeReply: @escaping () -> Void) {
        scripted = ScriptedPDTHTTPTransport(replies)
        hook = beforeReply
    }

    convenience init(reply: ScriptedPDTHTTPTransport.Reply, beforeReply: @escaping () -> Void) {
        self.init(replies: [reply], beforeReply: beforeReply)
    }

    var requests: [URLRequest] { scripted.requests }

    func send(_ request: URLRequest, cancellation: PDTCancellation?) throws -> (Data, HTTPURLResponse) {
        lock.lock()
        let pending = hook
        hook = nil
        lock.unlock()
        pending?()
        return try scripted.send(request, cancellation: cancellation)
    }
}

private final class FakeSecItems: @unchecked Sendable {
    private let lock = NSLock()
    private let forcedStatus: OSStatus?
    private(set) var item: Data?
    private(set) var queries: [[String: Any]] = []
    private(set) var added: [[String: Any]] = []

    var api: KeychainPDTCredentialStore.SecItemAPI {
        KeychainPDTCredentialStore.SecItemAPI(
            copyMatching: { query, result in
                self.record(query) {
                    guard let item = self.item else { return errSecItemNotFound }
                    result?.pointee = item as CFData
                    return errSecSuccess
                }
            },
            add: { query in
                self.record(query) {
                    let attributes = query as NSDictionary as! [String: Any]
                    self.added.append(attributes)
                    self.item = attributes[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            update: { query, changes in
                self.record(query) {
                    guard self.item != nil else { return errSecItemNotFound }
                    self.item = (changes as NSDictionary)[kSecValueData as String] as? Data
                    return errSecSuccess
                }
            },
            delete: { query in
                self.record(query) {
                    guard self.item != nil else { return errSecItemNotFound }
                    self.item = nil
                    return errSecSuccess
                }
            },
            isEntitled: forcedStatus != errSecMissingEntitlement
        )
    }

    /// `status` answers every call instead of the in-memory item.
    init(status: OSStatus? = nil) {
        forcedStatus = status
    }

    private func record(_ query: CFDictionary, _ body: () -> OSStatus) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        queries.append(query as NSDictionary as! [String: Any])
        return forcedStatus ?? body()
    }
}
