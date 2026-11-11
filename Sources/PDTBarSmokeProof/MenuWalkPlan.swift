/// A menu row or section the real-menu walk must find, by its `pdtbar.*` accessibility identifier.
public struct MenuSelector: Equatable, Sendable {
    public var label: String
    public var identifier: String

    public init(_ label: String, _ identifier: String) {
        self.label = label
        self.identifier = identifier
    }
}

/// A top-level row whose submenu the walk opens and captures as `<name>.png`.
public struct MenuWalkSubmenu: Equatable, Sendable {
    public var name: String
    public var opener: MenuSelector
    public var expectedChildren: [MenuSelector]
}

public struct MenuWalkPlan: Equatable, Sendable {
    /// The fixture whose rendered menu carries every selector below.
    public var fixture: String
    public var topLevel: [MenuSelector]
    public var submenus: [MenuWalkSubmenu]

    /// Issue #147's cohesive-UI walk, keyed to today's identifiers. The portfolio overview is the
    /// Allocation chart row, its submenu is "Full allocation list", and the Freshness section is titled "Data".
    /// Data health is not walked: the fixture's only cause is stale prices, which the Prices row already shows.
    /// Holding id 9001 belongs to the pinned fixture.
    public static let cohesiveUI = MenuWalkPlan(
        fixture: "concentration-pressure.json",
        topLevel: [
            MenuSelector("Summary", "pdtbar.row.summary.performance"),
            MenuSelector("Pulse", "pdtbar.section.pulse"),
            MenuSelector("Allocation", "pdtbar.section.allocation"),
            MenuSelector("Overview", "pdtbar.row.allocation.portfolio"),
            MenuSelector("Allocation overview", "pdtbar.row.allocation.portfolio.details"),
            MenuSelector("Income", "pdtbar.section.income"),
            MenuSelector("Big movers", "pdtbar.section.bigMovers"),
            MenuSelector("Freshness", "pdtbar.section.freshness"),
            MenuSelector("Prices", "pdtbar.row.freshness.summary"),
            MenuSelector("Actions", "pdtbar.section.actions"),
        ],
        submenus: [
            MenuWalkSubmenu(
                name: "allocation-overview",
                opener: MenuSelector("Allocation overview", "pdtbar.row.allocation.portfolio.details"),
                expectedChildren: [
                    MenuSelector("Top holding", "pdtbar.row.allocation.9001"),
                    MenuSelector("Sectors", "pdtbar.row.allocation.portfolio.sectors"),
                    MenuSelector("Asset types", "pdtbar.row.allocation.portfolio.assetTypes"),
                ]
            ),
        ]
    )

    public static let named: [String: MenuWalkPlan] = ["cohesive-ui": cohesiveUI]
}

extension Array where Element == MenuSelector {
    public func missing(from observed: Set<String>) -> [MenuSelector] {
        filter { !observed.contains($0.identifier) }
    }
}
