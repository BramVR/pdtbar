// swiftlint:disable file_length
// Tracked debt: finding 20 will split this smoke harness.
import ApplicationServices
import AppKit
import Foundation
import ImageIO
import PDTBarAppSupport
import PDTBarCore
import Security

private struct SmokeReport: Codable {
    var name: String
    var status: String
    var detail: String
    var artifacts: [String]
}

private enum SmokeStatus {
    static let passed = "passed"
    static let skipped = "skipped"
    static let failed = "failed"
}

private let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let defaultFixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
private let pinnedMcporterVersion = "0.12.2"
private let scriptedPDTAsOf = "2026-06-22"

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw CommandError.usage
    }

    let report: SmokeReport
    switch command {
    case "manual-claude-pdt":
        report = try manualClaudePDTSmoke(arguments: Array(arguments.dropFirst()))
    case "live-pdt":
        report = try livePDTSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-pdt-connector":
        report = try scriptedPDTConnectorSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-api-client":
        report = try scriptedAPIClientSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-api-snapshot":
        report = try scriptedAPISnapshotSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-api-auth":
        report = try scriptedAPIAuthSmoke(arguments: Array(arguments.dropFirst()))
    case "copy-holding-identifier-action":
        report = copyHoldingIdentifierActionSmoke()
    case "scripted-first-fetch":
        report = try scriptedFirstFetchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-returning-launch":
        report = try scriptedReturningLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-sign-in":
        report = try scriptedSignInSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-setup-retry":
        report = try scriptedSetupRetrySmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-pulse-mark-read":
        report = try scriptedPulseMarkReadSmoke(arguments: Array(arguments.dropFirst()))
    case "logged-out-launch":
        report = try loggedOutLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "ready-launch":
        report = try readyLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "app-bundle-packaging":
        report = try appBundlePackagingSmoke(arguments: Array(arguments.dropFirst()))
    case "packaged-onboarding":
        report = try packagedOnboardingSmoke(arguments: Array(arguments.dropFirst()))
    case "packaged-app":
        report = try packagedAppSmoke(arguments: Array(arguments.dropFirst()))
    case "peekaboo":
        report = try peekabooSmoke(arguments: Array(arguments.dropFirst()))
    case "real-user-pulse":
        report = try realUserPulseSmoke(arguments: Array(arguments.dropFirst()))
    case "portfolio-summary-proof":
        report = try portfolioSummaryProof(arguments: Array(arguments.dropFirst()))
    case "portfolio-values-settings-proof":
        report = try portfolioValuesSettingsProof(arguments: Array(arguments.dropFirst()))
    case "fixture-proof":
        report = try fixtureProof(arguments: Array(arguments.dropFirst()))
    case "menu-polish-proof":
        report = try menuPolishProof(arguments: Array(arguments.dropFirst()))
    default:
        throw CommandError.usage
    }

    try writeReport(report)
    Foundation.exit(report.status == SmokeStatus.failed ? 1 : 0)
} catch CommandError.usage {
    FileHandle.standardError.write(Data("""
    usage:
      pdtbar-smoke manual-claude-pdt [--claude <path>] [--model <alias>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke live-pdt [--server <mcporter-server>] [--mcporter <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-pdt-connector [--artifacts <dir>]
      pdtbar-smoke scripted-api-client [--artifacts <dir>]
      pdtbar-smoke scripted-api-snapshot [--artifacts <dir>]
      pdtbar-smoke scripted-api-auth [--artifacts <dir>]
      pdtbar-smoke copy-holding-identifier-action
      pdtbar-smoke scripted-first-fetch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-returning-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-sign-in [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-setup-retry [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-pulse-mark-read [--artifacts <dir>]
      pdtbar-smoke logged-out-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke ready-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke app-bundle-packaging [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke packaged-onboarding [--app <path-to-PDTBar.app>] [--app-support-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
      pdtbar-smoke packaged-app [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--timeout <seconds>]
      pdtbar-smoke peekaboo [--peekaboo <path>] [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>]
      pdtbar-smoke real-user-pulse [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
      pdtbar-smoke portfolio-summary-proof [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
      pdtbar-smoke portfolio-values-settings-proof [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
      pdtbar-smoke fixture-proof [--fixture <path>] [--output <path>]
      pdtbar-smoke menu-polish-proof [--output <path>]

    """.utf8))
    Foundation.exit(64)
} catch {
    try? writeReport(SmokeReport(
        name: "smoke",
        status: SmokeStatus.failed,
        detail: "\(error)",
        artifacts: []
    ))
    Foundation.exit(1)
}

// MARK: - Scripted PDT connection launches

/// One app launch over `--scripted-pdt` with isolated app support. The fixture
/// environment and a fake `claude`/`mcporter` first on PATH are traps: a
/// correct launch never writes the fixture sentinel or the CLI marker.
private struct ScriptedPDTLaunch {
    let appSupportDirectory: URL
    let script: URL
    let eventLog: URL
    let stderrLog: URL
    let snapshot: URL
    let fixtureSentinel: URL
    let cliMarker: URL
    let process: Process

    var fixtureSentinelEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: fixtureSentinel.path)) ?? []).isEmpty
    }

    var cliSpawned: Bool {
        FileManager.default.fileExists(atPath: cliMarker.path)
    }

    var snapshotWritten: Bool {
        FileManager.default.fileExists(atPath: snapshot.path)
    }

    var arguments: [String] {
        ["--app-support-dir", artifactPath(appSupportDirectory), "--scripted-pdt", artifactPath(script)]
    }

    func eventCount(_ event: String) -> Int {
        guard let content = try? String(contentsOf: eventLog, encoding: .utf8) else {
            return 0
        }
        return content.split(separator: "\n").filter { $0 == event }.count
    }

    func waitForEventCount(_ event: String, atLeast count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if eventCount(event) >= count {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return eventCount(event) >= count
    }

    func stderrContains(_ needle: String) -> Bool {
        ((try? String(contentsOf: stderrLog, encoding: .utf8)) ?? "").contains(needle)
    }
}

private struct ScriptedPDTFiles {
    let script: URL
    let eventLog: URL
}

/// Writes the script into `<appSupport>/scripted-pdt.json` with its event log beside it.
private func writeScriptedPDT(_ script: ScriptedPDTConnection, appSupportDirectory: URL) throws -> ScriptedPDTFiles {
    let eventLog = appSupportDirectory.appending(path: "scripted-pdt-events.log")
    var script = script
    script.eventLog = eventLog.path
    let scriptURL = appSupportDirectory.appending(path: "scripted-pdt.json")
    try stableJSONData(script).write(to: scriptURL, options: .atomic)
    return ScriptedPDTFiles(script: scriptURL, eventLog: eventLog)
}

private func launchScriptedPDTApp(
    _ app: URL,
    script: ScriptedPDTConnection,
    options: SmokeOptions,
    prefix: String,
    seed: PortfolioSnapshot? = nil
) throws -> ScriptedPDTLaunch {
    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "\(prefix)-app-support")
    let stateDirectory = appSupportDirectory.appending(path: "pdtbar/state")
    if let seed {
        _ = try SnapshotStore(directory: stateDirectory).commitCurrentSnapshot(seed)
    }
    let files = try writeScriptedPDT(script, appSupportDirectory: appSupportDirectory)
    let fixtureSentinel = try options.temporarySnapshotDirectory(prefix: "\(prefix)-fixture-sentinel")
    let cliMarker = appSupportDirectory.appending(path: "cli-spawned.log")
    let fakeBin = appSupportDirectory.appending(path: "fake-cli-bin")
    try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
    for name in ["claude", "mcporter"] {
        let fake = fakeBin.appending(path: name)
        let body = "#!/bin/sh\nprintf '%s %s\\n' \"$(basename \"$0\")\" \"$*\" >> '\(cliMarker.path)'\nexit 1\n"
        try Data(body.utf8).write(to: fake, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    }
    let stderrLog = appSupportDirectory.appending(path: "pdtbar-stderr.log")
    FileManager.default.createFile(atPath: stderrLog.path, contents: nil)

    let process = Process()
    process.executableURL = app
    process.arguments = ["--app-support-dir", appSupportDirectory.path, "--scripted-pdt", files.script.path]
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_APP_SUPPORT_DIR")
    process.environment = environment.merging([
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSentinel.path,
        "PATH": "\(fakeBin.path):\(environment["PATH"] ?? "/usr/bin:/bin")",
    ]) { _, new in new }
    process.standardError = try FileHandle(forWritingTo: stderrLog)
    try process.run()
    return ScriptedPDTLaunch(
        appSupportDirectory: appSupportDirectory,
        script: files.script,
        eventLog: files.eventLog,
        stderrLog: stderrLog,
        snapshot: stateDirectory.appending(path: "latest-portfolio-snapshot.json"),
        fixtureSentinel: fixtureSentinel,
        cliMarker: cliMarker,
        process: process
    )
}

private func scriptedHoldingsResponse() throws -> ScriptedPDTAPIConfiguration.Response {
    let holdings = packageRoot.appending(path: "docs/pdt/fixtures/api/full/01-holdings.json")
    return ScriptedPDTAPIConfiguration.Response(body: String(decoding: try Data(contentsOf: holdings), as: UTF8.self))
}

private func scriptedAPIError(_ status: Int, _ code: String, headers: [String: String]? = nil) -> ScriptedPDTAPIConfiguration.Response {
    ScriptedPDTAPIConfiguration.Response(
        status: status,
        body: #"{"error":{"code":"\#(code)","message":"m","details":{},"traceId":"t"}}"#,
        headers: headers
    )
}

/// Enough 503s to exhaust the client's retries on the required holdings request.
private func scriptedHoldingsUnavailable() -> [ScriptedPDTAPIConfiguration.Response] {
    Array(
        repeating: scriptedAPIError(503, "SERVICE_UNAVAILABLE", headers: ["Retry-After": "0"]),
        count: PDTAPIRequestPolicy().maxAttempts
    )
}

/// The pulse the app's first fetch builds from the same scripted replies.
private func expectedFirstFetchPulse(_ api: ScriptedPDTAPIConfiguration) throws -> PulseLifecycleResult {
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-first-fetch-expected")
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    return try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTAPIDataSource(
            client: PDTAPIClient(
                transport: api.transport(),
                tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("scripted"))
            ),
            options: .firstFetch
        ),
        snapshotStore: store,
        asOf: api.asOf
    ).fetch()
}

private struct MenuCheck: Codable {
    var name: String
    var visible: Bool
    var openAttempt: String?
    var evidencePath: String?
}

/// Opens the status menu and checks it shows `descriptor`'s rows and `texts`.
private func checkMenu(
    _ name: String,
    descriptor: MenuDescriptor,
    pulse: Bool = false,
    texts: [String] = [],
    forbiddenTexts: [String] = [],
    process: Process,
    timeout: TimeInterval,
    artifacts: URL
) throws -> MenuCheck {
    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let targets = pulse ? requiredPulseMenuTargets(in: surface) : requiredSetupMenuTargets(in: surface)
    let identifiers = Set(targets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    _ = waitForStatusText(descriptor.statusTitle, in: appElement, statusIdentifier: surface.status.accessibilityIdentifier, timeout: timeout)
    guard let status = waitForAccessibilityElement(in: appElement, identifier: surface.status.accessibilityIdentifier, timeout: timeout) else {
        return MenuCheck(name: name, visible: false, openAttempt: "status item missing", evidencePath: nil)
    }
    let opened = openStatusMenu(status, appElement: appElement, expectedMenuIdentifiers: identifiers, timeout: timeout)
    let snapshot = opened.snapshot ?? waitForAccessibilityIdentifiers(identifiers, in: appElement, timeout: timeout)
    let evidence = artifacts.appending(path: "pdtbar-\(name)-ax.json")
    try writeAccessibilityEvidence(
        snapshot: snapshot,
        expected: targets,
        statusIdentifier: surface.status.accessibilityIdentifier,
        statusText: accessibilityTexts(in: status),
        output: evidence
    )
    pressEscape()
    Thread.sleep(forTimeInterval: 0.2)
    let visible = identifiers.isSubset(of: snapshot.identifiers)
        && texts.allSatisfy { text in snapshot.texts.contains { $0.contains(text) } }
        && forbiddenTexts.allSatisfy { text in !snapshot.texts.contains { $0.contains(text) } }
    return MenuCheck(
        name: name,
        visible: visible,
        openAttempt: opened.successfulAttempt ?? opened.attempts.joined(separator: "; "),
        evidencePath: artifactPath(evidence)
    )
}

/// Clicks a menu row through Accessibility while the menu shows `descriptor`.
private func clickMenuRow(_ rowID: String, descriptor: MenuDescriptor, process: Process, timeout: TimeInterval) -> String? {
    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let identifiers = Set(requiredSetupMenuTargets(in: surface).map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    guard let status = waitForAccessibilityElement(in: appElement, identifier: surface.status.accessibilityIdentifier, timeout: timeout) else {
        return nil
    }
    return pressMenuRow(
        statusElement: status,
        appElement: appElement,
        rowIdentifier: "pdtbar.row.\(rowID)",
        expectedMenuIdentifiers: identifiers,
        timeout: timeout
    )
}

private func missingAppReport(_ name: String) -> SmokeReport {
    SmokeReport(
        name: name,
        status: SmokeStatus.failed,
        detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
        artifacts: []
    )
}

private func smokeArtifacts(_ options: SmokeOptions) throws -> URL {
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    return artifacts
}

private struct ScriptedLaunchIsolation: Codable {
    var appArguments: [String]
    var processStillRunning: Bool
    var cliSpawned: Bool
    var fixtureSentinelEmpty: Bool
}

private func isolation(_ launch: ScriptedPDTLaunch) -> ScriptedLaunchIsolation {
    ScriptedLaunchIsolation(
        appArguments: launch.arguments,
        processStillRunning: launch.process.isRunning,
        cliSpawned: launch.cliSpawned,
        fixtureSentinelEmpty: launch.fixtureSentinelEmpty
    )
}

private extension ScriptedLaunchIsolation {
    var clean: Bool { processStillRunning && !cliSpawned && fixtureSentinelEmpty }
}

// MARK: scripted-first-fetch

private struct ScriptedFirstFetchProof: Codable {
    var success: ScriptedLaunchIsolation
    var successSnapshotPath: String
    var successSnapshotWritten: Bool
    var successSnapshotAsOf: String?
    var successOpenHoldingCount: Int
    var successHoldingsRequests: Int
    var successPulseMenu: MenuCheck?
    var failure: ScriptedLaunchIsolation
    var failureHoldingsRequests: Int
    var failureSnapshotWritten: Bool
    var failureReported: Bool
    var failureMenu: MenuCheck?
    var accessibilityChecked: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private func scriptedFirstFetchSmoke(arguments: [String]) throws -> SmokeReport {
    let name = "scripted-first-fetch"
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return missingAppReport(name)
    }
    let artifacts = try smokeArtifacts(options)
    let proof = artifacts.appending(path: "pdtbar-scripted-first-fetch-proof.json")
    let accessibilityChecked = AXIsProcessTrusted()

    let successAPI = ScriptedPDTAPIConfiguration(responses: [try scriptedHoldingsResponse()], asOf: scriptedPDTAsOf)
    let expectedPulse = try expectedFirstFetchPulse(successAPI)
    let success = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .personalToken, api: successAPI),
        options: options,
        prefix: "\(name)-success"
    )
    defer { terminate(success.process) }
    let successSnapshotWritten = waitForFile(success.snapshot, timeout: options.timeout + 3.0)
    let publishedSnapshot = try? JSONDecoder().decode(PortfolioSnapshot.self, from: Data(contentsOf: success.snapshot))
    let successPulseMenu = accessibilityChecked
        ? try checkMenu(
            "\(name)-success",
            descriptor: expectedPulse.descriptor,
            pulse: true,
            process: success.process,
            timeout: options.timeout,
            artifacts: artifacts
        )
        : nil
    let successIsolation = isolation(success)
    terminate(success.process)

    let failure = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(
            connection: .personalToken,
            api: ScriptedPDTAPIConfiguration(responses: scriptedHoldingsUnavailable(), asOf: scriptedPDTAsOf)
        ),
        options: options,
        prefix: "\(name)-failure"
    )
    defer { terminate(failure.process) }
    let attempts = PDTAPIRequestPolicy().maxAttempts
    _ = failure.waitForEventCount("request /v1/portfolio/holdings", atLeast: attempts, timeout: options.timeout + 3.0)
    let failureReported = waitForFileContent(failure.stderrLog, contains: "first fetch failed", timeout: options.timeout + 3.0)
    let failureMenu = accessibilityChecked
        ? try checkMenu(
            "\(name)-failure",
            descriptor: PDTLaunchMenu.descriptor(for: .connected(.failed)),
            texts: ["Could not fetch portfolio", "Try again"],
            process: failure.process,
            timeout: options.timeout,
            artifacts: artifacts
        )
        : nil
    let failureIsolation = isolation(failure)

    let proofPayload = ScriptedFirstFetchProof(
        success: successIsolation,
        successSnapshotPath: artifactPath(success.snapshot),
        successSnapshotWritten: successSnapshotWritten,
        successSnapshotAsOf: publishedSnapshot?.asOf,
        successOpenHoldingCount: publishedSnapshot?.openHoldings.count ?? 0,
        successHoldingsRequests: success.eventCount("request /v1/portfolio/holdings"),
        successPulseMenu: successPulseMenu,
        failure: failureIsolation,
        failureHoldingsRequests: failure.eventCount("request /v1/portfolio/holdings"),
        failureSnapshotWritten: failure.snapshotWritten,
        failureReported: failureReported,
        failureMenu: failureMenu,
        accessibilityChecked: accessibilityChecked,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)
    let artifactsList = [artifactPath(proof)] + [successPulseMenu, failureMenu].compactMap { $0?.evidencePath }

    guard successIsolation.clean,
          successSnapshotWritten,
          proofPayload.successSnapshotAsOf == scriptedPDTAsOf,
          proofPayload.successOpenHoldingCount > 0,
          proofPayload.successHoldingsRequests >= 1,
          failureIsolation.clean,
          proofPayload.failureHoldingsRequests == attempts,
          !proofPayload.failureSnapshotWritten,
          failureReported,
          successPulseMenu?.visible ?? true,
          failureMenu?.visible ?? true
    else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "scripted PDT first fetch did not prove publish-on-success, no snapshot on a failed holdings fetch, and no CLI or fixture fallback",
            artifacts: artifactsList
        )
    }
    guard accessibilityChecked else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "connected first fetch wrote the snapshot; failed holdings fetch wrote none and reported the failure; no CLI spawned, no fixture state; macOS Accessibility permission missing for menu inspection",
            artifacts: artifactsList
        )
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "connected first fetch wrote the snapshot and showed the pulse; failed holdings fetch wrote none and showed Could not fetch portfolio; no CLI spawned, no fixture state",
        artifacts: artifactsList
    )
}

// MARK: scripted-setup-retry

private struct ScriptedSetupRetryScenarioProof: Codable {
    var name: String
    var isolation: ScriptedLaunchIsolation
    var initialChecks: Int
    var initialHoldingsRequests: Int
    var initialMenu: MenuCheck?
    var checkAgainClicks: [String?]
    var finalChecks: Int
    var finalHoldingsRequests: Int
    var snapshotWritten: Bool
    var passed: Bool
}

private struct ScriptedSetupRetryProof: Codable {
    var accessibilityChecked: Bool
    var scenarios: [ScriptedSetupRetryScenarioProof]
    var rawPortfolioPayloadsRedacted: Bool
}

private struct SetupRetryScenario {
    var name: String
    var script: ScriptedPDTConnection
    var state: PDTLaunchState
    /// Holdings requests the launch makes before the user acts.
    var initialHoldingsRequests: Int
    /// Whether Check again reaches a successful fetch.
    var reachesFetch: Bool
}

private func scriptedSetupRetrySmoke(arguments: [String]) throws -> SmokeReport {
    let name = "scripted-setup-retry"
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return missingAppReport(name)
    }
    let artifacts = try smokeArtifacts(options)
    let proof = artifacts.appending(path: "pdtbar-scripted-setup-retry-proof.json")
    let accessibilityChecked = AXIsProcessTrusted()
    let holdings = try scriptedHoldingsResponse()
    let scenarios = [
        SetupRetryScenario(
            name: "reconnect",
            script: ScriptedPDTConnection(connection: .tokenRevoked, api: ScriptedPDTAPIConfiguration(responses: [holdings], asOf: scriptedPDTAsOf)),
            state: .needsReconnect(.personalToken, .tokenRevoked),
            initialHoldingsRequests: 0,
            reachesFetch: false
        ),
        SetupRetryScenario(
            name: "subscription-paused",
            script: ScriptedPDTConnection(
                connection: .personalToken,
                api: ScriptedPDTAPIConfiguration(responses: [scriptedAPIError(403, "API_ACCESS_PAUSED"), holdings], asOf: scriptedPDTAsOf)
            ),
            state: .subscriptionPaused,
            initialHoldingsRequests: 1,
            reachesFetch: true
        ),
        SetupRetryScenario(
            name: "keychain-missing-entitlement",
            script: ScriptedPDTConnection(connection: .personalToken, keychainStatus: errSecMissingEntitlement),
            state: .keychainUnavailable(.missingEntitlement),
            initialHoldingsRequests: 0,
            reachesFetch: false
        ),
    ]

    var results: [ScriptedSetupRetryScenarioProof] = []
    for scenario in scenarios {
        let launch = try launchScriptedPDTApp(app, script: scenario.script, options: options, prefix: "\(name)-\(scenario.name)")
        defer { terminate(launch.process) }
        _ = launch.waitForEventCount("check", atLeast: 1, timeout: options.timeout + 3.0)
        if scenario.initialHoldingsRequests > 0 {
            _ = launch.waitForEventCount("request /v1/portfolio/holdings", atLeast: scenario.initialHoldingsRequests, timeout: options.timeout + 3.0)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let initialChecks = launch.eventCount("check")
        let initialHoldingsRequests = launch.eventCount("request /v1/portfolio/holdings")
        let descriptor = PDTLaunchMenu.descriptor(for: scenario.state)
        var initialMenu: MenuCheck?
        var clicks: [String?] = []
        if accessibilityChecked {
            initialMenu = try checkMenu(
                "\(name)-\(scenario.name)",
                descriptor: descriptor,
                texts: [PDTLaunchMenu.descriptor(for: scenario.state).statusTitle, "Check again"],
                process: launch.process,
                timeout: options.timeout,
                artifacts: artifacts
            )
            // A second click lands while the check or fetch runs, when the row is gone or refused.
            clicks.append(clickMenuRow("pdtConnection.check", descriptor: descriptor, process: launch.process, timeout: options.timeout))
            clicks.append(clickMenuRow("pdtConnection.check", descriptor: descriptor, process: launch.process, timeout: 0.5))
            _ = launch.waitForEventCount("check", atLeast: 2, timeout: options.timeout + 3.0)
            if scenario.reachesFetch {
                _ = waitForFile(launch.snapshot, timeout: options.timeout + 3.0)
                _ = launch.waitForEventCount("request /v1/portfolio/holdings", atLeast: scenario.initialHoldingsRequests + 2, timeout: options.timeout)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        let finalChecks = launch.eventCount("check")
        let finalHoldingsRequests = launch.eventCount("request /v1/portfolio/holdings")
        let scenarioIsolation = isolation(launch)
        let initialStateProved = initialChecks == 1 && initialHoldingsRequests == scenario.initialHoldingsRequests
        let retryProved = !accessibilityChecked || (
            initialMenu?.visible == true
                && clicks.first.flatMap { $0 } != nil
                && finalChecks == 2
                // A fetch after Check again is the first fetch plus the background detail refresh it starts,
                // each reading holdings once; a duplicate fetch would add another.
                && finalHoldingsRequests == scenario.initialHoldingsRequests + (scenario.reachesFetch ? 2 : 0)
                && launch.snapshotWritten == scenario.reachesFetch
        )
        results.append(ScriptedSetupRetryScenarioProof(
            name: scenario.name,
            isolation: scenarioIsolation,
            initialChecks: initialChecks,
            initialHoldingsRequests: initialHoldingsRequests,
            initialMenu: initialMenu,
            checkAgainClicks: clicks,
            finalChecks: finalChecks,
            finalHoldingsRequests: finalHoldingsRequests,
            snapshotWritten: launch.snapshotWritten,
            passed: scenarioIsolation.clean && initialStateProved && retryProved
                && (accessibilityChecked || !launch.snapshotWritten)
        ))
        terminate(launch.process)
    }

    try stableJSONData(ScriptedSetupRetryProof(
        accessibilityChecked: accessibilityChecked,
        scenarios: results,
        rawPortfolioPayloadsRedacted: true
    )).write(to: proof, options: .atomic)
    let artifactsList = [artifactPath(proof)] + results.compactMap { $0.initialMenu?.evidencePath }

    guard results.allSatisfy(\.passed) else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "scripted setup retry did not prove reconnect, paused, and Keychain states with one check per Check again and no duplicate fetch",
            artifacts: artifactsList
        )
    }
    guard accessibilityChecked else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "reconnect, paused, and Keychain launches each ran one check and stopped before a snapshot; macOS Accessibility permission missing for Check again click proof",
            artifacts: artifactsList
        )
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "reconnect, paused, and Keychain rows rendered; Check again reran one check per click, paused reached the fetch, and a duplicate click started no second fetch",
        artifacts: artifactsList
    )
}

