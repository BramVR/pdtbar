import Foundation
import Testing
@testable import PDTBarAppSupport

@Suite("Claude local connection tool-result files")
struct ClaudeLocalConnectionToolResultTests {
    @Test("Inline structured results return without the polling stall")
    func inlineStructuredResultsReturnWithoutPollingStall() throws {
        let fixture = try ToolResultFixture(delivery: .inline(createLeftover: false))
        defer { fixture.remove() }

        let started = Date()
        let data = try fixture.connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        let elapsed = Date().timeIntervalSince(started)

        #expect(try firstHoldingName(in: data) == "Inline Public Co")
        #expect(elapsed < 0.5)
    }

    @Test("Immediately available file results resolve and are deleted")
    func immediatelyAvailableFileResultsResolveAndAreDeleted() throws {
        let fixture = try ToolResultFixture(delivery: .immediateFile)
        defer { fixture.remove() }

        let data = try fixture.connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        #expect(try firstHoldingName(in: data) == "File Public Co")
        let resultFile = try #require(fixture.runner.resultFiles.first)
        #expect(!FileManager.default.fileExists(atPath: resultFile.path))
    }

    @Test("Delayed file results wait with backoff and still resolve")
    func delayedFileResultsWaitWithBackoffAndStillResolve() throws {
        let fixture = try ToolResultFixture(delivery: .delayedFile(0.05))
        defer { fixture.remove() }

        let started = Date()
        let data = try fixture.connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        let elapsed = Date().timeIntervalSince(started)

        #expect(try firstHoldingName(in: data) == "File Public Co")
        #expect(elapsed >= 0.02)
        #expect(elapsed < 0.5)
    }

    @Test("Inline results still delete leftover session files")
    func inlineResultsStillDeleteLeftoverSessionFiles() throws {
        let fixture = try ToolResultFixture(delivery: .inline(createLeftover: true))
        defer { fixture.remove() }

        _ = try fixture.connection.callReadTool("pdt-get-portfolio-holdings", arguments: [:])

        let leftoverFile = try #require(fixture.runner.resultFiles.first)
        #expect(!FileManager.default.fileExists(atPath: leftoverFile.path))
    }

    @Test("A negative inline lookup does not poison later file delivery")
    func negativeInlineLookupDoesNotPoisonLaterFileDelivery() throws {
        let fixture = try ToolResultFixture(delivery: .inlineWithoutSessionThenImmediateFile)
        defer { fixture.remove() }

        let inlineData = try fixture.connection.callReadTool(
            "pdt-get-portfolio-holdings",
            arguments: [:]
        )
        let fileData = try fixture.connection.callReadTool(
            "pdt-get-portfolio-holdings",
            arguments: [:]
        )

        #expect(try firstHoldingName(in: inlineData) == "Inline Public Co")
        #expect(try firstHoldingName(in: fileData) == "File Public Co")
        #expect(fixture.connection.claudeProjectDirectoryDiscoveryCountForTesting == 2)
    }

