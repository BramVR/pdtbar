#if canImport(Darwin)
import Darwin
#endif
import Foundation
import PDTBarCore

public struct DefaultClaudeLocalCommandRunner: ClaudeLocalCommandRunning {
    /// How long a finished (exited or killed) run waits for the pipe drains
    /// to reach end-of-file before abandoning them.
    private static let drainGracePeriod: TimeInterval = 1.0
    private enum DrainOutcome {
        case finished
        case cancelled
        case timedOut
    }

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
        try run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment,
            cancellation: nil
        )
    }

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String],
        cancellation: PDTCancellation?
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
        guard cancellation?.isCancelled != true else {
            return ClaudeLocalProcessResult(stdout: "", stderr: "", exitCode: -1)
        }
        try process.run()
        let stdoutDrain = ClaudeLocalPipeDrain(pipe: stdout)
        let stderrDrain = ClaudeLocalPipeDrain(pipe: stderr)
        let processGroup = setProcessGroup(process.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        var latestDescendants = ClaudeLocalProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
        while process.isRunning,
              Date() < deadline,
              cancellation?.isCancelled != true
        {
            let currentDescendants = ClaudeLocalProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
            if !currentDescendants.isEmpty || process.isRunning {
                latestDescendants = currentDescendants
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            let descendants = ClaudeLocalProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
            terminateProcessTree(process, processGroup: processGroup, descendants: descendants)
            _ = finishDrains(
                stdoutDrain,
                stderrDrain,
                deadline: Date().addingTimeInterval(Self.drainGracePeriod),
                cancellation: nil
            )
            return ClaudeLocalProcessResult(
                stdout: String(decoding: stdoutDrain.snapshot(), as: UTF8.self),
                stderr: String(decoding: stderrDrain.snapshot(), as: UTF8.self),
                exitCode: -1
            )
        }
        process.waitUntilExit()
        let terminationStatus = process.terminationStatus
        let drainOutcome = finishDrains(
            stdoutDrain,
            stderrDrain,
            deadline: Date().addingTimeInterval(Self.drainGracePeriod),
            cancellation: cancellation
        )
        if drainOutcome == .cancelled {
            terminateProcessTree(process, processGroup: processGroup, descendants: latestDescendants)
            _ = finishDrains(
                stdoutDrain,
                stderrDrain,
                deadline: Date().addingTimeInterval(Self.drainGracePeriod),
                cancellation: nil
            )
            return ClaudeLocalProcessResult(
                stdout: String(decoding: stdoutDrain.snapshot(), as: UTF8.self),
                stderr: String(decoding: stderrDrain.snapshot(), as: UTF8.self),
                exitCode: -1
            )
        }
        return ClaudeLocalProcessResult(
            stdout: String(decoding: stdoutDrain.snapshot(), as: UTF8.self),
            stderr: String(decoding: stderrDrain.snapshot(), as: UTF8.self),
            exitCode: terminationStatus
        )
    }

    private func terminateProcessTree(
        _ process: Process,
        processGroup: pid_t?,
        descendants: [pid_t]
    ) {
        if process.isRunning {
            process.terminate()
        }
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
        ClaudeLocalProcessTreeTerminator.terminateProcessTree(
            rootPID: process.processIdentifier,
            processGroup: processGroup,
            signal: SIGKILL,
            knownDescendants: descendants
        )
        process.waitUntilExit()
    }

    /// Joins the pipe drains without trusting the child's process tree to
    /// release the pipes. A descendant that survived the process exit or
    /// escaped the kill sweep (for example one spawned between the descendant
    /// scan and the signals, or before setpgid took effect) keeps the pipe
    /// write ends open, so a drain never sees end-of-file and an unbounded
    /// join would hang `run()` — and the menu's fetch state — forever. The
    /// exited process already wrote everything it had to say, and buffered
    /// output is readable immediately, so a short grace period after exit
    /// keeps healthy runs complete; anything still open at the deadline is
    /// abandoned with whatever output was captured so far.
    private func finishDrains(
        _ stdoutDrain: ClaudeLocalPipeDrain,
        _ stderrDrain: ClaudeLocalPipeDrain,
        deadline: Date,
        cancellation: PDTCancellation?
    ) -> DrainOutcome {
        while Date() < deadline {
            if cancellation?.isCancelled == true {
                return .cancelled
            }
            let pollDeadline = min(deadline, Date().addingTimeInterval(0.05))
            let stdoutFinished = stdoutDrain.waitUntilFinished(deadline: pollDeadline)
            let stderrFinished = stderrDrain.waitUntilFinished(deadline: pollDeadline)
            if stdoutFinished, stderrFinished {
                return .finished
            }
        }
        stdoutDrain.abandon()
        stderrDrain.abandon()
        return .timedOut
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
