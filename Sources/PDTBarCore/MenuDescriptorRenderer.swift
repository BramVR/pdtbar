import Foundation

public enum MenuBarSurfaceRenderer {
    public static func render(descriptor: MenuDescriptor) -> MenuBarSurface {
        let statusTitle = descriptor.statusBadge.map { "\(descriptor.statusTitle) [\($0)]" }
            ?? descriptor.statusTitle
        let statusCopy = descriptor.statusVisual.statusCopy.isEmpty ? statusTitle : descriptor.statusVisual.statusCopy
        return MenuBarSurface(
            status: MenuBarStatusSurface(
                title: descriptor.statusTitle,
                badge: descriptor.statusBadge,
                menuBarTitle: "",
                visual: descriptor.statusVisual,
                accessibilityIdentifier: descriptor.statusAccessibilityIdentifier,
                accessibilityLabel: "PDTBar \(statusCopy)",
                toolTip: "PDTBar \(statusCopy)"
            ),
            sections: descriptor.sections.map { section in
                MenuBarSectionSurface(
                    id: section.id,
                    title: section.title,
                    accessibilityIdentifier: section.accessibilityIdentifier,
                    rows: section.rows.map(renderRow)
                )
            }
        )
    }

    private static func renderRow(_ row: MenuRow) -> MenuBarRowSurface {
        MenuBarRowSurface(
            id: row.id,
            role: row.role,
            title: row.title,
            detail: row.detail,
            accessibilityIdentifier: row.accessibilityIdentifier,
            actionTarget: row.actionTarget,
            barChart: row.barChart,
            portfolioSummary: row.portfolioSummary,
            actionPayload: row.actionPayload,
            children: row.children.map(renderRow)
        )
    }
}

public extension MenuDescriptor {
    func applying(settings: PortfolioValueDisplaySettings) -> MenuDescriptor {
        if !settings.showPortfolioValues,
           portfolioValueProtectionState == .hidden
        {
            return self
        }
        if !settings.showPortfolioValues,
           portfolioValueProtectionState == nil
        {
            return failClosedForLegacyPortfolioValues()
        }
        var descriptor = self
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
        descriptor.sections = descriptor.sections.map { section in
            var section = section
            section.rows = section.rows.map { $0.applying(settings: settings) }
            return section
        }
        if !settings.showPortfolioValues {
            descriptor.portfolioValueProtectionState = .hidden
        } else {
            descriptor.portfolioValueProtectionState = portfolioValueProtectionState
        }
        return descriptor
    }

    private func failClosedForLegacyPortfolioValues() -> MenuDescriptor {
        var descriptor = self
        descriptor.sections = descriptor.sections.map { section in
            var section = section
            section.rows = section.rows.map(\.failClosedForLegacyPortfolioValues)
            return section
        }
        descriptor.portfolioValueProtectionState = .hidden
        return descriptor
    }
}

extension MenuDescriptor {
    func trustingPortfolioValueMetadata() -> MenuDescriptor {
        var descriptor = self
        descriptor.portfolioValueProtectionState = .complete
        return descriptor
    }
}

private extension MenuRow {
    var failClosedForLegacyPortfolioValues: MenuRow {
        var row = self
        if row.detail != nil {
            row.detail = PortfolioValueDisplaySettings.hiddenPlaceholder
        }
        if var summary = row.portfolioSummary {
            summary.totalValue = PortfolioValueDisplaySettings.hiddenPlaceholder
            row.portfolioSummary = summary
        }
        if var chart = row.barChart {
            chart.bars = chart.bars.map { bar in
                var bar = bar
                bar.detail = PortfolioValueDisplaySettings.hiddenPlaceholder
                return bar
            }
            row.barChart = chart
        }
        row.children = row.children.map(\.failClosedForLegacyPortfolioValues)
        row.portfolioValueDetail = nil
        row.portfolioValueBarDetails = nil
        row.portfolioValueSummaryTotal = nil
        return row
    }

    func applying(settings: PortfolioValueDisplaySettings) -> MenuRow {
        var row = self
        if let portfolioValueDetail {
            row.detail = portfolioValueDetail.rendered(settings: settings)
        }
        if let portfolioValueSummaryTotal, var summary = row.portfolioSummary {
            summary.totalValue = display(portfolioValueSummaryTotal, settings: settings)
            row.portfolioSummary = summary
        }
        if let portfolioValueBarDetails, var chart = row.barChart {
            chart.bars = chart.bars.enumerated().map { index, bar in
                var bar = bar
                if portfolioValueBarDetails.indices.contains(index) {
                    bar.detail = portfolioValueBarDetails[index].rendered(settings: settings)
                }
                return bar
            }
            row.barChart = chart
        }
        row.children = row.children.map { $0.applying(settings: settings) }
        if !settings.showPortfolioValues {
            row.portfolioValueDetail = nil
            row.portfolioValueBarDetails = nil
            row.portfolioValueSummaryTotal = nil
        }
        return row
    }

    func withPortfolioValueDetail(
        _ value: PortfolioValueText,
        settings: PortfolioValueDisplaySettings
    ) -> MenuRow {
        var row = self
        row.detail = value.rendered(settings: settings)
        row.portfolioValueDetail = settings.showPortfolioValues ? value : nil
        return row
    }
}

public enum MenuDescriptorRenderer {
    private static let maxPulseAttentionItems = 3

    public static func render(model: PortfolioPulseModel) -> MenuDescriptor {
        render(model: model, settings: PortfolioValueDisplaySettings())
    }

