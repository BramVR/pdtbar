import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Claude tool-call retry policy")
struct ClaudeToolCallRetryPolicyTests {
    @Test("Retry count maps to max attempts without an off-by-one")
    func retryCountMapsToMaxAttempts() {
        let policy = ClaudeToolCallRetryPolicy(retryCount: 1)

        #expect(policy.maxAttempts == 2)
        #expect(policy.shouldRetry(PDTMCPConnectorError.transientFailure("Claude did not call tool"), afterAttempt: 1))
        #expect(!policy.shouldRetry(PDTMCPConnectorError.transientFailure("Claude did not call tool"), afterAttempt: 2))
    }

    @Test("Missing expected tool calls are retryable but setup and read-shape errors are not")
    func retryClassificationMatchesClaudeToolCallFailures() {
        let policy = ClaudeToolCallRetryPolicy(retryCount: 2)

        #expect(policy.isRetryable(PDTMCPConnectorError.transientFailure("Claude did not call mcp__pdt__tool")))
        #expect(policy.isRetryable(PDTMCPConnectorError.setupUnavailable("Claude did not call mcp__pdt__tool")))
        #expect(!policy.isRetryable(PDTMCPConnectorError.setupUnavailable("Claude PDT MCP server is not connected")))
        #expect(!policy.isRetryable(PDTMCPConnectorError.missingScriptedResponse("pdt-get-portfolio-holdings")))
    }

    @Test("Negative retry counts disable extra attempts")
    func negativeRetryCountsDisableExtraAttempts() {
        let policy = ClaudeToolCallRetryPolicy(retryCount: -4)

        #expect(policy.maxAttempts == 1)
        #expect(!policy.shouldRetry(PDTMCPConnectorError.transientFailure("Claude did not call tool"), afterAttempt: 1))
    }
}
