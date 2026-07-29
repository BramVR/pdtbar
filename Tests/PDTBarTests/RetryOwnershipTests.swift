import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Retry ownership")
struct RetryOwnershipTests {
    @Test("Persistently transient logical call runs Claude CLI exactly 2 times")
    func persistentlyTransientLogicalCallRunsClaudeCLIExactlyTwoTimes() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
        ])
        let store = try temporaryStore("pdtbar-transient-two-run-bound-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(connection(runner: runner), store: store).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 2)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .transientFailure)
    }

    @Test("Setup-unavailable logical call is never retried by either layer")
    func setupUnavailableLogicalCallIsNeverRetriedByEitherLayer() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Error: Not logged in. Run claude auth login first.", exitCode: 1),
        ])
        let store = try temporaryStore("pdtbar-setup-no-layer-retry-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner, retryCount: 2),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(optionalRetryCount: 2)
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 1)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .setupUnavailable)
    }

    @Test("Already-passed phase deadline spawns 0 Claude CLI runs")
    func alreadyPassedPhaseDeadlineSpawnsZeroClaudeCLIRuns() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
        ])
        let store = try temporaryStore("pdtbar-passed-deadline-zero-run-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = DeadlineCrossingClock()

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(paginationTimeoutSeconds: 0.01),
                now: clock.now
            ).refresh()
        }

        #expect(readRuns(in: runner).isEmpty)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == 0)
        #expect(diagnostic.category == .timeout)
    }

    @Test("Base holdings deadline stops connector retry after 1 CLI run")
    func baseHoldingsDeadlineStopsConnectorRetryAfterOneCLIRun() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "This retry must not run", exitCode: 1),
        ])
        let store = try temporaryStore("pdtbar-base-connector-deadline-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner, retryBackoffSeconds: 0.05),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(paginationTimeoutSeconds: 0.01)
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 1)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.phase == .baseHoldings)
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .timeout)
    }

    @Test("Injected refresh clock still allows exactly 2 connector CLI runs")
    func injectedRefreshClockAllowsExactlyTwoConnectorCLIRuns() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
        ])
        let store = try temporaryStore("pdtbar-injected-clock-retry-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner),
                store: store,
                now: { Date(timeIntervalSinceReferenceDate: 0) }
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 2)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
    }

    @Test("Late successful process result is rejected after 1 CLI run")
    func lateSuccessfulProcessResultIsRejectedAfterOneCLIRun() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: connectedPDT, stderr: "", exitCode: 0),
                .init(stdout: emptyHoldingsStream, stderr: "", exitCode: 0),
            ],
            simulatedDelays: [0, 0.02],
            honorsTimeout: false
        )
        let store = try temporaryStore("pdtbar-late-success-deadline-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(paginationTimeoutSeconds: 0.01)
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 1)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .timeout)
    }

    @Test("Late failed process result reports timeout after 1 CLI run")
    func lateFailedProcessResultReportsTimeoutAfterOneCLIRun() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: connectedPDT, stderr: "", exitCode: 0),
                .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            ],
            simulatedDelays: [0, 0.02],
            honorsTimeout: false
        )
        let store = try temporaryStore("pdtbar-late-failure-deadline-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(paginationTimeoutSeconds: 0.01)
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 1)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .timeout)
    }

    @Test("Late generic connector result reports timeout after 1 call")
    func lateGenericConnectorResultReportsTimeoutAfterOneCall() throws {
        let connector = LateGenericPDTConnector()
        let store = try temporaryStore("pdtbar-late-generic-deadline-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try PDTBackgroundDetailRefresh(
                connector: connector,
                snapshotStore: store,
                asOf: "2026-03-29",
                options: PDTBackgroundDetailRefreshOptions(paginationTimeoutSeconds: 0.01)
            ).refresh()
        }

        #expect(connector.callCount == 1)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == connector.callCount)
        #expect(diagnostic.category == .timeout)
    }

    @Test("Cold prefix discovery deadline spawns 0 read CLI runs")
    func coldPrefixDiscoveryDeadlineSpawnsZeroReadCLIRuns() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [.init(stdout: connectedPDT, stderr: "", exitCode: 0)],
            simulatedDelays: [0.1]
        )
        let connection = connection(runner: runner)

        do {
            _ = try connection.callReadToolReportingAttempts(
                "pdt-get-portfolio-holdings",
                arguments: [:],
                retryDeadline: Date().addingTimeInterval(0.01)
            )
            Issue.record("Expected cold prefix discovery to exhaust the deadline")
        } catch let failure as PDTMCPConnectorCallFailure {
            #expect(failure.attemptCount == 0)
            #expect(failure.underlyingError as? PDTMCPConnectorError
                == .timeout("Claude MCP server check deadline expired"))
        }

        #expect(runner.requests.count == 1)
        #expect(readRuns(in: runner).isEmpty)
        #expect(runner.requests.first?.timeout ?? 1 <= 0.01)
    }

    @Test("Late prefix setup failure stays setup unavailable with 0 read CLI runs")
    func latePrefixSetupFailureStaysSetupUnavailableWithZeroReadCLIRuns() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [.init(stdout: "", stderr: "Error: Not logged in", exitCode: 1)],
            simulatedDelays: [0.02],
            honorsTimeout: false
        )
        let connection = connection(runner: runner)

        do {
            _ = try connection.callReadToolReportingAttempts(
                "pdt-get-portfolio-holdings",
                arguments: [:],
                retryDeadline: Date().addingTimeInterval(0.01)
            )
            Issue.record("Expected setup-unavailable prefix discovery failure")
        } catch let failure as PDTMCPConnectorCallFailure {
            #expect(failure.attemptCount == 0)
            #expect(failure.underlyingError as? PDTMCPConnectorError
                == .setupUnavailable("Claude PDT MCP server is not connected"))
        }

        #expect(runner.requests.count == 1)
        #expect(readRuns(in: runner).isEmpty)
    }

    @Test("Diagnostic reports all 4 CLI runs when outer retry is explicitly enabled")
    func diagnosticReportsAllFourCLIRunsWithOuterRetry() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: connectedPDT, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
            .init(stdout: "", stderr: "Temporary PDT failure", exitCode: 1),
        ])
        let store = try temporaryStore("pdtbar-four-run-diagnostic-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        #expect(throws: (any Error).self) {
            _ = try refresh(
                connection(runner: runner),
                store: store,
                options: PDTBackgroundDetailRefreshOptions(
                    optionalRetryCount: 1,
                    retryBackoffSeconds: 0
                )
            ).refresh()
        }

        let readRuns = readRuns(in: runner)
        #expect(readRuns.count == 4)
        let diagnostic = try #require(try store.loadLastDetailRefreshDiagnostic())
        #expect(diagnostic.attemptCount == readRuns.count)
        #expect(diagnostic.category == .transientFailure)
    }

    private var connectedPDT: String {
        "pdt (portfoliodividendtracker.com) connected"
    }

    private var emptyHoldingsStream: String {
        """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"call_1","name":"mcp__pdt__pdt-get-portfolio-holdings"}]}}
        {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[]}}
        {"type":"result","result":"{\\"status\\":\\"redacted-ok\\"}"}
        """
    }

    private func connection(
        runner: RecordingClaudeCommandRunner,
        retryCount: Int = 1,
        retryBackoffSeconds: Double = 0
    ) -> ClaudeLocalConnection {
        ClaudeLocalConnection(
            configuration: ClaudeLocalConnectionConfiguration(
                claudePath: "claude",
                model: "opus",
                toolTimeout: 10,
                readinessTimeout: 10,
                toolCallRetryPolicy: ClaudeToolCallRetryPolicy(
                    retryCount: retryCount,
                    retryBackoffSeconds: retryBackoffSeconds
                ),
                environment: [:],
                claudeProjectsDirectory: FileManager.default.temporaryDirectory
                    .appending(path: "pdtbar-retry-tests-\(UUID().uuidString)")
            ),
            commandRunner: runner
        )
    }

    private func refresh(
        _ connection: ClaudeLocalConnection,
        store: SnapshotStore,
        options: PDTBackgroundDetailRefreshOptions = PDTBackgroundDetailRefreshOptions(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> PDTBackgroundDetailRefresh {
        PDTBackgroundDetailRefresh(
            connector: connection,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: options,
            now: now
        )
    }

    private func temporaryStore(_ prefix: String) throws -> SnapshotStore {
        try SnapshotStore.temporaryTestStore(prefix: prefix)
    }

    private func readRuns(in runner: RecordingClaudeCommandRunner) -> [RecordingClaudeCommandRunner.Request] {
        runner.requests.filter { $0.arguments.first == "--model" }
    }
}

private final class LateGenericPDTConnector: PDTMCPConnector, @unchecked Sendable {
    private(set) var callCount = 0

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        callCount += 1
        Thread.sleep(forTimeInterval: 0.02)
        return Data(#"{"holdings":[]}"#.utf8)
    }
}

private final class DeadlineCrossingClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private var reads = 0

    func now() -> Date {
        lock.withLock {
            defer { reads += 1 }
            return reads == 0 ? start : start.addingTimeInterval(1)
        }
    }
}
