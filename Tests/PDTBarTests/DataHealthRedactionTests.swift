import Foundation
import Testing
import PDTBarCore

@Suite("Data health redaction")
struct DataHealthRedactionTests {
    @Test(
        "Nothing a failed PDT request carried reaches the stored failure, Data health, or the copied diagnostics",
        arguments: FailedRequest.allCases, FailedStep.allCases
    )
    func failedRequestLeaksNothing(request: FailedRequest, step: FailedStep) throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = syncReplies()
        replies[step.replyIndex] = request.reply

        let result = try? refresh(replies, store: store).refresh(cancellation: nil, progress: { _ in })

        #expect((result == nil) == (step == .baseHoldings))
        let failure = try #require(store.lastSyncFailure())
        #expect(failure.kind == request.kind)
        #expect(failure.phase == step.phase)
        #expect(failure.endpoint == step.endpoint)
        #expect(failure.traceID == nil)

        let shown = try shownHealth(result: result, store: store, failure: failure)
        let written: [(String, String)] = [
            ("stored failure", try storedFailureText(in: store)),
            ("dataHealth JSON", String(decoding: try stableJSONData(shown.health), as: UTF8.self)),
            ("Data health rows", allText(in: shown.row)),
            ("copied diagnostics", try #require(copiedDiagnostics(in: shown.row))),
        ]
        for (name, text) in written {
            for secret in Planted.all {
                #expect(!text.contains(secret), "\(name) leaked \(secret)")
            }
            #expect(!text.contains("SENTINEL"), "\(name)")
        }
    }

