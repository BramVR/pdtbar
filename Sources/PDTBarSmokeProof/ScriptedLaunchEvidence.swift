import PDTBarCore

public enum ScriptedLaunchViolation: String, Codable, CaseIterable, Sendable {
    case appNotRunning
    case fixtureStateWritten
    case snapshotDiffersFromExpected
    case eventsDifferFromExpected
    /// The scripted replies hold the seed's holdings and total, so the launch
    /// could not tell a refresh from a rewritten date.
    case scriptedRepliesMatchSeed
}

/// What a scripted app launch left behind once its fetch or refresh should be
/// done, read before the smoke stops the app.
public struct ScriptedLaunchEvidence {
    /// The snapshot on disk before a launch that must replace it.
    public var seed: PortfolioSnapshot?
    /// The snapshot the launch must leave on disk; nil when it must write none.
    public var expected: PortfolioSnapshot?
    public var published: PortfolioSnapshot?
    public var expectedEvents: [String]
    public var events: [String]
    public var processStillRunning: Bool
    public var fixtureSentinelEmpty: Bool

    public init(
        seed: PortfolioSnapshot? = nil,
        expected: PortfolioSnapshot?,
        published: PortfolioSnapshot?,
        expectedEvents: [String],
        events: [String],
        processStillRunning: Bool,
        fixtureSentinelEmpty: Bool
    ) {
        self.seed = seed
        self.expected = expected
        self.published = published
        self.expectedEvents = expectedEvents
        self.events = events
        self.processStillRunning = processStillRunning
        self.fixtureSentinelEmpty = fixtureSentinelEmpty
    }

    public var violations: [ScriptedLaunchViolation] {
        var violations: [ScriptedLaunchViolation] = []
        if !processStillRunning {
            violations.append(.appNotRunning)
        }
        if !fixtureSentinelEmpty {
            violations.append(.fixtureStateWritten)
        }
        if published != expected {
            violations.append(.snapshotDiffersFromExpected)
        }
        if events != expectedEvents {
            violations.append(.eventsDifferFromExpected)
        }
        if let seed,
           let expected,
           seed.openHoldings.map(\.quoteId) == expected.openHoldings.map(\.quoteId),
           seed.totalValue == expected.totalValue {
            violations.append(.scriptedRepliesMatchSeed)
        }
        return violations
    }
}
