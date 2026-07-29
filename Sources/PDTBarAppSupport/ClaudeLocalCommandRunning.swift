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
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String],
        cancellation: PDTCancellation?
    ) throws -> ClaudeLocalProcessResult
}

public extension ClaudeLocalCommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String],
        cancellation: PDTCancellation? = nil
    ) throws -> ClaudeLocalProcessResult {
        try run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
    }
}