    @Test(
        "A trace id PDT sends in a trace-shaped form survives to storage, Data health, and the copied diagnostics",
        arguments: [
            (["X-Request-Id": "6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f"], "not-a-trace", "6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f"),
            ([:], "0123456789abcdef0123456789ABCDEF", "0123456789abcdef0123456789ABCDEF"),
            (["X-Request-Id": Planted.token], "0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef"),
        ]
    )
    func traceShapedIDSurvives(headers: [String: String], bodyTraceID: String, expected: String) throws {
        let store = try seededStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var replies = syncReplies()
        replies[FailedStep.allocation.replyIndex] = .response(
            status: 503,
            body: Data(#"{"error":{"code":"SERVER_ERROR","message":"m","details":{},"traceId":"\#(bodyTraceID)"}}"#.utf8),
            headers: headers
        )

        let result = try refresh(replies, store: store).refresh(cancellation: nil, progress: { _ in })

        let failure = try #require(store.lastSyncFailure())
        #expect(failure.traceID?.value == expected)
        let shown = try shownHealth(result: result, store: store, failure: failure)
        #expect(try storedFailureText(in: store).contains(expected))
        #expect(String(decoding: try stableJSONData(shown.health), as: UTF8.self).contains(expected))
        #expect(copiedDiagnostics(in: shown.row)?.contains("trace: \(expected)") == true)
    }

    @Test(
        "Only a canonical UUID or 32 hex digits is a trace id",
        arguments: [
            ("6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f", true),
            ("6F1C2F0E-8A3B-4C1D-9E2F-0A1B2C3D4E5F", true),
            ("0123456789abcdef0123456789abcdef", true),
            ("", false),
            ("6f1c2f0e8a3b-4c1d-9e2f-0a1b2c3d4e5f-", false),
            ("6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5g", false),
            ("0123456789abcdef0123456789abcde", false),
            ("０１２３４５６７８９abcdef0123456789abcdef", false),
            (Planted.token, false),
            (Planted.url, false),
            ("user@example.com", false),
        ]
    )
    func traceIDShape(raw: String, accepted: Bool) throws {
        #expect((PDTTraceID(raw) != nil) == accepted)
        let decoded = try? JSONDecoder().decode(PDTTraceID.self, from: JSONEncoder().encode(raw))
        #expect((decoded != nil) == accepted)
    }

    @Test("A sync failure stores no text, URL, bytes, or error outside its trace id")
    func syncFailureStoresNoFreeText() {
        #expect(Set(everyKind.map(ordinal)).count == everyKind.count)
        for kind in everyKind {
            let failure = PDTSyncFailure(
                phase: .priceHistory,
                endpoint: .pricesBatch,
                kind: kind,
                requestCount: 2,
                traceID: PDTTraceID("6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f")
            )
            #expect(freeTextProperties(in: failure, path: "PDTSyncFailure") == [], "\(kind)")
        }

        struct Probe {
            var note = "text"
            var link = URL(string: "https://example.com")
            var bytes = Data([1])
            var cause: any Error = PDTAPIError.cancelled
            var count = 1
        }
        #expect(freeTextProperties(in: Probe(), path: "Probe") == ["Probe.note", "Probe.link", "Probe.bytes", "Probe.cause"])
    }

    @Test(
        "Every PDT error maps to one failure kind, and its menu copy says what to do",
        arguments: [
            (PDTAPIError.missingToken as any Error, PDTSyncFailure.Kind.reconnect, "reconnect"),
            (PDTAPIError.unauthenticated, .reconnect, "reconnect"),
            (PDTAPIError.tokenInvalid(reason: "expired"), .reconnect, "reconnect"),
            (PDTAPIError.insufficientScope, .readAccessMissing, "reconnect"),
            (PDTAPIError.apiAccessPaused, .accessPaused, "renew your subscription"),
            (PDTAPIError.forbidden, .forbidden, "reconnect"),
            (PDTAPIError.rateLimited(retryAfter: 120), .rateLimited(retryAfterSeconds: 120), "try again in 2 min"),
            (PDTAPIError.rateLimited(retryAfter: 61), .rateLimited(retryAfterSeconds: 61), "try again in 2 min"),
            (PDTAPIError.rateLimited(retryAfter: 7200), .rateLimited(retryAfterSeconds: 7200), "try again in 2 h"),
            (PDTAPIError.rateLimited(retryAfter: 9_999_999), .rateLimited(retryAfterSeconds: 86400), "try again in 24 h"),
            (PDTAPIError.rateLimited(retryAfter: nil), .rateLimited(retryAfterSeconds: nil), "try again later"),
            (PDTAPIError.transport(code: -1009), .network(urlErrorCode: -1009), "check your connection"),
            (PDTAPIError.server(status: 503, retryAfter: 5), .server(status: 503), "try again later"),
            (PDTAPIError.invalidResponse, .unreadableResponse, "update PDTBar"),
            (PDTAPIError.paginationStalled, .unreadableResponse, "update PDTBar"),
            (PDTAPIError.paginationLimitExceeded, .unreadableResponse, "update PDTBar"),
            (PDTAPIError.notFound, .unexpected(status: 404), "update PDTBar"),
            (PDTAPIError.validationFailed, .unexpected(status: 422), "update PDTBar"),
            (PDTAPIError.unexpectedStatus(418), .unexpected(status: 418), "update PDTBar"),
            (PDTAPIError.invalidRequest, .unexpected(status: nil), "update PDTBar"),
            (PDTAPIError.cancelled, .cancelled, "try again"),
            (PDTCredentialStoreError.keychain(status: -25300), .credentialStore, "try again"),
            (CocoaError(.fileReadUnknown), .unexpected(status: nil), "update PDTBar"),
        ]
    )
    func errorMapsToActionableKind(error: any Error, kind: PDTSyncFailure.Kind, action: String) {
        let failure = PDTSyncFailure(error, resource: .dividends(), phase: .income)

        #expect(failure.kind == kind)
        #expect(failure.endpoint == .dividends)
        #expect(failure.menuDetail.hasPrefix("Income: "))
        #expect(failure.menuDetail.hasSuffix("; \(action)"))
    }
}

/// Values a PDT answer could echo back. None may leave the client.
private enum Planted {
    static let token = "pdt_SENTINEL_TOKEN_0123456789abcdef0123456789abcdef"
    static let accountID = "acct-SENTINEL-4242"
    static let url = "https://api.portfoliodividendtracker.com/v1/accounts/acct-SENTINEL-4242/holdings?token=pdt_SENTINEL_TOKEN_0123456789abcdef0123456789abcdef"
    static let body = "RAW_BODY_SENTINEL"

