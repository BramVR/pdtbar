import ApplicationServices
import AppKit
import Foundation
import ImageIO
import PDTBarAppSupport
import PDTBarCore

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
    case "copy-holding-identifier-action":
        report = copyHoldingIdentifierActionSmoke()
    case "scripted-first-fetch":
        report = try scriptedFirstFetchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-returning-launch":
        report = try scriptedReturningLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-login-handoff":
        report = try scriptedLoginHandoffSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-setup-retry":
        report = try scriptedSetupRetrySmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-pulse-mark-read":
        report = try scriptedPulseMarkReadSmoke(arguments: Array(arguments.dropFirst()))
    case "logged-out-launch":
        report = try loggedOutLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "ready-launch":
        report = try readyLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "real-claude-flow-ax":
        report = try realClaudeFlowAXSmoke(arguments: Array(arguments.dropFirst()))
    case "packaged-onboarding":
        report = try packagedOnboardingSmoke(arguments: Array(arguments.dropFirst()))
    case "packaged-app":
        report = try packagedAppSmoke(arguments: Array(arguments.dropFirst()))
    case "peekaboo":
        report = try peekabooSmoke(arguments: Array(arguments.dropFirst()))
    case "real-user-pulse":
        report = try realUserPulseSmoke(arguments: Array(arguments.dropFirst()))
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
      pdtbar-smoke live-pdt [--server <mcporter-server>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-pdt-connector [--artifacts <dir>]
      pdtbar-smoke copy-holding-identifier-action
      pdtbar-smoke scripted-first-fetch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-returning-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-login-handoff [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-setup-retry [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-pulse-mark-read [--artifacts <dir>]
      pdtbar-smoke logged-out-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke ready-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke real-claude-flow-ax [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke packaged-onboarding [--app <path-to-PDTBar.app>] [--app-support-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
      pdtbar-smoke packaged-app [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--timeout <seconds>]
      pdtbar-smoke peekaboo [--peekaboo <path>] [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>]
      pdtbar-smoke real-user-pulse [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>] [--peekaboo <path>] [--timeout <seconds>]
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

private func readyLaunchSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "ready-launch-app-support")
    let responses = try scriptedPDTConnectorResponses()
    let configuration = ScriptedPDTMCPConnectorConfiguration(
        responses: responses.mapValues { String(decoding: $0, as: UTF8.self) },
        asOf: "2026-03-29"
    )
    try writeFirstFetchAppScript(configuration: configuration, appSupportDirectory: appSupportDirectory)
    let expectedStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-ready-launch-expected")
    defer {
        try? FileManager.default.removeItem(at: expectedStore.directory)
    }
    let expectedRun = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: configuration.connector()),
        snapshotStore: expectedStore,
        asOf: configuration.asOf
    ).fetch()
    let firstFetchSnapshot = appSupportDirectory.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    let fixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "ready-launch-fixture-sentinel")
    let fixtureSnapshot = fixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSnapshotDirectory.path,
        "PDTBAR_DISABLE_REAL_CLAUDE": "1",
    ]) { _, new in new }
    try process.run()
    defer {
        terminate(process)
    }
    let snapshotWritten = waitForFile(firstFetchSnapshot, timeout: options.timeout)
    guard process.isRunning else {
        process.waitUntilExit()
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "scripted ready app exited before the smoke timeout",
            artifacts: [artifactPath(appSupportDirectory)]
        )
    }
    guard snapshotWritten else {
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "scripted ready launch did not complete the first portfolio fetch",
            artifacts: [artifactPath(appSupportDirectory)]
        )
    }
    guard !FileManager.default.fileExists(atPath: fixtureSnapshot.path) else {
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "scripted ready launch consumed fixture environment and wrote fixture snapshot state",
            artifacts: [artifactPath(fixtureSnapshot)]
        )
    }

    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.skipped,
            detail: "scripted ready app completed first fetch and ignored fixture env; macOS Accessibility permission missing for pulse menu inspection",
            artifacts: [artifactPath(firstFetchSnapshot)]
        )
    }

    let surface = MenuBarSurfaceRenderer.render(descriptor: expectedRun.descriptor)
    let expectedTargets = requiredPulseMenuTargets(in: surface)
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "scripted ready app launched, but Accessibility could not find status item \(surface.status.accessibilityIdentifier)",
            artifacts: [artifactPath(appSupportDirectory)]
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
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let evidence = artifacts.appending(path: "pdtbar-ready-launch-ax.json")
    try writeAccessibilityEvidence(
        snapshot: menuSnapshot,
        expected: expectedTargets,
        statusIdentifier: surface.status.accessibilityIdentifier,
        statusText: accessibilityTexts(in: statusElement),
        output: evidence
    )
    let missingTargets = expectedTargets.filter { !menuSnapshot.identifiers.contains($0.accessibilityIdentifier) }
    let forbiddenTexts = Set(["Not connected", "Log in with Claude"]).intersection(menuSnapshot.texts)
    guard missingTargets.isEmpty && forbiddenTexts.isEmpty else {
        let missingLabels = missingTargets
            .map { "\($0.accessibilityIdentifier) (\($0.title))" }
            .joined(separator: ", ")
        return SmokeReport(
            name: "ready-launch",
            status: SmokeStatus.failed,
            detail: "scripted ready launch did not publish the first pulse cleanly after \(openedMenu.attempts.joined(separator: ", ")); missing selectors: \(missingLabels); forbidden login text: \(forbiddenTexts.sorted().joined(separator: ", "))",
            artifacts: [artifactPath(evidence)]
        )
    }

    return SmokeReport(
        name: "ready-launch",
        status: SmokeStatus.passed,
        detail: "scripted Claude/PDT readiness skipped logged-out UI, completed first fetch, and rendered the first real pulse without consuming fixture state",
        artifacts: [artifactPath(evidence), artifactPath(firstFetchSnapshot)]
    )
}

private func loggedOutLaunchSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "logged-out-launch-app-support")
    let setupStateDirectory = appSupportDirectory.appending(path: "pdtbar")
    try FileManager.default.createDirectory(at: setupStateDirectory, withIntermediateDirectories: true)
    try Data("{".utf8).write(
        to: setupStateDirectory.appending(path: "claude-setup.json"),
        options: .atomic
    )
    let fixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "logged-out-fixture-sentinel")
    let fixtureSnapshot = fixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSnapshotDirectory.path,
        "PDTBAR_DISABLE_REAL_CLAUDE": "1",
    ]) { _, new in new }
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
    Thread.sleep(forTimeInterval: options.timeout)
    guard process.isRunning else {
        process.waitUntilExit()
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.failed,
            detail: "no-argument app exited before the smoke timeout",
            artifacts: [artifactPath(appSupportDirectory)]
        )
    }
    guard !FileManager.default.fileExists(atPath: fixtureSnapshot.path) else {
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.failed,
            detail: "no-argument app consumed fixture environment and wrote fixture snapshot state",
            artifacts: [artifactPath(fixtureSnapshot)]
        )
    }

    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.skipped,
            detail: "no-argument app stayed running with isolated app support and ignored fixture env; macOS Accessibility permission missing for setup menu inspection",
            artifacts: [artifactPath(appSupportDirectory)]
        )
    }

    let descriptor = ClaudeSetupMenuDescriptor.loggedOut()
    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let expectedTargets = requiredSetupMenuTargets(in: surface)
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.failed,
            detail: "no-argument app launched, but Accessibility could not find status item \(surface.status.accessibilityIdentifier)",
            artifacts: [artifactPath(appSupportDirectory)]
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
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let evidence = artifacts.appending(path: "pdtbar-logged-out-launch-ax.json")
    try writeAccessibilityEvidence(
        snapshot: menuSnapshot,
        expected: expectedTargets,
        statusIdentifier: surface.status.accessibilityIdentifier,
        statusText: accessibilityTexts(in: statusElement),
        output: evidence
    )
    let expectedTexts = Set(["Not connected", "Log in with Claude", "Quit PDTBar"])
    let missingTargets = expectedTargets.filter { !menuSnapshot.identifiers.contains($0.accessibilityIdentifier) }
    let missingTexts = expectedTexts.filter { expectedText in
        !menuSnapshot.texts.contains { observedText in
            observedText.contains(expectedText)
        }
    }
    guard missingTargets.isEmpty && missingTexts.isEmpty else {
        let missingLabels = missingTargets
            .map { "\($0.accessibilityIdentifier) (\($0.title))" }
            .joined(separator: ", ")
        let missingCopy = missingTexts.sorted().joined(separator: ", ")
        return SmokeReport(
            name: "logged-out-launch",
            status: SmokeStatus.failed,
            detail: "could not verify logged-out setup menu after \(openedMenu.attempts.joined(separator: ", ")); missing selectors: \(missingLabels); missing text: \(missingCopy)",
            artifacts: [artifactPath(evidence)]
        )
    }

    return SmokeReport(
        name: "logged-out-launch",
        status: SmokeStatus.passed,
        detail: "no-argument app launched real Claude-first setup with isolated app support, ignored fixture env, and rendered Not connected, Log in with Claude, and Quit PDTBar",
        artifacts: [artifactPath(evidence)]
    )
}