    public static func render(
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> MenuDescriptor {
        let allocation = model.facetSnapshots.allocation
        let income = model.facetSnapshots.income
        let bigMovers = model.facetSnapshots.bigMovers
        let freshness = model.facetSnapshots.freshness
        let dataHealth = model.facetSnapshots.dataHealth

        let pulseRows: [MenuRow]
        if model.allQuiet {
            pulseRows = [
                MenuRow(
                    id: "pulse.quiet",
                    role: .pulseQuiet,
                    title: model.allQuietSignal.title,
                    detail: model.allQuietSignal.detail,
                    children: [
                        MenuRow(
                            id: "pulse.quiet.holdings",
                            title: "Open holdings",
                            detail: "\(model.portfolioGlance.openHoldingCount)"
                        ),
                        model.facetSnapshots.allocation.portfolioOverview.topNConcentration.map {
                            MenuRow(
                                id: "pulse.quiet.topAllocation",
                                title: "Top \($0.rankCount)",
                                detail: percent($0.weight)
                            )
                        },
                        MenuRow(
                            id: "pulse.quiet.freshness",
                            title: "Prices",
                            detail: overviewFreshnessDetail(for: freshness)
                        ),
                    ].compactMap { $0 }
                ),
            ]
        } else {
            pulseRows = model.rankedAttentionItems.prefix(maxPulseAttentionItems).map { item in
                MenuRow(
                    id: "\(item.id).glance",
                    role: .pulseAttention,
                    title: item.title,
                    children: attentionChildren(for: item, model: model, settings: settings)
                ).withPortfolioValueDetail(
                    attentionDetail(for: item, model: model),
                    settings: settings
                )
            }
        }

        let statusSignal = model.allQuiet
            ? model.allQuietSignal.title
            : model.rankedAttentionItems.first?.title ?? "Attention"
        let statusTitle = statusSignal
        let statusVisual = statusVisual(for: model)

        var descriptor = MenuDescriptor(
            statusTitle: statusTitle,
            statusBadge: model.rankedAttentionItems.isEmpty ? nil : "\(model.rankedAttentionItems.count)",
            statusVisual: statusVisual,
            sections: [
                MenuSection(
                    id: "summary",
                    title: "Summary",
                    rows: [portfolioSummaryRow(for: model, settings: settings)]
                ),
                MenuSection(
                    id: "pulse",
                    title: "Pulse",
                    rows: [
                        MenuRow(
                            id: "pulse.status",
                            role: .pulseSummary,
                            title: statusTitle
                        ),
                    ] + pulseRows
                ),
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: [
                        portfolioOverviewChartRow(for: allocation.portfolioOverview, settings: settings),
                        portfolioOverviewDetailsRow(for: allocation, model: model, settings: settings),
                    ] + allocationPressureRows(for: allocation, model: model, settings: settings)
                ),
                MenuSection(
                    id: "income",
                    title: "Income",
                    rows: IncomeCalendarDescriptor.rows(
                        for: IncomeCalendar.build(events: income.upcomingEvents, asOf: model.asOf),
                        settings: settings
                    )
                ),
                MenuSection(
                    id: "bigMovers",
                    title: "Big movers",
                    rows: [
                        MenuRow(
                            id: "bigMovers.summary",
                            role: .bigMoverSummary,
                            title: bigMoverTitle(for: bigMovers.maxMove, allocation: allocation),
                            detail: bigMovers.maxMove.map { "\(percent($0.percentChange)) over recent window" }
                                ?? "\(bigMovers.priceSeriesCount) price rows checked"
                        ),
                    ]
                ),
                MenuSection(
                    id: "freshness",
                    title: "Data",
                    rows: dataRows(freshness: freshness, health: dataHealth)
                ),
                topLevelActionsSection(refreshState: .available),
            ]
        )
        descriptor.portfolioValueProtectionState = settings.showPortfolioValues
            ? .complete
            : .hidden
        return descriptor
    }

