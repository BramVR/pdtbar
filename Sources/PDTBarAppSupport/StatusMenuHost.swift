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

    public init() {}

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

    private func ensureMenu() -> NSMenu {
        if let menu {
            return menu
        }
        let created = NSMenu()
        created.autoenablesItems = false
        menu = created
        return created
    }
}
