import Foundation
import Testing
import PDTBarCore

@Suite("Launch options")
struct LaunchOptionTests {
    @Test("No-argument launch uses the PDT API and ignores fixture environment")
    func noArgumentLaunchUsesPDTAPI() throws {
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

        #expect(options.mode == .pdtAPI)
        #expect(options.snapshotDirectory == nil)
        #expect(options.appSupportDirectory == URL(fileURLWithPath: appSupport))
        #expect(options.scriptedConnection == nil)
    }

    @Test("A scripted PDT connection runs only against an isolated app support directory")
    func scriptedConnectionNeedsIsolatedAppSupport() throws {
        #expect(throws: PDTBarLaunchOptionError.usage) {
            try PDTBarLaunchOptionParser.parse(arguments: ["--scripted-pdt", "/tmp/script.json"], environment: [:])
        }

        let options = try PDTBarLaunchOptionParser.parse(
            arguments: ["--app-support-dir", "/tmp/pdtbar-isolated", "--scripted-pdt", "/tmp/script.json"],
            environment: [:]
        )

        #expect(options.mode == .pdtAPI)
        #expect(options.scriptedConnection == URL(fileURLWithPath: "/tmp/script.json"))
        #expect(options.appSupportDirectory == URL(fileURLWithPath: "/tmp/pdtbar-isolated"))
    }

    @Test("A dev credential file runs only against an isolated app support directory and never with a script")
    func credentialFileNeedsIsolatedAppSupport() throws {
        for arguments in [
            ["--pdt-credential-file", "/tmp/pdt.json"],
            ["--app-support-dir", "/tmp/a", "--pdt-credential-file", "/tmp/pdt.json", "--scripted-pdt", "/tmp/s.json"],
            ["--fixture", "/tmp/f.json", "--app-support-dir", "/tmp/a", "--pdt-credential-file", "/tmp/pdt.json"],
        ] {
            #expect(throws: PDTBarLaunchOptionError.usage, "\(arguments)") {
                try PDTBarLaunchOptionParser.parse(arguments: arguments, environment: [:])
            }
        }

        let options = try PDTBarLaunchOptionParser.parse(
            arguments: ["--app-support-dir", "/tmp/pdtbar-isolated", "--pdt-credential-file", "/tmp/pdt.json"],
            environment: [:]
        )

        #expect(options.mode == .pdtAPI)
        #expect(options.credentialFile == URL(fileURLWithPath: "/tmp/pdt.json"))
        #expect(options.scriptedConnection == nil)
    }

    @Test("A scripted PDT connection cannot be combined with a fixture launch")
    func scriptedConnectionRejectsFixture() {
        #expect(throws: PDTBarLaunchOptionError.usage) {
            try PDTBarLaunchOptionParser.parse(
                arguments: ["--fixture", "/tmp/f.json", "--app-support-dir", "/tmp/a", "--scripted-pdt", "/tmp/s.json"],
                environment: [:]
            )
        }
    }

    @Test("The removed Claude login override is a usage error")
    func removedClaudeLoginOverrideIsRejected() {
        #expect(throws: PDTBarLaunchOptionError.usage) {
            try PDTBarLaunchOptionParser.parse(arguments: ["--scripted-claude-login-bin", "/tmp/login"], environment: [:])
        }
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

@Suite("PDT launch menu")
struct PDTLaunchMenuTests {
    @Test("Each connection state names itself and offers only the actions that state accepts")
    func connectionStatesOfferTheirActions() {
        let cases: [(PDTLaunchState, String, [String])] = [
            (.checkingConnection, "Checking PDT connection", []),
            (.connecting, "Signing in with PDT", ["pdtConnection.cancel"]),
            (.disconnecting, "Disconnecting from PDT", []),
            (.notConnected, "Not connected", ["pdtConnection.signIn", "pdtConnection.token"]),
            (
                .needsReconnect(.browserSession, .signInExpired),
                "Reconnect to PDT",
                ["pdtConnection.signIn", "pdtConnection.token", "pdtConnection.check", "pdtConnection.disconnect"]
            ),
            (
                .subscriptionPaused,
                "PDT access paused",
                ["pdtConnection.signIn", "pdtConnection.token", "pdtConnection.check", "pdtConnection.disconnect"]
            ),
            (.keychainUnavailable(.missingEntitlement), "Keychain unavailable", ["pdtConnection.check"]),
            (.keychainUnavailable(.failed), "Could not read the Keychain", ["pdtConnection.check"]),
        ]

        for (state, title, actions) in cases {
            let descriptor = PDTLaunchMenu.descriptor(for: state)
            let rows = descriptor.sections.flatMap(\.rows)

            #expect(descriptor.statusTitle == title, "\(state)")
            #expect(descriptor.statusVisual.isDimmed, "\(state)")
            #expect(rows.first?.id == "pdtConnection.status", "\(state)")
            #expect(rows.first?.title == title, "\(state)")
            #expect(rows.dropFirst().map(\.id) == actions, "\(state)")
        }
    }