    private static func portfolioSummaryRow(
        for model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> MenuRow {
        var row = MenuRow(
            id: "summary.performance",
            role: .portfolioSummary,
            title: "Portfolio summary",
            portfolioSummary: MenuRowPortfolioSummary(
                totalValue: display(model.portfolioGlance.totalValue, settings: settings),
                cagr: portfolioSummaryCAGR(model.portfolioPerformance),
                totalIncrease: portfolioSummaryPercent(model.portfolioPerformance.totalPercentageIncrease)
            )
        )
        row.portfolioValueSummaryTotal = settings.showPortfolioValues
            ? model.portfolioGlance.totalValue
            : nil
        return row
    }

    private static func portfolioSummaryCAGR(_ performance: PortfolioPerformanceSummary) -> String {
        guard performance.cagr == nil, performance.hasInsufficientCAGRPeriod else {
            return portfolioSummaryPercent(performance.cagr)
        }
        return "Too short to annualize"
    }

    private static func portfolioSummaryPercent(_ value: Double?) -> String {
        guard let value = finite(value) else {
            return "Unavailable"
        }
        if value > 0 {
            return "+\(percent(value))"
        }
        return percent(value)
    }

    private static func bigMoverTitle(for move: PriceMoveSummary?, allocation: AllocationSnapshot) -> String {
        guard let move else {
            return "No big movers"
        }
        return allocation.topHoldings
            .first { $0.quoteId == move.quoteId }?
            .name
            ?? "Quote \(move.quoteId)"
    }

    private static func holdingBarDetail(for holding: HoldingSummary) -> PortfolioValueText {
        PortfolioValueText([
            .literal("\(holding.name) \(percent(holding.weight)); "),
            .money(holding.worth),
        ])
    }

    private static func attentionDetail(
        for item: AttentionItem,
        model: PortfolioPulseModel
    ) -> PortfolioValueText {
        if item.id == "allocation.cashDrag",
           let cash = model.facetSnapshots.allocation.portfolioOverview.cashSummary
        {
            return PortfolioValueText([
                .literal("\(percent(cash.weight)); "),
                .money(cash.value),
            ])
        }
        if item.typedFacet == .bigMovers,
           let name = item.holdingIdentity?.name,
           let moveSize = item.moveSize,
           let beforeValue = item.beforeValue,
           let afterValue = item.afterValue,
           let currency = item.valueCurrency
        {
            var components: [PortfolioValueText.Component] = [
                .literal("\(name) moved \(signedPercent(moveSize)) from "),
                .money(Money(value: String(beforeValue), currency: currency)),
                .literal(" to "),
                .money(Money(value: String(afterValue), currency: currency)),
            ]
            if let beforeWeight = item.beforeWeight,
               let afterWeight = item.afterWeight
            {
                components.append(
                    .literal(
                        " while portfolio weight changed \(percent(beforeWeight))"
                            + " -> \(percent(afterWeight))."
                    )
                )
            } else {
                components.append(.literal(" over price history window."))
            }
            return PortfolioValueText(components)
        }
        if item.typedFacet == .income,
           let event = incomeEvent(for: item, model: model)
        {
            return incomeAttentionDetail(for: event)
        }
        if item.id == "allocation.cashDrag"
            || item.typedFacet == .bigMovers
            || item.typedFacet == .income
        {
            return PortfolioValueText([.unresolvedSensitive(item.detail)])
        }
        return PortfolioValueText([.literal(item.detail)])
    }

    private static func incomeAttentionDetail(for event: IncomeEventSummary) -> PortfolioValueText {
        let base = "\(event.symbolName) has an ex-dividend date on \(event.date)"
        guard let amount = event.amount else {
            return PortfolioValueText([.literal("\(base).")])
        }
        var components: [PortfolioValueText.Component] = [
            .literal("\(base); latest recorded dividend "),
            .money(amount),
        ]
        if let changePercent = event.changePercent,
           let priorAmount = event.priorAmount
        {
            let direction = changePercent >= 0 ? "up" : "down"
            components += [
                .literal(", \(direction) \(percent(abs(changePercent))) from prior "),
                .money(priorAmount),
            ]
        }
        components.append(.literal("."))
        return PortfolioValueText(components)
    }

    private static func incomeEvent(
        for item: AttentionItem,
        model: PortfolioPulseModel
    ) -> IncomeEventSummary? {
        model.facetSnapshots.income.upcomingEvents.first { event in
            guard event.kind == "ex-dividend",
                  event.date == item.eventDate
            else {
                return false
            }
            if let quoteID = item.holdingIdentity?.quoteId {
                return event.quoteId == quoteID
            }
            return event.symbolName == item.holdingIdentity?.name
        }
    }

    static func descriptorWithTopLevelActions(
        _ descriptor: MenuDescriptor,
        refreshState: MenuRefreshActionState
    ) -> MenuDescriptor {
        var descriptor = descriptor
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
        let actions = topLevelActionsSection(refreshState: refreshState)
        if let index = descriptor.sections.firstIndex(where: { $0.id == actions.id }) {
            descriptor.sections[index] = actions
        } else {
            descriptor.sections.append(actions)
        }
        descriptor.portfolioValueProtectionState = portfolioValueProtectionState
        return descriptor
    }

    private static func topLevelActionsSection(refreshState: MenuRefreshActionState) -> MenuSection {
        MenuSection(
            id: "actions",
            title: "Actions",
            rows: [
                refreshActionRow(state: refreshState),
                MenuRow(
                    id: "actions.openPDT",
                    role: .openPDT,
                    title: "Open PDT"
                ),
                MenuRow(
                    id: "actions.settings",
                    role: .settings,
                    title: "Settings..."
                ),
            ]
        )
    }

    private static func refreshActionRow(state: MenuRefreshActionState) -> MenuRow {
        switch state {
        case .available:
            return MenuRow(
                id: "actions.refreshNow",
                role: .fetchRetry,
                title: "Refresh now",
                detail: "Fill latest details"
            )
        case .inProgress:
            return MenuRow(
                id: "actions.refreshNow",
                role: .fetchStatus,
                title: "Refreshing now",
                detail: "Already in progress"
            )
        }
    }

    private static func portfolioOverviewDistributionRows(
        for overview: PortfolioOverviewSummary,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        [
            portfolioOverviewDistributionRow(
                id: "allocation.portfolio.sectors",
                role: .portfolioOverviewSector,
                title: "Sectors",
                summaries: overview.sectorSummary,
                settings: settings
            ),
            portfolioOverviewDistributionRow(
                id: "allocation.portfolio.assetTypes",
                role: .portfolioOverviewAssetType,
                title: "Asset types",
                summaries: overview.assetTypeSummary,
                settings: settings
            ),
        ].compactMap { $0 }
    }

    private static func portfolioOverviewChartRow(
        for overview: PortfolioOverviewSummary,
        settings: PortfolioValueDisplaySettings
    ) -> MenuRow {
        var row = MenuRow(
            id: "allocation.portfolio",
            role: .portfolioOverviewChart,
            title: "Portfolio",
            barChart: portfolioOverviewBarChart(for: overview, settings: settings)
        )
        if settings.showPortfolioValues {
            row.portfolioValueBarDetails = overview.topHoldings.map {
                holdingBarDetail(for: $0)
            }
        }
        return row
    }

    private static func portfolioOverviewDetailsRow(
        for allocation: AllocationSnapshot,
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> MenuRow {
        let overview = allocation.portfolioOverview
        return MenuRow(
            id: "allocation.portfolio.details",
            role: .portfolioOverviewDetails,
            title: "Detailed info",
            detail: "Full allocation list",
            children: allocationHoldingRows(
                for: allocation.topHoldings,
                model: model,
                settings: settings
            ) + portfolioOverviewDistributionRows(for: overview, settings: settings)
        )
    }

    private static func portfolioOverviewBarChart(
        for overview: PortfolioOverviewSummary,
        settings: PortfolioValueDisplaySettings
    ) -> MenuRowBarChart? {
        let bars = overview.topHoldings.map { holding in
            MenuRowBarChart.Bar(
                id: "allocation.portfolio.chart.\(holding.quoteId)",
                label: holdingChartLabel(holding),
                axisLabel: holdingChartAxisLabel(holding),
                weight: holding.weight,
                percentageLabel: percent(holding.weight),
                detail: holdingBarDetail(for: holding).rendered(settings: settings)
            )
        }
        guard !bars.isEmpty else {
            return nil
        }
        return MenuRowBarChart(bars: Array(bars))
    }

    private static func allocationHoldingRows(
        for holdings: [HoldingSummary],
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        holdings.map { holding in
            let attention = model.rankedAttentionItems.first { item in
                item.typedFacet == .allocation && item.holdingIdentity?.quoteId == holding.quoteId
            }
            let drillDownDetail = attention?.explanation.currentValue?.value
            return MenuRow(
                id: "allocation.\(holding.quoteId)",
                role: drillDownDetail == nil ? .allocationHolding : .allocationDrillDown,
                title: holding.name,
                detail: drillDownDetail ?? percent(holding.weight),
                children: allocationChildren(for: holding, attention: attention, settings: settings)
            )
        }
    }

    private static func allocationPressureRows(
        for allocation: AllocationSnapshot,
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        allocation.allocationPressureItems.map { item in
            MenuRow(
                id: "\(item.id).allocation",
                role: .allocationDrillDown,
                title: item.title,
                children: explanationRows(
                    for: item,
                    itemID: "\(item.id).allocation",
                    model: model,
                    settings: settings
                )
            ).withPortfolioValueDetail(attentionDetail(for: item, model: model), settings: settings)
        }
    }

    private static func holdingChartLabel(_ holding: HoldingSummary) -> String {
        if let copyableIdentifier = holding.copyableIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !copyableIdentifier.isEmpty
        {
            return copyableIdentifier
        }
        if let shortName = shortHoldingName(holding.name) {
            return shortName
        }
        return "\(holding.quoteId)"
    }

    private static func shortHoldingName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "/,("))
        guard let token = trimmed
            .components(separatedBy: separators)
            .map({ $0.trimmingCharacters(in: .punctuationCharacters) })
            .first(where: { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil })
        else {
            return nil
        }
        return String(token.prefix(12))
    }

    private static func holdingChartAxisLabel(_ holding: HoldingSummary) -> String {
        let publicLabel = holdingChartLabel(holding)
        if let first = publicLabel.first(where: { $0.isLetter }) {
            return String(first).uppercased()
        }
        if let first = holding.name.first(where: { $0.isLetter }) {
            return String(first).uppercased()
        }
        if let first = publicLabel.first(where: { $0.isNumber }) ?? holding.name.first(where: { $0.isNumber }) {
            return String(first)
        }
        return "?"
    }

    private static func portfolioOverviewDistributionRow(
        id: String,
        role: MenuRowRole,
        title: String,
        summaries: [DistributionSummary],
        settings: PortfolioValueDisplaySettings
    ) -> MenuRow? {
        guard let first = summaries.first else {
            return nil
        }
        let rows = summaries.prefix(PortfolioOverview.topHoldingLimit).map {
            MenuRow(
                id: "\(id).\(stableIDToken($0.name))",
                role: role,
                title: distributionLabel($0.name)
            ).withPortfolioValueDetail(
                PortfolioValueText([
                    .literal("\(percent($0.percentage / 100.0)); "),
                    .money($0.totalValue),
                ]),
                settings: settings
            )
        }
        return MenuRow(
            id: id,
            role: role,
            title: title,
            detail: "\(distributionLabel(first.name)) \(percent(first.percentage / 100.0))",
            children: Array(rows)
        )
    }

    private static func freshnessSummaryRow(for freshness: FreshnessSnapshot) -> MenuRow {
        MenuRow(
            id: "freshness.summary",
            role: .freshnessSummary,
            title: "Prices",
            detail: freshnessSummaryDetail(for: freshness),
            children: freshnessDetailRows(for: freshness)
        )
    }

    private static func dataRows(freshness: FreshnessSnapshot, health: DataHealthSnapshot) -> [MenuRow] {
        var rows = [freshnessSummaryRow(for: freshness)]
        if health.status != .healthy {
            rows.append(dataHealthRow(for: health))
        }
        return rows
    }

    static func dataHealthRow(for health: DataHealthSnapshot) -> MenuRow {
        MenuRow(
            id: "dataHealth",
            role: .dataHealthSummary,
            title: "Data health",
            detail: dataHealthSummaryDetail(for: health),
            children: dataHealthRows(for: health)
        )
    }

    static func descriptorByReplacingDataHealth(
        in descriptor: MenuDescriptor,
        with health: DataHealthSnapshot
    ) -> MenuDescriptor {
        var descriptor = descriptor
        let portfolioValueProtectionState = descriptor.portfolioValueProtectionState
        if health.status == .healthy {
            descriptor.sections = descriptor.sections.map { section in
                guard section.id == "freshness" else {
                    return section
                }
                var section = section
                section.rows.removeAll { $0.id == "dataHealth" }
                return section
            }
            descriptor.portfolioValueProtectionState = portfolioValueProtectionState
            return descriptor
        }
        let replacement = dataHealthRow(for: health)
        var replaced = false
        descriptor.sections = descriptor.sections.map { section in
            guard section.id == "freshness" else {
                return section
            }
            var section = section
            section.rows = section.rows.map { row in
                guard row.id == "dataHealth" else {
                    return row
                }
                replaced = true
                return replacement
            }
            if !replaced {
                section.rows.append(replacement)
            }
            return section
        }
        descriptor.portfolioValueProtectionState = portfolioValueProtectionState
        return descriptor
    }

    private static func dataHealthRows(for health: DataHealthSnapshot) -> [MenuRow] {
        [
            MenuRow(
                id: "dataHealth.source",
                role: .dataHealthSource,
                title: "Source",
                detail: health.source.detail
            ),
            MenuRow(
                id: "dataHealth.cache",
                role: .dataHealthCache,
                title: "Cache",
                detail: health.cache.summary
            ),
            MenuRow(
                id: "dataHealth.detailFill",
                role: .dataHealthDetailFill,
                title: "Detail fill",
                detail: health.detailFill.detail
            ),
            MenuRow(
                id: "dataHealth.readState",
                role: .dataHealthReadState,
                title: "Read state",
                detail: health.readState.detail
            ),
            dataHealthDiagnosticRow(for: health.diagnostic),
        ]
    }

    static func dataHealthDiagnosticRow(for diagnostic: DataHealthDiagnosticSummary?) -> MenuRow {
        guard let diagnostic else {
            return MenuRow(
                id: "dataHealth.diagnostic",
                role: .dataHealthDiagnostic,
                title: "Diagnostics",
                detail: "None recorded"
            )
        }
        return MenuRow(
            id: "dataHealth.diagnostic",
            role: .dataHealthDiagnostic,
            title: "Diagnostics",
            detail: diagnostic.detail,
            children: [
                MenuRow(
                    id: "dataHealth.diagnostic.copy",
                    role: .dataHealthDiagnosticCopy,
                    actionTarget: MenuRowActionTarget(
                        kind: .copyDataHealthDiagnostic,
                        id: "dataHealth.diagnostic.copy",
                        copyText: diagnostic.copyText
                    ),
                    title: "Copy diagnostics",
                    detail: "Redacted"
                ),
            ]
        )
    }

    private static func dataHealthSummaryDetail(for health: DataHealthSnapshot) -> String {
        switch health.status {
        case .healthy:
            return "Healthy"
        case .degraded:
            return "Needs attention"
        }
    }

    private static func freshnessDetailRows(for freshness: FreshnessSnapshot) -> [MenuRow] {
        var rows: [MenuRow] = []
        if freshness.staleHoldingCount > 0 {
            rows.append(
                MenuRow(
                    id: "freshness.staleCount",
                    role: .freshnessStaleCount,
                    title: "Stale holdings",
                    detail: "\(freshness.staleHoldingCount)"
                )
            )
        }
        if freshness.status != .fresh {
            rows.append(
                MenuRow(
                    id: "freshness.oldestPrice",
                    role: .freshnessOldestPrice,
                    title: "Oldest price",
                    detail: freshness.oldestPriceAsOf ?? "Unknown"
                )
            )
        }
        if freshness.status == .partial {
            rows.append(
                MenuRow(
                    id: "freshness.detailFill",
                    role: .freshnessDetailFill,
                    title: "Latest complete detail fill",
                    detail: freshness.latestCompleteDetailFillAsOf ?? "Not recorded"
                )
            )
        }
        return rows
    }

    private static func overviewFreshnessDetail(for freshness: FreshnessSnapshot) -> String {
        switch freshness.status {
        case .fresh:
            return freshness.oldestPriceAsOf ?? "Current"
        case .stale:
            return "\(freshness.staleHoldingCount) stale"
        case .partial:
            return "Partial"
        case .unknown:
            return "Unknown"
        }
    }

    private static func freshnessSummaryDetail(for freshness: FreshnessSnapshot) -> String {
        switch freshness.status {
        case .fresh:
            return freshness.oldestPriceAsOf.map { "Current through \($0)" } ?? "Current"
        case .stale:
            let oldest = freshness.oldestPriceAsOf.map { "; oldest \($0)" } ?? ""
            return "\(freshness.staleHoldingCount) stale\(oldest)"
        case .partial:
            return freshness.oldestPriceAsOf.map { "Partial; oldest \($0)" } ?? "Partial"
        case .unknown:
            return "Unknown price dates"
        }
    }

    private static func statusVisual(for model: PortfolioPulseModel) -> StatusVisualState {
        StatusVisualState(
            barHeights: concentrationBarHeights(from: model.facetSnapshots.allocation),
            filledBarCount: model.rankedAttentionItems.count,
            isDimmed: model.facetSnapshots.freshness.status != .fresh
        )
    }

    private static func concentrationBarHeights(from allocation: AllocationSnapshot) -> [Double] {
        let xRayWeights = (allocation.xRayHoldings ?? []).map(\.weight).filter { $0 > 0 }
        guard !xRayWeights.isEmpty else {
            return StatusVisualState().barHeights
        }
        return concentrationStackShape(fromXRayWeights: xRayWeights)
    }

    private static func concentrationStackShape(fromXRayWeights weights: [Double]) -> [Double] {
        let sortedWeights = weights
            .filter { $0 > 0 }
            .sorted(by: >)
        guard !sortedWeights.isEmpty else {
            return StatusVisualState().barHeights
        }
        let scale = concentrationSideScale(from: sortedWeights)
        return [
            rounded(StatusVisualState.defaultBarHeights[0] * scale, places: 3),
            StatusVisualState.defaultBarHeights[1],
            min(1.0, rounded(StatusVisualState.defaultBarHeights[2] * scale, places: 3)),
        ]
    }

    private static func concentrationSideScale(from portfolioWeights: [Double]) -> Double {
        let hhi = portfolioWeights.reduce(0.0) { $0 + ($1 * $1) }
        let diversifiedHHI = 1.0 / 25.0
        let concentratedHHI = 0.16
        let pressure = max(0.0, min(1.0, (hhi - diversifiedHHI) / (concentratedHHI - diversifiedHHI)))
        return 1.25 - (0.5 * pressure)
    }

    private static func attentionChildren(
        for item: AttentionItem,
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        var rows = explanationRows(for: item, itemID: item.id, model: model, settings: settings)
        if let sources = sourceSlotsDetail(for: item, supportingDataSlots: model.supportingDataSlots) {
            rows.append(
                MenuRow(
                    id: "\(item.id).sources",
                    role: .pulseAttentionExpansion,
                    title: "Sources",
                    detail: sources
                )
            )
        }
        rows.append(
            MenuRow(
                id: "\(item.id).markRead",
                role: .pulseMarkRead,
                title: "Mark as read",
                actionPayload: item.id
            )
        )
        return rows
    }

    private static func explanationRows(
        for item: AttentionItem,
        itemID: String,
        model: PortfolioPulseModel,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        let explanation = item.explanation
        return [
            ("trigger", explanation.trigger),
            ("severity", explanation.severity),
            ("threshold", explanation.threshold),
            ("currentValue", explanation.currentValue),
            ("priorValue", explanation.priorValue),
        ].compactMap { suffix, fact in
            guard let fact else { return nil }
            return MenuRow(
                id: "\(itemID).\(suffix)",
                role: .pulseAttentionExpansion,
                title: fact.label
            ).withPortfolioValueDetail(
                explanationDetail(for: item, suffix: suffix, fact: fact, model: model),
                settings: settings
            )
        }
    }

    private static func explanationDetail(
        for item: AttentionItem,
        suffix: String,
        fact: AttentionExplanationFact,
        model: PortfolioPulseModel
    ) -> PortfolioValueText {
        if item.id == "allocation.cashDrag",
           suffix == "currentValue",
           let cash = model.facetSnapshots.allocation.portfolioOverview.cashSummary
        {
            return PortfolioValueText([
                .literal("\(percent(cash.weight)); "),
                .money(cash.value),
            ])
        }
        if item.typedFacet == .bigMovers,
           let currency = item.valueCurrency
        {
            if suffix == "currentValue", let afterValue = item.afterValue {
                return .money(Money(value: String(afterValue), currency: currency))
            }
            if suffix == "priorValue", let beforeValue = item.beforeValue {
                return .money(Money(value: String(beforeValue), currency: currency))
            }
        }
        if item.typedFacet == .income,
           suffix == "priorValue",
           let priorAmount = incomeEvent(for: item, model: model)?.priorAmount
        {
            return .money(priorAmount)
        }
        if (item.id == "allocation.cashDrag" && suffix == "currentValue")
            || (item.typedFacet == .bigMovers && ["currentValue", "priorValue"].contains(suffix))
            || (item.typedFacet == .income && suffix == "priorValue")
        {
            return PortfolioValueText([.unresolvedSensitive(factDetail(fact))])
        }
        return PortfolioValueText([.literal(factDetail(fact))])
    }

    private static func factDetail(_ fact: AttentionExplanationFact) -> String {
        if fact.key == "severity",
           let score = fact.numericValue
        {
            return "\(fact.value); score \(decimalString(String(score), places: 2))"
        }
        return fact.value
    }

    private static func sourceSlotsDetail(
        for item: AttentionItem,
        supportingDataSlots: [SupportingDataSlot]
    ) -> String? {
        let labelsByID = supportingDataSlots.reduce(into: [String: String]()) { labelsByID, slot in
            labelsByID[slot.id] = slot.label
        }
        let explanationSlots = item.explanation.supportingSourceSlots
        let slots = explanationSlots.isEmpty
            ? item.supportingDataSlotIDs.map { AttentionExplanationSourceSlot(id: $0) }
            : explanationSlots
        let labels = slots.map { slot in
            slot.label ?? labelsByID[slot.id] ?? slot.id
        }
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
    }

    private static func allocationChildren(
        for holding: HoldingSummary,
        attention: AttentionItem?,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        var rows = [
            MenuRow(
                id: "allocation.\(holding.quoteId).worth",
                title: "Worth"
            ).withPortfolioValueDetail(.money(holding.worth), settings: settings),
        ]
        if let price = holding.price {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).price",
                    title: "Price"
                ).withPortfolioValueDetail(.money(price), settings: settings)
            )
        }
        if let isin = holding.isin {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).isin",
                    title: "ISIN",
                    detail: isin
                )
            )
        }
        if let recentMove = holding.recentMove {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).recentMove",
                    title: "Recent move",
                    detail: "\(signedPercent(recentMove.percentChange)) from \(recentMove.fromDate) to \(recentMove.toDate)"
                )
            )
        }
        if let nextIncomeEvent = holding.nextIncomeEvent {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).nextIncome",
                    title: "Next income"
                ).withPortfolioValueDetail(incomeEventDetail(for: nextIncomeEvent), settings: settings)
            )
        }
        if let averageBuyPrice = holding.averageBuyPrice {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).averageBuyPrice",
                    title: "Average buy price"
                ).withPortfolioValueDetail(.money(averageBuyPrice), settings: settings)
            )
        }
        if let gainLoss = holding.gainLoss {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).gainLoss",
                    title: "Gain/loss"
                ).withPortfolioValueDetail(.money(gainLoss), settings: settings)
            )
        }
        if let gainLossPercentage = holding.gainLossPercentage {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).gainLossPercentage",
                    title: "Gain/loss %",
                    detail: signedPercent(gainLossPercentage)
                )
            )
        }
        if let copyableIdentifier = holding.copyableIdentifier {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).copyIdentifier",
                    role: .holdingIdentifierCopy,
                    actionTarget: MenuRowActionTarget(
                        kind: .copyHoldingIdentifier,
                        id: "allocation.\(holding.quoteId).copyIdentifier",
                        copyText: copyableIdentifier
                    ),
                    title: "Copy identifier",
                    detail: copyableIdentifier
                )
            )
        }
        if let threshold = attention?.explanation.threshold {
            rows.append(
                MenuRow(
                    id: "allocation.\(holding.quoteId).line",
                    title: threshold.label,
                    detail: threshold.value
                )
            )
        }
        return rows
    }

}

