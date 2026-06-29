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
        #expect(options.claudeLoginBinaryOverride == nil)
    }

    @Test("No-argument launch ignores scripted Claude login binary environment")
    func noArgumentLaunchIgnoresScriptedClaudeLoginBinaryEnvironment() throws {
        let options = try PDTBarLaunchOptionParser.parse(
            arguments: [],
            environment: [
                "PDTBAR_CLAUDE_BIN": "/tmp/pdtbar-tests-handoff-script",
                "PDTBAR_CLAUDE_LOGIN_BIN": "/tmp/pdtbar-tests-login-script",
            ]
        )

        #expect(options.mode == .claudeFirst)
        #expect(options.claudeLoginBinaryOverride == nil)
    }

    @Test("Explicit scripted login handoff option carries debug binary")
    func explicitScriptedLoginHandoffOptionCarriesDebugBinary() throws {
        let options = try PDTBarLaunchOptionParser.parse(
            arguments: ["--scripted-claude-login-bin", "/tmp/pdtbar-tests-login-script"],
            environment: [:]
        )

        #expect(options.mode == .claudeFirst)
        #expect(options.claudeLoginBinaryOverride == "/tmp/pdtbar-tests-login-script")
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

    @Test("Successful login handoff can land on missing PDT setup after readiness recheck")
    func successfulLoginHandoffCanLandOnMissingPDTSetupAfterReadinessRecheck() {
        var readinessResults: [ClaudeReadinessProbeResult] = [.missingClaudeLogin, .missingPDTMCP]
        var renderedTitles: [String] = []
        var fetchCalls = 0

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { nil },
                readinessProbe: { readinessResults.removeFirst() },
                loginHandoff: { .succeeded },
                firstFetch: {
                    fetchCalls += 1
                    return .failed("unexpected fetch")
                }
            ),
            render: { renderedTitles.append($0.descriptor.statusTitle) }
        )

        runner.launch()
        runner.loginWithClaude()

        #expect(renderedTitles == [
            "Checking Claude",
            "Not connected",
            "Signing in with Claude",
            "Checking Claude",
            "Add the PDT MCP server to Claude",
        ])
        #expect(readinessResults.isEmpty)
        #expect(fetchCalls == 0)
    }

    @Test("Probing Claude descriptor keeps login action available")
    func probingDescriptorKeepsLoginActionAvailable() {
        let descriptor = ClaudeLaunchFlow.descriptor(for: .probingClaude)
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)

        #expect(descriptor.statusTitle == "Checking Claude")
        #expect(descriptor.statusVisual.isDimmed)
        #expect(descriptor.statusVisual.filledBarCount == 0)
        #expect(surface.sections.flatMap(\.rows).map(\.title) == [
            "Checking Claude setup",
            "Log in with Claude",
        ])
        #expect(surface.sections.flatMap(\.rows).map(\.detail) == [
            "No prompts opened",
            nil,
        ])
        #expect(surface.sections.flatMap(\.rows).last?.role == .setupLogin)
    }

    @Test("Setup descriptors expose retryable onboarding actions")
    func setupDescriptorsExposeRetryableOnboardingActions() {
        let openingClaude = ClaudeLaunchFlow.descriptor(for: .openingClaude)
        let missingLogin = ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)
        let missingPDTMCP = ClaudeLaunchFlow.descriptor(for: .missingPDTMCP)
        let missingClaude = ClaudeLaunchFlow.descriptor(for: .missingClaude)

        #expect(rowTitles(in: openingClaude) == ["Signing in with Claude", "Try login again"])
        #expect(openingClaude.sections.flatMap(\.rows).last?.role == .setupLogin)
        #expect(rowTitles(in: missingLogin) == ["Not connected", "Log in with Claude", "Check again"])
        #expect(missingLogin.sections.flatMap(\.rows).last?.role == .setupRetry)
        #expect(rowTitles(in: missingPDTMCP) == ["Add the PDT MCP server to Claude", "Log in with Claude", "Check again"])
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
        let cachedRefreshAction = ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: cachedPulse)
        let backgroundFailure = ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(cachedPulse: cachedPulse)

        #expect(rowTitles(in: firstFetch) == ["Fetching portfolio"])
        #expect(!rowTitles(in: firstFetch).contains("Log in with Claude"))
        #expect(rowTitles(in: fetchFailed) == ["Could not fetch portfolio", "Try again", "Log in with Claude"])
        #expect(MenuBarSurfaceRenderer.render(descriptor: fetchFailed).status.visual.isDimmed)
        #expect(cachedRefresh.statusTitle == cachedPulse.statusTitle)
        #expect(cachedRefresh.sections.first?.id == "portfolioFetch")
        #expect(cachedRefresh.sections.map(\.id).contains("pulse"))
        #expect(rowTitles(in: cachedRefresh).contains("Refreshing portfolio"))
        #expect(actionRow("actions.refreshNow", in: cachedRefresh)?.title == "Refreshing now")
        #expect(actionRow("actions.refreshNow", in: cachedRefresh)?.role == .fetchStatus)
        #expect(actionRow("actions.openPDT", in: cachedRefresh)?.role == .openPDT)
        #expect(cachedFailure.statusVisual.isDimmed)
        #expect(cachedFailure.statusVisual.barHeights == cachedPulse.statusVisual.barHeights)
        #expect(cachedFailure.statusVisual.filledBarCount == cachedPulse.statusVisual.filledBarCount)
        #expect(rowTitles(in: cachedFailure).contains("Details fill failed"))
        #expect(rowTitles(in: cachedFailure).contains("Fill details again"))
        #expect(!rowTitles(in: cachedFailure).contains("Log in with Claude"))
        #expect(actionRow("actions.refreshNow", in: cachedFailure)?.role == .fetchRetry)
        #expect(actionRow("actions.openPDT", in: cachedFailure)?.title == "Open PDT")
        #expect(freshnessRefreshDetailsAction(in: cachedRefreshAction)?.role == .fetchRetry)
        #expect(actionRow("actions.refreshNow", in: cachedRefreshAction)?.title == "Refresh now")
        #expect(actionRow("actions.openPDT", in: cachedRefreshAction)?.role == .openPDT)
        #expect(!cachedRefreshAction.sections.map(\.id).contains("portfolioFetch"))
        #expect(cachedRefreshAction.sections.first?.id == cachedPulse.sections.first?.id)
        #expect(backgroundFailure.sections.first?.id == "portfolioFetch")
        #expect(rowTitles(in: backgroundFailure).contains("Details fill failed"))
        #expect(rowTitles(in: backgroundFailure).contains("Fill details again"))
        #expect(!rowTitles(in: backgroundFailure).contains("Log in with Claude"))
    }

    @Test("Background detail retry renders active phase progress instead of stale failure")
    func backgroundDetailRetryRendersActivePhaseProgress() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: cachedPulse,
            progress: BackgroundDetailRefreshProgress(
                phase: .priceHistory,
                detail: "Calling pdt-list-symbol-prices",
                completedUnitCount: 12,
                totalUnitCount: 19
            ),
            cachedSnapshotAsOf: "2026-03-28"
        )
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)

        #expect(descriptor.statusTitle == cachedPulse.statusTitle)
        #expect(descriptor.sections.first?.id == "portfolioFetch")
        #expect(rowTitles(in: descriptor).contains("Filling details"))
        #expect(rowTitles(in: descriptor).contains("Cached data visible"))
        #expect(rowTitles(in: descriptor).contains("Step 5/5: Price history"))
        #expect(!rowTitles(in: descriptor).contains("Calling pdt-list-symbol-prices"))
        #expect(descriptor.sections.first?.rows.first { $0.id == "portfolioFetch.backgroundProgress.phase" }?.detail == "Calling pdt-list-symbol-prices")
        #expect(rowTitles(in: descriptor).contains("12/19 price histories checked"))
        #expect(descriptor.sections.first?.rows.first?.detail == "Last snapshot 2026-03-28")
        #expect(surface.status.toolTip == "PDTBar Syncing portfolio - Calling pdt-list-symbol-prices")
        #expect(surface.status.accessibilityLabel == "PDTBar Syncing portfolio - Calling pdt-list-symbol-prices")
        #expect(!rowTitles(in: descriptor).contains("Details fill failed"))
        #expect(!rowTitles(in: descriptor).contains("Fill details again"))
        #expect(actionRow("actions.refreshNow", in: descriptor)?.title == "Refreshing now")
        #expect(actionRow("actions.refreshNow", in: descriptor)?.role == .fetchStatus)
        #expect(actionRow("actions.openPDT", in: descriptor)?.role == .openPDT)
    }

    @Test("Background detail progress renders tool discovery substep")
    func backgroundDetailProgressRendersToolDiscoverySubstep() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
            cachedPulse: cachedPulse,
            progress: BackgroundDetailRefreshProgress(
                phase: .baseHoldings,
                detail: "Checking PDT tools"
            ),
            cachedSnapshotAsOf: "2026-03-28"
        )

        #expect(rowTitles(in: descriptor).contains("Cached data visible"))
        #expect(!rowTitles(in: descriptor).contains("Checking PDT tools"))
        #expect(descriptor.sections.first?.rows.first { $0.id == "portfolioFetch.backgroundProgress.phase" }?.detail == "Checking PDT tools")
        #expect(descriptor.sections.first?.rows.first?.detail == "Last snapshot 2026-03-28")
        #expect(MenuBarSurfaceRenderer.render(descriptor: descriptor).status.toolTip == "PDTBar Syncing portfolio - Checking PDT tools")
    }

    @Test("Background degraded completion keeps pulse rows and exposes retry")
    func backgroundDegradedCompletionKeepsPulseRowsAndExposesRetry() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let descriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: cachedPulse)

        #expect(descriptor.statusTitle == cachedPulse.statusTitle)
        #expect(descriptor.sections.first?.id == "portfolioFetch")
        #expect(descriptor.sections.map(\.id).contains("pulse"))
        #expect(rowTitles(in: descriptor).contains("Details partially filled"))
        #expect(rowTitles(in: descriptor).contains("Fill details again"))
        #expect(!rowTitles(in: descriptor).contains("Details fill failed"))
    }

    @Test("Claude auth status parser reads logged-in JSON from stdout")
    func claudeAuthStatusParserReadsLoggedInJSONFromStdout() {
        let noisyStdout = """
        notice
        {"loggedIn":true,"authMethod":"oauth"}
        """

        #expect(ClaudeAuthStatusParser.isLoggedIn(stdout: #"{"loggedIn":true}"#))
        #expect(ClaudeAuthStatusParser.isLoggedIn(stdout: noisyStdout))
        #expect(!ClaudeAuthStatusParser.isLoggedIn(stdout: #"{"loggedIn":false}"#))
        #expect(!ClaudeAuthStatusParser.isLoggedIn(stdout: "not json"))
        #expect(ClaudeAuthStatusParser.loggedInStatus(stdout: "not json") == nil)
    }

    @Test("Fetching descriptor exposes elapsed working time")
    func fetchingDescriptorExposesElapsedWorkingTime() {
        let descriptor = ClaudeLaunchFlow.descriptor(
            for: .fetchingPortfolio,
            fetchingElapsedSeconds: 12
        )

        #expect(descriptor.statusTitle == "Fetching portfolio 0:12")
        #expect(rowTitles(in: descriptor) == ["Fetching portfolio"])
        #expect(descriptor.sections.flatMap(\.rows).map(\.detail) == ["Read-only through Claude - working for 0:12"])
        #expect(MenuBarSurfaceRenderer.render(descriptor: descriptor).status.accessibilityLabel == "PDTBar Fetching portfolio 0:12")
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

    @Test("Login attempt gate ignores stale completions after retry")
    func loginAttemptGateIgnoresStaleCompletionsAfterRetry() {
        let gate = ClaudeLoginAttemptGate()

        let firstAttempt = gate.begin()
        let retryAttempt = gate.begin()

        #expect(!gate.finish(firstAttempt))
        #expect(gate.finish(retryAttempt))
        #expect(!gate.finish(retryAttempt))

        let laterAttempt = gate.begin()
        #expect(laterAttempt != firstAttempt)
        #expect(!gate.finish(firstAttempt))
        #expect(gate.finish(laterAttempt))
    }
}