// MARK: scripted-sign-in

private struct ScriptedSignInProof: Codable {
    var success: ScriptedLaunchIsolation
    var successIdleBeforeClick: Bool
    var successSetupMenu: MenuCheck?
    var successClick: String?
    var successSignInStarted: Bool
    var successSigningInVisible: Bool
    var successSnapshotWritten: Bool
    var successSnapshotAsOf: String?
    var denied: ScriptedLaunchIsolation
    var deniedClick: String?
    var deniedMenu: MenuCheck?
    var deniedHoldingsRequests: Int
    var deniedSnapshotWritten: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private func scriptedSignInSmoke(arguments: [String]) throws -> SmokeReport {
    let name = "scripted-sign-in"
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return missingAppReport(name)
    }
    let artifacts = try smokeArtifacts(options)
    let proof = artifacts.appending(path: "pdtbar-scripted-sign-in-proof.json")
    let api = ScriptedPDTAPIConfiguration(responses: [try scriptedHoldingsResponse()], asOf: scriptedPDTAsOf)
    let notConnected = PDTLaunchMenu.descriptor(for: .notConnected)

    let success = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .notConnected, signIn: .succeeds, signInDelaySeconds: max(options.timeout, 1.5), api: api),
        options: options,
        prefix: "\(name)-success"
    )
    defer { terminate(success.process) }
    _ = success.waitForEventCount("check", atLeast: 1, timeout: options.timeout + 3.0)
    Thread.sleep(forTimeInterval: 0.5)
    let successIdle = success.eventCount("sign-in") == 0 && success.eventCount("request /v1/portfolio/holdings") == 0
        && !success.snapshotWritten

    guard AXIsProcessTrusted() else {
        let successIsolation = isolation(success)
        terminate(success.process)
        try stableJSONData(ScriptedSignInProof(
            success: successIsolation,
            successIdleBeforeClick: successIdle,
            successSetupMenu: nil,
            successClick: nil,
            successSignInStarted: false,
            successSigningInVisible: false,
            successSnapshotWritten: false,
            successSnapshotAsOf: nil,
            denied: successIsolation,
            deniedClick: nil,
            deniedMenu: nil,
            deniedHoldingsRequests: 0,
            deniedSnapshotWritten: false,
            rawPortfolioPayloadsRedacted: true
        )).write(to: proof, options: .atomic)
        guard successIdle, successIsolation.clean else {
            return SmokeReport(name: name, status: SmokeStatus.failed, detail: "not-connected launch did not stay idle before a sign-in click", artifacts: [artifactPath(proof)])
        }
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "not-connected launch stayed idle with no sign-in, request, CLI, or fixture state; macOS Accessibility permission missing for Sign in with PDT click proof",
            artifacts: [artifactPath(proof)]
        )
    }

    let setupMenu = try checkMenu(
        "\(name)-not-connected",
        descriptor: notConnected,
        texts: ["Not connected", "Sign in with PDT", "Use a PDT token"],
        process: success.process,
        timeout: options.timeout,
        artifacts: artifacts
    )
    let successClick = clickMenuRow("pdtConnection.signIn", descriptor: notConnected, process: success.process, timeout: options.timeout)
    let signInStarted = success.waitForEventCount("sign-in", atLeast: 1, timeout: options.timeout)
    let appElement = AXUIElementCreateApplication(success.process.processIdentifier)
    let signingInVisible = waitForStatusText("Signing in with PDT", in: appElement, statusIdentifier: "pdtbar.status", timeout: options.timeout)
    let successSnapshotWritten = waitForSnapshotAsOf(success.snapshot, asOf: scriptedPDTAsOf, timeout: options.timeout + 6.0)
    let successIsolation = isolation(success)
    terminate(success.process)

    let denied = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .notConnected, signIn: .denied, api: api),
        options: options,
        prefix: "\(name)-denied"
    )
    defer { terminate(denied.process) }
    _ = denied.waitForEventCount("check", atLeast: 1, timeout: options.timeout + 3.0)
    let deniedClick = clickMenuRow("pdtConnection.signIn", descriptor: notConnected, process: denied.process, timeout: options.timeout)
    _ = denied.waitForEventCount("sign-in", atLeast: 1, timeout: options.timeout)
    let deniedMenu = try checkMenu(
        "\(name)-denied",
        descriptor: PDTLaunchMenu.descriptor(for: .notConnected, notice: .signInFailed(.denied)),
        texts: ["Sign-in failed", "PDT sign-in was declined", "Sign in with PDT"],
        process: denied.process,
        timeout: options.timeout,
        artifacts: artifacts
    )
    let deniedIsolation = isolation(denied)

    let proofPayload = ScriptedSignInProof(
        success: successIsolation,
        successIdleBeforeClick: successIdle,
        successSetupMenu: setupMenu,
        successClick: successClick,
        successSignInStarted: signInStarted,
        successSigningInVisible: signingInVisible,
        successSnapshotWritten: successSnapshotWritten,
        successSnapshotAsOf: snapshotAsOf(success.snapshot),
        denied: deniedIsolation,
        deniedClick: deniedClick,
        deniedMenu: deniedMenu,
        deniedHoldingsRequests: denied.eventCount("request /v1/portfolio/holdings"),
        deniedSnapshotWritten: denied.snapshotWritten,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)
    let artifactsList = [artifactPath(proof)] + [setupMenu, deniedMenu].compactMap(\.evidencePath)

    guard successIdle,
          successIsolation.clean,
          setupMenu.visible,
          successClick != nil,
          signInStarted,
          signingInVisible,
          successSnapshotWritten,
          deniedIsolation.clean,
          deniedClick != nil,
          deniedMenu.visible,
          proofPayload.deniedHoldingsRequests == 0,
          !proofPayload.deniedSnapshotWritten
    else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "scripted sign-in did not prove click-only sign-in, the first fetch after success, and the declined notice without a fetch",
            artifacts: artifactsList
        )
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "Sign in with PDT started the scripted sign-in only after the click, showed Signing in with PDT, then fetched; a declined sign-in showed Sign-in failed and fetched nothing",
        artifacts: artifactsList
    )
}

// MARK: logged-out-launch / ready-launch

private func loggedOutLaunchSmoke(arguments: [String]) throws -> SmokeReport {
    let name = "logged-out-launch"
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return missingAppReport(name)
    }
    let artifacts = try smokeArtifacts(options)
    let launch = try launchScriptedPDTApp(app, script: ScriptedPDTConnection(connection: .notConnected), options: options, prefix: name)
    defer { terminate(launch.process) }
    _ = launch.waitForEventCount("check", atLeast: 1, timeout: options.timeout + 3.0)
    Thread.sleep(forTimeInterval: options.timeout)
    let launchIsolation = isolation(launch)
    guard launchIsolation.clean,
          launch.eventCount("check") == 1,
          launch.eventCount("request /v1/portfolio/holdings") == 0,
          !launch.snapshotWritten
    else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "not-connected launch exited, spawned a CLI, wrote fixture or snapshot state, or fetched without a connection",
            artifacts: [artifactPath(launch.appSupportDirectory)]
        )
    }
    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "not-connected launch stayed running, checked once, fetched nothing, and ignored fixture env; macOS Accessibility permission missing for setup menu inspection",
            artifacts: [artifactPath(launch.appSupportDirectory)]
        )
    }
    let menu = try checkMenu(
        name,
        descriptor: PDTLaunchMenu.descriptor(for: .notConnected),
        texts: ["Not connected", "Sign in with PDT", "Use a PDT token", "Quit PDTBar"],
        process: launch.process,
        timeout: options.timeout,
        artifacts: artifacts
    )
    let artifactsList = [menu.evidencePath].compactMap { $0 }
    guard menu.visible else {
        return SmokeReport(name: name, status: SmokeStatus.failed, detail: "could not verify the not-connected setup menu after \(menu.openAttempt ?? "no attempt")", artifacts: artifactsList)
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "not-connected launch rendered Not connected, Sign in with PDT, Use a PDT token, and Quit PDTBar without a CLI or fixture state",
        artifacts: artifactsList
    )
}

private func readyLaunchSmoke(arguments: [String]) throws -> SmokeReport {
    let name = "ready-launch"
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return missingAppReport(name)
    }
    let artifacts = try smokeArtifacts(options)
    let api = ScriptedPDTAPIConfiguration(responses: [try scriptedHoldingsResponse()], asOf: scriptedPDTAsOf)
    let expectedPulse = try expectedFirstFetchPulse(api)
    let launch = try launchScriptedPDTApp(app, script: ScriptedPDTConnection(connection: .browserSession, api: api), options: options, prefix: name)
    defer { terminate(launch.process) }
    let snapshotWritten = waitForFile(launch.snapshot, timeout: options.timeout + 3.0)
    let launchIsolation = isolation(launch)
    guard launchIsolation.clean, snapshotWritten else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "connected launch did not stay running, finish the first fetch, or avoid CLI and fixture state",
            artifacts: [artifactPath(launch.appSupportDirectory)]
        )
    }
    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "connected launch completed the first fetch without a CLI or fixture state; macOS Accessibility permission missing for pulse menu inspection",
            artifacts: [artifactPath(launch.snapshot)]
        )
    }
    let menu = try checkMenu(
        name,
        descriptor: expectedPulse.descriptor,
        pulse: true,
        forbiddenTexts: ["Not connected", "Sign in with PDT"],
        process: launch.process,
        timeout: options.timeout,
        artifacts: artifacts
    )
    let artifactsList = [menu.evidencePath, artifactPath(launch.snapshot)].compactMap { $0 }
    guard menu.visible else {
        return SmokeReport(name: name, status: SmokeStatus.failed, detail: "connected launch did not publish the first pulse cleanly after \(menu.openAttempt ?? "no attempt")", artifacts: artifactsList)
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "connected launch skipped setup, completed the first fetch, and rendered the pulse without a CLI or fixture state",
        artifacts: artifactsList
    )
}

// MARK: packaged-onboarding

private struct PackagedOnboardingProof: Codable {
    var appBundlePath: String
    var appExecutablePath: String
    var launch: ScriptedLaunchIsolation
    var accessibilityChecked: Bool
    var idleBeforeClick: Bool
    var setupMenu: MenuCheck?
    var signInClick: String?
    var signInStarted: Bool
    var signingInVisible: Bool
    var firstFetchSnapshotWritten: Bool
    var screenshotPaths: [String]
    var rawPortfolioPayloadsRedacted: Bool
}

private func packagedOnboardingSmoke(arguments: [String]) throws -> SmokeReport {
    let name = "packaged-onboarding"
    let options = try SmokeOptions(arguments: arguments)
    let appBundle = options.app ?? packageRoot.appending(path: "PDTBar.app")
    guard appBundle.pathExtension == "app",
          let app = appBundleExecutable(in: appBundle),
          FileManager.default.isExecutableFile(atPath: app.path)
    else {
        return SmokeReport(
            name: name,
            status: SmokeStatus.failed,
            detail: "packaged PDTBar.app missing; run ./Scripts/package_app.sh or pass --app <path-to-PDTBar.app>",
            artifacts: []
        )
    }
    let artifacts = try smokeArtifacts(options)
    let proof = artifacts.appending(path: "pdtbar-packaged-onboarding-proof.json")
    let api = ScriptedPDTAPIConfiguration(responses: [try scriptedHoldingsResponse()], asOf: scriptedPDTAsOf)
    let launch = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .notConnected, signIn: .succeeds, signInDelaySeconds: max(options.timeout, 1.5), api: api),
        options: options,
        prefix: name
    )
    defer { terminate(launch.process) }
    _ = launch.waitForEventCount("check", atLeast: 1, timeout: options.timeout + 3.0)
    Thread.sleep(forTimeInterval: 0.5)
    var proofPayload = PackagedOnboardingProof(
        appBundlePath: artifactPath(appBundle),
        appExecutablePath: artifactPath(app),
        launch: isolation(launch),
        accessibilityChecked: AXIsProcessTrusted(),
        idleBeforeClick: launch.eventCount("sign-in") == 0 && !launch.snapshotWritten,
        setupMenu: nil,
        signInClick: nil,
        signInStarted: false,
        signingInVisible: false,
        firstFetchSnapshotWritten: false,
        screenshotPaths: [],
        rawPortfolioPayloadsRedacted: true
    )
    guard proofPayload.launch.clean, proofPayload.idleBeforeClick else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(name: name, status: SmokeStatus.failed, detail: "packaged app exited, spawned a CLI, wrote fixture state, or signed in before a click", artifacts: [artifactPath(proof)])
    }
    guard proofPayload.accessibilityChecked else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: name,
            status: SmokeStatus.skipped,
            detail: "packaged PDTBar.app launched with the scripted PDT connection, stayed idle, and ignored fixture env; macOS Accessibility permission missing for Sign in with PDT click proof",
            artifacts: [artifactPath(proof)]
        )
    }

    let notConnected = PDTLaunchMenu.descriptor(for: .notConnected)
    proofPayload.setupMenu = try checkMenu(
        name,
        descriptor: notConnected,
        texts: ["Not connected", "Sign in with PDT"],
        process: launch.process,
        timeout: options.timeout,
        artifacts: artifacts
    )
    proofPayload.signInClick = clickMenuRow("pdtConnection.signIn", descriptor: notConnected, process: launch.process, timeout: options.timeout)
    proofPayload.signInStarted = launch.waitForEventCount("sign-in", atLeast: 1, timeout: options.timeout)
    let appElement = AXUIElementCreateApplication(launch.process.processIdentifier)
    proofPayload.signingInVisible = waitForStatusText("Signing in with PDT", in: appElement, statusIdentifier: "pdtbar.status", timeout: options.timeout)
    if let screenshot = captureFullScreenScreenshot(
        name: "pdtbar-packaged-onboarding-signing-in",
        artifacts: artifacts,
        peekaboo: options.peekaboo.flatMap(peekabooScreenshotTool)
    ) {
        proofPayload.screenshotPaths.append(artifactPath(screenshot))
    }
    proofPayload.firstFetchSnapshotWritten = waitForSnapshotAsOf(launch.snapshot, asOf: scriptedPDTAsOf, timeout: options.timeout + 6.0)
    proofPayload.launch = isolation(launch)
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard proofPayload.launch.clean,
          proofPayload.setupMenu?.visible == true,
          proofPayload.signInClick != nil,
          proofPayload.signInStarted,
          proofPayload.signingInVisible,
          proofPayload.firstFetchSnapshotWritten
    else {
        return SmokeReport(name: name, status: SmokeStatus.failed, detail: "packaged onboarding did not prove the Sign in with PDT click, scripted sign-in, and first fetch", artifacts: [artifactPath(proof)])
    }
    return SmokeReport(
        name: name,
        status: SmokeStatus.passed,
        detail: "packaged PDTBar.app with the scripted PDT connection ignored fixture env, clicked Sign in with PDT through Accessibility, and completed the first fetch",
        artifacts: [artifactPath(proof)]
    )
}

