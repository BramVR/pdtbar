import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("PDT sync failure states")
struct SyncFailureStatesTests {
    @Test(
        "A failed first fetch names the typed failure and its next action",
        arguments: [
            (PDTAPIError.rateLimited(retryAfter: 120), "PDT rate limit; try again in 2 min"),
            (.rateLimited(retryAfter: nil), "PDT rate limit; try again later"),
            (.transport(code: URLError.notConnectedToInternet.rawValue), "Could not reach PDT; check your connection"),
            (.server(status: 503, retryAfter: nil), "PDT server problem; try again later"),
        ]
    )
    func firstFetchFailureNamesTheFailure(error: PDTAPIError, detail: String) {
        let runtime = PDTLaunchRuntime()
        _ = connectedLaunch(runtime)

        let failed = runtime.completeFirstFetch(.failed(
            .unavailable(.saved),
            failure: PDTSyncFailure(error, resource: .holdings(), phase: .baseHoldings)
        ))

        #expect(failed.state == .connected(.failed, .saved))
        #expect(failed.descriptor.statusTitle == "Could not fetch portfolio")
        let row = failed.descriptor.sections.flatMap(\.rows).first { $0.id == "portfolioFetch.failed" }
        #expect(row?.title == "Could not fetch portfolio")
        #expect(row?.detail == detail)
        #expect(rowTitles(in: failed.descriptor) == ["Could not fetch portfolio", "Try again", "Disconnect from PDT"])
    }

