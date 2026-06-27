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
    private let launchRuntime = PDTLaunchRuntime()
    private var statusItem: NSStatusItem?
    private var portfolioRefreshInFlight = false
    private var portfolioFetchStartedAt: Date?
    private var portfolioFetchProgressTimer: Timer?
    private var activeSnapshotDirectory: URL?
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
            handleLaunchUpdate(launchRuntime.launch(cachedPulse: cachedPulse))
        case let .fixture(fixture):
            let dataSource = PDTFixtureDataSource(fixture: fixture)
            let snapshotDirectory = try fixtureSnapshotDirectory()
            activeSnapshotDirectory = snapshotDirectory
            let result = try PressureRunner.run(
                dataSource: dataSource,
                snapshotStore: SnapshotStore(directory: snapshotDirectory),
                pulseReadStore: PulseReadStore(directory: snapshotDirectory)
            )
            launchRuntime.replaceCurrentPulse(result)
            installMenuBarItem(result.descriptor)
        }
    }

    private func startClaudeReadinessProbe(attemptID: Int) {
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
                self.handleLaunchUpdate(self.launchRuntime.completeReadinessProbe(
                    result,
                    attemptID: attemptID,
                    allowsBackgroundDetailRefresh: self.returningLaunchBackgroundDetailRefreshEnabled()
                ))
            }
        }
    }

    private func returningLaunchBackgroundDetailRefreshEnabled() -> Bool {
        guard launchRuntime.currentPulse != nil else {
            return false
        }
        return (try? firstFetchConnectorConfiguration().shouldStartBackgroundRefresh) ?? false
    }

    private func startFirstPortfolioFetch() {
        do {
            let configuration = try firstFetchConnectorConfiguration()
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
        stopPortfolioFetchProgressTimer()
        if let pulse = outcome.pulse {
            let refreshedPulse = pulseApplyingCurrentReadState(pulse)
            handleLaunchUpdate(launchRuntime.completeFirstFetch(.succeeded(refreshedPulse)))
            if outcome.shouldStartBackgroundRefresh {
                if let update = launchRuntime.beginBackgroundDetailRefresh() {
                    handleLaunchUpdate(update)
                }
            }
            return
        }
        let errorDescription = outcome.errorDescription ?? "unknown error"
        FileHandle.standardError.write(Data("pdtbar: first fetch failed: \(errorDescription)\n".utf8))
        handleLaunchUpdate(launchRuntime.completeFirstFetch(.failed(errorDescription)))
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
        guard launchRuntime.firstFetchInFlight else {
            stopPortfolioFetchProgressTimer()
            return
        }
        installPortfolioFetchProgressMenu(cancelOpenMenu: false)
    }

    private func installPortfolioFetchProgressMenu(cancelOpenMenu: Bool) {
        let elapsedSeconds = portfolioFetchStartedAt.map {
            Int(Date().timeIntervalSince($0))
        } ?? 0
        guard let update = launchRuntime.firstFetchProgress(fetchingElapsedSeconds: elapsedSeconds) else {
            return
        }
        installMenuBarItem(update.descriptor, cancelOpenMenu: cancelOpenMenu)
    }

    @objc private func retryPortfolioFetch(_ sender: NSMenuItem) {
        guard let update = launchRuntime.retryFirstFetch() else {
            return
        }
        handleLaunchUpdate(update)
    }

    private func startBackgroundPortfolioRefresh() {
        guard !portfolioRefreshInFlight else {
            return
        }
        portfolioRefreshInFlight = true
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
                              let update = self.launchRuntime.backgroundDetailRefreshProgress(progress)
                        else {
                            return
                        }
                        self.installMenuBarItem(update.descriptor, cancelOpenMenu: false)
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
            handleLaunchUpdate(launchRuntime.completeBackgroundDetailRefresh(
                .succeeded(pulse, outcome: outcome.detailRefreshOutcome ?? .completed)
            ))
            return
        }
        let errorDescription = outcome.errorDescription ?? "unknown error"
        FileHandle.standardError.write(Data("pdtbar: background refresh failed: \(errorDescription)\n".utf8))
        handleLaunchUpdate(launchRuntime.completeBackgroundDetailRefresh(.failed(errorDescription)))
    }

    @objc private func retryClaudeReadiness(_ sender: NSMenuItem) {
        guard let update = launchRuntime.retryReadiness() else {
            return
        }
        handleLaunchUpdate(update)
    }

    @objc private func loginWithClaude(_ sender: NSMenuItem) {
        let attempt = claudeLoginAttemptGate.begin()
        handleLaunchUpdate(launchRuntime.beginLoginHandoff())
        loginHandoff.startLogin { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.claudeLoginAttemptGate.finish(attempt) else {
                    return
                }
                switch result {
                case .success:
                    self.handleLaunchUpdate(self.launchRuntime.completeLoginHandoff(.succeeded))
                case .failure(let error):
                    FileHandle.standardError.write(Data("pdtbar: Claude handoff failed: \(error)\n".utf8))
                    if let handoffError = error as? ClaudeLoginHandoffError {
                        self.handleLaunchUpdate(
                            self.launchRuntime.completeLoginHandoff(.failed(handoffError.reason))
                        )
                    } else {
                        self.handleLaunchUpdate(self.launchRuntime.completeLoginHandoff(.failed(.failed)))
                    }
                }
            }
        }
    }

    private func handleLaunchUpdate(_ update: PDTOnboardingUpdate) {
        installMenuBarItem(update.descriptor)
        switch update.effect {
        case .none:
            return
        case .probeReadiness:
            startClaudeReadinessProbe(attemptID: launchRuntime.readinessAttemptID)
        case .startLoginHandoff:
            return
        case .startFirstFetch:
            startFirstPortfolioFetch()
        case .startBackgroundDetailRefresh:
            startBackgroundPortfolioRefresh()
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
            connector: ClaudeLocalConnection(environment: ProcessInfo.processInfo.environment),
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
            connector: ClaudeLocalConnection(environment: environment),
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
        if let barChart = row.barChart {
            item.view = makePortfolioAllocationChartRowView(
                title: row.title,
                detail: row.detail,
                barChart: barChart,
                accessibilityIdentifier: row.accessibilityIdentifier
            )
            item.isEnabled = false
        } else if item.action == nil && item.submenu == nil {
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

    private func makePortfolioAllocationChartRowView(
        title: String,
        detail: String?,
        barChart: MenuRowBarChart,
        accessibilityIdentifier: String
    ) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: 136))
        container.autoresizingMask = [.width]
        let chartSummary = barChart.bars.map { "\($0.label) \($0.percentageLabel)" }.joined(separator: ", ")
        configureStaticMenuViewAccessibility(
            container,
            accessibilityIdentifier: accessibilityIdentifier,
            label: ([title, detail, chartSummary].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }).joined(separator: " - ")
        )

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleField)

        let detailField = NSTextField(labelWithString: detail ?? "")
        detailField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        detailField.textColor = NSColor.secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.maximumNumberOfLines = 1
        detailField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailField)

        let chartStack = NSStackView()
        chartStack.orientation = .horizontal
        chartStack.alignment = .bottom
        chartStack.distribution = .fillEqually
        chartStack.spacing = 8
        chartStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chartStack)

        let maxWeight = max(barChart.bars.map(\.weight).max() ?? 0.0, 0.01)
        let colors: [NSColor] = [
            .systemBlue,
            .systemGreen,
            .systemTeal,
            .systemOrange,
            .systemIndigo,
        ]

        for (index, bar) in barChart.bars.enumerated() {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.distribution = .fill
            column.spacing = 3
            column.toolTip = bar.detail

            let percentageField = NSTextField(labelWithString: bar.percentageLabel)
            percentageField.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            percentageField.textColor = NSColor.labelColor
            percentageField.alignment = .center
            percentageField.lineBreakMode = .byTruncatingTail
            percentageField.maximumNumberOfLines = 1
            percentageField.toolTip = bar.detail

            let barArea = NSView()
            barArea.translatesAutoresizingMaskIntoConstraints = false

            let barView = NSBox()
            barView.boxType = .custom
            barView.cornerRadius = 3
            barView.fillColor = colors[index % colors.count].withAlphaComponent(0.82)
            barView.translatesAutoresizingMaskIntoConstraints = false
            barView.toolTip = bar.detail
            barArea.addSubview(barView)

            let normalizedHeight = CGFloat(max(0.08, min(1.0, bar.weight / maxWeight)))
            NSLayoutConstraint.activate([
                barArea.heightAnchor.constraint(equalToConstant: 42),
                barView.widthAnchor.constraint(equalTo: barArea.widthAnchor, multiplier: 0.58),
                barView.centerXAnchor.constraint(equalTo: barArea.centerXAnchor),
                barView.bottomAnchor.constraint(equalTo: barArea.bottomAnchor),
                barView.heightAnchor.constraint(equalTo: barArea.heightAnchor, multiplier: normalizedHeight),
            ])

            let labelField = NSTextField(labelWithString: bar.label)
            labelField.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            labelField.textColor = NSColor.secondaryLabelColor
            labelField.alignment = .center
            labelField.lineBreakMode = .byTruncatingTail
            labelField.maximumNumberOfLines = 1
            labelField.toolTip = bar.detail

            column.addArrangedSubview(percentageField)
            column.addArrangedSubview(barArea)
            column.addArrangedSubview(labelField)
            chartStack.addArrangedSubview(column)
        }

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            titleField.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),

            chartStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            chartStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            chartStack.topAnchor.constraint(equalTo: detailField.bottomAnchor, constant: 8),
            chartStack.heightAnchor.constraint(equalToConstant: 78),
        ])

        return container
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
            if let currentPulse = launchRuntime.currentPulse {
                let refreshedPulse = currentPulse.applyingReadState(try readStore.load())
                handleLaunchUpdate(launchRuntime.publishPulse(refreshedPulse))
                return
            }
            guard let cachedPulse = try PressureRunner.cachedPulse(
                snapshotStore: SnapshotStore(directory: directory),
                pulseReadStore: readStore
            ) else {
                return
            }
            handleLaunchUpdate(launchRuntime.publishPulse(cachedPulse))
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
    private var activeCancellation: ClaudeLocalLoginCancellation?

    init(environment: [String: String]) {
        self.environment = environment
    }

    func startLogin(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let cancellation = ClaudeLocalLoginCancellation()
        lock.lock()
        activeCancellation?.cancel()
        activeCancellation = cancellation
        lock.unlock()

        Task.detached(priority: .userInitiated) { [environment, cancellation, weak self] in
            let result = await ClaudeLocalLoginRunner(environment: environment).run(
                timeout: 120,
                cancellation: cancellation,
                onPhaseChange: { _ in }
            )
            self?.clearActiveCancellation(cancellation)
            switch result {
            case .success:
                completion(.success(()))
            case .failed(let reason, let message):
                completion(.failure(ClaudeLoginHandoffError.failed(reason, message)))
            case .cancelled:
                break
            }
        }
    }

    private func clearActiveCancellation(_ cancellation: ClaudeLocalLoginCancellation) {
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
            return ClaudeLocalConnection(environment: environment).checkReadiness()
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