private func realClaudeFlowAXSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "real-claude-flow-ax",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-real-claude-flow-ax-proof.json")
    var proofPayload = RealClaudeFlowAXProof(
        appArguments: [],
        fixtureModeUsed: false,
        scenarios: [],
        rawClaudeCredentialsUsed: false,
        rawPortfolioPayloadsRedacted: true
    )

    guard AXIsProcessTrusted() else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "real-claude-flow-ax",
            status: SmokeStatus.skipped,
            detail: "macOS Accessibility permission missing for real Claude-flow menu-bar smoke; grant Accessibility in System Settings > Privacy & Security > Accessibility to the app running this command, then rerun",
            artifacts: [artifactPath(proof)]
        )
    }

    let pressureResponses = try scriptedPDTConnectorResponses().mapValues { String(decoding: $0, as: UTF8.self) }
    let quietResponses = try scriptedQuietPDTConnectorResponses().mapValues { String(decoding: $0, as: UTF8.self) }

    let fetchingConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: quietResponses,
        asOf: "2026-03-29",
        initialCallDelaySeconds: max(options.timeout * 4.0, 6.0)
    )
    let quietConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: quietResponses,
        asOf: "2026-03-29"
    )
    let pressureConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: pressureResponses,
        asOf: "2026-03-29"
    )
    let retryableErrorConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: quietResponses,
        asOf: "2026-03-29",
        failure: "transientFailure",
        failureMessage: "Claude call timed out"
    )

    let quietExpectedStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-real-claude-flow-quiet-expected")
    let pressureExpectedStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-real-claude-flow-pressure-expected")
    defer {
        try? FileManager.default.removeItem(at: quietExpectedStore.directory)
        try? FileManager.default.removeItem(at: pressureExpectedStore.directory)
    }
    let quietExpectedRun = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: quietConfiguration.connector()),
        snapshotStore: quietExpectedStore,
        asOf: quietConfiguration.asOf
    ).fetch()
    let pressureExpectedRun = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: pressureConfiguration.connector()),
        snapshotStore: pressureExpectedStore,
        asOf: pressureConfiguration.asOf
    ).fetch()

    proofPayload.scenarios = [
        try realClaudeFlowAXScenario(
            name: "setup",
            app: app,
            options: options,
            artifacts: artifacts,
            readiness: "missingClaudeLogin",
            configuration: nil,
            descriptor: ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin),
            targetMode: .setup,
            expectedTexts: ["Not connected", "Log in with Claude", "Check again"]
        ),
        try realClaudeFlowAXScenario(
            name: "fetching",
            app: app,
            options: options,
            artifacts: artifacts,
            readiness: nil,
            configuration: fetchingConfiguration,
            descriptor: ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio),
            targetMode: .setup,
            expectedTexts: ["Fetching portfolio"]
        ),
        try realClaudeFlowAXScenario(
            name: "all-quiet",
            app: app,
            options: options,
            artifacts: artifacts,
            readiness: nil,
            configuration: quietConfiguration,
            descriptor: quietExpectedRun.descriptor,
            targetMode: .pulse,
            expectedTexts: ["All quiet - No attention items right now.", "No income events"],
            expectedSnapshotAsOf: "2026-03-29"
        ),
        try realClaudeFlowAXScenario(
            name: "pressure",
            app: app,
            options: options,
            artifacts: artifacts,
            readiness: nil,
            configuration: pressureConfiguration,
            descriptor: pressureExpectedRun.descriptor,
            targetMode: .pulse,
            expectedTexts: ["Scripted Adapter Co concentration"],
            expectedSnapshotAsOf: "2026-03-29"
        ),
        try realClaudeFlowAXScenario(
            name: "retryable-error",
            app: app,
            options: options,
            artifacts: artifacts,
            readiness: nil,
            configuration: retryableErrorConfiguration,
            descriptor: ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed),
            targetMode: .setup,
            expectedTexts: ["Could not fetch portfolio", "Try again"]
        ),
    ]
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard proofPayload.scenarios.allSatisfy(\.passed) else {
        return SmokeReport(
            name: "real-claude-flow-ax",
            status: SmokeStatus.failed,
            detail: "real app Claude-flow Accessibility matrix did not verify every setup/fetching/all-quiet/pressure/retryable-error surface",
            artifacts: [artifactPath(proof)] + proofPayload.scenarios.map(\.evidencePath)
        )
    }

    return SmokeReport(
        name: "real-claude-flow-ax",
        status: SmokeStatus.passed,
        detail: "real app no-argument Claude flow opened the menu through Accessibility and verified stable status/menu identifiers across setup, fetching, all-quiet, pressure, and retryable error surfaces",
        artifacts: [artifactPath(proof)] + proofPayload.scenarios.map(\.evidencePath)
    )
}