    @Test("A first fetch PDT rate-limits past the client's retries names the wait, end to end, and writes no snapshot")
    func firstFetchRateLimitEndToEnd() throws {
        let snapshots = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-191-first-fetch")
        defer { try? FileManager.default.removeItem(at: snapshots.directory) }
        let connection = appConnection(replies: [rateLimited(retryAfter: "120")])
        let runtime = PDTLaunchRuntime()
        _ = connectedLaunch(runtime)

        let failed = runtime.completeFirstFetch(runFirstFetch(connection, snapshots: snapshots))

        #expect(failed.state == .connected(.failed, .saved))
        #expect(failed.descriptor.sections.flatMap(\.rows).first { $0.id == "portfolioFetch.failed" }?.detail
            == "PDT rate limit; try again in 2 min")
        #expect(!FileManager.default.fileExists(atPath: snapshots.currentSnapshotPath.path))
        #expect(snapshots.lastSyncFailure()?.traceID?.value == traceID)
        #expect(snapshots.lastSyncFailure()?.requestCount == 1)
    }

    @Test("The retry of a failed first fetch drops the old failure while it runs")
    func firstFetchRetryDropsOldFailure() throws {
        let runtime = PDTLaunchRuntime()
        _ = connectedLaunch(runtime)
        _ = runtime.completeFirstFetch(.failed(.unavailable(.saved), failure: PDTSyncFailure(
            PDTAPIError.server(status: 503, retryAfter: nil), resource: .holdings(), phase: .baseHoldings
        )))

        let retry = try #require(runtime.retryFirstFetch())
        let failedWithoutRecord = runtime.completeFirstFetch(.failed(.unavailable(.saved)))

        #expect(rowTitles(in: retry.descriptor) == ["Fetching portfolio"])
        #expect(failedWithoutRecord.descriptor.sections.flatMap(\.rows).first { $0.id == "portfolioFetch.failed" }?.detail
            == "No partial pulse published")
    }

    @Test(
        "An optional phase that loses access moves the menu to that connection state over the committed pulse",
        arguments: [
            (401, "TOKEN_INVALID", PDTLaunchState.needsReconnect(.personalToken, .tokenRevoked), "Reconnect to PDT"),
            (403, "INSUFFICIENT_SCOPE", .needsReconnect(.personalToken, .readAccessMissing), "Reconnect to PDT"),
            (403, "API_ACCESS_PAUSED", .subscriptionPaused, "PDT access paused"),
        ]
    )
    func optionalPhaseAccessLoss(status: Int, code: String, state: PDTLaunchState, title: String) throws {
        let reply = apiError(status, code, details: #"{"reason":"revoked"}"#)
        let run = try backgroundRefresh(replies: [try holdingsReply(), reply])
        defer { try? FileManager.default.removeItem(at: run.snapshots.directory) }

        #expect(run.update.state == state)
        #expect(run.runtime.currentPulse?.source == .refreshedSnapshot)
        #expect(run.update.descriptor.sections.first?.id == "pdtConnection")
        #expect(run.update.descriptor.sections.first?.rows.first?.title == title)
        #expect(!rowTitles(in: run.update.descriptor).contains("Connected to PDT"))
        #expect(!rowTitles(in: run.update.descriptor).contains("Details partially filled"))
        #expect(healthDetail("access", in: run.update.descriptor)?.hasPrefix("Connected") == false)
        #expect(try copiedDiagnostics(run.update.descriptor).contains("step: allocation"))
        #expect(try copiedDiagnostics(run.update.descriptor).contains("trace: \(traceID)"))
        #expect(try run.snapshots.loadPriorSnapshotResult().snapshot?.asOf == "2026-06-22")
    }

    @Test(
        "An optional phase failure that keeps access stays a connected, partly filled pulse",
        arguments: [403, 429]
    )
    func optionalPhaseFailureKeepsConnection(status: Int) throws {
        let reply = status == 429 ? rateLimited(retryAfter: "120") : apiError(403, "FORBIDDEN")
        let run = try backgroundRefresh(replies: [try holdingsReply(), reply])
        defer { try? FileManager.default.removeItem(at: run.snapshots.directory) }

        #expect(run.update.state == .connected(.current, .saved))
        #expect(rowTitles(in: run.update.descriptor).contains("Details partially filled"))
    }

    @Test("A base-phase 401 keeps its failure record on the reconnect screen and through Check again, and commits no snapshot")
    func basePhaseAccessLossKeepsRecord() throws {
        let run = try backgroundRefresh(replies: [apiError(401, "TOKEN_INVALID", details: #"{"reason":"expired"}"#)])
        defer { try? FileManager.default.removeItem(at: run.snapshots.directory) }

        #expect(run.update.state == .needsReconnect(.personalToken, .tokenExpired))
        #expect(run.runtime.currentPulse?.source == .cachedSnapshot)
        #expect(try run.snapshots.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
        let copied = try copiedDiagnostics(run.update.descriptor)
        #expect(copied.contains("step: base holdings"))
        #expect(copied.contains("failure: reconnect needed (HTTP 401 or no stored credential)"))
        #expect(copied.contains("trace: \(traceID)"))

        _ = try #require(run.runtime.checkAgain())
        let stillBroken = run.runtime.completeConnection(
            PDTConnectionOutcome(.needsReconnect(.personalToken, .tokenExpired)),
            for: run.runtime.connectionAttempt
        )
        #expect(try copiedDiagnostics(stillBroken.descriptor).contains("trace: \(traceID)"))

        _ = try #require(run.runtime.checkAgain())
        let refreshing = run.runtime.completeConnection(PDTConnectionOutcome(.connected(.saved)), for: run.runtime.connectionAttempt)
        #expect(refreshing.effect == .startBackgroundDetailRefresh)
        #expect(diagnosticsRow(in: refreshing.descriptor)?.children.isEmpty != false)
    }

    @Test("A base-phase pause keeps its record on the paused screen")
    func basePhasePauseKeepsRecord() throws {
        let run = try backgroundRefresh(replies: [apiError(403, "API_ACCESS_PAUSED")])
        defer { try? FileManager.default.removeItem(at: run.snapshots.directory) }

        #expect(run.update.state == .subscriptionPaused)
        #expect(try copiedDiagnostics(run.update.descriptor).contains("failure: access paused (HTTP 403)"))
        #expect(try run.snapshots.loadPriorSnapshotResult().snapshot?.asOf == seededAsOf)
    }
}

private let seededAsOf = "2026-06-21"
private let traceID = "6f1c2f0e-8a3b-4c1d-9e2f-0a1b2c3d4e5f"
private let personalToken = PDTConnectionState.connected(.personalToken(PDTAPIToken("pdt_stored")))

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private struct BackgroundRun {
    var runtime: PDTLaunchRuntime
    var update: PDTOnboardingUpdate
    var snapshots: SnapshotStore
}

/// Seeds a saved snapshot, launches over it, and runs the refresh the way
/// `AppDelegate.startBackgroundPortfolioRefresh` does: a thrown error and the
/// store's record, or a committed result and what its last failure means for access.
private func backgroundRefresh(replies: [ScriptedPDTHTTPTransport.Reply]) throws -> BackgroundRun {
    let snapshots = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-191-background")
    let seed = appConnection(replies: try fullBackgroundReplies())
    _ = try PDTAPIBackgroundDetailRefresh(client: seed.apiClient(), snapshotStore: snapshots, asOf: seededAsOf).refresh()
    let cached = try #require(try PressureRunner.cachedPulse(snapshotStore: snapshots, today: "2026-06-22"))

    let runtime = PDTLaunchRuntime()
    _ = runtime.launch()
    _ = runtime.completeCachedPulseLoad(cached)
    let start = runtime.completeConnection(PDTConnectionOutcome(.connected(.saved)), for: runtime.connectionAttempt)
    #expect(start.effect == .startBackgroundDetailRefresh)

    let connection = appConnection(replies: replies)
    let refresh = PDTAPIBackgroundDetailRefresh(client: connection.apiClient(), snapshotStore: snapshots, asOf: "2026-06-22")
    let result: PDTLaunchBackgroundDetailRefreshResult
    do {
        let refreshed = try refresh.refresh()
        var status = PDTConnectionStatus.connected(.saved)
        if let ending = refreshed.failures.last, case let .connection(lost) = connection.failure(for: ending.kind) {
            status = lost
        }
        result = .succeeded(refreshed.pulse, outcome: refreshed.outcome, connection: status)
    } catch {
        result = .failed(connection.failure(for: error), failure: snapshots.lastSyncFailure())
    }
    return BackgroundRun(runtime: runtime, update: runtime.completeBackgroundDetailRefresh(result), snapshots: snapshots)
}

private func appConnection(replies: [ScriptedPDTHTTPTransport.Reply]) -> PDTAppConnection {
    PDTAppConnection(
        store: InMemoryPDTCredentialStore(personalToken),
        tokenEndpoint: PDTTokenEndpoint(transport: ScriptedPDTHTTPTransport([])),
        apiTransport: ScriptedPDTHTTPTransport(replies),
        signIn: { _ in throw PDTSignInError.accessDenied }
    )
}

/// What the app does for `.startFirstFetch`.
private func runFirstFetch(_ connection: PDTAppConnection, snapshots: SnapshotStore) -> PDTLaunchFetchResult {
    snapshots.setLastSyncFailure(nil)
    do {
        let pulse = try PDTCoalescedFirstPortfolioFetch(
            dataSource: PDTAPIDataSource(
                client: connection.apiClient(),
                options: .firstFetch,
                onSyncFailure: { snapshots.setLastSyncFailure($0) }
            ),
            snapshotStore: snapshots,
            asOf: "2026-06-22"
        ).fetch()
        return .succeeded(pulse, connection: connection.status(afterSyncEnding: nil))
    } catch {
        return .failed(connection.failure(for: error), failure: snapshots.lastSyncFailure())
    }
}

private func connectedLaunch(_ runtime: PDTLaunchRuntime) -> PDTOnboardingUpdate {
    _ = runtime.launch()
    _ = runtime.completeCachedPulseLoad(nil)
    return runtime.completeConnection(PDTConnectionOutcome(.connected(.saved)), for: runtime.connectionAttempt)
}

private func fullBackgroundReplies() throws -> [ScriptedPDTHTTPTransport.Reply] {
    let directory = packageRoot.appending(path: "docs/pdt/fixtures/api/full")
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("symbol-quotes") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { .response(status: 200, body: try Data(contentsOf: $0)) }
}

private func holdingsReply() throws -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: try Data(contentsOf: packageRoot.appending(path: "docs/pdt/fixtures/api/full/01-holdings.json")))
}

private func apiError(_ status: Int, _ code: String, details: String = "{}") -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: status,
        body: Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details),"traceId":"\#(traceID)"}}"#.utf8)
    )
}

private func rateLimited(retryAfter: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(
        status: 429,
        body: Data(#"{"error":{"code":"RATE_LIMITED","message":"m","details":{},"traceId":"\#(traceID)"}}"#.utf8),
        headers: ["Retry-After": retryAfter]
    )
}

private func rowTitles(in descriptor: MenuDescriptor) -> [String] {
    descriptor.sections.flatMap(\.rows).map(\.title)
}

private func healthRow(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections.first { $0.id == "freshness" }?.rows.first { $0.id == "dataHealth" }
}

private func healthDetail(_ row: String, in descriptor: MenuDescriptor) -> String? {
    healthRow(in: descriptor)?.children.first { $0.id == "dataHealth.\(row)" }?.detail
}

private func diagnosticsRow(in descriptor: MenuDescriptor) -> MenuRow? {
    healthRow(in: descriptor)?.children.first { $0.id == "dataHealth.diagnostic" }
}

private func copiedDiagnostics(_ descriptor: MenuDescriptor) throws -> String {
    let copy = try #require(diagnosticsRow(in: descriptor)?.children.first { $0.id == "dataHealth.diagnostic.copy" })
    return try #require(copy.actionTarget?.copyText)
}