    static let all = [token, accountID, url, body]
}

enum FailedRequest: String, CaseIterable, Sendable {
    case tokenInvalid, insufficientScope, accessPaused, otherForbidden, rateLimited, serverError, noAnswer, undecodable

    var reply: ScriptedPDTHTTPTransport.Reply {
        switch self {
        case .tokenInvalid: plantedError(401, "TOKEN_INVALID")
        case .insufficientScope: plantedError(403, "INSUFFICIENT_SCOPE")
        case .accessPaused: plantedError(403, "API_ACCESS_PAUSED")
        case .otherForbidden: plantedError(403, Planted.body)
        case .rateLimited: plantedError(429, "RATE_LIMITED")
        case .serverError: plantedError(503, "SERVER_ERROR")
        case .noAnswer: .failure(.notConnectedToInternet)
        case .undecodable: .response(
            status: 200,
            body: Data(#"{"data":"\#(Planted.body) \#(Planted.accountID) \#(Planted.token)"}"#.utf8),
            headers: plantedHeaders
        )
        }
    }

    var kind: PDTSyncFailure.Kind {
        switch self {
        case .tokenInvalid: .reconnect
        case .insufficientScope: .readAccessMissing
        case .accessPaused: .accessPaused
        case .otherForbidden: .forbidden
        case .rateLimited: .rateLimited(retryAfterSeconds: nil)
        case .serverError: .server(status: 503)
        case .noAnswer: .network(urlErrorCode: URLError.notConnectedToInternet.rawValue)
        case .undecodable: .unreadableResponse
        }
    }
}

/// Where in the sync the failed request sits: the required base, or an optional phase.
enum FailedStep: String, CaseIterable, Sendable {
    case baseHoldings, allocation

    var replyIndex: Int { self == .baseHoldings ? 0 : 1 }
    var phase: BackgroundDetailRefreshPhase { self == .baseHoldings ? .baseHoldings : .allocation }
    var endpoint: PDTAPIEndpoint { self == .baseHoldings ? .holdings : .distributions }
}

private let plantedHeaders = [
    "X-Request-Id": Planted.token,
    "Retry-After": Planted.accountID,
    "Authorization": "Bearer \(Planted.token)",
    "Location": Planted.url,
]

private func plantedError(_ status: Int, _ code: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: status,
        body: Data(
            #"{"error":{"code":"\#(code)","message":"\#(Planted.body) \#(Planted.accountID) \#(Planted.token)","details":{"reason":"\#(Planted.accountID)"},"traceId":"\#(Planted.url)"}}"#.utf8
        ),
        headers: plantedHeaders
    )
}

private let everyKind: [PDTSyncFailure.Kind] = [
    .reconnect, .readAccessMissing, .accessPaused, .forbidden,
    .rateLimited(retryAfterSeconds: 120), .rateLimited(retryAfterSeconds: nil),
    .network(urlErrorCode: -1009), .server(status: 503), .unreadableResponse,
    .unexpected(status: 404), .unexpected(status: nil), .credentialStore, .cancelled,
]

/// No `default`: a new kind does not compile until it is added here and to `everyKind`.
private func ordinal(_ kind: PDTSyncFailure.Kind) -> String {
    switch kind {
    case .reconnect: "reconnect"
    case .readAccessMissing: "readAccessMissing"
    case .accessPaused: "accessPaused"
    case .forbidden: "forbidden"
    case .rateLimited(nil): "rateLimited"
    case .rateLimited: "rateLimited+retryAfter"
    case .network: "network"
    case .server: "server"
    case .unreadableResponse: "unreadableResponse"
    case .unexpected(nil): "unexpected"
    case .unexpected: "unexpected+status"
    case .credentialStore: "credentialStore"
    case .cancelled: "cancelled"
    }
}

/// Paths of stored values that could hold arbitrary text. `PDTTraceID` is the
/// one allowed string, because it validates its shape.
private func freeTextProperties(in value: Any, path: String) -> [String] {
    if value is PDTTraceID {
        return []
    }
    if value is String || value is URL || value is Data || value is any Error {
        return [path]
    }
    return Mirror(reflecting: value).children.flatMap { child in
        freeTextProperties(in: child.value, path: "\(path).\(child.label ?? "_")")
    }
}

private func refresh(_ replies: [ScriptedPDTHTTPTransport.Reply], store: SnapshotStore) -> PDTAPIBackgroundDetailRefresh {
    PDTAPIBackgroundDetailRefresh(
        client: PDTAPIClient(
            transport: ScriptedPDTHTTPTransport(replies),
            tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(Planted.token)),
            policy: PDTAPIRequestPolicy(maxAttempts: 1),
            sleeper: NoSleep()
        ),
        snapshotStore: store,
        asOf: "2026-06-22"
    )
}