private func appBundlePackagingSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let appBundle = packageRoot.appending(path: "PDTBar.app")
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-app-bundle-packaging-proof.json")
    let packageScript = packageRoot.appending(path: "Scripts/package_app.sh")
    let packageCommand = [artifactPath(packageScript), "debug"]

    var proofPayload = AppBundlePackagingProof(
        appBundlePath: artifactPath(appBundle),
        appExecutablePath: "",
        packageCommand: packageCommand,
        bundleIdentifier: nil,
        bundleExecutable: nil,
        packageType: nil,
        menuBarAccessory: false,
        codesignVerified: false,
        codesignSignature: nil,
        launchedViaLaunchServices: false,
        launchedProcessIdentifier: nil,
        launchedBundleIdentifier: nil,
        launchedExecutablePath: nil,
        bundleProcessMatched: false,
        appSupportPath: "",
        accessibilityChecked: AXIsProcessTrusted(),
        statusIdentifier: "pdtbar.status",
        expectedMenuIdentifiers: [],
        observedStatusText: [],
        observedMenuIdentifiers: [],
        menuBarSurfaceVisible: false,
        fixtureModeUsed: false,
        rawClaudeCredentialsUsed: false,
        rawPortfolioPayloadsRedacted: true
    )

    guard options.app == nil else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "app-bundle-packaging always builds and verifies the root PDTBar.app; do not pass --app",
            artifacts: [artifactPath(proof)]
        )
    }
    guard FileManager.default.isExecutableFile(atPath: packageScript.path) else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "package script missing at \(artifactPath(packageScript))",
            artifacts: [artifactPath(proof)]
        )
    }

    _ = try run(packageScript, arguments: ["debug"], timeout: max(options.timeout * 20.0, 30.0))

    let info = try bundleInfoPlist(appBundle)
    proofPayload.bundleIdentifier = info["CFBundleIdentifier"] as? String
    proofPayload.bundleExecutable = info["CFBundleExecutable"] as? String
    proofPayload.packageType = info["CFBundlePackageType"] as? String
    proofPayload.menuBarAccessory = info["LSUIElement"] as? Bool == true

    guard let executable = appBundleExecutable(in: appBundle),
          FileManager.default.isExecutableFile(atPath: executable.path)
    else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "packaged app executable missing after package script",
            artifacts: [artifactPath(proof)]
        )
    }
    proofPayload.appExecutablePath = artifactPath(executable)

    guard proofPayload.bundleIdentifier?.isEmpty == false,
          proofPayload.bundleExecutable == executable.lastPathComponent,
          proofPayload.packageType == "APPL",
          proofPayload.menuBarAccessory
    else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "Info.plist does not include expected bundle identifier, executable, APPL package type, and LSUIElement menu-bar accessory metadata",
            artifacts: [artifactPath(proof)]
        )
    }

    let signature = try verifyCodeSignature(appBundle, timeout: max(options.timeout * 5.0, 10.0))
    proofPayload.codesignVerified = true
    proofPayload.codesignSignature = signature

    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "app-bundle-packaging-app-support")
    proofPayload.appSupportPath = artifactPath(appSupportDirectory)
    let scripted = try writeScriptedPDT(ScriptedPDTConnection(connection: .notConnected), appSupportDirectory: appSupportDirectory)

    let runningApp = try launchAppBundleWithLaunchServices(
        appBundle,
        arguments: ["--app-support-dir", appSupportDirectory.path, "--scripted-pdt", scripted.script.path],
        environment: [:],
        timeout: max(options.timeout, 2.0)
    )
    proofPayload.launchedViaLaunchServices = true
    proofPayload.launchedProcessIdentifier = runningApp.processIdentifier
    proofPayload.launchedBundleIdentifier = runningApp.bundleIdentifier
    proofPayload.launchedExecutablePath = runningApp.executableURL.map(artifactPath)
    proofPayload.bundleProcessMatched = runningApp.executableURL?.standardizedFileURL == executable.standardizedFileURL
    defer {
        runningApp.terminate()
    }

    guard proofPayload.bundleProcessMatched else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "LaunchServices did not start the packaged PDTBar.app executable",
            artifacts: [artifactPath(proof)]
        )
    }

    let loginSurface = MenuBarSurfaceRenderer.render(descriptor: PDTLaunchMenu.descriptor(for: .notConnected))
    let expectedTargets = requiredSetupMenuTargets(in: loginSurface)
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    proofPayload.statusIdentifier = loginSurface.status.accessibilityIdentifier
    proofPayload.expectedMenuIdentifiers = expectedMenuIdentifiers.sorted()

    guard proofPayload.accessibilityChecked else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.skipped,
            detail: "PDTBar.app was built, signed, and launched through LaunchServices; macOS Accessibility permission missing for menu-bar surface inspection",
            artifacts: [artifactPath(proof)]
        )
    }

    let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: loginSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "packaged app launched, but Accessibility could not find status item \(loginSurface.status.accessibilityIdentifier)",
            artifacts: [artifactPath(proof)]
        )
    }

    let openedMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: options.timeout
    )
    let menuSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
        expectedMenuIdentifiers,
        in: appElement,
        timeout: options.timeout
    )
    proofPayload.observedStatusText = accessibilityTexts(in: statusElement).sorted()
    proofPayload.observedMenuIdentifiers = menuSnapshot.identifiers.sorted()
    proofPayload.menuBarSurfaceVisible = expectedMenuIdentifiers.isSubset(of: menuSnapshot.identifiers)
        && menuSnapshot.texts.contains("Sign in with PDT")
        && menuSnapshot.texts.contains { $0.contains("Not connected") }
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard proofPayload.menuBarSurfaceVisible else {
        return SmokeReport(
            name: "app-bundle-packaging",
            status: SmokeStatus.failed,
            detail: "packaged app launched through LaunchServices, but setup menu-bar surface was not visible after \(openedMenu.attempts.joined(separator: ", "))",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "app-bundle-packaging",
        status: SmokeStatus.passed,
        detail: "PDTBar.app was packaged, signed, launched through LaunchServices, matched the bundle executable, and exposed the setup menu-bar surface",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedPDTConnectorSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-pdt-connector-proof.json")
    let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-pdt-connector")
    defer {
        try? FileManager.default.removeItem(at: snapshotStore.directory)
    }

    let responses = try scriptedPDTConnectorResponses()
    let connector = ScriptedPDTMCPConnector(responses: responses)
    let coalescedFetch = PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: connector),
        snapshotStore: snapshotStore,
        asOf: "2026-03-29"
    )
    let firstRun = try coalescedFetch.fetch()
    let secondRun = try coalescedFetch.fetch()
    let callCounts = Dictionary(grouping: connector.calls, by: { $0 }).mapValues(\.count)
    let calledOnlyAllowedTools = Set(connector.calls).isSubset(of: Set(PDTReadTools.allowedV1))
    let requiredToolsCalledOnce = PDTReadTools.requiredV1.allSatisfy { callCounts[$0] == 1 }
    let scenarioResults = try scriptedPDTConnectorScenarioResults(responses: responses)
    let proofPayload = ScriptedPDTConnectorProof(
        requiredReadTools: PDTReadTools.requiredV1,
        availabilityChecks: connector.availabilityChecks,
        callCounts: PDTReadTools.requiredV1.reduce(into: [String: Int]()) { counts, tool in
            counts[tool] = callCounts[tool] ?? 0
        },
        calledOnlyAllowedReadTools: calledOnlyAllowedTools,
        optionalSymbolLookupCalls: callCounts["pdt-get-symbol"] ?? 0,
        coalescedSecondFetchReusedFirstResult: firstRun == secondRun,
        snapshotWritten: firstRun.snapshotCommit.written,
        openHoldingCount: firstRun.model.facetSnapshots.allocation.openHoldingCount,
        renderedSectionIDs: firstRun.descriptor.sections.map(\.id),
        scenarios: scenarioResults,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard connector.availabilityChecks == 1,
          calledOnlyAllowedTools,
          requiredToolsCalledOnce,
          callCounts["pdt-get-symbol"] == 1,
          firstRun == secondRun,
          firstRun.snapshotCommit.written,
          firstRun.model.facetSnapshots.allocation.openHoldingCount > 0,
          scenarioResults.allSatisfy(\.passed)
    else {
        return SmokeReport(
            name: "scripted-pdt-connector",
            status: SmokeStatus.failed,
            detail: "scripted PDT connector did not prove required read-tool availability, allowed coalesced call counts, optional symbol lookup, progressive detail refresh, or all scripted response states",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "scripted-pdt-connector",
        status: SmokeStatus.passed,
        detail: "scripted Claude PDT connector checked required v1 read tools, called each required tool exactly once plus optional symbol lookup for a coalesced fetch, rendered through PressureRunner, and proved progressive degraded detail refresh with redacted proof",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedAPIClientSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-api-client-proof.json")
    let secret = "pdt_scripted_smoke_secret"
    let page = { (rows: String, current: Int, last: Int) in
        ScriptedPDTHTTPTransport.Reply.response(
            status: 200,
            body: Data(#"{"data":[\#(rows)],"meta":{"currentPage":\#(current),"lastPage":\#(last),"perPage":100,"total":3}}"#.utf8)
        )
    }
    let transport = ScriptedPDTHTTPTransport([
        .response(status: 200, body: Data(#"{"data":[{"id":1},{"id":2}]}"#.utf8)),
        .response(status: 429, body: Data(#"{"error":{"code":"RATE_LIMITED","message":"m","details":{},"traceId":"t"}}"#.utf8), headers: ["Retry-After": "0"]),
        page(#"{"id":1},{"id":2}"#, 1, 2),
        page(#"{"id":3}"#, 2, 2),
        .response(status: 200, body: Data(#"{"data":{"items":[{"id":1}],"hasMore":false,"totalCount":1},"meta":[]}"#.utf8)),
        .response(status: 401, body: Data(#"{"error":{"code":"TOKEN_INVALID","message":"m","details":{"reason":"expired"},"traceId":"t"}}"#.utf8)),
    ])
    let client = PDTAPIClient(
        transport: transport,
        tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(secret)),
        sleeper: ThreadPDTAPISleeper()
    )
    let holdings: [ScriptedAPIRow] = try client.getAll(.holdings())
    let dividends: [ScriptedAPIRow] = try client.getAll(.dividends())
    let xRay: [ScriptedAPIRow] = try client.getAll(.xRay)
    var expiredTokenClassified = false
    do {
        _ = try client.get(.me)
    } catch PDTAPIError.tokenInvalid(reason: "expired") {
        expiredTokenClassified = true
    }

    let requests = transport.requests
    let proofPayload = ScriptedAPIClientProof(
        requestCount: requests.count,
        paths: requests.compactMap { $0.url?.path },
        onlyGET: requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil },
        onlyPDTOrigin: requests.allSatisfy { $0.url?.scheme == "https" && $0.url?.host == "api.portfoliodividendtracker.com" },
        holdingRows: holdings.count,
        paginatedDividendRows: dividends.count,
        xRayRows: xRay.count,
        rateLimitRetried: requests.filter { $0.url?.path == "/v1/dividends" }.count == 3,
        expiredTokenClassified: expiredTokenClassified
    )
    let proofData = try stableJSONData(proofPayload)
    try proofData.write(to: proof, options: .atomic)

    guard proofPayload.onlyGET,
          proofPayload.onlyPDTOrigin,
          holdings.count == 2,
          dividends.count == 3,
          xRay.count == 1,
          proofPayload.rateLimitRetried,
          expiredTokenClassified,
          !String(decoding: proofData, as: UTF8.self).contains(secret)
    else {
        return SmokeReport(
            name: "scripted-api-client",
            status: SmokeStatus.failed,
            detail: "scripted PDT API client did not prove GET-only same-origin requests, pagination, rate-limit retry, typed token errors, or token redaction",
            artifacts: [artifactPath(proof)]
        )
    }
    return SmokeReport(
        name: "scripted-api-client",
        status: SmokeStatus.passed,
        detail: "scripted PDT API client sent only GET requests to the PDT API origin, completed page and offset pagination, retried a 429, classified an expired token, and kept the token out of proof",
        artifacts: [artifactPath(proof)]
    )
}

private struct ScriptedAPIRow: Decodable {
    var id: Int
}

private struct ScriptedAPIClientProof: Codable {
    var requestCount: Int
    var paths: [String]
    var onlyGET: Bool
    var onlyPDTOrigin: Bool
    var holdingRows: Int
    var paginatedDividendRows: Int
    var xRayRows: Int
    var rateLimitRetried: Bool
    var expiredTokenClassified: Bool
}

private func scriptedAPIAuthSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-api-auth-proof.json")
    let secrets = ["scripted-code", "scripted-access-1", "scripted-refresh-1", "scripted-access-2", "scripted-refresh-2", "pdt_scripted_personal"]
    let tokenReply = { (access: String, refresh: String) in
        ScriptedPDTHTTPTransport.Reply.response(
            status: 200,
            body: Data(#"{"access_token":"\#(access)","expires_in":3600,"refresh_token":"\#(refresh)","token_type":"Bearer"}"#.utf8)
        )
    }
    let ok = ScriptedPDTHTTPTransport.Reply.response(status: 200, body: Data(#"{"data":{}}"#.utf8))
    let tokens = ScriptedPDTHTTPTransport([
        tokenReply(secrets[1], secrets[2]),
        tokenReply(secrets[3], secrets[4]),
        .response(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)),
    ])
    let api = ScriptedPDTHTTPTransport(Array(repeating: ok, count: 7))
    let clock = SmokeClock()
    let tokenEndpoint = PDTTokenEndpoint(
        client: PDTOAuthClient(id: "scripted-client", redirectPort: 0),
        transport: tokens,
        now: { clock.now }
    )
    let connection = PDTConnection(store: InMemoryPDTCredentialStore(), tokenEndpoint: tokenEndpoint, now: { clock.now })
    let client = PDTAPIClient(transport: api, tokenProvider: connection)

    let session = try PDTBrowserSignIn(tokenEndpoint: tokenEndpoint, timeout: 10) { authorize in
        let query = Dictionary(
            (URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        var callback = URLComponents(string: query["redirect_uri"] ?? "")!
        callback.queryItems = [URLQueryItem(name: "code", value: secrets[0]), URLQueryItem(name: "state", value: query["state"])]
        URLSession(configuration: .ephemeral).dataTask(with: callback.url!).resume()
    }.run()
    try connection.signedIn(session)

    clock.advance(by: 3600)
    let concurrentFailures = SmokeCounter()
    DispatchQueue.concurrentPerform(iterations: 6) { _ in
        do {
            _ = try client.get(.me)
        } catch {
            concurrentFailures.increment()
        }
    }
    let refreshesForConcurrentReads = tokens.requests.count - 1

    clock.advance(by: 3600)
    var reconnectSurfaced = false
    do {
        _ = try client.get(.me)
    } catch PDTAPIError.tokenInvalid {
        reconnectSurfaced = true
    }
    let needsReconnect = try connection.state() == .needsReconnect(.browserSession, .refreshRejected(PDTRefreshToken(secrets[4]).fingerprint))

    try connection.connect(personalToken: PDTAPIToken.personal(pasted: secrets[5]))
    _ = try client.get(.me)
    let revokeAt = try connection.disconnect()
    let disconnected = try connection.state() == .disconnected

    let tokenRequests = tokens.requests
    let apiRequests = api.requests
    let proofPayload = ScriptedAPIAuthProof(
        tokenRequestCount: tokenRequests.count,
        apiRequestCount: apiRequests.count,
        tokenRequestsOnlyPOSTToTokenEndpoint: tokenRequests.allSatisfy {
            $0.httpMethod == "POST" && $0.url?.absoluteString == "https://auth.portfoliodividendtracker.com/oauth/token"
        },
        apiRequestsOnlyGET: apiRequests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil },
        concurrentReadFailures: concurrentFailures.value,
        refreshesForConcurrentReads: refreshesForConcurrentReads,
        concurrentReadsUsedRotatedToken: apiRequests.prefix(6).allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(secrets[3])"
        },
        invalidGrantNeedsReconnect: reconnectSurfaced && needsReconnect,
        personalTokenSent: apiRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(secrets[5])",
        disconnected: disconnected,
        revokeAt: revokeAt.absoluteString
    )
    let proofData = try stableJSONData(proofPayload)
    try proofData.write(to: proof, options: .atomic)
    let proofText = String(decoding: proofData, as: UTF8.self)

    guard proofPayload.tokenRequestCount == 3,
          proofPayload.apiRequestCount == 7,
          proofPayload.tokenRequestsOnlyPOSTToTokenEndpoint,
          proofPayload.apiRequestsOnlyGET,
          proofPayload.concurrentReadFailures == 0,
          proofPayload.refreshesForConcurrentReads == 1,
          proofPayload.concurrentReadsUsedRotatedToken,
          proofPayload.invalidGrantNeedsReconnect,
          proofPayload.personalTokenSent,
          proofPayload.disconnected,
          secrets.allSatisfy({ !proofText.contains($0) })
    else {
        return SmokeReport(
            name: "scripted-api-auth",
            status: SmokeStatus.failed,
            detail: "scripted PDT sign-in did not prove loopback code exchange, single-flight refresh, reconnect on invalid_grant, the pasted-token path, disconnect, or secret-free proof",
            artifacts: [artifactPath(proof)]
        )
    }
    return SmokeReport(
        name: "scripted-api-auth",
        status: SmokeStatus.passed,
        detail: "scripted PDT sign-in exchanged a loopback callback code, shared one refresh across 6 concurrent reads, moved to reconnect on invalid_grant, read with a pasted token, disconnected, and kept every secret out of proof",
        artifacts: [artifactPath(proof)]
    )
}

private struct ScriptedAPIAuthProof: Codable {
    var tokenRequestCount: Int
    var apiRequestCount: Int
    var tokenRequestsOnlyPOSTToTokenEndpoint: Bool
    var apiRequestsOnlyGET: Bool
    var concurrentReadFailures: Int
    var refreshesForConcurrentReads: Int
    var concurrentReadsUsedRotatedToken: Bool
    var invalidGrantNeedsReconnect: Bool
    var personalTokenSent: Bool
    var disconnected: Bool
    var revokeAt: String
}

private final class SmokeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date()

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}

private final class SmokeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private func scriptedAPISnapshotSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-api-snapshot-proof.json")
    let secret = "pdt_scripted_smoke_secret"
    let fixtures = packageRoot.appending(path: "docs/pdt/fixtures/api/full")
    let replies = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { ScriptedPDTHTTPTransport.Reply.response(status: 200, body: try Data(contentsOf: $0)) }
    let transport = ScriptedPDTHTTPTransport(replies)
    let failures = SmokeSyncFailureRecorder()
    let dataSource = PDTAPIDataSource(
        client: PDTAPIClient(
            transport: transport,
            tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(secret))
        ),
        onOptionalFacetFailure: { failures.record($0) }
    )
    let snapshot = try dataSource.snapshot(asOf: "2026-06-22")

    let requests = transport.requests
    let failedSyncs = try scriptedAPIFailedSyncProofs()
    let proofPayload = ScriptedAPISnapshotProof(
        requestCount: requests.count,
        paths: requests.compactMap { $0.url?.path },
        onlyGET: requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil },
        onlyPDTOrigin: requests.allSatisfy { $0.url?.scheme == "https" && $0.url?.host == "api.portfoliodividendtracker.com" },
        openHoldings: snapshot.openHoldings.count,
        holdingsWithCopyableIdentifier: snapshot.openHoldings.filter { $0.copyableIdentifier != nil }.count,
        sectors: snapshot.sectors.count,
        assetTypes: snapshot.assetTypes.count,
        xRayHoldings: snapshot.xRayHoldings?.count,
        incomeEvents: snapshot.incomeEvents.count,
        dividendRows: snapshot.dividendRowCount,
        pricePoints: snapshot.priceSeries.count,
        degraded: snapshot.latestDetailFillOutcome == .degraded,
        failures: failures.failures,
        failedSyncs: failedSyncs
    )
    let proofData = try stableJSONData(proofPayload)
    try proofData.write(to: proof, options: .atomic)

    guard proofPayload.onlyGET,
          proofPayload.onlyPDTOrigin,
          requests.count == replies.count,
          proofPayload.openHoldings == 6,
          proofPayload.holdingsWithCopyableIdentifier == 4,
          proofPayload.sectors == 4,
          proofPayload.xRayHoldings == 3,
          proofPayload.incomeEvents == 3,
          proofPayload.dividendRows == 4,
          proofPayload.pricePoints == 4,
          !proofPayload.degraded,
          proofPayload.failures.isEmpty,
          !String(decoding: proofData, as: UTF8.self).contains(secret)
    else {
        return SmokeReport(
            name: "scripted-api-snapshot",
            status: SmokeStatus.failed,
            detail: "scripted PDT REST snapshot did not map every facet from GET-only same-origin fixture replies without degrading or leaking the token",
            artifacts: [artifactPath(proof)]
        )
    }
    let unproven = failedSyncs.filter { !$0.proven }.map(\.reply)
    guard unproven.isEmpty, !String(decoding: proofData, as: UTF8.self).contains("SENTINEL") else {
        return SmokeReport(
            name: "scripted-api-snapshot",
            status: SmokeStatus.failed,
            detail: "scripted PDT REST failures did not each store a typed failure, say what to do in Data health, keep the saved copy, and keep PDT's answer out of Data health and the copied diagnostics: \(unproven.joined(separator: ", "))",
            artifacts: [artifactPath(proof)]
        )
    }
    return SmokeReport(
        name: "scripted-api-snapshot",
        status: SmokeStatus.passed,
        detail: "scripted PDT REST snapshot replayed \(requests.count) GET-only fixture replies from the PDT API origin, mapped holdings, allocation, x-ray, income, dividends, identifiers, and prices without degrading, and kept the token out of proof; \(failedSyncs.count) failed syncs (401, 403 scope, 403 paused, 429, 503, undecodable) each stored a typed failure, named what to do in Data health over the saved copy, and kept the planted token, account id, URL, and body out of Data health and the copied diagnostics",
        artifacts: [artifactPath(proof)]
    )
}

/// One failed background refresh per PDT answer, each over a store that holds a
/// saved copy. Every answer carries a planted token, account id, URL, and body.
private func scriptedAPIFailedSyncProofs() throws -> [ScriptedAPIFailedSyncProof] {
    let token = "pdt_SENTINEL_TOKEN_0123456789abcdef0123456789abcdef"
    let planted = [token, "acct-SENTINEL-4242", "https://api.portfoliodividendtracker.com/v1/accounts/acct-SENTINEL-4242", "RAW_BODY_SENTINEL"]
    func answer(_ status: Int, _ code: String, retryAfter: String = "acct-SENTINEL-4242") -> ScriptedPDTHTTPTransport.Reply {
        .response(
            status: status,
            body: Data(#"{"error":{"code":"\#(code)","message":"\#(planted[3]) \#(planted[1]) \#(token)","details":{"reason":"\#(planted[1])"},"traceId":"\#(planted[2])"}}"#.utf8),
            headers: ["Retry-After": retryAfter, "X-Request-Id": token, "Authorization": "Bearer \(token)"]
        )
    }
    let cases: [(reply: String, answer: ScriptedPDTHTTPTransport.Reply, kind: PDTSyncFailure.Kind, action: String)] = [
        ("401 TOKEN_INVALID", answer(401, "TOKEN_INVALID"), .reconnect, "reconnect"),
        ("403 INSUFFICIENT_SCOPE", answer(403, "INSUFFICIENT_SCOPE"), .readAccessMissing, "reconnect"),
        ("403 API_ACCESS_PAUSED", answer(403, "API_ACCESS_PAUSED"), .accessPaused, "renew your subscription"),
        ("429 RATE_LIMITED", answer(429, "RATE_LIMITED", retryAfter: "120"), .rateLimited(retryAfterSeconds: 120), "try again in 2 min"),
        ("503 SERVER_ERROR", answer(503, "SERVER_ERROR"), .server(status: 503), "try again later"),
        ("200 undecodable", .response(status: 200, body: Data(#"{"data":"\#(planted[3]) \#(planted[1]) \#(token)"}"#.utf8)), .unreadableResponse, "update PDTBar"),
    ]
    let completeSync = try scriptedAPIBackgroundRefreshResponses()
    return try cases.map { reply, answer, kind, action in
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-api-failed-sync")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        func refresh(_ transport: ScriptedPDTHTTPTransport, asOf: String) -> PDTAPIBackgroundDetailRefresh {
            PDTAPIBackgroundDetailRefresh(
                client: PDTAPIClient(
                    transport: transport,
                    tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(token)),
                    policy: PDTAPIRequestPolicy(maxAttempts: 1)
                ),
                snapshotStore: store,
                asOf: asOf
            )
        }
        _ = try refresh(ScriptedPDTAPIConfiguration(responses: completeSync).transport(), asOf: "2026-06-21").refresh()
        let refreshFailed = (try? refresh(ScriptedPDTHTTPTransport([answer]), asOf: "2026-06-22").refresh()) == nil

        let failure = store.lastSyncFailure()
        let runtime = DataHealthRuntime(access: .connected, sync: .failed(failure))
        let savedCopy = try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-06-22")
        let health = savedCopy.map { DataHealth.snapshot($0.model.facetSnapshots.dataHealth, in: runtime) }
        let healthRow = savedCopy?.descriptor(in: runtime).sections
            .first { $0.id == "freshness" }?.rows
            .first { $0.id == "dataHealth" }
        let diagnostics = healthRow?.children.first { $0.id == "dataHealth.diagnostic" }
        let copyText = diagnostics?.children.first?.actionTarget?.copyText
        let written = [
            copyText ?? "",
            healthRow.map { menuText(in: $0) } ?? "",
            try health.map { String(decoding: try stableJSONData($0), as: UTF8.self) } ?? "",
            (try? String(contentsOf: store.directory.appending(path: "latest-sync-failure.json"), encoding: .utf8)) ?? "",
        ]
        let redacted = written.allSatisfy { text in
            !text.isEmpty && planted.allSatisfy { !text.contains($0) } && !text.contains("SENTINEL")
        }
        return ScriptedAPIFailedSyncProof(
            reply: reply,
            failure: failure,
            dataHealthDetail: diagnostics?.detail,
            copiedDiagnostics: copyText,
            savedCopyAsOf: health?.cache.lastSyncAsOf,
            proven: refreshFailed
                && failure?.kind == kind
                && failure?.endpoint == .holdings
                && diagnostics?.detail?.hasSuffix("; \(action)") == true
                && health?.source.pulse == .cachedSnapshot
                && health?.status == .degraded
                && health?.cache.lastSyncAsOf == "2026-06-21"
                && redacted
        )
    }
}

private func menuText(in row: MenuRow) -> String {
    ([row.title, row.detail ?? "", row.actionTarget?.copyText ?? ""] + row.children.map(menuText)).joined(separator: "\n")
}

/// Proof of one failed sync. Every field is a closed type, a literal, or text
/// built from them, so the proof file is safe to attach.
private struct ScriptedAPIFailedSyncProof: Codable {
    var reply: String
    var failure: PDTSyncFailure?
    var dataHealthDetail: String?
    var copiedDiagnostics: String?
    var savedCopyAsOf: String?
    var proven: Bool
}

private struct ScriptedAPISnapshotProof: Codable {
    var requestCount: Int
    var paths: [String]
    var onlyGET: Bool
    var onlyPDTOrigin: Bool
    var openHoldings: Int
    var holdingsWithCopyableIdentifier: Int
    var sectors: Int
    var assetTypes: Int
    var xRayHoldings: Int?
    var incomeEvents: Int
    var dividendRows: Int
    var pricePoints: Int
    var degraded: Bool
    var failures: [PDTSyncFailure]
    var failedSyncs: [ScriptedAPIFailedSyncProof]
}

private final class SmokeSyncFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [PDTSyncFailure] = []

    var failures: [PDTSyncFailure] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ failure: PDTSyncFailure) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(failure)
    }
}

private func copyHoldingIdentifierActionSmoke() -> SmokeReport {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("pdtbar.copy.identifier.smoke.\(UUID().uuidString)"))
    let dispatcher = MenuActionDispatcher(pasteboard: pasteboard)
    let actionTarget = MenuRowActionTarget(
        kind: .copyHoldingIdentifier,
        id: "allocation.9701.copyIdentifier",
        copyText: "PUBC"
    )
    let item = NSMenuItem(title: "Copy identifier - redacted", action: nil, keyEquivalent: "")
    item.representedObject = actionTarget

    dispatcher.copyMenuRowAction(item)

    guard pasteboard.string(forType: .string) == "PUBC" else {
        return SmokeReport(
            name: "copy-holding-identifier-action",
            status: SmokeStatus.failed,
            detail: "copy identifier action did not write expected sanitized identifier from action metadata",
            artifacts: []
        )
    }

    return SmokeReport(
        name: "copy-holding-identifier-action",
        status: SmokeStatus.passed,
        detail: "AppKit dispatcher copied sanitized holding identifier from explicit action metadata using an isolated pasteboard",
        artifacts: []
    )
}

private func scriptedPulseMarkReadSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-pulse-mark-read-proof.json")
    let stateDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-pulse-mark-read-state")
    let snapshotStore = SnapshotStore(directory: stateDirectory)
    let readStore = PulseReadStore(directory: stateDirectory)
    let pressureFixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
    let initialRun = try PressureRunner.run(
        dataSource: PDTFixtureDataSource(fixture: pressureFixture),
        snapshotStore: snapshotStore,
        pulseReadStore: readStore
    )
    let firstItem = try require(
        initialRun.model.rankedAttentionItems.first,
        "scripted mark-read smoke requires pressure fixture attention"
    )
    let markReadAction = try require(
        initialRun.descriptor.sections
            .flatMap(\.rows)
            .flatMap(\.children)
            .first { $0.role == .pulseMarkRead },
        "pressure descriptor should expose Mark as read action"
    )
    let clickedPayload = try require(markReadAction.actionPayload, "Mark as read action should carry attention ID")
    let clickedFingerprint = try require(
        initialRun.unfilteredModel.rankedAttentionItems.first { $0.id == clickedPayload }?.readFingerprint,
        "Mark as read action should resolve to an in-memory fingerprint"
    )
    try readStore.markRead(clickedFingerprint)
    let afterClickPulse = try require(
        try PressureRunner.cachedPulse(snapshotStore: snapshotStore, pulseReadStore: readStore),
        "cached pulse lifecycle should reload after scripted Mark as read click"
    )
    let reloadedReadStore = PulseReadStore(directory: stateDirectory)
    let relaunchPulse = try require(
        try PressureRunner.cachedPulse(snapshotStore: snapshotStore, pulseReadStore: reloadedReadStore),
        "cached pulse lifecycle should reload after read-state relaunch"
    )
    var changedSnapshot = try PDTFixtureDataSource.snapshot(from: pressureFixture)
    changedSnapshot.openHoldings[0].weight = 0.265
    let changedRun = try PressureRunner.run(
        dataSource: StaticPortfolioDataSource(snapshot: changedSnapshot),
        snapshotStore: snapshotStore,
        pulseReadStore: reloadedReadStore
    )
    let resurfacedItem = changedRun.model.rankedAttentionItems.first
    let payloadMatchesFirstItem = clickedPayload == firstItem.id
    let afterClickHidden = !afterClickPulse.model.rankedAttentionItems.contains {
        $0.readFingerprint == clickedFingerprint
    } && afterClickPulse.source == .cachedSnapshot
    let relaunchHidden = !relaunchPulse.model.rankedAttentionItems.contains {
        $0.readFingerprint == clickedFingerprint
    } && relaunchPulse.source == .cachedSnapshot
    let changedResurfaced = resurfacedItem?.holdingIdentity?.quoteId == firstItem.holdingIdentity?.quoteId
        && resurfacedItem?.readFingerprint != clickedFingerprint
    let proofPayload = ScriptedPulseMarkReadProof(
        stateDirectory: artifactPath(stateDirectory),
        actionTitle: markReadAction.title,
        actionPayloadMatchedFirstAttentionFingerprint: payloadMatchesFirstItem,
        afterClickHidden: afterClickHidden,
        persistedRelaunchHidden: relaunchHidden,
        changedDataResurfaced: changedResurfaced,
        caughtUpStatusTitle: afterClickPulse.descriptor.statusTitle,
        changedStatusBadge: changedRun.descriptor.statusBadge,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)
    guard payloadMatchesFirstItem, afterClickHidden, relaunchHidden, changedResurfaced else {
        return SmokeReport(
            name: "scripted-pulse-mark-read",
            status: SmokeStatus.failed,
            detail: "scripted Mark as read proof did not hide, persist, and resurface changed pulse data",
            artifacts: [artifactPath(proof)]
        )
    }
    return SmokeReport(
        name: "scripted-pulse-mark-read",
        status: SmokeStatus.passed,
        detail: "scripted Mark as read action persisted local read state, hid the same fingerprint across reload, and resurfaced changed fixture data",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedReturningLaunchSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-returning-launch-proof.json")
    let responses = try scriptedAPIBackgroundRefreshResponses()
    let staleSnapshot = try PDTFixtureDataSource(fixture: defaultFixture).snapshot(asOf: "2026-03-28")
    let cachedDescriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: staleSnapshot))
    let refreshDelay = max(options.timeout * 5, 10.0)
    let refreshConfiguration = ScriptedPDTAPIConfiguration(
        responses: responses,
        asOf: "2026-03-29",
        initialRequestDelaySeconds: refreshDelay
    )
    let expectedFreshStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-returning-launch-expected")
    defer {
        try? FileManager.default.removeItem(at: expectedFreshStore.directory)
    }
    _ = try expectedFreshStore.commitCurrentSnapshot(staleSnapshot)
    let expectedFreshRun = try PDTAPIBackgroundDetailRefresh(
        client: PDTAPIClient(
            transport: ScriptedPDTAPIConfiguration(responses: responses).transport(),
            tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("scripted"))
        ),
        snapshotStore: expectedFreshStore,
        asOf: refreshConfiguration.asOf
    ).refresh()

    let successLaunch = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .browserSession, api: refreshConfiguration),
        options: options,
        prefix: "scripted-returning-launch-success",
        seed: staleSnapshot
    )
    let successProcess = successLaunch.process
    let successSnapshot = successLaunch.snapshot
    defer {
        terminate(successProcess)
    }

    guard isolation(successLaunch).clean,
          snapshotAsOf(successSnapshot) == staleSnapshot.asOf
    else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "returning launch did not start with the seeded local snapshot preserved, or spawned a CLI or wrote fixture state",
            artifacts: [artifactPath(successSnapshot)]
        )
    }

    let accessibilityChecked = AXIsProcessTrusted()
    var stalePulseVisible = false
    var backgroundProgressVisible = false
    var backgroundProgressScreenshotPath: String?
    var backgroundProgressScreenshotBlocker: String?
    var freshPulseVisible = false
    var failurePulseVisible = false
    var failureRetryVisible = false
    var axArtifacts: [String] = []
    let screenshotTool = options.peekaboo.flatMap(peekabooScreenshotTool)
    if accessibilityChecked {
        let staleAXTimeout = min(refreshDelay - 1.0, max(options.timeout, 5.0))
        let refreshingSurface = MenuBarSurfaceRenderer.render(
            descriptor: PDTLaunchMenu.descriptorForBackgroundDetailProgress(
                cachedPulse: cachedDescriptor,
                progress: BackgroundDetailRefreshProgress(phase: .baseHoldings)
            )
        )
        let targets = requiredSetupMenuTargets(in: refreshingSurface)
        let appElement = AXUIElementCreateApplication(successProcess.processIdentifier)
        if let statusElement = waitForAccessibilityElement(
            in: appElement,
            identifier: refreshingSurface.status.accessibilityIdentifier,
            timeout: staleAXTimeout
        ) {
            let statusText = accessibilityTexts(in: statusElement)
            let openedMenu = openStatusMenu(
                statusElement,
                appElement: appElement,
                expectedMenuIdentifiers: Set(targets.map(\.accessibilityIdentifier)),
                timeout: staleAXTimeout
            )
            let snapshot = openedMenu.snapshot ?? accessibilitySnapshot(in: appElement)
            let evidence = artifacts.appending(path: "pdtbar-scripted-returning-launch-stale-ax.json")
            try writeAccessibilityEvidence(
                snapshot: snapshot,
                expected: targets,
                statusIdentifier: refreshingSurface.status.accessibilityIdentifier,
                statusText: statusText,
                output: evidence
            )
            axArtifacts.append(artifactPath(evidence))
            let staleMenuVisible = Set(targets.map(\.accessibilityIdentifier)).isSubset(of: snapshot.identifiers)
            let staleStatusVisible = statusText.contains(refreshingSurface.status.accessibilityLabel)
                || statusText.contains(refreshingSurface.status.title)
            backgroundProgressVisible = staleMenuVisible
                && snapshot.texts.contains { $0.hasPrefix("Filling details") }
                && snapshot.texts.contains("Step 1/6: Base holdings")
                && !snapshot.texts.contains("Details fill failed")
            stalePulseVisible = backgroundProgressVisible
                || staleMenuVisible
                || (staleStatusVisible && snapshotAsOf(successSnapshot) == staleSnapshot.asOf)
            if backgroundProgressVisible {
                let screenshot = (try? captureMenuScreenshot(
                    name: "pdtbar-scripted-returning-launch-progress",
                    snapshot: snapshot,
                    expectedMenuIdentifiers: Set(targets.map(\.accessibilityIdentifier)),
                    artifacts: artifacts,
                    peekaboo: screenshotTool
                )) ?? captureFullScreenScreenshot(
                    name: "pdtbar-scripted-returning-launch-progress-fullscreen",
                    artifacts: artifacts,
                    peekaboo: screenshotTool
                )
                if let screenshot {
                    backgroundProgressScreenshotPath = artifactPath(screenshot)
                    axArtifacts.append(artifactPath(screenshot))
                } else {
                    backgroundProgressScreenshotBlocker = screenshotTool == nil
                        ? "Peekaboo screenshot capture unavailable or missing required TCC permissions"
                        : "Peekaboo screenshot capture returned no visible image while Accessibility saw the progress menu"
                }
            }
        }
    }

    guard waitForSnapshotAsOf(successSnapshot, asOf: "2026-03-29", timeout: refreshDelay + options.timeout + 3.0),
          let refreshedSnapshotAsOf = snapshotAsOf(successSnapshot),
          refreshedSnapshotAsOf == "2026-03-29"
    else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "returning launch did not replace the local snapshot after complete scripted refresh",
            artifacts: [artifactPath(successSnapshot)] + axArtifacts
        )
    }

    if accessibilityChecked {
        let freshSurface = MenuBarSurfaceRenderer.render(descriptor: expectedFreshRun.descriptor)
        let targets = requiredPulseMenuTargets(in: freshSurface)
        let appElement = AXUIElementCreateApplication(successProcess.processIdentifier)
        if let statusElement = waitForAccessibilityElement(
            in: appElement,
            identifier: freshSurface.status.accessibilityIdentifier,
            timeout: options.timeout
        ) {
            let snapshot = waitForAccessibilityIdentifiers(
                Set(targets.map(\.accessibilityIdentifier)),
                in: appElement,
                timeout: options.timeout
            )
            let evidence = artifacts.appending(path: "pdtbar-scripted-returning-launch-fresh-ax.json")
            try writeAccessibilityEvidence(
                snapshot: snapshot,
                expected: targets,
                statusIdentifier: freshSurface.status.accessibilityIdentifier,
                statusText: accessibilityTexts(in: statusElement),
                output: evidence
            )
            axArtifacts.append(artifactPath(evidence))
            freshPulseVisible = Set(targets.map(\.accessibilityIdentifier)).isSubset(of: snapshot.identifiers)
        }
    }
    terminate(successProcess)

    let unavailable = ScriptedPDTAPIConfiguration.Response(
        status: 503,
        body: #"{"error":{"code":"SERVICE_UNAVAILABLE","message":"m","details":{},"traceId":"t"}}"#,
        headers: ["Retry-After": "0"]
    )
    let failureConfiguration = ScriptedPDTAPIConfiguration(
        responses: Array(repeating: unavailable, count: PDTAPIRequestPolicy().maxAttempts),
        asOf: "2026-03-29"
    )
    let failureLaunch = try launchScriptedPDTApp(
        app,
        script: ScriptedPDTConnection(connection: .browserSession, api: failureConfiguration),
        options: options,
        prefix: "scripted-returning-launch-failure",
        seed: staleSnapshot
    )
    let failureProcess = failureLaunch.process
    let failureSnapshot = failureLaunch.snapshot
    defer {
        terminate(failureProcess)
    }
    _ = waitForFileContent(failureLaunch.stderrLog, contains: "background refresh failed", timeout: options.timeout + 3.0)
    let failurePreservedSnapshot = isolation(failureLaunch).clean
        && failureLaunch.stderrContains("background refresh failed")
        && snapshotAsOf(failureSnapshot) == staleSnapshot.asOf

    if accessibilityChecked {
        let failureSurface = MenuBarSurfaceRenderer.render(
            descriptor: PDTLaunchMenu.descriptorForBackgroundRefreshFailure(cachedPulse: cachedDescriptor)
        )
        let targets = requiredSetupMenuTargets(in: failureSurface)
        let appElement = AXUIElementCreateApplication(failureProcess.processIdentifier)
        if let statusElement = waitForAccessibilityElement(
            in: appElement,
            identifier: failureSurface.status.accessibilityIdentifier,
            timeout: options.timeout
        ) {
            let openedMenu = openStatusMenu(
                statusElement,
                appElement: appElement,
                expectedMenuIdentifiers: Set(targets.map(\.accessibilityIdentifier)),
                timeout: options.timeout
            )
            if let snapshot = openedMenu.snapshot {
                let evidence = artifacts.appending(path: "pdtbar-scripted-returning-launch-failure-ax.json")
                try writeAccessibilityEvidence(
                    snapshot: snapshot,
                    expected: targets,
                    statusIdentifier: failureSurface.status.accessibilityIdentifier,
                    statusText: accessibilityTexts(in: statusElement),
                    output: evidence
                )
                axArtifacts.append(artifactPath(evidence))
                let identifiers = Set(targets.map(\.accessibilityIdentifier))
                failurePulseVisible = identifiers.isSubset(of: snapshot.identifiers)
                failureRetryVisible = snapshot.identifiers.contains("pdtbar.row.portfolioFetch.retry")
                    && snapshot.texts.contains("Fill details again")
                    && !snapshot.texts.contains("Sign in with PDT")
            }
        }
    }

    let proofPayload = ScriptedReturningLaunchProof(
        seededSnapshotPath: artifactPath(successSnapshot),
        staleSnapshotAsOf: staleSnapshot.asOf,
        refreshedSnapshotAsOf: snapshotAsOf(successSnapshot),
        failureSnapshotAsOf: snapshotAsOf(failureSnapshot),
        accessibilityChecked: accessibilityChecked,
        stalePulseVisibleDuringRefresh: stalePulseVisible,
        backgroundDetailProgressVisible: backgroundProgressVisible,
        backgroundDetailProgressScreenshotPath: backgroundProgressScreenshotPath,
        backgroundDetailProgressScreenshotBlocker: backgroundProgressScreenshotBlocker,
        freshPulseVisibleAfterRefresh: freshPulseVisible,
        transientFailurePreservedSnapshot: failurePreservedSnapshot,
        transientFailurePulseVisible: failurePulseVisible,
        transientFailureRetryVisible: failureRetryVisible,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard failurePreservedSnapshot,
          !accessibilityChecked || (
              stalePulseVisible
              && backgroundProgressVisible
              && freshPulseVisible
              && failurePulseVisible
              && failureRetryVisible
          )
    else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "scripted returning launch did not prove background progress visibility, fresh replacement, or transient failure preservation",
            artifacts: [artifactPath(proof)] + axArtifacts
        )
    }

    return SmokeReport(
        name: "scripted-returning-launch",
        status: SmokeStatus.passed,
        detail: "returning launch kept the seeded pulse visible with active detail progress, replaced it after complete scripted data, and preserved it with a details retry after transient failure",
        artifacts: [artifactPath(proof)] + axArtifacts
    )
}

