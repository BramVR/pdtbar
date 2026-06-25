import Foundation
import Testing
import PDTBarCore

@Suite("Launch options")
struct LaunchOptionTests {
    @Test("No-argument launch uses Claude-first mode and ignores fixture environment")
    func noArgumentLaunchUsesClaudeFirstMode() throws {
        let appSupport = "/tmp/pdtbar-tests-app-support"
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")

        let options = try PDTBarLaunchOptionParser.parse(
            arguments: [],
            environment: [
                "PDTBAR_APP_SUPPORT_DIR": appSupport,
                "PDTBAR_FIXTURE": fixture.path,
                "PDTBAR_SNAPSHOT_DIR": "/tmp/pdtbar-tests-snapshot",
            ]
        )

        #expect(options.mode == .claudeFirst)
        #expect(options.snapshotDirectory == nil)
        #expect(options.appSupportDirectory == URL(fileURLWithPath: appSupport))
    }

    @Test("Fixture launch requires explicit flag and may use snapshot directory")
    func fixtureLaunchRequiresExplicitFlag() throws {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")

        let options = try PDTBarLaunchOptionParser.parse(
            arguments: ["--fixture", fixture.path],
            environment: ["PDTBAR_SNAPSHOT_DIR": "/tmp/pdtbar-tests-snapshot"]
        )

        #expect(options.mode == .fixture(fixture))
        #expect(options.snapshotDirectory == URL(fileURLWithPath: "/tmp/pdtbar-tests-snapshot"))
    }

    @Test("Snapshot directory without fixture is rejected")
    func snapshotDirectoryWithoutFixtureIsRejected() {
        #expect(throws: PDTBarLaunchOptionError.usage) {
            try PDTBarLaunchOptionParser.parse(arguments: ["--snapshot-dir", "/tmp/pdtbar-tests-snapshot"])
        }
    }
}

