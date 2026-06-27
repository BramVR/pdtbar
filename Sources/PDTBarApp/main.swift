import AppKit
import Darwin
import Foundation
import PDTBarAppSupport
import PDTBarCore

private struct PortfolioFetchOutcome: @unchecked Sendable {
    var pulse: PulseLifecycleResult? = nil
    var errorDescription: String?
    var detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome?
    var detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic?
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
                outcome = PortfolioFetchOutcome(
                    errorDescription: "\(error)",
                    detailRefreshDiagnostic: try? snapshotStore.loadLastDetailRefreshDiagnostic()
                )
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
        handleLaunchUpdate(launchRuntime.completeBackgroundDetailRefresh(
            .failed(errorDescription, diagnostic: outcome.detailRefreshDiagnostic)
        ))
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
            if row.actionTarget?.kind == .copyHoldingIdentifier || row.actionTarget?.kind == .copyDataHealthDiagnostic {
                item.target = menuActionDispatcher
                item.action = #selector(MenuActionDispatcher.copyMenuRowAction(_:))
                item.representedObject = row.actionTarget
            }
            if row.role == .pulseMarkRead, let fingerprint = row.actionPayload {
                item.target = self
                item.action = #selector(markPulseItemRead(_:))
                item.representedObject = fingerprint
            }
            if row.role == .openPDT {
                item.target = self
                item.action = #selector(openPDT(_:))
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

    @objc private func openPDT(_ sender: NSMenuItem) {
        guard let url = URL(string: "https://app.portfoliodividendtracker.com/login?locale=en") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func makePortfolioAllocationChartRowView(
        title: String,
        detail: String?,
        barChart: MenuRowBarChart,
        accessibilityIdentifier: String
    ) -> NSView {
        let hasDetail = detail?.isEmpty == false
        let rowHeight: CGFloat = hasDetail ? 226 : 212
        let container = PortfolioAllocationChartRowView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: rowHeight))
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

        let detailField: NSTextField?
        if let detail, !detail.isEmpty {
            let field = NSTextField(labelWithString: detail)
            field.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = NSColor.secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)
            detailField = field
        } else {
            detailField = nil
        }