    @Test("Reconnect copy names why PDT stopped accepting the connection")
    func reconnectCopyNamesTheCause() {
        let details: [(PDTReconnectCause, String)] = [
            (.signInExpired, "Your PDT sign-in has expired"),
            (.tokenExpired, "Your PDT token has expired"),
            (.tokenRevoked, "PDTBar's access was revoked in PDT"),
            (.tokenInvalid, "PDT no longer accepts this connection"),
            (.readAccessMissing, "This connection can't read your portfolio"),
        ]
        for (cause, detail) in details {
            let status = PDTLaunchMenu.descriptor(for: .needsReconnect(.personalToken, cause)).sections.first?.rows.first
            #expect(status?.detail == detail)
        }
    }

    @Test("Reconnect, paused, and Keychain screens keep a cached pulse visible; not connected hides it")
    func connectionScreensAndCachedPulse() throws {
        let cachedPulse = try quietFixtureDescriptor()

        for state in [
            PDTLaunchState.checkingConnection,
            .needsReconnect(.personalToken, .tokenRevoked),
            .subscriptionPaused,
            .keychainUnavailable(.missingEntitlement),
        ] {
            let descriptor = PDTLaunchMenu.descriptor(for: state, cachedPulse: cachedPulse)
            #expect(descriptor.sections.first?.id == "pdtConnection", "\(state)")
            #expect(descriptor.sections.map(\.id).contains("pulse"), "\(state)")
            #expect(descriptor.statusVisual.isDimmed, "\(state)")
            #expect(actionRow("actions.refreshNow", in: descriptor)?.role == .fetchStatus, "\(state)")
        }

        let notConnected = PDTLaunchMenu.descriptor(for: .notConnected, cachedPulse: cachedPulse)
        #expect(notConnected.sections.map(\.id) == ["pdtConnection"])
        #expect(notConnected.statusTitle == "Not connected")
    }

    @Test("A failed sign-in shows its reason above the sign-in actions")
    func signInFailureNotice() {
        let descriptor = PDTLaunchMenu.descriptor(for: .notConnected, notice: .signInFailed(.denied))
        let rows = descriptor.sections.flatMap(\.rows)

        #expect(rows.map(\.id) == ["pdtConnection.status", "pdtConnection.signInFailed", "pdtConnection.signIn", "pdtConnection.token"])
        #expect(rows[1].title == "Sign-in failed")
        #expect(rows[1].detail == "PDT sign-in was declined")
    }

    @Test("After a disconnect the menu links to the PDT page where access is removed")
    func disconnectNoticeLinksRevokePage() {
        let descriptor = PDTLaunchMenu.descriptor(for: .notConnected, notice: .disconnected(revokeAt: PDTOAuthEndpoints.integrations))
        let revoke = descriptor.sections.flatMap(\.rows).first { $0.id == "pdtConnection.revoke" }

        #expect(revoke?.role == .connectionRevoke)
        #expect(revoke?.actionPayload == PDTOAuthEndpoints.integrations.absoluteString)
    }

    @Test("First fetch descriptors show progress and a retryable failure without a pulse")
    func firstFetchDescriptors() {
        let fetching = PDTLaunchMenu.descriptor(for: .connected(.fetching))
        let elapsed = PDTLaunchMenu.descriptor(for: .connected(.fetching), fetchingElapsedSeconds: 12)
        let failed = PDTLaunchMenu.descriptor(for: .connected(.failed))

        #expect(rowTitles(in: fetching) == ["Fetching portfolio"])
        #expect(elapsed.statusTitle == "Fetching portfolio 0:12")
        #expect(elapsed.sections.flatMap(\.rows).map(\.detail) == ["Read-only from PDT - working for 0:12"])
        #expect(MenuBarSurfaceRenderer.render(descriptor: elapsed).status.accessibilityLabel == "PDTBar Fetching portfolio 0:12")
        #expect(failed.statusTitle == "Could not fetch portfolio")
        #expect(rowTitles(in: failed) == ["Could not fetch portfolio", "Try again", "Disconnect from PDT"])
        #expect(rowRoles(in: failed) == [.fetchStatus, .fetchRetry, .connectionDisconnect])
        #expect(MenuBarSurfaceRenderer.render(descriptor: failed).status.visual.isDimmed)
    }

