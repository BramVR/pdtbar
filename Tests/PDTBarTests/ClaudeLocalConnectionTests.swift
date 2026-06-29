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

    @Test("MCP list parsing derives Claude PDT tool prefixes")
    func mcpListParsingDerivesClaudePDTToolPrefixes() {
        let output = "claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected"

        #expect(ClaudeLocalConnection.pdtToolPrefixes(fromMCPListOutput: output) == [
            "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__",
        ])
        #expect(ClaudeLocalConnection.pdtToolPrefixes(fromMCPListOutput: "pdt (portfoliodividendtracker.com) connected") == [
            "mcp__pdt__",
        ])
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

    @Test("Connected PDT server reports ToolSearch verified required read tools")
    func connectedPDTServerReportsToolSearchVerifiedRequiredReadTools() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
            .init(stdout: "mcp__pdt__pdt-get-portfolio-holdings", stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        let available = try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])

        #expect(available == ["pdt-get-portfolio-holdings"])
        #expect(runner.requests.count == 2)
        #expect(runner.requests.last?.arguments.contains("ToolSearch") == true)
    }

    @Test("MCP list availability verifies tools with ToolSearch")
    func mcpListAvailabilityVerifiesToolsWithToolSearch() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected", stderr: "", exitCode: 0),
            .init(stdout: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-x-ray-holdings", stderr: "", exitCode: 0),
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
        #expect(progress.values == ["Checking Claude MCP servers", "Finding PDT read tools"])
        #expect(runner.requests.count == 2)
        #expect(runner.requests.last?.arguments.contains("ToolSearch") == true)
    }

    @Test("Partial ToolSearch availability resolves missing tools individually")
    func partialToolSearchAvailabilityResolvesMissingToolsIndividually() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
            .init(stdout: "mcp__pdt__pdt-get-portfolio-holdings", stderr: "", exitCode: 0),
            .init(stdout: "mcp__pdt__pdt-list-x-ray-holdings", stderr: "", exitCode: 0),
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
        #expect(runner.requests.count == 3)
        #expect(progress.values.contains("Finding PDT read tools"))
        #expect(progress.values.contains("Finding pdt-list-x-ray-holdings"))
    }

    @Test("Concrete read-tool calls avoid broad PDT allowlists")
    func concreteReadToolCallsAvoidBroadPDTAllowlists() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: streamJSON(
                toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-x-ray-holdings",
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

        #expect(runner.requests.count == 1)
        #expect(runner.requests.first?.arguments.joined(separator: " ").contains("--allowedTools mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-x-ray-holdings") == true)
        #expect(runner.requests.first?.arguments.joined(separator: " ").contains("--allowedTools mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-*") == false)
        #expect(runner.requests.allSatisfy { !$0.arguments.contains("ToolSearch") })
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
        #expect(progress.values.contains("Finding PDT read tools"))
        #expect(!progress.values.contains("Waiting on Claude for PDT tool discovery"))
        #expect(runner.requests.contains { $0.arguments.contains("ToolSearch") })
        let toolSearchArguments = runner.requests.last?.arguments.joined(separator: " ") ?? ""
        #expect(toolSearchArguments.contains("--disallowedTools"))
        #expect(toolSearchArguments.contains("Bash"))
        #expect(toolSearchArguments.contains("Read"))
        #expect(toolSearchArguments.contains("WebSearch"))
    }

    @Test("Concrete read-tool calls reject different tool names")
    func concreteReadToolCallsRejectDifferentToolNames() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-symbol-quote",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"symbol":{"id":5101}}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        #expect(throws: PDTMCPConnectorError.transientFailure("Claude did not call mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-symbol")) {
            try connection.callReadTool("pdt-get-symbol", arguments: ["id": "5101"])
        }
    }

    @Test("Read-tool calls use concrete allowlists, parser results, and retry classification")
    func readToolCallsUseSharedResolutionAndParser() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: streamJSON(toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"Result pending"}]}"#), stderr: "", exitCode: 0),
            .init(stdout: streamJSON(toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Shared Public Co","portfolioWeight":0.21}]}}"#), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 1),
            commandRunner: runner
        )

        let data = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(try firstHoldingName(in: data) == "Shared Public Co")
        #expect(runner.requests.count == 2)
        let readRequest = try #require(runner.requests.last)
        #expect(readRequest.arguments.joined(separator: " ").contains("--allowedTools mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Call the PDT read tool named pdt-get-portfolio-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("mcp__*__pdt-update-*"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Bash"))
        #expect(readRequest.arguments.joined(separator: " ").contains("Read"))
        #expect(readRequest.arguments.joined(separator: " ").contains("WebSearch"))
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

    private func configuration(
        retryCount: Int = 1,
        claudeProjectsDirectory: URL? = nil
    ) -> ClaudeLocalConnectionConfiguration {
        ClaudeLocalConnectionConfiguration(
            claudePath: "claude",
            model: "opus",
            toolTimeout: 10,
            readinessTimeout: 10,
            toolCallRetryPolicy: ClaudeToolCallRetryPolicy(retryCount: retryCount),
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
