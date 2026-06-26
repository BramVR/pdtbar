import Foundation
import PDTBarCore

public struct ClaudeToolCallRetryPolicy: Equatable, Sendable {
    public var retryCount: Int

    public init(retryCount: Int = 1) {
        self.retryCount = max(0, retryCount)
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
        case PDTMCPConnectorError.setupUnavailable(let message):
            message.localizedCaseInsensitiveContains("did not call")
        default:
            false
        }
    }
}