private func scriptedLoginHandoffSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-login-handoff-proof.json")

    guard AXIsProcessTrusted() else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.skipped,
            detail: "macOS Accessibility permission missing for user-initiated Log in with Claude menu-click proof",
            artifacts: []
        )
    }

    let successAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-login-handoff-success-app-support")
    let successMarker = successAppSupport.appending(path: "pdtbar/claude-handoff-started")
    let successInvocationLog = successMarker.appendingPathExtension("log")
    let successResult = successAppSupport.appending(path: "pdtbar/claude-handoff-result")
    let successProbeLog = successAppSupport.appending(path: "pdtbar/readiness-probes.log")
    let successScript = try writeHandoffScript(
        in: successAppSupport,
        name: "handoff-success.sh",
        delay: max(options.timeout + 3.0, 4.0),
        postSuccessDelay: max(options.timeout + 12.0, 16.0),
        exitStatus: 0
    )
    let successProcess = try launchLoginHandoffApp(
        app,
        appSupportDirectory: successAppSupport,
        handoffScript: successScript,
        marker: successMarker,
        result: successResult,
        resultValue: "success",
        probeLog: successProbeLog
    )
    defer {
        terminate(successProcess)
    }

    let loginSurface = MenuBarSurfaceRenderer.render(descriptor: ClaudeSetupMenuDescriptor.loggedOut())
    let loginTargets = requiredSetupMenuTargets(in: loginSurface)
    let loginIDs = Set(loginTargets.map(\.accessibilityIdentifier))
    let successAppElement = AXUIElementCreateApplication(successProcess.processIdentifier)
    guard let successStatus = waitForAccessibilityElement(
        in: successAppElement,
        identifier: loginSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.failed,
            detail: "scripted success launch did not reach logged-out setup before handoff",
            artifacts: [artifactPath(successAppSupport)]
        )
    }
    let successWasIdleBeforeClick = !FileManager.default.fileExists(atPath: successMarker.path)
    let successInitialReadinessProbed = waitForReadinessProbeCount(
        successProbeLog,
        expectedCount: 1,
        timeout: options.timeout
    )
    let successClick = pressMenuRow(
        statusElement: successStatus,
        appElement: successAppElement,
        rowIdentifier: "pdtbar.row.claudeSetup.login",
        expectedMenuIdentifiers: loginIDs,
        timeout: options.timeout
    )
    let successScriptInvoked = waitForFile(successMarker, timeout: options.timeout)
    let progressVisible = waitForStatusText(
        "Signing in with Claude",
        in: successAppElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout
    )
    let openingSurface = MenuBarSurfaceRenderer.render(descriptor: ClaudeLaunchFlow.descriptor(for: .openingClaude))
    let openingTargets = requiredSetupMenuTargets(in: openingSurface)
    let openingIDs = Set(openingTargets.map(\.accessibilityIdentifier))
    let progressMenu = openStatusMenu(
        successStatus,
        appElement: successAppElement,
        expectedMenuIdentifiers: openingIDs,
        timeout: options.timeout
    )
    let progressRetryVisible = openingIDs.isSubset(of: progressMenu.snapshot?.identifiers ?? [])
        && (progressMenu.snapshot?.texts.contains("Try login again") ?? false)
    let successRetryClick = pressMenuRow(
        statusElement: successStatus,
        appElement: successAppElement,
        rowIdentifier: "pdtbar.row.claudeSetup.login",
        expectedMenuIdentifiers: openingIDs,
        timeout: options.timeout
    )
    let successRetryInvoked = waitForHandoffInvocationCount(
        successInvocationLog,
        expectedCount: 2,
        timeout: options.timeout
    )
    let successSupersededAttemptTerminated = waitForFileContent(
        successInvocationLog,
        contains: "terminated",
        timeout: options.timeout + 2.0
    )
    let successLoginArgsIncluded = waitForFileContent(
        successMarker,
        contains: "auth login",
        timeout: options.timeout
    )
    let successConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: try scriptedPDTConnectorResponses().mapValues { String(decoding: $0, as: UTF8.self) },
        asOf: "2026-03-29",
        initialCallDelaySeconds: 1.0
    )
    try writeFirstFetchAppScript(configuration: successConfiguration, appSupportDirectory: successAppSupport)
    let successCompleted = waitForFile(successResult, timeout: options.timeout + 8.0)
    let successReadinessRechecked = waitForReadinessProbeCount(
        successProbeLog,
        expectedCount: 2,
        timeout: options.timeout + 6.0
    )
    let successReadinessProbeCount = readinessProbeCount(in: successProbeLog)
    let successFetchingVisible = waitForStatusText(
        "Fetching portfolio",
        in: successAppElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout
    )
    let successFirstFetchSnapshot = successAppSupport.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    let successFirstFetchSnapshotWritten = waitForSnapshotAsOf(
        successFirstFetchSnapshot,
        asOf: "2026-03-29",
        timeout: options.timeout + 8.0
    )
    let successStoppedAfterOutput = waitForHandoffTerminationCount(
        successInvocationLog,
        expectedCount: 2,
        timeout: options.timeout + 2.0
    )
    let successFirstFetchAsOf = snapshotAsOf(successFirstFetchSnapshot)
    terminate(successProcess)

    let failureAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-login-handoff-failure-app-support")
    let failureMarker = failureAppSupport.appending(path: "pdtbar/claude-handoff-started")
    let failureResult = failureAppSupport.appending(path: "pdtbar/claude-handoff-result")
    let failureScript = try writeHandoffScript(
        in: failureAppSupport,
        name: "handoff-failure.sh",
        delay: 0.1,
        promptBeforeURL: false,
        exitStatus: 42
    )
    let failureProcess = try launchLoginHandoffApp(
        app,
        appSupportDirectory: failureAppSupport,
        handoffScript: failureScript,
        marker: failureMarker,
        result: failureResult,
        resultValue: "failure"
    )
    defer {
        terminate(failureProcess)
    }

    let failureAppElement = AXUIElementCreateApplication(failureProcess.processIdentifier)
    guard let failureStatus = waitForAccessibilityElement(
        in: failureAppElement,
        identifier: loginSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.failed,
            detail: "scripted failure launch did not reach logged-out setup before handoff",
            artifacts: [artifactPath(failureAppSupport)]
        )
    }
    let failureWasIdleBeforeClick = !FileManager.default.fileExists(atPath: failureMarker.path)
    let failureClick = pressMenuRow(
        statusElement: failureStatus,
        appElement: failureAppElement,
        rowIdentifier: "pdtbar.row.claudeSetup.login",
        expectedMenuIdentifiers: loginIDs,
        timeout: options.timeout
    )
    let failureScriptInvoked = waitForFile(failureMarker, timeout: options.timeout)
    let failureLoginArgsIncluded = waitForFileContent(
        failureMarker,
        contains: "auth login",
        timeout: options.timeout
    )
    let failureCompleted = waitForFile(failureResult, timeout: options.timeout + 2.0)
    let missingClaudeSurface = MenuBarSurfaceRenderer.render(
        descriptor: ClaudeLaunchFlow.descriptor(forLoginFailure: .failed)
    )
    let missingClaudeTargets = requiredSetupMenuTargets(in: missingClaudeSurface)
    let missingClaudeIDs = Set(missingClaudeTargets.map(\.accessibilityIdentifier))
    let missingClaudeStatusVisible = waitForStatusText(
        "Claude login failed",
        in: failureAppElement,
        statusIdentifier: missingClaudeSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    )
    if missingClaudeStatusVisible {
        Thread.sleep(forTimeInterval: 0.3)
    }
    let missingClaudeMenu: AccessibilitySnapshot
    let missingClaudeOpenAttempt: String?
    if let missingClaudeStatus = waitForAccessibilityElement(
        in: failureAppElement,
        identifier: missingClaudeSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) {
        let openedMenu = openStatusMenu(
            missingClaudeStatus,
            appElement: failureAppElement,
            expectedMenuIdentifiers: missingClaudeIDs,
            timeout: options.timeout
        )
        missingClaudeOpenAttempt = openedMenu.successfulAttempt ?? openedMenu.attempts.joined(separator: "; ")
        missingClaudeMenu = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
            missingClaudeIDs,
            in: failureAppElement,
            timeout: options.timeout
        )
    } else {
        missingClaudeOpenAttempt = nil
        missingClaudeMenu = waitForAccessibilityIdentifiers(
            missingClaudeIDs,
            in: failureAppElement,
            timeout: options.timeout
        )
    }
    let missingClaudeMenuVisible = missingClaudeIDs.isSubset(of: missingClaudeMenu.identifiers)
        && missingClaudeMenu.texts.contains { $0.contains("Claude login failed") }
        && missingClaudeMenu.texts.contains("Log in with Claude")

    let proofPayload = ScriptedLoginHandoffProof(
        successIdleBeforeClick: successWasIdleBeforeClick,
        successInitialReadinessProbed: successInitialReadinessProbed,
        successClickAttempt: successClick,
        successScriptInvoked: successScriptInvoked,
        successLoginArgsIncluded: successLoginArgsIncluded,
        successProgressVisible: progressVisible,
        successProgressRetryVisible: progressRetryVisible,
        successProgressMenuOpenAttempt: progressMenu.successfulAttempt,
        successProgressObservedIdentifiers: progressMenu.snapshot?.identifiers.sorted() ?? [],
        successProgressObservedTexts: progressMenu.snapshot?.texts.sorted() ?? [],
        successRetryClickAttempt: successRetryClick,
        successRetryInvoked: successRetryInvoked,
        successSupersededAttemptTerminated: successSupersededAttemptTerminated,
        successStoppedAfterOutput: successStoppedAfterOutput,
        successCompleted: successCompleted,
        successReadinessRechecked: successReadinessRechecked,
        successReadinessProbeCount: successReadinessProbeCount,
        successFetchingVisible: successFetchingVisible,
        successFirstFetchSnapshotWritten: successFirstFetchSnapshotWritten,
        successFirstFetchAsOf: successFirstFetchAsOf,
        failureIdleBeforeClick: failureWasIdleBeforeClick,
        failureClickAttempt: failureClick,
        failureScriptInvoked: failureScriptInvoked,
        failureLoginArgsIncluded: failureLoginArgsIncluded,
        failureCompleted: failureCompleted,
        failureMissingClaudeStatusVisible: missingClaudeStatusVisible,
        failureMissingClaudeMenuVisible: missingClaudeMenuVisible,
        failureMissingClaudeOpenAttempt: missingClaudeOpenAttempt,
        failureMissingClaudeObservedIdentifiers: missingClaudeMenu.identifiers.sorted(),
        failureMissingClaudeObservedTexts: missingClaudeMenu.texts.sorted(),
        rawClaudeCredentialsUsed: false
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard successWasIdleBeforeClick,
          successInitialReadinessProbed,
          successClick != nil,
          successScriptInvoked,
          successLoginArgsIncluded,
          progressVisible,
          progressRetryVisible,
          successRetryClick != nil,
          successRetryInvoked,
          successSupersededAttemptTerminated,
          successStoppedAfterOutput,
          successCompleted,
          successReadinessRechecked,
          successReadinessProbeCount == 2,
          successFetchingVisible,
          successFirstFetchSnapshotWritten,
          successFirstFetchAsOf == "2026-03-29",
          failureWasIdleBeforeClick,
          failureClick != nil,
          failureScriptInvoked,
          failureLoginArgsIncluded,
          failureCompleted,
          missingClaudeStatusVisible,
          missingClaudeMenuVisible
    else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.failed,
            detail: "scripted login handoff did not prove user-initiated success, in-flight retry supersession, readiness recheck, first fetch, and missing-Claude failure states",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "scripted-login-handoff",
        status: SmokeStatus.passed,
        detail: "Log in with Claude invoked scripted claude auth login only after menu click, superseded an in-flight auth retry, rechecked readiness once, started first fetch, and rendered failed-login state on login failure",
        artifacts: [artifactPath(proof)]
    )
}

