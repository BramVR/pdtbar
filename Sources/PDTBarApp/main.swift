import AppKit
import Combine
import Darwin
import Foundation
import PDTBarAppSupport
import PDTBarCore
import SwiftUI

private struct PortfolioFetchOutcome: @unchecked Sendable {
    var pulse: PulseLifecycleResult?
    var failure: PDTFetchFailure = .unavailable
    var errorDescription: String?
    var detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome?
    var syncFailure: PDTSyncFailure?
    /// After a committed refresh: not `.connected` when an optional phase lost access.
    var connectionAfterSync: PDTConnectionStatus = .connected
}

private struct CachedPulseLoadOutcome: @unchecked Sendable {
    var pulse: PulseLifecycleResult?
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: PDTBarLaunchOptions
    private let environment: [String: String]
    private lazy var launchRuntime = PDTLaunchRuntime { [unowned self] in
        try? PulseReadStore(directory: self.currentSnapshotDirectory()).load()
    }
    /// One connection per store for the whole process (ADR-0002 "one connection per store").
    private var pdtConnection: PDTAppConnection?
    private var statusItem: NSStatusItem?
    private var activeRefreshCancellation: PDTCancellation?
    private var activeRefreshCompletion: DispatchGroup?
    private var signInCancellation: PDTCancellation?
    private var portfolioFetchStartedAt: Date?
    private var portfolioFetchProgressTimer: Timer?
    private var activeSnapshotDirectory: URL?
    private let menuActionDispatcher = MenuActionDispatcher()
    private let statusMenuHost = StatusMenuHost()
    private let settingsStore: PDTBarSettingsStore
    private var settingsCancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var currentRawDescriptor: MenuDescriptor?
    private let menuItemViewWidth: CGFloat = 400

