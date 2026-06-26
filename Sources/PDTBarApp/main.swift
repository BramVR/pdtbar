import AppKit
import Darwin
import Foundation
import PDTBarAppSupport
import PDTBarCore

private struct PortfolioFetchOutcome: @unchecked Sendable {
    var pulse: PulseLifecycleResult? = nil
    var errorDescription: String?
    var detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome?
    var shouldStartBackgroundRefresh = false
}

private struct FirstFetchConnectorConfiguration: @unchecked Sendable {
    var connector: any PDTMCPConnector
    var asOf: String?
    var liveOptions = PDTLiveDataSourceOptions()
    var shouldStartBackgroundRefresh = false
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: PDTBarLaunchOptions
    private let loginHandoff: ClaudeLoginHandoff
    private let onboardingCoordinator = PDTOnboardingCoordinator()
    private var statusItem: NSStatusItem?
    private var currentPulse: PulseLifecycleResult?
    private var cachedPulseDescriptor: MenuDescriptor?
    private var portfolioFetchInFlight = false
    private var portfolioRefreshInFlight = false
    private var portfolioFetchStartedAt: Date?
    private var portfolioFetchProgressTimer: Timer?
    private var activeSnapshotDirectory: URL?
    private let claudeReadinessProbeGate = ClaudeReadinessProbeGate()
    private let claudeLoginAttemptGate = ClaudeLoginAttemptGate()
    private let menuActionDispatcher = MenuActionDispatcher()
    private let menuItemViewWidth: CGFloat = 400

    init(options: PDTBarLaunchOptions) {
        self.options = options
        self.loginHandoff = ClaudeCLILoginHandoff(
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
            activeSnapshotDirectory = firstFetchStateDirectory()
            let cachedPulse = loadCachedPulse()
            currentPulse = cachedPulse
            cachedPulseDescriptor = cachedPulse?.descriptor
            handleOnboardingUpdate(onboardingCoordinator.launch(cachedPulse: cachedPulse?.descriptor))
        case let .fixture(fixture):
            let dataSource = PDTFixtureDataSource(fixture: fixture)
            let snapshotDirectory = try fixtureSnapshotDirectory()
            activeSnapshotDirectory = snapshotDirectory
            let result = try PressureRunner.run(
                dataSource: dataSource,
                snapshotStore: SnapshotStore(directory: snapshotDirectory),
                pulseReadStore: PulseReadStore(directory: snapshotDirectory)
            )
            currentPulse = result
            cachedPulseDescriptor = result.descriptor
            installMenuBarItem(result.descriptor)
        }
    }

