import Testing
import PDTBarCore
import PDTBarSmokeProof

@Suite("Scripted launch evidence")
struct ScriptedLaunchEvidenceTests {
    @Test("A refresh that published the scripted portfolio, logged its requests, and left the app running proves the launch")
    func completedRefreshHasNoViolations() {
        #expect(completedRefresh().violations.isEmpty)
    }

    @Test("An app that died after publishing does not prove the launch")
    func prematureDeathFails() {
        var evidence = completedRefresh()
        evidence.processStillRunning = false

        #expect(evidence.violations == [.appNotRunning])
    }

    @Test("A seeded snapshot with only its date rewritten does not prove the launch")
    func dateOnlyRewriteFails() {
        var rewritten = seed
        rewritten.asOf = refreshed.asOf
        var evidence = completedRefresh()
        evidence.published = rewritten

        #expect(evidence.violations == [.snapshotDiffersFromExpected])
    }

    @Test("A date-only rewrite by an app that then died without requesting anything reports every gap")
    func dateOnlyRewriteByDeadIdleAppFails() {
        var rewritten = seed
        rewritten.asOf = refreshed.asOf
        var evidence = completedRefresh()
        evidence.published = rewritten
        evidence.events = []
        evidence.processStillRunning = false

        #expect(evidence.violations == [.appNotRunning, .snapshotDiffersFromExpected, .eventsDifferFromExpected])
    }

    @Test("A refresh that stopped before its last request does not prove the launch")
    func incompleteRequestSequenceFails() {
        var evidence = completedRefresh()
        evidence.events.removeLast()

        #expect(evidence.violations == [.eventsDifferFromExpected])
    }

    @Test("A request beyond the scripted sequence does not prove the launch")
    func extraRequestFails() {
        var evidence = completedRefresh()
        evidence.events.append("request /v1/me")

        #expect(evidence.violations == [.eventsDifferFromExpected])
    }

    @Test("A launch that wrote fixture state does not prove the launch")
    func fixtureStateFails() {
        var evidence = completedRefresh()
        evidence.fixtureSentinelEmpty = false

        #expect(evidence.violations == [.fixtureStateWritten])
    }

    @Test("A launch that published nothing does not prove the launch")
    func missingSnapshotFails() {
        var evidence = completedRefresh()
        evidence.published = nil

        #expect(evidence.violations == [.snapshotDiffersFromExpected])
    }

    @Test("A failed refresh that left the seeded snapshot in place proves the launch")
    func failedRefreshKeepingSeedHasNoViolations() {
        #expect(failedRefresh().violations.isEmpty)
    }

    @Test("A failed refresh that changed the holdings under the seeded date does not prove the launch")
    func failedRefreshChangingHoldingsFails() {
        var changed = refreshed
        changed.asOf = seed.asOf
        var evidence = failedRefresh()
        evidence.published = changed

        #expect(evidence.violations == [.snapshotDiffersFromExpected])
    }

    @Test("A failed first fetch that wrote a snapshot does not prove the launch")
    func failedFirstFetchWritingSnapshotFails() {
        var evidence = failedRefresh()
        evidence.expected = nil

        #expect(evidence.violations == [.snapshotDiffersFromExpected])
    }

    @Test("Scripted replies that hold the seed's holdings and total cannot prove a refresh")
    func repliesIndistinguishableFromSeedFail() {
        var redated = seed
        redated.asOf = refreshed.asOf
        var evidence = completedRefresh()
        evidence.expected = redated
        evidence.published = redated

        #expect(evidence.violations == [.scriptedRepliesMatchSeed])
    }

    @Test("A first fetch has no seed to tell apart")
    func firstFetchWithoutSeedHasNoViolations() {
        var evidence = completedRefresh()
        evidence.seed = nil

        #expect(evidence.violations.isEmpty)
    }
}

private let refreshEvents = ["check", "request /v1/portfolio/holdings", "request /v1/prices/batch"]

private var seed: PortfolioSnapshot {
    snapshot(asOf: "2026-03-28", total: "300.00", quoteIds: [9001, 9002, 9003])
}

private var refreshed: PortfolioSnapshot {
    snapshot(asOf: "2026-03-29", total: "200.00", quoteIds: [9001, 9004])
}

private func completedRefresh() -> ScriptedLaunchEvidence {
    ScriptedLaunchEvidence(
        seed: seed,
        expected: refreshed,
        published: refreshed,
        expectedEvents: refreshEvents,
        events: refreshEvents,
        processStillRunning: true,
        fixtureSentinelEmpty: true
    )
}

private func failedRefresh() -> ScriptedLaunchEvidence {
    ScriptedLaunchEvidence(
        expected: seed,
        published: seed,
        expectedEvents: refreshEvents,
        events: refreshEvents,
        processStillRunning: true,
        fixtureSentinelEmpty: true
    )
}

private func snapshot(asOf: String, total: String, quoteIds: [Int]) -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: asOf,
        totalValue: Money(value: total, currency: "EUR"),
        openHoldings: quoteIds.map {
            NormalizedHolding(
                name: "Holding \($0)",
                quoteId: $0,
                weight: 100 / Double(quoteIds.count),
                worth: Money(value: "100.00", currency: "EUR"),
                price: nil,
                priceAsOf: asOf
            )
        },
        sectors: [],
        assetTypes: [],
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: []
    )
}