private func manualClaudePDTSmoke(arguments: [String]) throws -> SmokeReport {
    guard !arguments.contains("--bare") else {
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.failed,
            detail: "refusing manual Claude readiness proof with --bare; use normal claude -p so the logged-in Claude CLI user and MCP setup are exercised",
            artifacts: []
        )
    }

    let options = try SmokeOptions(arguments: arguments)
    let environment = ProcessInfo.processInfo.environment
    let claudePath = options.claude?.path ?? environment["PDTBAR_CLAUDE_BIN"] ?? "claude"
    let claude = URL(fileURLWithPath: claudePath)
    let model = options.model ?? environment["PDTBAR_CLAUDE_MODEL"] ?? "opus"
    let timeout = options.timeoutWasProvided ? options.timeout : 60.0
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

    guard claudePath.contains("/") || executableExistsOnPath(claudePath) else {
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.skipped,
            detail: "Claude CLI unavailable on PATH; install/sign in with Claude and rerun, or pass --claude <path>",
            artifacts: []
        )
    }
    if claudePath.contains("/") {
        guard FileManager.default.isExecutableFile(atPath: claude.path) else {
            return SmokeReport(
                name: "manual-claude-pdt",
                status: SmokeStatus.skipped,
                detail: "Claude CLI unavailable at passed --claude path; install/sign in with Claude and rerun",
                artifacts: []
            )
        }
    }

    let started = Date()
    let allowedTools: [String]
    do {
        allowedTools = try manualClaudePDTAllowedTools(
            claudePath: claudePath,
            model: model,
            timeout: min(timeout, 60.0)
        )
    } catch {
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.skipped,
            detail: "local Claude/PDT setup required; ToolSearch did not resolve every required PDT read tool",
            artifacts: []
        )
    }
    let result: CommandResult
    let sessionID = UUID().uuidString
    let filesBeforeCall = claudeToolResultFiles()
    do {
        var claudeArguments = [
            claudePath,
            "--model", model,
            "--disallowedTools", manualClaudePDTDisallowedTools().joined(separator: ","),
            "--session-id", sessionID,
            "-p", manualClaudePDTPrompt(resolvedTools: allowedTools.filter { $0.hasPrefix("mcp__") }),
            "--output-format", "stream-json",
            "--verbose",
            "--no-session-persistence",
            "--json-schema", manualClaudePDTJSONSchema(),
        ]
        claudeArguments.insert(contentsOf: ["--allowedTools", allowedTools.joined(separator: ",")], at: 3)
        result = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: claudeArguments,
            timeout: timeout
        )
    } catch let CommandError.commandFailed(_, stdout, stderr) {
        let combined = [stdout, stderr].joined(separator: "\n")
        let createdFiles = claudeToolResultFiles().subtracting(filesBeforeCall)
        let referencedFiles = Set(savedClaudeToolResultFiles(in: Data(combined.utf8)))
        deleteSavedClaudeToolResultFiles(pdtToolResultFiles(
            in: createdFiles,
            referencedFiles: referencedFiles,
            sessionID: sessionID
        ))
        guard PDTLiveUnavailableClassifier.shouldSkip(combined) || isClaudeModelSetupError(combined) else {
            return SmokeReport(
                name: "manual-claude-pdt",
                status: SmokeStatus.failed,
                detail: "claude -p returned an error before redacted PDT reachability proof could be parsed",
                artifacts: []
            )
        }
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.skipped,
            detail: "local Claude/PDT setup required; claude -p did not complete with the configured model alias or MCP setup",
            artifacts: []
        )
    } catch CommandError.timedOut {
        deleteSavedClaudeToolResultFiles(pdtToolResultFiles(
            in: claudeToolResultFiles().subtracting(filesBeforeCall),
            referencedFiles: [],
            sessionID: sessionID
        ))
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.skipped,
            detail: "claude -p timed out before PDT reachability proof completed; local Claude/PDT setup may need attention",
            artifacts: []
        )
    }

    let payload = redactedClaudePDTResponse(from: result.stdout)
    let createdFiles = claudeToolResultFiles().subtracting(filesBeforeCall)
    let referencedFiles = Set(savedClaudeToolResultFiles(in: result.stdout))
    deleteSavedClaudeToolResultFiles(pdtToolResultFiles(
        in: createdFiles,
        referencedFiles: referencedFiles,
        sessionID: sessionID
    ))

    let required = Set(PDTReadTools.requiredV1)
    let reported = Set(payload.toolNames)
    let missing = PDTReadTools.requiredV1.filter { !reported.contains($0) }
    let writeToolCount = max(payload.writeToolsCalled, payload.nonReadPDTToolNames.count)
    let success = (payload.status == "ok" || payload.status == "redacted-ok")
        && missing.isEmpty
        && writeToolCount == 0
        && payload.toolResultErrorCount == 0
    let duration = Date().timeIntervalSince(started)
    let proof = ManualClaudePDTProof(
        promptMode: "-p",
        bareModeUsed: false,
        requiredReadTools: PDTReadTools.requiredV1,
        reportedReadTools: payload.toolNames.filter { required.contains($0) }.sorted(),
        reportedToolCount: reported.intersection(required).count,
        selectorCount: payload.selectors.count,
        selectors: payload.selectors.sorted(),
        durationSeconds: roundedSmokeValue(duration, places: 2),
        statusText: redactedStatus(payload.statusText),
        writeToolsCalled: writeToolCount,
        toolResultErrorCount: payload.toolResultErrorCount,
        rawClaudeOutputRedacted: true,
        rawPortfolioPayloadsRedacted: true
    )
    let proofPath = artifacts.appending(path: "pdtbar-manual-claude-pdt-proof.json")
    try stableJSONData(proof).write(to: proofPath, options: .atomic)

    if payload.status == "setup-required" {
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.skipped,
            detail: "local Claude/PDT setup required; claude -p completed but reported setup-required without raw PDT data",
            artifacts: [artifactPath(proofPath)]
        )
    }

    guard success else {
        return SmokeReport(
            name: "manual-claude-pdt",
            status: SmokeStatus.failed,
            detail: "claude -p did not prove every required PDT read tool with redacted, read-only proof; missing=\(missing.joined(separator: ",")); writeToolsCalled=\(writeToolCount); toolResultErrorCount=\(payload.toolResultErrorCount)",
            artifacts: [artifactPath(proofPath)]
        )
    }

    return SmokeReport(
        name: "manual-claude-pdt",
        status: SmokeStatus.passed,
        detail: "claude -p reached required PDT read tools through the logged-in Claude setup; proof contains only tool names, counts, selectors, duration, and redacted status",
        artifacts: [artifactPath(proofPath)]
    )
}

private func isClaudeModelSetupError(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    guard lowercased.contains("model") else {
        return false
    }
    return [
        "unavailable",
        "not available",
        "unknown model",
        "invalid model",
        "does not exist",
        "not found",
        "no access",
        "access denied",
    ].contains { lowercased.contains($0) }
}

private func livePDTSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let environment = ProcessInfo.processInfo.environment
    if let schemaPath = environment["PDTBAR_LIVE_PDT_SCHEMA_JSON"], !schemaPath.isEmpty {
        let schemaData = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        let object = try JSONSerialization.jsonObject(with: schemaData)
        let schemaToolNames = toolNames(in: object)
        let missingTools = PDTReadTools.requiredV1.filter { tool in
            !schemaToolNames.contains(tool)
        }
        guard missingTools.isEmpty else {
            return SmokeReport(
                name: "live-pdt",
                status: SmokeStatus.failed,
                detail: "schema missing required PDT read tools: \(missingTools.joined(separator: ", "))",
                artifacts: [schemaPath]
            )
        }
    }

    let server = try discoverLivePDTServer(options: options)
    guard let server else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.skipped,
            detail: "no configured mcporter PDT server exposes the required read tools; set PDTBAR_LIVE_PDT_SERVER or configure/auth a PDT server, then rerun",
            artifacts: []
        )
    }
    let mcporter: McporterTool
    do {
        mcporter = try resolveMcporterTool(options: options, environment: environment)
    } catch let error as McporterSetupError {
        return SmokeReport(
            name: "live-pdt",
            status: error.status,
            detail: error.detail,
            artifacts: error.artifacts
        )
    }

    let snapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-live-pdt-smoke")
    defer {
        try? FileManager.default.removeItem(at: snapshotStore.directory)
    }
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-live-pdt-pulse-proof.json")
    let liveTimeout = options.timeoutWasProvided ? options.timeout : 60.0
    let result: PressureRunResult
    do {
        result = try PressureRunner.run(
            dataSource: PDTLiveDataSource(
                toolClient: PDTLiveMcporterClient(
                    mcporter: mcporter,
                    server: server,
                    timeout: liveTimeout
                )
            ),
            snapshotStore: snapshotStore
        )
    } catch let CommandError.commandFailed(_, stdout, stderr) {
        guard PDTLiveUnavailableClassifier.shouldSkip([stdout, stderr].joined(separator: "\n")) else {
            return SmokeReport(
                name: "live-pdt",
                status: SmokeStatus.failed,
                detail: "configured PDT server returned a read-tool error; live smoke did not prove the PortfolioDataSource path",
                artifacts: []
            )
        }
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.skipped,
            detail: "configured PDT server did not complete read-only tool calls; credentials or local server access may be missing",
            artifacts: []
        )
    } catch CommandError.timedOut {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.skipped,
            detail: "configured PDT server timed out during read-only smoke; local access may be unavailable",
            artifacts: []
        )
    } catch let error as PDTLiveDataSourceError {
        guard !error.shouldSkipLiveSmoke else {
            return SmokeReport(
                name: "live-pdt",
                status: SmokeStatus.skipped,
                detail: "configured PDT server returned an auth/offline response; cached credentials or local access may be missing",
                artifacts: []
            )
        }
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.failed,
            detail: "live PDT response was not decodable as the expected read-only tool shape",
            artifacts: []
        )
    }

    let surface = MenuBarSurfaceRenderer.render(descriptor: result.descriptor)
    let proofPayload = LivePDTPulseProof(
        mcporterSource: mcporter.sourceDescription,
        snapshotWritten: result.snapshotCommit.written,
        statusAccessibilityIdentifier: surface.status.accessibilityIdentifier,
        sectionIDs: surface.sections.map(\.id),
        rowCount: surface.sections.flatMap(\.rows).count,
        rawPortfolioValuesRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)
    let pulseRows = surface.sections.first { $0.id == "pulse" }?.rows ?? []
    guard result.snapshotCommit.written,
          !surface.status.accessibilityIdentifier.isEmpty,
          !pulseRows.isEmpty,
          result.model.facetSnapshots.allocation.openHoldingCount > 0
    else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.failed,
            detail: "live PDT read succeeded, but did not produce open holdings and pulse rows",
            artifacts: [artifactPath(proof)]
        )
    }
    return SmokeReport(
        name: "live-pdt",
        status: SmokeStatus.passed,
        detail: "read-only live PDT data reached PressureRunner and rendered a pulse descriptor with isolated snapshot state; private portfolio values redacted from proof",
        artifacts: [artifactPath(proof)]
    )
}

private func packagedAppSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    let fixture = options.fixture ?? defaultFixture
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "packaged-app",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let process = Process()
    let snapshotDirectory = try options.resolvedSnapshotDirectory()
    let snapshot = snapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let previousSnapshotModifiedAt = modificationDate(of: snapshot)
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path, "--snapshot-dir", snapshotDirectory.path]
    process.environment = ProcessInfo.processInfo.environment.merging(["PDTBAR_FIXTURE_MODE": "1"]) { _, new in new }
    try process.run()
    Thread.sleep(forTimeInterval: options.timeout)
    let running = process.isRunning
    if running {
        process.terminate()
    }
    process.waitUntilExit()

    let timeoutDescription = String(format: "%.1f", options.timeout)
    guard running else {
        return SmokeReport(
            name: "packaged-app",
            status: SmokeStatus.failed,
            detail: "fixture-mode app exited before the smoke timeout",
            artifacts: []
        )
    }
    guard FileManager.default.fileExists(atPath: snapshot.path) else {
        return SmokeReport(
            name: "packaged-app",
            status: SmokeStatus.failed,
            detail: "fixture-mode app stayed running for \(timeoutDescription)s but did not write latest-portfolio-snapshot.json",
            artifacts: [artifactPath(snapshotDirectory)]
        )
    }
    if let previousSnapshotModifiedAt,
       let currentSnapshotModifiedAt = modificationDate(of: snapshot),
       currentSnapshotModifiedAt <= previousSnapshotModifiedAt
    {
        return SmokeReport(
            name: "packaged-app",
            status: SmokeStatus.failed,
            detail: "fixture-mode app stayed running for \(timeoutDescription)s but did not refresh latest-portfolio-snapshot.json",
            artifacts: [artifactPath(snapshot)]
        )
    }
    return SmokeReport(
        name: "packaged-app",
        status: SmokeStatus.passed,
        detail: "fixture-mode app launched with isolated snapshot dir, wrote latest-portfolio-snapshot.json, and stayed running for \(timeoutDescription)s",
        artifacts: [artifactPath(snapshot)]
    )
}