    @Test("Project directory discovery is once-only under concurrent reads")
    func projectDirectoryDiscoveryIsOnceOnlyUnderConcurrentReads() async throws {
        let fixture = try ToolResultFixture(delivery: .inline(createLeftover: false))
        defer { fixture.remove() }

        let resultCount = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let data = try fixture.connection.callReadTool(
                        "pdt-get-portfolio-holdings",
                        arguments: [:]
                    )
                    return data.count
                }
            }
            var completed = 0
            for try await byteCount in group {
                #expect(byteCount > 0)
                completed += 1
            }
            return completed
        }

        #expect(resultCount == 16)
        #expect(fixture.connection.claudeProjectDirectoryDiscoveryCountForTesting == 1)
    }

    @Test("A stale cached project directory is rediscovered for file delivery")
    func staleCachedProjectDirectoryIsRediscoveredForFileDelivery() throws {
        let fixture = try ToolResultFixture(delivery: .staleCachedDirectoryThenMovedFile)
        defer { fixture.remove() }

        let inlineData = try fixture.connection.callReadTool(
            "pdt-get-portfolio-holdings",
            arguments: [:]
        )
        let fileData = try fixture.connection.callReadTool(
            "pdt-get-portfolio-holdings",
            arguments: [:]
        )

        #expect(try firstHoldingName(in: inlineData) == "Inline Public Co")
        #expect(try firstHoldingName(in: fileData) == "File Public Co")
    }

    @Test("Repeated inline results do not repeat project directory discovery")
    func repeatedInlineResultsDoNotRepeatProjectDirectoryDiscovery() throws {
        let fixture = try ToolResultFixture(delivery: .inline(createLeftover: false))
        defer { fixture.remove() }

        for _ in 0..<4 {
            let data = try fixture.connection.callReadTool(
                "pdt-get-portfolio-holdings",
                arguments: [:]
            )
            #expect(try firstHoldingName(in: data) == "Inline Public Co")
        }

        #expect(fixture.connection.claudeProjectDirectoryDiscoveryCountForTesting == 1)
    }

    @Test("A fallback read rediscovers a stale project directory at most once")
    func fallbackReadRediscoversStaleProjectDirectoryAtMostOnce() throws {
        let fixture = try ToolResultFixture(delivery: .staleCachedDirectoryThenMissingFile)
        defer { fixture.remove() }

        _ = try fixture.connection.callReadTool(
            "pdt-get-portfolio-holdings",
            arguments: [:]
        )
        let discoveryCountBeforeFallback =
            fixture.connection.claudeProjectDirectoryDiscoveryCountForTesting

        #expect(throws: Error.self) {
            _ = try fixture.connection.callReadTool(
                "pdt-get-portfolio-holdings",
                arguments: [:]
            )
        }
        #expect(
            fixture.connection.claudeProjectDirectoryDiscoveryCountForTesting
                == discoveryCountBeforeFallback + 1
        )
    }

    private func firstHoldingName(in data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let holdings = object?["holdings"] as? [[String: Any]]
        return holdings?.first?["symbolName"] as? String
    }
}

private final class ToolResultFixture: @unchecked Sendable {
    let root: URL
    let runner: ToolResultClaudeCommandRunner
    let connection: ClaudeLocalConnection