enum MenuRefreshActionState {
    case available
    case inProgress
}

public enum IncomeCalendarDescriptor {
    public static let previewLimit = 3

    public static func rows(for intent: IncomeCalendarIntent) -> [MenuRow] {
        rows(for: intent, settings: PortfolioValueDisplaySettings())
    }

    public static func rows(
        for intent: IncomeCalendarIntent,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        guard let nextEvent = intent.nextEvent else {
            return [
                MenuRow(
                    id: "income.empty",
                    role: .incomeEmpty,
                    title: "No income events",
                    detail: "No calendar events in the next window"
                ),
            ]
        }

        let previewEvents = Array(intent.events.prefix(previewLimit))
        let overflowEvents = Array(intent.events.dropFirst(previewLimit))
        let previewRows = previewEvents.enumerated().map { index, event in
            if index == 0 {
                return MenuRow(
                    id: "income.next",
                    role: .incomeNext,
                    actionTarget: incomeEventActionTarget(for: event, rowID: "income.next"),
                    title: "Next income: \(event.symbolName)",
                    children: incomeEventChildren(for: event, settings: settings)
                ).withPortfolioValueDetail(incomeEventDetail(for: event), settings: settings)
            }
            return incomeEventRow(for: event, id: incomeEventRowID(for: event), settings: settings)
        }
        let overflowRows = overflowGroups(
            for: overflowEvents,
            nextDate: nextEvent.date,
            asOf: intent.asOf,
            settings: settings
        )

        return [
            MenuRow(
                id: "income.summary",
                role: .incomeSummary,
                title: "Income window",
                detail: summaryDetail(for: intent.summary)
            ),
        ] + previewRows + overflowRows
    }