private func packagedOnboardingSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let appBundle = options.app ?? packageRoot.appending(path: "PDTBar.app")
    guard appBundle.pathExtension == "app",
          let app = appBundleExecutable(in: appBundle),
          FileManager.default.isExecutableFile(atPath: app.path)
    else {
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.failed,
            detail: "packaged PDTBar.app missing; run ./Scripts/package_app.sh or pass --app <path-to-PDTBar.app>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-packaged-onboarding-proof.json")
    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "packaged-onboarding-app-support")
    let fixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "packaged-onboarding-fixture-sentinel")
    let fixtureSnapshot = fixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let marker = appSupportDirectory.appending(path: "pdtbar/claude-handoff-started")
    let result = appSupportDirectory.appending(path: "pdtbar/claude-handoff-result")
    let probeLog = appSupportDirectory.appending(path: "pdtbar/readiness-probes.log")
    let handoffScript = try writeHandoffScript(
        in: appSupportDirectory,
        name: "packaged-onboarding-handoff-success.sh",
        delay: max(options.timeout, 1.0),
        exitStatus: 0
    )

    var proofPayload = PackagedOnboardingProof(
        appBundlePath: artifactPath(appBundle),
        appExecutablePath: artifactPath(app),
        appArguments: [],
        appSupportPath: artifactPath(appSupportDirectory),
        fixtureSnapshotPath: artifactPath(fixtureSnapshot),
        fixtureEnvInjected: true,
        fixtureSnapshotWritten: false,
        accessibilityChecked: AXIsProcessTrusted(),
        setupMenuVisible: false,
        loginClickAttempt: nil,
        handoffScriptInvoked: false,
        loginArgsIncluded: false,
        openingStatusVisible: false,
        readinessProbeCount: 0,
        readinessRechecked: false,
        fetchingVisibleAfterReadiness: false,
        firstFetchSnapshotWritten: false,
        postReadinessState: nil,
        expectedSelectors: [],
        observedSelectors: [],
        observedStatusText: [],
        screenshotPaths: [],
        rawClaudeCredentialsUsed: false,
        rawPortfolioPayloadsRedacted: true
    )
    let screenshotTool = options.peekaboo.flatMap(peekabooScreenshotTool)

    let process = try launchPackagedOnboardingApp(
        app,
        appSupportDirectory: appSupportDirectory,
        fixtureSnapshotDirectory: fixtureSnapshotDirectory,
        handoffScript: handoffScript,
        marker: marker,
        result: result,
        probeLog: probeLog
    )
    defer {
        terminate(process)
    }

    let loginSurface = MenuBarSurfaceRenderer.render(descriptor: ClaudeSetupMenuDescriptor.loggedOut())
    let loginTargets = requiredSetupMenuTargets(in: loginSurface)
    let loginIDs = Set(loginTargets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    _ = waitForReadinessProbeCount(probeLog, expectedCount: 1, timeout: options.timeout)
    Thread.sleep(forTimeInterval: 0.2)

    guard process.isRunning else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.failed,
            detail: "packaged PDTBar.app exited before onboarding setup proof",
            artifacts: [artifactPath(proof), artifactPath(appSupportDirectory)]
        )
    }

    proofPayload.fixtureSnapshotWritten = FileManager.default.fileExists(atPath: fixtureSnapshot.path)
    proofPayload.readinessProbeCount = readinessProbeCount(in: probeLog)
    guard !proofPayload.fixtureSnapshotWritten else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.failed,
            detail: "packaged no-argument onboarding consumed fixture environment and wrote fixture snapshot state",
            artifacts: [artifactPath(proof)]
        )
    }

    guard proofPayload.accessibilityChecked else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.skipped,
            detail: "packaged PDTBar.app launched with isolated app support and ignored fixture env; macOS Accessibility permission missing for Log in with Claude click proof",
            artifacts: [artifactPath(proof)]
        )
    }

    guard let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: loginSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.failed,
            detail: "packaged PDTBar.app launched, but Accessibility could not find setup status item \(loginSurface.status.accessibilityIdentifier)",
            artifacts: [artifactPath(proof)]
        )
    }

    let openedMenu = openStatusMenu(
        statusElement,
        appElement: appElement,
        expectedMenuIdentifiers: loginIDs,
        timeout: options.timeout
    )
    let setupSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
        loginIDs,
        in: appElement,
        timeout: options.timeout
    )
    if loginIDs.isSubset(of: setupSnapshot.identifiers),
       let screenshot = try? captureMenuScreenshot(
           name: "pdtbar-packaged-onboarding-setup",
           snapshot: setupSnapshot,
           expectedMenuIdentifiers: loginIDs,
           artifacts: artifacts,
           peekaboo: screenshotTool
       )
    {
        proofPayload.screenshotPaths.append(artifactPath(screenshot))
    }
    proofPayload.setupMenuVisible = loginIDs.isSubset(of: setupSnapshot.identifiers)
        && setupSnapshot.texts.contains("Log in with Claude")
        && setupSnapshot.texts.contains { $0.contains("Not connected") }
    proofPayload.expectedSelectors = loginIDs.sorted()
    proofPayload.observedSelectors = setupSnapshot.identifiers.sorted()
    proofPayload.observedStatusText = accessibilityTexts(in: statusElement).sorted()

    let configuration = ScriptedPDTMCPConnectorConfiguration(
        responses: try scriptedPDTConnectorResponses().mapValues { String(decoding: $0, as: UTF8.self) },
        asOf: "2026-03-29",
        initialCallDelaySeconds: max(options.timeout, 1.0)
    )
    try writeFirstFetchAppScript(configuration: configuration, appSupportDirectory: appSupportDirectory)

    proofPayload.loginClickAttempt = pressMenuRow(
        statusElement: statusElement,
        appElement: appElement,
        rowIdentifier: "pdtbar.row.claudeSetup.login",
        expectedMenuIdentifiers: loginIDs,
        timeout: options.timeout
    )
    proofPayload.handoffScriptInvoked = waitForFile(marker, timeout: options.timeout)
    proofPayload.loginArgsIncluded = waitForFileContent(
        marker,
        contains: "auth login",
        timeout: options.timeout
    )
    proofPayload.openingStatusVisible = waitForStatusText(
        "Signing in with Claude",
        in: appElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout
    )
    let openingSurface = MenuBarSurfaceRenderer.render(descriptor: ClaudeLaunchFlow.descriptor(for: .openingClaude))
    let openingTargets = requiredSetupMenuTargets(in: openingSurface)
    let openingIDs = Set(openingTargets.map(\.accessibilityIdentifier))
    if let openingStatus = waitForAccessibilityElement(
        in: appElement,
        identifier: openingSurface.status.accessibilityIdentifier,
        timeout: min(options.timeout, 2.0)
    ) {
        let openingMenu = openStatusMenu(
            openingStatus,
            appElement: appElement,
            expectedMenuIdentifiers: openingIDs,
            timeout: min(options.timeout, 2.0)
        )
        if let openingSnapshot = openingMenu.snapshot,
           openingIDs.isSubset(of: openingSnapshot.identifiers),
           let screenshot = try? captureMenuScreenshot(
               name: "pdtbar-packaged-onboarding-opening",
               snapshot: openingSnapshot,
               expectedMenuIdentifiers: openingIDs,
               artifacts: artifacts,
               peekaboo: screenshotTool
           )
        {
            proofPayload.screenshotPaths.append(artifactPath(screenshot))
        }
    }
    pressEscape()
    Thread.sleep(forTimeInterval: 0.2)

    let completed = waitForFile(result, timeout: options.timeout + 3.0)
    proofPayload.readinessRechecked = waitForReadinessProbeCount(
        probeLog,
        expectedCount: 2,
        timeout: options.timeout + 4.0
    )
    proofPayload.readinessProbeCount = readinessProbeCount(in: probeLog)
    proofPayload.fetchingVisibleAfterReadiness = waitForStatusText(
        "Fetching portfolio",
        in: appElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout + 2.0
    )
    if proofPayload.fetchingVisibleAfterReadiness {
        proofPayload.postReadinessState = "fetchingPortfolio"
        pressEscape()
        Thread.sleep(forTimeInterval: 0.2)
        let fetchingSurface = MenuBarSurfaceRenderer.render(descriptor: ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio))
        let fetchingTargets = requiredSetupMenuTargets(in: fetchingSurface)
        let fetchingIDs = Set(fetchingTargets.map(\.accessibilityIdentifier))
        if let fetchingStatus = waitForAccessibilityElement(
            in: appElement,
            identifier: fetchingSurface.status.accessibilityIdentifier,
            timeout: min(options.timeout, 2.0)
        ) {
            let fetchingMenu = openStatusMenu(
                fetchingStatus,
                appElement: appElement,
                expectedMenuIdentifiers: fetchingIDs,
                timeout: min(options.timeout, 2.0)
            )
            if let fetchingSnapshot = fetchingMenu.snapshot,
               fetchingIDs.isSubset(of: fetchingSnapshot.identifiers),
               let screenshot = try? captureMenuScreenshot(
                   name: "pdtbar-packaged-onboarding-fetching",
                   snapshot: fetchingSnapshot,
                   expectedMenuIdentifiers: fetchingIDs,
                   artifacts: artifacts,
                   peekaboo: screenshotTool
               )
            {
                proofPayload.screenshotPaths.append(artifactPath(screenshot))
            }
        }
    }
    let firstFetchSnapshot = appSupportDirectory.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    proofPayload.firstFetchSnapshotWritten = waitForFile(
        firstFetchSnapshot,
        timeout: options.timeout + 6.0
    )
    proofPayload.fixtureSnapshotWritten = FileManager.default.fileExists(atPath: fixtureSnapshot.path)
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard proofPayload.setupMenuVisible,
          proofPayload.loginClickAttempt != nil,
          proofPayload.handoffScriptInvoked,
          proofPayload.loginArgsIncluded,
          completed,
          proofPayload.openingStatusVisible,
          proofPayload.readinessRechecked,
          proofPayload.readinessProbeCount >= 2,
          proofPayload.fetchingVisibleAfterReadiness,
          proofPayload.firstFetchSnapshotWritten,
          !proofPayload.fixtureSnapshotWritten
    else {
        return SmokeReport(
            name: "packaged-onboarding",
            status: SmokeStatus.failed,
            detail: "packaged onboarding did not prove setup click, scripted handoff success, readiness recheck, and post-recheck first fetch",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "packaged-onboarding",
        status: SmokeStatus.passed,
        detail: "packaged PDTBar.app no-argument onboarding ignored fixture env, opened setup through Accessibility, clicked Log in with Claude, rechecked readiness, and started scripted first fetch",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedSetupRetrySmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "scripted-setup-retry",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-setup-retry-proof.json")
    let missingLoginDescriptor = ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)
    let missingPDTMCPDescriptor = ClaudeLaunchFlow.descriptor(for: .missingPDTMCP)
    let gate = ClaudeReadinessProbeGate()
    let gateFirstBegin = gate.begin()
    let gateRejectedDuplicate = !gate.begin()
    gate.finish()
    let gateRetryBegin = gate.begin()
    gate.finish()

    var proofPayload = ScriptedSetupRetryProof(
        missingLoginRows: missingLoginDescriptor.sections.flatMap(\.rows).map(\.title),
        missingPDTMCPRows: missingPDTMCPDescriptor.sections.flatMap(\.rows).map(\.title),
        gateRejectedDuplicateProbe: gateFirstBegin && gateRejectedDuplicate && gateRetryBegin,
        scenarios: [],
        rawClaudeCredentialsUsed: false,
        rawPortfolioPayloadsRedacted: true
    )

    guard AXIsProcessTrusted() else {
        try stableJSONData(proofPayload).write(to: proof, options: .atomic)
        return SmokeReport(
            name: "scripted-setup-retry",
            status: SmokeStatus.skipped,
            detail: "macOS Accessibility permission missing for Check again menu-click proof; descriptor and duplicate-probe gate proof written",
            artifacts: [artifactPath(proof)]
        )
    }

    let missingLoginScenario = try scriptedSetupRetryScenario(
        name: "missing-claude-login",
        initialReadiness: "missingClaudeLogin",
        descriptor: missingLoginDescriptor,
        expectedTexts: ["Not connected", "Log in with Claude", "Check again"],
        options: options,
        app: app,
        artifacts: artifacts
    )
    let missingPDTMCPScenario = try scriptedSetupRetryScenario(
        name: "missing-pdt-mcp",
        initialReadiness: "missingPDTMCP",
        descriptor: missingPDTMCPDescriptor,
        expectedTexts: ["Add the PDT MCP server to Claude", "Log in with Claude", "Check again"],
        options: options,
        app: app,
        artifacts: artifacts
    )
    proofPayload.scenarios = [missingLoginScenario, missingPDTMCPScenario]
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard proofPayload.gateRejectedDuplicateProbe,
          proofPayload.scenarios.allSatisfy(\.passed)
    else {
        return SmokeReport(
            name: "scripted-setup-retry",
            status: SmokeStatus.failed,
            detail: "scripted setup retry did not prove both missing setup states and Check again readiness retry",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "scripted-setup-retry",
        status: SmokeStatus.passed,
        detail: "missing Claude login and missing PDT MCP rendered retryable setup states; Check again reran readiness once and reached first fetch with redacted scripted data",
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
    let clickedPayload = try require(markReadAction.actionPayload, "Mark as read action should carry fingerprint")
    try readStore.markRead(clickedPayload)
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
    let payloadMatchesFirstItem = clickedPayload == firstItem.readFingerprint
    let afterClickHidden = afterClickPulse.descriptor.statusBadge == nil
        && afterClickPulse.descriptor.statusTitle.contains("All caught up")
        && afterClickPulse.source == .cachedSnapshot
    let relaunchHidden = relaunchPulse.descriptor.statusBadge == nil
        && relaunchPulse.descriptor.statusTitle.contains("All caught up")
        && relaunchPulse.source == .cachedSnapshot
    let changedResurfaced = resurfacedItem?.holdingIdentity?.quoteId == firstItem.holdingIdentity?.quoteId
        && resurfacedItem?.readFingerprint != clickedPayload
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

private func scriptedFirstFetchSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.resolvedAppExecutable(defaultExecutable: packageRoot.appending(path: ".build/debug/pdtbar"))
    guard FileManager.default.isExecutableFile(atPath: app.path) else {
        return SmokeReport(
            name: "scripted-first-fetch",
            status: SmokeStatus.failed,
            detail: "app executable missing; run swift build --product pdtbar first or pass --app <path>",
            artifacts: []
        )
    }

    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    let proof = artifacts.appending(path: "pdtbar-scripted-first-fetch-proof.json")
    let responses = try scriptedPDTConnectorResponses()
    let responseStrings = responses.mapValues { String(decoding: $0, as: UTF8.self) }
    let completeConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: responseStrings,
        asOf: "2026-03-29"
    )
    let expectedStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-first-fetch-expected")
    defer {
        try? FileManager.default.removeItem(at: expectedStore.directory)
    }
    let expectedRun = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: completeConfiguration.connector()),
        snapshotStore: expectedStore,
        asOf: completeConfiguration.asOf
    ).fetch()
    let expectedSurface = MenuBarSurfaceRenderer.render(descriptor: expectedRun.descriptor)

    let missingConfiguration = ScriptedPDTMCPConnectorConfiguration(
        availableTools: PDTReadTools.requiredV1.filter { $0 != "pdt-list-dividends" },
        responses: responseStrings,
        asOf: "2026-03-29"
    )
    let missingDirectStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-first-fetch-missing")
    defer {
        try? FileManager.default.removeItem(at: missingDirectStore.directory)
    }
    let missingDirectBlocked: Bool
    do {
        _ = try PDTCoalescedFirstPortfolioFetch(
            dataSource: PDTMCPConnectorDataSource(connector: missingConfiguration.connector()),
            snapshotStore: missingDirectStore,
            asOf: missingConfiguration.asOf
        ).fetch()
        missingDirectBlocked = false
    } catch PDTMCPConnectorError.missingRequiredReadTools(let missing) {
        missingDirectBlocked = missing == ["pdt-list-dividends"]
            && !FileManager.default.fileExists(
                atPath: missingDirectStore.directory.appending(path: "latest-portfolio-snapshot.json").path
            )
    }

    let successAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-first-fetch-success-app-support")
    try writeFirstFetchAppScript(
        configuration: completeConfiguration,
        appSupportDirectory: successAppSupport
    )
    let successFixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-first-fetch-success-fixture-sentinel")
    let successFixtureSnapshot = successFixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let successStateDirectory = successAppSupport.appending(path: "pdtbar/state")
    let successSnapshot = successStateDirectory.appending(path: "latest-portfolio-snapshot.json")
    let successProcess = try launchFirstFetchApp(
        app,
        appSupportDirectory: successAppSupport,
        fixtureSnapshotDirectory: successFixtureSnapshotDirectory
    )
    defer {
        terminate(successProcess)
    }
    let successSnapshotWritten = waitForFile(successSnapshot, timeout: options.timeout)
    guard successProcess.isRunning,
          successSnapshotWritten,
          !FileManager.default.fileExists(atPath: successFixtureSnapshot.path)
    else {
        return SmokeReport(
            name: "scripted-first-fetch",
            status: SmokeStatus.failed,
            detail: "complete scripted first fetch did not stay running, write isolated state, or avoid fixture state",
            artifacts: [artifactPath(successAppSupport), artifactPath(successFixtureSnapshotDirectory)]
        )
    }
    let publishedSnapshot = try JSONDecoder().decode(
        PortfolioSnapshot.self,
        from: Data(contentsOf: successSnapshot)
    )
    let accessibilityChecked = AXIsProcessTrusted()
    var successAXVisible = false
    var axArtifacts: [String] = []
    if accessibilityChecked {
        let appElement = AXUIElementCreateApplication(successProcess.processIdentifier)
        if let statusElement = waitForAccessibilityElement(
            in: appElement,
            identifier: expectedSurface.status.accessibilityIdentifier,
            timeout: options.timeout
        ) {
            let targets = requiredPulseMenuTargets(in: expectedSurface)
            let openedMenu = openStatusMenu(
                statusElement,
                appElement: appElement,
                expectedMenuIdentifiers: Set(targets.map(\.accessibilityIdentifier)),
                timeout: options.timeout
            )
            if let snapshot = openedMenu.snapshot {
                let evidence = artifacts.appending(path: "pdtbar-scripted-first-fetch-success-ax.json")
                try writeAccessibilityEvidence(
                    snapshot: snapshot,
                    expected: targets,
                    statusIdentifier: expectedSurface.status.accessibilityIdentifier,
                    statusText: accessibilityTexts(in: statusElement),
                    output: evidence
                )
                axArtifacts.append(artifactPath(evidence))
                successAXVisible = Set(targets.map(\.accessibilityIdentifier)).isSubset(of: snapshot.identifiers)
            }
        }
    }
    terminate(successProcess)

    let failureAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-first-fetch-failure-app-support")
    try writeFirstFetchAppScript(
        configuration: missingConfiguration,
        appSupportDirectory: failureAppSupport
    )
    let failureFixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-first-fetch-failure-fixture-sentinel")
    let failureFixtureSnapshot = failureFixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let failureSnapshot = failureAppSupport.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    let failureProcess = try launchFirstFetchApp(
        app,
        appSupportDirectory: failureAppSupport,
        fixtureSnapshotDirectory: failureFixtureSnapshotDirectory
    )
    defer {
        terminate(failureProcess)
    }
    Thread.sleep(forTimeInterval: options.timeout)
    let missingToolPreventedPublication = failureProcess.isRunning
        && missingDirectBlocked
        && !FileManager.default.fileExists(atPath: failureSnapshot.path)
        && !FileManager.default.fileExists(atPath: failureFixtureSnapshot.path)
    var failureAXVisible = false
    if accessibilityChecked {
        let expectedFailureSurface = MenuBarSurfaceRenderer.render(
            descriptor: ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed)
        )
        let appElement = AXUIElementCreateApplication(failureProcess.processIdentifier)
        if let statusElement = waitForAccessibilityElement(
            in: appElement,
            identifier: expectedFailureSurface.status.accessibilityIdentifier,
            timeout: options.timeout
        ) {
            let targets = requiredSetupMenuTargets(in: expectedFailureSurface)
            let openedMenu = openStatusMenu(
                statusElement,
                appElement: appElement,
                expectedMenuIdentifiers: Set(targets.map(\.accessibilityIdentifier)),
                timeout: options.timeout
            )
            if let snapshot = openedMenu.snapshot {
                let evidence = artifacts.appending(path: "pdtbar-scripted-first-fetch-failure-ax.json")
                try writeAccessibilityEvidence(
                    snapshot: snapshot,
                    expected: targets,
                    statusIdentifier: expectedFailureSurface.status.accessibilityIdentifier,
                    statusText: accessibilityTexts(in: statusElement),
                    output: evidence
                )
                axArtifacts.append(artifactPath(evidence))
                failureAXVisible = Set(targets.map(\.accessibilityIdentifier)).isSubset(of: snapshot.identifiers)
            }
        }
    }

    let proofPayload = ScriptedFirstFetchProof(
        snapshotPath: artifactPath(successSnapshot),
        snapshotWritten: successSnapshotWritten,
        snapshotAsOf: publishedSnapshot.asOf,
        openHoldingCount: publishedSnapshot.openHoldings.count,
        expectedRenderedSectionIDs: expectedRun.descriptor.sections.map(\.id),
        missingRequiredToolBlockedPublication: missingToolPreventedPublication,
        accessibilityChecked: accessibilityChecked,
        successPulseVisibleThroughAccessibility: successAXVisible,
        failureVisibleThroughAccessibility: failureAXVisible,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard successSnapshotWritten,
          publishedSnapshot.openHoldings.count > 0,
          expectedRun.descriptor.sections.map(\.id).contains("pulse"),
          missingToolPreventedPublication,
          !accessibilityChecked || (successAXVisible && failureAXVisible)
    else {
        return SmokeReport(
            name: "scripted-first-fetch",
            status: SmokeStatus.failed,
            detail: "scripted first-fetch did not prove complete publication and required-tool blocking",
            artifacts: [artifactPath(proof)] + axArtifacts
        )
    }

    return SmokeReport(
        name: "scripted-first-fetch",
        status: SmokeStatus.passed,
        detail: "complete scripted first fetch wrote isolated state and produced the pulse descriptor; missing required tool wrote no snapshot and published no pulse",
        artifacts: [artifactPath(proof)] + axArtifacts
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
    let responses = try scriptedPDTConnectorResponses()
    let responseStrings = responses.mapValues { String(decoding: $0, as: UTF8.self) }
    let staleSnapshot = try PDTFixtureDataSource(fixture: defaultFixture).snapshot(asOf: "2026-03-28")
    let cachedDescriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: staleSnapshot))
    let refreshDelay = max(options.timeout * 5, 10.0)
    let refreshConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: responseStrings,
        asOf: "2026-03-29",
        initialCallDelaySeconds: refreshDelay
    )
    let expectedFreshStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-returning-launch-expected")
    defer {
        try? FileManager.default.removeItem(at: expectedFreshStore.directory)
    }
    _ = try expectedFreshStore.commitCurrentSnapshot(staleSnapshot)
    let expectedFreshConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: responseStrings,
        asOf: refreshConfiguration.asOf
    )
    let expectedFreshRun = try PDTBackgroundDetailRefresh(
        connector: expectedFreshConfiguration.connector(),
        snapshotStore: expectedFreshStore,
        asOf: expectedFreshConfiguration.asOf
    ).refresh()

    let successAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-returning-launch-success-app-support")
    let successStore = SnapshotStore(directory: successAppSupport.appending(path: "pdtbar/state"))
    let successSeed = try successStore.commitCurrentSnapshot(staleSnapshot)
    try writeFirstFetchAppScript(configuration: refreshConfiguration, appSupportDirectory: successAppSupport)
    let successFixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-returning-launch-success-fixture-sentinel")
    let successFixtureSnapshot = successFixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let successSnapshot = successStore.directory.appending(path: "latest-portfolio-snapshot.json")
    let successProcess = try launchFirstFetchApp(
        app,
        appSupportDirectory: successAppSupport,
        fixtureSnapshotDirectory: successFixtureSnapshotDirectory,
        scriptedBackgroundRefresh: true
    )
    defer {
        terminate(successProcess)
    }

    guard successProcess.isRunning,
          snapshotAsOf(successSnapshot) == staleSnapshot.asOf,
          !FileManager.default.fileExists(atPath: successFixtureSnapshot.path)
    else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "returning launch did not start with the seeded local snapshot preserved",
            artifacts: [artifactPath(URL(fileURLWithPath: successSeed.path))]
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
            descriptor: ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
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
                && snapshot.texts.contains("Step 1/5: Base holdings")
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

    let failureConfiguration = ScriptedPDTMCPConnectorConfiguration(
        responses: responseStrings,
        asOf: "2026-03-29",
        failure: "transientFailure",
        failureMessage: "Claude call timed out"
    )
    let failureAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-returning-launch-failure-app-support")
    let failureStore = SnapshotStore(directory: failureAppSupport.appending(path: "pdtbar/state"))
    _ = try failureStore.commitCurrentSnapshot(staleSnapshot)
    try writeFirstFetchAppScript(configuration: failureConfiguration, appSupportDirectory: failureAppSupport)
    let failureFixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-returning-launch-failure-fixture-sentinel")
    let failureFixtureSnapshot = failureFixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let failureSnapshot = failureStore.directory.appending(path: "latest-portfolio-snapshot.json")
    let failureProcess = try launchFirstFetchApp(
        app,
        appSupportDirectory: failureAppSupport,
        fixtureSnapshotDirectory: failureFixtureSnapshotDirectory,
        scriptedBackgroundRefresh: true
    )
    defer {
        terminate(failureProcess)
    }
    Thread.sleep(forTimeInterval: options.timeout)
    let failurePreservedSnapshot = failureProcess.isRunning
        && snapshotAsOf(failureSnapshot) == staleSnapshot.asOf
        && !FileManager.default.fileExists(atPath: failureFixtureSnapshot.path)

    if accessibilityChecked {
        let failureSurface = MenuBarSurfaceRenderer.render(
            descriptor: ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(cachedPulse: cachedDescriptor)
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
                    && !snapshot.texts.contains("Log in with Claude")
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

private func realUserPulseSmoke(arguments: [String]) throws -> SmokeReport {
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
    process.environment = ProcessInfo.processInfo.environment.merging(["PDTBAR_FIXTURE_MODE": "1"]) { _, new in new }
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
    let screenshot = try? captureRealUserMenuScreenshot(
        snapshot: menuSnapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )
    let freshnessScreenshot = try? captureFreshnessDetailScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )
    let attentionScreenshot = try? captureAttentionExplanationScreenshot(
        snapshot: menuSnapshot,
        artifacts: artifacts,
        peekaboo: screenshotPeekaboo
    )
    let priorDetail = expectedScenario.seededPrior.map { "; seeded prior snapshot \($0.asOf)" } ?? ""
    let screenshotDetail = screenshot == nil ? "" : "; captured menu screenshot"
    let freshnessScreenshotDetail = freshnessScreenshot == nil ? "" : "; captured freshness detail screenshot"
    let attentionScreenshotDetail = attentionScreenshot == nil ? "" : "; captured attention explanation screenshot"
    let reportArtifacts = [artifactPath(evidence)]
        + (screenshot.map { [artifactPath($0)] } ?? [])
        + (freshnessScreenshot.map { [artifactPath($0)] } ?? [])
        + (attentionScreenshot.map { [artifactPath($0)] } ?? [])
    return SmokeReport(
        name: "real-user-pulse",
        status: SmokeStatus.passed,
        detail: "launched fixture-mode app with isolated state\(priorDetail), opened menu-bar pulse through \(openedMenu.successfulAttempt ?? "Accessibility"), verified status plus pulse/allocation/income/big-mover/freshness selectors for \(fixture.lastPathComponent)\(screenshotDetail)\(freshnessScreenshotDetail)\(attentionScreenshotDetail)",
        artifacts: reportArtifacts
    )
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
        MenuProofCard(title: "Setup", descriptor: ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)),
        MenuProofCard(title: "Fetching", descriptor: ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio)),
        MenuProofCard(title: "All quiet", descriptor: quietDescriptor),
        MenuProofCard(title: "Pressure", descriptor: pressureDescriptor),
        MenuProofCard(title: "Error", descriptor: ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed)),
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
    let requiredSectionIDs = ["pulse", "allocation", "income", "bigMovers", "freshness"]
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
    var expected: [PulseTargetEvidence]
    var observedIdentifiers: [String]
    var observedFramesByIdentifier: [String: AccessibilityFrame]
    var observedTexts: [String]
}

