import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Claude local connection")
struct ClaudeLocalConnectionTests {
    @Test("MCP list parsing recognizes connected PDT servers only")
    func mcpListParsingRecognizesConnectedPDTServersOnly() {
        #expect(ClaudeLocalConnection.pdtServerIsConnected(in: "Portfolio Dividend Tracker connected"))
        #expect(ClaudeLocalConnection.pdtServerIsConnected(in: "pdt (portfoliodividendtracker.com) connected"))
        #expect(!ClaudeLocalConnection.pdtServerIsConnected(in: "Portfolio Dividend Tracker not connected"))
        #expect(!ClaudeLocalConnection.pdtServerIsConnected(in: "Some Other MCP connected"))
    }

    @Test("MCP list parsing derives PDT tool prefixes")
    func mcpListParsingDerivesPDTToolPrefixes() {
        let output = """
        claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected
        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        claude.ai Google Drive: https://drivemcp.googleapis.com/mcp/v1 - ! Needs authentication
        """

        let prefixes = ClaudeLocalConnection.pdtToolPrefixes(fromMCPListOutput: output)

        #expect(prefixes == ["mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__"])
    }

    @Test("Missing Claude classifies readiness and availability as setup unavailable")
    func missingClaudeClassifiesSetupUnavailable() throws {
        let runner = RecordingClaudeCommandRunner(executableAvailable: false)
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(connection.checkReadiness() == .missingClaudeLogin)
        #expect(throws: PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")) {
            try connection.availableReadTools()
        }
        #expect(runner.requests.isEmpty)
    }

    @Test("Environment configuration preserves configured Claude binary")
    func environmentConfigurationPreservesConfiguredClaudeBinary() throws {
        let configured = ClaudeLocalConnectionConfiguration(environment: [
            "PDTBAR_CLAUDE_BIN": "/usr/local/bin/claude-wrapper",
        ])

        #expect(configured.claudePath == "/usr/local/bin/claude-wrapper")
    }

    @Test("Missing PDT MCP blocks readiness and read-tool availability")
    func missingPDTMCPBlocksReadinessAndAvailability() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: #"{"loggedIn":true}"#, stderr: "", exitCode: 0),
            .init(stdout: "other server connected", stderr: "", exitCode: 0),
            .init(stdout: "other server connected", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(connection.checkReadiness() == .missingPDTMCP)
        #expect(throws: PDTMCPConnectorError.setupUnavailable("Claude PDT MCP server is not connected")) {
            try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])
        }
    }

    @Test("Connected PDT server reports requested read tools without ToolSearch")
    func connectedPDTServerReportsRequestedReadToolsWithoutToolSearch() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        let available = try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])

        #expect(available == ["pdt-get-portfolio-holdings"])
        #expect(runner.requests.count == 1)
        #expect(!runner.requests.contains { $0.arguments.contains("ToolSearch") })
    }

    @Test("MCP list availability reports tools without ToolSearch")
    func mcpListAvailabilityReportsToolsWithoutToolSearch() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: runner
        )
        let progress = StringProgressRecorder()

        let available = try connection.availableReadTools(required: ["pdt-list-x-ray-holdings"]) {
            progress.append($0)
        }

        #expect(available == ["pdt-list-x-ray-holdings"])
        #expect(progress.values == ["Checking Claude MCP servers"])
        #expect(runner.requests.count == 1)
        #expect(!runner.requests.contains { $0.arguments.contains("ToolSearch") })
    }

    @Test("MCP list availability reports multiple requested required tools together")
    func mcpListAvailabilityReportsMultipleRequestedRequiredToolsTogether() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )
        let progress = StringProgressRecorder()

        let available = try connection.availableReadTools(required: [
            "pdt-get-portfolio-holdings",
            "pdt-list-x-ray-holdings",
        ]) {
            progress.append($0)
        }

        #expect(available == ["pdt-get-portfolio-holdings", "pdt-list-x-ray-holdings"])
        #expect(runner.requests.count == 1)
        #expect(progress.values == ["Checking Claude MCP servers"])
    }

    @Test("Read-tool calls use PDT-only deny policy")
    func readToolCallsUsePDTOnlyDenyPolicy() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected\nclaude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected", stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-list-x-ray-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"items":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: runner
        )

        _ = try connection.availableReadTools(required: ["pdt-list-x-ray-holdings"])
        _ = try connection.callReadTool("pdt-list-x-ray-holdings", arguments: [
            "limit": "1",
            "offset": "0",
        ])

        #expect(runner.requests.count == 2)
        let readArguments = runner.requests.last?.arguments ?? []
        #expect(readArguments.joined(separator: " ").contains("--allowedTools ToolSearch,mcp__pdt__pdt-list-x-ray-holdings"))
        var disallowed = Set<String>()
        if let flagIndex = readArguments.firstIndex(of: "--disallowedTools"), flagIndex + 1 < readArguments.count {
            disallowed = Set(readArguments[flagIndex + 1].split(separator: ",").map(String.init))
        }
        // Production must send the entire shared read-only deny policy plus
        // the non-requested PDT read tools, and never deny the requested tool
        // or ToolSearch.
        #expect(Set(ClaudePDTReadOnlyToolPolicy.disallowedTools).isSubset(of: disallowed))
        #expect(disallowed.contains("ListMcpResourcesTool"))
        #expect(disallowed.contains("ReadMcpResourceTool"))
        #expect(disallowed.contains("mcp__*__pdt-update-*"))
        #expect(disallowed.contains("mcp__*__pdt-get-portfolio-holdings"))
        #expect(disallowed.contains("mcp__*__pdt-get-symbol"))
        #expect(!disallowed.contains("mcp__*__pdt-list-x-ray-holdings"))
        #expect(!disallowed.contains("mcp__pdt__pdt-list-x-ray-holdings"))
        #expect(!disallowed.contains("ToolSearch"))
    }

    @Test("Availability reports PDT server check progress")
    func availabilityReportsPDTServerCheckProgress() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
            .init(stdout: "mcp__pdt__pdt-list-x-ray-holdings", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )
        let progress = StringProgressRecorder()

        _ = try connection.availableReadTools(required: ["pdt-list-x-ray-holdings"]) {
            progress.append($0)
        }

        #expect(progress.values.contains("Checking Claude MCP servers"))
        #expect(!progress.values.contains("Finding PDT read tools"))
        #expect(!runner.requests.contains { $0.arguments.contains("ToolSearch") })
        let toolSearchArguments = runner.requests.last?.arguments.joined(separator: " ") ?? ""
        #expect(toolSearchArguments == "mcp list")
    }

    @Test("Concrete read-tool calls reject different tool names")
    func concreteReadToolCallsRejectDifferentToolNames() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-symbol-quote",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"symbol":{"id":5101}}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        _ = try connection.availableReadTools(required: ["pdt-get-symbol"])
        #expect(throws: PDTMCPConnectorError.transientFailure("Claude did not call mcp__pdt__pdt-get-symbol")) {
            try connection.callReadTool("pdt-get-symbol", arguments: ["id": "5101"])
        }
        let readArguments = runner.requests.last?.arguments.joined(separator: " ") ?? ""
        #expect(readArguments.contains("--allowedTools ToolSearch,mcp__pdt__pdt-get-symbol"))
        #expect(readArguments.contains("mcp__*__pdt-get-symbol-quote"))
    }

    @Test("Read-tool calls use deny policy, parser results, and retry classification")
    func readToolCallsUseSharedResolutionAndParser() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: streamJSON(toolName: "mcp__pdt__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"Result pending"}]}"#), stderr: "", exitCode: 0),
            .init(stdout: streamJSON(toolName: "mcp__pdt__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Shared Public Co","portfolioWeight":0.21}]}}"#), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 1),
            commandRunner: runner
        )

        _ = try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])
        let data = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(try firstHoldingName(in: data) == "Shared Public Co")
        #expect(runner.requests.count == 3)
        let readRequest = try #require(runner.requests.last)
        #expect(readRequest.arguments.joined(separator: " ").contains("--allowedTools ToolSearch,mcp__pdt__pdt-get-portfolio-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Find and call the read-only PDT MCP tool named pdt-get-portfolio-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("mcp__*__pdt-update-*"))
        #expect(readRequest.arguments.joined(separator: " ").contains("mcp__*__pdt-list-x-ray-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("AskUserQuestion"))
        #expect(readRequest.arguments.joined(separator: " ").contains("DesignSync"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Bash"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Read"))
        #expect(readRequest.arguments.joined(separator: " ").contains("WebSearch"))
    }

    @Test("Direct read-tool calls refresh MCP prefixes before invoking Claude")
    func directReadToolCallsRefreshMCPPrefixesBeforeInvokingClaude() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-list-x-ray-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"items":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: runner
        )

        _ = try connection.callReadTool("pdt-list-x-ray-holdings", arguments: [
            "limit": "1",
            "offset": "0",
        ])

        #expect(runner.requests.map { $0.arguments.first ?? "" } == ["mcp", "--model"])
        let readArguments = runner.requests.last?.arguments.joined(separator: " ") ?? ""
        #expect(readArguments.contains("--allowedTools ToolSearch,mcp__pdt__pdt-list-x-ray-holdings"))
        #expect(readArguments.contains("mcp__*__pdt-get-portfolio-holdings"))
    }

    @Test("Non-read PDT tools are refused before Claude is invoked")
    func nonReadPDTToolsAreRefusedBeforeClaudeIsInvoked() throws {
        let runner = RecordingClaudeCommandRunner()
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(throws: PDTMCPConnectorError.nonReadTool("pdt-update-portfolio")) {
            try connection.callReadTool("pdt-update-portfolio", arguments: [:])
        }
        #expect(runner.requests.isEmpty)
    }

    @Test("Readiness probe timeout reports a retryable failure, not a logged-out user")
    func readinessProbeTimeoutReportsRetryableFailure() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: #"{"loggedIn":true}"#, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "", exitCode: -1),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(connection.checkReadiness() == .failed)
    }

    @Test("Readiness probe still reports missing login for real nonzero MCP list exits")
    func readinessProbeStillReportsMissingLoginForRealNonzeroExits() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: #"{"loggedIn":true}"#, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Not logged in", exitCode: 1),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(connection.checkReadiness() == .missingClaudeLogin)
    }

    @Test("Readiness probe reports missing login when the Claude binary vanished mid-probe")
    func readinessProbeReportsMissingLoginWhenClaudeBinaryVanishedMidProbe() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: #"{"loggedIn":true}"#, stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "claude not found", exitCode: -1),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(),
            commandRunner: runner
        )

        #expect(connection.checkReadiness() == .missingClaudeLogin)
    }

    @Test("MCP list missing binary during availability stays setup unavailable")
    func mcpListMissingBinaryDuringAvailabilityStaysSetupUnavailable() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "", stderr: "claude not found", exitCode: -1),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        #expect(throws: PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")) {
            try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])
        }
    }

    @Test("MCP list timeout during availability is transient, not missing setup")
    func mcpListTimeoutDuringAvailabilityIsTransient() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "", stderr: "", exitCode: -1),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        #expect(throws: PDTMCPConnectorError.transientFailure("Claude MCP server check timed out")) {
            try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])
        }
    }

    @Test("Timed-out read calls classify as transient and retry with backoff between attempts")
    func timedOutReadCallsClassifyAsTransientAndRetryWithBackoff() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "", exitCode: -1),
            .init(stdout: "", stderr: "", exitCode: -1),
            .init(stdout: "", stderr: "", exitCode: -1),
        ])
        let delays = DelayRecorder()
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 2, retryBackoffSeconds: 2.0),
            commandRunner: runner,
            retryDelay: { delays.append($0) }
        )

        #expect(throws: PDTMCPConnectorError.transientFailure("Claude pdt-get-portfolio-holdings call timed out")) {
            try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        }
        // Three attempts (mcp list + three read runs) with a backoff before
        // each retry: N-1 delays for N attempts.
        #expect(runner.requests.count == 4)
        #expect(delays.values == [2.0, 2.0])
    }

    @Test("Transient nonzero exits recover after a backed-off retry")
    func transientNonzeroExitsRecoverAfterBackedOffRetry() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "stream error: unexpected disconnect", exitCode: 1),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-portfolio-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let delays = DelayRecorder()
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 1, retryBackoffSeconds: 0.25),
            commandRunner: runner,
            retryDelay: { delays.append($0) }
        )

        _ = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(runner.requests.count == 3)
        #expect(delays.values == [0.25])
    }

    @Test("Transient server-unavailable read failures recover after retry")
    func transientServerUnavailableReadFailuresRecoverAfterRetry() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "PDT MCP server unavailable; try again later", exitCode: 1),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-portfolio-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let delays = DelayRecorder()
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 1, retryBackoffSeconds: 0.5),
            commandRunner: runner,
            retryDelay: { delays.append($0) }
        )

        _ = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(runner.requests.count == 3)
        #expect(delays.values == [0.5])
    }

    @Test("Auth-outage read failures classify as setup unavailable and never retry")
    func authOutageReadFailuresClassifyAsSetupUnavailableAndNeverRetry() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "Error: Not logged in. Run claude auth login first.", exitCode: 1),
        ])
        let delays = DelayRecorder()
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 2, retryBackoffSeconds: 2.0),
            commandRunner: runner,
            retryDelay: { delays.append($0) }
        )

        #expect(throws: PDTMCPConnectorError.setupUnavailable(
            "Claude pdt-get-portfolio-holdings reported missing auth or unavailable access"
        )) {
            try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        }
        // One mcp list plus a single read attempt: deterministic auth
        // failures must not spawn further full CLI runs.
        #expect(runner.requests.count == 2)
        #expect(delays.values.isEmpty)
    }

    private func configuration(
        retryCount: Int = 1,
        retryBackoffSeconds: Double = 0,
        claudeProjectsDirectory: URL? = nil
    ) -> ClaudeLocalConnectionConfiguration {
        ClaudeLocalConnectionConfiguration(
            claudePath: "claude",
            model: "opus",
            toolTimeout: 10,
            readinessTimeout: 10,
            toolCallRetryPolicy: ClaudeToolCallRetryPolicy(
                retryCount: retryCount,
                retryBackoffSeconds: retryBackoffSeconds
            ),
            environment: [:],
            claudeProjectsDirectory: claudeProjectsDirectory ?? temporaryClaudeProjectsDirectory()
        )
    }

    private func temporaryClaudeProjectsDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pdtbar-claude-tests-\(UUID().uuidString)")
    }

    private func writeClaudeTranscript(_ text: String, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)
    }

    private func streamJSON(toolName: String, result: String) -> String {
        """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"call_1","name":"\(toolName)"}]}}
        \(result)
        {"type":"result","result":"{\\"status\\":\\"redacted-ok\\"}"}
        """
    }

    private func firstHoldingName(in data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let holdings = object?["holdings"] as? [[String: Any]]
        return holdings?.first?["symbolName"] as? String
    }
}

private final class RecordingClaudeCommandRunner: ClaudeLocalCommandRunning, @unchecked Sendable {
    struct Request: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let lock = NSLock()
    private var queuedResults: [ClaudeLocalProcessResult]
    private let executableAvailable: Bool
    private var recordedRequests: [Request] = []

    init(
        executableAvailable: Bool = true,
        results: [ClaudeLocalProcessResult] = []
    ) {
        self.executableAvailable = executableAvailable
        self.queuedResults = results
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func executableExists(
        _ executable: String,
        environment: [String: String]
    ) -> Bool {
        executableAvailable
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> ClaudeLocalProcessResult {
        lock.lock()
        recordedRequests.append(Request(executable: executable, arguments: arguments))
        let result = queuedResults.isEmpty
            ? ClaudeLocalProcessResult(stdout: "", stderr: "", exitCode: 0)
            : queuedResults.removeFirst()
        lock.unlock()
        return result
    }
}

private final class StringProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ value: String) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
}

private final class DelayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ value: TimeInterval) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
}
