import AppKit
import Foundation
import PDTBarCore

private struct AppOptions {
    var fixture: URL
    var snapshotDirectory: URL?
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: AppOptions
    private var statusItem: NSStatusItem?

    init(options: AppOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let descriptor = try loadDescriptor()
            installMenuBarItem(descriptor)
        } catch {
            FileHandle.standardError.write(Data("pdtbar: \(error)\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }

    private func loadDescriptor() throws -> MenuDescriptor {
        let dataSource = PDTFixtureDataSource(fixture: options.fixture)
        return try PressureRunner.run(
            dataSource: dataSource,
            snapshotStore: SnapshotStore(directory: options.snapshotDirectory ?? defaultSnapshotDirectory())
        ).descriptor
    }

    private func installMenuBarItem(_ descriptor: MenuDescriptor) {
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = surface.status.menuBarTitle
        item.button?.identifier = NSUserInterfaceItemIdentifier(surface.status.accessibilityIdentifier)
        item.button?.toolTip = surface.status.toolTip
        item.button?.setAccessibilityLabel(surface.status.accessibilityLabel)
        item.button?.setAccessibilityIdentifier(surface.status.accessibilityIdentifier)
        item.menu = makeMenu(from: surface)
        statusItem = item
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
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Quit PDTBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}

private func parseOptions(_ arguments: [String]) throws -> AppOptions {
    var fixture: URL?
    var snapshotDirectory: URL?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--fixture" where index + 1 < arguments.count:
            fixture = URL(fileURLWithPath: arguments[index + 1])
            index += 2
        case "--snapshot-dir" where index + 1 < arguments.count:
            snapshotDirectory = URL(fileURLWithPath: arguments[index + 1])
            index += 2
        default:
            throw CommandError.usage
        }
    }

    let configuredSnapshotDirectory = snapshotDirectory
        ?? ProcessInfo.processInfo.environment["PDTBAR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    if let fixture {
        return AppOptions(fixture: fixture, snapshotDirectory: configuredSnapshotDirectory)
    }
    if let fixturePath = ProcessInfo.processInfo.environment["PDTBAR_FIXTURE"] {
        return AppOptions(fixture: URL(fileURLWithPath: fixturePath), snapshotDirectory: configuredSnapshotDirectory)
    }
    throw CommandError.usage
}

private enum CommandError: Error {
    case usage
}

private func defaultSnapshotDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return base.appending(path: "pdtbar/snapshots")
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
} catch {
    FileHandle.standardError.write(
        Data("usage: pdtbar --fixture <path> [--snapshot-dir <path>]\n".utf8)
    )
    Foundation.exit(64)
}
