import AppKit
import Foundation
import PDTBarAppSupport
import Testing
import PDTBarCore

@Suite("Holding identifier copy")
struct HoldingIdentifierCopyTests {
    @Test("Holding drill-down exposes copy action only for public quote code and preserves target through surface")
    func descriptorExposesCopyIdentifierActionOnlyForPublicQuoteCode() throws {
        let fixture = try temporaryFixture("""
        {
          "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
          "getPortfolioHoldings": {
            "holdings": [
              {
                "symbolName": "Copyable Public Co",
                "symbolQuoteId": 9701,
                "currentPriceDate": "2026-06-22T23:59:59+00:00",
                "currentPriceLocal": { "value": "50.00", "currency": "EUR" },
                "currentWorth": { "value": "1000.00", "currency": "EUR" },
                "currentWorthLocal": { "value": "1000.00", "currency": "EUR" },
                "portfolioWeight": 0.10,
                "closedAt": null
              },
              {
                "symbolName": "Ambiguous Private Co",
                "symbolQuoteId": 9702,
                "currentPriceDate": "2026-06-22T23:59:59+00:00",
                "currentPriceLocal": { "value": "25.00", "currency": "EUR" },
                "currentWorth": { "value": "500.00", "currency": "EUR" },
                "currentWorthLocal": { "value": "500.00", "currency": "EUR" },
                "portfolioWeight": 0.05,
                "closedAt": null
              }
            ]
          },
          "getSymbolQuotes": [
            { "id": 9701, "code": "PUBC", "symbolId": 5701 },
            { "id": 9702, "symbolId": 5702 }
          ]
        }
        """)
        defer {
            try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent())
        }

        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: fixture))
        )

        let copyableChildren = try #require(
            descriptor.sections.first { $0.id == "allocation" }?
                .rows.first { $0.title == "Copyable Public Co" }?
                .children
        )
        let copyRow = try #require(copyableChildren.first { $0.id == "allocation.9701.copyIdentifier" })
        #expect(copyRow.role == .holdingIdentifierCopy)
        #expect(copyRow.title == "Copy identifier")
        #expect(copyRow.detail == "PUBC")
        #expect(copyRow.actionTarget?.kind == .copyHoldingIdentifier)
        #expect(copyRow.actionTarget?.copyText == "PUBC")

        let ambiguousChildren = try #require(
            descriptor.sections.first { $0.id == "allocation" }?
                .rows.first { $0.title == "Ambiguous Private Co" }?
                .children
        )
        #expect(ambiguousChildren.contains { $0.id.hasSuffix(".copyIdentifier") } == false)

        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let surfaceCopyRow = surface.sections.first { $0.id == "allocation" }?
            .rows.first { $0.id == "allocation.9701" }?
            .children.first { $0.id == "allocation.9701.copyIdentifier" }
        #expect(surfaceCopyRow?.actionTarget?.kind == .copyHoldingIdentifier)
        #expect(surfaceCopyRow?.actionTarget?.copyText == "PUBC")
    }

    @MainActor
    @Test("AppKit dispatcher copies identifier from action target metadata")
    func appKitDispatcherCopiesIdentifierFromActionTarget() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pdtbar.copy.identifier.\(UUID().uuidString)"))
        let dispatcher = MenuActionDispatcher(pasteboard: pasteboard)
        let item = NSMenuItem(title: "Copy identifier - PUBC", action: nil, keyEquivalent: "")
        item.representedObject = MenuRowActionTarget(
            kind: .copyHoldingIdentifier,
            id: "allocation.9701.copyIdentifier",
            copyText: "PUBC"
        )

        dispatcher.copyMenuRowAction(item)

        #expect(pasteboard.string(forType: .string) == "PUBC")
    }
}

private func temporaryFixture(_ contents: String) throws -> URL {
    let directory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-copy-identifier-fixture").directory
    let fixture = directory.appending(path: "fixture.json")
    try Data(contents.utf8).write(to: fixture)
    return fixture
}
