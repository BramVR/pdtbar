import Foundation
import Testing
import PDTBarAppSupport

@Suite("Claude tool-result parser")
struct ClaudeToolResultParserTests {
    private let toolName = "mcp__pdt__pdt-get-portfolio-holdings"
    private let readToolName = "pdt-get-portfolio-holdings"

    @Test("Structured content is preferred over JSON text content")
    func structuredContentIsPreferredOverJSONTextContent() throws {
        let output = streamJSON(
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Structured Public Co","portfolioWeight":0.25}]},"content":[{"type":"text","text":"{\"holdings\":[{\"symbolName\":\"Text Public Co\"}]}"}]}
            """#
        )

        let data = try ClaudeToolResultParser().resultData(
            for: toolName,
            readToolName: readToolName,
            output: output,
            currentSessionResultFiles: []
        )

        #expect(try firstHoldingName(in: data) == "Structured Public Co")
    }

    @Test("JSON text content is used when structured content is absent")
    func jsonTextContentIsUsedWhenStructuredContentIsAbsent() throws {
        let output = streamJSON(
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"{\"holdings\":[{\"symbolName\":\"Text Public Co\",\"portfolioWeight\":0.12}]}"}]}
            """#
        )

        let data = try ClaudeToolResultParser().resultData(
            for: toolName,
            readToolName: readToolName,
            output: output,
            currentSessionResultFiles: []
        )

        #expect(try firstHoldingName(in: data) == "Text Public Co")
    }

    @Test("Concrete PDT allow rule accepts the requested concrete read tool")
    func concretePDTAllowRuleAcceptsRequestedConcreteReadTool() throws {
        let output = streamJSON(
            toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings",
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Scoped Public Co","portfolioWeight":0.16}]}}
            """#
        )

        let data = try ClaudeToolResultParser().resultData(
            for: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings",
            readToolName: readToolName,
            output: output,
            currentSessionResultFiles: []
        )

        #expect(try firstHoldingName(in: data) == "Scoped Public Co")
    }

    @Test("Concrete PDT allow rule rejects a different read tool")
    func concretePDTAllowRuleRejectsDifferentReadTool() throws {
        let output = streamJSON(
            toolName: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-list-dividends",
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"data":[]}}
            """#
        )

        #expect(throws: ClaudeToolResultParserError.missingToolCall("mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings")) {
            _ = try ClaudeToolResultParser().resultData(
                for: "mcp__claude_ai_Portfolio_Dividend_Tracker_PDT__pdt-get-portfolio-holdings",
                readToolName: readToolName,
                output: output,
                currentSessionResultFiles: []
            )
        }
    }

    @Test("Saved file references are used before JSON text content")
    func savedFileReferencesAreUsedBeforeJSONTextContent() throws {
        let directory = try temporaryDirectory(named: "claude-parser-saved-reference")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let savedFile = directory.appending(path: "pdt-get-portfolio-holdings-result.txt")
        try #"{"holdings":[{"symbolName":"Saved Public Co","portfolioWeight":0.20}]}"#
            .write(to: savedFile, atomically: true, encoding: .utf8)
        let output = streamJSON(
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"Saved result to \#(savedFile.path)"},{"type":"text","text":"{\"holdings\":[{\"symbolName\":\"Text Public Co\"}]}"}]}
            """#
        )

        let data = try ClaudeToolResultParser().resultData(
            for: toolName,
            readToolName: readToolName,
            output: output,
            currentSessionResultFiles: [savedFile]
        )

        #expect(try firstHoldingName(in: data) == "Saved Public Co")
    }

    @Test("Current session tool-result files are used when Claude omits a saved-file reference")
    func currentSessionToolResultFilesAreUsedWithoutSavedFileReference() throws {
        let directory = try temporaryDirectory(named: "claude-parser-session-file")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sessionFile = directory.appending(path: "tool-result-pdt-get-portfolio-holdings.txt")
        try #"{"holdings":[{"symbolName":"Session Public Co","portfolioWeight":0.18}]}"#
            .write(to: sessionFile, atomically: true, encoding: .utf8)
        let output = streamJSON(
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"Result saved by Claude."}]}
            """#
        )

        let data = try ClaudeToolResultParser().resultData(
            for: toolName,
            readToolName: readToolName,
            output: output,
            currentSessionResultFiles: [sessionFile]
        )

        #expect(try firstHoldingName(in: data) == "Session Public Co")
    }

    @Test("Missing matching tool calls report a retryable parser error")
    func missingMatchingToolCallsReportParserError() throws {
        let output = streamJSON(
            toolName: "mcp__pdt__pdt-list-dividends",
            result: #"""
            {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"data":[]}}
            """#
        )

        do {
            _ = try ClaudeToolResultParser().resultData(
                for: toolName,
                readToolName: readToolName,
                output: output,
                currentSessionResultFiles: []
            )
            Issue.record("Expected missing tool-call error")
        } catch let error as ClaudeToolResultParserError {
            #expect(error == .missingToolCall(toolName))
        }
    }

    @Test("Malformed stream output reports the malformed line")
    func malformedStreamOutputReportsMalformedLine() throws {
        do {
            _ = try ClaudeToolResultParser().resultData(
                for: toolName,
                readToolName: readToolName,
                output: "{not-json}\n",
                currentSessionResultFiles: []
            )
            Issue.record("Expected malformed stream error")
        } catch let error as ClaudeToolResultParserError {
            #expect(error == .malformedStreamJSON(line: 1))
        }
    }

    @Test("Cleanup selection is limited to current-session PDT read-tool result files")
    func cleanupSelectionIsLimitedToCurrentSessionPDTReadToolResultFiles() throws {
        let directory = try temporaryDirectory(named: "claude-parser-cleanup")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let currentHolding = directory.appending(path: "tool-result-pdt-get-portfolio-holdings.txt")
        let currentDividend = directory.appending(path: "tool-result-pdt-list-dividends.txt")
        let currentNonPDT = directory.appending(path: "notes.txt")
        let oldHolding = directory.appending(path: "old-tool-result-pdt-get-portfolio-holdings.txt")
        for file in [currentHolding, currentDividend, currentNonPDT, oldHolding] {
            try #"{"status":"redacted-ok"}"#.write(to: file, atomically: true, encoding: .utf8)
        }
        let output = "Saved current \(currentHolding.path), old \(oldHolding.path), other \(currentNonPDT.path)"

        let cleanup = ClaudeToolResultParser().cleanupResultFiles(
            output: output,
            readToolNames: [readToolName],
            currentSessionResultFiles: [currentHolding, currentDividend, currentNonPDT]
        )

        #expect(cleanup == [currentHolding])
    }

    private func streamJSON(toolName: String? = nil, result: String) -> String {
        let name = toolName ?? self.toolName
        return """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"call_1","name":"\(name)"}]}}
        \(result)
        {"type":"result","result":"{\\"status\\":\\"redacted-ok\\"}"}
        """
    }

    private func firstHoldingName(in data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let holdings = object?["holdings"] as? [[String: Any]]
        return holdings?.first?["symbolName"] as? String
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
