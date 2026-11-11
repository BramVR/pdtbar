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
        let topLevel = Set(surface.sections.map(\.accessibilityIdentifier) + topRows.map(\.accessibilityIdentifier))

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

private func renderedSurface(fixture: String) throws -> MenuBarSurface {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let snapshot = try PDTFixtureDataSource.snapshot(from: root.appending(path: "docs/pdt/fixtures/\(fixture)"))
    let descriptor = MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: snapshot))
    return MenuBarSurfaceRenderer.render(descriptor: descriptor)
}
