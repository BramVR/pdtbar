import Foundation
import PDTBarCore

/// Retry policy for local Claude CLI read-tool calls.
///
/// Every attempt is a full `claude -p` CLI/LLM run (up to the configured tool
/// timeout), so only errors classified as true transients are retryable:
/// `ClaudeLocalConnection` maps timeouts, transient-looking nonzero exits, and
/// missing/unparseable tool results to `transientFailure`. Setup and auth
/// outages (`setupUnavailable`) and deterministic shape errors repeat
/// identically on retry and are never retried here.
public struct ClaudeToolCallRetryPolicy: Equatable, Sendable {
    public var retryCount: Int
    public var retryBackoffSeconds: Double

    public init(retryCount: Int = 1, retryBackoffSeconds: Double = 2.0) {
        self.retryCount = max(0, retryCount)
        self.retryBackoffSeconds = max(0, retryBackoffSeconds)
    }

    public var maxAttempts: Int {
        retryCount + 1
    }

    public func shouldRetry(_ error: Error, afterAttempt attempt: Int) -> Bool {
        attempt < maxAttempts && isRetryable(error)
    }

    public func isRetryable(_ error: Error) -> Bool {
        switch error {
        case PDTMCPConnectorError.transientFailure:
            true
        default:
            false
        }
    }
}
