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

    @Test("ToolSearch resolves required PDT read tools")
    func toolSearchResolvesRequiredReadTools() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "Portfolio Dividend Tracker connected", stderr: "", exitCode: 0),
            .init(stdout: toolSearchStream(readTools: ["pdt-get-portfolio-holdings"]), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0),
            commandRunner: runner
        )

        let available = try connection.availableReadTools(required: ["pdt-get-portfolio-holdings"])

        #expect(available == ["pdt-get-portfolio-holdings"])
        #expect(runner.requests.last?.arguments.contains("ToolSearch") == true)
    }

    @Test("Read-tool calls use ToolSearch, read-only allowlists, parser results, and retry classification")
    func readToolCallsUseSharedResolutionAndParser() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: toolSearchStream(readTools: ["pdt-get-portfolio-holdings"]), stderr: "", exitCode: 0),
            .init(stdout: streamJSON(toolName: "mcp__pdt__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"Result pending"}]}"#), stderr: "", exitCode: 0),
            .init(stdout: streamJSON(toolName: "mcp__pdt__pdt-get-portfolio-holdings", result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Shared Public Co","portfolioWeight":0.21}]}}"#), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 1),
            commandRunner: runner
        )

        let data = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(try firstHoldingName(in: data) == "Shared Public Co")
        #expect(runner.requests.count == 3)
        let readRequest = try #require(runner.requests.last)
        #expect(readRequest.arguments.joined(separator: " ").contains("--allowedTools mcp__pdt__pdt-get-portfolio-holdings"))
        #expect(readRequest.arguments.joined(separator: " ").contains("mcp__*__pdt-update-*"))
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

    private func configuration(retryCount: Int = 1) -> ClaudeLocalConnectionConfiguration {
        ClaudeLocalConnectionConfiguration(
            claudePath: "claude",
            model: "opus",
            toolTimeout: 10,
            readinessTimeout: 10,
            toolCallRetryPolicy: ClaudeToolCallRetryPolicy(retryCount: retryCount),
            environment: [:],
            claudeProjectsDirectory: FileManager.default.temporaryDirectory
        )
    }

    private func toolSearchStream(readTools: [String]) -> String {
        let content = readTools
            .map { #"{"type":"tool_use","id":"search_\#($0)","name":"mcp__pdt__\#($0)"}"# }
            .joined(separator: ",")
        return """
        {"type":"assistant","message":{"content":[\(content)]}}
        {"type":"result","result":"{\\"status\\":\\"redacted-ok\\"}"}
        """
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
