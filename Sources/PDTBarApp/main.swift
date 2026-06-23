import AppKit
import Foundation
import PDTBarCore

private struct PortfolioFetchOutcome: @unchecked Sendable {
    var descriptor: MenuDescriptor?
    var errorDescription: String?
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: PDTBarLaunchOptions
    private let loginHandoff: ClaudeLoginHandoff
    private var statusItem: NSStatusItem?
    private var cachedPulseDescriptor: MenuDescriptor?
    private var portfolioFetchInFlight = false
    private let claudeReadinessProbeGate = ClaudeReadinessProbeGate()

    init(options: PDTBarLaunchOptions) {
        self.options = options
        self.loginHandoff = ClaudeDesktopLoginHandoff(
            environment: ProcessInfo.processInfo.environment
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try launch()
        } catch {
            FileHandle.standardError.write(Data("pdtbar: \(error)\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }

    private func launch() throws {
        switch options.mode {
        case .claudeFirst:
            cachedPulseDescriptor = loadCachedPulseDescriptor()
            installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .probingClaude, cachedPulse: cachedPulseDescriptor))
            startClaudeReadinessProbe()
        case let .fixture(fixture):
            let dataSource = PDTFixtureDataSource(fixture: fixture)
            let descriptor = try PressureRunner.run(
                dataSource: dataSource,
                snapshotStore: SnapshotStore(directory: try fixtureSnapshotDirectory())
            ).descriptor
            installMenuBarItem(descriptor)
        }
    }

    private func startClaudeReadinessProbe() {
        guard claudeReadinessProbeGate.begin() else {
            return
        }
        installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .probingClaude, cachedPulse: cachedPulseDescriptor))
        let probe = ScriptedClaudeReadinessProbe(
            appSupportDirectory: appSupportDirectory(),
            environment: ProcessInfo.processInfo.environment
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let result = probe.check()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.claudeReadinessProbeGate.finish()
                let state = ClaudeLaunchFlow.state(afterReadinessProbe: result)
                self.installMenuBarItem(ClaudeLaunchFlow.descriptor(for: state, cachedPulse: self.cachedPulseDescriptor))
                if state == .fetchingPortfolio {
                    self.startFirstPortfolioFetch()
                }
            }
        }
    }

    private func startFirstPortfolioFetch() {
        guard !portfolioFetchInFlight else {
            return
        }
        portfolioFetchInFlight = true
        installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio, cachedPulse: cachedPulseDescriptor))
        do {
            let configuration = try scriptedPDTConnectorConfiguration()
            let snapshotStore = SnapshotStore(directory: firstFetchStateDirectory())
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome: PortfolioFetchOutcome
                do {
                    let fetch = try PDTCoalescedFirstPortfolioFetch(
                        dataSource: PDTMCPConnectorDataSource(connector: configuration.connector()),
                        snapshotStore: snapshotStore,
                        asOf: configuration.asOf
                    )
                    outcome = PortfolioFetchOutcome(descriptor: try fetch.fetch().descriptor, errorDescription: nil)
                } catch {
                    outcome = PortfolioFetchOutcome(descriptor: nil, errorDescription: "\(error)")
                }
                DispatchQueue.main.async { [weak self] in
                    self?.finishFirstPortfolioFetch(outcome)
                }
            }
        } catch {
            finishFirstPortfolioFetch(PortfolioFetchOutcome(descriptor: nil, errorDescription: "\(error)"))
        }
    }

    private func finishFirstPortfolioFetch(_ outcome: PortfolioFetchOutcome) {
        portfolioFetchInFlight = false
        if let descriptor = outcome.descriptor {
            cachedPulseDescriptor = descriptor
            installMenuBarItem(descriptor)
            return
        }
        let errorDescription = outcome.errorDescription ?? "unknown error"
        FileHandle.standardError.write(Data("pdtbar: first fetch failed: \(errorDescription)\n".utf8))
        installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed, cachedPulse: cachedPulseDescriptor))
    }

    @objc private func retryPortfolioFetch(_ sender: NSMenuItem) {
        startFirstPortfolioFetch()
    }

    @objc private func retryClaudeReadiness(_ sender: NSMenuItem) {
        startClaudeReadinessProbe()
    }

    @objc private func loginWithClaude(_ sender: NSMenuItem) {
        installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .openingClaude))
        loginHandoff.openOrFocus { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin))
                case .failure(let error):
                    FileHandle.standardError.write(Data("pdtbar: Claude handoff failed: \(error)\n".utf8))
                    self?.installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .missingClaude))
                }
            }
        }
    }

    private func scriptedPDTConnectorConfiguration() throws -> ScriptedPDTMCPConnectorConfiguration {
        let url = appSupportDirectory().appending(path: "pdtbar/scripted-pdt-mcp.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScriptedPDTMCPConnectorConfiguration.self, from: data)
    }

    private func firstFetchStateDirectory() -> URL {
        appSupportDirectory().appending(path: "pdtbar/state")
    }

    private func loadCachedPulseDescriptor() -> MenuDescriptor? {
        try? PressureRunner.cachedPulseDescriptor(
            snapshotStore: SnapshotStore(directory: firstFetchStateDirectory())
        )
    }

    private func fixtureSnapshotDirectory() throws -> URL {
        if let snapshotDirectory = options.snapshotDirectory {
            return snapshotDirectory
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-fixture-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appSupportDirectory() -> URL {
        options.appSupportDirectory ?? defaultAppSupportDirectory()
    }

    private func installMenuBarItem(_ descriptor: MenuDescriptor) {
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let item: NSStatusItem
        if let statusItem {
            item = statusItem
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
        }
        item.button?.title = surface.status.menuBarTitle
        item.button?.identifier = NSUserInterfaceItemIdentifier(surface.status.accessibilityIdentifier)
        item.button?.toolTip = surface.status.toolTip
        item.button?.setAccessibilityLabel(surface.status.accessibilityLabel)
        item.button?.setAccessibilityIdentifier(surface.status.accessibilityIdentifier)
        item.menu = makeMenu(from: surface)
    }

    private func makeMenu(from surface: MenuBarSurface) -> NSMenu {
        let menu = NSMenu()
        for section in surface.sections {
            let heading = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            heading.identifier = NSUserInterfaceItemIdentifier(section.accessibilityIdentifier)
            heading.setAccessibilityIdentifier(section.accessibilityIdentifier)
            heading.isEnabled = false
            menu.addItem(heading)
            for row in section.rows {
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                if !row.accessibilityIdentifier.isEmpty {
                    item.identifier = NSUserInterfaceItemIdentifier(row.accessibilityIdentifier)
                    item.setAccessibilityIdentifier(row.accessibilityIdentifier)
                }
                if row.role == .fetchRetry {
                    item.target = self
                    item.action = #selector(retryPortfolioFetch(_:))
                }
                if row.role == .setupRetry {
                    item.target = self
                    item.action = #selector(retryClaudeReadiness(_:))
                }
                if row.role == .setupLogin {
                    item.target = self
                    item.action = #selector(loginWithClaude(_:))
                }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Quit PDTBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}

private protocol ClaudeLoginHandoff {
    func openOrFocus(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void)
}

private enum ClaudeLoginHandoffError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private final class ClaudeDesktopLoginHandoff: ClaudeLoginHandoff {
    private let environment: [String: String]

    init(environment: [String: String]) {
        self.environment = environment
    }

    func openOrFocus(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if let script = scriptedHandoffPath() {
            run(executable: URL(fileURLWithPath: script), arguments: [], completion: completion)
            return
        }
        run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Claude"],
            completion: completion
        )
    }

    private func scriptedHandoffPath() -> String? {
        if let script = environment["PDTBAR_CLAUDE_HANDOFF_SCRIPT"], !script.isEmpty {
            return script
        }
        return nil
    }

    private func run(
        executable: URL,
        arguments: [String],
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let nullOutput = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
            process.standardOutput = nullOutput
            process.standardError = nullOutput
            do {
                defer {
                    try? nullOutput?.close()
                }
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(ClaudeLoginHandoffError.failed("Claude Desktop could not be opened")))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

private struct ScriptedClaudeReadinessProbe {
    var appSupportDirectory: URL
    var environment: [String: String]

    func check() -> ClaudeReadinessProbeResult {
        recordProbe()
        if let scripted = environment["PDTBAR_CLAUDE_READINESS"] {
            return parse(scripted) ?? .failed
        }
        let url = appSupportDirectory.appending(path: "pdtbar/claude-readiness.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .notReady
        }
        guard let data = try? Data(contentsOf: url),
              let script = try? JSONDecoder().decode(Script.self, from: data)
        else {
            return .failed
        }
        if let delay = script.delaySeconds, delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        return parse(script.result) ?? .failed
    }

    private func recordProbe() {
        guard let log = environment["PDTBAR_CLAUDE_READINESS_LOG"], !log.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: log)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer {
            try? handle.close()
        }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: Data("probe\n".utf8))
    }

    private func parse(_ value: String) -> ClaudeReadinessProbeResult? {
        switch value {
        case "ready":
            return .ready
        case "notReady":
            return .notReady
        case "missingClaudeLogin", "loggedOut":
            return .missingClaudeLogin
        case "missingPDTMCP", "missingPdtMcp", "missingPDTMCPServer", "missingPDTServer", "missingSetup":
            return .missingPDTMCP
        case "failed", "failure":
            return .failed
        default:
            return nil
        }
    }

    private struct Script: Decodable {
        var result: String
        var delaySeconds: Double?
    }
}

private func defaultAppSupportDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
}

do {
    let options = try PDTBarLaunchOptionParser.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
} catch {
    FileHandle.standardError.write(
        Data("usage: pdtbar [--app-support-dir <path>] | --fixture <path> [--snapshot-dir <path>]\n".utf8)
    )
    Foundation.exit(64)
}
