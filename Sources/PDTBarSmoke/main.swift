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
        report = try livePDTSmoke()
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
      pdtbar-smoke live-pdt
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

private func livePDTSmoke() throws -> SmokeReport {
    let environment = ProcessInfo.processInfo.environment
    guard environment["PDTBAR_LIVE_PDT_SMOKE"] == "1" else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.skipped,
            detail: "set PDTBAR_LIVE_PDT_SMOKE=1 and PDTBAR_LIVE_PDT_SCHEMA_JSON=/path/to/mcporter-schema.json to run the opt-in live contract smoke",
            artifacts: []
        )
    }
    guard let schemaPath = environment["PDTBAR_LIVE_PDT_SCHEMA_JSON"], !schemaPath.isEmpty else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.failed,
            detail: "PDTBAR_LIVE_PDT_SCHEMA_JSON is required; create it with: npx -y mcporter list <pdt-server> --schema --json > /tmp/pdt-schema.json",
            artifacts: []
        )
    }

    let schemaData = try Data(contentsOf: URL(fileURLWithPath: schemaPath))
    let object = try JSONSerialization.jsonObject(with: schemaData)
    let schemaToolNames = toolNames(in: object)
    let requiredTools = [
        "pdt-get-portfolio-holdings",
        "pdt-get-portfolio-distributions",
        "pdt-list-calendar-events",
        "pdt-list-dividends",
        "pdt-list-symbol-prices",
        "pdt-get-symbol-quote",
    ]
    let missingTools = requiredTools.filter { tool in
        !schemaToolNames.contains(tool)
    }
    guard missingTools.isEmpty else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.failed,
            detail: "schema missing required PDT tools: \(missingTools.joined(separator: ", "))",
            artifacts: [schemaPath]
        )
    }

    let incomeSnapshot = try PDTFixtureDataSource(
        fixture: packageRoot.appending(path: "docs/pdt/fixtures/income-event.json")
    ).snapshot()
    let mappedIncomeEvent = incomeSnapshot.incomeEvents.first {
        $0.symbolId == 5003 && $0.quoteId == 9003
    }
    guard mappedIncomeEvent != nil else {
        return SmokeReport(
            name: "live-pdt",
            status: SmokeStatus.failed,
            detail: "normalized mapping check failed for sanitized symbolId to quoteId fixture",
            artifacts: [schemaPath]
        )
    }

    return SmokeReport(
        name: "live-pdt",
        status: SmokeStatus.passed,
        detail: "live PDT schema exposes required read tools; sanitized fixture mapping proves symbolId to quoteId normalization without private portfolio assertions",
        artifacts: [schemaPath]
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
    let descriptor = MenuDescriptorRenderer.render(
        model: PressureEngine.buildModel(from: try PDTFixtureDataSource(fixture: fixture).snapshot())
    )
    let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
    let expectedTargets = requiredQuietPulseMenuTargets(in: surface)
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

    let process = Process()
    let snapshotDirectory = try options.isolatedSnapshotDirectory(prefix: "real-user-pulse-app")
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
            detail: "fixture-mode app exposed status item \(surface.status.accessibilityIdentifier), but not visible all-quiet status \(surface.status.menuBarTitle)",
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
            detail: "could not verify opened fixture-mode pulse menu after \(openedMenu.attempts.joined(separator: ", ")); missing expected quiet fixture targets: \(missingLabels)",
            artifacts: [artifactPath(evidence)]
        )
    }

    return SmokeReport(
        name: "real-user-pulse",
        status: SmokeStatus.passed,
        detail: "launched fixture-mode app, opened menu-bar pulse through \(openedMenu.successfulAttempt ?? "Accessibility"), and verified quiet fixture status plus pulse/allocation/income/big-mover/freshness selectors",
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

private struct QuietPulseTarget {
    var accessibilityIdentifier: String
    var title: String
}

private func requiredQuietPulseMenuTargets(in surface: MenuBarSurface) -> [QuietPulseTarget] {
    var targets: [QuietPulseTarget] = []
    let requiredSectionIDs = ["pulse", "allocation", "income", "bigMovers", "freshness"]
    for sectionID in requiredSectionIDs {
        guard let section = surface.sections.first(where: { $0.id == sectionID }) else {
            targets.append(QuietPulseTarget(accessibilityIdentifier: "missing.section.\(sectionID)", title: sectionID))
            continue
        }
        targets.append(QuietPulseTarget(accessibilityIdentifier: section.accessibilityIdentifier, title: section.title))
        if let firstRow = section.rows.first {
            targets.append(QuietPulseTarget(
                accessibilityIdentifier: firstRow.accessibilityIdentifier,
                title: firstRow.title
            ))
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
    var expected: [QuietPulseTargetEvidence]
    var observedIdentifiers: [String]
    var observedTexts: [String]
}

private struct QuietPulseTargetEvidence: Codable {
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
    expected: [QuietPulseTarget],
    statusIdentifier: String,
    statusText: Set<String>,
    output: URL
) throws {
    let evidence = AccessibilityEvidence(
        statusIdentifier: statusIdentifier,
        statusText: statusText.sorted(),
        expected: expected.map {
            QuietPulseTargetEvidence(
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
    var timeout: TimeInterval = 2.0

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
            case "--timeout" where index + 1 < arguments.count:
                timeout = TimeInterval(arguments[index + 1]) ?? 2.0
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

private func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
    let process = Process()
    let fileManager = FileManager.default
    let stdoutURL = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-smoke-\(UUID().uuidString).stdout")
    let stderrURL = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-smoke-\(UUID().uuidString).stderr")
    guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
          fileManager.createFile(atPath: stderrURL.path, contents: nil) else {
        throw CommandError.commandFailed(executable.lastPathComponent, "failed to create temporary output files")
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
        throw CommandError.commandFailed(executable.lastPathComponent, String(data: err, encoding: .utf8) ?? "")
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
    if let array = object as? [Any] {
        return Set(array.flatMap { Array(toolNames(in: $0)) })
    }
    if let dictionary = object as? [String: Any] {
        var names = Set(dictionary.values.flatMap { Array(toolNames(in: $0)) })
        if let name = dictionary["name"] as? String {
            names.insert(name)
            if let selectorToolName = name.split(separator: ".").last {
                names.insert(String(selectorToolName))
            }
        }
        return names
    }
    return Set()
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
    case commandFailed(String, String)

    var description: String {
        switch self {
        case .usage:
            return "usage"
        case let .timedOut(command):
            return "\(command) timed out"
        case let .commandFailed(command, stderr):
            return "\(command) failed: \(stderr)"
        }
    }
}