private struct LivePDTPulseProof: Codable {
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

private struct ScriptedFirstFetchProof: Codable {
    var snapshotPath: String
    var snapshotWritten: Bool
    var snapshotAsOf: String
    var openHoldingCount: Int
    var expectedRenderedSectionIDs: [String]
    var missingRequiredToolBlockedPublication: Bool
    var accessibilityChecked: Bool
    var successPulseVisibleThroughAccessibility: Bool
    var failureVisibleThroughAccessibility: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct ScriptedSetupRetryProof: Codable {
    var missingLoginRows: [String]
    var missingPDTMCPRows: [String]
    var gateRejectedDuplicateProbe: Bool
    var scenarios: [ScriptedSetupRetryScenarioProof]
    var rawClaudeCredentialsUsed: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct ScriptedSetupRetryScenarioProof: Codable {
    var name: String
    var initialStatusVisible: Bool
    var initialMenuVisible: Bool
    var retryClickAttempt: String?
    var readinessProbeCount: Int
    var firstFetchSnapshotWritten: Bool
    var firstFetchAsOf: String?
    var fixtureSnapshotWritten: Bool
    var passed: Bool
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

private struct ScriptedLoginHandoffProof: Codable {
    var successIdleBeforeClick: Bool
    var successInitialReadinessProbed: Bool
    var successClickAttempt: String?
    var successScriptInvoked: Bool
    var successLoginArgsIncluded: Bool
    var successProgressVisible: Bool
    var successProgressRetryVisible: Bool
    var successProgressMenuOpenAttempt: String?
    var successProgressObservedIdentifiers: [String]
    var successProgressObservedTexts: [String]
    var successRetryClickAttempt: String?
    var successRetryInvoked: Bool
    var successSupersededAttemptTerminated: Bool
    var successStoppedAfterOutput: Bool
    var successCompleted: Bool
    var successReadinessRechecked: Bool
    var successReadinessProbeCount: Int
    var successFetchingVisible: Bool
    var successFirstFetchSnapshotWritten: Bool
    var successFirstFetchAsOf: String?
    var failureIdleBeforeClick: Bool
    var failureClickAttempt: String?
    var failureScriptInvoked: Bool
    var failureLoginArgsIncluded: Bool
    var failureCompleted: Bool
    var failureMissingClaudeStatusVisible: Bool
    var failureMissingClaudeMenuVisible: Bool
    var failureMissingClaudeOpenAttempt: String?
    var failureMissingClaudeObservedIdentifiers: [String]
    var failureMissingClaudeObservedTexts: [String]
    var rawClaudeCredentialsUsed: Bool
}

private struct PackagedOnboardingProof: Codable {
    var appBundlePath: String
    var appExecutablePath: String
    var appArguments: [String]
    var appSupportPath: String
    var fixtureSnapshotPath: String
    var fixtureEnvInjected: Bool
    var fixtureSnapshotWritten: Bool
    var accessibilityChecked: Bool
    var setupMenuVisible: Bool
    var loginClickAttempt: String?
    var handoffScriptInvoked: Bool
    var loginArgsIncluded: Bool
    var openingStatusVisible: Bool
    var readinessProbeCount: Int
    var readinessRechecked: Bool
    var fetchingVisibleAfterReadiness: Bool
    var firstFetchSnapshotWritten: Bool
    var postReadinessState: String?
    var expectedSelectors: [String]
    var observedSelectors: [String]
    var observedStatusText: [String]
    var screenshotPaths: [String]
    var rawClaudeCredentialsUsed: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct RealClaudeFlowAXProof: Codable {
    var appArguments: [String]
    var fixtureModeUsed: Bool
    var scenarios: [RealClaudeFlowAXScenarioProof]
    var rawClaudeCredentialsUsed: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct RealClaudeFlowAXScenarioProof: Codable {
    var name: String
    var statusIdentifier: String
    var expectedMenuIdentifiers: [String]
    var observedStatusText: [String]
    var observedMenuTexts: [String]
    var observedMenuIdentifiers: [String]
    var openedMenuVia: String?
    var snapshotAsOf: String?
    var fixtureSnapshotWritten: Bool
    var evidencePath: String
    var passed: Bool
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

private func captureRealUserMenuScreenshot(
    snapshot: AccessibilitySnapshot,
    expectedMenuIdentifiers: Set<String>,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    try captureMenuScreenshot(
        name: "pdtbar-real-user-pulse",
        snapshot: snapshot,
        expectedMenuIdentifiers: expectedMenuIdentifiers,
        artifacts: artifacts,
        peekaboo: peekaboo
    )
}

private func captureFreshnessDetailScreenshot(
    snapshot: AccessibilitySnapshot,
    artifacts: URL,
    peekaboo: URL?
) throws -> URL? {
    guard let peekaboo,
          let freshnessRect = snapshot.framesByIdentifier["pdtbar.row.freshness.summary"]?.rect,
          !freshnessRect.isNull,
          !freshnessRect.isEmpty
    else {
        return nil
    }
    moveMouse(to: CGPoint(x: freshnessRect.maxX - 24, y: freshnessRect.midY))
    Thread.sleep(forTimeInterval: 0.6)

    let display = displayBounds(containing: freshnessRect)
    let padded = CGRect(
        x: max(display.minX, freshnessRect.minX - 520),
        y: max(display.minY, freshnessRect.minY - 96),
        width: min(display.width, freshnessRect.width + 600),
        height: min(display.height, 360)
    ).intersection(display).integral
    guard !padded.isNull, !padded.isEmpty else {
        return nil
    }

    let screenshot = artifacts.appending(path: "pdtbar-real-user-pulse-freshness-detail.png")
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
    let menuBounds = menuFrameBounds(snapshot: snapshot, expectedMenuIdentifiers: expectedMenuIdentifiers)
        ?? statusMenuFallbackBounds(snapshot: snapshot)
    let captureBounds = screenshotCaptureBounds(containing: menuBounds)
    let displayRegion = "\(Int(captureBounds.minX)),\(Int(captureBounds.minY)),\(Int(captureBounds.width)),\(Int(captureBounds.height))"
    _ = try run(
        peekaboo,
        arguments: [
            "image",
            "--mode", "area",
            "--region", displayRegion,
            "--path", rawScreenshot.path,
            "--json",
            "--no-remote",
        ],
        timeout: 20
    )
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
    guard let peekaboo else {
        return nil
    }
    let screenshot = artifacts.appending(path: "\(name).png")
    do {
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
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
    let status = snapshot.framesByIdentifier["pdtbar.status"].flatMap { validRect($0.rect) }
    let display = displayBounds(containing: status)
    let width = min(display.width, status == nil ? 900 : 560)
    let x = display.maxX - width
    let y = min(max(display.minY, (status?.maxY ?? display.minY + 44) + 2), display.maxY)
    let height = status == nil ? min(display.maxY - y, 1280) : min(display.maxY - y, 88)
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

private enum RealClaudeFlowAXTargetMode {
    case setup
    case pulse
}

private func realClaudeFlowAXScenario(
    name: String,
    app: URL,
    options: SmokeOptions,
    artifacts: URL,
    readiness: String?,
    configuration: ScriptedPDTMCPConnectorConfiguration?,
    descriptor: MenuDescriptor,
    targetMode: RealClaudeFlowAXTargetMode,
    expectedTexts: Set<String>,
    expectedSnapshotAsOf: String? = nil
) throws -> RealClaudeFlowAXScenarioProof {
    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "real-claude-flow-\(name)-app-support")
    let fixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "real-claude-flow-\(name)-fixture-sentinel")
    let fixtureSnapshot = fixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    if let configuration {
        try writeFirstFetchAppScript(configuration: configuration, appSupportDirectory: appSupportDirectory)
    } else if let readiness {
        try writeReadinessScript(result: readiness, appSupportDirectory: appSupportDirectory)
    }

    let process = try launchFirstFetchApp(
        app,
        appSupportDirectory: appSupportDirectory,
        fixtureSnapshotDirectory: fixtureSnapshotDirectory
    )
    defer {
        terminate(process)
    }

    let stateSnapshot = appSupportDirectory.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    if let expectedSnapshotAsOf {
        _ = waitForSnapshotAsOf(
            stateSnapshot,
            asOf: expectedSnapshotAsOf,
            timeout: options.timeout + 3.0
        )
    }

    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let expectedTargets: [PulseTarget]
    switch targetMode {
    case .setup:
        expectedTargets = requiredSetupMenuTargets(in: surface)
    case .pulse:
        expectedTargets = requiredPulseMenuTargets(in: surface)
    }
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    let expectedStatusTextVisible = waitForStatusText(
        surface.status.accessibilityLabel,
        in: appElement,
        statusIdentifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout + 1.0
    )
    let statusElement = waitForAccessibilityElement(
        in: appElement,
        identifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout + 1.0
    )
    let statusText = statusElement.map(accessibilityTexts) ?? []
    let openedMenu: OpenMenuResult
    let menuSnapshot: AccessibilitySnapshot
    if let statusElement {
        openedMenu = openStatusMenu(
            statusElement,
            appElement: appElement,
            expectedMenuIdentifiers: expectedMenuIdentifiers,
            timeout: options.timeout + 1.0
        )
        menuSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
            expectedMenuIdentifiers,
            in: appElement,
            timeout: options.timeout
        )
    } else {
        openedMenu = OpenMenuResult(snapshot: nil, successfulAttempt: nil, attempts: ["status item missing"])
        menuSnapshot = accessibilitySnapshot(in: appElement)
    }

    let evidence = artifacts.appending(path: "pdtbar-real-claude-flow-\(name)-ax.json")
    try writeAccessibilityEvidence(
        snapshot: menuSnapshot,
        expected: expectedTargets,
        statusIdentifier: surface.status.accessibilityIdentifier,
        statusText: statusText,
        output: evidence
    )

    let statusVisible = expectedStatusTextVisible
        && statusText.contains { observed in
            observed == surface.status.accessibilityLabel ||
                observed == surface.status.title ||
                observed.hasPrefix("\(surface.status.accessibilityLabel) ") ||
                observed.hasPrefix("\(surface.status.title) ")
        }
    let menuIdentifiersVisible = expectedMenuIdentifiers.isSubset(of: menuSnapshot.identifiers)
    let menuTextVisible = expectedTexts.allSatisfy { expected in
        menuSnapshot.texts.contains { observed in
            observed.contains(expected)
        }
    }
    let snapshotMatches = expectedSnapshotAsOf.map { snapshotAsOf(stateSnapshot) == $0 } ?? true
    let fixtureSnapshotWritten = FileManager.default.fileExists(atPath: fixtureSnapshot.path)
    return RealClaudeFlowAXScenarioProof(
        name: name,
        statusIdentifier: surface.status.accessibilityIdentifier,
        expectedMenuIdentifiers: expectedMenuIdentifiers.sorted(),
        observedStatusText: statusText.sorted(),
        observedMenuTexts: menuSnapshot.texts.sorted(),
        observedMenuIdentifiers: menuSnapshot.identifiers.sorted(),
        openedMenuVia: openedMenu.successfulAttempt,
        snapshotAsOf: snapshotAsOf(stateSnapshot),
        fixtureSnapshotWritten: fixtureSnapshotWritten,
        evidencePath: artifactPath(evidence),
        passed: process.isRunning
            && statusElement != nil
            && statusVisible
            && menuIdentifiersVisible
            && menuTextVisible
            && snapshotMatches
            && !fixtureSnapshotWritten
    )
}

private func scriptedSetupRetryScenario(
    name: String,
    initialReadiness: String,
    descriptor: MenuDescriptor,
    expectedTexts: Set<String>,
    options: SmokeOptions,
    app: URL,
    artifacts: URL
) throws -> ScriptedSetupRetryScenarioProof {
    let appSupportDirectory = try options.isolatedAppSupportDirectory(prefix: "scripted-setup-retry-\(name)-app-support")
    let fixtureSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "scripted-setup-retry-\(name)-fixture-sentinel")
    let fixtureSnapshot = fixtureSnapshotDirectory.appending(path: "latest-portfolio-snapshot.json")
    let probeLog = appSupportDirectory.appending(path: "pdtbar/readiness-probes.log")
    try writeReadinessScript(result: initialReadiness, appSupportDirectory: appSupportDirectory)
    let process = try launchSetupRetryApp(
        app,
        appSupportDirectory: appSupportDirectory,
        fixtureSnapshotDirectory: fixtureSnapshotDirectory,
        probeLog: probeLog
    )
    defer {
        terminate(process)
    }

    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let expectedTargets = requiredSetupMenuTargets(in: surface)
    let expectedIDs = Set(expectedTargets.map(\.accessibilityIdentifier))
    let appElement = AXUIElementCreateApplication(process.processIdentifier)
    let initialStatusVisible = waitForStatusText(
        descriptor.statusTitle,
        in: appElement,
        statusIdentifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout
    )
    var initialMenuVisible = false
    var retryClickAttempt: String?
    if let status = waitForAccessibilityElement(
        in: appElement,
        identifier: surface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) {
        let openedMenu = openStatusMenu(
            status,
            appElement: appElement,
            expectedMenuIdentifiers: expectedIDs,
            timeout: options.timeout
        )
        let menuSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
            expectedIDs,
            in: appElement,
            timeout: options.timeout
        )
        let evidence = artifacts.appending(path: "pdtbar-scripted-setup-retry-\(name)-ax.json")
        try writeAccessibilityEvidence(
            snapshot: menuSnapshot,
            expected: expectedTargets,
            statusIdentifier: surface.status.accessibilityIdentifier,
            statusText: accessibilityTexts(in: status),
            output: evidence
        )
        initialMenuVisible = expectedIDs.isSubset(of: menuSnapshot.identifiers)
            && expectedTexts.allSatisfy { expected in
                menuSnapshot.texts.contains { observed in
                    observed.contains(expected)
                }
            }

        let configuration = ScriptedPDTMCPConnectorConfiguration(
            responses: try scriptedPDTConnectorResponses().mapValues { String(decoding: $0, as: UTF8.self) },
            asOf: "2026-03-29"
        )
        try writeFirstFetchAppScript(configuration: configuration, appSupportDirectory: appSupportDirectory)
        retryClickAttempt = pressMenuRow(
            statusElement: status,
            appElement: appElement,
            rowIdentifier: "pdtbar.row.claudeSetup.retry",
            expectedMenuIdentifiers: expectedIDs,
            timeout: options.timeout
        )
    }

    let firstFetchSnapshot = appSupportDirectory.appending(path: "pdtbar/state/latest-portfolio-snapshot.json")
    let firstFetchSnapshotWritten = waitForSnapshotAsOf(
        firstFetchSnapshot,
        asOf: "2026-03-29",
        timeout: options.timeout + 3.0
    )
    let firstFetchAsOf = snapshotAsOf(firstFetchSnapshot)
    let probeCount = readinessProbeCount(in: probeLog)
    let fixtureSnapshotWritten = FileManager.default.fileExists(atPath: fixtureSnapshot.path)
    return ScriptedSetupRetryScenarioProof(
        name: name,
        initialStatusVisible: initialStatusVisible,
        initialMenuVisible: initialMenuVisible,
        retryClickAttempt: retryClickAttempt,
        readinessProbeCount: probeCount,
        firstFetchSnapshotWritten: firstFetchSnapshotWritten,
        firstFetchAsOf: firstFetchAsOf,
        fixtureSnapshotWritten: fixtureSnapshotWritten,
        passed: initialStatusVisible
            && initialMenuVisible
            && retryClickAttempt != nil
            && probeCount == 2
            && firstFetchSnapshotWritten
            && firstFetchAsOf == "2026-03-29"
            && !fixtureSnapshotWritten
    )
}

private func writeReadinessScript(result: String, appSupportDirectory: URL) throws {
    let directory = appSupportDirectory.appending(path: "pdtbar")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = #"{"result":"\#(result)"}"#
    try Data(payload.utf8).write(
        to: directory.appending(path: "claude-readiness.json"),
        options: .atomic
    )
}

private func writeFirstFetchAppScript(
    configuration: ScriptedPDTMCPConnectorConfiguration,
    appSupportDirectory: URL
) throws {
    let directory = appSupportDirectory.appending(path: "pdtbar")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"result":"ready"}"#.utf8).write(
        to: directory.appending(path: "claude-readiness.json"),
        options: .atomic
    )
    try stableJSONData(configuration).write(
        to: directory.appending(path: "scripted-pdt-mcp.json"),
        options: .atomic
    )
}

private func launchSetupRetryApp(
    _ app: URL,
    appSupportDirectory: URL,
    fixtureSnapshotDirectory: URL,
    probeLog: URL
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSnapshotDirectory.path,
        "PDTBAR_CLAUDE_READINESS_LOG": probeLog.path,
    ]) { _, new in new }
    try process.run()
    return process
}

