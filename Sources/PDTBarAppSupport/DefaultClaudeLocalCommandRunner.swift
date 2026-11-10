#if canImport(Darwin)
import Darwin
#endif
import Foundation
import PDTBarCore

public struct DefaultClaudeLocalCommandRunner: ClaudeLocalCommandRunning {
    /// How long a finished (exited or killed) run waits for the pipe drains
    /// to reach end-of-file before abandoning them.
    private static let drainGracePeriod: TimeInterval = 1.0

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
        let workingDirectory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-claude-cli")
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        var processEnvironment = environment
        processEnvironment["PATH"] = Self.executableSearchDirectories(environment: environment).joined(separator: ":")
        guard cancellation?.isCancelled != true else {
            return ClaudeLocalProcessResult(stdout: "", stderr: "", exitCode: -1)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        let child = try ChildProcessGroup.spawn(ChildLaunch(
            executable: resolvedExecutable,
            arguments: arguments,
            environment: processEnvironment,
            workingDirectory: workingDirectory,
            stdio: .pipes(stdout: stdout, stderr: stderr)
        ))
        let stdoutDrain = ClaudeLocalPipeDrain(pipe: stdout)
        let stderrDrain = ClaudeLocalPipeDrain(pipe: stderr)
        let deadline = Date().addingTimeInterval(timeout)
        while child.isRunning,
              Date() < deadline,
              cancellation?.isCancelled != true
        {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let exitStatus = child.end()
        finishDrains(stdoutDrain, stderrDrain, deadline: Date().addingTimeInterval(Self.drainGracePeriod))
        return ClaudeLocalProcessResult(
            stdout: String(decoding: stdoutDrain.snapshot(), as: UTF8.self),
            stderr: String(decoding: stderrDrain.snapshot(), as: UTF8.self),
            exitCode: exitStatus ?? -1
        )
    }

    /// Joins the pipe drains without trusting every writer to be gone. The
    /// group is already ended, but a helper that left it (`setsid`) can keep
    /// the write ends open, so an unbounded join could hang `run()` and the
    /// menu's fetch state forever. Buffered output is readable immediately,
    /// so a short grace keeps healthy runs complete; anything still open at
    /// the deadline is abandoned with the output captured so far.
    private func finishDrains(
        _ stdoutDrain: ClaudeLocalPipeDrain,
        _ stderrDrain: ClaudeLocalPipeDrain,
        deadline: Date
    ) {
        let stdoutFinished = stdoutDrain.waitUntilFinished(deadline: deadline)
        let stderrFinished = stderrDrain.waitUntilFinished(deadline: deadline)
        if !stdoutFinished { stdoutDrain.abandon() }
        if !stderrFinished { stderrDrain.abandon() }
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
