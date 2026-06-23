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
        if let snapshotDirectory = options.snapshotDirectory {
            return try PressureRunner.run(
                fixture: options.fixture,
                snapshotDirectory: snapshotDirectory
            ).descriptor
        }
        let snapshot = try PDTFixtureDataSource.snapshot(from: options.fixture)
        return MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
    }

    private func installMenuBarItem(_ descriptor: MenuDescriptor) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = descriptor.statusTitle
        item.button?.identifier = NSUserInterfaceItemIdentifier(descriptor.statusAccessibilityIdentifier)
        item.button?.toolTip = "PDTBar \(descriptor.statusTitle)"
        item.button?.setAccessibilityLabel("PDTBar \(descriptor.statusTitle)")
        item.menu = makeMenu(from: descriptor)
        statusItem = item
    }

    private func makeMenu(from descriptor: MenuDescriptor) -> NSMenu {
        let menu = NSMenu()
        for section in descriptor.sections {
            let heading = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            heading.identifier = NSUserInterfaceItemIdentifier(section.accessibilityIdentifier)
            heading.isEnabled = false
            menu.addItem(heading)
            for row in section.rows {
                let title = row.detail.map { "\(row.title) - \($0)" } ?? row.title
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if !row.accessibilityIdentifier.isEmpty {
                    item.identifier = NSUserInterfaceItemIdentifier(row.accessibilityIdentifier)
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

    if let fixture {
        return AppOptions(fixture: fixture, snapshotDirectory: snapshotDirectory)
    }
    if let fixturePath = ProcessInfo.processInfo.environment["PDTBAR_FIXTURE"] {
        return AppOptions(fixture: URL(fileURLWithPath: fixturePath), snapshotDirectory: snapshotDirectory)
    }
    throw CommandError.usage
}

private enum CommandError: Error {
    case usage
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