    private static func summaryDetail(for summary: IncomeCalendarSummary) -> String {
        guard summary.eventCount > 0 else {
            return "No calendar events in the next window"
        }

        let eventWord = summary.eventCount == 1 ? "event" : "events"
        let window = summary.windowEnd.map { " through \($0)" } ?? ""
        if summary.estimatedCount == 0 {
            return "\(summary.confirmedCount) confirmed \(eventWord)\(window)"
        }
        if summary.confirmedCount == 0 {
            return "\(summary.estimatedCount) estimated \(eventWord)\(window)"
        }
        return "\(summary.eventCount) \(eventWord)\(window); \(summary.confirmedCount) confirmed, \(summary.estimatedCount) estimated"
    }

    private static func overflowGroups(
        for events: [IncomeEventSummary],
        nextDate: String,
        asOf: String,
        settings: PortfolioValueDisplaySettings
    ) -> [MenuRow] {
        let buckets = IncomeOverflowBucket.allCases.map { bucket in
            let bucketEvents = events.filter { bucket.contains($0, nextDate: nextDate, asOf: asOf) }
            return (bucket, bucketEvents)
        }

        return buckets.compactMap { bucket, bucketEvents in
            guard !bucketEvents.isEmpty else { return nil }
            let groupID = "income.overflow.\(bucket.id)"
            return MenuRow(
                id: groupID,
                role: .incomeDrillDown,
                title: bucket.title,
                detail: bucketEvents.count == 1 ? "1 event" : "\(bucketEvents.count) events",
                children: bucketEvents.map { event in
                    incomeEventRow(
                        for: event,
                        id: "\(groupID).\(incomeEventRowID(for: event))",
                        settings: settings
                    )
                }
            )
        }
    }
}

