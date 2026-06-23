import ApplicationServices
import Foundation
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
    case "live-pdt":
        report = try livePDTSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-pdt-connector":
        report = try scriptedPDTConnectorSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-first-fetch":
        report = try scriptedFirstFetchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-returning-launch":
        report = try scriptedReturningLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-login-handoff":
        report = try scriptedLoginHandoffSmoke(arguments: Array(arguments.dropFirst()))
    case "scripted-setup-retry":
        report = try scriptedSetupRetrySmoke(arguments: Array(arguments.dropFirst()))
    case "logged-out-launch":
        report = try loggedOutLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "ready-launch":
        report = try readyLaunchSmoke(arguments: Array(arguments.dropFirst()))
    case "packaged-app":
        report = try packagedAppSmoke(arguments: Array(arguments.dropFirst()))
    case "peekaboo":
        report = try peekabooSmoke(arguments: Array(arguments.dropFirst()))
    case "real-user-pulse":
        report = try realUserPulseSmoke(arguments: Array(arguments.dropFirst()))
    case "fixture-proof":
        report = try fixtureProof(arguments: Array(arguments.dropFirst()))
    default:
        throw CommandError.usage
    }

    try writeReport(report)
    Foundation.exit(report.status == SmokeStatus.failed ? 1 : 0)
} catch CommandError.usage {
    FileHandle.standardError.write(Data("""
    usage:
      pdtbar-smoke live-pdt [--server <mcporter-server>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-pdt-connector [--artifacts <dir>]
      pdtbar-smoke scripted-first-fetch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-returning-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-login-handoff [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke scripted-setup-retry [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke logged-out-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke ready-launch [--app <path>] [--app-support-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke packaged-app [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--timeout <seconds>]
      pdtbar-smoke peekaboo [--peekaboo <path>] [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>]
      pdtbar-smoke real-user-pulse [--app <path>] [--fixture <path>] [--snapshot-dir <path>] [--artifacts <dir>] [--timeout <seconds>]
      pdtbar-smoke fixture-proof [--fixture <path>] [--output <path>]

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
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
    let missingTexts = expectedTexts.subtracting(menuSnapshot.texts)
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

private func scriptedLoginHandoffSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
    let successResult = successAppSupport.appending(path: "pdtbar/claude-handoff-result")
    let successScript = try writeHandoffScript(
        in: successAppSupport,
        name: "handoff-success.sh",
        delay: max(options.timeout, 1.0),
        exitStatus: 0
    )
    let successProcess = try launchLoginHandoffApp(
        app,
        appSupportDirectory: successAppSupport,
        handoffScript: successScript,
        marker: successMarker,
        result: successResult,
        resultValue: "success"
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
    let successClick = pressMenuRow(
        statusElement: successStatus,
        appElement: successAppElement,
        rowIdentifier: "pdtbar.row.claudeSetup.login",
        expectedMenuIdentifiers: loginIDs,
        timeout: options.timeout
    )
    let successScriptInvoked = waitForFile(successMarker, timeout: options.timeout)
    let progressVisible = waitForStatusText(
        "Opening Claude Desktop",
        in: successAppElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout
    )
    let successCompleted = waitForFile(successResult, timeout: options.timeout + 2.0)
    let returnedToLoggedOut = waitForStatusText(
        "Not connected",
        in: successAppElement,
        statusIdentifier: "pdtbar.status",
        timeout: options.timeout
    )
    let successRetrySurface = MenuBarSurfaceRenderer.render(
        descriptor: ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)
    )
    let successRetryTargets = requiredSetupMenuTargets(in: successRetrySurface)
    let successRetryIDs = Set(successRetryTargets.map(\.accessibilityIdentifier))
    var successSetupRetryVisible = false
    if let returnedStatus = waitForAccessibilityElement(
        in: successAppElement,
        identifier: successRetrySurface.status.accessibilityIdentifier,
        timeout: options.timeout
    ) {
        let openedMenu = openStatusMenu(
            returnedStatus,
            appElement: successAppElement,
            expectedMenuIdentifiers: successRetryIDs,
            timeout: options.timeout
        )
        let menuSnapshot = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
            successRetryIDs,
            in: successAppElement,
            timeout: options.timeout
        )
        successSetupRetryVisible = successRetryIDs.isSubset(of: menuSnapshot.identifiers)
            && menuSnapshot.texts.contains("Check again")
    }
    terminate(successProcess)

    let failureAppSupport = try options.isolatedAppSupportDirectory(prefix: "scripted-login-handoff-failure-app-support")
    let failureMarker = failureAppSupport.appending(path: "pdtbar/claude-handoff-started")
    let failureResult = failureAppSupport.appending(path: "pdtbar/claude-handoff-result")
    let failureScript = try writeHandoffScript(
        in: failureAppSupport,
        name: "handoff-failure.sh",
        delay: 0.1,
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
    let failureCompleted = waitForFile(failureResult, timeout: options.timeout + 2.0)
    let missingClaudeSurface = MenuBarSurfaceRenderer.render(
        descriptor: ClaudeLaunchFlow.descriptor(for: .missingClaude)
    )
    let missingClaudeTargets = requiredSetupMenuTargets(in: missingClaudeSurface)
    let missingClaudeIDs = Set(missingClaudeTargets.map(\.accessibilityIdentifier))
    let missingClaudeStatusVisible = waitForStatusText(
        "Claude Desktop not found",
        in: failureAppElement,
        statusIdentifier: missingClaudeSurface.status.accessibilityIdentifier,
        timeout: options.timeout
    )
    let missingClaudeMenu: AccessibilitySnapshot
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
        missingClaudeMenu = openedMenu.snapshot ?? waitForAccessibilityIdentifiers(
            missingClaudeIDs,
            in: failureAppElement,
            timeout: options.timeout
        )
    } else {
        missingClaudeMenu = waitForAccessibilityIdentifiers(
            missingClaudeIDs,
            in: failureAppElement,
            timeout: options.timeout
        )
    }
    let missingClaudeMenuVisible = missingClaudeIDs.isSubset(of: missingClaudeMenu.identifiers)
        && missingClaudeMenu.texts.contains("Claude Desktop not found")
        && missingClaudeMenu.texts.contains("Log in with Claude")

    let proofPayload = ScriptedLoginHandoffProof(
        successIdleBeforeClick: successWasIdleBeforeClick,
        successClickAttempt: successClick,
        successScriptInvoked: successScriptInvoked,
        successProgressVisible: progressVisible,
        successCompleted: successCompleted,
        successReturnedToLoggedOut: returnedToLoggedOut,
        successSetupRetryVisible: successSetupRetryVisible,
        failureIdleBeforeClick: failureWasIdleBeforeClick,
        failureClickAttempt: failureClick,
        failureScriptInvoked: failureScriptInvoked,
        failureCompleted: failureCompleted,
        failureMissingClaudeStatusVisible: missingClaudeStatusVisible,
        failureMissingClaudeMenuVisible: missingClaudeMenuVisible,
        rawClaudeCredentialsUsed: false
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard successWasIdleBeforeClick,
          successClick != nil,
          successScriptInvoked,
          progressVisible,
          successCompleted,
          returnedToLoggedOut,
          successSetupRetryVisible,
          failureWasIdleBeforeClick,
          failureClick != nil,
          failureScriptInvoked,
          failureCompleted,
          missingClaudeStatusVisible,
          missingClaudeMenuVisible
    else {
        return SmokeReport(
            name: "scripted-login-handoff",
            status: SmokeStatus.failed,
            detail: "scripted login handoff did not prove user-initiated success, retryable signed-out state, progress, and missing-Claude failure states",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "scripted-login-handoff",
        status: SmokeStatus.passed,
        detail: "Log in with Claude invoked the scripted handoff only after menu click, showed Opening Claude Desktop, returned to a retryable signed-out state, and rendered missing-Claude state on handoff failure",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedSetupRetrySmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
        expectedTexts: ["Add the PDT MCP server in Claude Desktop", "Check again"],
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
    let calledOnlyRequiredTools = Set(connector.calls).isSubset(of: Set(PDTReadTools.requiredV1))
    let requiredToolsCalledOnce = PDTReadTools.requiredV1.allSatisfy { callCounts[$0] == 1 }
    let scenarioResults = try scriptedPDTConnectorScenarioResults(responses: responses)
    let proofPayload = ScriptedPDTConnectorProof(
        requiredReadTools: PDTReadTools.requiredV1,
        availabilityChecks: connector.availabilityChecks,
        callCounts: PDTReadTools.requiredV1.reduce(into: [String: Int]()) { counts, tool in
            counts[tool] = callCounts[tool] ?? 0
        },
        calledOnlyRequiredReadTools: calledOnlyRequiredTools,
        coalescedSecondFetchReusedFirstResult: firstRun == secondRun,
        snapshotWritten: firstRun.snapshotCommit.written,
        openHoldingCount: firstRun.model.facetSnapshots.allocation.openHoldingCount,
        renderedSectionIDs: firstRun.descriptor.sections.map(\.id),
        scenarios: scenarioResults,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard connector.availabilityChecks == 1,
          calledOnlyRequiredTools,
          requiredToolsCalledOnce,
          firstRun == secondRun,
          firstRun.snapshotCommit.written,
          firstRun.model.facetSnapshots.allocation.openHoldingCount > 0,
          scenarioResults.allSatisfy(\.passed)
    else {
        return SmokeReport(
            name: "scripted-pdt-connector",
            status: SmokeStatus.failed,
            detail: "scripted PDT connector did not prove required read-tool availability, exact coalesced call counts, or all scripted response states",
            artifacts: [artifactPath(proof)]
        )
    }

    return SmokeReport(
        name: "scripted-pdt-connector",
        status: SmokeStatus.passed,
        detail: "scripted Claude PDT connector checked required v1 read tools, called each read tool exactly once for a coalesced fetch, and rendered through PressureRunner with redacted proof",
        artifacts: [artifactPath(proof)]
    )
}

private func scriptedFirstFetchSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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
    let expectedFreshRun = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: expectedFreshConfiguration.connector()),
        snapshotStore: expectedFreshStore,
        asOf: expectedFreshConfiguration.asOf
    ).fetch()

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
        fixtureSnapshotDirectory: successFixtureSnapshotDirectory
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
    var freshPulseVisible = false
    var failurePulseVisible = false
    var failureRetryVisible = false
    var axArtifacts: [String] = []
    if accessibilityChecked {
        let staleAXTimeout = min(refreshDelay - 1.0, max(options.timeout, 5.0))
        let refreshingSurface = MenuBarSurfaceRenderer.render(
            descriptor: ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio, cachedPulse: cachedDescriptor)
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
            let staleStatusVisible = statusText.contains(refreshingSurface.status.menuBarTitle)
                || statusText.contains(refreshingSurface.status.accessibilityLabel)
            stalePulseVisible = staleMenuVisible || (staleStatusVisible && snapshotAsOf(successSnapshot) == staleSnapshot.asOf)
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
        fixtureSnapshotDirectory: failureFixtureSnapshotDirectory
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
            descriptor: ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed, cachedPulse: cachedDescriptor)
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
                    && snapshot.texts.contains("Try again")
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
        freshPulseVisibleAfterRefresh: freshPulseVisible,
        transientFailurePreservedSnapshot: failurePreservedSnapshot,
        transientFailurePulseVisible: failurePulseVisible,
        transientFailureRetryVisible: failureRetryVisible,
        rawPortfolioPayloadsRedacted: true
    )
    try stableJSONData(proofPayload).write(to: proof, options: .atomic)

    guard failurePreservedSnapshot,
          !accessibilityChecked || (stalePulseVisible && freshPulseVisible && failurePulseVisible && failureRetryVisible)
    else {
        return SmokeReport(
            name: "scripted-returning-launch",
            status: SmokeStatus.failed,
            detail: "scripted returning launch did not prove stale visibility, fresh replacement, or transient failure preservation",
            artifacts: [artifactPath(proof)] + axArtifacts
        )
    }

    return SmokeReport(
        name: "scripted-returning-launch",
        status: SmokeStatus.passed,
        detail: "returning launch kept the seeded pulse visible during refresh, replaced it after complete scripted data, and preserved it with Try again after transient failure",
        artifacts: [artifactPath(proof)] + axArtifacts
    )
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
    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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

    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
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

    let app = options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")
    let fixture = options.fixture ?? defaultFixture
    let expectedSnapshotDirectory = try options.temporarySnapshotDirectory(prefix: "real-user-pulse-expected")
    let expectedScenario = try fixturePulseScenario(fixture: fixture, snapshotDirectory: expectedSnapshotDirectory)
    let surface = MenuBarSurfaceRenderer.render(descriptor: expectedScenario.run.descriptor)
    let expectedTargets = requiredPulseMenuTargets(in: surface)
    let expectedMenuIdentifiers = Set(expectedTargets.map(\.accessibilityIdentifier))
    let artifacts = options.artifacts ?? packageRoot.appending(path: ".build/pdtbar-smoke-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

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
    guard statusText.contains(surface.status.menuBarTitle) || statusText.contains(surface.status.accessibilityLabel) else {
        return SmokeReport(
            name: "real-user-pulse",
            status: SmokeStatus.failed,
            detail: "fixture-mode app exposed status item \(surface.status.accessibilityIdentifier), but not visible expected status \(surface.status.menuBarTitle)",
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

    let priorDetail = expectedScenario.seededPrior.map { "; seeded prior snapshot \($0.asOf)" } ?? ""
    return SmokeReport(
        name: "real-user-pulse",
        status: SmokeStatus.passed,
        detail: "launched fixture-mode app with isolated state\(priorDetail), opened menu-bar pulse through \(openedMenu.successfulAttempt ?? "Accessibility"), and verified status plus pulse/allocation/income/big-mover/freshness selectors for \(fixture.lastPathComponent)",
        artifacts: [artifactPath(evidence)]
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
            targets.append(PulseTarget(accessibilityIdentifier: row.accessibilityIdentifier, title: row.title))
        }
    }

    return targets
}

private func requiredSetupMenuTargets(in surface: MenuBarSurface) -> [PulseTarget] {
    surface.sections.flatMap { section in
        [PulseTarget(accessibilityIdentifier: section.accessibilityIdentifier, title: section.title)]
            + section.rows.map {
                PulseTarget(accessibilityIdentifier: $0.accessibilityIdentifier, title: $0.title)
            }
    }
}

private struct AccessibilitySnapshot: Codable {
    var identifiers: Set<String>
    var texts: Set<String>
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
    var observedTexts: [String]
}

private struct LivePDTPulseProof: Codable {
    var snapshotWritten: Bool
    var statusAccessibilityIdentifier: String
    var sectionIDs: [String]
    var rowCount: Int
    var rawPortfolioValuesRedacted: Bool
}

private struct ScriptedPDTConnectorProof: Codable {
    var requiredReadTools: [String]
    var availabilityChecks: Int
    var callCounts: [String: Int]
    var calledOnlyRequiredReadTools: Bool
    var coalescedSecondFetchReusedFirstResult: Bool
    var snapshotWritten: Bool
    var openHoldingCount: Int
    var renderedSectionIDs: [String]
    var scenarios: [ScriptedPDTConnectorScenarioResult]
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
    var freshPulseVisibleAfterRefresh: Bool
    var transientFailurePreservedSnapshot: Bool
    var transientFailurePulseVisible: Bool
    var transientFailureRetryVisible: Bool
    var rawPortfolioPayloadsRedacted: Bool
}

private struct ScriptedLoginHandoffProof: Codable {
    var successIdleBeforeClick: Bool
    var successClickAttempt: String?
    var successScriptInvoked: Bool
    var successProgressVisible: Bool
    var successCompleted: Bool
    var successReturnedToLoggedOut: Bool
    var successSetupRetryVisible: Bool
    var failureIdleBeforeClick: Bool
    var failureClickAttempt: String?
    var failureScriptInvoked: Bool
    var failureCompleted: Bool
    var failureMissingClaudeStatusVisible: Bool
    var failureMissingClaudeMenuVisible: Bool
    var rawClaudeCredentialsUsed: Bool
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
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let status = findAccessibilityElement(in: root, identifier: statusIdentifier) {
            let texts = accessibilityTexts(in: status)
            if texts.contains(expected) || texts.contains("PDTBar \(expected)") {
                return true
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    if let status = findAccessibilityElement(in: root, identifier: statusIdentifier) {
        let texts = accessibilityTexts(in: status)
        return texts.contains(expected) || texts.contains("PDTBar \(expected)")
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
    var snapshot = AccessibilitySnapshot(identifiers: [], texts: [])
    var stack = [root]
    var visited = 0
    while let element = stack.popLast(), visited < 800 {
        visited += 1
        if let identifier = accessibilityString(element, "AXIdentifier"), !identifier.isEmpty {
            snapshot.identifiers.insert(identifier)
        }
        for text in accessibilityTexts(in: element) {
            snapshot.texts.insert(text)
        }
        stack.append(contentsOf: accessibilityChildren(of: element))
    }
    return snapshot
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
            && expectedTexts.isSubset(of: menuSnapshot.texts)

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
    fixtureSnapshotDirectory: URL
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

private func launchLoginHandoffApp(
    _ app: URL,
    appSupportDirectory: URL,
    handoffScript: URL,
    marker: URL,
    result: URL,
    resultValue: String
) throws -> Process {
    let process = Process()
    process.executableURL = app
    process.arguments = []
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PDTBAR_CLAUDE_READINESS")
    process.environment = environment.merging([
        "PDTBAR_APP_SUPPORT_DIR": appSupportDirectory.path,
        "PDTBAR_CLAUDE_HANDOFF_SCRIPT": handoffScript.path,
        "PDTBAR_CLAUDE_HANDOFF_MARKER": marker.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT": result.path,
        "PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE": resultValue,
    ]) { _, new in new }
    try process.run()
    return process
}

private func writeHandoffScript(
    in appSupportDirectory: URL,
    name: String,
    delay: TimeInterval,
    exitStatus: Int32
) throws -> URL {
    let directory = appSupportDirectory.appending(path: "pdtbar")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appending(path: name)
    let content = """
    #!/bin/sh
    printf started > "$PDTBAR_CLAUDE_HANDOFF_MARKER"
    sleep \(String(format: "%.2f", delay))
    printf "%s" "$PDTBAR_CLAUDE_HANDOFF_RESULT_VALUE" > "$PDTBAR_CLAUDE_HANDOFF_RESULT"
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
    var fixture: URL?
    var peekaboo: URL?
    var artifacts: URL?
    var output: URL?
    var snapshotDirectory: URL?
    var appSupportDirectory: URL?
    var server: String?
    var timeout: TimeInterval = 2.0
    var timeoutWasProvided = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--app" where index + 1 < arguments.count:
                app = URL(fileURLWithPath: arguments[index + 1])
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
        ("auth-setup-error", PDTMCPConnectorError.setupUnavailable("Claude Desktop needs PDT setup")),
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
        { "id": 9101, "symbolId": 5101 }
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
      <text x="48" y="59" fill="#ffffff" font-family="Menlo, monospace" font-size="18">\(escape(descriptor.statusTitle))</text>
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

private enum CommandError: Error, CustomStringConvertible {
    case usage
    case timedOut(String)
    case commandFailed(String, String, String)

    var description: String {
        switch self {
        case .usage:
            return "usage"
        case let .timedOut(command):
            return "\(command) timed out"
        case let .commandFailed(command, stdout, stderr):
            return "\(command) failed: \([stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n"))"
        }
    }
}
