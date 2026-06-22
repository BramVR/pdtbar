import AppKit
import PulseCore

private enum FixtureName: String {
    case quiet
    case pressure
}

private struct PulseArguments {
    var fixture: FixtureName = .quiet
    var renderOnce = false
}

private enum PulseArgumentError: Error, CustomStringConvertible {
    case unknownFixture(String)

    var description: String {
        switch self {
        case .unknownFixture(let fixture):
            return "Unknown fixture '\(fixture)'. Use 'quiet' or 'pressure'."
        }
    }
}

private func parseArguments(_ arguments: [String]) throws -> PulseArguments {
    var parsed = PulseArguments()
    var index = 1

    while index < arguments.count {
        switch arguments[index] {
        case "--fixture" where index + 1 < arguments.count:
            guard let fixture = FixtureName(rawValue: arguments[index + 1]) else {
                throw PulseArgumentError.unknownFixture(arguments[index + 1])
            }
            parsed.fixture = fixture
            index += 2
        case "--render-once":
            parsed.renderOnce = true
            index += 1
        default:
            index += 1
        }
    }

    return parsed
}

private func model(for fixture: FixtureName) -> PulseModel {
    switch fixture {
    case .quiet:
        return .quietFixture
    case .pressure:
        return .pressureFixture
    }
}

private func renderSummary(_ view: PulseView) -> String {
    var lines = [
        "status.title=\(view.status.title)",
        "status.badge=\(view.status.badge ?? "none")",
        "card.title=\(view.card.title)",
        "rows.count=\(view.card.rows.count)"
    ]

    for (index, row) in view.card.rows.enumerated() {
        lines.append("row.\(index).title=\(row.title)")
        lines.append("row.\(index).detail=\(row.detail)")
        lines.append("row.\(index).facet=\(row.facet.rawValue)")
    }

    if let allocationDrillDown = view.allocationDrillDown {
        lines.append("allocation.title=\(allocationDrillDown.title)")
        lines.append("allocation.rows.count=\(allocationDrillDown.rows.count)")

        for (index, row) in allocationDrillDown.rows.enumerated() {
            lines.append("allocation.row.\(index).title=\(row.title)")
            lines.append("allocation.row.\(index).detail=\(row.detail)")
        }
    }

    return lines.joined(separator: "\n")
}

@MainActor
private final class PulseMenuBarController: NSObject {
    private let view: PulseView
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(view: PulseView) {
        self.view = view
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = [view.status.title, view.status.badge].compactMap(\.self).joined(separator: " ")
            button.toolTip = view.card.title
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: view.card.title, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !view.card.rows.isEmpty {
            menu.addItem(.separator())
            for row in view.card.rows {
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = row.detail
                menu.addItem(item)

                let detail = NSMenuItem(title: row.detail, action: nil, keyEquivalent: "")
                detail.isEnabled = false
                detail.indentationLevel = 1
                menu.addItem(detail)
            }
        }

        if let allocationDrillDown = view.allocationDrillDown {
            menu.addItem(.separator())
            let allocationItem = NSMenuItem(title: allocationDrillDown.title, action: nil, keyEquivalent: "")
            let allocationMenu = NSMenu()

            if allocationDrillDown.rows.isEmpty {
                let empty = NSMenuItem(title: "No open holdings", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                allocationMenu.addItem(empty)
            } else {
                for row in allocationDrillDown.rows {
                    let item = NSMenuItem(title: "\(row.title) - \(row.detail)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    allocationMenu.addItem(item)
                }
            }

            menu.setSubmenu(allocationMenu, for: allocationItem)
            menu.addItem(allocationItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Portfolio Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

@MainActor
private final class PulseAppDelegate: NSObject, NSApplicationDelegate {
    private let view: PulseView
    private var controller: PulseMenuBarController?

    init(view: PulseView) {
        self.view = view
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = PulseMenuBarController(view: view)
    }
}

private let arguments: PulseArguments

do {
    arguments = try parseArguments(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}

private let rendered = PulseRenderer.render(model(for: arguments.fixture))

if arguments.renderOnce {
    print(renderSummary(rendered))
} else {
    let application = NSApplication.shared
    let delegate = PulseAppDelegate(view: rendered)
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
}
