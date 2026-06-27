#if canImport(Darwin)
import Darwin
#endif
import Foundation
import PDTBarCore

public struct ClaudeLocalProcessResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol ClaudeLocalCommandRunning: Sendable {
    func executableExists(_ executable: String, environment: [String: String]) -> Bool
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> ClaudeLocalProcessResult
}

public struct ClaudeLocalConnectionConfiguration: Sendable {
    public var claudePath: String
    public var model: String
    public var toolTimeout: TimeInterval
    public var readinessTimeout: TimeInterval
    public var toolCallRetryPolicy: ClaudeToolCallRetryPolicy
    public var environment: [String: String]
    public var claudeProjectsDirectory: URL

    public init(
        claudePath: String,
        model: String,
        toolTimeout: TimeInterval,
        readinessTimeout: TimeInterval,
        toolCallRetryPolicy: ClaudeToolCallRetryPolicy,
        environment: [String: String],
        claudeProjectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    ) {
        self.claudePath = claudePath
        self.model = model
        self.toolTimeout = toolTimeout
        self.readinessTimeout = readinessTimeout
        self.toolCallRetryPolicy = toolCallRetryPolicy
        self.environment = environment
        self.claudeProjectsDirectory = claudeProjectsDirectory
    }

    public init(environment: [String: String]) {
        self.init(
            claudePath: environment["PDTBAR_CLAUDE_BIN"].flatMap { $0.nilIfEmpty } ?? "claude",
            model: environment["PDTBAR_CLAUDE_MODEL"].flatMap { $0.nilIfEmpty } ?? "opus",
            toolTimeout: environment["PDTBAR_CLAUDE_TOOL_TIMEOUT"].flatMap(Double.init) ?? 120.0,
            readinessTimeout: environment["PDTBAR_CLAUDE_READINESS_TIMEOUT"].flatMap(Double.init) ?? 20.0,
            toolCallRetryPolicy: ClaudeToolCallRetryPolicy(
                retryCount: environment["PDTBAR_CLAUDE_TOOL_RETRY_COUNT"].flatMap(Int.init) ?? 1
            ),
            environment: environment
        )
    }
}

public final class ClaudeLocalConnection: PDTMCPConnector {
    private let configuration: ClaudeLocalConnectionConfiguration
    private let commandRunner: any ClaudeLocalCommandRunning
    private let toolResultParser: ClaudeToolResultParser
    private let discoveredToolNamesLock = NSLock()
    private var discoveredToolNames: [String: String] = [:]

    public convenience init(environment: [String: String]) {
        self.init(configuration: ClaudeLocalConnectionConfiguration(environment: environment))
    }

    public init(
        configuration: ClaudeLocalConnectionConfiguration,
        commandRunner: any ClaudeLocalCommandRunning = DefaultClaudeLocalCommandRunner(),
        toolResultParser: ClaudeToolResultParser = ClaudeToolResultParser()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
        self.toolResultParser = toolResultParser
    }

    public func checkReadiness() -> ClaudeReadinessProbeResult {
        guard commandRunner.executableExists(configuration.claudePath, environment: configuration.environment) else {
            return .missingClaudeLogin
        }
        do {
            let authStatus = try commandRunner.run(
                executable: configuration.claudePath,
                arguments: ["auth", "status"],
                timeout: min(configuration.readinessTimeout, 10.0),
                environment: configuration.environment
            )
            let explicitAuthStatus = ClaudeAuthStatusParser.loggedInStatus(stdout: authStatus.stdout)
                ?? ClaudeAuthStatusParser.loggedInStatus(stdout: authStatus.stderr)
            if explicitAuthStatus == false {
                return .missingClaudeLogin
            }
            let result = try mcpList(timeout: configuration.readinessTimeout)
            if result.exitCode == 0, Self.pdtServerIsConnected(in: result.combinedOutput) {
                return .ready
            }
            guard result.exitCode == 0 else {
                return .missingClaudeLogin
            }
            return .missingPDTMCP
        } catch {
            return .failed
        }
    }

    public func availableReadTools() throws -> Set<String> {
        try availableReadTools(required: Set(PDTReadTools.requiredV1))
    }

    public func availableReadTools(required: Set<String>) throws -> Set<String> {
        guard commandRunner.executableExists(configuration.claudePath, environment: configuration.environment) else {
            throw PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")
        }
        let result = try mcpList(timeout: min(configuration.toolTimeout, 30.0))
        guard result.exitCode == 0, Self.pdtServerIsConnected(in: result.combinedOutput) else {
            throw PDTMCPConnectorError.setupUnavailable("Claude PDT MCP server is not connected")
        }
        let requiredReadTools = PDTReadTools.requiredV1.filter { required.contains($0) }
        let resolved = try resolvedToolNames(for: requiredReadTools)
        var available = Set(resolved.keys)
        for tool in requiredReadTools where !available.contains(tool) {
            if (try? resolvedToolName(for: tool)) != nil {
                available.insert(tool)
            }
        }
        return available
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        guard PDTReadTools.requiredV1.contains(name) else {
            throw PDTMCPConnectorError.nonReadTool(name)
        }
        guard commandRunner.executableExists(configuration.claudePath, environment: configuration.environment) else {
            throw PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")
        }
        let toolName = try resolvedToolName(for: name)
        var attempts = 0
        var lastError: Error?
        repeat {
            attempts += 1
            do {
                return try callReadToolOnce(name, resolvedToolName: toolName, arguments: arguments)
            } catch {
                lastError = error
                guard configuration.toolCallRetryPolicy.shouldRetry(error, afterAttempt: attempts) else {
                    throw error
                }
            }
        } while attempts < configuration.toolCallRetryPolicy.maxAttempts
        throw lastError ?? PDTMCPConnectorError.transientFailure("Claude \(name) call failed")
    }