        let chartAxisView = PortfolioAllocationYAxisView(bars: barChart.bars)
        chartAxisView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chartAxisView)

        let chartScrollView = NSScrollView()
        chartScrollView.borderType = .noBorder
        chartScrollView.drawsBackground = false
        chartScrollView.hasVerticalScroller = false
        chartScrollView.hasHorizontalScroller = barChart.bars.count > PortfolioAllocationVerticalBarChartView.visibleSlotCount
        chartScrollView.autohidesScrollers = barChart.bars.count <= PortfolioAllocationVerticalBarChartView.visibleSlotCount
        chartScrollView.horizontalScrollElasticity = .allowed
        chartScrollView.scrollerStyle = .overlay
        chartScrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chartScrollView)

        let chartView = PortfolioAllocationVerticalBarChartView(bars: barChart.bars)
        let chartAxisWidth = PortfolioAllocationYAxisView.axisWidth
        let chartAxisGap = PortfolioAllocationYAxisView.axisGap
        let chartViewportWidth = menuItemViewWidth - 20 - chartAxisWidth - chartAxisGap - 28
        let chartContentWidth = PortfolioAllocationVerticalBarChartView.contentWidth(
            viewportWidth: chartViewportWidth,
            barCount: barChart.bars.count
        )
        chartView.frame = NSRect(
            x: 0,
            y: 0,
            width: chartContentWidth,
            height: PortfolioAllocationVerticalBarChartView.chartHeight
        )
        chartView.autoresizingMask = [.height]
        chartScrollView.documentView = chartView

        let xAxisScrollView = NSScrollView()
        xAxisScrollView.borderType = .noBorder
        xAxisScrollView.drawsBackground = false
        xAxisScrollView.hasVerticalScroller = false
        xAxisScrollView.hasHorizontalScroller = false
        xAxisScrollView.horizontalScrollElasticity = .none
        xAxisScrollView.scrollerStyle = .overlay
        xAxisScrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(xAxisScrollView)

        let xAxisView = PortfolioAllocationXAxisView(bars: barChart.bars)
        xAxisView.frame = NSRect(
            x: 0,
            y: 0,
            width: chartContentWidth,
            height: PortfolioAllocationXAxisView.axisHeight
        )
        xAxisView.autoresizingMask = [.height]
        xAxisScrollView.documentView = xAxisView

        let selectedAccent = NSBox()
        selectedAccent.boxType = .custom
        selectedAccent.borderWidth = 0
        selectedAccent.cornerRadius = 1
        selectedAccent.fillColor = PortfolioAllocationVerticalBarChartView.barColor
        selectedAccent.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectedAccent)

        let selectedTitleField = NSTextField(labelWithString: "")
        selectedTitleField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        selectedTitleField.textColor = NSColor.secondaryLabelColor
        selectedTitleField.lineBreakMode = .byTruncatingTail
        selectedTitleField.maximumNumberOfLines = 1
        selectedTitleField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectedTitleField)

        let selectedDetailField = NSTextField(labelWithString: "")
        selectedDetailField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1)
        selectedDetailField.textColor = NSColor.tertiaryLabelColor
        selectedDetailField.lineBreakMode = .byTruncatingTail
        selectedDetailField.maximumNumberOfLines = 1
        selectedDetailField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectedDetailField)

        let applySelection: (MenuRowBarChart.Bar?) -> Void = { bar in
            guard let bar else {
                selectedTitleField.stringValue = "Hover a bar for details"
                selectedDetailField.stringValue = ""
                selectedAccent.isHidden = true
                return
            }
            selectedTitleField.stringValue = "\(bar.label): \(bar.percentageLabel)"
            selectedDetailField.stringValue = bar.detail
            selectedAccent.isHidden = false
        }
        chartView.onSelectionChanged = applySelection
        applySelection(chartView.selectedBar)

        container.mirrorHorizontalScroll(from: chartScrollView, to: xAxisScrollView)

        var constraints = [
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            titleField.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),

            chartAxisView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            chartAxisView.widthAnchor.constraint(equalToConstant: chartAxisWidth),
            chartAxisView.heightAnchor.constraint(equalToConstant: PortfolioAllocationVerticalBarChartView.chartHeight),

            chartScrollView.leadingAnchor.constraint(equalTo: chartAxisView.trailingAnchor, constant: chartAxisGap),
            chartScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            chartScrollView.heightAnchor.constraint(equalToConstant: PortfolioAllocationVerticalBarChartView.chartHeight),

            xAxisScrollView.leadingAnchor.constraint(equalTo: chartScrollView.leadingAnchor),
            xAxisScrollView.trailingAnchor.constraint(equalTo: chartScrollView.trailingAnchor),
            xAxisScrollView.topAnchor.constraint(equalTo: chartScrollView.bottomAnchor, constant: -1),
            xAxisScrollView.heightAnchor.constraint(equalToConstant: PortfolioAllocationXAxisView.axisHeight),

            selectedAccent.leadingAnchor.constraint(equalTo: chartAxisView.leadingAnchor),
            selectedAccent.topAnchor.constraint(equalTo: xAxisScrollView.bottomAnchor, constant: 8),
            selectedAccent.widthAnchor.constraint(equalToConstant: 2),
            selectedAccent.heightAnchor.constraint(equalToConstant: 30),

            selectedTitleField.leadingAnchor.constraint(equalTo: selectedAccent.trailingAnchor, constant: 8),
            selectedTitleField.trailingAnchor.constraint(equalTo: chartScrollView.trailingAnchor),
            selectedTitleField.topAnchor.constraint(equalTo: xAxisScrollView.bottomAnchor, constant: 5),

            selectedDetailField.leadingAnchor.constraint(equalTo: selectedTitleField.leadingAnchor),
            selectedDetailField.trailingAnchor.constraint(equalTo: selectedTitleField.trailingAnchor),
            selectedDetailField.topAnchor.constraint(equalTo: selectedTitleField.bottomAnchor, constant: 1),
            selectedDetailField.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ]

        let chartTopAnchor = detailField?.bottomAnchor ?? titleField.bottomAnchor
        constraints += [
            chartAxisView.topAnchor.constraint(equalTo: chartTopAnchor, constant: 9),
            chartScrollView.topAnchor.constraint(equalTo: chartTopAnchor, constant: 9),
        ]
        if let detailField {
            constraints += [
                detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                detailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
                detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            ]
        }

        NSLayoutConstraint.activate(constraints)

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

private final class PortfolioAllocationChartRowView: NSView {
    private weak var sourceScrollView: NSScrollView?
    private weak var targetScrollView: NSScrollView?

