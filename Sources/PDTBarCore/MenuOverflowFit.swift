import Foundation

/// The order PDTBar gives up menu height when the menu would overflow the screen (#296).
///
/// Each step only moves rows under a parent row, so every row stays reachable through a
/// submenu. Steps apply cumulatively in declaration order; a step that finds nothing to
/// fold leaves the surface unchanged. The order gives up the least first: a summary of a move
/// Pulse usually shows, then the income list, then the chart, and attention items last.
public enum MenuOverflowStep: Int, CaseIterable, Sendable {
    /// Big movers loses its heading; its row moves into one `Big movers` submenu row.
    case foldBigMovers
    /// Income keeps its summary row; the event rows move into its submenu.
    case foldIncomeList
    /// The allocation chart moves to the top of the Full allocation list submenu.
    case foldAllocationChart
    /// Attention items that spilled out of Pulse into Allocation move into one submenu row.
    case foldSpilledPressures
    /// Every titled section except Actions keeps its first row and folds the rest.
    case foldSectionTails
    /// Last resort, so Actions and Quit stay on screen: every titled section except Actions
    /// becomes one row named after it, hinting at its first row, with all its rows in the submenu.
    case collapseSections
}

public extension MenuBarSurface {
    /// The first build, along the overflow ladder, whose height fits `budget`.
    ///
    /// The unchanged surface is built and measured first, so a menu that fits renders exactly
    /// as it would without this call. When even the last step overflows, its build is returned.
    func fitted<Built>(
        within budget: Double,
        build: (MenuBarSurface) -> Built,
        height: (Built) -> Double
    ) -> (built: Built, steps: [MenuOverflowStep]) {
        var surface = self
        var built = build(surface)
        var fits = height(built) <= budget
        var applied: [MenuOverflowStep] = []
        for step in MenuOverflowStep.allCases where !fits {
            let next = surface.compacted(by: step)
            guard next != surface else { continue }
            surface = next
            built = build(surface)
            fits = height(built) <= budget
            applied.append(step)
        }
        return (built, applied)
    }

    func compacted(by step: MenuOverflowStep) -> MenuBarSurface {
        var surface = self
        surface.sections = sections.map { section in
            switch step {
            case .foldIncomeList: section.foldingIncomeList()
            case .foldAllocationChart: section.foldingAllocationChart()
            case .foldBigMovers: section.foldingBigMovers()
            case .foldSpilledPressures: section.foldingSpilledPressures()
            case .foldSectionTails: section.foldingTail()
            case .collapseSections: section.collapsing()
            }
        }
        return surface
    }
}

private extension MenuBarSectionSurface {
    func foldingIncomeList() -> MenuBarSectionSurface {
        guard id == "income",
              let summaryIndex = rows.firstIndex(where: { $0.role == .incomeSummary }),
              rows.count > 1
        else { return self }
        var summary = rows[summaryIndex]
        summary.children += rows.enumerated().filter { $0.offset != summaryIndex }.map(\.element)
        var section = self
        section.rows = [summary]
        return section
    }

    func foldingAllocationChart() -> MenuBarSectionSurface {
        guard id == "allocation",
              let chartIndex = rows.firstIndex(where: { $0.barChart != nil }),
              let detailsIndex = rows.firstIndex(where: { $0.role == .portfolioOverviewDetails })
        else { return self }
        var section = self
        section.rows[detailsIndex].children.insert(rows[chartIndex], at: 0)
        section.rows.remove(at: chartIndex)
        return section
    }

    func foldingBigMovers() -> MenuBarSectionSurface {
        guard id == "bigMovers", !title.isEmpty, !rows.isEmpty else { return self }
        var section = self
        section.title = ""
        section.rows = [
            MenuBarSectionSurface.foldRow(
                id: "bigMovers.folded",
                title: title,
                detail: rows.first?.title,
                children: rows
            ),
        ]
        return section
    }

    func foldingSpilledPressures() -> MenuBarSectionSurface {
        let spilled = rows.filter { $0.role == .allocationDrillDown }
        guard id == "allocation", spilled.count > 1 else { return self }
        var section = self
        section.rows = rows.filter { $0.role != .allocationDrillDown } + [
            MenuBarSectionSurface.foldRow(
                id: "allocation.morePressures",
                title: "\(spilled.count) more attention items",
                detail: nil,
                children: spilled
            ),
        ]
        return section
    }

    func foldingTail() -> MenuBarSectionSurface {
        // Two rows fold into one "1 more" row of the same height, so only longer tails save space.
        guard id != "actions", !title.isEmpty, rows.count > 2 else { return self }
        var section = self
        section.rows = [rows[0]] + [
            MenuBarSectionSurface.foldRow(
                id: "\(id).more",
                title: "\(rows.count - 1) more",
                detail: nil,
                children: Array(rows.dropFirst())
            ),
        ]
        return section
    }

    func collapsing() -> MenuBarSectionSurface {
        guard id != "actions", !title.isEmpty, !rows.isEmpty else { return self }
        var section = self
        section.title = ""
        section.rows = [
            MenuBarSectionSurface.foldRow(id: "\(id).collapsed", title: title, detail: rows[0].title, children: rows),
        ]
        return section
    }

    static func foldRow(id: String, title: String, detail: String?, children: [MenuBarRowSurface]) -> MenuBarRowSurface {
        MenuBarRowSurface(
            id: id,
            role: .row,
            title: title,
            detail: detail,
            accessibilityIdentifier: "pdtbar.row.\(id)",
            children: children
        )
    }
}