@Suite("PDT onboarding runner")
struct PDTOnboardingRunnerTests {
    @Test("Launch runtime publishes first fetched pulse after ready no-argument launch")
    func launchRuntimePublishesFirstFetchedPulseAfterReadyNoArgumentLaunch() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch(cachedPulse: nil)
        let ready = runtime.completeReadinessProbe(.ready)
        let complete = runtime.completeFirstFetch(.succeeded(pulse))

        #expect(launch.effect == .probeReadiness)
        #expect(launch.descriptor.statusTitle == "Checking Claude")
        #expect(ready.effect == .startFirstFetch)
        #expect(ready.descriptor.statusTitle == "Fetching portfolio")
        #expect(complete.effect == .none)
        #expect(complete.descriptor.statusTitle == pulse.descriptor.statusTitle)
        #expect(freshnessRefreshDetailsAction(in: complete.descriptor)?.role == .fetchRetry)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
    }

    @Test("Launch runtime keeps cached pulse visible while probing and filling details")
    func launchRuntimeKeepsCachedPulseVisibleWhileProbingAndFillingDetails() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch(cachedPulse: cachedPulse)
        let ready = runtime.completeReadinessProbe(.ready)

        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(launch.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: launch.descriptor).contains("Checking Claude setup"))
        #expect(ready.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: ready.descriptor).contains("Filling details"))
        #expect(rowTitles(in: ready.descriptor).contains("Step 1/5: Base holdings"))
    }

    @Test("Launch runtime can install cached pulse after initial probing paint")
    func launchRuntimeCanInstallCachedPulseAfterInitialProbingPaint() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch(cachedPulse: nil)
        let cached = try #require(runtime.completeCachedPulseLoad(cachedPulse))
        let ready = runtime.completeReadinessProbe(.ready)

        #expect(launch.descriptor.statusTitle == "Checking Claude")
        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(cached.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: cached.descriptor).contains("Checking Claude setup"))
        #expect(ready.effect == .startBackgroundDetailRefresh)
        #expect(rowTitles(in: ready.descriptor).contains("Filling details"))
    }

    @Test("Launch runtime first paint is independent of large cached snapshot decode")
    func launchRuntimeFirstPaintIsIndependentOfLargeCachedSnapshotDecode() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-large-cached-launch-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let largeSnapshot = try largeCachedSnapshot(repeatingHoldings: 2_500)
        let encodedSnapshot = try stableJSONData(largeSnapshot)
        _ = try store.commitCurrentSnapshot(largeSnapshot)
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch(cachedPulse: nil)

        #expect(encodedSnapshot.count > 1_000_000)
        #expect(launch.descriptor.statusTitle == "Checking Claude")
        #expect(rowTitles(in: launch.descriptor) == ["Checking Claude setup", "Log in with Claude"])
        #expect(runtime.currentPulse == nil)

        let cachedPulse = try #require(try PressureRunner.cachedPulse(
            snapshotStore: store,
            pulseReadStore: PulseReadStore(directory: store.directory)
        ))
        let cached = try #require(runtime.completeCachedPulseLoad(cachedPulse))

        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(cached.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: cached.descriptor).contains("Checking Claude setup"))
    }

    @Test("Launch runtime ignores late cached pulse after fresh fetch publishes")
    func launchRuntimeIgnoresLateCachedPulseAfterFreshFetchPublishes() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let fetchedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        _ = runtime.completeReadinessProbe(.ready)
        let fetched = runtime.completeFirstFetch(.succeeded(fetchedPulse))
        let lateCache = runtime.completeCachedPulseLoad(cachedPulse)

        #expect(fetched.descriptor.statusTitle == fetchedPulse.descriptor.statusTitle)
        #expect(lateCache == nil)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(runtime.currentPulse?.descriptor.statusTitle == fetchedPulse.descriptor.statusTitle)
    }

    @Test("Launch runtime ignores ready completion after login handoff starts")
    func launchRuntimeIgnoresReadyCompletionAfterLoginHandoffStarts() {
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        let attemptID = runtime.readinessAttemptID
        let login = runtime.beginLoginHandoff()
        let staleReady = runtime.completeReadinessProbe(.ready, attemptID: attemptID)

        #expect(login.descriptor.statusTitle == "Signing in with Claude")
        #expect(staleReady.descriptor.statusTitle == "Signing in with Claude")
        #expect(staleReady.effect == .none)
        #expect(!runtime.firstFetchInFlight)
    }

    @Test("Launch runtime starts returning cached detail refresh and reports progress")
    func launchRuntimeStartsReturningCachedDetailRefreshAndReportsProgress() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        let ready = runtime.completeReadinessProbe(.ready)
        let progress = try #require(runtime.backgroundDetailRefreshProgress(
            BackgroundDetailRefreshProgress(
                phase: .priceHistory,
                completedUnitCount: 12,
                totalUnitCount: 19
            )
        ))

        #expect(ready.effect == .startBackgroundDetailRefresh)
        #expect(ready.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: ready.descriptor).contains("Filling details"))
        #expect(progress.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: progress.descriptor).contains("Step 5/5: Price history"))
        #expect(rowTitles(in: progress.descriptor).contains("12/19 price histories checked"))
        #expect(!rowTitles(in: progress.descriptor).contains("Details fill failed"))
    }

    @Test("Launch runtime preserves cached normal refresh when background detail refresh is disabled")
    func launchRuntimePreservesCachedNormalRefreshWhenBackgroundDetailRefreshIsDisabled() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        let ready = runtime.completeReadinessProbe(.ready, allowsBackgroundDetailRefresh: false)

        #expect(ready.effect == .startFirstFetch)
        #expect(runtime.firstFetchInFlight)
        #expect(!runtime.backgroundDetailRefreshInFlight)
        #expect(ready.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: ready.descriptor).contains("Refreshing portfolio"))
        #expect(!rowTitles(in: ready.descriptor).contains("Filling details"))
    }

    @Test("Launch runtime publishes completed background detail refresh")
    func launchRuntimePublishesCompletedBackgroundDetailRefresh() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let refreshedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        let completed = runtime.completeBackgroundDetailRefresh(.succeeded(refreshedPulse, outcome: .completed))

        #expect(!runtime.backgroundDetailRefreshInFlight)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(completed.descriptor.statusTitle == refreshedPulse.descriptor.statusTitle)
        #expect(freshnessRefreshDetailsAction(in: completed.descriptor)?.role == .fetchRetry)
        #expect(!rowTitles(in: completed.descriptor).contains("Details partially filled"))
        #expect(!rowTitles(in: completed.descriptor).contains("Details fill failed"))
    }

    @Test("Launch runtime renders degraded background detail completion")
    func launchRuntimeRendersDegradedBackgroundDetailCompletion() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let refreshedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        let degraded = runtime.completeBackgroundDetailRefresh(.succeeded(refreshedPulse, outcome: .degraded))

        #expect(!runtime.backgroundDetailRefreshInFlight)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(degraded.descriptor.statusTitle == refreshedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: degraded.descriptor).contains("Details partially filled"))
        #expect(rowTitles(in: degraded.descriptor).contains("Fill details again"))
        #expect(!rowTitles(in: degraded.descriptor).contains("Details fill failed"))
    }

    @Test("Launch runtime preserves cached pulse after background detail failure")
    func launchRuntimePreservesCachedPulseAfterBackgroundDetailFailure() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        let failed = runtime.completeBackgroundDetailRefresh(.failed("scripted detail fill failed"))

        #expect(!runtime.backgroundDetailRefreshInFlight)
        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(failed.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: failed.descriptor).contains("Details fill failed"))
        #expect(rowTitles(in: failed.descriptor).contains("Fill details again"))
        #expect(!rowTitles(in: failed.descriptor).contains("Log in with Claude"))
    }

    @Test("Launch runtime surfaces background detail failure diagnostics")
    func launchRuntimeSurfacesBackgroundDetailFailureDiagnostics() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()
        let diagnostic = PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-list-symbol-prices",
            phase: .priceHistory,
            attemptCount: 1,
            category: .transientFailure,
            argumentShape: ["symbol_quote_id"]
        )

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        let failed = runtime.completeBackgroundDetailRefresh(.failed("scripted detail fill failed", diagnostic: diagnostic))
        let diagnosticRow = try #require(healthRow(in: failed.descriptor)?.children.first { $0.id == "dataHealth.diagnostic" })

        #expect(failed.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(diagnosticRow.detail == "pdt-list-symbol-prices; priceHistory; transientFailure")
        #expect(diagnosticRow.children.first?.actionTarget?.copyText?.contains("argument_keys: symbol_quote_id") == true)
    }

    @Test("Launch runtime retries failed background detail refresh")
    func launchRuntimeRetriesFailedBackgroundDetailRefresh() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        _ = runtime.completeBackgroundDetailRefresh(.failed("scripted detail fill failed"))

        let retry = try #require(runtime.retryFirstFetch())
        let duplicateRetry = runtime.retryFirstFetch()

        #expect(retry.effect == .startBackgroundDetailRefresh)
        #expect(runtime.backgroundDetailRefreshInFlight)
        #expect(duplicateRetry == nil)
        #expect(retry.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: retry.descriptor).contains("Filling details"))
        #expect(!rowTitles(in: retry.descriptor).contains("Details fill failed"))
    }

    @Test("Launch runtime preserves cached pulse and retry copy after background detail failure")
    func launchRuntimePreservesCachedPulseAndRetryCopyAfterBackgroundDetailFailure() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        _ = runtime.completeReadinessProbe(.ready)
        let failed = runtime.completeBackgroundDetailRefresh(.failed("scripted details fill failed"))

        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(failed.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: failed.descriptor).contains("Details fill failed"))
        #expect(rowTitles(in: failed.descriptor).contains("Fill details again"))
        #expect(!rowTitles(in: failed.descriptor).contains("Log in with Claude"))
    }

    @Test("Launch runtime renders first fetch failure without cache as retryable setup")
    func launchRuntimeRendersFirstFetchFailureWithoutCacheAsRetryableSetup() {
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        _ = runtime.completeReadinessProbe(.ready)
        let failed = runtime.completeFirstFetch(.failed("scripted first fetch failed"))

        #expect(runtime.currentPulse == nil)
        #expect(failed.descriptor.statusTitle == "Could not fetch portfolio")
        #expect(rowTitles(in: failed.descriptor) == ["Could not fetch portfolio", "Try again", "Log in with Claude"])
    }

    @Test("Launch runtime owns first fetch retry gate and progress descriptor")
    func launchRuntimeOwnsFirstFetchRetryGateAndProgressDescriptor() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        _ = runtime.completeReadinessProbe(.ready)
        #expect(runtime.retryFirstFetch() == nil)
        _ = runtime.completeFirstFetch(.failed("scripted first fetch failed"))

        let retry = try #require(runtime.retryFirstFetch())
        let duplicateRetry = runtime.retryFirstFetch()
        let progress = try #require(runtime.firstFetchProgress(fetchingElapsedSeconds: 12))
        let complete = runtime.completeFirstFetch(.succeeded(pulse))

        #expect(retry.effect == .startFirstFetch)
        #expect(duplicateRetry == nil)
        #expect(progress.descriptor.statusTitle == "Fetching portfolio 0:12")
        #expect(complete.descriptor.statusTitle == pulse.descriptor.statusTitle)
    }

    @Test("Launch runtime ignores duplicate ready completions while first fetch is in flight")
    func launchRuntimeIgnoresDuplicateReadyCompletionsWhileFirstFetchIsInFlight() {
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        let firstReady = runtime.completeReadinessProbe(.ready)
        let duplicateReady = runtime.completeReadinessProbe(.ready)

        #expect(firstReady.effect == .startFirstFetch)
        #expect(duplicateReady.effect == .none)
        #expect(duplicateReady.descriptor.statusTitle == "Fetching portfolio")
        #expect(runtime.firstFetchInFlight)
    }

    @Test("Launch runtime ignores stale readiness completions from earlier attempts")
    func launchRuntimeIgnoresStaleReadinessCompletionsFromEarlierAttempts() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: nil)
        let firstAttemptID = runtime.readinessAttemptID
        _ = runtime.completeLoginHandoff(.succeeded)
        let secondAttemptID = runtime.readinessAttemptID
        let staleFailure = runtime.completeReadinessProbe(.failed, attemptID: firstAttemptID)
        let ready = runtime.completeReadinessProbe(.ready, attemptID: secondAttemptID)
        let complete = runtime.completeFirstFetch(.succeeded(pulse))
        let laterStaleFailure = runtime.completeReadinessProbe(.missingClaudeLogin, attemptID: firstAttemptID)

        #expect(staleFailure.effect == .none)
        #expect(staleFailure.descriptor.statusTitle == "Checking Claude")
        #expect(ready.effect == .startFirstFetch)
        #expect(complete.descriptor.statusTitle == pulse.descriptor.statusTitle)
        #expect(laterStaleFailure.descriptor.statusTitle == pulse.descriptor.statusTitle)
        #expect(freshnessRefreshDetailsAction(in: laterStaleFailure.descriptor)?.role == .fetchRetry)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
    }

    @Test("Launch runtime stale readiness completion preserves cached fetch failure copy")
    func launchRuntimeStaleReadinessCompletionPreservesCachedFetchFailureCopy() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        let firstAttemptID = runtime.readinessAttemptID
        _ = runtime.completeLoginHandoff(.succeeded)
        let secondAttemptID = runtime.readinessAttemptID
        _ = runtime.completeReadinessProbe(.ready, attemptID: secondAttemptID)
        let failure = runtime.completeFirstFetch(.failed("scripted details fill failed"))
        let staleFailure = runtime.completeReadinessProbe(.failed, attemptID: firstAttemptID)

        #expect(failure.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: staleFailure.descriptor).contains("Details fill failed"))
        #expect(rowTitles(in: staleFailure.descriptor).contains("Fill details again"))
        #expect(freshnessRefreshDetailsAction(in: staleFailure.descriptor) == nil)
    }

    @Test("Launch runtime stale readiness completion preserves active setup copy")
    func launchRuntimeStaleReadinessCompletionPreservesActiveSetupCopy() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch(cachedPulse: cachedPulse)
        let firstAttemptID = runtime.readinessAttemptID
        _ = runtime.completeLoginHandoff(.succeeded)
        let secondAttemptID = runtime.readinessAttemptID
        let missingSetup = runtime.completeReadinessProbe(.missingPDTMCP, attemptID: secondAttemptID)
        let staleFailure = runtime.completeReadinessProbe(.failed, attemptID: firstAttemptID)

        #expect(missingSetup.descriptor.statusTitle == "Add the PDT MCP server to Claude")
        #expect(staleFailure.descriptor.statusTitle == "Add the PDT MCP server to Claude")
        #expect(rowTitles(in: staleFailure.descriptor).contains("Check again"))
        #expect(freshnessRefreshDetailsAction(in: staleFailure.descriptor) == nil)
    }

    @Test("Fresh setup login handoff success rechecks readiness and starts first fetch")
    func freshSetupLoginHandoffSuccessRechecksReadinessAndStartsFirstFetch() throws {
        let fetchedDescriptor = try quietFixtureDescriptor()
        var readinessResults: [ClaudeReadinessProbeResult] = [.missingClaudeLogin, .ready]
        var handoffCalls = 0
        var fetchCalls = 0
        var renderedStates: [ClaudeLaunchState] = []
        var renderedTitles: [String] = []

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { nil },
                readinessProbe: {
                    readinessResults.removeFirst()
                },
                loginHandoff: {
                    handoffCalls += 1
                    return .succeeded
                },
                firstFetch: {
                    fetchCalls += 1
                    return .succeeded(fetchedDescriptor)
                }
            ),
            render: {
                renderedStates.append($0.state)
                renderedTitles.append($0.descriptor.statusTitle)
            }
        )

        runner.launch()
        #expect(renderedStates == [.probingClaude, .missingClaudeLogin])
        #expect(handoffCalls == 0)
        #expect(fetchCalls == 0)

        runner.loginWithClaude()

        #expect(renderedStates == [
            .probingClaude,
            .missingClaudeLogin,
            .openingClaude,
            .probingClaude,
            .fetchingPortfolio,
            .fetchingPortfolio,
            .fetchingPortfolio,
        ])
        #expect(renderedTitles.last == fetchedDescriptor.statusTitle)
        #expect(handoffCalls == 1)
        #expect(fetchCalls == 1)
        #expect(readinessResults.isEmpty)
    }

    @Test("Login handoff failure shows missing Claude copy and does not fetch")
    func loginHandoffFailureShowsMissingClaudeCopyAndDoesNotFetch() {
        var handoffCalls = 0
        var fetchCalls = 0
        var renderedTitles: [String] = []

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { nil },
                readinessProbe: { .missingClaudeLogin },
                loginHandoff: {
                    handoffCalls += 1
                    return .failed(.missingBinary)
                },
                firstFetch: {
                    fetchCalls += 1
                    return .failed("unexpected fetch")
                }
            ),
            render: { renderedTitles.append($0.descriptor.statusTitle) }
        )

        runner.launch()
        runner.loginWithClaude()

        #expect(renderedTitles.last == "Claude CLI not found")
        #expect(handoffCalls == 1)
        #expect(fetchCalls == 0)
    }

    @Test("Readiness failures map to setup states without live fetch")
    func readinessFailuresMapToSetupStatesWithoutLiveFetch() {
        let cases: [(ClaudeReadinessProbeResult, String)] = [
            (.missingClaudeLogin, "Not connected"),
            (.missingPDTMCP, "Add the PDT MCP server to Claude"),
            (.failed, "Could not check Claude"),
        ]

        for (probeResult, expectedTitle) in cases {
            var fetchCalls = 0
            var renderedTitles: [String] = []

            let runner = PDTOnboardingRunner(
                dependencies: PDTOnboardingRunnerDependencies(
                    loadCachedPulse: { nil },
                    readinessProbe: { probeResult },
                    loginHandoff: { .failed(.failed) },
                    firstFetch: {
                        fetchCalls += 1
                        return .failed("unexpected fetch")
                    }
                ),
                render: { renderedTitles.append($0.descriptor.statusTitle) }
            )

            runner.launch()

            #expect(renderedTitles == ["Checking Claude", expectedTitle])
            #expect(fetchCalls == 0)
        }
    }

    @Test("Fetch failure shows retryable fetch copy")
    func fetchFailureShowsRetryableFetchCopy() {
        var fetchCalls = 0
        var renderedTitles: [String] = []

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { nil },
                readinessProbe: { .ready },
                loginHandoff: { .succeeded },
                firstFetch: {
                    fetchCalls += 1
                    return .failed("scripted first fetch failed")
                }
            ),
            render: { renderedTitles.append($0.descriptor.statusTitle) }
        )

        runner.launch()

        #expect(renderedTitles == [
            "Checking Claude",
            "Fetching portfolio",
            "Fetching portfolio",
            "Could not fetch portfolio",
        ])
        #expect(fetchCalls == 1)
    }

    @Test("Fetch retry invokes first fetch again")
    func fetchRetryInvokesFirstFetchAgain() throws {
        let fetchedDescriptor = try quietFixtureDescriptor()
        var fetchResults: [PDTOnboardingFetchResult] = [
            .failed("scripted first fetch failed"),
            .succeeded(fetchedDescriptor),
        ]
        var renderedTitles: [String] = []

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { nil },
                readinessProbe: { .ready },
                loginHandoff: { .succeeded },
                firstFetch: {
                    fetchResults.removeFirst()
                }
            ),
            render: { renderedTitles.append($0.descriptor.statusTitle) }
        )

        runner.launch()
        runner.retryFirstFetch()

        #expect(fetchResults.isEmpty)
        #expect(renderedTitles.last == fetchedDescriptor.statusTitle)
    }

    @Test("Coordinator preserves cached pulse supplied at initialization")
    func coordinatorPreservesCachedPulseSuppliedAtInitialization() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let coordinator = PDTOnboardingCoordinator(cachedPulse: cachedPulse)

        let update = coordinator.launch()

        #expect(update.descriptor.statusTitle == cachedPulse.statusTitle)
        #expect(rowTitles(in: update.descriptor).contains("Checking Claude setup"))
    }

    @Test("Coordinator uses latest fetched pulse for later refresh states")
    func coordinatorUsesLatestFetchedPulseForLaterRefreshStates() throws {
        let stalePulse = try quietFixtureDescriptor()
        let freshPulse = MenuDescriptor(
            statusTitle: "Fresh scripted pulse",
            sections: [
                MenuSection(
                    id: "pulse",
                    title: "Pulse",
                    rows: [MenuRow(id: "pulse.status", title: "Fresh scripted pulse")]
                ),
            ]
        )
        let coordinator = PDTOnboardingCoordinator(cachedPulse: stalePulse)

        _ = coordinator.completeFirstFetch(.succeeded(freshPulse))
        let refresh = coordinator.beginFirstFetch()

        #expect(refresh.descriptor.statusTitle == "Fresh scripted pulse")
        #expect(rowTitles(in: refresh.descriptor).contains("Refreshing portfolio"))
    }

    @Test("Returning launch preserves cached pulse when fetch fails")
    func returningLaunchPreservesCachedPulseWhenFetchFails() throws {
        let cachedPulse = try quietFixtureDescriptor()
        var fetchCalls = 0
        var renderedDescriptors: [MenuDescriptor] = []

        let runner = PDTOnboardingRunner(
            dependencies: PDTOnboardingRunnerDependencies(
                loadCachedPulse: { cachedPulse },
                readinessProbe: { .ready },
                loginHandoff: { .succeeded },
                firstFetch: {
                    fetchCalls += 1
                    return .failed("scripted details fill failed")
                }
            ),
            render: { renderedDescriptors.append($0.descriptor) }
        )

        runner.launch()

        let finalDescriptor = try #require(renderedDescriptors.last)
        #expect(finalDescriptor.statusTitle == cachedPulse.statusTitle)
        #expect(rowTitles(in: finalDescriptor).contains("Details fill failed"))
        #expect(rowTitles(in: finalDescriptor).contains("Fill details again"))
        #expect(!rowTitles(in: finalDescriptor).contains("Log in with Claude"))
        #expect(fetchCalls == 1)
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
        #expect(descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness", "actions"])
        #expect(actionRow("actions.refreshNow", in: descriptor)?.role == .fetchRetry)
        #expect(actionRow("actions.openPDT", in: descriptor)?.role == .openPDT)
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
    try quietFixturePulse().descriptor
}