private enum IncomeOverflowBucket: CaseIterable {
    case next
    case thisWeek
    case later

    var id: String {
        switch self {
        case .next: "next"
        case .thisWeek: "this-week"
        case .later: "later"
        }
    }

    var title: String {
        switch self {
        case .next: "Next"
        case .thisWeek: "This week"
        case .later: "Later"
        }
    }

    func contains(_ event: IncomeEventSummary, nextDate: String, asOf: String) -> Bool {
        switch self {
        case .next:
            return event.date == nextDate
        case .thisWeek:
            return event.date != nextDate && event.date <= dayString(asOf, addingDays: 7)
        case .later:
            return event.date != nextDate && event.date > dayString(asOf, addingDays: 7)
        }
    }
}

private func incomeEventRow(
    for event: IncomeEventSummary,
    id: String,
    settings: PortfolioValueDisplaySettings
) -> MenuRow {
    MenuRow(
        id: id,
        role: .incomeEvent,
        actionTarget: incomeEventActionTarget(for: event, rowID: id),
        title: event.symbolName,
        children: incomeEventChildren(for: event, rowID: id, settings: settings)
    ).withPortfolioValueDetail(incomeEventDetail(for: event), settings: settings)
}

private func incomeEventChildren(
    for event: IncomeEventSummary,
    rowID: String? = nil,
    settings: PortfolioValueDisplaySettings
) -> [MenuRow] {
    let baseID = rowID ?? incomeEventRowID(for: event)
    func child(_ suffix: String, role: MenuRowRole, title: String, detail: String) -> MenuRow {
        let id = "\(baseID).\(suffix)"
        return MenuRow(
            id: id,
            role: role,
            actionTarget: incomeEventActionTarget(for: event, rowID: id),
            title: title,
            detail: detail
        )
    }
    return [
        child("date", role: .incomeEventDate, title: "Date", detail: event.date),
        child("kind", role: .incomeEventKind, title: "Kind", detail: incomeEventKindLabel(for: event.kind)),
        child("state", role: .incomeEventState, title: "State", detail: event.estimated ? "Estimated" : "Confirmed"),
        event.amount.map {
            child("amount", role: .incomeEventAmount, title: "Amount", detail: "")
                .withPortfolioValueDetail(.money($0), settings: settings)
        },
        incomeEventChangeDetail(for: event).map { detail in
            child("change", role: .incomeEventChange, title: "Change", detail: "")
                .withPortfolioValueDetail(detail, settings: settings)
        },
    ].compactMap { $0 }
}