@Suite("Claude launch flow")
struct ClaudeLaunchFlowTests {
    @Test("Readiness probe states map to product launch states")
    func readinessProbeStatesMapToLaunchStates() {
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: nil) == .probingClaude)
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: .ready) == .fetchingPortfolio)
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: .notReady) == .loggedOut)
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: .missingClaudeLogin) == .missingClaudeLogin)
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: .missingPDTMCP) == .missingPDTMCP)
        #expect(ClaudeLaunchFlow.state(afterReadinessProbe: .failed) == .probeFailed)
    }

    @Test("Successful login handoff resumes readiness")
    func successfulLoginHandoffResumesReadiness() {
        #expect(ClaudeLaunchFlow.action(afterLoginHandoff: .succeeded) == .recheckReadiness)
        #expect(ClaudeLaunchFlow.action(afterLoginHandoff: .failed) == .showMissingClaude)
    }

    @Test("Probing Claude descriptor keeps login action available")
    func probingDescriptorKeepsLoginActionAvailable() {
        let descriptor = ClaudeLaunchFlow.descriptor(for: .probingClaude)
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)

        #expect(descriptor.statusTitle == "Checking Claude")
        #expect(descriptor.statusVisual.isDimmed)
        #expect(descriptor.statusVisual.filledBarCount == 0)
        #expect(surface.sections.flatMap(\.rows).map(\.title) == [
            "Checking Claude setup - No prompts opened",
            "Log in with Claude",
        ])
        #expect(surface.sections.flatMap(\.rows).last?.role == .setupLogin)
    }

    @Test("Setup descriptors expose retryable onboarding actions")
    func setupDescriptorsExposeRetryableOnboardingActions() {
        let missingLogin = ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)
        let missingPDTMCP = ClaudeLaunchFlow.descriptor(for: .missingPDTMCP)
        let missingClaude = ClaudeLaunchFlow.descriptor(for: .missingClaude)

        #expect(rowTitles(in: missingLogin) == ["Not connected", "Log in with Claude", "Check again"])
        #expect(missingLogin.sections.flatMap(\.rows).last?.role == .setupRetry)
        #expect(rowTitles(in: missingPDTMCP) == ["Add the PDT MCP server to Claude", "Check again"])
        #expect(missingPDTMCP.sections.flatMap(\.rows).last?.role == .setupRetry)
        #expect(rowTitles(in: missingClaude) == ["Claude CLI not found", "Log in with Claude"])
    }

    @Test("Login failure descriptors use Claude CLI result copy")
    func loginFailureDescriptorsUseClaudeCLIResultCopy() {
        #expect(rowTitles(in: ClaudeLaunchFlow.descriptor(forLoginFailure: .missingBinary)) == [
            "Claude CLI not found",
            "Log in with Claude",
        ])
        #expect(rowTitles(in: ClaudeLaunchFlow.descriptor(forLoginFailure: .timedOut)) == [
            "Claude login timed out",
            "Log in with Claude",
        ])
        #expect(rowTitles(in: ClaudeLaunchFlow.descriptor(forLoginFailure: .failed)) == [
            "Claude login failed",
            "Log in with Claude",
        ])
        #expect(rowTitles(in: ClaudeLaunchFlow.descriptor(forLoginFailure: .launchFailed)) == [
            "Could not start claude auth login",
            "Log in with Claude",
        ])
    }

    @Test("Fetch descriptors keep login UI out of ready path")
    func fetchDescriptorsKeepLoginUIOutOfReadyPath() throws {
        let firstFetch = ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio)
        let fetchFailed = ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed)
        let cachedPulse = try quietFixtureDescriptor()
        let cachedRefresh = ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio, cachedPulse: cachedPulse)
        let cachedFailure = ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed, cachedPulse: cachedPulse)

        #expect(rowTitles(in: firstFetch) == ["Fetching portfolio"])
        #expect(!rowTitles(in: firstFetch).contains("Log in with Claude"))
        #expect(rowTitles(in: fetchFailed) == ["Could not fetch portfolio", "Try again", "Log in with Claude"])
        #expect(MenuBarSurfaceRenderer.render(descriptor: fetchFailed).status.visual.isDimmed)
        #expect(cachedRefresh.statusTitle == cachedPulse.statusTitle)
        #expect(cachedRefresh.sections.map(\.id).contains("pulse"))
        #expect(rowTitles(in: cachedRefresh).contains("Refreshing portfolio"))
        #expect(cachedFailure.statusVisual.isDimmed)
        #expect(cachedFailure.statusVisual.barHeights == cachedPulse.statusVisual.barHeights)
        #expect(cachedFailure.statusVisual.filledBarCount == cachedPulse.statusVisual.filledBarCount)
        #expect(rowTitles(in: cachedFailure).contains("Try again"))
    }

    @Test("Readiness probe gate serializes setup probes")
    func readinessProbeGateSerializesSetupProbes() {
        let gate = ClaudeReadinessProbeGate()

        #expect(gate.begin())
        #expect(!gate.begin())
        gate.finish()
        #expect(gate.begin())
        gate.finish()
    }
}

@Suite("Launch surface")
struct LaunchSurfaceTests {
    @Test("Quiet fixture descriptor renders stable launch surface")
    func quietFixtureDescriptorRendersStableLaunchSurface() throws {
        let descriptor = try quietFixtureDescriptor()
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)

        #expect(descriptor.statusTitle == "EUR 51,200.00 - All quiet")
        #expect(descriptor.statusVisual.filledBarCount == 0)
        #expect(!descriptor.statusVisual.isDimmed)
        #expect(descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness"])
        #expect(surface.status.title == "EUR 51,200.00 - All quiet")
        #expect(surface.status.menuBarTitle.isEmpty)
        #expect(surface.status.visual == descriptor.statusVisual)
        #expect(surface.status.accessibilityIdentifier == "pdtbar.status")
        #expect(surface.sections.first { $0.id == "pulse" }?.rows.first?.title == "EUR 51,200.00 - All quiet")
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func quietFixtureDescriptor() throws -> MenuDescriptor {
    let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
    return MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
}

private func rowTitles(in descriptor: MenuDescriptor) -> [String] {
    descriptor
        .sections
        .flatMap(\.rows)
        .map(\.title)
}
