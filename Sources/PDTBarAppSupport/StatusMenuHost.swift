import AppKit
import Foundation

/// Owns the single live `NSMenu` instance shown under the status item.
///
/// Refreshes must mutate this one menu's items in place instead of installing
/// a replacement `NSMenu`. Swapping `NSStatusItem.menu` while the user has the
/// menu open leaves the visible menu tracking a detached instance that no
/// later update or `cancelTracking()` call can reach, so the open menu keeps
/// showing stale rows (such as an ever-growing fetch progress counter) until
/// the user dismisses it manually. `NSMenu` supports item mutation while the
/// menu is open, so in-place updates keep progress rows live and keep
/// `cancelTracking()` pointed at the menu that is actually tracking.
@MainActor
public final class StatusMenuHost {
    public private(set) var menu: NSMenu?
    /// Off-screen twin of the live menu for measuring candidate items (#296). It must be
    /// configured like the live menu, or measuring could validate items the live menu never would.
    let measuringMenu = StatusMenuHost.makeMenu()

    public init() {}

    init(menu: NSMenu) {
        self.menu = menu
    }

    /// Ends menu tracking before presenting a separate key window.
    public func dismissWithoutAnimation() {
        menu?.cancelTrackingWithoutAnimation()
    }

    /// Replaces the live menu's items, creating the menu on first use.
    ///
    /// - Parameter cancelOpenMenu: dismisses the menu when it is currently
    ///   open, preserving the product decision that freshly landed data
    ///   closes the stale menu instead of updating underneath the user.
    @discardableResult
    public func apply(items: [NSMenuItem], cancelOpenMenu: Bool) -> NSMenu {
        let menu = ensureMenu()
        if cancelOpenMenu {
            menu.cancelTracking()
        }
        menu.items = items
        return menu
    }

    /// Height `items` would take in the live menu. The items come back detached, ready to apply.
    public func measuredHeight(of items: [NSMenuItem]) -> Double {
        measuringMenu.items = items
        defer { measuringMenu.removeAllItems() }
        return measuringMenu.size.height
    }

    private func ensureMenu() -> NSMenu {
        if let menu {
            return menu
        }
        let created = StatusMenuHost.makeMenu()
        menu = created
        return created
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }
}