private func incomeEventActionTarget(for event: IncomeEventSummary, rowID: String) -> MenuRowActionTarget {
    let eventID = incomeEventRowID(for: event)
    return MenuRowActionTarget(
        kind: .incomeEvent,
        id: eventID,
        incomeEvent: IncomeEventActionTarget(
            eventID: eventID,
            rowID: rowID,
            date: event.date,
            kind: event.kind,
            symbolName: event.symbolName,
            estimated: event.estimated,
            symbolId: event.symbolId,
            quoteId: event.quoteId
        )
    )
}

private func incomeEventDetail(for event: IncomeEventSummary) -> PortfolioValueText {
    var components: [PortfolioValueText.Component] = [
        .literal(
            "\(incomeEventKindLabel(for: event.kind)) on \(event.date); "
                + (event.estimated ? "estimated" : "confirmed")
        ),
    ]
    if let amount = event.amount {
        components += [.literal("; "), .money(amount)]
    }
    if let change = incomeEventChangeDetail(for: event) {
        components.append(.literal("; "))
        components.append(contentsOf: change.components)
    }
    return PortfolioValueText(components)
}

private func incomeEventKindLabel(for kind: String) -> String {
    switch kind {
    case "ex-dividend":
        return "Ex-dividend date"
    case "payment-dividend":
        return "Dividend payment date"
    default:
        return kind
    }
}