private func launchFirstFetchApp(
    _ app: URL,
    appSupportDirectory: URL,
    fixtureSnapshotDirectory: URL,
    scriptedBackgroundRefresh: Bool = false
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSnapshotDirectory.path,
        "PDTBAR_SCRIPTED_BACKGROUND_REFRESH": scriptedBackgroundRefresh ? "1" : "0",
    ]) { _, new in new }
    try process.run()
    return process
}

private func readinessProbeCount(in log: URL) -> Int {
    guard let content = try? String(contentsOf: log, encoding: .utf8) else {
        return 0
    }
    return content
        .split(separator: "\n")
        .filter { $0 == "probe" }
        .count
}

private func waitForReadinessProbeCount(_ log: URL, expectedCount: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if readinessProbeCount(in: log) >= expectedCount {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return readinessProbeCount(in: log) >= expectedCount
}

private func handoffInvocationCount(in log: URL) -> Int {
    guard let content = try? String(contentsOf: log, encoding: .utf8) else {
        return 0
    }
    return content
        .split(separator: "\n")
        .filter { $0.hasPrefix("started ") }
        .count
}

private func waitForHandoffInvocationCount(_ log: URL, expectedCount: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if handoffInvocationCount(in: log) >= expectedCount {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return handoffInvocationCount(in: log) >= expectedCount
}

private func handoffTerminationCount(in log: URL) -> Int {
    guard let content = try? String(contentsOf: log, encoding: .utf8) else {
        return 0
    }
    return content
        .split(separator: "\n")
        .filter { $0.hasPrefix("terminated ") }
        .count
}

private func waitForHandoffTerminationCount(_ log: URL, expectedCount: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if handoffTerminationCount(in: log) >= expectedCount {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return handoffTerminationCount(in: log) >= expectedCount
}

private func launchLoginHandoffApp(
    _ app: URL,
    appSupportDirectory: URL,
    handoffScript: URL,
    marker: URL,
    result: URL,
    resultValue: String,
    probeLog: URL? = nil
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    var scriptedEnvironment = [
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_CLAUDE_BIN": handoffScript.path,
        "PDTBAR_CLAUDE_HANDOFF_MARKER": marker.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT": result.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE": resultValue,
        "PDTBAR_DISABLE_REAL_CLAUDE": "1",
    ]
    if let probeLog {
        scriptedEnvironment["PDTBAR_CLAUDE_READINESS_LOG"] = probeLog.path
    }
    process.environment = environment.merging(scriptedEnvironment) { _, new in new }
    try process.run()
    return process
}

private func launchPackagedOnboardingApp(
    _ app: URL,
    appSupportDirectory: URL,
    fixtureSnapshotDirectory: URL,
    handoffScript: URL,
    marker: URL,
    result: URL,
    probeLog: URL
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_FIXTURE": defaultFixture.path,
        "PDTBAR_SNAPSHOT_DIR": fixtureSnapshotDirectory.path,
        "PDTBAR_CLAUDE_BIN": handoffScript.path,
        "PDTBAR_CLAUDE_HANDOFF_MARKER": marker.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT": result.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE": "success",
        "PDTBAR_CLAUDE_READINESS_LOG": probeLog.path,
        "PDTBAR_DISABLE_REAL_CLAUDE": "1",
    ]) { _, new in new }
    try process.run()
    return process
}

private func writeHandoffScript(
    in appSupportDirectory: URL,
    name: String,
    delay: TimeInterval,
    promptBeforeURL: Bool = true,
    postSuccessDelay: TimeInterval = 0,
    exitStatus: Int32
) throws -> URL {
    let directory = appSupportDirectory.appending(path: "pdtbar")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appending(path: name)
    let content = """
    #!/bin/sh
    printf 'started %s pid=%s\\n' "$*" "$$" >> "$PDTBAR_CLAUDE_HANDOFF_MARKER.log"
    trap 'printf "terminated pid=%s\\n" "$$" >> "$PDTBAR_CLAUDE_HANDOFF_MARKER.log"; exit 143' TERM INT HUP
    printf 'started %s' "$*" > "$PDTBAR_CLAUDE_HANDOFF_MARKER"
    if [ "$1" = "auth" ] && [ "$2" = "login" ]; then
    \(promptBeforeURL ? "  printf 'press ENTER to open in browser\\n'" : "  :")
      printf 'https://claude.ai/login\\n'
      IFS= read -r _ || true
      if [ \(exitStatus) -eq 0 ]; then
        :
      else
        printf 'Claude login failed\\n'
      fi
    fi
    sleep \(String(format: "%.2f", delay))
    if [ "$1" = "auth" ] && [ "$2" = "login" ] && [ \(exitStatus) -eq 0 ]; then
      printf "%s" "$PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE" > "$PDTBAR_CLAUDE_HANDOFF_RESULT"
      printf 'Successfully logged in\\n'
      sleep \(String(format: "%.2f", postSuccessDelay))
    else
      printf "%s" "$PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE" > "$PDTBAR_CLAUDE_HANDOFF_RESULT"
    fi
    exit \(exitStatus)
    """
    try Data(content.utf8).write(to: script, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
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
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28": try mcpContent("""
        {
          "data": [
            { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": 5101, "symbolName": "Scripted Adapter Co" }
          ]
        }
        """),
        "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=250": try mcpResult("""
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
        "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28": try mcpContent("""
        { "data": [] }
        """),
        "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=250": try mcpResult("""
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
    var server: String
    var timeout: TimeInterval

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        let selector = "\(server).\(name)"
        let toolArguments = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "npx", "-y", "mcporter", "call",
                "--no-oauth",
                "--timeout", String(Int(timeout * 1000)),
                selector,
            ] + toolArguments,
            timeout: timeout + 1.0
        ).stdout
    }
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
    [
        "AskUserQuestion",
        "Bash",
        "CronCreate",
        "CronDelete",
        "CronList",
        "DesignSync",
        "Edit",
        "EnterPlanMode",
        "EnterWorktree",
        "ExitPlanMode",
        "ExitWorktree",
        "Monitor",
        "NotebookEdit",
        "PushNotification",
        "Read",
        "RemoteTrigger",
        "ScheduleWakeup",
        "Skill",
        "Task",
        "TaskCreate",
        "TaskGet",
        "TaskList",
        "TaskOutput",
        "TaskStop",
        "TaskUpdate",
        "WebFetch",
        "WebSearch",
        "Workflow",
        "Write",
        "mcp__*__pdt-add-*",
        "mcp__*__pdt-create-*",
        "mcp__*__pdt-delete-*",
        "mcp__*__pdt-patch-*",
        "mcp__*__pdt-post-*",
        "mcp__*__pdt-put-*",
        "mcp__*__pdt-remove-*",
        "mcp__*__pdt-set-*",
        "mcp__*__pdt-update-*",
    ]
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