    init(delivery: ToolResultClaudeCommandRunner.Delivery) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-tool-result-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = ToolResultClaudeCommandRunner(root: root, delivery: delivery)
        connection = ClaudeLocalConnection(
            configuration: ClaudeLocalConnectionConfiguration(
                claudePath: "claude",
                model: "opus",
                toolTimeout: 10,
                readinessTimeout: 10,
                toolCallRetryPolicy: ClaudeToolCallRetryPolicy(retryCount: 0, retryBackoffSeconds: 0),
                environment: [:],
                claudeProjectsDirectory: root
            ),
            commandRunner: runner
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ToolResultClaudeCommandRunner: ClaudeLocalCommandRunning, @unchecked Sendable {
    enum Delivery: Sendable {
        case inline(createLeftover: Bool)
        case immediateFile
        case delayedFile(TimeInterval)
        case inlineWithoutSessionThenImmediateFile
        case staleCachedDirectoryThenMovedFile
        case staleCachedDirectoryThenMissingFile
    }

    private let root: URL
    private let delivery: Delivery
    private let lock = NSLock()
    private var readOrdinal = 0
    private var recordedResultFiles: [URL] = []

    init(root: URL, delivery: Delivery) {
        self.root = root
        self.delivery = delivery
    }

    var resultFiles: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedResultFiles
    }

    func executableExists(_ executable: String, environment: [String: String]) -> Bool {
        true
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> ClaudeLocalProcessResult {
        guard arguments.first == "--model" else {
            return ClaudeLocalProcessResult(
                stdout: "pdt (portfoliodividendtracker.com) connected",
                stderr: "",
                exitCode: 0
            )
        }
        let sessionID = try #require(argument(after: "--session-id", in: arguments))
        let ordinal = nextReadOrdinal()
        let toolResults = root
            .appending(path: "fixed-project")
            .appending(path: sessionID)
            .appending(path: "tool-results")

        let resultLine: String
        switch delivery {
        case .inline(let createLeftover):
            try FileManager.default.createDirectory(at: toolResults, withIntermediateDirectories: true)
            if createLeftover {
                let leftover = resultFile(in: toolResults, ordinal: ordinal)
                try Data(#"{"holdings":[{"symbolName":"Leftover Public Co"}]}"#.utf8)
                    .write(to: leftover)
                remember(resultFile: leftover)
            }
            resultLine = """
            {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Inline Public Co"}]}}
            """
        case .immediateFile:
            try FileManager.default.createDirectory(at: toolResults, withIntermediateDirectories: true)
            let file = resultFile(in: toolResults, ordinal: ordinal)
            try filePayload.write(to: file)
            remember(resultFile: file)
            resultLine = fileResultLine(file)
        case .delayedFile(let delay):
            try FileManager.default.createDirectory(at: toolResults, withIntermediateDirectories: true)
            let file = resultFile(in: toolResults, ordinal: ordinal)
            remember(resultFile: file)
            let payload = filePayload
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                try? payload.write(to: file)
            }
            resultLine = fileResultLine(file)
        case .inlineWithoutSessionThenImmediateFile:
            if ordinal == 1 {
                resultLine = """
                {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Inline Public Co"}]}}
                """
            } else {
                try FileManager.default.createDirectory(at: toolResults, withIntermediateDirectories: true)
                let file = resultFile(in: toolResults, ordinal: ordinal)
                try filePayload.write(to: file)
                remember(resultFile: file)
                resultLine = fileResultLine(file)
            }
        case .staleCachedDirectoryThenMovedFile:
            if ordinal == 1 {
                try FileManager.default.createDirectory(
                    at: toolResults,
                    withIntermediateDirectories: true
                )
                resultLine = """
                {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Inline Public Co"}]}}
                """
            } else {
                try FileManager.default.removeItem(at: root.appending(path: "fixed-project"))
                let movedToolResults = root
                    .appending(path: "moved-project")
                    .appending(path: sessionID)
                    .appending(path: "tool-results")
                try FileManager.default.createDirectory(
                    at: movedToolResults,
                    withIntermediateDirectories: true
                )
                let file = resultFile(in: movedToolResults, ordinal: ordinal)
                try filePayload.write(to: file)
                remember(resultFile: file)
                resultLine = fileResultLine(file)
            }
        case .staleCachedDirectoryThenMissingFile:
            if ordinal == 1 {
                try FileManager.default.createDirectory(
                    at: toolResults,
                    withIntermediateDirectories: true
                )
                resultLine = """
                {"type":"tool_result","tool_use_id":"call_1","structuredContent":{"holdings":[{"symbolName":"Inline Public Co"}]}}
                """
            } else {
                try FileManager.default.removeItem(at: root.appending(path: "fixed-project"))
                let missingFile = root
                    .appending(path: "missing-project")
                    .appending(path: sessionID)
                    .appending(path: "tool-results")
                    .appending(path: "pdt-get-portfolio-holdings-\(ordinal).txt")
                resultLine = fileResultLine(missingFile)
            }
        }
        return ClaudeLocalProcessResult(
            stdout: streamJSON(resultLine: resultLine),
            stderr: "",
            exitCode: 0
        )
    }

    private var filePayload: Data {
        Data(#"{"holdings":[{"symbolName":"File Public Co"}]}"#.utf8)
    }

    private func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func nextReadOrdinal() -> Int {
        lock.lock()
        defer { lock.unlock() }
        readOrdinal += 1
        return readOrdinal
    }

    private func remember(resultFile: URL) {
        lock.lock()
        recordedResultFiles.append(resultFile)
        lock.unlock()
    }

    private func resultFile(in directory: URL, ordinal: Int) -> URL {
        directory.appending(path: "pdt-get-portfolio-holdings-\(ordinal).txt")
    }

    private func fileResultLine(_ file: URL) -> String {
        let object: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": "call_1",
            "content": [[
                "type": "text",
                "text": "Tool result saved to \(file.path)",
            ]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func streamJSON(resultLine: String) -> String {
        """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"call_1","name":"mcp__pdt__pdt-get-portfolio-holdings"}]}}
        \(resultLine)
        {"type":"result","result":"{\\"status\\":\\"redacted-ok\\"}"}
        """
    }
}