    init(options: PDTBarLaunchOptions) {
        self.options = options
        let environment = ProcessInfo.processInfo.environment
        self.environment = environment
        self.settingsStore = PDTBarSettingsStore(userDefaults: PDTBarSettingsStore.userDefaults(environment: environment))
        super.init()
        self.settingsCancellable = settingsStore.$showPortfolioValues
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rerenderCurrentMenuForSettings()
                }
            }
    }

    private func launch() throws {
        switch options.mode {
        case .pdtAPI:
            pdtConnection = try makeConnection()
            activeSnapshotDirectory = firstFetchStateDirectory()
            handleLaunchUpdate(launchRuntime.launch())
        case let .fixture(fixture):
            let dataSource = PDTFixtureDataSource(fixture: fixture)
            let snapshotDirectory = try fixtureSnapshotDirectory()
            activeSnapshotDirectory = snapshotDirectory
            let result = try PressureRunner.run(
                dataSource: dataSource,
                snapshotStore: SnapshotStore(directory: snapshotDirectory),
                pulseReadStore: PulseReadStore(directory: snapshotDirectory)
            )
            if let descriptor = launchRuntime.replaceCurrentPulse(result) {
                installMenuBarItem(descriptor)
            }
        }
    }

    private func makeConnection() throws -> PDTAppConnection {
        if let script = options.scriptedConnection {
            return try ScriptedPDTConnection.load(script)
                .appConnection(lockDirectory: appSupportDirectory().appending(path: "pdtbar"))
        }
        return PDTAppConnection.production(appSupportDirectory: appSupportDirectory(), credentialFile: options.credentialFile) { url in
            guard NSWorkspace.shared.open(url) else {
                throw PDTSignInError.browserUnavailable
            }
        }
    }

    private func startCachedPulseLoad() {
        let directory = currentSnapshotDirectory()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = CachedPulseLoadOutcome(
                pulse: try? PressureRunner.cachedPulse(
                    snapshotStore: SnapshotStore(directory: directory),
                    pulseReadStore: PulseReadStore(directory: directory)
                )
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, let update = self.launchRuntime.completeCachedPulseLoad(outcome.pulse) else {
                    return
                }
                self.handleLaunchUpdate(update)
            }
        }
    }

    private func runConnectionOperation(_ operation: @escaping @Sendable (PDTAppConnection) -> PDTConnectionOutcome) {
        guard let connection = pdtConnection else {
            return
        }
        let attempt = launchRuntime.connectionAttempt
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = operation(connection)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.signInCancellation = nil
                self.handleLaunchUpdate(self.launchRuntime.completeConnection(outcome, for: attempt))
            }
        }
    }

    private func startSignIn() {
        let cancellation = PDTCancellation()
        signInCancellation = cancellation
        runConnectionOperation { $0.signIn(cancellation: cancellation) }
    }

    private func startFirstPortfolioFetch() {
        guard let connection = pdtConnection else {
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
            // Cleared first, so a fetch that fails without a PDT request cannot show an older record.
            snapshotStore.setLastSyncFailure(nil)
            do {
                // The coalesced fetch persists the snapshot before it returns a pulse.
                let pulse = try PDTCoalescedFirstPortfolioFetch(
                    dataSource: PDTAPIDataSource(
                        client: connection.apiClient(),
                        options: .firstFetch,
                        onSyncFailure: { snapshotStore.setLastSyncFailure($0) }
                    ),
                    snapshotStore: snapshotStore,
                    asOf: connection.asOf,
                    pulseReadStore: pulseReadStore
                ).fetch()
                outcome = PortfolioFetchOutcome(pulse: pulse)
            } catch {
                outcome = PortfolioFetchOutcome(
                    failure: connection.failure(for: error),
                    errorDescription: PDTAppConnection.logLabel(for: error),
                    syncFailure: snapshotStore.lastSyncFailure()
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishFirstPortfolioFetch(outcome)
            }
        }
    }

    private func finishFirstPortfolioFetch(_ outcome: PortfolioFetchOutcome) {
        stopPortfolioFetchProgressTimer()
        if let pulse = outcome.pulse {
            handleLaunchUpdate(launchRuntime.completeFirstFetch(.succeeded(pulse)))
            if let update = launchRuntime.beginBackgroundDetailRefresh() {
                handleLaunchUpdate(update)
            }
            return
        }
        FileHandle.standardError.write(Data("pdtbar: first fetch failed: \(outcome.errorDescription ?? "unknown error")\n".utf8))
        handleLaunchUpdate(launchRuntime.completeFirstFetch(.failed(outcome.failure, failure: outcome.syncFailure)))
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

    private func startBackgroundPortfolioRefresh() {
        guard let connection = pdtConnection else {
            return
        }
        let stateDirectory = firstFetchStateDirectory()
        activeSnapshotDirectory = stateDirectory
        let snapshotStore = SnapshotStore(directory: stateDirectory)
        let refresh = PDTAPIBackgroundDetailRefresh(
            client: connection.apiClient(),
            snapshotStore: snapshotStore,
            pulseReadStore: PulseReadStore(directory: stateDirectory),
            asOf: connection.asOf
        )
        let cancellation = PDTCancellation()
        let completion = DispatchGroup()
        completion.enter()
        activeRefreshCancellation = cancellation
        activeRefreshCompletion = completion
        DispatchQueue.global(qos: .utility).async {
            defer {
                completion.leave()
            }
            let outcome: PortfolioFetchOutcome
            do {
                let result = try refresh.refresh(cancellation: cancellation) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let update = self.launchRuntime.backgroundDetailRefreshProgress(progress) else {
                            return
                        }
                        self.installMenuBarItem(update.descriptor, cancelOpenMenu: false)
                    }
                }
                var connectionAfterSync = PDTConnectionStatus.connected
                if let ending = result.failures.last, case let .connection(status) = connection.failure(for: ending.kind) {
                    connectionAfterSync = status
                }
                outcome = PortfolioFetchOutcome(
                    pulse: result.pulse,
                    detailRefreshOutcome: result.outcome,
                    connectionAfterSync: connectionAfterSync
                )
            } catch {
                outcome = PortfolioFetchOutcome(
                    failure: connection.failure(for: error),
                    errorDescription: PDTAppConnection.logLabel(for: error),
                    syncFailure: snapshotStore.lastSyncFailure()
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishBackgroundPortfolioRefresh(outcome)
            }
        }
    }

    private func finishBackgroundPortfolioRefresh(_ outcome: PortfolioFetchOutcome) {
        activeRefreshCancellation = nil
        activeRefreshCompletion = nil
        if let pulse = outcome.pulse {
            handleLaunchUpdate(launchRuntime.completeBackgroundDetailRefresh(
                .succeeded(pulse, outcome: outcome.detailRefreshOutcome ?? .completed, connection: outcome.connectionAfterSync)
            ))
            return
        }
        FileHandle.standardError.write(Data("pdtbar: background refresh failed: \(outcome.errorDescription ?? "unknown error")\n".utf8))
        handleLaunchUpdate(launchRuntime.completeBackgroundDetailRefresh(
            .failed(outcome.failure, failure: outcome.syncFailure)
        ))
    }

    @objc private func retryPortfolioFetch(_ sender: NSMenuItem) {
        handleLaunchUpdate(launchRuntime.retryFirstFetch())
    }

    @objc private func signInWithPDT(_ sender: NSMenuItem) {
        handleLaunchUpdate(launchRuntime.signIn())
    }

    @objc private func cancelSignIn(_ sender: NSMenuItem) {
        handleLaunchUpdate(launchRuntime.cancelSignIn())
    }

    @objc private func checkConnectionAgain(_ sender: NSMenuItem) {
        handleLaunchUpdate(launchRuntime.checkAgain())
    }

    @objc private func disconnectFromPDT(_ sender: NSMenuItem) {
        handleLaunchUpdate(launchRuntime.disconnect())
    }

    @objc private func openRevokePage(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? String, let url = URL(string: link) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The pasted-token fallback. The field is secure, and the value goes
    /// straight into the store; it is never logged or shown.
    @objc private func enterPDTToken(_ sender: NSMenuItem) {
        statusMenuHost.dismissWithoutAnimation()
        let alert = NSAlert()
        alert.messageText = "Use a PDT token"
        alert.informativeText = "In PDT, open Integrations > API and create a token with the read scope. Paste it here."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let token = try? PDTAPIToken.personal(pasted: field.stringValue)
        else {
            return
        }
        field.stringValue = ""
        handleLaunchUpdate(launchRuntime.connect(token: token))
    }

    private func handleLaunchUpdate(_ update: PDTOnboardingUpdate?) {
        guard let update else {
            return
        }
        installMenuBarItem(update.descriptor)
        switch update.effect {
        case .none:
            return
        case .loadCachedPulse:
            startCachedPulseLoad()
        case .checkConnection:
            runConnectionOperation { $0.check() }
        case .signIn:
            startSignIn()
        case .connectToken(let token):
            runConnectionOperation { $0.connect(token: token) }
        case .cancelSignIn:
            signInCancellation?.cancel()
        case .disconnect:
            runConnectionOperation { $0.disconnect() }
        case .startFirstFetch:
            startFirstPortfolioFetch()
        case .startBackgroundDetailRefresh:
            startBackgroundPortfolioRefresh()
        }
    }

    private func firstFetchStateDirectory() -> URL {
        appSupportDirectory().appending(path: "pdtbar/state")
    }

    private func currentSnapshotDirectory() -> URL {
        activeSnapshotDirectory ?? firstFetchStateDirectory()
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
        currentRawDescriptor = descriptor
        let surface = MenuBarSurfaceRenderer.render(
            descriptor: descriptor.applying(settings: settingsStore.displaySettings)
        )
        let item: NSStatusItem
        if let statusItem {
            item = statusItem
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem = item
        }
        item.length = NSStatusItem.squareLength
        item.button?.title = surface.status.menuBarTitle
        item.button?.image = makeConcentrationStackStatusImage(from: surface.status.visual)
        item.button?.imagePosition = .imageOnly
        item.button?.identifier = NSUserInterfaceItemIdentifier(surface.status.accessibilityIdentifier)
        item.button?.toolTip = surface.status.toolTip
        item.button?.setAccessibilityLabel(surface.status.accessibilityLabel)
        item.button?.setAccessibilityIdentifier(surface.status.accessibilityIdentifier)
        // Mutate the one live menu in place. Assigning a fresh NSMenu on every
        // update would leave an already-open menu tracking a detached
        // instance that later progress updates and cancelTracking() calls can
        // no longer reach, freezing stale fetch-progress rows on screen.
        let menu = statusMenuHost.apply(
            items: makeMenuItems(from: surface),
            cancelOpenMenu: cancelOpenMenu
        )
        if item.menu !== menu {
            item.menu = menu
        }
    }

    private func makeMenuItems(from surface: MenuBarSurface) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for section in surface.sections {
            if section.showsHeading {
                items.append(makeSectionHeadingItem(
                    title: section.title,
                    accessibilityIdentifier: section.accessibilityIdentifier
                ))
            }
            for row in section.rows {
                items.append(makeMenuItem(from: row))
            }
            items.append(.separator())
        }
        items.append(NSMenuItem(title: "Quit PDTBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return items
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
            if let action = connectionAction(for: row.role) {
                item.target = self
                item.action = action
                item.representedObject = row.actionPayload
            }
            if row.actionTarget?.kind == .copyHoldingIdentifier || row.actionTarget?.kind == .copyDataHealthDiagnostic {
                item.target = menuActionDispatcher
                item.action = #selector(MenuActionDispatcher.copyMenuRowAction(_:))
                item.representedObject = row.actionTarget
            }
            if row.role == .pulseMarkRead,
               let attentionID = row.actionPayload,
               let fingerprint = launchRuntime.currentPulse?.unfilteredModel.rankedAttentionItems
                .first(where: { $0.id == attentionID })?
                .readFingerprint
            {
                item.target = self
                item.action = #selector(markPulseItemRead(_:))
                item.representedObject = fingerprint
            }
            if row.role == .openPDT {
                item.target = self
                item.action = #selector(openPDT(_:))
            }
            if row.role == .settings {
                item.target = self
                item.action = #selector(showSettings(_:))
            }
        } else {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for child in row.children {
                submenu.addItem(makeMenuItem(from: child))
            }
            item.submenu = submenu
        }
        if let portfolioSummary = row.portfolioSummary {
            item.view = makePortfolioSummaryGridView(
                summary: portfolioSummary,
                accessibilityIdentifier: row.accessibilityIdentifier
            )
            item.isEnabled = false
        } else if let barChart = row.barChart {
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
                accessibilityIdentifier: row.accessibilityIdentifier,
                usesSecondaryProgressStyle: row.id == "portfolioFetch.backgroundProgress.priceHistory"
            )
            item.isEnabled = false
        } else {
            item.isEnabled = true
            applyDetailSubtitle(row.detail, to: item, title: row.title)
        }
        return item
    }

    private func makePortfolioSummaryGridView(
        summary: MenuRowPortfolioSummary,
        accessibilityIdentifier: String
    ) -> NSView {
        let layout = PortfolioSummaryGridLayout(
            width: menuItemViewWidth,
            systemFontSize: NSFont.systemFontSize,
            showsPerformance: summary.showsPerformance
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: layout.rowHeight))
        container.autoresizingMask = [.width]
        configureStaticMenuViewAccessibility(
            container,
            accessibilityIdentifier: accessibilityIdentifier,
            label: summary.accessibilityLabel
        )

        let total = makeSummaryMetric(
            label: "Total portfolio value",
            value: summary.totalValue
        )
        let cagr = makeSummaryMetric(label: "CAGR", value: summary.cagr)
        let increase = makeSummaryMetric(label: "Total increase", value: summary.totalIncrease)
        let performance = NSStackView(views: [cagr, increase])
        performance.orientation = .horizontal
        performance.alignment = .top
        performance.distribution = .fill
        performance.spacing = PortfolioSummaryGridLayout.columnGap

        performance.isHidden = !summary.showsPerformance
        let grid = NSStackView(views: [total, performance])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.distribution = .fill
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: PortfolioSummaryGridLayout.horizontalPadding),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -PortfolioSummaryGridLayout.horizontalPadding),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),
            total.widthAnchor.constraint(equalTo: grid.widthAnchor),
            performance.widthAnchor.constraint(equalTo: grid.widthAnchor),
            cagr.widthAnchor.constraint(equalToConstant: layout.columnWidth),
            increase.widthAnchor.constraint(equalToConstant: layout.columnWidth),
        ])
        return container
    }

    private func makeSummaryMetric(
        label: String,
        value: String
    ) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        labelField.textColor = NSColor.secondaryLabelColor
        labelField.lineBreakMode = .byWordWrapping
        labelField.maximumNumberOfLines = 2

        let valueField = NSTextField(labelWithString: value)
        valueField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        valueField.textColor = NSColor.labelColor
        valueField.lineBreakMode = .byWordWrapping
        valueField.maximumNumberOfLines = 2

        let stack = NSStackView(views: [labelField, valueField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    @objc private func openPDT(_ sender: NSMenuItem) {
        guard let url = URL(string: "https://app.portfoliodividendtracker.com/login?locale=en") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        // Activating a key window while the view-backed menu is still closing
        // can strand its allocation-chart host window on screen.
        statusMenuHost.dismissWithoutAnimation()
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 92),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = "Settings"
            created.isReleasedWhenClosed = false
            created.contentView = NSHostingView(rootView: PDTBarSettingsView(settingsStore: settingsStore))
            settingsWindow = created
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func rerenderCurrentMenuForSettings() {
        guard let currentRawDescriptor else {
            return
        }
        installMenuBarItem(currentRawDescriptor, cancelOpenMenu: false)
    }

    private func makePortfolioAllocationChartRowView(
        title: String,
        detail: String?,
        barChart: MenuRowBarChart,
        accessibilityIdentifier: String
    ) -> NSView {
        let hasDetail = detail?.isEmpty == false
        let rowHeight: CGFloat = hasDetail ? 138 : 124
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: rowHeight))
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

        // The section heading above names the chart; the title stays in the accessibility label only.
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

        let chartView = PortfolioAllocationVerticalBarChartView(bars: barChart.bars)
        let chartAxisWidth = PortfolioAllocationYAxisView.axisWidth
        let chartAxisGap = PortfolioAllocationYAxisView.axisGap
        let chartViewportWidth = menuItemViewWidth - 20 - chartAxisWidth - chartAxisGap - 28
        let chartContentWidth = PortfolioAllocationVerticalBarChartView.contentWidth(
            viewportWidth: chartViewportWidth,
            barCount: barChart.bars.count
        )

        let usesHorizontalScroll = barChart.bars.count > PortfolioAllocationChartLayout.visibleSlotCount
        let chartHostView: NSView
        let selectedTextTrailingAnchor: NSLayoutXAxisAnchor
        var chartHostConstraints: [NSLayoutConstraint] = []
        if usesHorizontalScroll {
            let chartScrollView = NSScrollView()
            chartScrollView.borderType = .noBorder
            chartScrollView.drawsBackground = false
            chartScrollView.hasVerticalScroller = false
            chartScrollView.hasHorizontalScroller = true
            chartScrollView.autohidesScrollers = false
            chartScrollView.horizontalScrollElasticity = .allowed
            chartScrollView.scrollerStyle = .overlay
            chartScrollView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(chartScrollView)

            chartView.frame = NSRect(
                x: 0,
                y: 0,
                width: chartContentWidth,
                height: PortfolioAllocationChartLayout.chartHeight
            )
            chartView.autoresizingMask = [.height]
            chartScrollView.documentView = chartView

            chartHostView = chartScrollView
            selectedTextTrailingAnchor = chartScrollView.trailingAnchor
        } else {
            chartView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(chartView)

            chartHostView = chartView
            selectedTextTrailingAnchor = chartView.trailingAnchor
            chartHostConstraints.append(
                chartView.widthAnchor.constraint(greaterThanOrEqualToConstant: chartContentWidth)
            )
        }

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
        // Middle truncation: a long holding name gives way before the weight and value at the end.
        selectedTitleField.lineBreakMode = .byTruncatingMiddle
        selectedTitleField.maximumNumberOfLines = 1
        selectedTitleField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectedTitleField)

        let applySelection: (MenuRowBarChart.Bar?) -> Void = { bar in
            guard let bar else {
                selectedTitleField.stringValue = "Hover a bar for details"
                selectedAccent.isHidden = true
                return
            }
            // bar.detail already names the holding and its weight; a fail-closed placeholder does not.
            let detailNamesHolding = !bar.detail.isEmpty && bar.detail != PortfolioValueDisplaySettings.hiddenPlaceholder
            selectedTitleField.stringValue = detailNamesHolding ? bar.detail : "\(bar.label): \(bar.percentageLabel)"
            selectedAccent.isHidden = false
        }
        chartView.onSelectionChanged = applySelection
        applySelection(chartView.selectedBar)

        var constraints = [
            chartAxisView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            chartAxisView.widthAnchor.constraint(equalToConstant: chartAxisWidth),
            chartAxisView.heightAnchor.constraint(equalToConstant: PortfolioAllocationChartLayout.chartHeight),

            chartHostView.leadingAnchor.constraint(equalTo: chartAxisView.trailingAnchor, constant: chartAxisGap),
            chartHostView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            chartHostView.heightAnchor.constraint(equalToConstant: PortfolioAllocationChartLayout.chartHeight),

            selectedAccent.leadingAnchor.constraint(equalTo: chartAxisView.leadingAnchor),
            selectedAccent.topAnchor.constraint(equalTo: chartHostView.bottomAnchor, constant: 8),
            selectedAccent.widthAnchor.constraint(equalToConstant: 2),
            selectedAccent.heightAnchor.constraint(equalToConstant: 16),

            selectedTitleField.leadingAnchor.constraint(equalTo: selectedAccent.trailingAnchor, constant: 8),
            selectedTitleField.trailingAnchor.constraint(equalTo: selectedTextTrailingAnchor),
            selectedTitleField.topAnchor.constraint(equalTo: chartHostView.bottomAnchor, constant: 7),
            selectedTitleField.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ]

        let chartTopAnchor = detailField?.bottomAnchor ?? container.topAnchor
        let chartTopGap: CGFloat = detailField == nil ? 4 : 9
        constraints += [
            chartAxisView.topAnchor.constraint(equalTo: chartTopAnchor, constant: chartTopGap),
            chartHostView.topAnchor.constraint(equalTo: chartTopAnchor, constant: chartTopGap),
        ]
        constraints += chartHostConstraints
        if let detailField {
            constraints += [
                detailField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                detailField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
                detailField.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            ]
        }

        NSLayoutConstraint.activate(constraints)

        return container
    }

    private func makeStaticMenuRowView(
        title: String,
        detail: String?,
        accessibilityIdentifier: String,
        usesSecondaryProgressStyle: Bool = false
    ) -> NSView {
        let hasDetail = detail?.isEmpty == false
        let rowHeight: CGFloat = hasDetail ? 42 : (usesSecondaryProgressStyle ? 24 : 30)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuItemViewWidth, height: rowHeight))
        container.autoresizingMask = [.width]
        configureStaticMenuViewAccessibility(
            container,
            accessibilityIdentifier: accessibilityIdentifier,
            label: detail.map { "\(title) - \($0)" } ?? title
        )

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(
            ofSize: usesSecondaryProgressStyle ? NSFont.smallSystemFontSize : NSFont.systemFontSize
        )
        titleField.textColor = usesSecondaryProgressStyle ? NSColor.secondaryLabelColor : NSColor.labelColor
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
            try PulseReadStore(directory: currentSnapshotDirectory()).markRead(fingerprint)
            if let update = launchRuntime.pulseReadStateDidChange() {
                handleLaunchUpdate(update)
            }
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

