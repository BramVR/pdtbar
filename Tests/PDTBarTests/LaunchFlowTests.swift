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
            "Checking Claude setup - No prompts opened",
            "Log in with Claude",
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
        #expect(cachedFailure.statusVisual.isDimmed)
        #expect(cachedFailure.statusVisual.barHeights == cachedPulse.statusVisual.barHeights)
        #expect(cachedFailure.statusVisual.filledBarCount == cachedPulse.statusVisual.filledBarCount)
        #expect(rowTitles(in: cachedFailure).contains("Details fill failed"))
        #expect(rowTitles(in: cachedFailure).contains("Fill details again"))
        #expect(!rowTitles(in: cachedFailure).contains("Log in with Claude"))
        #expect(rowTitles(in: cachedRefreshAction).contains("Refresh details"))
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
                completedUnitCount: 12,
                totalUnitCount: 19
            )
        )

        #expect(descriptor.statusTitle == cachedPulse.statusTitle)
        #expect(descriptor.sections.first?.id == "portfolioFetch")
        #expect(rowTitles(in: descriptor).contains("Filling details"))
        #expect(rowTitles(in: descriptor).contains("Step 5/5: Price history"))
        #expect(rowTitles(in: descriptor).contains("12/19 price histories checked"))
        #expect(!rowTitles(in: descriptor).contains("Details fill failed"))
        #expect(!rowTitles(in: descriptor).contains("Fill details again"))
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