private func quietFixturePulse() throws -> PulseLifecycleResult {
    let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-launch-flow-runtime-test")
    return try PressureRunner.run(
        dataSource: PDTFixtureDataSource(fixture: fixture),
        snapshotStore: snapshotStore,
        pulseReadStore: PulseReadStore(directory: snapshotStore.directory)
    )
}

private func cachedQuietFixturePulse() throws -> PulseLifecycleResult {
    let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-launch-flow-cached-runtime-test")
    _ = try PressureRunner.run(
        dataSource: PDTFixtureDataSource(fixture: fixture),
        snapshotStore: snapshotStore,
        pulseReadStore: PulseReadStore(directory: snapshotStore.directory)
    )
    return try #require(try PressureRunner.cachedPulse(
        snapshotStore: snapshotStore,
        pulseReadStore: PulseReadStore(directory: snapshotStore.directory)
    ))
}

private func largeCachedSnapshot(repeatingHoldings count: Int) throws -> PortfolioSnapshot {
    let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    var snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
    let seedHoldings = try #require(!snapshot.openHoldings.isEmpty ? snapshot.openHoldings : nil)
    snapshot.openHoldings = (0..<count).map { index in
        var holding = seedHoldings[index % seedHoldings.count]
        holding.name = "Synthetic cached holding \(index)"
        holding.quoteId = 1_000_000 + index
        holding.copyableIdentifier = "synthetic-cached-holding-\(index)"
        return holding
    }
    return snapshot
}

private func rowTitles(in descriptor: MenuDescriptor) -> [String] {
    descriptor
        .sections
        .flatMap(\.rows)
        .map(\.title)
}

private func healthRow(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor
        .sections
        .first { $0.id == "freshness" }?
        .rows
        .first { $0.id == "dataHealth" }
}

private func freshnessRefreshDetailsAction(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections
        .first { $0.id == "freshness" }?
        .rows
        .first { $0.id == "freshness.summary" }?
        .children
        .first { $0.id == "freshness.refreshDetails" }
}

private func actionRow(_ id: String, in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections
        .first { $0.id == "actions" }?
        .rows
        .first { $0.id == id }
}