    private func startClaudeReadinessProbe() {
        guard claudeReadinessProbeGate.begin() else {
            return
        }
        installMenuBarItem(onboardingCoordinator.beginReadinessProbe().descriptor)
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
                self.handleOnboardingUpdate(self.onboardingCoordinator.completeReadinessProbe(result))
            }
        }
    }

    private func startFirstPortfolioFetch() {
        guard !portfolioFetchInFlight else {
            return
        }
        portfolioFetchInFlight = true
        installMenuBarItem(onboardingCoordinator.beginFirstFetch().descriptor)
        do {
            let configuration = try firstFetchConnectorConfiguration()
            if configuration.shouldStartBackgroundRefresh && cachedPulseDescriptor != nil {
                portfolioFetchInFlight = false
                startBackgroundPortfolioRefresh()
                return
            }
            portfolioFetchStartedAt = Date()
            installPortfolioFetchProgressMenu(cancelOpenMenu: true)
            startPortfolioFetchProgressTimer()
            let stateDirectory = firstFetchStateDirectory()
            activeSnapshotDirectory = stateDirectory
            let snapshotStore = SnapshotStore(directory: stateDirectory)
            let pulseReadStore = PulseReadStore(directory: stateDirectory)
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome: PortfolioFetchOutcome
                do {
                    let fetch = PDTCoalescedFirstPortfolioFetch(
                        dataSource: PDTMCPConnectorDataSource(
                            connector: configuration.connector,
                            liveOptions: configuration.liveOptions
                        ),
                        snapshotStore: snapshotStore,
                        asOf: configuration.asOf,
                        pulseReadStore: pulseReadStore
                    )
                    let result = try fetch.fetch()
                    outcome = PortfolioFetchOutcome(
                        pulse: result,
                        errorDescription: nil,
                        shouldStartBackgroundRefresh: configuration.shouldStartBackgroundRefresh
                    )
                } catch {
                    outcome = PortfolioFetchOutcome(errorDescription: "\(error)")
                }
                DispatchQueue.main.async { [weak self] in
                    self?.finishFirstPortfolioFetch(outcome)
                }
            }
        } catch {
            finishFirstPortfolioFetch(PortfolioFetchOutcome(errorDescription: "\(error)"))
        }
    }

    private func finishFirstPortfolioFetch(_ outcome: PortfolioFetchOutcome) {
        portfolioFetchInFlight = false
        stopPortfolioFetchProgressTimer()
        if let pulse = outcome.pulse {
            let refreshedPulse = pulseApplyingCurrentReadState(pulse)
            let descriptor = refreshedPulse.descriptor
            currentPulse = refreshedPulse
            cachedPulseDescriptor = descriptor
            installMenuBarItem(onboardingCoordinator.completeFirstFetch(.succeeded(descriptor)).descriptor)
            if outcome.shouldStartBackgroundRefresh {
                startBackgroundPortfolioRefresh()
            }
            return
        }
        let errorDescription = outcome.errorDescription ?? "unknown error"
        FileHandle.standardError.write(Data("pdtbar: first fetch failed: \(errorDescription)\n".utf8))
        installMenuBarItem(onboardingCoordinator.completeFirstFetch(.failed(errorDescription)).descriptor)
    }

    private func startPortfolioFetchProgressTimer() {
        portfolioFetchProgressTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(updatePortfolioFetchProgress(_:)),
            userInfo: nil,
            repeats: true
        )
        portfolioFetchProgressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPortfolioFetchProgressTimer() {
        portfolioFetchProgressTimer?.invalidate()
        portfolioFetchProgressTimer = nil
        portfolioFetchStartedAt = nil
    }

    @objc private func updatePortfolioFetchProgress(_ timer: Timer) {
        guard portfolioFetchInFlight else {
            stopPortfolioFetchProgressTimer()
            return
        }
        installPortfolioFetchProgressMenu(cancelOpenMenu: false)
    }

    private func installPortfolioFetchProgressMenu(cancelOpenMenu: Bool) {
        let elapsedSeconds = portfolioFetchStartedAt.map {
            Int(Date().timeIntervalSince($0))
        } ?? 0
        installMenuBarItem(
            onboardingCoordinator.beginFirstFetch(fetchingElapsedSeconds: elapsedSeconds).descriptor,
            cancelOpenMenu: cancelOpenMenu
        )
    }

    @objc private func retryPortfolioFetch(_ sender: NSMenuItem) {
        startFirstPortfolioFetch()
    }

    private func startBackgroundPortfolioRefresh() {
        guard !portfolioRefreshInFlight else {
            return
        }
        portfolioRefreshInFlight = true
        if let cachedPulseDescriptor {
            installMenuBarItem(
                ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
                    cachedPulse: cachedPulseDescriptor,
                    progress: BackgroundDetailRefreshProgress(phase: .baseHoldings)
                )
            )
        }
        let stateDirectory = firstFetchStateDirectory()
        activeSnapshotDirectory = stateDirectory
        let snapshotStore = SnapshotStore(directory: stateDirectory)
        let pulseReadStore = PulseReadStore(directory: stateDirectory)
        let environment = ProcessInfo.processInfo.environment
        let refreshConfiguration: FirstFetchConnectorConfiguration
        do {
            refreshConfiguration = try backgroundRefreshConnectorConfiguration(environment: environment)
        } catch {
            finishBackgroundPortfolioRefresh(
                PortfolioFetchOutcome(errorDescription: "\(error)")
            )
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let outcome: PortfolioFetchOutcome
            do {
                let refresh = PDTBackgroundDetailRefresh(
                    connector: refreshConfiguration.connector,
                    snapshotStore: snapshotStore,
                    pulseReadStore: pulseReadStore,
                    asOf: refreshConfiguration.asOf,
                )
                let result = try refresh.refresh { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.portfolioRefreshInFlight,
                              let cachedPulseDescriptor = self.cachedPulseDescriptor
                        else {
                            return
                        }
                        self.installMenuBarItem(
                            ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
                                cachedPulse: cachedPulseDescriptor,
                                progress: progress
                            ),
                            cancelOpenMenu: false
                        )
                    }
                }
                outcome = PortfolioFetchOutcome(
                    pulse: result.pulse,
                    errorDescription: nil,
                    detailRefreshOutcome: result.outcome
                )
            } catch {
                outcome = PortfolioFetchOutcome(errorDescription: "\(error)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishBackgroundPortfolioRefresh(outcome)
            }
        }
    }

    private func finishBackgroundPortfolioRefresh(_ outcome: PortfolioFetchOutcome) {
        portfolioRefreshInFlight = false
        if let pulse = outcome.pulse {
            let refreshedPulse = pulseApplyingCurrentReadState(pulse)
            let descriptor = refreshedPulse.descriptor
            currentPulse = refreshedPulse
            cachedPulseDescriptor = descriptor
            if outcome.detailRefreshOutcome == .degraded {
                installMenuBarItem(ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: descriptor))
            } else {
                installPortfolioPulseDescriptor(descriptor)
            }
            return
        }
        let errorDescription = outcome.errorDescription ?? "unknown error"
        FileHandle.standardError.write(Data("pdtbar: background refresh failed: \(errorDescription)\n".utf8))
        if let cachedPulseDescriptor {
            installMenuBarItem(ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(cachedPulse: cachedPulseDescriptor))
        } else {
            installMenuBarItem(ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed))
        }
    }

    @objc private func retryClaudeReadiness(_ sender: NSMenuItem) {
        startClaudeReadinessProbe()
    }

    @objc private func loginWithClaude(_ sender: NSMenuItem) {
        let attempt = claudeLoginAttemptGate.begin()
        installMenuBarItem(onboardingCoordinator.beginLoginHandoff().descriptor)
        loginHandoff.startLogin { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.claudeLoginAttemptGate.finish(attempt) else {
                    return
                }
                switch result {
                case .success:
                    self.handleOnboardingUpdate(self.onboardingCoordinator.completeLoginHandoff(.succeeded))
                case .failure(let error):
                    FileHandle.standardError.write(Data("pdtbar: Claude handoff failed: \(error)\n".utf8))
                    if let handoffError = error as? ClaudeLoginHandoffError {
                        self.handleOnboardingUpdate(
                            self.onboardingCoordinator.completeLoginHandoff(.failed(handoffError.reason))
                        )
                    } else {
                        self.handleOnboardingUpdate(self.onboardingCoordinator.completeLoginHandoff(.failed(.failed)))
                    }
                }
            }
        }
    }

    private func handleOnboardingUpdate(_ update: PDTOnboardingUpdate) {
        installMenuBarItem(update.descriptor)
        switch update.effect {
        case .none:
            return
        case .probeReadiness:
            startClaudeReadinessProbe()
        case .startLoginHandoff:
            return
        case .startFirstFetch:
            startFirstPortfolioFetch()
        }
    }

    private func scriptedPDTConnectorConfiguration() throws -> ScriptedPDTMCPConnectorConfiguration {
        let url = appSupportDirectory().appending(path: "pdtbar/scripted-pdt-mcp.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScriptedPDTMCPConnectorConfiguration.self, from: data)
    }

    private func firstFetchConnectorConfiguration() throws -> FirstFetchConnectorConfiguration {
        let scriptedURL = appSupportDirectory().appending(path: "pdtbar/scripted-pdt-mcp.json")
        if FileManager.default.fileExists(atPath: scriptedURL.path) {
            let configuration = try scriptedPDTConnectorConfiguration()
            return FirstFetchConnectorConfiguration(
                connector: try configuration.connector(),
                asOf: configuration.asOf,
                liveOptions: PDTLiveDataSourceOptions(),
                shouldStartBackgroundRefresh: scriptedBackgroundRefreshEnabled()
            )
        }
        return FirstFetchConnectorConfiguration(
            connector: ClaudeCLIPDTMCPConnector(environment: ProcessInfo.processInfo.environment),
            asOf: nil,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: false,
                includePriceSeries: false
            ),
            shouldStartBackgroundRefresh: true
        )
    }

    private func backgroundRefreshConnectorConfiguration(
        environment: [String: String]
    ) throws -> FirstFetchConnectorConfiguration {
        if scriptedBackgroundRefreshEnabled() {
            let scriptedURL = appSupportDirectory().appending(path: "pdtbar/scripted-pdt-mcp.json")
            if FileManager.default.fileExists(atPath: scriptedURL.path) {
                let configuration = try scriptedPDTConnectorConfiguration()
                return FirstFetchConnectorConfiguration(
                    connector: try configuration.connector(),
                    asOf: configuration.asOf
                )
            }
        }
        return FirstFetchConnectorConfiguration(
            connector: ClaudeCLIPDTMCPConnector(environment: environment),
            asOf: nil
        )
    }

    private func scriptedBackgroundRefreshEnabled() -> Bool {
        ProcessInfo.processInfo.environment["PDTBAR_SCRIPTED_BACKGROUND_REFRESH"] == "1"
    }

    private func firstFetchStateDirectory() -> URL {
        appSupportDirectory().appending(path: "pdtbar/state")
    }

    private func currentSnapshotDirectory() -> URL {
        activeSnapshotDirectory ?? firstFetchStateDirectory()
    }

    private func loadCachedPulse() -> PulseLifecycleResult? {
        let directory = currentSnapshotDirectory()
        return try? PressureRunner.cachedPulse(
            snapshotStore: SnapshotStore(directory: directory),
            pulseReadStore: PulseReadStore(directory: directory)
        )
    }

    private func pulseApplyingCurrentReadState(_ pulse: PulseLifecycleResult) -> PulseLifecycleResult {
        let readStore = PulseReadStore(directory: currentSnapshotDirectory())
        guard let readState = try? readStore.load() else {
            return pulse
        }
        return pulse.applyingReadState(readState)
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

    private func installMenuBarItem(_ descriptor: MenuDescriptor, cancelOpenMenu: Bool = true) {
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let item: NSStatusItem
        if let statusItem {
            item = statusItem
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem = item
        }
        if cancelOpenMenu {
            item.menu?.cancelTracking()
        }
        item.length = NSStatusItem.squareLength
        item.button?.title = surface.status.menuBarTitle
        item.button?.image = makeConcentrationStackStatusImage(from: surface.status.visual)
        item.button?.imagePosition = .imageOnly
        item.button?.identifier = NSUserInterfaceItemIdentifier(surface.status.accessibilityIdentifier)
        item.button?.toolTip = surface.status.toolTip
        item.button?.setAccessibilityLabel(surface.status.accessibilityLabel)
        item.button?.setAccessibilityIdentifier(surface.status.accessibilityIdentifier)
        item.menu = makeMenu(from: surface)
    }

    private func installPortfolioPulseDescriptor(_ descriptor: MenuDescriptor) {
        installMenuBarItem(onboardingCoordinator.completeFirstFetch(.succeeded(descriptor)).descriptor)
    }

    private func makeMenu(from surface: MenuBarSurface) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for section in surface.sections {
            let heading = makeSectionHeadingItem(
                title: section.title,
                accessibilityIdentifier: section.accessibilityIdentifier
            )
            menu.addItem(heading)
            for row in section.rows {
                menu.addItem(makeMenuItem(from: row))
            }
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Quit PDTBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func makeSectionHeadingItem(title: String, accessibilityIdentifier: String) -> NSMenuItem {
        let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        heading.setAccessibilityIdentifier(accessibilityIdentifier)
        heading.view = makeSectionHeadingView(title: title, accessibilityIdentifier: accessibilityIdentifier)
        heading.isEnabled = false
        return heading
    }

    private func makeSectionHeadingView(title: String, accessibilityIdentifier: String) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: 28))
        container.autoresizingMask = [.width]
        configureStaticMenuViewAccessibility(
            container,
            accessibilityIdentifier: accessibilityIdentifier,
            label: title
        )

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleField)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func makeMenuItem(from row: MenuBarRowSurface) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        if !row.accessibilityIdentifier.isEmpty {
            item.identifier = NSUserInterfaceItemIdentifier(row.accessibilityIdentifier)
            item.setAccessibilityIdentifier(row.accessibilityIdentifier)
        }
        if row.children.isEmpty {
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
            if row.actionTarget?.kind == .copyHoldingIdentifier {
                item.target = menuActionDispatcher
                item.action = #selector(MenuActionDispatcher.copyMenuRowAction(_:))
                item.representedObject = row.actionTarget
            }
            if row.role == .pulseMarkRead, let fingerprint = row.actionPayload {
                item.target = self
                item.action = #selector(markPulseItemRead(_:))
                item.representedObject = fingerprint
            }
        } else {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for child in row.children {
                submenu.addItem(makeMenuItem(from: child))
            }
            item.submenu = submenu
        }
        if item.action == nil && item.submenu == nil {
            item.view = makeStaticMenuRowView(
                title: row.title,
                detail: row.detail,
                accessibilityIdentifier: row.accessibilityIdentifier
            )
            item.isEnabled = false
        } else {
            item.isEnabled = true
            applyDetailSubtitle(row.detail, to: item, title: row.title)
        }
        return item
    }

    private func makeStaticMenuRowView(title: String, detail: String?, accessibilityIdentifier: String) -> NSView {
        let hasDetail = detail?.isEmpty == false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: hasDetail ? 42 : 30))
        container.autoresizingMask = [.width]
        configureStaticMenuViewAccessibility(
            container,
            accessibilityIdentifier: accessibilityIdentifier,
            label: detail.map { "\(title) - \($0)" } ?? title
        )

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleField)

        if let detail, !detail.isEmpty {
            let detailField = NSTextField(labelWithString: detail)
            detailField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
            detailField.textColor = NSColor.secondaryLabelColor
            detailField.lineBreakMode = .byTruncatingTail
            detailField.maximumNumberOfLines = 1
            detailField.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(detailField)

            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                titleField.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),

                detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                detailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
                detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            ])
        } else {
            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        return container
    }

    private func configureStaticMenuViewAccessibility(
        _ view: NSView,
        accessibilityIdentifier: String,
        label: String
    ) {
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel(label)
        if !accessibilityIdentifier.isEmpty {
            view.setAccessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private func applyDetailSubtitle(_ detail: String?, to item: NSMenuItem, title: String) {
        guard let detail, !detail.isEmpty else {
            return
        }
        if #available(macOS 14.4, *) {
            item.subtitle = detail
        } else {
            item.title = "\(title) - \(detail)"
        }
        item.toolTip = "\(title) - \(detail)"
    }

    @objc private func markPulseItemRead(_ sender: NSMenuItem) {
        guard let fingerprint = sender.representedObject as? String else {
            return
        }
        do {
            let directory = currentSnapshotDirectory()
            let readStore = PulseReadStore(directory: directory)
            try readStore.markRead(fingerprint)
            if let currentPulse {
                let refreshedPulse = currentPulse.applyingReadState(try readStore.load())
                self.currentPulse = refreshedPulse
                cachedPulseDescriptor = refreshedPulse.descriptor
                installPortfolioPulseDescriptor(refreshedPulse.descriptor)
                return
            }
            guard let cachedPulse = try PressureRunner.cachedPulse(
                snapshotStore: SnapshotStore(directory: directory),
                pulseReadStore: readStore
            ) else {
                return
            }
            currentPulse = cachedPulse
            let descriptor = cachedPulse.descriptor
            cachedPulseDescriptor = descriptor
            installPortfolioPulseDescriptor(descriptor)
        } catch {
            FileHandle.standardError.write(Data("pdtbar: mark read failed: \(error)\n".utf8))
        }
    }

    private func makeConcentrationStackStatusImage(from visual: StatusVisualState) -> NSImage {
        let size = NSSize(width: 24, height: 19)
        let image = NSImage(size: size, flipped: false) { _ in
            let maxBarHeight: CGFloat = 16.2
            let barWidth: CGFloat = 5.0
            let gap: CGFloat = 2.0
            let baseline: CGFloat = 1.2
            let startX: CGFloat = 2.5
            let fillAlpha: CGFloat = visual.isDimmed ? 0.36 : 0.72
            let outlineAlpha: CGFloat = visual.isDimmed ? 0.42 : 0.86

            for (index, rawHeight) in visual.barHeights.prefix(3).enumerated() {
                let normalizedHeight = CGFloat(max(0.30, min(1.0, rawHeight)))
                let height = normalizedHeight * maxBarHeight
                let rect = NSRect(
                    x: startX + CGFloat(index) * (barWidth + gap),
                    y: baseline,
                    width: barWidth,
                    height: height
                )
                let barPath = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
                if index < visual.filledBarCount {
                    NSGraphicsContext.saveGraphicsState()
                    barPath.addClip()
                    NSColor.black.withAlphaComponent(fillAlpha).setFill()
                    NSBezierPath(rect: NSRect(
                        x: rect.minX,
                        y: rect.minY,
                        width: rect.width,
                        height: rect.height
                    )).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                NSColor.black.withAlphaComponent(outlineAlpha).setStroke()
                barPath.lineWidth = 1.2
                barPath.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private protocol ClaudeLoginHandoff {
    func startLogin(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void)
}

private enum ClaudeLoginHandoffError: Error, CustomStringConvertible {
    case failed(ClaudeLoginFailureReason, String)

    var reason: ClaudeLoginFailureReason {
        switch self {
        case .failed(let reason, _):
            return reason
        }
    }

    var description: String {
        switch self {
        case .failed(_, let message):
            return message
        }
    }
}

private final class ClaudeCLILoginHandoff: ClaudeLoginHandoff, @unchecked Sendable {
    private let environment: [String: String]
    private let lock = NSLock()
    private var activeCancellation: ClaudeLoginCancellation?

    init(environment: [String: String]) {
        self.environment = environment
    }

    func startLogin(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let cancellation = ClaudeLoginCancellation()
        lock.lock()
        activeCancellation?.cancel()
        activeCancellation = cancellation
        lock.unlock()

        Task.detached(priority: .userInitiated) { [environment, cancellation, weak self] in
            let result = await ClaudeLoginRunner.run(
                timeout: 120,
                environment: environment,
                cancellation: cancellation,
                onPhaseChange: { _ in }
            )
            self?.clearActiveCancellation(cancellation)
            switch result.outcome {
            case .success:
                completion(.success(()))
            case .missingBinary:
                completion(.failure(ClaudeLoginHandoffError.failed(.missingBinary, "Claude CLI not found")))
            case .timedOut:
                completion(.failure(ClaudeLoginHandoffError.failed(.timedOut, "Claude login timed out")))
            case .failed(let status):
                completion(.failure(ClaudeLoginHandoffError.failed(
                    .failed,
                    "claude auth login exited with status \(status)"
                )))
            case .launchFailed(let message):
                completion(.failure(ClaudeLoginHandoffError.failed(.launchFailed, message)))
            case .cancelled:
                break
            }
        }
    }

    private func clearActiveCancellation(_ cancellation: ClaudeLoginCancellation) {
        lock.lock()
        if activeCancellation === cancellation {
            activeCancellation = nil
        }
        lock.unlock()
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
            if environment["PDTBAR_DISABLE_REAL_CLAUDE"] == "1" {
                return .notReady
            }
            return ClaudeCLIReadinessProbe(environment: environment).check()
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

private struct ClaudeCLIReadinessProbe {
    var environment: [String: String]

    func check() -> ClaudeReadinessProbeResult {
        guard ClaudeCLIProcess.executableExists(claudePath, environment: environment) else {
            return .missingClaudeLogin
        }
        do {
            let authStatus = try ClaudeCLIProcess.run(
                executable: claudePath,
                arguments: ["auth", "status"],
                timeout: min(timeoutSeconds, 10.0),
                environment: environment
            )
            let explicitAuthStatus = ClaudeAuthStatusParser.loggedInStatus(stdout: authStatus.stdout)
                ?? ClaudeAuthStatusParser.loggedInStatus(stdout: authStatus.stderr)
            if explicitAuthStatus == false {
                return .missingClaudeLogin
            }
            let result = try ClaudeCLIProcess.run(
                executable: claudePath,
                arguments: ["mcp", "list"],
                timeout: timeoutSeconds,
                environment: environment
            )
            let output = result.stdout + "\n" + result.stderr
            if result.exitCode == 0, ClaudeCLIPDTMCPConnector.pdtServerIsConnected(in: output) {
                return .ready
            }
            guard result.exitCode == 0 else {
                return .missingClaudeLogin
            }
            return .missingPDTMCP
        } catch {
            return .failed
        }
    }

    private var claudePath: String {
        environment["PDTBAR_CLAUDE_BIN"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
    }

    private var timeoutSeconds: TimeInterval {
        environment["PDTBAR_CLAUDE_READINESS_TIMEOUT"].flatMap(Double.init) ?? 20.0
    }
}

private final class ClaudeCLIPDTMCPConnector: PDTMCPConnector {
    private let environment: [String: String]
    private let claudePath: String
    private let model: String
    private let timeout: TimeInterval
    private let toolCallRetryPolicy: ClaudeToolCallRetryPolicy
    private var discoveredToolNames: [String: String] = [:]

    init(environment: [String: String]) {
        self.environment = environment
        self.claudePath = environment["PDTBAR_CLAUDE_BIN"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
        self.model = environment["PDTBAR_CLAUDE_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "opus"
        self.timeout = environment["PDTBAR_CLAUDE_TOOL_TIMEOUT"].flatMap(Double.init) ?? 120.0
        self.toolCallRetryPolicy = ClaudeToolCallRetryPolicy(
            retryCount: environment["PDTBAR_CLAUDE_TOOL_RETRY_COUNT"].flatMap(Int.init) ?? 1
        )
    }

    func availableReadTools() throws -> Set<String> {
        try availableReadTools(required: Set(PDTReadTools.requiredV1))
    }

    func availableReadTools(required: Set<String>) throws -> Set<String> {
        guard ClaudeCLIProcess.executableExists(claudePath, environment: environment) else {
            throw PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")
        }
        let result = try ClaudeCLIProcess.run(
            executable: claudePath,
            arguments: ["mcp", "list"],
            timeout: min(timeout, 30.0),
            environment: environment
        )
        let output = result.stdout + "\n" + result.stderr
        guard result.exitCode == 0,
              Self.pdtServerIsConnected(in: output)
        else {
            throw PDTMCPConnectorError.setupUnavailable("Claude PDT MCP server is not connected")
        }
        let requiredReadTools = PDTReadTools.requiredV1.filter { required.contains($0) }
        let resolved = try resolvedToolNames(for: requiredReadTools)
        var available = Set(resolved.keys)
        for tool in requiredReadTools where !available.contains(tool) {
            if (try? resolvedToolName(for: tool)) != nil {
                available.insert(tool)
            }
        }
        return available
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        guard PDTReadTools.requiredV1.contains(name) else {
            throw PDTMCPConnectorError.nonReadTool(name)
        }
        guard ClaudeCLIProcess.executableExists(claudePath, environment: environment) else {
            throw PDTMCPConnectorError.setupUnavailable("Claude CLI is unavailable")
        }
        let toolName = try resolvedToolName(for: name)
        var attempts = 0
        var lastError: Error?
        repeat {
            attempts += 1
            do {
                return try callReadToolOnce(name, resolvedToolName: toolName, arguments: arguments)
            } catch {
                lastError = error
                guard toolCallRetryPolicy.shouldRetry(error, afterAttempt: attempts) else {
                    throw error
                }
            }
        } while attempts < toolCallRetryPolicy.maxAttempts
        throw lastError ?? PDTMCPConnectorError.transientFailure("Claude \(name) call failed")
    }

    private func callReadToolOnce(
        _ name: String,
        resolvedToolName toolName: String,
        arguments: [String: String]
    ) throws -> Data {
        let sessionID = UUID().uuidString
        let commandArguments = [
            "--model", model,
            "--allowedTools", toolName,
            "--disallowedTools", disallowedTools().joined(separator: ","),
            "--session-id", sessionID,
            "-p", prompt(toolName: toolName, readToolName: name, arguments: arguments),
            "--output-format", "stream-json",
            "--verbose",
            "--no-session-persistence",
        ]
        let result = try ClaudeCLIProcess.run(
            executable: claudePath,
            arguments: commandArguments,
            timeout: timeout,
            environment: environment
        )
        let createdFiles = claudeToolResultFiles(sessionID: sessionID)
        defer {
            deleteClaudeToolResultFiles(pdtToolResultFiles(
                in: createdFiles,
                referencedBy: result.stdout,
                readToolName: name,
                sessionID: sessionID
            ))
        }
        guard result.exitCode == 0 else {
            throw PDTMCPConnectorError.transientFailure("Claude \(name) call failed")
        }
        return try toolResultData(for: toolName, createdFiles: createdFiles, in: result.stdout)
    }

    static func pdtServerIsConnected(in output: String) -> Bool {
        output
            .split(separator: "\n")
            .contains { line in
                let lowercasedLine = line.lowercased()
                return lowercasedLine.contains("connected")
                    && !lowercasedLine.contains("not connected")
                    && !lowercasedLine.contains("disconnected")
                    && (
                        lowercasedLine.contains("portfolio dividend tracker")
                            || lowercasedLine.contains("portfoliodividendtracker.com")
                            || lowercasedLine.contains("pdt")
                    )
            }
    }

    private func resolvedToolName(for readToolName: String) throws -> String {
        if let cached = discoveredToolNames[readToolName] {
            return cached
        }
        if let resolved = try resolvedToolNames(for: [readToolName])[readToolName] {
            return resolved
        }
        throw PDTMCPConnectorError.setupUnavailable("Claude could not find \(readToolName)")
    }

    private func resolvedToolNames(for readToolNames: [String]) throws -> [String: String] {
        let unresolved = readToolNames.filter { discoveredToolNames[$0] == nil }
        guard !unresolved.isEmpty else {
            return discoveredToolNames.filter { readToolNames.contains($0.key) }
        }
        let stillUnresolved = unresolved
        let toolList = stillUnresolved.joined(separator: ", ")
        var attempts = 0
        var lastResultExitCode: Int32 = 0
        repeat {
            attempts += 1
            let sessionID = UUID().uuidString
            let result = try ClaudeCLIProcess.run(
                executable: claudePath,
                arguments: [
                    "--model", model,
                    "--allowedTools", "ToolSearch",
                    "--disallowedTools", toolSearchDisallowedTools().joined(separator: ","),
                    "--session-id", sessionID,
                    "-p", "Use ToolSearch to find these PDT MCP read-only tools: \(toolList). Return only {\"status\":\"redacted-ok\"}.",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--no-session-persistence",
                ],
                timeout: min(timeout, 60.0),
                environment: environment
            )
            let createdFiles = claudeToolResultFiles(sessionID: sessionID)
            deleteClaudeToolResultFiles(pdtToolResultFiles(
                in: createdFiles,
                referencedBy: result.stdout,
                readToolNames: stillUnresolved,
                sessionID: sessionID
            ))
            lastResultExitCode = result.exitCode
            guard result.exitCode == 0 else {
                continue
            }
            let resolved = discoveredToolNames(for: stillUnresolved, in: result.stdout)
            discoveredToolNames.merge(resolved) { current, _ in current }
            if stillUnresolved.allSatisfy({ discoveredToolNames[$0] != nil }) {
                break
            }
        } while attempts < toolCallRetryPolicy.maxAttempts
        for readToolName in stillUnresolved where discoveredToolNames[readToolName] == nil {
            try resolveToolNameIndividually(readToolName)
        }
        let missing = stillUnresolved.filter { discoveredToolNames[$0] == nil }
        guard lastResultExitCode == 0 || missing.isEmpty else {
            throw PDTMCPConnectorError.setupUnavailable("Claude could not find \(toolList)")
        }
        return discoveredToolNames.filter { readToolNames.contains($0.key) }
    }

    private func resolveToolNameIndividually(_ readToolName: String) throws {
        var attempts = 0
        repeat {
            attempts += 1
            let sessionID = UUID().uuidString
            let result = try ClaudeCLIProcess.run(
                executable: claudePath,
                arguments: [
                    "--model", model,
                    "--allowedTools", "ToolSearch",
                    "--disallowedTools", toolSearchDisallowedTools().joined(separator: ","),
                    "--session-id", sessionID,
                    "-p", "Use ToolSearch to find exactly this PDT MCP read-only tool: \(readToolName). Return only {\"status\":\"redacted-ok\"}.",
                    "--output-format", "stream-json",
                    "--verbose",
                    "--no-session-persistence",
                ],
                timeout: min(timeout, 60.0),
                environment: environment
            )
            let createdFiles = claudeToolResultFiles(sessionID: sessionID)
            deleteClaudeToolResultFiles(pdtToolResultFiles(
                in: createdFiles,
                referencedBy: result.stdout,
                readToolNames: [readToolName],
                sessionID: sessionID
            ))
            guard result.exitCode == 0 else {
                continue
            }
            let resolved = discoveredToolNames(for: [readToolName], in: result.stdout)
            discoveredToolNames.merge(resolved) { current, _ in current }
            if discoveredToolNames[readToolName] != nil {
                break
            }
        } while attempts < toolCallRetryPolicy.maxAttempts
    }

    private func discoveredToolNames(for readToolNames: [String], in output: String) -> [String: String] {
        readToolNames.reduce(into: [String: String]()) { resolved, readToolName in
            if let toolName = discoveredToolName(for: readToolName, in: output) {
                resolved[readToolName] = toolName
            }
        }
    }

    private func discoveredToolName(for readToolName: String, in output: String) -> String? {
        let pattern = #"mcp__[A-Za-z0-9_.-]+__\#(NSRegularExpression.escapedPattern(for: readToolName))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return expression.matches(in: output, range: range).compactMap { match in
            Range(match.range, in: output).map { String(output[$0]) }
        }.first
    }

    private func prompt(toolName: String, readToolName: String, arguments: [String: String]) -> String {
        let argumentData = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        let argumentJSON = String(decoding: argumentData, as: UTF8.self)
        return """
        PDTBar needs one local read-only PDT MCP result.

        Rules:
        - Call exactly this read-only PDT MCP tool: \(toolName)
        - This is the requested PDT read tool: \(readToolName)
        - Use exactly these JSON arguments: \(argumentJSON)
        - Do not call any write, create, update, delete, remove, post, put, or set tool.
        - Do not print holdings, values, account identifiers, endpoints, credentials, or raw tool output in your final answer.
        - After the tool call, return only {"status":"redacted-ok"}.
        """
    }

    private func disallowedTools() -> [String] {
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

    private func toolSearchDisallowedTools() -> [String] {
        disallowedTools().filter { !$0.hasPrefix("mcp__") }
    }

    private func toolResultData(for toolName: String, createdFiles: Set<URL>, in output: String) throws -> Data {
        let objects = output
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        let matchingToolUseIDs = Set(objects.flatMap { toolUseIDs(for: toolName, in: $0) })
        guard !matchingToolUseIDs.isEmpty else {
            throw PDTMCPConnectorError.transientFailure("Claude did not call \(toolName)")
        }
        for object in objects {
            if let structured = structuredToolResult(in: object, matching: matchingToolUseIDs) {
                return try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys])
            }
            if let file = toolResultFile(in: object, matching: matchingToolUseIDs, createdFiles: createdFiles),
               let data = try? Data(contentsOf: file)
            {
                return data
            }
            if let data = toolResultContentData(in: object, matching: matchingToolUseIDs) {
                return data
            }
        }
        throw PDTMCPConnectorError.transientFailure("Claude did not return structured data for \(toolName)")
    }

    private func toolUseIDs(for toolName: String, in object: Any) -> [String] {
        if let array = object as? [Any] {
            return array.flatMap { toolUseIDs(for: toolName, in: $0) }
        }
        guard let dictionary = object as? [String: Any] else {
            return []
        }
        let current: [String]
        if dictionary["type"] as? String == "tool_use",
           dictionary["name"] as? String == toolName,
           let id = dictionary["id"] as? String
        {
            current = [id]
        } else {
            current = []
        }
        return current + dictionary.values.flatMap { toolUseIDs(for: toolName, in: $0) }
    }

    private func structuredToolResult(in object: Any, matching ids: Set<String>) -> Any? {
        if let array = object as? [Any] {
            for item in array {
                if let structured = structuredToolResult(in: item, matching: ids) {
                    return structured
                }
            }
            return nil
        }
        guard let dictionary = object as? [String: Any] else {
            return nil
        }
        if dictionary["type"] as? String == "tool_result",
           let toolUseID = dictionary["tool_use_id"] as? String,
           ids.contains(toolUseID),
           let structured = dictionary["structuredContent"]
        {
            return structured
        }
        for value in dictionary.values {
            if let structured = structuredToolResult(in: value, matching: ids) {
                return structured
            }
        }
        return nil
    }

    private func toolResultContentData(in object: Any, matching ids: Set<String>) -> Data? {
        if let array = object as? [Any] {
            for item in array {
                if let data = toolResultContentData(in: item, matching: ids) {
                    return data
                }
            }
            return nil
        }
        guard let dictionary = object as? [String: Any] else {
            return nil
        }
        if dictionary["type"] as? String == "tool_result",
           let toolUseID = dictionary["tool_use_id"] as? String,
           ids.contains(toolUseID),
           let content = dictionary["content"],
           let data = jsonData(inToolResultContent: content)
        {
            return data
        }
        for value in dictionary.values {
            if let data = toolResultContentData(in: value, matching: ids) {
                return data
            }
        }
        return nil
    }

    private func toolResultFile(in object: Any, matching ids: Set<String>, createdFiles: Set<URL>) -> URL? {
        if let array = object as? [Any] {
            for item in array {
                if let file = toolResultFile(in: item, matching: ids, createdFiles: createdFiles) {
                    return file
                }
            }
            return nil
        }
        guard let dictionary = object as? [String: Any] else {
            return nil
        }
        if dictionary["type"] as? String == "tool_result",
           let toolUseID = dictionary["tool_use_id"] as? String,
           ids.contains(toolUseID),
           let content = dictionary["content"],
           let file = savedToolResultFile(inToolResultContent: content, createdFiles: createdFiles)
        {
            return file
        }
        for value in dictionary.values {
            if let file = toolResultFile(in: value, matching: ids, createdFiles: createdFiles) {
                return file
            }
        }
        return nil
    }

    private func jsonData(inToolResultContent content: Any) -> Data? {
        if let text = content as? String {
            let data = Data(text.utf8)
            return (try? JSONSerialization.jsonObject(with: data)) == nil ? nil : data
        }
        if let array = content as? [Any] {
            for item in array {
                if let data = jsonData(inToolResultContent: item) {
                    return data
                }
            }
            return nil
        }
        guard let dictionary = content as? [String: Any] else {
            return nil
        }
        if let text = dictionary["text"] as? String,
           let data = jsonData(inToolResultContent: text)
        {
            return data
        }
        for value in dictionary.values {
            if let data = jsonData(inToolResultContent: value) {
                return data
            }
        }
        return nil
    }

    private func savedToolResultFile(inToolResultContent content: Any, createdFiles: Set<URL>) -> URL? {
        if let text = content as? String {
            return savedToolResultFile(in: text, createdFiles: createdFiles)
        }
        if let array = content as? [Any] {
            for item in array {
                if let file = savedToolResultFile(inToolResultContent: item, createdFiles: createdFiles) {
                    return file
                }
            }
            return nil
        }
        guard let dictionary = content as? [String: Any] else {
            return nil
        }
        if let text = dictionary["text"] as? String,
           let file = savedToolResultFile(in: text, createdFiles: createdFiles)
        {
            return file
        }
        for value in dictionary.values {
            if let file = savedToolResultFile(inToolResultContent: value, createdFiles: createdFiles) {
                return file
            }
        }
        return nil
    }

    private func savedToolResultFile(in content: String, createdFiles: Set<URL>) -> URL? {
        savedToolResultFiles(in: content).first { createdFiles.contains($0) }
    }

    private func savedToolResultFiles(in content: String) -> [URL] {
        let projectsRoot = claudeProjectsDirectory().path
        var files: [URL] = []
        var searchStart = content.startIndex
        while let rootRange = content.range(of: projectsRoot, range: searchStart..<content.endIndex),
              let extensionRange = content.range(of: ".txt", range: rootRange.lowerBound..<content.endIndex)
        {
            let path = String(content[rootRange.lowerBound..<extensionRange.upperBound])
            files.append(URL(fileURLWithPath: path))
            searchStart = extensionRange.upperBound
        }
        return files
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

    private func deleteClaudeToolResultFiles(_ files: [URL]) {
        for file in Set(files) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func pdtToolResultFiles(
        in createdFiles: Set<URL>,
        referencedBy output: String,
        readToolName: String,
        sessionID: String
    ) -> [URL] {
        pdtToolResultFiles(
            in: createdFiles,
            referencedBy: output,
            readToolNames: [readToolName],
            sessionID: sessionID
        )
    }

    private func pdtToolResultFiles(
        in createdFiles: Set<URL>,
        referencedBy output: String,
        readToolNames: [String],
        sessionID: String
    ) -> [URL] {
        let deadline = Date().addingTimeInterval(1.0)
        var sessionFiles = Set<URL>()
        repeat {
            sessionFiles = claudeToolResultFiles(sessionID: sessionID)
            if sessionFiles.contains(where: { file in
                readToolNames.contains { file.lastPathComponent.contains($0) }
            }) {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        let referenced = savedToolResultFiles(in: output).filter { createdFiles.contains($0) }
        let matchingReadTool = createdFiles.union(sessionFiles).filter { file in
            readToolNames.contains { file.lastPathComponent.contains($0) }
        }
        return referenced + matchingReadTool
    }
}

private struct ClaudeCLIProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class LockedDataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer {
            lock.unlock()
        }
        return data
    }
}

private enum ClaudeCLIProcess {
    static func executableExists(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        resolvedExecutable(executable, environment: environment) != nil
    }

    static func resolvedExecutable(
        _ executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }
        for directory in executableSearchDirectories(environment: environment) {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]
    ) throws -> ClaudeCLIProcessResult {
        guard let resolvedExecutable = resolvedExecutable(executable, environment: environment) else {
            return ClaudeCLIProcessResult(stdout: "", stderr: "\(executable) not found", exitCode: -1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = arguments
        let workingDirectory = FileManager.default.temporaryDirectory.appending(path: "pdtbar-claude-cli")
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        process.currentDirectoryURL = workingDirectory
        var processEnvironment = environment
        processEnvironment["PATH"] = executableSearchDirectories(environment: environment).joined(separator: ":")
        process.environment = processEnvironment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutData = LockedDataAccumulator()
        let stderrData = LockedDataAccumulator()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData.append(stdout.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData.append(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        try process.run()
        let processGroup = setpgid(process.processIdentifier, process.processIdentifier) == 0
            ? process.processIdentifier
            : nil
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            let descendants = TTYProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
            process.terminate()
            TTYProcessTreeTerminator.terminateProcessTree(
                rootPID: process.processIdentifier,
                processGroup: processGroup,
                signal: SIGTERM,
                knownDescendants: descendants
            )
            let waitDeadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < waitDeadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                TTYProcessTreeTerminator.terminateProcessTree(
                    rootPID: process.processIdentifier,
                    processGroup: processGroup,
                    signal: SIGKILL,
                    knownDescendants: descendants
                )
            }
            process.waitUntilExit()
            readers.wait()
            return ClaudeCLIProcessResult(
                stdout: String(decoding: stdoutData.snapshot(), as: UTF8.self),
                stderr: String(decoding: stderrData.snapshot(), as: UTF8.self),
                exitCode: -1
            )
        }
        process.waitUntilExit()
        readers.wait()
        return ClaudeCLIProcessResult(
            stdout: String(decoding: stdoutData.snapshot(), as: UTF8.self),
            stderr: String(decoding: stderrData.snapshot(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private static func executableSearchDirectories(environment: [String: String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (pathDirectories + defaults).filter { directory in
            seen.insert(directory).inserted
        }
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