    @Test("Refresh descriptors over a cached pulse keep the pulse and its actions")
    func cachedRefreshDescriptors() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let cachedRefresh = PDTLaunchMenu.descriptor(for: .connected(.fetching), cachedPulse: cachedPulse)
        let cachedFailure = PDTLaunchMenu.descriptor(for: .connected(.failed), cachedPulse: cachedPulse)
        let cachedRefreshAction = PDTLaunchMenu.descriptorWithRefreshDetailsAction(cachedPulse: cachedPulse)

        #expect(cachedRefresh.statusTitle == cachedPulse.statusTitle)
        #expect(cachedRefresh.sections.first?.id == "portfolioFetch")
        #expect(cachedRefresh.sections.map(\.id).contains("pulse"))
        #expect(rowTitles(in: cachedRefresh).contains("Refreshing portfolio"))
        #expect(actionRow("actions.refreshNow", in: cachedRefresh)?.title == "Refreshing now")
        #expect(actionRow("actions.refreshNow", in: cachedRefresh)?.role == .fetchStatus)
        #expect(actionRow("actions.openPDT", in: cachedRefresh)?.role == .openPDT)
        #expect(cachedFailure.statusVisual.isDimmed)
        #expect(cachedFailure.statusVisual.barHeights == cachedPulse.statusVisual.barHeights)
        #expect(rowTitles(in: cachedFailure).contains("Details fill failed"))
        #expect(rowTitles(in: cachedFailure).contains("Fill details again"))
        #expect(actionRow("actions.refreshNow", in: cachedFailure) == nil)
        #expect(actionRow("actions.openPDT", in: cachedFailure)?.role == .openPDT)
        #expect(freshnessRefreshDetailsAction(in: cachedRefreshAction)?.role == .fetchRetry)
        #expect(actionRow("actions.refreshNow", in: cachedRefreshAction)?.title == "Refresh now")
        #expect(!cachedRefreshAction.sections.map(\.id).contains("portfolioFetch"))
    }

    @Test("Background detail retry renders active phase progress instead of stale failure")
    func backgroundDetailRetryRendersActivePhaseProgress() throws {
        let cachedPulse = try quietFixtureDescriptor()
        let descriptor = PDTLaunchMenu.descriptorForBackgroundDetailProgress(
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
        #expect(rowTitles(in: descriptor).contains("Step 5/6: Price history"))
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
        let descriptor = PDTLaunchMenu.descriptorForBackgroundDetailProgress(
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
        let descriptor = PDTLaunchMenu.descriptorForBackgroundDetailDegraded(cachedPulse: cachedPulse)

        #expect(descriptor.statusTitle == cachedPulse.statusTitle)
        #expect(descriptor.sections.first?.id == "portfolioFetch")
        #expect(descriptor.sections.map(\.id).contains("pulse"))
        #expect(rowTitles(in: descriptor).contains("Details partially filled"))
        #expect(rowTitles(in: descriptor).contains("Fill details again"))
        #expect(!rowTitles(in: descriptor).contains("Details fill failed"))
    }

}

@Suite("PDT launch runtime")
struct PDTLaunchRuntimeTests {
    @Test("Launch loads the cached pulse first, then checks the connection")
    func launchLoadsCachedPulseThenChecks() throws {
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch()
        #expect(launch.effect == .loadCachedPulse)
        #expect(launch.descriptor.statusTitle == "Checking PDT connection")
        #expect(runtime.signIn() == nil)
        #expect(runtime.checkAgain() == nil)

        let loaded = try #require(runtime.completeCachedPulseLoad(nil))
        #expect(loaded.effect == .checkConnection)
        #expect(loaded.state == .checkingConnection)
        #expect(runtime.completeCachedPulseLoad(nil) == nil)
    }

    @Test("First paint does not wait for a large cached snapshot to decode")
    func firstPaintIsIndependentOfLargeCachedSnapshotDecode() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-large-cached-launch-test")
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let largeSnapshot = try largeCachedSnapshot(repeatingHoldings: 2_500)
        #expect(try stableJSONData(largeSnapshot).count > 1_000_000)
        _ = try store.commitCurrentSnapshot(largeSnapshot)
        let runtime = PDTLaunchRuntime()

        let launch = runtime.launch()

        #expect(rowTitles(in: launch.descriptor) == ["Checking PDT connection"])
        #expect(runtime.currentPulse == nil)

        let cachedPulse = try #require(try PressureRunner.cachedPulse(
            snapshotStore: store,
            pulseReadStore: PulseReadStore(directory: store.directory)
        ))
        let cached = try #require(runtime.completeCachedPulseLoad(cachedPulse))

        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(cached.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: cached.descriptor).contains("Checking PDT connection"))
    }

    @Test("A new user signs in, then the first fetch publishes the pulse")
    func newUserSignsInThenFirstFetchPublishes() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()

        let notConnected = launched(runtime, cachedPulse: nil, status: .notConnected)
        #expect(notConnected.state == .notConnected)
        #expect(notConnected.effect == .none)

        let signingIn = try #require(runtime.signIn())
        #expect(signingIn.effect == .signIn)
        #expect(signingIn.state == .connecting)
        #expect(rowTitles(in: signingIn.descriptor).contains("Cancel sign-in"))

        let connected = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        #expect(connected.effect == .startFirstFetch)
        #expect(connected.descriptor.statusTitle == "Fetching portfolio")

        let complete = runtime.completeFirstFetch(.succeeded(pulse))
        #expect(complete.effect == .none)
        #expect(complete.state == .connected(.current))
        #expect(complete.descriptor.statusTitle == pulse.descriptor.statusTitle)
        #expect(freshnessRefreshDetailsAction(in: complete.descriptor)?.role == .fetchRetry)
        #expect(actionRow("actions.disconnect", in: complete.descriptor)?.role == .connectionDisconnect)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
    }

    @Test("A pasted token connects like a sign-in")
    func pastedTokenConnects() throws {
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .notConnected)

        let connecting = try #require(runtime.connect(token: PDTAPIToken("pdt_pasted")))
        #expect(connecting.effect == .connectToken(PDTAPIToken("pdt_pasted")))
        #expect(runtime.signIn() == nil)

        let connected = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        #expect(connected.effect == .startFirstFetch)
    }

    @Test("A returning launch with a cached pulse refreshes details in the background instead of a first fetch")
    func returningLaunchRunsBackgroundRefresh() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch()
        let checking = try #require(runtime.completeCachedPulseLoad(cachedPulse))
        #expect(checking.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: checking.descriptor).contains("Checking PDT connection"))
        #expect(actionRow("actions.refreshNow", in: checking.descriptor)?.role == .fetchStatus)
        #expect(runtime.retryFirstFetch() == nil)

        let connected = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)

        #expect(connected.effect == .startBackgroundDetailRefresh)
        #expect(!runtime.firstFetchInFlight)
        #expect(runtime.backgroundDetailRefreshInFlight)
        #expect(connected.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: connected.descriptor).contains("Filling details"))
        #expect(rowTitles(in: connected.descriptor).contains("Step 1/6: Base holdings"))
    }

    @Test("Stale and foreign connection outcomes are dropped")
    func staleConnectionOutcomesAreDropped() throws {
        let runtime = PDTLaunchRuntime()
        let other = PDTLaunchRuntime()
        _ = runtime.launch()
        _ = try #require(runtime.completeCachedPulseLoad(nil))
        let launchCheck = runtime.connectionAttempt
        _ = runtime.completeConnection(PDTConnectionOutcome(.notConnected), for: launchCheck)
        _ = try #require(runtime.signIn())

        let stale = runtime.completeConnection(PDTConnectionOutcome(.connected), for: launchCheck)
        let foreign = runtime.completeConnection(PDTConnectionOutcome(.connected), for: other.connectionAttempt)

        #expect(stale.effect == .none)
        #expect(stale.state == .connecting)
        #expect(foreign.effect == .none)
        #expect(foreign.state == .connecting)
        #expect(!runtime.firstFetchInFlight)

        let current = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        let duplicate = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        #expect(current.effect == .startFirstFetch)
        #expect(duplicate.effect == .none)
    }

    @Test("Connection actions are refused while a fetch runs, and the menu does not offer them")
    func connectionActionsRefusedWhileFetching() throws {
        let runtime = PDTLaunchRuntime()
        let fetching = launched(runtime, cachedPulse: nil, status: .connected)
        #expect(fetching.effect == .startFirstFetch)

        #expect(runtime.signIn() == nil)
        #expect(runtime.connect(token: PDTAPIToken("pdt_x")) == nil)
        #expect(runtime.checkAgain() == nil)
        #expect(runtime.disconnect() == nil)
        #expect(!rowRoles(in: fetching.descriptor).contains(.connectionDisconnect))

        let cachedRuntime = PDTLaunchRuntime()
        let refreshing = launched(cachedRuntime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)
        #expect(refreshing.effect == .startBackgroundDetailRefresh)
        #expect(cachedRuntime.disconnect() == nil)
        #expect(!rowRoles(in: refreshing.descriptor).contains(.connectionDisconnect))
    }

    @Test("A failed first fetch can be retried once at a time")
    func firstFetchRetryStartsOneFetch() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .connected)
        #expect(runtime.retryFirstFetch() == nil)

        let failed = runtime.completeFirstFetch(.failed(.unavailable))
        #expect(failed.state == .connected(.failed))
        #expect(runtime.currentPulse == nil)

        let retry = try #require(runtime.retryFirstFetch())
        let duplicateRetry = runtime.retryFirstFetch()
        let progress = try #require(runtime.firstFetchProgress(fetchingElapsedSeconds: 12))
        let complete = runtime.completeFirstFetch(.succeeded(pulse))

        #expect(retry.effect == .startFirstFetch)
        #expect(duplicateRetry == nil)
        #expect(progress.descriptor.statusTitle == "Fetching portfolio 0:12")
        #expect(complete.descriptor.statusTitle == pulse.descriptor.statusTitle)
    }

    @Test("A connection failure during the first fetch moves to that connection screen")
    func firstFetchConnectionFailureShowsConnectionScreen() {
        let cases: [(PDTConnectionStatus, PDTLaunchState)] = [
            (.needsReconnect(.personalToken, .tokenRevoked), .needsReconnect(.personalToken, .tokenRevoked)),
            (.subscriptionPaused, .subscriptionPaused),
            (.keychainUnavailable(.missingEntitlement), .keychainUnavailable(.missingEntitlement)),
        ]
        for (status, state) in cases {
            let runtime = PDTLaunchRuntime()
            _ = launched(runtime, cachedPulse: nil, status: .connected)

            let failed = runtime.completeFirstFetch(.failed(.connection(status)))

            #expect(failed.state == state)
            #expect(failed.effect == .none)
            #expect(runtime.currentPulse == nil)
            #expect(!runtime.firstFetchInFlight)
        }
    }

    @Test("A fetch result with no fetch running changes nothing")
    func strayFetchResultsAreIgnored() throws {
        let runtime = PDTLaunchRuntime()
        let notConnected = launched(runtime, cachedPulse: nil, status: .notConnected)

        let firstFetch = runtime.completeFirstFetch(.succeeded(try quietFixturePulse()))
        let refresh = runtime.completeBackgroundDetailRefresh(.failed(.connection(.subscriptionPaused)))

        #expect(firstFetch.state == .notConnected)
        #expect(refresh.state == .notConnected)
        #expect(runtime.currentPulse == nil)
        #expect(refresh.descriptor == notConnected.descriptor)
    }

    @Test("Reconnect and paused keep the cached pulse visible; a later not connected hides it")
    func connectionFailuresAndCachedPulse() throws {
        let cachedPulse = try cachedQuietFixturePulse()

        let cases: [(PDTConnectionStatus, PDTLaunchState)] = [
            (.needsReconnect(.browserSession, .signInExpired), .needsReconnect(.browserSession, .signInExpired)),
            (.subscriptionPaused, .subscriptionPaused),
        ]
        for (status, state) in cases {
            let runtime = PDTLaunchRuntime()
            _ = launched(runtime, cachedPulse: cachedPulse, status: .connected)

            let failed = runtime.completeBackgroundDetailRefresh(.failed(.connection(status)))

            #expect(failed.state == state)
            #expect(failed.descriptor.sections.first?.id == "pdtConnection")
            #expect(failed.descriptor.sections.map(\.id).contains("pulse"))
            #expect(runtime.currentPulse?.source == .cachedSnapshot)
        }

        let runtime = PDTLaunchRuntime()
        let notConnected = launched(runtime, cachedPulse: cachedPulse, status: .notConnected)
        #expect(notConnected.descriptor.sections.map(\.id) == ["pdtConnection"])
    }

    @Test("Check again from a paused subscription reruns one check, then reaches the fetch")
    func checkAgainRerunsOneCheck() throws {
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .subscriptionPaused)

        let check = try #require(runtime.checkAgain())
        #expect(check.effect == .checkConnection)
        #expect(check.state == .checkingConnection)
        #expect(runtime.checkAgain() == nil)
        #expect(runtime.signIn() == nil)

        let connected = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        #expect(connected.effect == .startFirstFetch)
    }

    @Test("Cancel is offered only while signing in, and the sign-in outcome still ends the operation")
    func cancelSignIn() throws {
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .notConnected)
        #expect(runtime.cancelSignIn() == nil)

        _ = try #require(runtime.signIn())
        let cancel = try #require(runtime.cancelSignIn())
        #expect(cancel.effect == .cancelSignIn)
        #expect(cancel.state == .connecting)

        let ended = runtime.completeConnection(PDTConnectionOutcome(.notConnected), for: runtime.connectionAttempt)
        #expect(ended.state == .notConnected)
        #expect(rowTitles(in: ended.descriptor).contains("Sign in with PDT"))
        #expect(!rowTitles(in: ended.descriptor).contains("Sign-in failed"))
    }

    @Test("A failed sign-in shows its notice until the next connection operation")
    func signInFailureNoticeClearsOnNextOperation() throws {
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .notConnected)
        _ = try #require(runtime.signIn())

        let failed = runtime.completeConnection(
            PDTConnectionOutcome(.notConnected, notice: .signInFailed(.portBusy)),
            for: runtime.connectionAttempt
        )
        #expect(rowTitles(in: failed.descriptor).contains("Sign-in failed"))

        let retry = try #require(runtime.signIn())
        #expect(!rowTitles(in: retry.descriptor).contains("Sign-in failed"))
    }

    @Test("Disconnect hides the pulse and links to the PDT revoke page")
    func disconnectHidesPulseAndLinksRevokePage() throws {
        let pulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .connected)
        _ = runtime.completeFirstFetch(.succeeded(pulse))

        let disconnecting = try #require(runtime.disconnect())
        #expect(disconnecting.effect == .disconnect)
        #expect(disconnecting.state == .disconnecting)
        #expect(runtime.disconnect() == nil)

        let done = runtime.completeConnection(
            PDTConnectionOutcome(.notConnected, notice: .disconnected(revokeAt: PDTOAuthEndpoints.connectedApps)),
            for: runtime.connectionAttempt
        )

        #expect(done.state == .notConnected)
        #expect(done.descriptor.sections.map(\.id) == ["pdtConnection"])
        #expect(done.descriptor.sections.flatMap(\.rows).first { $0.id == "pdtConnection.revoke" }?.actionPayload
            == PDTOAuthEndpoints.connectedApps.absoluteString)
    }

    @Test("Mark-read republish during the connection check keeps the check")
    func markReadRepublishDuringCheckKeepsTheCheck() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = runtime.launch()
        _ = try #require(runtime.completeCachedPulseLoad(cachedPulse))

        let republished = try #require(runtime.pulseReadStateDidChange())

        #expect(republished.state == .checkingConnection)
        #expect(republished.effect == .none)
        #expect(rowTitles(in: republished.descriptor).contains("Checking PDT connection"))
        #expect(runtime.retryFirstFetch() == nil)
    }

    @Test("Background refresh reports progress over the cached pulse")
    func backgroundRefreshReportsProgress() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: cachedPulse, status: .connected)

        let progress = try #require(runtime.backgroundDetailRefreshProgress(
            BackgroundDetailRefreshProgress(phase: .priceHistory, completedUnitCount: 12, totalUnitCount: 19)
        ))

        #expect(progress.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: progress.descriptor).contains("Step 5/6: Price history"))
        #expect(rowTitles(in: progress.descriptor).contains("12/19 price histories checked"))
        #expect(!rowTitles(in: progress.descriptor).contains("Details fill failed"))
    }

    @Test("A completed background refresh publishes the refreshed pulse")
    func completedBackgroundRefreshPublishes() throws {
        let refreshedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)

        let completed = runtime.completeBackgroundDetailRefresh(.succeeded(refreshedPulse, outcome: .completed))

        #expect(!runtime.backgroundDetailRefreshInFlight)
        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(completed.descriptor.statusTitle == refreshedPulse.descriptor.statusTitle)
        #expect(freshnessRefreshDetailsAction(in: completed.descriptor)?.role == .fetchRetry)
        #expect(!rowTitles(in: completed.descriptor).contains("Details partially filled"))
    }

    @Test("A degraded background refresh publishes the pulse and offers a retry")
    func degradedBackgroundRefresh() throws {
        let refreshedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)

        let degraded = runtime.completeBackgroundDetailRefresh(.succeeded(refreshedPulse, outcome: .degraded))

        #expect(runtime.currentPulse?.source == .fetchedSnapshot)
        #expect(rowTitles(in: degraded.descriptor).contains("Details partially filled"))
        #expect(rowTitles(in: degraded.descriptor).contains("Fill details again"))
    }

    @Test("A failed or partly filled refresh offers its retry once, beside the notice, and that retry starts a refresh")
    func failedOrDegradedRefreshOffersRetryOnce() throws {
        let failedRuntime = PDTLaunchRuntime()
        _ = launched(failedRuntime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)
        let failed = failedRuntime.completeBackgroundDetailRefresh(.failed(.unavailable))

        let degradedRuntime = PDTLaunchRuntime()
        _ = launched(degradedRuntime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)
        let degraded = degradedRuntime.completeBackgroundDetailRefresh(.succeeded(try quietFixturePulse(), outcome: .degraded))

        for (runtime, update, notice) in [
            (failedRuntime, failed, "Details fill failed"),
            (degradedRuntime, degraded, "Details partially filled"),
        ] {
            let fetchRows = try #require(update.descriptor.sections.first { $0.id == "portfolioFetch" }).rows
            #expect(fetchRows.map(\.title) == [notice, "Fill details again"], "\(notice)")
            #expect(rowRoles(in: update.descriptor).filter { $0 == .fetchRetry }.count == 1, "\(notice)")
            #expect(actionRow("actions.refreshNow", in: update.descriptor) == nil, "\(notice)")
            #expect(actionRow("actions.openPDT", in: update.descriptor)?.role == .openPDT, "\(notice)")
            #expect(actionRow("actions.settings", in: update.descriptor)?.role == .settings, "\(notice)")

            let retry = try #require(runtime.retryFirstFetch(), "\(notice)")
            #expect(retry.effect == .startBackgroundDetailRefresh, "\(notice)")
            #expect(actionRow("actions.refreshNow", in: retry.descriptor)?.title == "Refreshing now", "\(notice)")
        }

        let completedRuntime = PDTLaunchRuntime()
        _ = launched(completedRuntime, cachedPulse: try cachedQuietFixturePulse(), status: .connected)
        let completed = completedRuntime.completeBackgroundDetailRefresh(.succeeded(try quietFixturePulse(), outcome: .completed))
        #expect(actionRow("actions.refreshNow", in: completed.descriptor)?.role == .fetchRetry)
        #expect(actionRow("actions.refreshNow", in: completed.descriptor)?.title == "Refresh now")
    }

    @Test("A failed background refresh keeps the cached pulse, says what to do, and retries once at a time")
    func failedBackgroundRefresh() throws {
        let cachedPulse = try cachedQuietFixturePulse()
        let runtime = PDTLaunchRuntime()
        let failure = PDTSyncFailure(
            phase: .baseHoldings,
            endpoint: .holdings,
            kind: .rateLimited(retryAfterSeconds: 120),
            requestCount: 3
        )
        let refreshing = launched(runtime, cachedPulse: cachedPulse, status: .connected)

        let failed = runtime.completeBackgroundDetailRefresh(.failed(.unavailable, failure: failure))

        #expect(runtime.currentPulse?.source == .cachedSnapshot)
        #expect(failed.descriptor.statusTitle == cachedPulse.descriptor.statusTitle)
        #expect(rowTitles(in: failed.descriptor).contains("Details fill failed"))
        #expect(healthRow(in: failed.descriptor)?.detail == "Needs attention")
        #expect(healthDetail("access", in: failed.descriptor) == "Connected")
        #expect(healthDetail("detailFill", in: failed.descriptor) == "Failed")
        #expect(healthDetail("diagnostic", in: failed.descriptor) == "Base holdings: PDT rate limit; try again in 2 min")
        #expect(healthDetail("source", in: failed.descriptor)?.contains("saved copy") == true)
        #expect(healthDetail("cache", in: failed.descriptor) == healthDetail("cache", in: refreshing.descriptor))
        #expect(healthDetail("freshness", in: failed.descriptor) == healthDetail("freshness", in: refreshing.descriptor))
        #expect(actionRow("actions.disconnect", in: failed.descriptor) != nil)

        let retry = try #require(runtime.retryFirstFetch())
        #expect(retry.effect == .startBackgroundDetailRefresh)
        #expect(runtime.retryFirstFetch() == nil)
        #expect(rowTitles(in: retry.descriptor).contains("Filling details"))
        #expect(!rowTitles(in: retry.descriptor).contains("Details fill failed"))
        #expect(healthRow(in: retry.descriptor)?.detail == "Refreshing")
    }

    @Test("A launch over a saved copy says checking, then refreshing, and is healthy only once a sync commits")
    func savedCopyIsNeverShownAsVerified() throws {
        let runtime = PDTLaunchRuntime()

        _ = runtime.launch()
        let checking = try #require(runtime.completeCachedPulseLoad(try cachedQuietFixturePulse()))
        #expect(healthRow(in: checking.descriptor)?.detail == "Checking")
        #expect(healthDetail("access", in: checking.descriptor) == "Checking")
        #expect(healthDetail("source", in: checking.descriptor)?.contains("saved copy") == true)

        let refreshing = runtime.completeConnection(PDTConnectionOutcome(.connected), for: runtime.connectionAttempt)
        #expect(healthRow(in: refreshing.descriptor)?.detail == "Refreshing")
        #expect(healthDetail("access", in: refreshing.descriptor) == "Connected")
        #expect(healthDetail("source", in: refreshing.descriptor)?.contains("saved copy") == true)

        let refreshed = runtime.completeBackgroundDetailRefresh(.succeeded(try quietFixturePulse(), outcome: .completed))
        #expect(healthRow(in: refreshed.descriptor) == nil)
    }

    @Test(
        "A connection screen over a saved copy says in Data health why access stopped",
        arguments: [
            (PDTConnectionStatus.needsReconnect(.browserSession, .signInExpired), "Reconnect needed: your PDT sign-in has expired"),
            (.needsReconnect(.personalToken, .tokenRevoked), "Reconnect needed: PDTBar's access was revoked in PDT"),
            (.needsReconnect(.personalToken, .readAccessMissing), "Reconnect needed: this connection can't read your portfolio"),
            (.subscriptionPaused, "Paused: your PDT subscription has ended"),
            (.keychainUnavailable(.failed), "Keychain unavailable"),
        ]
    )
    func connectionScreenNamesAccessProblem(status: PDTConnectionStatus, access: String) throws {
        let runtime = PDTLaunchRuntime()

        let screen = launched(runtime, cachedPulse: try cachedQuietFixturePulse(), status: status)

        #expect(screen.descriptor.sections.first?.id == "pdtConnection")
        #expect(healthRow(in: screen.descriptor)?.detail == "Needs attention")
        #expect(healthDetail("access", in: screen.descriptor) == access)
        #expect(healthDetail("source", in: screen.descriptor)?.contains("saved copy") == true)
    }

    @Test("Republished fetched pulse keeps live-verified source facts")
    func republishedFetchedPulseKeepsLiveVerifiedSourceFacts() throws {
        let fetchedPulse = try quietFixturePulse()
        let runtime = PDTLaunchRuntime()
        _ = launched(runtime, cachedPulse: nil, status: .connected)
        _ = runtime.completeFirstFetch(.succeeded(fetchedPulse))

        let republished = try #require(runtime.pulseReadStateDidChange())

        #expect(fetchedPulse.model.facetSnapshots.dataHealth.status == .healthy)
        #expect(healthRow(in: republished.descriptor) == nil)
        #expect(republished.descriptor.sections.first { $0.id == "freshness" }?.title == "Data")
    }
}

