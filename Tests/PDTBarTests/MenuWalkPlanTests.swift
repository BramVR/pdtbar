import Foundation
import Testing
import PDTBarCore
import PDTBarSmokeProof

@Suite("Menu walk plan")
struct MenuWalkPlanTests {
    @Test("Cohesive-UI plan matches the menu its fixture renders")
    func cohesiveUIPlanMatchesRenderedMenu() throws {
        let plan = MenuWalkPlan.cohesiveUI
        let surface = try renderedSurface(fixture: plan.fixture)
        let topRows = surface.sections.flatMap(\.rows)
        let topLevel = Set(surface.sections.filter(\.showsHeading).map(\.accessibilityIdentifier) + topRows.map(\.accessibilityIdentifier))

        #expect(plan.topLevel.missing(from: topLevel).map(\.identifier) == [])
        for submenu in plan.submenus {
            #expect(topLevel.contains(submenu.opener.identifier), "opener \(submenu.opener.identifier)")
            let opener = topRows.first { $0.accessibilityIdentifier == submenu.opener.identifier }
            let children = Set(opener?.children.map(\.accessibilityIdentifier) ?? [])
            #expect(submenu.expectedChildren.missing(from: children).map(\.identifier) == [], "\(submenu.name)")
        }
    }

    @Test("Missing selectors keep plan order and ignore extra identifiers")
    func missingSelectorsKeepPlanOrder() {
        let selectors = [
            MenuSelector("Pulse", "pdtbar.section.pulse"),
            MenuSelector("Income", "pdtbar.section.income"),
            MenuSelector("Data health", "pdtbar.row.dataHealth"),
        ]
        let observed: Set = ["pdtbar.section.income", "pdtbar.row.extra"]

        #expect(selectors.missing(from: observed).map(\.label) == ["Pulse", "Data health"])
        #expect(selectors.missing(from: Set(selectors.map(\.identifier))).isEmpty)
    }

    @Test("Plan names are unique and safe as evidence file names")
    func planNamesAreSafeFileNames() {
        let names = MenuWalkPlan.cohesiveUI.submenus.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil })
        #expect(MenuWalkPlan.named["cohesive-ui"] == .cohesiveUI)
    }
}

/// The fixture's menu as the launched app draws it: fetched this run, over a connected PDT.
private func renderedSurface(fixture: String) throws -> MenuBarSurface {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let run = try PressureRunner.run(
        dataSource: PDTFixtureDataSource(fixture: root.appending(path: "docs/pdt/fixtures/\(fixture)")),
        snapshotStore: try SnapshotStore.temporaryTestStore(prefix: "menu-walk-plan")
    )
    return MenuBarSurfaceRenderer.render(descriptor: run.descriptor(in: DataHealthRuntime(access: .connected)))
}