private func peekabooSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let peekaboo = options.peekaboo ?? URL(fileURLWithPath: "/opt/homebrew/bin/peekaboo")
    guard FileManager.default.isExecutableFile(atPath: peekaboo.path) else {
        return SmokeReport(
            name: "peekaboo",
            status: SmokeStatus.skipped,
            detail: "Peekaboo unavailable at \(peekaboo.path); pass --peekaboo <path> to run UI proof",
            artifacts: []
        )
    }

    let permissionJSON = try run(peekaboo, arguments: ["permissions", "--json"], timeout: 15).stdout
    guard let missingPermissions = requiredMissingPermissions(from: permissionJSON) else {
        return SmokeReport(
            name: "peekaboo",
            status: SmokeStatus.failed,
            detail: "Peekaboo permissions output was not valid JSON",
            artifacts: []
        )
    }
    guard missingPermissions.isEmpty else {
        return SmokeReport(
            name: "peekaboo",
            status: SmokeStatus.skipped,
            detail: "Peekaboo TCC permissions missing: \(missingPermissions.joined(separator: ", "))",
            artifacts: []
        )
    }

    let preflightSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "peekaboo-preflight")
    let appReport = try packagedAppSmoke(arguments: [
        "--app", (options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")).path,
        "--fixture", (options.fixture ?? defaultFixture).path,
        "--snapshot-dir", preflightSnapshotDirectory.path,
        "--timeout", "2.0",
    ])
    guard appReport.status == SmokeStatus.passed else {
        return appReport
    }

    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    let fixture = options.fixture ?? defaultFixture
    let expectedStatusTitle = try fixtureStatusTitle(for: fixture)
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

    let process = Process()
    let snapshotDirectory = try options.resolvedSnapshotDirectory()
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path, "--snapshot-dir", snapshotDirectory.path]
    process.environment = ProcessInfo.processInfo.environment.merging(["PDTBAR_FIXTURE_MODE": "1"]) { _, new in new }
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
    Thread.sleep(forTimeInterval: 1.0)

    let menubarJSON = try run(peekaboo, arguments: ["menubar", "list", "--json"], timeout: 20).stdout
    guard String(data: menubarJSON, encoding: .utf8)?.contains(expectedStatusTitle) == true else {
        return SmokeReport(
            name: "peekaboo",
            status: SmokeStatus.failed,
            detail: "Peekaboo could inspect the menu bar, but did not see expected fixture status text",
            artifacts: []
        )
    }

    let screenshot = artifacts.appending(path: "pdtbar-menubar.png")
    _ = try run(peekaboo, arguments: ["image", "--app", "menubar", "--path", screenshot.path, "--json"], timeout: 20)
    return SmokeReport(
        name: "peekaboo",
        status: SmokeStatus.passed,
        detail: "Peekaboo inspected fixture-mode menu bar text and captured a screenshot",
        artifacts: [artifactPath(screenshot)]
    )
}

private func realUserPulseSmoke(
    arguments: [String],
    captureDetailScreenshots: Bool = true
) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: "real-user-pulse",
            status: SmokeStatus.skipped,
            detail: "macOS Accessibility permission missing for real-user pulse e2e; grant Accessibility in System Settings > Privacy & Security > Accessibility to the app running this command, then rerun",
            artifacts: []
        )
    }

    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    let fixture = options.fixture ?? defaultFixture
    let expectedSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "real-user-pulse-expected")
    let expectedScenario = try fixturePulseScenario(fixture: fixture, snapshotDirectory: expectedSnapshotDirectory)
    let surface = MenuBarSurfaceRenderer.render(descriptor: expectedScenario.run.descriptor)
    let expectedTargets = requiredPulseMenuTargets(in: surface)
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let screenshotPeekaboo = peekabooScreenshotTool(
        options.peekaboo ?? URL(fileURLWithPath: "/opt/homebrew/bin/peekaboo")
    )

    let preflightSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "real-user-pulse-preflight")
    let appReport = try packagedAppSmoke(arguments: [
        "--app", app.path,
        "--fixture", fixture.path,
        "--snapshot-dir", preflightSnapshotDirectory.path,
        "--timeout", String(options.timeout),
    ])
    guard appReport.status == SmokeStatus.passed else {
        return appReport
    }

    let snapshotDirectory = try options.isolatedSnapshotDirectory(prefix: "real-user-pulse-app")
    if expectedScenario.seededPrior != nil {
        _ = try PressureRunner.seedPriorSnapshot(fixture: fixture, snapshotDirectory: snapshotDirectory)
    }
    let process = Process()
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path, "--snapshot-dir", snapshotDirectory.path]
    process.environment = ProcessInfo.processInfo.environment.merging([
        "PDTBAR_FIXTURE_MODE": "1",
    ]) { _, new in new }
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
    Thread.sleep(forTimeInterval: 1.0)

    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "real-user-pulse",
            status: SmokeStatus.failed,
            detail: "fixture-mode app launched, but Accessibility could not find status item \(surface.status.accessibilityIdentifier)",
            artifacts: []
        )
    }
    let statusText = accessibilityTexts(in: statusElement)
    guard statusText.contains(surface.status.accessibilityLabel) || statusText.contains(surface.status.title) else {
        return SmokeReport(
            name: "real-user-pulse",
            status: SmokeStatus.failed,
            detail: "fixture-mode app exposed status item \(surface.status.accessibilityIdentifier), but not visible expected status \(surface.status.accessibilityLabel)",
            artifacts: []
        )
    }
    let openedMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: options.timeout
    )
    let menuSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
        expectedMenuIdentifiers,
        in: appElement,
        timeout: options.timeout
    )
    let evidence = artifacts.appending(path: "pdtbar-real-user-pulse-ax.json")
    try writeAccessibilityEvidence(
        snapshot: menuSnapshot,
        expected: expectedTargets,
        statusIdentifier: surface.status.accessibilityIdentifier,
        statusText: statusText,
        output: evidence
    )
    let missingTargets = expectedTargets.filter { !menuSnapshot.identifiers.contains($0.accessibilityIdentifier) }
    guard missingTargets.isEmpty else {
        let missingLabels = missingTargets
            .map { "\($0.accessibilityIdentifier) (\($0.title))" }
            .joined(separator: ", ")
        return SmokeReport(
            name: "real-user-pulse",
            status: SmokeStatus.failed,
            detail: "could not verify opened fixture-mode pulse menu after \(openedMenu.attempts.joined(separator: ", ")); missing expected fixture targets: \(missingLabels)",
            artifacts: [artifactPath(evidence)]
        )
    }

    movePointerToNeutralMenuArea(in: menuSnapshot)
    let screenshot = (try? captureNativeMenuScreenshot(
        name: "pdtbar-real-user-pulse",
        snapshot: menuSnapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        artifacts: artifacts
    )) ?? (try? captureRealUserMenuScreenshot(
        name: "pdtbar-real-user-pulse",
        snapshot: menuSnapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )) ?? captureFullScreenScreenshot(
        name: "pdtbar-real-user-pulse-screen-fallback",
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )
    let allocationScreenshot = captureDetailScreenshots ? try? captureAllocationDetailScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    ) : nil
    let pricesScreenshot = captureDetailScreenshots ? try? capturePricesDetailScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    ) : nil
    let attentionScreenshot = captureDetailScreenshots ? try? captureAttentionExplanationScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    ) : nil
    let dataHealthScreenshot = captureDetailScreenshots ? try? captureDataHealthDetailScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    ) : nil
    let priorDetail = expectedScenario.seededPrior.map { "; seeded prior snapshot \($0.asOf)" } ?? ""
    let screenshotDetail = screenshot == nil ? "" : "; captured menu screenshot"
    let allocationScreenshotDetail = allocationScreenshot == nil ? "" : "; captured allocation detail screenshot"
    let pricesScreenshotDetail = pricesScreenshot == nil ? "" : "; captured Prices detail screenshot"
    let attentionScreenshotDetail = attentionScreenshot == nil ? "" : "; captured attention explanation screenshot"
    let dataHealthScreenshotDetail = dataHealthScreenshot == nil ? "" : "; captured Data health screenshot"
    var reportArtifacts = [artifactPath(evidence)]
    if let screenshot {
        reportArtifacts.append(artifactPath(screenshot))
    }
    if let allocationScreenshot {
        reportArtifacts.append(artifactPath(allocationScreenshot))
    }
    if let pricesScreenshot {
        reportArtifacts.append(artifactPath(pricesScreenshot))
    }
    if let attentionScreenshot {
        reportArtifacts.append(artifactPath(attentionScreenshot))
    }
    if let dataHealthScreenshot {
        reportArtifacts.append(artifactPath(dataHealthScreenshot))
    }
    return SmokeReport(
        name: "real-user-pulse",
        status: SmokeStatus.passed,
        detail: "launched fixture-mode app with isolated state\(priorDetail), opened menu-bar pulse through \(openedMenu.successfulAttempt ?? "Accessibility"), verified status plus pulse/allocation/income/big-mover/Data selectors for \(fixture.lastPathComponent)\(screenshotDetail)\(allocationScreenshotDetail)\(pricesScreenshotDetail)\(attentionScreenshotDetail)\(dataHealthScreenshotDetail)",
        artifacts: reportArtifacts
    )
}

private func portfolioSummaryProof(arguments: [String]) throws -> SmokeReport {
    var report = try realUserPulseSmoke(arguments: arguments, captureDetailScreenshots: false)
    report.name = "portfolio-summary-proof"
    guard report.status == SmokeStatus.passed else {
        return report
    }
    let hasActualMenuScreenshot = report.artifacts.contains {
        $0.hasSuffix("pdtbar-real-user-pulse-menu.png")
    }
    guard hasActualMenuScreenshot else {
        report.status = SmokeStatus.failed
        report.detail = "summary selectors were visible through Accessibility, but actual menu screenshot capture was unavailable"
        return report
    }
    report.detail = "fresh fixture app rendered the accessible two-column Summary grid above Portfolio in an actual menu screenshot"
    return report
}

private func settingsProofMenuIdentifiers(for surface: MenuBarSurface) -> Set<String> {
    Set(requiredPulseMenuTargets(in: surface).map(\.accessibilityIdentifier))
        .union(["pdtbar.section.actions", "pdtbar.row.actions.settings"])
}

private func sensitivePortfolioTexts(in surface: MenuBarSurface) -> Set<String> {
    var texts: Set<String> = []
    for section in surface.sections {
        for row in section.rows {
            collectSensitivePortfolioTexts(from: row, into: &texts)
        }
    }
    return texts.filter(isSensitivePortfolioText)
}

private func collectSensitivePortfolioTexts(from row: MenuBarRowSurface, into texts: inout Set<String>) {
    texts.insert(row.title)
    if let detail = row.detail {
        texts.insert(detail)
        texts.insert("\(row.title) - \(detail)")
    }
    if let summary = row.portfolioSummary {
        texts.insert(summary.totalValue)
        texts.insert(summary.accessibilityLabel)
    }
    if let chart = row.barChart {
        for bar in chart.bars {
            texts.insert(bar.detail)
        }
    }
    for child in row.children {
        collectSensitivePortfolioTexts(from: child, into: &texts)
    }
}

private func isSensitivePortfolioText(_ text: String) -> Bool {
    let currencyTokens = ["EUR ", "USD ", "GBP ", "CHF ", "CAD ", "AUD ", "€", "$", "£"]
    return currencyTokens.contains { text.contains($0) }
}

private func portfolioValuesProofArtifacts(
    evidence: URL? = nil,
    settingsScreenshot: URL?,
    hiddenMenuScreenshot: URL?
) -> [String] {
    [evidence, settingsScreenshot, hiddenMenuScreenshot].compactMap { url in
        url.map(artifactPath)
    }
}

private func portfolioValuesSettingsProof(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.skipped,
            detail: "macOS Accessibility permission missing for Settings/menu proof; no authorization prompt requested",
            artifacts: []
        )
    }

    let screenshotPeekaboo = peekabooScreenshotTool(
        options.peekaboo ?? URL(fileURLWithPath: "/opt/homebrew/bin/peekaboo")
    )
    guard let screenshotPeekaboo else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.skipped,
            detail: "Peekaboo screenshot permission unavailable for public PNG proof; no authorization prompt requested",
            artifacts: []
        )
    }

    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    let fixture = options.fixture ?? defaultFixture
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let expectedSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "portfolio-values-settings-expected")
    let expectedScenario = try fixturePulseScenario(fixture: fixture, snapshotDirectory: expectedSnapshotDirectory)
    let visibleSurface = MenuBarSurfaceRenderer.render(descriptor: expectedScenario.run.descriptor)
    let hiddenSurface = MenuBarSurfaceRenderer.render(
        descriptor: expectedScenario.run.descriptor.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
    )
    let visibleSensitiveTexts = sensitivePortfolioTexts(in: visibleSurface)
    guard !visibleSensitiveTexts.isEmpty else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "fixture surface did not expose any monetary values to prove hiding",
            artifacts: []
        )
    }

    let suiteName = "pdtbar-smoke-\(UUID().uuidString)"
    if let defaults = UserDefaults(suiteName: suiteName) {
        defaults.removePersistentDomain(forName: suiteName)
    }
    defer {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    let snapshotDirectory = try options.isolatedSnapshotDirectory(prefix: "portfolio-values-settings-app")
    let firstLaunch = try launchFixtureApp(
        app: app,
        fixture: fixture,
        snapshotDirectory: snapshotDirectory,
        userDefaultsSuite: suiteName
    )
    defer {
        terminate(firstLaunch)
    }

    let appElement = AXUIElementCreateApplication(firstLaunch.processIdentifier)
    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: visibleSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "fixture app launched, but Accessibility could not find status item \(visibleSurface.status.accessibilityIdentifier)",
            artifacts: []
        )
    }

    let expectedMenuIdentifiers = settingsProofMenuIdentifiers(for: visibleSurface)
    let visibleMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: options.timeout
    )
    guard let visibleSnapshot = visibleMenu.snapshot,
          visibleSensitiveTexts.contains(where: visibleSnapshot.texts.contains)
    else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "visible menu did not expose expected fixture monetary text before toggling",
            artifacts: []
        )
    }

    guard let settingsOpenAttempt = pressMenuRow(
        statusElement: statusElement,
        appElement: appElement,
        rowIdentifier: "pdtbar.row.actions.settings",
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "could not press Settings menu row",
            artifacts: []
        )
    }
    guard let checkbox = waitForAccessibilityElement(
        in: appElement,
        matchingText: "Show portfolio values",
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "Settings window opened via \(settingsOpenAttempt), but checkbox was not accessible",
            artifacts: []
        )
    }

    let settingsScreenshot = try captureElementScreenshot(
        name: "pdtbar-settings-show-portfolio-values",
        element: checkbox,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )
    let snapshot = snapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let snapshotModifiedBeforeToggle = modificationDate(of: snapshot)
    let toggleOffResult = AXUIElementPerformAction(checkbox, kAXPressAction as CFString)
    guard toggleOffResult == .success else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "Settings checkbox was found, but AXPress failed with \(toggleOffResult)",
            artifacts: settingsScreenshot.map { [artifactPath($0)] } ?? []
        )
    }
    Thread.sleep(forTimeInterval: 0.4)

    let hiddenIdentifiers = settingsProofMenuIdentifiers(for: hiddenSurface)
    let hiddenMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: hiddenIdentifiers,
        timeout: options.timeout
    )
    guard let hiddenSnapshot = hiddenMenu.snapshot else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "menu did not reopen after values were hidden",
            artifacts: settingsScreenshot.map { [artifactPath($0)] } ?? []
        )
    }
    guard hiddenSnapshot.texts.contains(PortfolioValueDisplaySettings.hiddenPlaceholder),
          visibleSensitiveTexts.allSatisfy({ !hiddenSnapshot.texts.contains($0) })
    else {
        let evidence = try writePortfolioValuesSettingsEvidence(
            artifacts: artifacts,
            suiteName: suiteName,
            visibleSensitiveTexts: visibleSensitiveTexts,
            hiddenTexts: hiddenSnapshot.texts,
            relaunchHiddenTexts: [],
            restoredTexts: [],
            snapshotModifiedBeforeToggle: snapshotModifiedBeforeToggle,
            snapshotModifiedAfterToggle: modificationDate(of: snapshot)
        )
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "hidden menu did not replace every fixture monetary text with the placeholder",
            artifacts: [artifactPath(evidence)] + (settingsScreenshot.map { [artifactPath($0)] } ?? [])
        )
    }
    let snapshotModifiedAfterToggle = modificationDate(of: snapshot)
    guard snapshotModifiedAfterToggle == snapshotModifiedBeforeToggle else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "settings toggle rewrote the fixture snapshot, so no-refetch proof failed",
            artifacts: settingsScreenshot.map { [artifactPath($0)] } ?? []
        )
    }

    let hiddenMenuScreenshot = try captureNativeMenuScreenshot(
        name: "pdtbar-values-hidden",
        snapshot: hiddenSnapshot,
        expectedMenuIdentifiers: hiddenIdentifiers,
        artifacts: artifacts
    )

    terminate(firstLaunch)
    let relaunch = try launchFixtureApp(
        app: app,
        fixture: fixture,
        snapshotDirectory: snapshotDirectory,
        userDefaultsSuite: suiteName
    )
    defer {
        terminate(relaunch)
    }
    let relaunchAppElement = AXUIElementCreateApplication(relaunch.processIdentifier)
    guard let relaunchStatus = waitForAccessibilityElement(
        in: relaunchAppElement,
        identifier: hiddenSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "relaunch did not expose fixture status item",
            artifacts: portfolioValuesProofArtifacts(
                settingsScreenshot: settingsScreenshot,
                hiddenMenuScreenshot: hiddenMenuScreenshot
            )
        )
    }
    let relaunchMenu = openStatusMenu(
        relaunchStatus,
        appElement: relaunchAppElement,
        expectedMenuIdentifiers: hiddenIdentifiers,
        timeout: options.timeout
    )
    guard let relaunchSnapshot = relaunchMenu.snapshot,
          relaunchSnapshot.texts.contains(PortfolioValueDisplaySettings.hiddenPlaceholder),
          visibleSensitiveTexts.allSatisfy({ !relaunchSnapshot.texts.contains($0) })
    else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "hidden portfolio value preference did not persist across relaunch",
            artifacts: portfolioValuesProofArtifacts(
                settingsScreenshot: settingsScreenshot,
                hiddenMenuScreenshot: hiddenMenuScreenshot
            )
        )
    }

    guard pressMenuRow(
        statusElement: relaunchStatus,
        appElement: relaunchAppElement,
        rowIdentifier: "pdtbar.row.actions.settings",
        expectedMenuIdentifiers: hiddenIdentifiers,
        timeout: options.timeout
    ) != nil,
          let relaunchCheckbox = waitForAccessibilityElement(
              in: relaunchAppElement,
              matchingText: "Show portfolio values",
              timeout: options.timeout
          )
    else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "could not reopen Settings after relaunch",
            artifacts: portfolioValuesProofArtifacts(
                settingsScreenshot: settingsScreenshot,
                hiddenMenuScreenshot: hiddenMenuScreenshot
            )
        )
    }
    let snapshotModifiedBeforeRestore = modificationDate(of: snapshot)
    let toggleOnResult = AXUIElementPerformAction(relaunchCheckbox, kAXPressAction as CFString)
    guard toggleOnResult == .success else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "Settings checkbox restore AXPress failed with \(toggleOnResult)",
            artifacts: portfolioValuesProofArtifacts(
                settingsScreenshot: settingsScreenshot,
                hiddenMenuScreenshot: hiddenMenuScreenshot
            )
        )
    }
    Thread.sleep(forTimeInterval: 0.4)
    let restoredMenu = openStatusMenu(
        relaunchStatus,
        appElement: relaunchAppElement,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: options.timeout
    )
    guard let restoredSnapshot = restoredMenu.snapshot,
          visibleSensitiveTexts.contains(where: restoredSnapshot.texts.contains),
          !restoredSnapshot.texts.contains(PortfolioValueDisplaySettings.hiddenPlaceholder),
          modificationDate(of: snapshot) == snapshotModifiedBeforeRestore
    else {
        return SmokeReport(
            name: "portfolio-values-settings-proof",
            status: SmokeStatus.failed,
            detail: "turning values back on did not restore fixture monetary text from in-memory state without rewriting the snapshot",
            artifacts: portfolioValuesProofArtifacts(
                settingsScreenshot: settingsScreenshot,
                hiddenMenuScreenshot: hiddenMenuScreenshot
            )
        )
    }

    let evidence = try writePortfolioValuesSettingsEvidence(
        artifacts: artifacts,
        suiteName: suiteName,
        visibleSensitiveTexts: visibleSensitiveTexts,
        hiddenTexts: hiddenSnapshot.texts,
        relaunchHiddenTexts: relaunchSnapshot.texts,
        restoredTexts: restoredSnapshot.texts,
        snapshotModifiedBeforeToggle: snapshotModifiedBeforeToggle,
        snapshotModifiedAfterToggle: snapshotModifiedAfterToggle
    )
    return SmokeReport(
        name: "portfolio-values-settings-proof",
        status: SmokeStatus.passed,
        detail: "packaged fixture app opened native Settings, toggled portfolio values off without snapshot rewrite, persisted hidden values across relaunch, then restored formatted values from current state",
        artifacts: portfolioValuesProofArtifacts(
            evidence: evidence,
            settingsScreenshot: settingsScreenshot,
            hiddenMenuScreenshot: hiddenMenuScreenshot
        )
    )
}

private func launchFixtureApp(
    app: URL,
    fixture: URL,
    snapshotDirectory: URL,
    userDefaultsSuite: String
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path, "--snapshot-dir", snapshotDirectory.path]
    process.environment = ProcessInfo.processInfo.environment.merging([
        "PDTBAR_FIXTURE_MODE": "1",
        PDTBarSettingsStore.userDefaultsSuiteEnvironmentKey: userDefaultsSuite,
    ]) { _, new in new }
    try process.run()
    Thread.sleep(forTimeInterval: 0.8)
    return process
}

