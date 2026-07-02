import AppKit
import Foundation
import Testing
import PDTBarAppSupport

@Suite("Status menu host")
struct StatusMenuHostTests {
    @MainActor
    @Test("Repeated applies reuse one live menu instance and replace its items")
    func repeatedAppliesReuseOneLiveMenuInstanceAndReplaceItsItems() {
        let host = StatusMenuHost()

        let first = host.apply(
            items: [NSMenuItem(title: "Fetching… 1s", action: nil, keyEquivalent: "")],
            cancelOpenMenu: true
        )
        let second = host.apply(
            items: [NSMenuItem(title: "Fetching… 2s", action: nil, keyEquivalent: "")],
            cancelOpenMenu: false
        )
        let third = host.apply(
            items: [
                NSMenuItem(title: "Pulse", action: nil, keyEquivalent: ""),
                NSMenuItem(title: "Quit PDTBar", action: nil, keyEquivalent: "q"),
            ],
            cancelOpenMenu: true
        )

        #expect(first === second)
        #expect(second === third)
        #expect(host.menu === third)
        #expect(third.items.map(\.title) == ["Pulse", "Quit PDTBar"])
    }

    @MainActor
    @Test("Menu host keeps descriptor-driven item enabling manual")
    func menuHostKeepsDescriptorDrivenItemEnablingManual() {
        let host = StatusMenuHost()

        let menu = host.apply(items: [], cancelOpenMenu: false)

        #expect(menu.autoenablesItems == false)
        #expect(menu.items.isEmpty)
    }
}