private extension AppDelegate {
    func connectionAction(for role: MenuRowRole) -> Selector? {
        switch role {
        case .connectionSignIn: #selector(signInWithPDT(_:))
        case .connectionToken: #selector(enterPDTToken(_:))
        case .connectionCancel: #selector(cancelSignIn(_:))
        case .connectionCheck: #selector(checkConnectionAgain(_:))
        case .connectionDisconnect: #selector(disconnectFromPDT(_:))
        case .connectionRevoke: #selector(openRevokePage(_:))
        default: nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try launch()
        } catch {
            FileHandle.standardError.write(Data("pdtbar: \(error)\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        signInCancellation?.cancel()
        activeRefreshCancellation?.cancel()
        _ = activeRefreshCompletion?.wait(timeout: .now() + 4.0)
    }
}

private struct PDTBarSettingsView: View {
    @ObservedObject var settingsStore: PDTBarSettingsStore

    var body: some View {
        Toggle("Show portfolio values", isOn: $settingsStore.showPortfolioValues)
            .padding(20)
            .frame(width: 300, alignment: .leading)
    }
}

private final class PortfolioAllocationVerticalBarChartView: NSView {
    static let barColor = NSColor(calibratedRed: 0.28, green: 0.68, blue: 0.73, alpha: 0.92)

    private let bars: [MenuRowBarChart.Bar]
    private let selectionView = NSBox()
    private var barViews: [NSBox] = []
    private var trackingArea: NSTrackingArea?
    private var selectedIndex: Int? {
        didSet {
            guard selectedIndex != oldValue else { return }
            self.layoutBarViews()
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
        configureBarSubviews()
    }

    static func contentWidth(viewportWidth: CGFloat, barCount: Int) -> CGFloat {
        PortfolioAllocationChartLayout.contentWidth(viewportWidth: viewportWidth, barCount: barCount)
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

    override func layout() {
        super.layout()
        layoutBarViews()
    }

    private func configureBarSubviews() {
        selectionView.boxType = .custom
        selectionView.borderWidth = 0
        selectionView.cornerRadius = 0
        selectionView.fillColor = NSColor.labelColor.withAlphaComponent(0.10)
        addSubview(selectionView)

        barViews = bars.map { _ in
            let barView = NSBox()
            barView.boxType = .custom
            barView.borderWidth = 0
            barView.fillColor = Self.barColor
            addSubview(barView)
            return barView
        }
    }

    private func layoutBarViews() {
        guard !self.bars.isEmpty, self.bounds.width > 1, self.bounds.height > 1 else {
            selectionView.isHidden = true
            barViews.forEach { $0.isHidden = true }
            return
        }
        let layout = PortfolioAllocationChartLayout(
            bounds: self.bounds,
            weights: self.bars.map(\.weight)
        )

        if let selectedIndex {
            let barRect = layout.barRect(at: selectedIndex)
            selectionView.frame = NSRect(
                x: barRect.minX,
                y: layout.plotRect.minY,
                width: barRect.width,
                height: layout.plotRect.height
            )
            selectionView.isHidden = false
        } else {
            selectionView.isHidden = true
        }

        for index in self.bars.indices {
            let barRect = layout.barRect(at: index)
            let barView = barViews[index]
            barView.frame = barRect
            barView.cornerRadius = PortfolioAllocationChartLayout.barCornerRadius
            barView.isHidden = barRect.height <= 0
        }
    }

    private func updateSelection(with event: NSEvent) {
        let location = self.convert(event.locationInWindow, from: nil)
        let layout = PortfolioAllocationChartLayout(
            bounds: self.bounds,
            weights: self.bars.map(\.weight)
        )
        guard let index = layout.index(at: location) else { return }
        self.selectedIndex = index
    }

    private static func clampedWeight(_ weight: Double) -> CGFloat {
        PortfolioAllocationChartLayout.clampedWeight(weight)
    }

    static func totalSlotCount(for barCount: Int) -> Int {
        PortfolioAllocationChartLayout.totalSlotCount(for: barCount)
    }

    static func leadingSlotCount(for barCount: Int) -> Int {
        PortfolioAllocationChartLayout.leadingSlotCount(for: barCount)
    }

    static func plotRect(in bounds: NSRect) -> NSRect {
        PortfolioAllocationChartLayout.plotRect(in: bounds)
    }

    static func scaleMaxWeight(for bars: [MenuRowBarChart.Bar]) -> CGFloat {
        PortfolioAllocationChartLayout.scaleMaxWeight(for: bars.map(\.weight))
    }

    static func tickValues(for bars: [MenuRowBarChart.Bar]) -> [CGFloat] {
        PortfolioAllocationChartLayout.tickValues(for: bars.map(\.weight))
    }

    static func tickStep(for maxWeight: CGFloat) -> CGFloat {
        PortfolioAllocationChartLayout.tickStep(for: maxWeight)
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
            let y = plotRect.maxY - PortfolioAllocationChartLayout.barHeight(
                for: tick,
                plotHeight: plotRect.height,
                scaleMaxWeight: scaleMax
            )
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
        Data("usage: pdtbar [--app-support-dir <path> [--scripted-pdt <file> | --pdt-credential-file <file>]] | --fixture <path> [--snapshot-dir <path>]\n".utf8)
    )
    Foundation.exit(64)
}
