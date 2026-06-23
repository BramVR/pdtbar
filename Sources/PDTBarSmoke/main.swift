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
      pdtbar-smoke packaged-app [--app <path>] [--fixture <path>] [--timeout <seconds>]
      pdtbar-smoke peekaboo [--peekaboo <path>] [--app <path>] [--fixture <path>] [--artifacts <dir>]
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
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path]
    process.environment = ProcessInfo.processInfo.environment.merging(["PDTBAR_FIXTURE_MODE": "1"]) { _, new in new }
    try process.run()
    Thread.sleep(forTimeInterval: options.timeout)
    let running = process.isRunning
    if running {
        process.terminate()
    }
    process.waitUntilExit()

    let timeoutDescription = String(format: "%.1f", options.timeout)
    return SmokeReport(
        name: "packaged-app",
        status: running ? SmokeStatus.passed : SmokeStatus.failed,
        detail: running
            ? "fixture-mode app launched and stayed running for \(timeoutDescription)s"
            : "fixture-mode app exited before the smoke timeout",
        artifacts: []
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

    let appReport = try packagedAppSmoke(arguments: [
        "--app", (options.app ?? packageRoot.appending(path: ".build/debug/pdtbar")).path,
        "--fixture", (options.fixture ?? defaultFixture).path,
        "--timeout", "0.5",
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
    process.executableURL = app
    process.arguments = ["--fixture", fixture.path]
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
        artifacts: [screenshot.path]
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
        artifacts: [output.path]
    )
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
            case "--timeout" where index + 1 < arguments.count:
                timeout = TimeInterval(arguments[index + 1]) ?? 2.0
                index += 2
            default:
                throw CommandError.usage
            }
        }
    }
}

private struct CommandResult {
    var stdout: Data
    var stderr: Data
}

private func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
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
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
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