/// Runs launch through the cached pulse load and the connection check.
@discardableResult
private func launched(
    _ runtime: PDTLaunchRuntime,
    cachedPulse: PulseLifecycleResult?,
    status: PDTConnectionStatus
) -> PDTOnboardingUpdate {
    _ = runtime.launch()
    _ = runtime.completeCachedPulseLoad(cachedPulse)
    return runtime.completeConnection(PDTConnectionOutcome(status), for: runtime.connectionAttempt)
}

@Suite("Launch surface")
struct LaunchSurfaceTests {
    @Test("Quiet fixture descriptor renders stable launch surface")
    func quietFixtureDescriptorRendersStableLaunchSurface() throws {
        let descriptor = try quietFixtureDescriptor()
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)

        #expect(descriptor.statusTitle == "All quiet")
        #expect(descriptor.statusVisual.filledBarCount == 0)
        #expect(!descriptor.statusVisual.isDimmed)
        #expect(descriptor.sections.map(\.id) == ["summary", "pulse", "allocation", "income", "bigMovers", "freshness", "actions"])
        let dataSection = try #require(descriptor.sections.first { $0.id == "freshness" })
        let prices = try #require(dataSection.rows.first { $0.id == "freshness.summary" })
        #expect(dataSection.title == "Data")
        #expect(prices.title == "Prices")
        #expect(prices.detail == "Current through 2026-06-22")
        #expect(healthRow(in: descriptor) == nil)
        #expect(actionRow("actions.refreshNow", in: descriptor)?.role == .fetchRetry)
        #expect(actionRow("actions.openPDT", in: descriptor)?.role == .openPDT)
        #expect(actionRow("actions.settings", in: descriptor)?.title == "Settings...")
        #expect(actionRow("actions.settings", in: descriptor)?.role == .settings)
        #expect(surface.status.title == "All quiet")
        #expect(surface.status.menuBarTitle.isEmpty)
        #expect(surface.status.visual == descriptor.statusVisual)
        #expect(surface.status.accessibilityIdentifier == "pdtbar.status")
        #expect(surface.sections.first { $0.id == "pulse" }?.rows.first?.title == "All quiet")
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
        pulseReadStore: PulseReadStore(directory: snapshotStore.directory),
        today: "2026-06-22"
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

private func healthDetail(_ row: String, in descriptor: MenuDescriptor) -> String? {
    healthRow(in: descriptor)?.children.first { $0.id == "dataHealth.\(row)" }?.detail
}

private func freshnessRefreshDetailsAction(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections
        .first { $0.id == "freshness" }?
        .rows
        .first { $0.id == "freshness.summary" }?
        .children
        .first { $0.id == "freshness.refreshDetails" }
}

private func rowRoles(in descriptor: MenuDescriptor) -> [MenuRowRole] {
    func roles(_ rows: [MenuRow]) -> [MenuRowRole] {
        rows.flatMap { [$0.role] + roles($0.children) }
    }
    return roles(descriptor.sections.flatMap(\.rows))
}

private func actionRow(_ id: String, in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections
        .first { $0.id == "actions" }?
        .rows
        .first { $0.id == id }
}
