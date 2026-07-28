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

    @Test("Canonical PDT prefix wins regardless of list order with renamed fallback")
    func canonicalPDTPrefixWinsRegardlessOfListOrderWithRenamedFallback() throws {
        let output = """
        pdt-staging: https://staging.example/mcp - ✔ Connected
        claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected
        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        """
        let expectedOrder = [
            "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__",
            "mcp__pdt_staging__",
        ]
        #expect(ClaudeLocalConnection.pdtToolPrefixes(fromMCPListOutput: output) == expectedOrder)
        #expect(ClaudeLocalConnection.pdtToolPrefixes(
            fromMCPListOutput: "PDT Prod: https://pdt-prod.example/mcp - ✔ Connected"
        ) == ["mcp__PDT_Prod__"])

        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: output, stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-x-ray-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"items":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: runner
        )

        _ = try connection.callReadTool("pdt-list-x-ray-holdings", arguments: [:])

        let readArguments = try #require(runner.requests.last?.arguments)
        let allowedToolsIndex = try #require(readArguments.firstIndex(of: "--allowedTools"))
        #expect(
            readArguments[allowedToolsIndex + 1]
                == "ToolSearch,mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-x-ray-holdings"
        )

        let renamedOutput = "PDT Prod: https://pdt-prod.example/mcp - ✔ Connected"
        let renamedRunner = RecordingClaudeCommandRunner(results: [
            .init(stdout: renamedOutput, stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__PDT_Prod__pdt-list-x-ray-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"items":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let renamedConnection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: renamedRunner
        )

        _ = try renamedConnection.callReadTool("pdt-list-x-ray-holdings", arguments: [:])

        let renamedReadArguments = try #require(renamedRunner.requests.last?.arguments)
        let renamedAllowedToolsIndex = try #require(renamedReadArguments.firstIndex(of: "--allowedTools"))
        #expect(
            renamedReadArguments[renamedAllowedToolsIndex + 1]
                == "ToolSearch,mcp__PDT_Prod__pdt-list-x-ray-holdings"
        )
    }

    @Test("MCP list parsing derives non-PDT prefixes across names and states")
    func mcpListParsingDerivesNonPDTPrefixesAcrossNamesAndStates() {
        let output = """
        claude.ai Portfolio Dividend Tracker (PDT): https://mcp.portfoliodividendtracker.com - ✔ Connected
        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        claude.ai Google Drive: https://drivemcp.googleapis.com/mcp/v1 - ! Needs authentication
        Local Webflow (Design/API): http://127.0.0.1:7331/mcp - ✘ Failed to connect
        Notion - Workspace [beta]: https://mcp.notion.example - Disconnected
        PDT Prod: https://pdt-prod.example/mcp - ✔ Connected
        My PDT Server: https://pdt.example/mcp - ✔ Connected
        pdt-staging: https://staging.example/mcp - ✔ Connected
        informational text without a server status
        """

        let prefixes = ClaudeLocalConnection.nonPDTToolPrefixes(fromMCPListOutput: output)

        #expect(prefixes == [
            "mcp__claude_ai_Gmail__",
            "mcp__claude_ai_Google_Drive__",
            "mcp__Local_Webflow_Design_API__",
            "mcp__Notion_Workspace_beta__",
        ])
        #expect(ClaudeLocalConnection.nonPDTToolPrefixes(fromMCPListOutput: "").isEmpty)
        #expect(ClaudeLocalConnection.nonPDTToolPrefixes(fromMCPListOutput: "unparseable output").isEmpty)
    }

    @Test("PDT-ish server names fail open and are never denied")
    func pdtishServerNamesFailOpenAndAreNeverDenied() throws {
        let mcpListOutput = """
        PDT Prod: https://pdt-prod.example/mcp - ✔ Connected
        My PDT Server: https://pdt.example/mcp - ✔ Connected
        pdt-staging: https://staging.example/mcp - ✔ Connected
        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        """
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: mcpListOutput, stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__PDT_Prod__pdt-list-x-ray-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"items":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, claudeProjectsDirectory: temporaryClaudeProjectsDirectory()),
            commandRunner: runner
        )

        _ = try connection.callReadTool("pdt-list-x-ray-holdings", arguments: [:])

        let readArguments = try #require(runner.requests.last?.arguments)
        let disallowedFlagIndex = try #require(readArguments.firstIndex(of: "--disallowedTools"))
        let disallowed = Set(readArguments[disallowedFlagIndex + 1].split(separator: ",").map(String.init))
        #expect(disallowed.contains("mcp__claude_ai_Gmail__*"))
        #expect(!disallowed.contains("mcp__PDT_Prod__*"))
        #expect(!disallowed.contains("mcp__My_PDT_Server__*"))
        #expect(!disallowed.contains("mcp__pdt_staging__*"))
    }

    @Test("MCP detection and deny classification matrix")
    func mcpDetectionAndDenyClassificationMatrix() {
        let cases = [
            (
                "claude.ai Portfolio Dividend Tracker (PDT): ... - Connected",
                "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__",
                true,
                false
            ),
            ("PDT Prod: ... - Connected", "mcp__PDT_Prod__", true, false),
            ("My PDT Server: ... - Connected", "mcp__My_PDT_Server__", true, false),
            ("pdt-staging: ... - Connected", "mcp__pdt_staging__", true, false),
            ("claude.ai Gmail: ... - Connected", "mcp__claude_ai_Gmail__", false, true),
            ("claude.ai Notion: ... - Connected", "mcp__claude_ai_Notion__", false, true),
        ]
        let output = cases.map(\.0).joined(separator: "\n")
        let deniedPrefixes = Set(ClaudeLocalConnection.nonPDTToolPrefixes(fromMCPListOutput: output))

        for (line, prefix, expectedPDT, expectedDenied) in cases {
            let detectedAsPDT = ClaudeLocalConnection.pdtServerIsConnected(in: line)
            let denied = deniedPrefixes.contains(prefix)
            #expect(detectedAsPDT == expectedPDT)
            #expect(denied == expectedDenied)
        }
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

    @Test("Environment configuration defaults the performance timeout to sixty seconds")
    func environmentConfigurationDefaultsPerformanceTimeout() {
        let configured = ClaudeLocalConnectionConfiguration(environment: [:])

        #expect(configured.performanceToolTimeout == 60)
    }

    @Test("Environment configuration honors the performance timeout override")
    func environmentConfigurationHonorsPerformanceTimeoutOverride() throws {
        var configured = ClaudeLocalConnectionConfiguration(environment: [
            "PDTBAR_CLAUDE_PERFORMANCE_TOOL_TIMEOUT": "95.5",
        ])
        configured.claudeProjectsDirectory = temporaryClaudeProjectsDirectory()
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
                performanceResult(),
            ],
            simulatedDelays: [0, 96]
        )
        let connection = ClaudeLocalConnection(
            configuration: configured,
            commandRunner: runner
        )

        #expect(configured.performanceToolTimeout == 95.5)
        #expect(throws: PDTMCPConnectorError.timeout(
            "Claude pdt-get-portfolio-performance call timed out"
        )) {
            try connection.callReadTool("pdt-get-portfolio-performance", arguments: [:])
        }
        #expect(runner.requests.last?.timeout == 95.5)
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
        let modelIndex = try #require(readArguments.firstIndex(of: "--model"))
        #expect(Array(readArguments[(modelIndex + 2)...(modelIndex + 3)]) == ["--permission-mode", "dontAsk"])
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
        #expect(disallowed.contains("mcp__claude_ai_Gmail__*"))
        #expect(!disallowed.contains("mcp__*__pdt-list-x-ray-holdings"))
        #expect(!disallowed.contains("mcp__pdt__pdt-list-x-ray-holdings"))
        #expect(!disallowed.contains("mcp__*"))
        #expect(!disallowed.contains("ToolSearch"))
    }

    @Test("Read argv is exact and never denies the resolved PDT prefix")
    func readArgvIsExactAndNeverDeniesResolvedPDTPrefix() throws {
        let mcpListOutput = """
        pdt (portfoliodividendtracker.com) connected
        claude.ai Notion - Workspace [beta]: https://mcp.notion.example - ! Needs authentication
        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        pdt (portfoliodividendtracker.com): https://mcp.portfoliodividendtracker.com - Disconnected
        """
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: mcpListOutput, stderr: "", exitCode: 0),
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

        let readArguments = try #require(runner.requests.last?.arguments)
        let sessionFlagIndex = try #require(readArguments.firstIndex(of: "--session-id"))
        let sessionID = readArguments[sessionFlagIndex + 1]
        let dynamicNonPDTDenies = [
            "mcp__claude_ai_Gmail__*",
            "mcp__claude_ai_Notion_Workspace_beta__*",
        ]
        let expectedDisallowed = (
            ClaudePDTReadOnlyToolPolicy.disallowedTools
                + PDTReadTools.allowedV1
                    .filter { $0 != "pdt-list-x-ray-holdings" }
                    .map { "mcp__*__\($0)" }
                + dynamicNonPDTDenies
        ).joined(separator: ",")
        let expectedPrompt = """
        PDTBar needs one local read-only PDT MCP result.

        Rules:
        - Find and call the read-only PDT MCP tool named pdt-list-x-ray-holdings from the Portfolio Dividend Tracker (PDT) MCP server.
        - Use exactly these JSON arguments: {"limit":"1","offset":"0"}
        - Do not call any PDT MCP tool other than pdt-list-x-ray-holdings.
        - Do not call any write, create, update, delete, remove, post, put, or set tool.
        - Do not print holdings, values, account identifiers, endpoints, credentials, or raw tool output in your final answer.
        - After the tool call, return only {"status":"redacted-ok"}.
        """
        #expect(readArguments == [
            "--model", "opus",
            "--permission-mode", "dontAsk",
            "--allowedTools", "ToolSearch,mcp__pdt__pdt-list-x-ray-holdings",
            "--disallowedTools", expectedDisallowed,
            "--session-id", sessionID,
            "-p", expectedPrompt,
            "--output-format", "stream-json",
            "--verbose",
            "--no-session-persistence",
        ])

        let disallowed = Set(expectedDisallowed.split(separator: ",").map(String.init))
        #expect(!disallowed.contains("mcp__pdt__*"))
        #expect(!disallowed.contains("mcp__pdt__pdt-list-x-ray-holdings"))
        #expect(!disallowed.contains("mcp__*"))

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

    @Test("Read-tool print runs wait for MCP tools before prompting Claude")
    func readToolPrintRunsWaitForMCPToolsBeforePromptingClaude() throws {
        let runner = RecordingClaudeCommandRunner(results: [
            .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
            .init(stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-portfolio-holdings",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[]}}"#
            ), stderr: "", exitCode: 0),
        ])
        let connection = ClaudeLocalConnection(
            configuration: configuration(environment: ["MCP_CONNECTION_NONBLOCKING": "true"]),
            commandRunner: runner
        )

        _ = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(runner.requests.first?.environment["MCP_CONNECTION_NONBLOCKING"] == "true")
        #expect(runner.requests.last?.arguments.first == "--model")
        #expect(runner.requests.last?.environment["MCP_CONNECTION_NONBLOCKING"] == "false")
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

        #expect(throws: PDTMCPConnectorError.timeout("Claude pdt-get-portfolio-holdings call timed out")) {
            try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        }
        // Three attempts (mcp list + three read runs) with a backoff before
        // each retry: N-1 delays for N attempts.
        #expect(runner.requests.count == 4)
        #expect(delays.values == [2.0, 2.0])
    }

    @Test("Performance calls beyond the bounded budget time out without data")
    func performanceCallBeyondBudgetTimesOutWithoutData() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
                performanceResult(),
            ],
            simulatedDelays: [0, 18.5]
        )
        let connection = ClaudeLocalConnection(
            configuration: configuration(
                retryCount: 2,
                toolTimeout: 120,
                performanceToolTimeout: 18
            ),
            commandRunner: runner
        )
        let connector = PerformanceRoutingPDTConnector(performanceConnector: connection)
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-performance-timeout-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .degraded)
        #expect(result.model.portfolioPerformance == PortfolioPerformanceSummary())
        #expect(result.model.facetSnapshots.dataHealth.diagnostic?.detail
            == "pdt-get-portfolio-performance; performance; timeout")
        #expect(result.diagnostics == [
            PDTDetailRefreshFailureDiagnostic(
                toolName: "pdt-get-portfolio-performance",
                phase: .performance,
                attemptCount: 1,
                category: .timeout,
                argumentShape: []
            ),
        ])
        #expect(runner.requests.filter { $0.arguments.first == "--model" }.count == 1)
        #expect(runner.requests.last?.timeout == 18)
    }

    @Test("Measured-latency performance calls fit the bounded budget and populate data")
    func measuredLatencyPerformanceCallsPopulateData() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
                performanceResult(),
                performanceGainsResult(),
            ],
            simulatedDelays: [0, 18.5, 18.5]
        )
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 2, toolTimeout: 120),
            commandRunner: runner
        )
        let connector = PerformanceRoutingPDTConnector(performanceConnector: connection)
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-performance-latency-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let result = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(retryBackoffSeconds: 0)
        ).refresh()

        #expect(result.outcome == .completed)
        #expect(result.model.portfolioPerformance.totalPercentageIncrease == 0.21)
        #expect(result.model.portfolioPerformance.cagr != nil)
        #expect(runner.requests.filter { $0.arguments.first == "--model" }.map(\.timeout) == [60, 60])
    }

    @Test("Performance timeout is clamped by the overall tool timeout")
    func performanceTimeoutIsClampedByOverallToolTimeout() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
                performanceResult(),
            ],
            simulatedDelays: [0, 120.5]
        )
        let connection = ClaudeLocalConnection(
            configuration: configuration(
                retryCount: 2,
                toolTimeout: 120,
                performanceToolTimeout: 180
            ),
            commandRunner: runner
        )

        #expect(throws: PDTMCPConnectorError.timeout(
            "Claude pdt-get-portfolio-performance call timed out"
        )) {
            try connection.callReadTool("pdt-get-portfolio-performance", arguments: [:])
        }
        #expect(runner.requests.filter { $0.arguments.first == "--model" }.count == 1)
        #expect(runner.requests.last?.timeout == 120)
    }

    @Test("Non-performance reads retain the configured tool budget")
    func nonPerformanceReadsRetainConfiguredToolBudget() throws {
        let runner = RecordingClaudeCommandRunner(
            results: [
                .init(stdout: "pdt (portfoliodividendtracker.com) connected", stderr: "", exitCode: 0),
                .init(
                    stdout: streamJSON(
                        toolName: "mcp__pdt__pdt-get-portfolio-holdings",
                        result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[]}}"#
                    ),
                    stderr: "",
                    exitCode: 0
                ),
            ],
            simulatedDelays: [0, 90]
        )
        let connection = ClaudeLocalConnection(
            configuration: configuration(retryCount: 0, toolTimeout: 120),
            commandRunner: runner
        )

        _ = try connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(runner.requests.last?.timeout == 120)
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
        toolTimeout: Double = 10,
        performanceToolTimeout: Double = 60,
        environment: [String: String] = [:],
        claudeProjectsDirectory: URL? = nil
    ) -> ClaudeLocalConnectionConfiguration {
        ClaudeLocalConnectionConfiguration(
            claudePath: "claude",
            model: "opus",
            toolTimeout: toolTimeout,
            performanceToolTimeout: performanceToolTimeout,
            readinessTimeout: 10,
            toolCallRetryPolicy: ClaudeToolCallRetryPolicy(
                retryCount: retryCount,
                retryBackoffSeconds: retryBackoffSeconds
            ),
            environment: environment,
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

    private func performanceResult() -> ClaudeLocalProcessResult {
        ClaudeLocalProcessResult(
            stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-portfolio-performance",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"oldestPortfolioDate":"2024-03-29","latestPortfolioDate":"2026-03-29"}}"#
            ),
            stderr: "",
            exitCode: 0
        )
    }

    private func performanceGainsResult() -> ClaudeLocalProcessResult {
        ClaudeLocalProcessResult(
            stdout: streamJSON(
                toolName: "mcp__pdt__pdt-get-portfolio-gains",
                result: #"{"type":"tool_result","tool_use_id":"call_1","structuredContent":{"totalGainsPercentage":0.21}}"#
            ),
            stderr: "",
            exitCode: 0
        )
    }
}