    public static func pdtServerIsConnected(in output: String) -> Bool {
        output
            .split(separator: "\n")
            .contains { line in
                let lowercasedLine = line.lowercased()
                return lowercasedLine.contains("connected")
                    && !lowercasedLine.contains("not connected")
                    && !lowercasedLine.contains("disconnected")
                    && (
                        lowercasedLine.contains("portfolio dividend tracker")
                            || lowercasedLine.contains("portfoliodividendtracker.com")
                            || lowercasedLine.contains("pdt")
                    )
            }
    }

    private func mcpList(timeout: TimeInterval) throws -> ClaudeLocalProcessResult {
        try commandRunner.run(
            executable: configuration.claudePath,
            arguments: ["mcp", "list"],
            timeout: timeout,
            environment: configuration.environment
        )
    }

    private func resolvedToolName(for readToolName: String) throws -> String {
        if let cached = discoveredToolNameFromCache(for: readToolName) {
            return cached
        }
        if let resolved = try resolvedToolNames(for: [readToolName])[readToolName] {
            return resolved
        }
        throw PDTMCPConnectorError.setupUnavailable("Claude could not find \(readToolName)")
    }

    private func resolvedToolNames(for readToolNames: [String]) throws -> [String: String] {
        let cached = discoveredToolNamesSnapshot()
        let unresolved = readToolNames.filter { cached[$0] == nil }
        guard !unresolved.isEmpty else {
            return cached.filter { readToolNames.contains($0.key) }
        }
        let toolList = unresolved.joined(separator: ", ")
        var attempts = 0
        var lastResultExitCode: Int32 = 0
        repeat {
            attempts += 1
            let result = try runToolSearch(
                readToolNames: unresolved,
                prompt: "Use ToolSearch to find these PDT MCP read-only tools: \(toolList). Return only {\"status\":\"redacted-ok\"}."
            )
            lastResultExitCode = result.exitCode
            guard result.exitCode == 0 else {
                continue
            }
            mergeDiscoveredToolNames(discoveredToolNames(for: unresolved, in: result.stdout))
            if unresolved.allSatisfy({ discoveredToolNameFromCache(for: $0) != nil }) {
                break
            }
        } while attempts < configuration.toolCallRetryPolicy.maxAttempts
        for readToolName in unresolved where discoveredToolNameFromCache(for: readToolName) == nil {
            try resolveToolNameIndividually(readToolName)
        }
        let finalSnapshot = discoveredToolNamesSnapshot()
        let missing = unresolved.filter { finalSnapshot[$0] == nil }
        guard lastResultExitCode == 0 || missing.isEmpty else {
            throw PDTMCPConnectorError.setupUnavailable("Claude could not find \(toolList)")
        }
        return finalSnapshot.filter { readToolNames.contains($0.key) }
    }

    private func resolveToolNameIndividually(_ readToolName: String) throws {
        var attempts = 0
        repeat {
            attempts += 1
            let result = try runToolSearch(
                readToolNames: [readToolName],
                prompt: "Use ToolSearch to find exactly this PDT MCP read-only tool: \(readToolName). Return only {\"status\":\"redacted-ok\"}."
            )
            guard result.exitCode == 0 else {
                continue
            }
            mergeDiscoveredToolNames(discoveredToolNames(for: [readToolName], in: result.stdout))
            if discoveredToolNameFromCache(for: readToolName) != nil {
                break
            }
        } while attempts < configuration.toolCallRetryPolicy.maxAttempts
    }

    private func discoveredToolNameFromCache(for readToolName: String) -> String? {
        discoveredToolNamesLock.lock()
        defer {
            discoveredToolNamesLock.unlock()
        }
        return discoveredToolNames[readToolName]
    }

    private func discoveredToolNamesSnapshot() -> [String: String] {
        discoveredToolNamesLock.lock()
        defer {
            discoveredToolNamesLock.unlock()
        }
        return discoveredToolNames
    }

    private func mergeDiscoveredToolNames(_ newToolNames: [String: String]) {
        discoveredToolNamesLock.lock()
        discoveredToolNames.merge(newToolNames) { current, _ in current }
        discoveredToolNamesLock.unlock()
    }

    private func runToolSearch(readToolNames: [String], prompt: String) throws -> ClaudeLocalProcessResult {
        let sessionID = UUID().uuidString
        let result = try commandRunner.run(
            executable: configuration.claudePath,
            arguments: [
                "--model", configuration.model,
                "--allowedTools", "ToolSearch",
                "--disallowedTools", toolSearchDisallowedTools().joined(separator: ","),
                "--session-id", sessionID,
                "-p", prompt,
                "--output-format", "stream-json",
                "--verbose",
                "--no-session-persistence",
            ],
            timeout: min(configuration.toolTimeout, 60.0),
            environment: configuration.environment
        )
        let currentSessionFiles = currentSessionToolResultFiles(readToolNames: readToolNames, sessionID: sessionID)
        deleteClaudeToolResultFiles(pdtToolResultFiles(
            referencedBy: result.stdout,
            readToolNames: readToolNames,
            currentSessionFiles: currentSessionFiles
        ))
        return result
    }