private func writePortfolioValuesSettingsEvidence(
    artifacts: URL,
    suiteName: String,
    visibleSensitiveTexts: Set<String>,
    hiddenTexts: Set<String>,
    relaunchHiddenTexts: Set<String>,
    restoredTexts: Set<String>,
    snapshotModifiedBeforeToggle: Date?,
    snapshotModifiedAfterToggle: Date?
) throws -> URL {
    let evidence = PortfolioValuesSettingsEvidence(
        userDefaultsSuite: suiteName,
        visibleSensitiveTexts: visibleSensitiveTexts.sorted(),
        hiddenPlaceholder: PortfolioValueDisplaySettings.hiddenPlaceholder,
        hiddenTexts: hiddenTexts.sorted(),
        relaunchHiddenTexts: relaunchHiddenTexts.sorted(),
        restoredTexts: restoredTexts.sorted(),
        snapshotModifiedBeforeToggle: snapshotModifiedBeforeToggle,
        snapshotModifiedAfterToggle: snapshotModifiedAfterToggle,
        snapshotUnchangedOnToggle: snapshotModifiedBeforeToggle == snapshotModifiedAfterToggle
    )
    let output = artifacts.appending(path: "pdtbar-portfolio-values-settings-proof.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    try encoder.encode(evidence).write(to: output, options: .atomic)
    return output
}


private func fixtureProof(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let fixture = options.fixture ?? defaultFixture
    let output = options.output ?? packageRoot.appending(path: "docs/smoke/fixture-proof.svg")
    let model = PressureEngine.buildModel(from: try PDTFixtureDataSource(fixture: fixture).snapshot())
    let descriptor = MenuDescriptorRenderer.render(model: model)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fixtureProofSVG(descriptor: descriptor).write(to: output, atomically: true, encoding: .utf8)
    return SmokeReport(
        name: "fixture-proof",
        status: SmokeStatus.passed,
        detail: "rendered fixture descriptor proof for \(fixture.lastPathComponent)",
        artifacts: [artifactPath(output)]
    )
}

private func menuPolishProof(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let output = options.output ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts/pdtbar-menu-polish-proof.svg")
    let quietDescriptor = MenuDescriptorRenderer.render(
        model: PressureEngine.buildModel(from: try PDTFixtureDataSource(fixture: defaultFixture).snapshot())
    )
    let pressureStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-menu-polish-pressure")
    defer {
        try? FileManager.default.removeItem(at: pressureStore.directory)
    }
    let pressureDescriptor = try PressureRunner.run(
        fixture: packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json"),
        snapshotDirectory: pressureStore.directory
    ).descriptor
    let cards = [
        MenuProofCard(title: "Setup", descriptor: PDTLaunchMenu.descriptor(for: .notConnected)),
        MenuProofCard(title: "Fetching", descriptor: PDTLaunchMenu.descriptor(for: .connected(.fetching))),
        MenuProofCard(title: "All quiet", descriptor: quietDescriptor),
        MenuProofCard(title: "Pressure", descriptor: pressureDescriptor),
        MenuProofCard(title: "Error", descriptor: PDTLaunchMenu.descriptor(for: .connected(.failed))),
    ]
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try menuProofSVG(cards: cards).write(to: output, atomically: true, encoding: .utf8)
    return SmokeReport(
        name: "menu-polish-proof",
        status: SmokeStatus.passed,
        detail: "rendered sanitized setup/fetching/all-quiet/pressure/error menu proof",
        artifacts: [artifactPath(output)]
    )
}

private struct PulseScenario {
    var run: PressureRunResult
    var seededPrior: SnapshotCommit?
}

private func fixturePulseScenario(fixture: URL, snapshotDirectory: URL) throws -> PulseScenario {
    let seededPrior: SnapshotCommit?
    do {
        seededPrior = try PressureRunner.seedPriorSnapshot(fixture: fixture, snapshotDirectory: snapshotDirectory)
    } catch FixtureError.missingPriorSnapshot {
        seededPrior = nil
    }
    let run = try PressureRunner.run(fixture: fixture, snapshotDirectory: snapshotDirectory)
    return PulseScenario(run: run, seededPrior: seededPrior)
}

private struct PulseTarget {
    var accessibilityIdentifier: String
    var title: String
}

private func requiredPulseMenuTargets(in surface: MenuBarSurface) -> [PulseTarget] {
    var targets: [PulseTarget] = []
    let requiredSectionIDs = ["summary", "pulse", "allocation", "income", "bigMovers", "freshness"]
    for sectionID in requiredSectionIDs {
        guard let section = surface.sections.first(where: { $0.id == sectionID }) else {
            targets.append(PulseTarget(accessibilityIdentifier: "missing.section.\(sectionID)", title: sectionID))
            continue
        }
        targets.append(PulseTarget(accessibilityIdentifier: section.accessibilityIdentifier, title: section.title))
        for row in section.rows {
            targets.append(contentsOf: requiredMenuTargets(for: row))
        }
    }

    return targets
}

private func requiredSetupMenuTargets(in surface: MenuBarSurface) -> [PulseTarget] {
    surface.sections.flatMap { section in
        [PulseTarget(accessibilityIdentifier: section.accessibilityIdentifier, title: section.title)]
            + section.rows.flatMap(requiredMenuTargets)
    }
}

private func requiredMenuTargets(for row: MenuBarRowSurface) -> [PulseTarget] {
    [PulseTarget(accessibilityIdentifier: row.accessibilityIdentifier, title: row.title)]
        + row.children.flatMap(requiredMenuTargets)
}

private struct AccessibilitySnapshot: Codable {
    var identifiers: Set<String>
    var texts: Set<String>
    var framesByIdentifier: [String: AccessibilityFrame]
}

private struct AccessibilityFrame: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(rect: CGRect) {
        x = Double(rect.minX)
        y = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct OpenMenuResult {
    var snapshot: AccessibilitySnapshot?
    var successfulAttempt: String?
    var attempts: [String]
}

private struct AccessibilityEvidence: Codable {
    var statusIdentifier: String
    var statusText: [String]
    var displayMode: DisplayModeEvidence?
    var expected: [PulseTargetEvidence]
    var observedIdentifiers: [String]
    var observedFramesByIdentifier: [String: AccessibilityFrame]
    var observedTexts: [String]
}

private struct PortfolioValuesSettingsEvidence: Codable {
    var userDefaultsSuite: String
    var visibleSensitiveTexts: [String]
    var hiddenPlaceholder: String
    var hiddenTexts: [String]
    var relaunchHiddenTexts: [String]
    var restoredTexts: [String]
    var snapshotModifiedBeforeToggle: Date?
    var snapshotModifiedAfterToggle: Date?
    var snapshotUnchangedOnToggle: Bool
}

private struct DisplayModeEvidence: Codable {
    var logicalWidth: Int
    var logicalHeight: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
}

private struct LivePDTPulseProof: Codable {
    var mcporterSource: String
    var snapshotWritten: Bool
    var statusAccessibilityIdentifier: String
    var sectionIDs: [String]
    var rowCount: Int
    var rawPortfolioValuesRedacted: Bool
}

private struct ManualClaudePDTProof: Codable {
    var promptMode: String
    var bareModeUsed: Bool
    var requiredReadTools: [String]
    var reportedReadTools: [String]
    var reportedToolCount: Int
    var selectorCount: Int
    var selectors: [String]
    var durationSeconds: Double
    var statusText: String
    var writeToolsCalled: Int
    var toolResultErrorCount: Int
    var rawClaudeOutputRedacted: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct RedactedClaudePDTResponse {
    var status: String
    var statusText: String
    var toolNames: [String]
    var selectors: [String]
    var writeToolsCalled: Int
    var nonReadPDTToolNames: [String]
    var toolResultErrorCount: Int
}

private struct ScriptedPDTConnectorProof: Codable {
    var requiredReadTools: [String]
    var availabilityChecks: Int
    var callCounts: [String: Int]
    var calledOnlyAllowedReadTools: Bool
    var optionalSymbolLookupCalls: Int
    var coalescedSecondFetchReusedFirstResult: Bool
    var snapshotWritten: Bool
    var openHoldingCount: Int
    var renderedSectionIDs: [String]
    var scenarios: [ScriptedPDTConnectorScenarioResult]
    var rawPortfolioPayloadsRedacted: Bool
}

private struct ScriptedPulseMarkReadProof: Codable {
    var stateDirectory: String
    var actionTitle: String
    var actionPayloadMatchedFirstAttentionFingerprint: Bool
    var afterClickHidden: Bool
    var persistedRelaunchHidden: Bool
    var changedDataResurfaced: Bool
    var caughtUpStatusTitle: String
    var changedStatusBadge: String?
    var rawPortfolioPayloadsRedacted: Bool
}

private struct ScriptedReturningLaunchProof: Codable {
    var seededSnapshotPath: String
    var staleSnapshotAsOf: String
    var refreshedSnapshotAsOf: String?
    var failureSnapshotAsOf: String?
    var accessibilityChecked: Bool
    var stalePulseVisibleDuringRefresh: Bool
    var backgroundDetailProgressVisible: Bool
    var backgroundDetailProgressScreenshotPath: String?
    var backgroundDetailProgressScreenshotBlocker: String?
    var freshPulseVisibleAfterRefresh: Bool
    var transientFailurePreservedSnapshot: Bool
    var transientFailurePulseVisible: Bool
    var transientFailureRetryVisible: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct AppBundlePackagingProof: Codable {
    var appBundlePath: String
    var appExecutablePath: String
    var packageCommand: [String]
    var bundleIdentifier: String?
    var bundleExecutable: String?
    var packageType: String?
    var menuBarAccessory: Bool
    var codesignVerified: Bool
    var codesignSignature: String?
    var launchedViaLaunchServices: Bool
    var launchedProcessIdentifier: Int32?
    var launchedBundleIdentifier: String?
    var launchedExecutablePath: String?
    var bundleProcessMatched: Bool
    var appSupportPath: String
    var accessibilityChecked: Bool
    var statusIdentifier: String
    var expectedMenuIdentifiers: [String]
    var observedStatusText: [String]
    var observedMenuIdentifiers: [String]
    var menuBarSurfaceVisible: Bool
    var fixtureModeUsed: Bool
    var rawClaudeCredentialsUsed: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private final class LaunchServicesOpenResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var application: NSRunningApplication?
    private var error: Error?
    private var isComplete = false

    func complete(application: NSRunningApplication?, error: Error?) {
        lock.lock()
        self.application = application
        self.error = error
        isComplete = true
        lock.unlock()
    }

    func completed() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isComplete
    }

    func snapshot() -> (application: NSRunningApplication?, error: Error?, isComplete: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (application, error, isComplete)
    }
}

private struct ScriptedPDTConnectorScenarioResult: Codable {
    var name: String
    var passed: Bool
    var detail: String
}

private struct PulseTargetEvidence: Codable {
    var accessibilityIdentifier: String
    var title: String
}

private func waitForAccessibilityElement(
    in root: AXUIElement,
    identifier: String,
    timeout: TimeInterval
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = findAccessibilityElement(in: root, identifier: identifier) {
            return element
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

private func waitForAccessibilityElement(
    in root: AXUIElement,
    matchingText expectedText: String,
    timeout: TimeInterval
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = findAccessibilityElement(in: root, matchingText: expectedText) {
            return element
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return findAccessibilityElement(in: root, matchingText: expectedText)
}

private func waitForAccessibilityIdentifiers(
    _ identifiers: Set<String>,
    in root: AXUIElement,
    timeout: TimeInterval
) -> AccessibilitySnapshot {
    let deadline = Date().addingTimeInterval(timeout)
    var latest = accessibilitySnapshot(in: root)
    while !identifiers.isSubset(of: latest.identifiers) && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
        latest = accessibilitySnapshot(in: root)
    }
    return latest
}

private func waitForStatusText(
    _ expected: String,
    in root: AXUIElement,
    statusIdentifier: String,
    timeout: TimeInterval
) -> Bool {
    func matchesExpectedStatus(_ text: String) -> Bool {
        text == expected ||
            text == "PDTBar \(expected)" ||
            text.hasPrefix("\(expected) ") ||
            text.hasPrefix("PDTBar \(expected) ")
    }

    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let status = findAccessibilityElement(in: root, identifier: statusIdentifier) {
            let texts = accessibilityTexts(in: status)
            if texts.contains(where: matchesExpectedStatus) {
                return true
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    if let status = findAccessibilityElement(in: root, identifier: statusIdentifier) {
        let texts = accessibilityTexts(in: status)
        return texts.contains(where: matchesExpectedStatus)
    }
    return false
}

private func pressMenuRow(
    statusElement: AXUIElement,
    appElement: AXUIElement,
    rowIdentifier: String,
    expectedMenuIdentifiers: Set<String>,
    timeout: TimeInterval
) -> String? {
    let openedMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        timeout: timeout
    )
    guard let row = waitForAccessibilityElement(
        in: appElement,
        identifier: rowIdentifier,
        timeout: min(timeout, 1.0)
    ) else {
        return nil
    }
    let result = AXUIElementPerformAction(row, kAXPressAction as CFString)
    if result == .success {
        return "\(openedMenu.successfulAttempt ?? "menu opened"); \(kAXPressAction)=\(result)"
    }
    if let center = accessibilityCenter(of: row) {
        click(point: center)
        return "\(openedMenu.successfulAttempt ?? "menu opened"); coordinateClick=\(format(point: center)); \(kAXPressAction)=\(result)"
    }
    return "\(openedMenu.successfulAttempt ?? "menu opened"); \(kAXPressAction)=\(result)"
}

private func openStatusMenu(
    _ statusElement: AXUIElement,
    appElement: AXUIElement,
    expectedMenuIdentifiers: Set<String>,
    timeout: TimeInterval
) -> OpenMenuResult {
    var attempts: [String] = []
    let messagingTimeout = Float(max(timeout, 0.1))
    _ = AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
    _ = AXUIElementSetMessagingTimeout(statusElement, messagingTimeout)
    let actions = accessibilityActionNames(of: statusElement)
    for action in [kAXPressAction as String, kAXShowMenuAction as String] {
        let result = AXUIElementPerformAction(statusElement, action as CFString)
        attempts.append("\(action)=\(result)")
        if result == .success || actions.contains(action) {
            let snapshot = waitForAccessibilityIdentifiers(
                expectedMenuIdentifiers,
                in: appElement,
                timeout: min(timeout, 1.5)
            )
            if expectedMenuIdentifiers.isSubset(of: snapshot.identifiers) {
                return OpenMenuResult(snapshot: snapshot, successfulAttempt: action, attempts: attempts)
            }
        }
    }

    if let center = accessibilityCenter(of: statusElement) {
        click(point: center)
        attempts.append("coordinateClick=\(format(point: center))")
        let snapshot = waitForAccessibilityIdentifiers(
            expectedMenuIdentifiers,
            in: appElement,
            timeout: timeout
        )
        if expectedMenuIdentifiers.isSubset(of: snapshot.identifiers) {
            return OpenMenuResult(snapshot: snapshot, successfulAttempt: "coordinate click", attempts: attempts)
        }
        return OpenMenuResult(snapshot: snapshot, successfulAttempt: nil, attempts: attempts)
    }

    attempts.append("coordinateClick=no AXPosition/AXSize")
    return OpenMenuResult(snapshot: nil, successfulAttempt: nil, attempts: attempts)
}

private func findAccessibilityElement(in root: AXUIElement, identifier: String) -> AXUIElement? {
    var stack = [root]
    var visited = 0
    while let element = stack.popLast(), visited < 500 {
        visited += 1
        if accessibilityString(element, "AXIdentifier") == identifier {
            return element
        }
        stack.append(contentsOf: accessibilityChildren(of: element))
    }
    return nil
}

private func findAccessibilityElement(in root: AXUIElement, matchingText expectedText: String) -> AXUIElement? {
    var stack = [root]
    var visited = 0
    while let element = stack.popLast(), visited < 800 {
        visited += 1
        let texts = accessibilityTexts(in: element)
        if texts.contains(expectedText) || texts.contains(where: { $0.contains(expectedText) }) {
            return element
        }
        stack.append(contentsOf: accessibilityChildren(of: element))
    }
    return nil
}

private func accessibilitySnapshot(in root: AXUIElement) -> AccessibilitySnapshot {
    var snapshot = AccessibilitySnapshot(identifiers: [], texts: [], framesByIdentifier: [:])
    var stack = [root]
    var visited = 0
    while let element = stack.popLast(), visited < 800 {
        visited += 1
        if let identifier = accessibilityString(element, "AXIdentifier"), !identifier.isEmpty {
            snapshot.identifiers.insert(identifier)
            if let frame = accessibilityFrame(of: element) {
                snapshot.framesByIdentifier[identifier] = AccessibilityFrame(rect: frame)
            }
        }
        for text in accessibilityTexts(in: element) {
            snapshot.texts.insert(text)
        }
        stack.append(contentsOf: accessibilityChildren(of: element))
    }
    return snapshot
}

private func captureNativeMenuScreenshot(
    name: String,
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>,
    artifacts: URL
) throws -> URL? {
    guard let menuBounds = menuFrameBounds(snapshot: snapshot, expectedMenuIdentifiers: expectedMenuIdentifiers)
        ?? statusMenuFallbackBounds(snapshot: snapshot)
    else {
        return nil
    }
    let bounds = menuBounds.insetBy(dx: 2, dy: 2).integral
    let screenshot = artifacts.appending(path: "\(name)-menu.png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    _ = try run(
        URL(fileURLWithPath: "/usr/sbin/screencapture"),
        arguments: [
            "-x",
            "-R\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))",
            screenshot.path,
        ],
        timeout: 10
    )
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func captureRealUserMenuScreenshot(
    name: String,
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    try captureMenuScreenshot(
        name: name,
        snapshot: snapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        artifacts: artifacts,
        peekaboo: peekaboo
    )
}

private func captureAllocationDetailScreenshot(
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    guard let peekaboo,
          let allocationRect = snapshot.framesByIdentifier["pdtbar.row.allocation.portfolio.details"]?.rect,
          !allocationRect.isNull,
          !allocationRect.isEmpty
    else {
        return nil
    }
    moveMouse(to: CGPoint(x: allocationRect.maxX - 24, y: allocationRect.midY))
    Thread.sleep(forTimeInterval: 0.6)

    let display = displayBounds(containing: allocationRect)
    let padded = CGRect(
        x: max(display.minX, allocationRect.minX - 520),
        y: max(display.minY, allocationRect.minY - 96),
        width: min(display.width, allocationRect.width + 600),
        height: min(display.height, 420)
    ).intersection(display).integral
    guard !padded.isNull, !padded.isEmpty else {
        return nil
    }

    let screenshot = artifacts.appending(path: "pdtbar-real-user-pulse-allocation-detail.png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    try captureAreaScreenshot(to: screenshot, bounds: padded, peekaboo: peekaboo)
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func capturePricesDetailScreenshot(
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    let stablePricesRowIdentifier = "pdtbar.row.freshness.summary"
    return try captureSubmenuScreenshot(
        rowIdentifier: stablePricesRowIdentifier,
        name: "pdtbar-real-user-pulse-prices-detail",
        snapshot: snapshot,
        artifacts: artifacts,
        peekaboo: peekaboo
    )
}

private func captureDataHealthDetailScreenshot(
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    try captureSubmenuScreenshot(
        rowIdentifier: "pdtbar.row.dataHealth",
        name: "pdtbar-real-user-pulse-data-health",
        snapshot: snapshot,
        artifacts: artifacts,
        peekaboo: peekaboo
    )
}

private func captureSubmenuScreenshot(
    rowIdentifier: String,
    name: String,
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    guard let peekaboo,
          let rowRect = snapshot.framesByIdentifier[rowIdentifier]?.rect,
          !rowRect.isNull,
          !rowRect.isEmpty
    else {
        return nil
    }
    moveMouse(to: CGPoint(x: rowRect.maxX - 24, y: rowRect.midY))
    Thread.sleep(forTimeInterval: 0.6)

    let display = displayBounds(containing: rowRect)
    let padded = CGRect(
        x: max(display.minX, rowRect.minX - 400),
        y: max(display.minY, rowRect.minY - 96),
        width: min(display.width, rowRect.width + 520),
        height: min(display.height, 360)
    ).intersection(display).integral
    guard !padded.isNull, !padded.isEmpty else {
        return nil
    }

    let screenshot = artifacts.appending(path: "\(name).png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    _ = try run(
        peekaboo,
        arguments: [
            "image",
            "--mode", "area",
            "--region", "\(Int(padded.minX)),\(Int(padded.minY)),\(Int(padded.width)),\(Int(padded.height))",
            "--path", screenshot.path,
            "--json",
            "--no-remote",
        ],
        timeout: 20
    )
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func captureElementScreenshot(
    name: String,
    element: AXUIElement,
    artifacts: URL,
    peekaboo: URL
) throws -> URL? {
    guard let elementRect = accessibilityFrame(of: element),
          !elementRect.isNull,
          !elementRect.isEmpty
    else {
        return nil
    }
    let display = displayBounds(containing: elementRect)
    let padded = CGRect(
        x: max(display.minX, elementRect.minX - 32),
        y: max(display.minY, elementRect.minY - 28),
        width: min(display.width, max(300, elementRect.width + 96)),
        height: min(display.height, max(96, elementRect.height + 64))
    ).intersection(display).integral
    guard !padded.isNull, !padded.isEmpty else {
        return nil
    }

    let screenshot = artifacts.appending(path: "\(name).png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    try captureAreaScreenshot(to: screenshot, bounds: padded, peekaboo: peekaboo)
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func captureAreaScreenshot(to screenshot: URL, bounds: CGRect, peekaboo: URL) throws {
    let region = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))"
    do {
        _ = try run(
            peekaboo,
            arguments: [
                "image",
                "--mode", "area",
                "--region", region,
                "--path", screenshot.path,
                "--json",
                "--no-remote",
            ],
            timeout: 20
        )
    } catch {
        _ = try run(
            URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: [
                "-x",
                "-R\(region)",
                screenshot.path,
            ],
            timeout: 10
        )
    }
}

private func captureAttentionExplanationScreenshot(
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    guard let peekaboo else {
        return nil
    }
    let attentionRect = snapshot.framesByIdentifier.keys.sorted()
        .first(where: { $0.hasSuffix(".glance") && !$0.contains(".quiet") })
        .flatMap { snapshot.framesByIdentifier[$0]?.rect }
        .flatMap(validRect)
    let menuRect = statusMenuFallbackBounds(snapshot: snapshot)
    let hoverRect = attentionRect ?? menuRect
    guard let hoverRect else {
        return nil
    }
    let hoverY = attentionRect?.midY ?? (hoverRect.minY + 92)
    moveMouse(to: CGPoint(x: hoverRect.maxX - 24, y: hoverY))
    Thread.sleep(forTimeInterval: 0.6)

    let display = displayBounds(containing: hoverRect)
    let minX = attentionRect.map { max(display.minX, $0.minX - 395) }
        ?? max(display.minX, hoverRect.maxX - 885)
    let width = attentionRect.map { min(display.maxX - minX, $0.width + 365) }
        ?? min(display.maxX - minX, 885)
    let padded = CGRect(
        x: minX,
        y: max(display.minY, hoverRect.minY - 96),
        width: width,
        height: min(display.height, 340)
    ).intersection(display).integral
    guard !padded.isNull, !padded.isEmpty else {
        return nil
    }

    let screenshot = artifacts.appending(path: "pdtbar-real-user-pulse-attention-explanation.png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    _ = try run(
        peekaboo,
        arguments: [
            "image",
            "--mode", "area",
            "--region", "\(Int(padded.minX)),\(Int(padded.minY)),\(Int(padded.width)),\(Int(padded.height))",
            "--path", screenshot.path,
            "--json",
            "--no-remote",
        ],
        timeout: 20
    )
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func captureMenuScreenshot(
    name: String,
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    guard let peekaboo else {
        return nil
    }
    let rawScreenshot = artifacts.appending(path: "\(name)-screen.png")
    let screenshot = artifacts.appending(path: "\(name)-menu.png")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    guard let menuBounds = menuFrameBounds(snapshot: snapshot, expectedMenuIdentifiers: expectedMenuIdentifiers)
        ?? statusMenuFallbackBounds(snapshot: snapshot)
    else {
        return nil
    }
    let captureBounds = screenshotCaptureBounds(containing: menuBounds)
    try captureAreaScreenshot(to: rawScreenshot, bounds: captureBounds, peekaboo: peekaboo)
    defer {
        try? FileManager.default.removeItem(at: rawScreenshot)
    }
    try cropMenuScreenshot(
        rawScreenshot,
        to: screenshot,
        snapshot: snapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        displayBounds: captureBounds
    )
    guard imageHasVisiblePixels(screenshot) else {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
    return screenshot
}

private func captureFullScreenScreenshot(name: String, artifacts: URL, peekaboo: URL?) -> URL? {
    let screenshot = artifacts.appending(path: "\(name).png")
    do {
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        if let peekaboo {
            do {
                _ = try run(
                    peekaboo,
                    arguments: [
                        "image",
                        "--mode", "screen",
                        "--path", screenshot.path,
                        "--json",
                        "--no-remote",
                    ],
                    timeout: 20
                )
            } catch {
                _ = try run(
                    URL(fileURLWithPath: "/usr/sbin/screencapture"),
                    arguments: ["-x", screenshot.path],
                    timeout: 10
                )
            }
        } else {
            _ = try run(
                URL(fileURLWithPath: "/usr/sbin/screencapture"),
                arguments: ["-x", screenshot.path],
                timeout: 10
            )
        }
        guard imageHasVisiblePixels(screenshot) else {
            try? FileManager.default.removeItem(at: screenshot)
            return nil
        }
        return screenshot
    } catch {
        try? FileManager.default.removeItem(at: screenshot)
        return nil
    }
}

private func movePointerToNeutralMenuArea(in snapshot: AccessibilitySnapshot) {
    let neutralIdentifiers = [
        "pdtbar.section.income",
        "pdtbar.section.pulse",
        "pdtbar.section.allocation",
    ]
    guard let rect = neutralIdentifiers.compactMap({ snapshot.framesByIdentifier[$0]?.rect }).first else {
        return
    }
    moveMouse(to: CGPoint(x: rect.minX + 24, y: rect.midY))
    Thread.sleep(forTimeInterval: 0.2)
}

private func peekabooScreenshotTool(_ peekaboo: URL) -> URL? {
    guard FileManager.default.isExecutableFile(atPath: peekaboo.path) else {
        return nil
    }
    guard let permissionJSON = try? run(peekaboo, arguments: ["permissions", "--json"], timeout: 15).stdout else {
        return nil
    }
    guard requiredMissingPermissions(from: permissionJSON)?.isEmpty == true else {
        return nil
    }
    return peekaboo
}

private func cropMenuScreenshot(
    _ source: URL,
    to destination: URL,
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>,
    displayBounds: CGRect
) throws {
    let dimensions = try imageDimensions(of: source)
    let scaleX = Double(dimensions.width) / max(Double(displayBounds.width), 1)
    let scaleY = Double(dimensions.height) / max(Double(displayBounds.height), 1)
    let fallback = CGRect(
        x: max(0, Double(dimensions.width - min(dimensions.width, 1700) - 20)),
        y: 20,
        width: Double(min(dimensions.width, 1700)),
        height: Double(min(dimensions.height, 760))
    )
    let sourceRect: CGRect
    if let bounds = menuFrameBounds(snapshot: snapshot, expectedMenuIdentifiers: expectedMenuIdentifiers) {
        let minX = bounds.minX
        let minY = bounds.minY - 8
        let maxX = bounds.maxX - 8
        let maxY = bounds.maxY + 48
        sourceRect = CGRect(
            x: Double(minX - displayBounds.minX) * scaleX,
            y: Double(minY - displayBounds.minY) * scaleY,
            width: Double(maxX - minX) * scaleX,
            height: Double(maxY - minY) * scaleY
        )
    } else if let bounds = statusMenuFallbackBounds(snapshot: snapshot) {
        sourceRect = CGRect(
            x: Double(bounds.minX - displayBounds.minX) * scaleX,
            y: Double(bounds.minY - displayBounds.minY) * scaleY,
            width: Double(bounds.width) * scaleX,
            height: Double(bounds.height) * scaleY
        )
    } else {
        sourceRect = fallback
    }
    let imageRect = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
    let candidate = sourceRect.intersection(imageRect)
    let clamped = candidate.isNull || candidate.isEmpty ? fallback.intersection(imageRect) : candidate
    guard !clamped.isNull, !clamped.isEmpty else {
        throw CommandError.commandFailed("sips", "", "empty screenshot crop")
    }
    let width = max(1, Int(clamped.width.rounded(.up)))
    let height = max(1, Int(clamped.height.rounded(.up)))
    let offsetX = max(0, Int(clamped.minX.rounded(.down)))
    let offsetY = max(0, Int(clamped.minY.rounded(.down)))
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
    _ = try run(
        URL(fileURLWithPath: "/usr/bin/sips"),
        arguments: [
            "-c", "\(height)", "\(width)",
            "--cropOffset", "\(offsetY)", "\(offsetX)",
            destination.path,
        ],
        timeout: 20
    )
}

private func menuFrameBounds(
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>
) -> CGRect? {
    expectedMenuIdentifiers
        .compactMap { snapshot.framesByIdentifier[$0]?.rect }
        .filter { rect in
            guard !rect.isNull, !rect.isEmpty, rect.width > 0, rect.height > 0 else {
                return false
            }
            return rect.maxY < displayBounds(containing: rect).maxY - 8
        }
        .reduce(nil as CGRect?) { partial, rect in partial?.union(rect) ?? rect }
}

private func statusMenuFallbackBounds(snapshot: AccessibilitySnapshot) -> CGRect? {
    guard let status = snapshot.framesByIdentifier["pdtbar.status"].flatMap({ validRect($0.rect) }) else {
        return nil
    }
    let display = displayBounds(containing: status)
    let width = min(display.width, 560)
    let x = display.maxX - width
    let y = min(max(display.minY, status.maxY + 2), display.maxY)
    let height = min(display.maxY - y, 88)
    return CGRect(x: x, y: y, width: width, height: height).integral
}

private func validRect(_ rect: CGRect) -> CGRect? {
    guard !rect.isNull, !rect.isEmpty, rect.width > 0, rect.height > 0 else {
        return nil
    }
    return rect
}

private func displayBounds(containing rect: CGRect?) -> CGRect {
    guard let rect, !rect.isNull, !rect.isEmpty else {
        return CGDisplayBounds(CGMainDisplayID())
    }
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
        return CGDisplayBounds(CGMainDisplayID())
    }
    var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
    guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
        return CGDisplayBounds(CGMainDisplayID())
    }
    return displays
        .prefix(Int(displayCount))
        .map { CGDisplayBounds($0) }
        .max { left, right in
            left.intersection(rect).area < right.intersection(rect).area
        } ?? CGDisplayBounds(CGMainDisplayID())
}

private func screenshotCaptureBounds(containing rect: CGRect?) -> CGRect {
    let display = displayBounds(containing: rect)
    guard let rect, !rect.isNull, !rect.isEmpty else {
        let width = min(display.width, 1700)
        let height = min(display.height, 760)
        return CGRect(
            x: display.maxX - width,
            y: display.minY,
            width: width,
            height: height
        ).integral
    }
    let padded = rect.insetBy(dx: -40, dy: -40)
    let clamped = padded.intersection(display)
    guard !clamped.isNull, !clamped.isEmpty else {
        return rect.integral
    }
    return clamped.integral
}

private func imageDimensions(of image: URL) throws -> (width: Int, height: Int) {
    let output = try run(
        URL(fileURLWithPath: "/usr/bin/sips"),
        arguments: [
            "-g", "pixelWidth",
            "-g", "pixelHeight",
            image.path,
        ],
        timeout: 20
    ).stdout
    let text = String(data: output, encoding: .utf8) ?? ""
    let width = text.dimensionValue(for: "pixelWidth")
    let height = text.dimensionValue(for: "pixelHeight")
    guard let width, let height else {
        throw CommandError.commandFailed("sips", text, "missing image dimensions")
    }
    return (width, height)
}

private func imageHasVisiblePixels(_ image: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return false
    }
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else {
        return false
    }
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sampleStride = max(bytesPerPixel, buffer.count / 256 / bytesPerPixel * bytesPerPixel)
        var minLuma = Double.greatestFiniteMagnitude
        var maxLuma = 0.0
        var visibleSamples = 0
        var index = 0
        while index + 3 < buffer.count {
            let red = buffer[index]
            let green = buffer[index + 1]
            let blue = buffer[index + 2]
            let alpha = buffer[index + 3]
            if alpha > 8 {
                let luma = 0.2126 * Double(red)
                    + 0.7152 * Double(green)
                    + 0.0722 * Double(blue)
                minLuma = min(minLuma, luma)
                maxLuma = max(maxLuma, luma)
                if luma > 24 {
                    visibleSamples += 1
                }
            }
            index += sampleStride
        }
        return visibleSamples > 2 && maxLuma > minLuma + 16
    }
}

private func accessibilityTexts(in element: AXUIElement) -> Set<String> {
    let attributes = ["AXTitle", "AXDescription", "AXHelp", "AXValue"]
    return Set(attributes.compactMap { accessibilityString(element, $0) }.filter { !$0.isEmpty })
}

private func accessibilityString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

private func accessibilityActionNames(of element: AXUIElement) -> Set<String> {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let actions = names as? [String]
    else {
        return []
    }
    return Set(actions)
}

private func accessibilityCenter(of element: AXUIElement) -> CGPoint? {
    guard let position = accessibilityCGPoint(element, "AXPosition"),
          let size = accessibilityCGSize(element, "AXSize")
    else {
        return nil
    }
    return CGPoint(x: position.x + (size.width / 2), y: position.y + (size.height / 2))
}

private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
    guard let position = accessibilityCGPoint(element, "AXPosition"),
          let size = accessibilityCGSize(element, "AXSize")
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

private func accessibilityCGPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let axValue = value,
          CFGetTypeID(axValue) == AXValueGetTypeID(),
          AXValueGetType(axValue as! AXValue) == .cgPoint
    else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func accessibilityCGSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let axValue = value,
          CFGetTypeID(axValue) == AXValueGetTypeID(),
          AXValueGetType(axValue as! AXValue) == .cgSize
    else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return size
}

private func click(point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    up?.post(tap: .cghidEventTap)
}

private func pressEscape() {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
    down?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    up?.post(tap: .cghidEventTap)
}

private func moveMouse(to point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
}

private func format(point: CGPoint) -> String {
    let x = String(format: "%.1f", point.x)
    let y = String(format: "%.1f", point.y)
    return "\(x),\(y)"
}

private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
    var elements: [AXUIElement] = []
    for attribute in ["AXChildren", "AXExtrasMenuBar"] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value
        else {
            continue
        }
        if let children = axValue as? [AXUIElement] {
            elements.append(contentsOf: children)
        } else if CFGetTypeID(axValue) == AXUIElementGetTypeID() {
            elements.append(axValue as! AXUIElement)
        }
    }
    return elements
}

private func writeAccessibilityEvidence(
    snapshot: AccessibilitySnapshot,
    expected: [PulseTarget],
    statusIdentifier: String,
    statusText: Set<String>,
    output: URL
) throws {
    let evidence = AccessibilityEvidence(
        statusIdentifier: statusIdentifier,
        statusText: statusText.sorted(),
        displayMode: CGDisplayCopyDisplayMode(CGMainDisplayID()).map {
            DisplayModeEvidence(
                logicalWidth: $0.width,
                logicalHeight: $0.height,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight,
                refreshRate: $0.refreshRate
            )
        },
        expected: expected.map {
            PulseTargetEvidence(
                accessibilityIdentifier: $0.accessibilityIdentifier,
                title: $0.title
            )
        },
        observedIdentifiers: snapshot.identifiers.sorted(),
        observedFramesByIdentifier: snapshot.framesByIdentifier,
        observedTexts: snapshot.texts.sorted()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(evidence).write(to: output)
}

private func artifactPath(_ url: URL) -> String {
    let root = packageRoot.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path == root {
        return "."
    }
    if path.hasPrefix("\(root)/") {
        return String(path.dropFirst(root.count + 1))
    }
    return path
}

private func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CommandError.runtime(message)
    }
    return value
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var fixedSnapshot: PortfolioSnapshot

    init(snapshot: PortfolioSnapshot) {
        fixedSnapshot = snapshot
    }

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        fixedSnapshot
    }
}

private func modificationDate(of url: URL) -> Date? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.modificationDate] as? Date
}

private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return FileManager.default.fileExists(atPath: url.path)
}