private final class RecordingClaudeCommandRunner: ClaudeLocalCommandRunning, @unchecked Sendable {
    struct Request: Equatable {
        var executable: String
        var arguments: [String]
        var timeout: TimeInterval
        var environment: [String: String]
    }

    private let lock = NSLock()
    private var queuedResults: [ClaudeLocalProcessResult]
    private var queuedSimulatedDelays: [TimeInterval]
    private let executableAvailable: Bool
    private var recordedRequests: [Request] = []

    init(
        executableAvailable: Bool = true,
        results: [ClaudeLocalProcessResult] = [],
        simulatedDelays: [TimeInterval] = []
    ) {
        self.executableAvailable = executableAvailable
        self.queuedResults = results
        self.queuedSimulatedDelays = simulatedDelays
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
        recordedRequests.append(Request(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        ))
        let simulatedDelay = queuedSimulatedDelays.isEmpty ? 0 : queuedSimulatedDelays.removeFirst()
        let result = queuedResults.isEmpty
            ? ClaudeLocalProcessResult(stdout: "", stderr: "", exitCode: 0)
            : queuedResults.removeFirst()
        lock.unlock()
        if simulatedDelay > timeout {
            // Match DefaultClaudeLocalCommandRunner: -1 with no missing-binary
            // stderr is classified by ClaudeLocalConnection as a timeout.
            return ClaudeLocalProcessResult(stdout: "", stderr: "", exitCode: -1)
        }
        return result
    }
}

private final class PerformanceRoutingPDTConnector: PDTMCPConnector {
    private let performanceConnector: any PDTMCPConnector

    init(performanceConnector: any PDTMCPConnector) {
        self.performanceConnector = performanceConnector
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1 + PDTReadTools.performance)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        if PDTReadTools.performance.contains(name) {
            return try performanceConnector.callReadTool(name, arguments: arguments)
        }
        guard let response = Self.responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(name)
        }
        return Data(response.utf8)
    }

    private static let responses = [
        "pdt-get-portfolio-holdings": #"{"holdings":[]}"#,
        "pdt-get-portfolio-distributions": #"{"sectors":[],"assetTypes":[]}"#,
        "pdt-list-x-ray-holdings": #"{"items":[],"hasMore":false}"#,
        "pdt-list-calendar-events": #"{"data":[],"meta":{"last_page":1}}"#,
        "pdt-list-dividends": #"{"data":[],"meta":{"last_page":1}}"#,
    ]
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
