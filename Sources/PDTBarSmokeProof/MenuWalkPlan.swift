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
            MenuWalkSubmenu(
                name: "prices",
                opener: MenuSelector("Prices", "pdtbar.row.freshness.summary"),
                expectedChildren: [
                    MenuSelector("Top holding price", "pdtbar.row.freshness.price.9001"),
                ]
            ),
        ]
    )

    /// Issue #191: a returning launch whose holdings request PDT rejects with `401`. The reconnect
    /// screen keeps the failure record, so Data health still offers Diagnostics with its copy row.
    public static let syncFailureReconnect = MenuWalkPlan(
        fixture: "sync-failure-base-401.json",
        topLevel: [
            MenuSelector("Reconnect", "pdtbar.row.pdtConnection.status"),
            MenuSelector("Sign in", "pdtbar.row.pdtConnection.signIn"),
            MenuSelector("Check again", "pdtbar.row.pdtConnection.check"),
            MenuSelector("Data health", "pdtbar.row.dataHealth"),
        ],
        submenus: [
            MenuWalkSubmenu(
                name: "data-health",
                opener: MenuSelector("Data health", "pdtbar.row.dataHealth"),
                expectedChildren: [
                    MenuSelector("Access", "pdtbar.row.dataHealth.access"),
                    MenuSelector("Detail fill", "pdtbar.row.dataHealth.detailFill"),
                    MenuSelector("Diagnostics", "pdtbar.row.dataHealth.diagnostic"),
                ]
            ),
        ]
    )

    public static let named: [String: MenuWalkPlan] = [
        "cohesive-ui": cohesiveUI,
        "sync-failure-reconnect": syncFailureReconnect,
    ]
}

extension Array where Element == MenuSelector {
    public func missing(from observed: Set<String>) -> [MenuSelector] {
        filter { !observed.contains($0.identifier) }
    }
}