    func mirrorHorizontalScroll(from sourceScrollView: NSScrollView, to targetScrollView: NSScrollView) {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        self.sourceScrollView = sourceScrollView
        self.targetScrollView = targetScrollView
        sourceScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sourceBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: sourceScrollView.contentView
        )
    }

    @objc
    private func sourceBoundsDidChange(_ notification: Notification) {
        guard let sourceScrollView, let targetScrollView else { return }
        let origin = sourceScrollView.contentView.bounds.origin
        targetScrollView.contentView.setBoundsOrigin(NSPoint(x: origin.x, y: 0))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private final class PortfolioAllocationVerticalBarChartView: NSView {
    static let barColor = NSColor(calibratedRed: 0.28, green: 0.68, blue: 0.73, alpha: 0.92)
    static let visibleSlotCount = 30
    static let chartHeight: CGFloat = 114

    private let bars: [MenuRowBarChart.Bar]
    private var trackingArea: NSTrackingArea?
    private var selectedIndex: Int? {
        didSet {
            guard selectedIndex != oldValue else { return }
            self.needsDisplay = true
            self.onSelectionChanged?(self.selectedBar)
        }
    }

    var onSelectionChanged: ((MenuRowBarChart.Bar?) -> Void)?

    var selectedBar: MenuRowBarChart.Bar? {
        guard let selectedIndex, self.bars.indices.contains(selectedIndex) else { return nil }
        return self.bars[selectedIndex]
    }

    override var isFlipped: Bool {
        true
    }

    init(bars: [MenuRowBarChart.Bar]) {
        self.bars = bars
        self.selectedIndex = bars.isEmpty ? nil : 0
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    static func contentWidth(viewportWidth: CGFloat, barCount: Int) -> CGFloat {
        let visibleWidth = max(viewportWidth, 1)
        let slotCount = max(barCount, Self.visibleSlotCount)
        return visibleWidth * CGFloat(slotCount) / CGFloat(Self.visibleSlotCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.acceptsMouseMovedEvents = true
        self.updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved,
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.updateSelection(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        self.updateSelection(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !self.bars.isEmpty, self.bounds.width > 1, self.bounds.height > 1 else { return }

        let plotRect = Self.plotRect(in: self.bounds)
        let totalSlotCount = self.totalSlotCount
        let leadingSlotCount = self.leadingSlotCount
        let slotWidth = plotRect.width / CGFloat(totalSlotCount)
        let barHalfWidth = Self.barHalfWidth(slotWidth: slotWidth)
        let barWidth = barHalfWidth * 2
        let scaleMaxWeight = Self.scaleMaxWeight(for: self.bars)

        if let selectedIndex {
            let centerX = plotRect.minX + slotWidth * (CGFloat(leadingSlotCount + selectedIndex) + 0.5)
            let bandRect = NSRect(
                x: centerX - barHalfWidth,
                y: plotRect.minY,
                width: barWidth,
                height: plotRect.height
            )
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            bandRect.fill()
        }

        for (index, bar) in self.bars.enumerated() {
            let weight = Self.clampedWeight(bar.weight)
            let barHeight = max(weight > 0 ? 3 : 0, plotRect.height * weight / scaleMaxWeight)
            let centerX = plotRect.minX + slotWidth * (CGFloat(leadingSlotCount + index) + 0.5)
            let barRect = NSRect(
                x: centerX - barWidth / 2,
                y: plotRect.maxY - barHeight,
                width: barWidth,
                height: barHeight
            )
            Self.barColor.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3).fill()
        }

    }

    private func updateSelection(with event: NSEvent) {
        let location = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(location), !self.bars.isEmpty else { return }
        let plotWidth = max(self.bounds.width, 1)
        let slotWidth = plotWidth / CGFloat(self.totalSlotCount)
        let rawSlot = Int(floor(location.x / slotWidth))
        let index = rawSlot - self.leadingSlotCount
        guard self.bars.indices.contains(index) else { return }
        self.selectedIndex = index
    }

    private static func clampedWeight(_ weight: Double) -> CGFloat {
        guard weight.isFinite, weight > 0 else { return 0 }
        return CGFloat(min(weight, 1))
    }

    static func totalSlotCount(for barCount: Int) -> Int {
        max(barCount, Self.visibleSlotCount)
    }

    static func leadingSlotCount(for barCount: Int) -> Int {
        max((Self.visibleSlotCount - barCount) / 2, 0)
    }

    static func plotRect(in bounds: NSRect) -> NSRect {
        let topInset: CGFloat = 16
        let bottomInset: CGFloat = 6
        return NSRect(
            x: 0,
            y: topInset,
            width: bounds.width,
            height: max(1, bounds.height - topInset - bottomInset)
        )
    }

    static func scaleMaxWeight(for bars: [MenuRowBarChart.Bar]) -> CGFloat {
        max(bars.map { Self.clampedWeight($0.weight) }.max() ?? 0, 0.01)
    }

    static func tickValues(for bars: [MenuRowBarChart.Bar]) -> [CGFloat] {
        let scaleMax = Self.scaleMaxWeight(for: bars)
        let step = Self.tickStep(for: scaleMax)
        var values: [CGFloat] = []
        var tick: CGFloat = 0
        while tick <= scaleMax + 0.000001 {
            values.append(tick)
            tick += step
        }
        return values
    }

    static func tickStep(for maxWeight: CGFloat) -> CGFloat {
        switch maxWeight {
        case ...0.05:
            return 0.01
        case ...0.15:
            return 0.05
        case ...0.30:
            return 0.10
        case ...0.60:
            return 0.25
        default:
            return 0.25
        }
    }

    private static func barHalfWidth(slotWidth: CGFloat) -> CGFloat {
        slotWidth * 0.25 + 2
    }

    private var totalSlotCount: Int {
        Self.totalSlotCount(for: self.bars.count)
    }

    private var leadingSlotCount: Int {
        Self.leadingSlotCount(for: self.bars.count)
    }
}

private final class PortfolioAllocationXAxisView: NSView {
    static let axisHeight: CGFloat = 16

    private let bars: [MenuRowBarChart.Bar]

    override var isFlipped: Bool {
        true
    }

    init(bars: [MenuRowBarChart.Bar]) {
        self.bars = bars
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !self.bars.isEmpty, self.bounds.width > 1, self.bounds.height > 1 else { return }

        let totalSlotCount = PortfolioAllocationVerticalBarChartView.totalSlotCount(for: self.bars.count)
        let leadingSlotCount = PortfolioAllocationVerticalBarChartView.leadingSlotCount(for: self.bars.count)
        let slotWidth = self.bounds.width / CGFloat(totalSlotCount)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        for index in self.bars.indices {
            let centerX = self.bounds.minX + slotWidth * (CGFloat(leadingSlotCount + index) + 0.5)
            let labelWidth = max(slotWidth, 10)
            let labelRect = NSRect(
                x: centerX - labelWidth / 2,
                y: 0,
                width: labelWidth,
                height: Self.axisHeight
            )
            let label = self.bars[index].axisLabel ?? String(self.bars[index].label.prefix(1)).uppercased()
            NSString(string: label).draw(in: labelRect, withAttributes: attrs)
        }
    }
}

private final class PortfolioAllocationYAxisView: NSView {
    static let axisWidth: CGFloat = 38
    static let axisGap: CGFloat = 6

    private let bars: [MenuRowBarChart.Bar]

    override var isFlipped: Bool {
        true
    }

    init(bars: [MenuRowBarChart.Bar]) {
        self.bars = bars
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !self.bars.isEmpty, self.bounds.width > 1, self.bounds.height > 1 else { return }

        let plotRect = PortfolioAllocationVerticalBarChartView.plotRect(in: self.bounds)
        let scaleMax = PortfolioAllocationVerticalBarChartView.scaleMaxWeight(for: self.bars)
        let axisX = self.bounds.maxX - 5

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        for tick in PortfolioAllocationVerticalBarChartView.tickValues(for: self.bars) {
            let y = plotRect.maxY - plotRect.height * tick / scaleMax
            let tickPath = NSBezierPath()
            tickPath.move(to: NSPoint(x: axisX - 5, y: y))
            tickPath.line(to: NSPoint(x: axisX, y: y))
            tickPath.lineWidth = 1
            tickPath.stroke()

            let label = Self.percentLabel(tick)
            let labelRect = NSRect(
                x: 0,
                y: y - 6,
                width: axisX - 8,
                height: 12
            )
            NSString(string: label).draw(in: labelRect, withAttributes: attrs)
        }
    }

    private static func percentLabel(_ weight: CGFloat) -> String {
        let percent = weight * 100
        if abs(percent.rounded() - percent) < 0.001 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", Double(percent))
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
