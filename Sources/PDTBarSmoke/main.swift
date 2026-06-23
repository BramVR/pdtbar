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

private let requiredLivePDTTools = [
    "pdt-get-portfolio-holdings",
    "pdt-get-portfolio-distributions",
    "pdt-list-calendar-events",
    "pdt-list-dividends",
    "pdt-list-symbol-prices",
    "pdt-get-symbol-quote",
]

private func livePDTSmoke(arguments: [String]) throws -> SmokeReport {
    let options = try SmokeOptions(arguments: arguments)
    let environment = ProcessInfo.processInfo.environment
    if let schemaPath = environment["PDTBAR_LIVE_PDT_SCHEMA_JSON"], !schemaPath.isEmpty {
        let schemaData = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
        let object = try JSONSerialization.jsonObject(with: schemaData)
        let schemaToolNames = toolNames(in: object)
        let missingTools = requiredLivePDTTools.filter { tool in
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
}

private struct CommandResult {
    var stdout: Data
    var stderr: Data
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