private func waitForFileContent(_ url: URL, contains needle: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           text.contains(needle)
        {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return (try? String(contentsOf: url, encoding: .utf8))?.contains(needle) == true
}

private func waitForSnapshotAsOf(_ url: URL, asOf: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if snapshotAsOf(url) == asOf {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return snapshotAsOf(url) == asOf
}

private func snapshotAsOf(_ url: URL) -> String? {
    guard FileManager.default.fileExists(atPath: url.path),
          let snapshot = try? JSONDecoder().decode(PortfolioSnapshot.self, from: Data(contentsOf: url))
    else {
        return nil
    }
    return snapshot.asOf
}

/// The `full` API fixture in background-refresh request order. Symbol-quote
/// lookups belong to the first fetch only.
private func scriptedAPIBackgroundRefreshResponses() throws -> [ScriptedPDTAPIConfiguration.Response] {
    let directory = packageRoot.appending(path: "docs/pdt/fixtures/api/full")
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("symbol-quotes") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { ScriptedPDTAPIConfiguration.Response(body: String(decoding: try Data(contentsOf: $0), as: UTF8.self)) }
}

private func terminate(_ process: Process) {
    if process.isRunning {
        process.terminate()
    }
    process.waitUntilExit()
}

private func fixtureStatusTitle(for fixture: URL) throws -> String {
    let model = PressureEngine.buildModel(from: try PDTFixtureDataSource(fixture: fixture).snapshot())
    return MenuDescriptorRenderer.render(model: model).statusTitle
}

private struct SmokeOptions {
    var app: URL?
    var claude: URL?
    var mcporter: URL?
    var fixture: URL?
    var peekaboo: URL?
    var artifacts: URL?
    var output: URL?
    var snapshotDirectory: URL?
    var appSupportDirectory: URL?
    var server: String?
    var model: String?
    var timeout: TimeInterval = 2.0
    var timeoutWasProvided = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--app" where index + 1 < arguments.count:
                app = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--claude" where index + 1 < arguments.count:
                claude = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--mcporter" where index + 1 < arguments.count:
                mcporter = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--fixture" where index + 1 < arguments.count:
                fixture = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--peekaboo" where index + 1 < arguments.count:
                peekaboo = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--artifacts" where index + 1 < arguments.count:
                artifacts = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--output" where index + 1 < arguments.count:
                output = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--snapshot-dir" where index + 1 < arguments.count:
                snapshotDirectory = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--app-support-dir" where index + 1 < arguments.count:
                appSupportDirectory = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--server" where index + 1 < arguments.count:
                server = arguments[index + 1]
                index += 2
            case "--model" where index + 1 < arguments.count:
                model = arguments[index + 1]
                index += 2
            case "--timeout" where index + 1 < arguments.count:
                timeout = TimeInterval(arguments[index + 1]) ?? 2.0
                timeoutWasProvided = true
                index += 2
            default:
                throw CommandError.usage
            }
        }
    }

    func resolvedSnapshotDirectory() throws -> URL {
        if let snapshotDirectory {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            return snapshotDirectory
        }
        return try temporarySnapshotDirectory(prefix: "snapshots")
    }

    func resolvedAppExecutable(defaultExecutable: URL) -> URL {
        let candidate = app ?? defaultExecutable
        return appBundleExecutable(in: candidate) ?? candidate
    }

    func temporarySnapshotDirectory(prefix: String) throws -> URL {
        let directory = packageRoot
            .appending(path: ".build/pdtbar-smoke-artifacts/\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func isolatedSnapshotDirectory(prefix: String) throws -> URL {
        let base = snapshotDirectory ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let directory = base.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func isolatedAppSupportDirectory(prefix: String) throws -> URL {
        let base = appSupportDirectory ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let directory = base.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private func appBundleExecutable(in candidate: URL) -> URL? {
    guard candidate.pathExtension == "app" else {
        return nil
    }

    let infoPlist = candidate.appending(path: "Contents/Info.plist")
    let info = (try? Data(contentsOf: infoPlist))
        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let bundleExecutable = (info?["CFBundleExecutable"] as? String)
        ?? candidate.deletingPathExtension().lastPathComponent
    return candidate
        .appending(path: "Contents/MacOS")
        .appending(path: bundleExecutable)
}

private func bundleInfoPlist(_ appBundle: URL) throws -> [String: Any] {
    let infoPlist = appBundle.appending(path: "Contents/Info.plist")
    guard let data = try? Data(contentsOf: infoPlist),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else {
        throw CommandError.runtime("Info.plist missing or unreadable at \(artifactPath(infoPlist))")
    }
    return info
}

private func verifyCodeSignature(_ appBundle: URL, timeout: TimeInterval) throws -> String {
    _ = try run(
        URL(fileURLWithPath: "/usr/bin/codesign"),
        arguments: ["--verify", "--deep", "--strict", "--verbose=2", appBundle.path],
        timeout: timeout
    )
    let details = try run(
        URL(fileURLWithPath: "/usr/bin/codesign"),
        arguments: ["-dv", appBundle.path],
        timeout: timeout
    )
    let text = String(data: details.stderr, encoding: .utf8) ?? ""
    return text
        .split(separator: "\n")
        .first { $0.hasPrefix("Signature=") }
        .map(String.init) ?? "Signature=unknown"
}

private func launchAppBundleWithLaunchServices(
    _ appBundle: URL,
    arguments: [String] = [],
    environment: [String: String],
    timeout: TimeInterval
) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.allowsRunningApplicationSubstitution = false
    configuration.createsNewApplicationInstance = true
    configuration.arguments = arguments
    configuration.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let result = LaunchServicesOpenResultBox()
    NSWorkspace.shared.openApplication(at: appBundle, configuration: configuration) { application, error in
        result.complete(application: application, error: error)
    }

    let deadline = Date().addingTimeInterval(timeout)
    while !result.completed() && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    let openResult = result.snapshot()
    guard openResult.isComplete else {
        throw CommandError.timedOut("LaunchServices open \(appBundle.lastPathComponent)")
    }
    if let openError = openResult.error {
        throw CommandError.runtime("LaunchServices failed to open \(appBundle.lastPathComponent): \(openError)")
    }
    return try require(openResult.application, "LaunchServices opened \(appBundle.lastPathComponent) without a running application")
}

private struct CommandResult {
    var stdout: Data
    var stderr: Data
}

private func scriptedPDTConnectorScenarioResults(
    responses: [String: Data]
) throws -> [ScriptedPDTConnectorScenarioResult] {
    var results: [ScriptedPDTConnectorScenarioResult] = []

    let missingToolConnector = ScriptedPDTMCPConnector(
        availableTools: Set(PDTReadTools.requiredV1.filter { $0 != "pdt-list-dividends" }),
        responses: responses
    )
    do {
        _ = try PDTMCPConnectorDataSource(connector: missingToolConnector).snapshot(asOf: "2026-03-29")
        results.append(.init(name: "missing-tool", passed: false, detail: "snapshot unexpectedly succeeded"))
    } catch PDTMCPConnectorError.missingRequiredReadTools(let missing) {
        results.append(.init(
            name: "missing-tool",
            passed: missing == ["pdt-list-dividends"] && missingToolConnector.calls.isEmpty,
            detail: "missing=\(missing.joined(separator: ",")); calls=\(missingToolConnector.calls.count)"
        ))
    }

    for (name, failure) in [
        ("auth-setup-error", PDTMCPConnectorError.setupUnavailable("Claude needs PDT setup")),
        ("transient-failure", PDTMCPConnectorError.transientFailure("Claude call timed out")),
    ] {
        do {
            _ = try PDTMCPConnectorDataSource(
                connector: ScriptedPDTMCPConnector(responses: responses, failure: failure)
            ).snapshot(asOf: "2026-03-29")
            results.append(.init(name: name, passed: false, detail: "snapshot unexpectedly succeeded"))
        } catch let error as PDTMCPConnectorError {
            results.append(.init(name: name, passed: error == failure, detail: error.description))
        }
    }

    var malformedResponses = responses
    malformedResponses["pdt-get-portfolio-holdings"] = Data("{".utf8)
    do {
        _ = try PDTMCPConnectorDataSource(
            connector: ScriptedPDTMCPConnector(responses: malformedResponses)
        ).snapshot(asOf: "2026-03-29")
        results.append(.init(name: "malformed-payload", passed: false, detail: "snapshot unexpectedly succeeded"))
    } catch PDTLiveDataSourceError.malformedToolResult(let tool) {
        results.append(.init(
            name: "malformed-payload",
            passed: tool == "pdt-get-portfolio-holdings",
            detail: tool
        ))
    }

    var degradedResponses = responses
    degradedResponses.removeValue(
        forKey: "pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9101"
    )
    let degradedStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-smoke-progressive-detail")
    defer {
        try? FileManager.default.removeItem(at: degradedStore.directory)
    }
    do {
        let degraded = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: degradedResponses),
            snapshotStore: degradedStore,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()
        let partialSnapshot = try degradedStore.loadPriorSnapshot()
        let diagnostic = try degradedStore.loadLastDetailRefreshDiagnostic()
        let retried = try PDTBackgroundDetailRefresh(
            connector: ScriptedPDTMCPConnector(responses: responses),
            snapshotStore: degradedStore,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
        ).refresh()
        let diagnosticAfterRetry = try degradedStore.loadLastDetailRefreshDiagnostic()
        results.append(.init(
            name: "progressive-detail-degraded-retry",
            passed: degraded.outcome == .degraded
                && partialSnapshot?.sectors.isEmpty == false
                && partialSnapshot?.incomeEvents.isEmpty == false
                && diagnostic?.toolName == "pdt-list-symbol-prices"
                && diagnostic?.argumentShape == ["date_from", "date_to", "symbol_quote_id"]
                && retried.outcome == .completed
                && retried.model.facetSnapshots.bigMovers.priceSeriesCount == 2
                && diagnosticAfterRetry == nil,
            detail: "partial=\(degraded.outcome.rawValue); retry=\(retried.outcome.rawValue); diagnostic=\(diagnostic?.category.rawValue ?? "none")"
        ))
    } catch {
        results.append(.init(
            name: "progressive-detail-degraded-retry",
            passed: false,
            detail: "progressive detail scenario failed"
        ))
    }

    return results
}

private func scriptedPDTConnectorResponses() throws -> [String: Data] {
    [
        "pdt-get-portfolio-holdings": try mcpContent("""
        {
          "holdings": [
            {
              "symbolName": "Scripted Adapter Co",
              "symbolQuoteId": 9101,
              "currentPriceDate": "2026-03-29T22:00:00+00:00",
              "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
              "portfolioWeight": 0.25,
              "closedAt": null
            }
          ]
        }
        """),
        "pdt-get-portfolio-distributions": try mcpResult("""
        {
          "sectors": [
            { "categoryName": "Technology", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
          ],
          "assetTypes": [
            { "categoryName": "Stock", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
          ]
        }
        """),
        "pdt-list-x-ray-holdings?limit=500&offset=0": try mcpResult("""
        {
          "items": [
            { "weight": 25.0 },
            { "weight": 0.5 }
          ],
          "hasMore": false
        }
        """),
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28&page=1&per_page=100": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": 5101, "symbolName": "Scripted Adapter Co" }
          ],
          "meta": { "last_page": 1 }
        }
        """),
        "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=100": try mcpResult("""
        {
          "data": [
            { "date": "2026-03-28T08:13:00+00:00", "amount": { "value": "8.00", "currency": "EUR" }, "symbolQuoteId": 9101 }
          ],
          "meta": { "last_page": 1 }
        }
        """),
        "pdt-get-symbol-quote?id=9101": try mcpContent("""
        { "id": 9101, "code": "SPDT", "symbolId": 5101 }
        """),
        "pdt-get-symbol?id=5101": try mcpContent("""
        { "id": 5101, "name": "Scripted Adapter Co", "isin": "NL0010273215" }
        """),
        "pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9101": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-27", "closeAdjusted": "19.00", "symbolQuoteId": 9101 },
            { "date": "2026-03-29", "closeAdjusted": "20.00", "symbolQuoteId": 9101 }
          ]
        }
        """),
    ]
}

private func scriptedQuietPDTConnectorResponses() throws -> [String: Data] {
    [
        "pdt-get-portfolio-holdings": try mcpContent("""
        {
          "holdings": [
            {
              "symbolName": "Scripted Quiet Co",
              "symbolQuoteId": 9102,
              "currentPriceDate": "2026-03-29T22:00:00+00:00",
              "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
              "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
              "portfolioWeight": 0.10,
              "closedAt": null
            }
          ]
        }
        """),
        "pdt-get-portfolio-distributions": try mcpResult("""
        {
          "sectors": [
            { "categoryName": "Technology", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
          ],
          "assetTypes": [
            { "categoryName": "Stock", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
          ]
        }
        """),
        "pdt-list-x-ray-holdings?limit=500&offset=0": try mcpResult("""
        {
          "items": [
            { "weight": 10.0 },
            { "weight": 0.5 }
          ],
          "hasMore": false
        }
        """),
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28&page=1&per_page=100": try mcpContent("""
        { "data": [], "meta": { "last_page": 1 } }
        """),
        "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=100": try mcpResult("""
        {
          "data": [],
          "meta": { "last_page": 1 }
        }
        """),
        "pdt-get-symbol-quote?id=9102": try mcpContent("""
        { "id": 9102, "symbolId": 5102 }
        """),
        "pdt-get-symbol?id=5102": try mcpContent("""
        { "id": 5102, "name": "Scripted Quiet Co", "isin": "BE0000000001" }
        """),
        "pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9102": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-27", "closeAdjusted": "20.00", "symbolQuoteId": 9102 },
            { "date": "2026-03-29", "closeAdjusted": "20.00", "symbolQuoteId": 9102 }
          ]
        }
        """),
    ]
}

private func mcpContent(_ json: String) throws -> Data {
    try mcpContent(json, isError: false)
}

private func mcpContent(_ text: String, isError: Bool) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "isError": isError,
            "content": [
                [
                    "type": "text",
                    "text": text,
                ],
            ],
        ],
        options: [.sortedKeys]
    )
}