/// A store holding one complete sync, so a failed base still has a saved copy to show.
private func seededStore() throws -> SnapshotStore {
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-data-health-redaction-test")
    _ = try refresh(syncReplies(), store: store).refresh(cancellation: nil, progress: { _ in })
    return store
}

/// One complete sync in request order: holdings, distributions, x-ray, calendar, dividends, prices.
private func syncReplies() -> [ScriptedPDTHTTPTransport.Reply] {
    let holding = #"{"symbolName":"Holding 1","symbolQuoteId":1,"symbolId":1001,"currentPriceDate":"2026-06-22T23:59:59+00:00","portfolioWeight":"1","closedAt":null,"currentWorthLocal":{"value":"100.00","currency":"EUR"}}"#
    let emptyPage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1}}"#
    return [
        #"{"data":[\#(holding)]}"#,
        #"{"data":{"sectors":[],"assetTypes":[]}}"#,
        #"{"data":{"items":[],"hasMore":false}}"#,
        emptyPage,
        emptyPage,
        #"{"data":{"prices":[[{"date":"2026-06-22","closeAdjusted":"10.00","closeCurrency":"EUR","symbolQuoteId":1}]]}}"#,
    ].map { .response(status: 200, body: Data($0.utf8)) }
}

/// Data health as the app shows it after this sync: the degraded pulse the sync
/// returned, or the saved copy under a failed sync when the base failed.
private func shownHealth(
    result: PDTBackgroundDetailRefreshResult?,
    store: SnapshotStore,
    failure: PDTSyncFailure
) throws -> (health: DataHealthSnapshot, row: MenuRow) {
    let pulse = try result?.pulse ?? #require(try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-06-22"))
    let runtime = DataHealthRuntime(access: .connected, sync: result == nil ? .failed(failure) : .idle)
    let row = try #require(
        pulse.descriptor(in: runtime).sections.first { $0.id == "freshness" }?.rows.first { $0.id == "dataHealth" }
    )
    return (DataHealth.snapshot(pulse.model.facetSnapshots.dataHealth, in: runtime), row)
}

private func storedFailureText(in store: SnapshotStore) throws -> String {
    try String(contentsOf: store.directory.appending(path: "latest-sync-failure.json"), encoding: .utf8)
}

private func allText(in row: MenuRow) -> String {
    ([row.title, row.detail ?? "", row.actionTarget?.copyText ?? ""] + row.children.map(allText)).joined(separator: "\n")
}

private func copiedDiagnostics(in healthRow: MenuRow) -> String? {
    healthRow.children.first { $0.id == "dataHealth.diagnostic" }?.children.first?.actionTarget?.copyText
}

private struct NoSleep: PDTAPISleeper {
    func sleep(seconds _: TimeInterval, cancellation _: PDTCancellation?) throws {}
}