    private func discoveredToolNames(for readToolNames: [String], in output: String) -> [String: String] {
        readToolNames.reduce(into: [String: String]()) { resolved, readToolName in
            if let toolName = discoveredToolName(for: readToolName, in: output) {
                resolved[readToolName] = toolName
            }
        }
    }

    private func discoveredToolName(for readToolName: String, in output: String) -> String? {
        let pattern = #"mcp__[A-Za-z0-9_.-]+__\#(NSRegularExpression.escapedPattern(for: readToolName))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return expression.matches(in: output, range: range).compactMap { match in
            Range(match.range, in: output).map { String(output[$0]) }
        }.first
    }

    private func callReadToolOnce(
        _ name: String,
        resolvedToolName toolName: String,
        arguments: [String: String]
    ) throws -> Data {
        let sessionID = UUID().uuidString
        let result = try commandRunner.run(
            executable: configuration.claudePath,
            arguments: [
                "--model", configuration.model,
                "--allowedTools", toolName,
                "--disallowedTools", disallowedTools().joined(separator: ","),
                "--session-id", sessionID,
                "-p", prompt(toolName: toolName, readToolName: name, arguments: arguments),
                "--output-format", "stream-json",
                "--verbose",
                "--no-session-persistence",
            ],
            timeout: configuration.toolTimeout,
            environment: configuration.environment
        )
        let currentSessionFiles = currentSessionToolResultFiles(readToolNames: [name], sessionID: sessionID)
        defer {
            deleteClaudeToolResultFiles(pdtToolResultFiles(
                referencedBy: result.stdout,
                readToolNames: [name],
                currentSessionFiles: currentSessionFiles
            ))
        }
        guard result.exitCode == 0 else {
            throw PDTMCPConnectorError.transientFailure("Claude \(name) call failed")
        }
        return try toolResultData(
            for: toolName,
            readToolName: name,
            currentSessionFiles: currentSessionFiles,
            in: result.stdout
        )
    }

    private func prompt(toolName: String, readToolName: String, arguments: [String: String]) -> String {
        let argumentData = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        let argumentJSON = String(decoding: argumentData, as: UTF8.self)
        return """
        PDTBar needs one local read-only PDT MCP result.

        Rules:
        - Call exactly this read-only PDT MCP tool: \(toolName)
        - This is the requested PDT read tool: \(readToolName)
        - Use exactly these JSON arguments: \(argumentJSON)
        - Do not call any write, create, update, delete, remove, post, put, or set tool.
        - Do not print holdings, values, account identifiers, endpoints, credentials, or raw tool output in your final answer.
        - After the tool call, return only {"status":"redacted-ok"}.
        """
    }

    private func disallowedTools() -> [String] {
        [
            "AskUserQuestion",
            "Bash",
            "CronCreate",
            "CronDelete",
            "CronList",
            "DesignSync",
            "Edit",
            "EnterPlanMode",
            "EnterWorktree",
            "ExitPlanMode",
            "ExitWorktree",
            "Monitor",
            "NotebookEdit",
            "PushNotification",
            "Read",
            "RemoteTrigger",
            "ScheduleWakeup",
            "Skill",
            "Task",
            "TaskCreate",
            "TaskGet",
            "TaskList",
            "TaskOutput",
            "TaskStop",
            "TaskUpdate",
            "WebFetch",
            "WebSearch",
            "Workflow",
            "Write",
            "mcp__*__pdt-add-*",
            "mcp__*__pdt-create-*",
            "mcp__*__pdt-delete-*",
            "mcp__*__pdt-patch-*",
            "mcp__*__pdt-post-*",
            "mcp__*__pdt-put-*",
            "mcp__*__pdt-remove-*",
            "mcp__*__pdt-set-*",
            "mcp__*__pdt-update-*",
        ]
    }

    private func toolSearchDisallowedTools() -> [String] {
        disallowedTools().filter { !$0.hasPrefix("mcp__") }
    }

    private func toolResultData(
        for toolName: String,
        readToolName: String,
        currentSessionFiles: Set<URL>,
        in output: String
    ) throws -> Data {
        do {
            return try toolResultParser.resultData(
                for: toolName,
                readToolName: readToolName,
                output: output,
                currentSessionResultFiles: currentSessionFiles
            )
        } catch ClaudeToolResultParserError.missingToolCall {
            throw PDTMCPConnectorError.transientFailure("Claude did not call \(toolName)")
        } catch {
            throw PDTMCPConnectorError.transientFailure("Claude did not return structured data for \(toolName)")
        }
    }

    private func claudeToolResultFiles(sessionID: String? = nil) -> Set<URL> {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: configuration.claudeProjectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files = Set<URL>()
        for project in projects {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            let sessionDirectories: [URL]
            if let sessionID {
                sessionDirectories = [project.appending(path: sessionID)]
            } else {
                sessionDirectories = (try? FileManager.default.contentsOfDirectory(
                    at: project,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            for sessionDirectory in sessionDirectories {
                let toolResults = sessionDirectory.appending(path: "tool-results")
                guard let toolFiles = try? FileManager.default.contentsOfDirectory(
                    at: toolResults,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                files.formUnion(toolFiles.filter { $0.pathExtension == "txt" })
            }
        }
        return files
    }

    private func currentSessionToolResultFiles(readToolNames: [String], sessionID: String) -> Set<URL> {
        let deadline = Date().addingTimeInterval(1.0)
        var sessionFiles = Set<URL>()
        repeat {
            sessionFiles = claudeToolResultFiles(sessionID: sessionID)
            if sessionFiles.contains(where: { file in
                readToolNames.contains { file.lastPathComponent.contains($0) }
            }) {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return sessionFiles
    }

    private func pdtToolResultFiles(
        referencedBy output: String,
        readToolNames: [String],
        currentSessionFiles: Set<URL>
    ) -> [URL] {
        toolResultParser.cleanupResultFiles(
            output: output,
            readToolNames: readToolNames,
            currentSessionResultFiles: currentSessionFiles
        )
    }

    private func deleteClaudeToolResultFiles(_ files: [URL]) {
        for file in Set(files) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

public struct DefaultClaudeLocalCommandRunner: ClaudeLocalCommandRunning {
    public init() {}

    public func executableExists(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        resolvedExecutable(executable, environment: environment) != nil
    }

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> ClaudeLocalProcessResult {
        guard let resolvedExecutable = resolvedExecutable(executable, environment: environment) else {
            return ClaudeLocalProcessResult(stdout: "", stderr: "\(executable) not found", exitCode: -1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = arguments
        let workingDirectory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-claude-cli")
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        process.currentDirectoryURL = workingDirectory
        var processEnvironment = environment
        processEnvironment["PATH"] = Self.executableSearchDirectories(environment: environment).joined(separator: ":")
        process.environment = processEnvironment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutData = LockedDataAccumulator()
        let stderrData = LockedDataAccumulator()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData.append(stdout.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData.append(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        try process.run()
        let processGroup = setProcessGroup(process.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            let descendants = ClaudeLocalProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
            process.terminate()
            ClaudeLocalProcessTreeTerminator.terminateProcessTree(
                rootPID: process.processIdentifier,
                processGroup: processGroup,
                signal: SIGTERM,
                knownDescendants: descendants
            )
            let waitDeadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < waitDeadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                ClaudeLocalProcessTreeTerminator.terminateProcessTree(
                    rootPID: process.processIdentifier,
                    processGroup: processGroup,
                    signal: SIGKILL,
                    knownDescendants: descendants
                )
            }
            process.waitUntilExit()
            readers.wait()
            return ClaudeLocalProcessResult(
                stdout: String(decoding: stdoutData.snapshot(), as: UTF8.self),
                stderr: String(decoding: stderrData.snapshot(), as: UTF8.self),
                exitCode: -1
            )
        }
        process.waitUntilExit()
        readers.wait()
        return ClaudeLocalProcessResult(
            stdout: String(decoding: stdoutData.snapshot(), as: UTF8.self),
            stderr: String(decoding: stderrData.snapshot(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func resolvedExecutable(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }
        for directory in Self.executableSearchDirectories(environment: environment) {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func executableSearchDirectories(environment: [String: String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (pathDirectories + defaults).filter { directory in
            seen.insert(directory).inserted
        }
    }
}

public enum ClaudeLocalLoginPhase: Sendable {
    case requesting
    case waitingBrowser
}

public enum ClaudeLocalLoginOutcome: Sendable, Equatable {
    case success
    case failed(ClaudeLoginFailureReason, String)
    case cancelled
}

public final class ClaudeLocalLoginCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return cancelled
    }
}

public struct ClaudeLocalLoginRunner: Sendable {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(
        timeout: TimeInterval = 120,
        cancellation: ClaudeLocalLoginCancellation = ClaudeLocalLoginCancellation(),
        onPhaseChange: @escaping @Sendable (ClaudeLocalLoginPhase) -> Void
    ) async -> ClaudeLocalLoginOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(
                    timeout: timeout,
                    environment: environment,
                    cancellation: cancellation,
                    onPhaseChange: onPhaseChange
                ))
            }
        }
    }

    private static func runBlocking(
        timeout: TimeInterval,
        environment: [String: String],
        cancellation: ClaudeLocalLoginCancellation,
        onPhaseChange: @escaping @Sendable (ClaudeLocalLoginPhase) -> Void
    ) -> ClaudeLocalLoginOutcome {
        onPhaseChange(.requesting)
        do {
            let runResult = try runPTY(
                timeout: timeout,
                environment: environment,
                cancellation: cancellation,
                onPhaseChange: onPhaseChange
            )
            if runResult.terminationStatus == 0 || outputLooksSuccessful(runResult.text) {
                return .success
            }
            if let status = runResult.terminationStatus {
                return .failed(.failed, "claude auth login exited with status \(status)")
            }
            return .failed(.timedOut, "Claude login timed out")
        } catch TTYCommandRunner.Error.binaryNotFound {
            return .failed(.missingBinary, "Claude CLI not found")
        } catch TTYCommandRunner.Error.timedOut {
            return .failed(.timedOut, "Claude login timed out")
        } catch TTYCommandRunner.Error.cancelled {
            return .cancelled
        } catch {
            if cancellation.isCancelled {
                return .cancelled
            }
            return .failed(.launchFailed, error.localizedDescription)
        }
    }

    private static func runPTY(
        timeout: TimeInterval,
        environment: [String: String],
        cancellation: ClaudeLocalLoginCancellation,
        onPhaseChange: @escaping @Sendable (ClaudeLocalLoginPhase) -> Void
    ) throws -> TTYCommandRunner.Result {
        guard !cancellation.isCancelled else {
            throw TTYCommandRunner.Error.cancelled
        }
        let successSubstrings = [
            "Successfully logged in",
            "Login successful",
            "Logged in successfully",
            "Authentication successful",
            "Authentication complete",
            "Successfully authenticated",
            "Authenticated successfully",
        ]
        var options = TTYCommandRunner.Options(
            rows: 50,
            cols: 160,
            timeout: timeout,
            baseEnvironment: environment
        )
        options.extraArgs = ["auth", "login"]
        options.stopOnURL = false
        options.stopOnSubstrings = successSubstrings
        options.sendOnSubstrings = [
            "Enter to open": "\r",
            "enter to open": "\r",
            "Return to open": "\r",
            "return to open": "\r",
            "Press Enter to open": "\r",
            "press Enter to open": "\r",
            "press enter to open": "\r",
            "Press Return to open": "\r",
            "press Return to open": "\r",
            "press return to open": "\r",
            "Press Enter": "\r",
            "press Enter": "\r",
            "press enter": "\r",
            "Press Return": "\r",
            "press Return": "\r",
            "press return": "\r",
        ]
        options.sendEnterEvery = 1.0
        options.settleAfterStop = 0.35
        options.debugLogPath = environment["PDTBAR_CLAUDE_LOGIN_DEBUG_LOG"]?.nilIfEmpty
        return try TTYCommandRunner().run(
            binary: environment["PDTBAR_CLAUDE_BIN"]?.nilIfEmpty ?? "claude",
            send: "",
            options: options,
            isCancelled: { cancellation.isCancelled },
            onURLDetected: { onPhaseChange(.waitingBrowser) }
        )
    }

    private static func outputLooksSuccessful(_ text: String) -> Bool {
        let normalized = TTYCommandRunner.normalizedNeedleText(text)
        let successNeedles = [
            "successfully logged in",
            "login successful",
            "logged in successfully",
            "authentication successful",
            "authentication complete",
            "successfully authenticated",
            "authenticated successfully",
        ]
        return successNeedles.contains { normalized.contains($0) }
    }
}

private final class LockedDataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer {
            lock.unlock()
        }
        return data
    }
}

private struct TTYCommandRunner {
    struct Result: Sendable {
        let text: String
        let terminationStatus: Int32?
    }

    struct Options: Sendable {
        var rows: UInt16 = 50
        var cols: UInt16 = 160
        var timeout: TimeInterval = 20.0
        var idleTimeout: TimeInterval?
        var workingDirectory: URL?
        var extraArgs: [String] = []
        var baseEnvironment: [String: String]?
        var initialDelay: TimeInterval = 0.4
        var sendEnterEvery: TimeInterval?
        var sendOnSubstrings: [String: String] = [:]
        var stopOnURL = false
        var stopOnSubstrings: [String] = []
        var settleAfterStop: TimeInterval = 0.25
        var debugLogPath: String?
    }

    enum Error: Swift.Error, LocalizedError, Sendable {
        case binaryNotFound(String)
        case launchFailed(String)
        case timedOut
        case cancelled

        var errorDescription: String? {
            switch self {
            case let .binaryNotFound(bin):
                "Missing CLI '\(bin)'. Install it or add it to PATH."
            case let .launchFailed(msg):
                "Failed to launch process: \(msg)"
            case .timedOut:
                "PTY command timed out."
            case .cancelled:
                "PTY command cancelled."
            }
        }
    }

    private struct RollingBuffer {
        private let maxNeedle: Int
        private var tail = Data()

        init(maxNeedle: Int) {
            self.maxNeedle = max(0, maxNeedle)
        }

        mutating func append(_ data: Data) -> Data {
            guard !data.isEmpty else { return Data() }
            var combined = Data()
            combined.reserveCapacity(tail.count + data.count)
            combined.append(tail)
            combined.append(data)
            if maxNeedle > 1 {
                tail = combined.count >= maxNeedle - 1 ? combined.suffix(maxNeedle - 1) : combined
            } else {
                tail.removeAll(keepingCapacity: true)
            }
            return combined
        }
    }

    private enum DrainReadResult {
        case data(Data)
        case wouldBlock
        case closed
    }

    private final class DebugLog: @unchecked Sendable {
        private let url: URL
        private let lock = NSLock()

        init?(path: String?) {
            guard let path, !path.isEmpty else { return nil }
            self.url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: self.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            append("debug log started")
        }

        func append(_ message: String) {
            let line = "\(Self.timestamp()) \(Self.redact(message))\n"
            guard let data = line.data(using: .utf8) else { return }
            lock.lock()
            defer {
                lock.unlock()
            }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url)
            {
                defer {
                    try? handle.close()
                }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }

        private static func timestamp() -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: Date())
        }

        private static func redact(_ text: String) -> String {
            var redacted = text
            redacted = redacted.replacingOccurrences(
                of: #"https?://\S+"#,
                with: "[redacted-url]",
                options: .regularExpression
            )
            redacted = redacted.replacingOccurrences(
                of: #"[A-Za-z0-9_\-]{40,}"#,
                with: "[redacted-token]",
                options: .regularExpression
            )
            return redacted
        }
    }

    func run(
        binary: String,
        send script: String,
        options: Options = Options(),
        isCancelled: (@Sendable () -> Bool)? = nil,
        onURLDetected: (@Sendable () -> Void)? = nil
    ) throws -> Result {
        if isCancelled?() == true {
            throw Error.cancelled
        }
        let debugLog = DebugLog(path: options.debugLogPath)
        let resolved: String
        if binary.contains("/"), FileManager.default.isExecutableFile(atPath: binary) {
            resolved = binary
        } else if let hit = Self.which(binary, environment: options.baseEnvironment ?? ProcessInfo.processInfo.environment) {
            resolved = hit
        } else {
            debugLog?.append("binary not found: \(binary)")
            throw Error.binaryNotFound(binary)
        }
        debugLog?.append("launching \(resolved) \(options.extraArgs.joined(separator: " "))")

        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: options.rows, ws_col: options.cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw Error.launchFailed("openpty failed")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        func writeAllToPrimary(_ data: Data) throws {
            try data.withUnsafeBytes { rawBytes in
                guard let baseAddress = rawBytes.baseAddress else { return }
                var offset = 0
                var retries = 0
                while offset < rawBytes.count {
                    let written = write(primaryFD, baseAddress.advanced(by: offset), rawBytes.count - offset)
                    if written > 0 {
                        offset += written
                        retries = 0
                        continue
                    }
                    if written == 0 { break }
                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK {
                        retries += 1
                        if retries > 200 {
                            throw Error.launchFailed("write to PTY would block")
                        }
                        usleep(5000)
                        continue
                    }
                    throw Error.launchFailed("write to PTY failed: \(String(cString: strerror(err)))")
                }
            }
        }

        let baseEnv = options.baseEnvironment ?? ProcessInfo.processInfo.environment
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolved)
        proc.arguments = options.extraArgs
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle
        var env = Self.enrichedEnvironment(baseEnv: baseEnv, home: baseEnv["HOME"] ?? NSHomeDirectory())
        if let workingDirectory = options.workingDirectory {
            proc.currentDirectoryURL = workingDirectory
            env["PWD"] = workingDirectory.path
        }
        proc.environment = env

        var cleanedUp = false
        var didLaunch = false
        var processGroup: pid_t?
        func cleanup() {
            guard !cleanedUp else { return }
            if didLaunch, proc.isRunning {
                try? writeAllToPrimary(Data("/exit\n".utf8))
            }
            try? primaryHandle.close()
            try? secondaryHandle.close()
            guard didLaunch else {
                cleanedUp = true
                return
            }
            let descendants = ClaudeLocalProcessTreeTerminator.descendantPIDs(of: proc.processIdentifier)
            if proc.isRunning {
                proc.terminate()
            }
            ClaudeLocalProcessTreeTerminator.terminateProcessTree(
                rootPID: proc.processIdentifier,
                processGroup: processGroup,
                signal: SIGTERM,
                knownDescendants: descendants
            )
            let waitDeadline = Date().addingTimeInterval(2.0)
            while proc.isRunning, Date() < waitDeadline {
                usleep(100_000)
            }
            if proc.isRunning {
                ClaudeLocalProcessTreeTerminator.terminateProcessTree(
                    rootPID: proc.processIdentifier,
                    processGroup: processGroup,
                    signal: SIGKILL,
                    knownDescendants: descendants
                )
            } else {
                for pid in descendants where pid > 0 {
                    kill(pid, SIGKILL)
                }
            }
            if didLaunch {
                proc.waitUntilExit()
            }
            cleanedUp = true
        }

        defer { cleanup() }

        do {
            try proc.run()
            didLaunch = true
            debugLog?.append("process launched pid=\(proc.processIdentifier)")
        } catch {
            debugLog?.append("launch failed: \(error.localizedDescription)")
            throw Error.launchFailed(error.localizedDescription)
        }

        let pid = proc.processIdentifier
        if setpgid(pid, pid) == 0 {
            processGroup = pid
        }

        func send(_ text: String) throws {
            guard let data = text.data(using: .utf8) else { return }
            try writeAllToPrimary(data)
        }

        let deadline = Date().addingTimeInterval(options.timeout)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)

        var buffer = Data()
        func readChunkResult() -> (data: Data, terminalRead: Int, errno: Int32) {
            var appended = Data()
            var terminalRead = 0
            var terminalErrno: Int32 = 0
            while true {
                var tmp = [UInt8](repeating: 0, count: 8192)
                errno = 0
                let n = read(primaryFD, &tmp, tmp.count)
                if n > 0 {
                    let slice = tmp.prefix(n)
                    buffer.append(contentsOf: slice)
                    appended.append(contentsOf: slice)
                    continue
                }
                terminalRead = Int(n)
                terminalErrno = errno
                break
            }
            return (appended, terminalRead, terminalErrno)
        }

        func readChunk() -> Data {
            readChunkResult().data
        }

        func readDrainChunk() -> DrainReadResult {
            let result = readChunkResult()
            return Self.drainReadResult(for: result.data, terminalRead: result.terminalRead, errno: result.errno)
        }

        let cursorQuery = Data([0x1B, 0x5B, 0x36, 0x6E])

        usleep(UInt32(options.initialDelay * 1_000_000))

        if isCancelled?() == true {
            debugLog?.append("cancelled before initial send")
            throw Error.cancelled
        }
        if !trimmed.isEmpty {
            try send(trimmed)
            try send("\r")
            debugLog?.append("sent initial script")
        }

        let stopNeedles = options.stopOnSubstrings.map { Data($0.utf8) }
        let sendNeedles = options.sendOnSubstrings.map {
            (needle: Data($0.key.utf8), needleString: $0.key, keys: Data($0.value.utf8))
        }
        let urlNeedles = [Data("https://".utf8), Data("http://".utf8)]
        let needleLengths =
            stopNeedles.map(\.count) +
            sendNeedles.map(\.needle.count) +
            urlNeedles.map(\.count) +
            [cursorQuery.count]
        let maxNeedle = needleLengths.max() ?? cursorQuery.count
        var scanBuffer = RollingBuffer(maxNeedle: maxNeedle)
        var nextCursorCheckAt = Date(timeIntervalSince1970: 0)
        var lastEnter = Date()
        var stoppedEarly = false
        var urlSeen = false
        var triggeredSends = Set<Data>()
        var triggeredSendPayloads = Set<Data>()
        var sentAuthPromptEnter = false
        var recentText = ""
        var lastOutputAt = Date()

        func processChunk(_ newData: Data, allowSends: Bool, allowStop: Bool) -> Bool {
            guard !newData.isEmpty else { return false }

            lastOutputAt = Date()
            if let chunkText = String(bytes: newData, encoding: .utf8) {
                recentText += chunkText
                if recentText.count > 8192 {
                    recentText.removeFirst(recentText.count - 8192)
                }
            }

            let scanData = scanBuffer.append(newData)
            if Date() >= nextCursorCheckAt,
               scanData.range(of: cursorQuery) != nil
            {
                try? send("\u{1b}[1;1R")
                nextCursorCheckAt = Date().addingTimeInterval(1.0)
            }

            if allowSends, !sendNeedles.isEmpty {
                let recentTextCollapsed = recentText.replacingOccurrences(of: "\r", with: "")
                let recentTextNormalized = Self.normalizedNeedleText(recentText)
                for item in sendNeedles where !triggeredSends.contains(item.needle) {
                    let matched = scanData.range(of: item.needle) != nil ||
                        recentText.contains(item.needleString) ||
                        recentTextCollapsed.contains(item.needleString) ||
                        recentTextNormalized.contains(Self.normalizedNeedleText(item.needleString))
                    if matched {
                        if triggeredSendPayloads.insert(item.keys).inserted {
                            if let keysString = String(data: item.keys, encoding: .utf8) {
                                try? send(keysString)
                            } else {
                                try? writeAllToPrimary(item.keys)
                            }
                            sentAuthPromptEnter = true
                            debugLog?.append("matched send substring: \(item.needleString)")
                        }
                        triggeredSends.insert(item.needle)
                    }
                }
            }

            if urlNeedles.contains(where: { scanData.range(of: $0) != nil }) {
                if !urlSeen {
                    urlSeen = true
                    onURLDetected?()
                    if !sentAuthPromptEnter, !Self.looksLikeCodeEntryPrompt(recentText) {
                        try? send("\r")
                        sentAuthPromptEnter = true
                        debugLog?.append("url detected; sent fallback enter")
                    }
                    debugLog?.append("url detected")
                    lastEnter = Date()
                }
                if allowStop, options.stopOnURL {
                    return true
                }
            }

            if allowStop, !stopNeedles.isEmpty {
                let recentTextNormalized = Self.normalizedNeedleText(recentText)
                for index in stopNeedles.indices {
                    if scanData.range(of: stopNeedles[index]) != nil ||
                        recentTextNormalized.contains(Self.normalizedNeedleText(options.stopOnSubstrings[index]))
                    {
                        return true
                    }
                }
            }

            return false
        }

        while Date() < deadline {
            if isCancelled?() == true {
                debugLog?.append("cancelled")
                throw Error.cancelled
            }
            let readResult = readDrainChunk()
            let newData = switch readResult {
            case let .data(data):
                data
            case .wouldBlock, .closed:
                Data()
            }
            if !newData.isEmpty {
                debugLog?.append("output chunk bytes=\(newData.count)")
            }
            if processChunk(newData, allowSends: true, allowStop: true) {
                stoppedEarly = true
                break
            }
            if let idleTimeout = options.idleTimeout,
               !buffer.isEmpty,
               Date().timeIntervalSince(lastOutputAt) >= idleTimeout
            {
                stoppedEarly = true
                break
            }

            if !urlSeen, let every = options.sendEnterEvery, Date().timeIntervalSince(lastEnter) >= every {
                try? send("\r")
                debugLog?.append("sent periodic enter")
                lastEnter = Date()
            }

            if case .closed = readResult, !proc.isRunning { break }
            if !proc.isRunning { break }
            usleep(60000)
        }

        if isCancelled?() == true {
            debugLog?.append("cancelled after loop")
            throw Error.cancelled
        }

        if stoppedEarly {
            let settle = max(0, min(options.settleAfterStop, deadline.timeIntervalSinceNow))
            if settle > 0 {
                let settleDeadline = Date().addingTimeInterval(settle)
                while Date() < settleDeadline {
                    let newData = readChunk()
                    let scanData = scanBuffer.append(newData)
                    if Date() >= nextCursorCheckAt,
                       !scanData.isEmpty,
                       scanData.range(of: cursorQuery) != nil
                    {
                        try? send("\u{1b}[1;1R")
                        nextCursorCheckAt = Date().addingTimeInterval(1.0)
                    }
                    usleep(50000)
                }
            }
        } else if !proc.isRunning {
            let drainFor = max(0, min(0.2, deadline.timeIntervalSinceNow))
            if drainFor > 0 {
                Self.drainRemainingOutput(
                    until: Date().addingTimeInterval(drainFor),
                    readChunk: readDrainChunk,
                    processChunk: { _ = processChunk($0, allowSends: false, allowStop: false) }
                )
            }
        }

        let terminationStatus = proc.isRunning ? nil : proc.terminationStatus
        debugLog?.append("finished running=\(proc.isRunning) status=\(terminationStatus.map(String.init) ?? "nil")")
        let text = String(data: buffer, encoding: .utf8) ?? ""
        if text.isEmpty, let terminationStatus {
            return Result(text: text, terminationStatus: terminationStatus)
        }
        guard !text.isEmpty else {
            debugLog?.append("timed out with empty output")
            throw Error.timedOut
        }
        return Result(text: text, terminationStatus: terminationStatus)
    }

    private static func drainRemainingOutput(
        until drainDeadline: Date,
        readChunk: () -> DrainReadResult,
        processChunk: (Data) -> Void
    ) {
        while Date() < drainDeadline {
            switch readChunk() {
            case let .data(newData):
                processChunk(newData)
            case .wouldBlock:
                usleep(20000)
            case .closed:
                return
            }
        }
    }

    private static func drainReadResult(for data: Data, terminalRead: Int, errno err: Int32) -> DrainReadResult {
        if !data.isEmpty { return .data(data) }

        if terminalRead == 0 {
            return .closed
        }

        if terminalRead < 0 {
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                return .wouldBlock
            }
            if err == EIO {
                return .closed
            }
        }

        return .closed
    }

    static func normalizedNeedleText(_ text: String) -> String {
        let withoutCarriageReturns = text.replacingOccurrences(of: "\r", with: "")
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return withoutCarriageReturns.lowercased()
        }
        let range = NSRange(withoutCarriageReturns.startIndex..<withoutCarriageReturns.endIndex, in: withoutCarriageReturns)
        return regex
            .stringByReplacingMatches(in: withoutCarriageReturns, options: [], range: range, withTemplate: "")
            .lowercased()
    }

    private static func looksLikeCodeEntryPrompt(_ text: String) -> Bool {
        let normalized = normalizedNeedleText(text)
        let codeNeedles = [
            "paste code",
            "paste the code",
            "paste your code",
            "code here",
            "enter code",
            "enter the code",
            "authorization code",
            "if prompted",
        ]
        return codeNeedles.contains { normalized.contains($0) }
    }

    private static func which(_ binary: String, environment: [String: String]) -> String? {
        DefaultClaudeLocalCommandRunner.executableSearchDirectories(environment: environment)
            .map { "\($0)/\(binary)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func enrichedEnvironment(baseEnv: [String: String], home: String) -> [String: String] {
        var env = baseEnv
        env["PATH"] = DefaultClaudeLocalCommandRunner.executableSearchDirectories(environment: baseEnv).joined(separator: ":")
        if env["HOME"]?.isEmpty ?? true {
            env["HOME"] = home
        }
        if env["TERM"]?.isEmpty ?? true {
            env["TERM"] = "xterm-256color"
        }
        if env["COLORTERM"]?.isEmpty ?? true {
            env["COLORTERM"] = "truecolor"
        }
        if env["LANG"]?.isEmpty ?? true {
            env["LANG"] = "en_US.UTF-8"
        }
        return env
    }
}

private struct ClaudeLocalProcessTreeTerminator {
    static func descendantPIDs(of rootPID: pid_t) -> [pid_t] {
        guard rootPID > 0 else { return [] }
        var seen: Set<pid_t> = [rootPID]
        var pending = currentChildPIDs(of: rootPID)
        var descendants: [pid_t] = []

        while let pid = pending.popLast() {
            guard pid > 0, seen.insert(pid).inserted else { continue }
            descendants.append(pid)
            pending.append(contentsOf: currentChildPIDs(of: pid))
        }

        return descendants
    }

    static func currentChildPIDs(of parentPID: pid_t) -> [pid_t] {
        guard parentPID > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: 128)
        let byteCount = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let childCount = proc_listchildpids(parentPID, &pids, byteCount)
        guard childCount > 0 else { return [] }
        return Array(pids.prefix(min(Int(childCount), pids.count))).filter { $0 > 0 }
    }

    static func terminateProcessTree(
        rootPID: pid_t,
        processGroup: pid_t?,
        signal: Int32,
        knownDescendants: [pid_t] = []
    ) {
        guard rootPID > 0 else { return }

        var seen: Set<pid_t> = [rootPID]
        let descendants = knownDescendants + descendantPIDs(of: rootPID)
        for pid in descendants where pid > 0 && seen.insert(pid).inserted {
            kill(pid, signal)
        }
        if let processGroup {
            kill(-processGroup, signal)
        }
        kill(rootPID, signal)
    }
}

private func setProcessGroup(_ pid: pid_t) -> pid_t? {
    setpgid(pid, pid) == 0 ? pid : nil
}

private extension ClaudeLocalProcessResult {
    var combinedOutput: String {
        stdout + "\n" + stderr
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