private func incomeEventChangeDetail(for event: IncomeEventSummary) -> PortfolioValueText? {
    guard let changePercent = event.changePercent,
          let priorAmount = event.priorAmount
    else {
        return nil
    }
    return PortfolioValueText([
        .literal("\(signedPercent(changePercent)) from "),
        .money(priorAmount),
    ])
}

private func incomeEventRowID(for event: IncomeEventSummary) -> String {
    let identity = event.quoteId.map { "quote.\($0)" }
        ?? event.symbolId.map { "symbol.\($0)" }
        ?? "portfolio"
    return "income.\(identity).\(event.kind).\(event.date)"
}

func incomeCalendarEventRanksBefore(_ lhs: IncomeEventSummary, _ rhs: IncomeEventSummary) -> Bool {
    if lhs.date != rhs.date {
        return lhs.date < rhs.date
    }
    let lhsPriority = incomeCalendarEventPriority(lhs.kind)
    let rhsPriority = incomeCalendarEventPriority(rhs.kind)
    if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
    }
    if lhs.symbolName != rhs.symbolName {
        return lhs.symbolName < rhs.symbolName
    }
    return incomeEventRowID(for: lhs) < incomeEventRowID(for: rhs)
}

private func incomeCalendarEventPriority(_ kind: String) -> Int {
    switch kind {
    case "ex-dividend":
        return 0
    case "payment-dividend":
        return 1
    default:
        return 2
    }
}

func isIncomeCalendarEventKind(_ kind: String) -> Bool {
    kind == "ex-dividend" || kind == "payment-dividend"
}