private func mcpResult(_ json: String) throws -> Data {
    let payload = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONSerialization.data(
        withJSONObject: ["result": payload],
        options: [.sortedKeys]
    )
}

private struct PDTLiveMcporterClient: PDTLiveToolClient {
    var mcporter: McporterTool
    var server: String
    var timeout: TimeInterval

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        let selector = "\(server).\(name)"
        let toolArguments = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return try run(
            mcporter.executable,
            arguments: [
                "call",
                "--no-oauth",
                "--timeout", String(Int(timeout * 1000)),
                selector,
            ] + toolArguments,
            timeout: timeout + 1.0
        ).stdout
    }
}

private struct McporterTool {
    var executable: URL
    var sourceDescription: String
}

private enum McporterSetupError: Error {
    case defaultMissing(URL)
    case defaultPackageMissing(URL)
    case defaultPackageUnreadable(URL)
    case defaultPackageMalformed(URL)
    case defaultVersionMismatch(expected: String, actual: String, packageJSON: URL)
    case explicitPathMissing(URL)

    var status: String {
        switch self {
        case .defaultMissing,
             .defaultPackageMissing,
             .defaultPackageUnreadable,
             .defaultPackageMalformed,
             .defaultVersionMismatch,
             .explicitPathMissing:
            SmokeStatus.failed
        }
    }

    var detail: String {
        switch self {
        case .defaultMissing(let expected):
            "pinned mcporter is not installed at \(artifactPath(expected)); run npm ci, then rerun live-pdt or pass --mcporter <trusted-local-path>"
        case .defaultPackageMissing(let packageJSON):
            "pinned mcporter executable exists, but \(artifactPath(packageJSON)) is missing; run npm ci to restore mcporter@\(pinnedMcporterVersion)"
        case .defaultPackageUnreadable(let packageJSON):
            "pinned mcporter metadata at \(artifactPath(packageJSON)) is unreadable; run npm ci to restore mcporter@\(pinnedMcporterVersion)"
        case .defaultPackageMalformed(let packageJSON):
            "pinned mcporter metadata at \(artifactPath(packageJSON)) is malformed or missing a version; run npm ci to restore mcporter@\(pinnedMcporterVersion)"
        case .defaultVersionMismatch(let expected, let actual, let packageJSON):
            "pinned mcporter version mismatch in \(artifactPath(packageJSON)); expected \(expected), found \(actual); run npm ci"
        case .explicitPathMissing(let executable):
            "trusted mcporter path is not executable at \(artifactPath(executable)); pass --mcporter <trusted-local-path> or run npm ci for the pinned repo-local tool"
        }
    }

    var artifacts: [String] {
        switch self {
        case .defaultMissing(let expected), .explicitPathMissing(let expected):
            [artifactPath(expected)]
        case .defaultPackageMissing(let packageJSON),
             .defaultPackageUnreadable(let packageJSON),
             .defaultPackageMalformed(let packageJSON),
             .defaultVersionMismatch(_, _, let packageJSON):
            [artifactPath(packageJSON)]
        }
    }
}

private func resolveMcporterTool(options: SmokeOptions, environment: [String: String]) throws -> McporterTool {
    let environmentMcporterPath = environment["PDTBAR_MCPORTER_BIN"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let explicitEnvironmentMcporter = environmentMcporterPath
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    if let explicit = options.mcporter ?? explicitEnvironmentMcporter {
        guard FileManager.default.isExecutableFile(atPath: explicit.path) else {
            throw McporterSetupError.explicitPathMissing(explicit)
        }
        return McporterTool(
            executable: explicit,
            sourceDescription: "trusted local path \(artifactPath(explicit))"
        )
    }

    let executable = packageRoot.appending(path: "node_modules/.bin/mcporter")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        throw McporterSetupError.defaultMissing(executable)
    }
    let packageJSON = packageRoot.appending(path: "node_modules/mcporter/package.json")
    guard FileManager.default.fileExists(atPath: packageJSON.path) else {
        throw McporterSetupError.defaultPackageMissing(packageJSON)
    }
    guard let data = try? Data(contentsOf: packageJSON) else {
        throw McporterSetupError.defaultPackageUnreadable(packageJSON)
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = object["version"] as? String
    else {
        throw McporterSetupError.defaultPackageMalformed(packageJSON)
    }
    guard version == pinnedMcporterVersion else {
        throw McporterSetupError.defaultVersionMismatch(
            expected: pinnedMcporterVersion,
            actual: version,
            packageJSON: packageJSON
        )
    }
    return McporterTool(
        executable: executable,
        sourceDescription: "package-lock mcporter@\(pinnedMcporterVersion) \(artifactPath(executable))"
    )
}

private func discoverLivePDTServer(options: SmokeOptions) throws -> String? {
    if let server = options.server ?? ProcessInfo.processInfo.environment["PDTBAR_LIVE_PDT_SERVER"],
       !server.isEmpty
    {
        return server
    }
    return nil
}

private func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
    let process = Process()
    let fileManager = FileManager.default
    let stdoutURL = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-smoke-\(UUID().uuidString).stdout")
    let stderrURL = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-smoke-\(UUID().uuidString).stderr")
    guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
          fileManager.createFile(atPath: stderrURL.path, contents: nil) else {
        throw CommandError.commandFailed(executable.lastPathComponent, "", "failed to create temporary output files")
    }
    var openHandles: [FileHandle] = []
    defer {
        for handle in openHandles {
            try? handle.close()
        }
        try? fileManager.removeItem(at: stdoutURL)
        try? fileManager.removeItem(at: stderrURL)
    }
    let stdout = try FileHandle(forWritingTo: stdoutURL)
    openHandles.append(stdout)
    let stderr = try FileHandle(forWritingTo: stderrURL)
    openHandles.append(stderr)
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        throw CommandError.timedOut(executable.lastPathComponent)
    }
    try? stdout.close()
    try? stderr.close()
    openHandles.removeAll()
    let out = try Data(contentsOf: stdoutURL)
    let err = try Data(contentsOf: stderrURL)
    guard process.terminationStatus == 0 else {
        throw CommandError.commandFailed(
            executable.lastPathComponent,
            String(data: out, encoding: .utf8) ?? "",
            String(data: err, encoding: .utf8) ?? ""
        )
    }
    return CommandResult(stdout: out, stderr: err)
}

private func requiredMissingPermissions(from data: Data) -> [String]? {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
        return nil
    }
    return permissionDictionaries(in: object).compactMap { permission in
        guard permission["isRequired"] as? Bool == true,
              permission["isGranted"] as? Bool == false
        else { return nil }
        return permission["name"] as? String
    }
}

private func permissionDictionaries(in object: Any) -> [[String: Any]] {
    if let array = object as? [Any] {
        return array.flatMap(permissionDictionaries)
    }
    if let dictionary = object as? [String: Any] {
        let current = dictionary.keys.contains("isRequired") ? [dictionary] : []
        return current + dictionary.values.flatMap(permissionDictionaries)
    }
    return []
}

private func toolNames(in object: Any) -> Set<String> {
    var names = Set<String>()
    var stack = [object]
    while let item = stack.popLast() {
        if let array = item as? [Any] {
            stack.append(contentsOf: array)
            continue
        }
        if let dictionary = item as? [String: Any] {
            stack.append(contentsOf: dictionary.values)
            if let name = dictionary["name"] as? String {
                names.insert(name)
                if let selectorToolName = name.split(separator: ".").last {
                    names.insert(String(selectorToolName))
                }
            }
            continue
        }
    }
    return names
}

private func manualClaudePDTPrompt(resolvedTools: [String]) -> String {
    let tools = zip(PDTReadTools.requiredV1, resolvedTools).map { readTool, resolvedTool in
        "\(readTool): \(resolvedTool)"
    }.joined(separator: "\n- ")
    return """
    PDTBar manual smoke. Use the Claude CLI PDT MCP setup for read-only proof.

    Rules:
    - Call each resolved PDT MCP tool listed below exactly once.
    - Use normal Claude tool access only. Do not use bare mode.
    - Call only these resolved read-only PDT tools:
    - \(tools)
    - Do not call any write/mutate tool.
    - Do not include holdings, values, account identifiers, payload fields, endpoints, credentials, or raw tool output in your answer.
    - For list tools, use the smallest safe read-only request you can. For quote/price tools, derive one selector from holdings if needed, but do not print it if it contains private data.

    Return exactly one minified JSON object, no Markdown:
    {"status":"redacted-ok","statusText":"redacted-ok","toolNames":["pdt-get-portfolio-holdings"],"selectors":["pdt-get-portfolio-holdings"],"writeToolsCalled":0}

    Include all required tool names in toolNames/selectors only after you have reached them.
    If Claude or PDT MCP setup is missing, return status "setup-required" with redacted statusText.
    """
}

private func manualClaudePDTJSONSchema() -> String {
    """
    {"type":"object","additionalProperties":false,"properties":{"status":{"type":"string"},"statusText":{"type":"string"},"toolNames":{"type":"array","items":{"type":"string"}},"selectors":{"type":"array","items":{"type":"string"}},"writeToolsCalled":{"type":"integer"}},"required":["status","statusText","toolNames","selectors","writeToolsCalled"]}
    """
}

private func manualClaudePDTAllowedTools(
    claudePath: String,
    model: String,
    timeout: TimeInterval
) throws -> [String] {
    let result = try run(
        URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [
            claudePath,
            "--model", model,
            "--allowedTools", "ToolSearch",
            "--disallowedTools", manualClaudePDTToolSearchDisallowedTools().joined(separator: ","),
            "-p", "Use ToolSearch to find these PDT MCP read-only tools: \(PDTReadTools.requiredV1.joined(separator: ", ")). Return only {\"status\":\"redacted-ok\"}.",
            "--output-format", "stream-json",
            "--verbose",
            "--no-session-persistence",
        ],
        timeout: timeout
    )
    let output = String(decoding: result.stdout, as: UTF8.self)
    let resolved = Dictionary(uniqueKeysWithValues: PDTReadTools.requiredV1.compactMap { readTool -> (String, String)? in
        guard let toolName = manualClaudePDTToolName(readTool: readTool, in: output) else {
            return nil
        }
        return (readTool, toolName)
    })
    guard resolved.count == PDTReadTools.requiredV1.count else {
        throw PDTMCPConnectorError.setupUnavailable("ToolSearch did not resolve all PDT read tools")
    }
    return PDTReadTools.requiredV1.compactMap { resolved[$0] } + ["StructuredOutput", "ToolSearch"]
}

private func manualClaudePDTToolName(readTool: String, in output: String) -> String? {
    let pattern = #"mcp__[A-Za-z0-9_.-]+__\#(NSRegularExpression.escapedPattern(for: readTool))"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(output.startIndex..<output.endIndex, in: output)
    return expression.matches(in: output, range: range).compactMap { match in
        Range(match.range, in: output).map { String(output[$0]) }
    }.first
}

private func manualClaudePDTDisallowedTools() -> [String] {
    // Shared with the production read-only sync (`ClaudeLocalConnection`) so
    // this smoke always exercises the real read-only deny policy.
    ClaudePDTReadOnlyToolPolicy.disallowedTools
}

private func manualClaudePDTToolSearchDisallowedTools() -> [String] {
    manualClaudePDTDisallowedTools().filter { !$0.hasPrefix("mcp__") }
}

private func redactedClaudePDTResponse(from data: Data) -> RedactedClaudePDTResponse {
    let streamObjects = streamJSONObjects(from: data)
    let rawToolUseNames = streamObjects.flatMap(toolUseNames)
    let telemetryToolNames = safePDTReadToolNames(in: rawToolUseNames)
    let telemetryNonReadPDTToolNames = nonRequiredPDTToolNames(in: rawToolUseNames)
    let telemetryToolResultErrorCount = streamObjects.map(toolResultErrorCount).reduce(0, +)
    let reachedAllRequired = Set(PDTReadTools.requiredV1).isSubset(of: Set(telemetryToolNames))
    let status = reachedAllRequired ? "redacted-ok" : (telemetryToolNames.isEmpty ? "setup-required" : "partial")
    return RedactedClaudePDTResponse(
        status: status,
        statusText: reachedAllRequired ? "redacted-ok" : redactedStatus(status),
        toolNames: telemetryToolNames,
        selectors: telemetryToolNames,
        writeToolsCalled: telemetryNonReadPDTToolNames.count,
        nonReadPDTToolNames: telemetryNonReadPDTToolNames,
        toolResultErrorCount: telemetryToolResultErrorCount
    )
}

private func savedClaudeToolResultFiles(in data: Data) -> [URL] {
    guard let text = String(data: data, encoding: .utf8) else {
        return []
    }
    let projectsRoot = claudeProjectsDirectory().path
    var files: [URL] = []
    var searchStart = text.startIndex
    while let rootRange = text.range(of: projectsRoot, range: searchStart..<text.endIndex),
          let extensionRange = text.range(of: ".txt", range: rootRange.lowerBound..<text.endIndex)
    {
        let path = String(text[rootRange.lowerBound..<extensionRange.upperBound])
        files.append(URL(fileURLWithPath: path))
        searchStart = extensionRange.upperBound
    }
    return files
}

private func deleteSavedClaudeToolResultFiles(_ files: [URL]) {
    for file in Set(files) {
        try? FileManager.default.removeItem(at: file)
    }
}

private func pdtToolResultFiles(in createdFiles: Set<URL>, referencedFiles: Set<URL>, sessionID: String) -> [URL] {
    let deadline = Date().addingTimeInterval(1.0)
    var sessionFiles = Set<URL>()
    repeat {
        sessionFiles = claudeToolResultFiles(sessionID: sessionID)
        if sessionFiles.contains(where: { file in
            PDTReadTools.requiredV1.contains { file.lastPathComponent.contains($0) }
        }) {
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    let referenced = createdFiles.intersection(referencedFiles)
    let matchingReadTool = createdFiles.union(sessionFiles).filter { file in
        PDTReadTools.requiredV1.contains { file.lastPathComponent.contains($0) }
    }
    return Array(referenced.union(matchingReadTool))
}

private func claudeToolResultFiles(sessionID: String? = nil) -> Set<URL> {
    let root = claudeProjectsDirectory()
    guard let projects = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    var files = Set<URL>()
    for project in projects {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { continue }
        let sessionDirectories: [URL]
        if let sessionID {
            sessionDirectories = [project.appending(path: sessionID)]
        } else {
            sessionDirectories = (try? FileManager.default.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        for sessionDirectory in sessionDirectories {
            let toolResults = sessionDirectory.appending(path: "tool-results")
            guard let toolFiles = try? FileManager.default.contentsOfDirectory(
                at: toolResults,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            files.formUnion(toolFiles.filter { $0.pathExtension == "txt" })
        }
    }
    return files
}

private func claudeProjectsDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
}

private func streamJSONObjects(from data: Data) -> [[String: Any]] {
    guard let text = String(data: data, encoding: .utf8) else {
        return []
    }
    return text
        .split(separator: "\n")
        .compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return nil
            }
            return object
        }
}

private func toolUseNames(in object: Any) -> [String] {
    if let array = object as? [Any] {
        return array.flatMap(toolUseNames)
    }
    guard let dictionary = object as? [String: Any] else {
        return []
    }
    let current: [String]
    if dictionary["type"] as? String == "tool_use",
       let name = dictionary["name"] as? String
    {
        current = [name]
    } else {
        current = []
    }
    return current + dictionary.values.flatMap(toolUseNames)
}

private func toolResultErrorCount(in object: Any) -> Int {
    if let array = object as? [Any] {
        return array.map(toolResultErrorCount).reduce(0, +)
    }
    guard let dictionary = object as? [String: Any] else {
        return 0
    }
    let current = dictionary["type"] as? String == "tool_result"
        && (dictionary["is_error"] as? Bool == true || dictionary["isError"] as? Bool == true)
        ? 1
        : 0
    return current + dictionary.values.map(toolResultErrorCount).reduce(0, +)
}

private func safePDTReadToolNames(in values: [String]) -> [String] {
    let safeNames = values.flatMap { value in
        PDTReadTools.requiredV1.filter { value.contains($0) }
    }
    return Array(Set(safeNames)).sorted()
}

private func nonRequiredPDTToolNames(in values: [String]) -> [String] {
    let required = Set(PDTReadTools.requiredV1)
    let names = values.flatMap(pdtToolNames)
        .filter { !required.contains($0) }
    return Array(Set(names)).sorted()
}

private func pdtToolNames(in value: String) -> [String] {
    value
        .split { character in
            !(character.isLetter || character.isNumber || character == "-")
        }
        .map(String.init)
        .filter { $0.hasPrefix("pdt-") }
}

private func redactedStatus(_ status: String) -> String {
    let lowered = status.lowercased()
    if lowered.contains("setup") || lowered.contains("missing") || lowered.contains("login") {
        return "redacted-setup-required"
    }
    if lowered.contains("ok") || lowered.contains("pass") || lowered.contains("success") {
        return "redacted-ok"
    }
    return "redacted-status"
}

private func executableExistsOnPath(_ name: String) -> Bool {
    guard !name.contains("/") else {
        return FileManager.default.isExecutableFile(atPath: name)
    }
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
    return paths.contains { directory in
        FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: directory).appending(path: name).path)
    }
}

private func roundedSmokeValue(_ value: Double, places: Int) -> Double {
    let multiplier = pow(10.0, Double(places))
    return (value * multiplier).rounded() / multiplier
}

private func fixtureProofSVG(descriptor: MenuDescriptor) -> String {
    let rows = descriptor.sections.flatMap { section in
        [section.title] + section.rows.prefix(2).map { row in
            row.detail.map { "\(row.title) - \($0)" } ?? row.title
        }
    }.prefix(8)
    let escapedRows = rows.enumerated().map { offset, row in
        "<text x=\"44\" y=\"\(154 + (offset * 28))\" class=\"row\">\(escape(row))</text>"
    }.joined(separator: "\n")

    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="900" height="460" viewBox="0 0 900 460">
      <rect width="900" height="460" fill="#f7f7f2"/>
      <rect x="30" y="28" width="840" height="48" rx="8" fill="#1f2933"/>
      \(statusIconSVG(visual: descriptor.statusVisual, x: 48, y: 41, scale: 1.25))
      <rect x="30" y="100" width="520" height="320" rx="8" fill="#ffffff" stroke="#d6d3ca"/>
      <text x="44" y="132" class="heading">Fixture menu proof</text>
      \(escapedRows)
      <style>
        .heading { font: 700 18px -apple-system, BlinkMacSystemFont, sans-serif; fill: #18202a; }
        .row { font: 15px -apple-system, BlinkMacSystemFont, sans-serif; fill: #2e3742; }
      </style>
    </svg>

    """
}

private struct MenuProofCard {
    var title: String
    var descriptor: MenuDescriptor
}

private func menuProofSVG(cards: [MenuProofCard]) -> String {
    let cardWidth = 520
    let cardHeight = 330
    let gap = 24
    let columns = 2
    let rows = Int(ceil(Double(cards.count) / Double(columns)))
    let width = (cardWidth * columns) + (gap * (columns + 1))
    let height = (cardHeight * rows) + (gap * (rows + 1))
    let cardMarkup = cards.enumerated().map { index, card in
        let column = index % columns
        let row = index / columns
        let x = gap + column * (cardWidth + gap)
        let y = gap + row * (cardHeight + gap)
        return menuProofCardSVG(card: card, x: x, y: y, width: cardWidth, height: cardHeight)
    }.joined(separator: "\n")

    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
      <rect width="100%" height="100%" fill="#f5f5f0"/>
      \(cardMarkup)
      <style>
        .card { fill: #ffffff; stroke: #d7d3c8; }
        .status { fill: #18202a; }
        .label { font: 700 13px -apple-system, BlinkMacSystemFont, sans-serif; fill: #5b6470; }
        .section { font: 700 13px -apple-system, BlinkMacSystemFont, sans-serif; fill: #18202a; }
        .row { font: 13px -apple-system, BlinkMacSystemFont, sans-serif; fill: #2e3742; }
        .child { font: 12px -apple-system, BlinkMacSystemFont, sans-serif; fill: #697386; }
      </style>
    </svg>

    """
}

private func menuProofCardSVG(card: MenuProofCard, x: Int, y: Int, width: Int, height: Int) -> String {
    let visibleRows = menuProofRows(descriptor: card.descriptor).prefix(10)
    let rowsMarkup = visibleRows.enumerated().map { offset, row in
        let className = row.isChild ? "child" : (row.isSection ? "section" : "row")
        let indent = row.isChild ? 22 : 0
        return "<text x=\"\(x + 22 + indent)\" y=\"\(y + 104 + offset * 20)\" class=\"\(className)\">\(escape(proofText(row.text, limit: row.isChild ? 62 : 66)))</text>"
    }.joined(separator: "\n")
    return """
      <g>
        <rect x="\(x)" y="\(y)" width="\(width)" height="\(height)" rx="8" class="card"/>
        <text x="\(x + 18)" y="\(y + 28)" class="label">\(escape(card.title))</text>
        <rect x="\(x + 16)" y="\(y + 42)" width="\(width - 32)" height="34" rx="7" class="status"/>
        \(statusIconSVG(visual: card.descriptor.statusVisual, x: x + 30, y: y + 50, scale: 1.0))
        \(rowsMarkup)
      </g>
    """
}

private func statusIconSVG(visual: StatusVisualState, x: Int, y: Int, scale: Double) -> String {
    let barWidth = 5.0 * scale
    let gap = 2.0 * scale
    let maxHeight = 16.2 * scale
    let baseline = Double(y) + (17.4 * scale)
    let fillOpacity = visual.isDimmed ? 0.36 : 0.72
    let outlineOpacity = visual.isDimmed ? 0.42 : 0.86
    let bars = visual.barHeights.prefix(3).enumerated().map { index, rawHeight in
        let height = max(0.30, min(1.0, rawHeight)) * maxHeight
        let barX = Double(x) + Double(index) * (barWidth + gap)
        let barY = baseline - height
        let fill = index < visual.filledBarCount
            ? "<rect x=\"\(svgNumber(barX))\" y=\"\(svgNumber(barY))\" width=\"\(svgNumber(barWidth))\" height=\"\(svgNumber(height))\" rx=\"\(svgNumber(2.5 * scale))\" fill=\"#ffffff\" opacity=\"\(svgNumber(fillOpacity))\"/>"
            : ""
        return [
            fill,
            "<rect x=\"\(svgNumber(barX))\" y=\"\(svgNumber(barY))\" width=\"\(svgNumber(barWidth))\" height=\"\(svgNumber(height))\" rx=\"\(svgNumber(2.5 * scale))\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"\(svgNumber(1.2 * scale))\" opacity=\"\(svgNumber(outlineOpacity))\"/>",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }.joined(separator: "\n")
    return ["<g>", bars, "</g>"].joined(separator: "\n")
}

private func svgNumber(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private struct MenuProofRow {
    var text: String
    var isSection: Bool
    var isChild: Bool
}

private func menuProofRows(descriptor: MenuDescriptor) -> [MenuProofRow] {
    descriptor.sections.flatMap { section in
        [MenuProofRow(text: section.title, isSection: true, isChild: false)]
            + section.rows.flatMap { menuProofRows(row: $0, depth: 0) }
    }
}

private func menuProofRows(row: MenuRow, depth: Int) -> [MenuProofRow] {
    let title = row.detail.map { "\(row.title) - \($0)" } ?? row.title
    return [MenuProofRow(text: title, isSection: false, isChild: depth > 0)]
        + row.children.flatMap { menuProofRows(row: $0, depth: depth + 1) }
}

private func proofText(_ value: String, limit: Int) -> String {
    if value.count <= limit {
        return value
    }
    return String(value.prefix(max(0, limit - 3))) + "..."
}

private func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func writeReport(_ report: SmokeReport) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private extension String {
    func dimensionValue(for key: String) -> Int? {
        split(separator: "\n").compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == key else {
                return nil
            }
            return Int(parts[1])
        }.first
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }
        return width * height
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case usage
    case runtime(String)
    case timedOut(String)
    case commandFailed(String, String, String)

    var description: String {
        switch self {
        case .usage:
            return "usage"
        case let .runtime(message):
            return message
        case let .timedOut(command):
            return "\(command) timed out"
        case let .commandFailed(command, stdout, stderr):
            return "\(command) failed: \([stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n"))"
        }
    }
}
