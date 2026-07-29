import Foundation

public enum PressureEngine {
    public static let concentrationThreshold = 0.20
    public static let sectorConcentrationThreshold = 0.30
    public static let cashDragThreshold = 0.10
    public static let concentrationDriftThreshold = 0.05
    public static let bigMoverThreshold = 0.10

    public static func buildModel(
        from snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot? = nil,
        readState: PulseReadState? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        today: String? = nil
    ) -> PortfolioPulseModel {
        let portfolioOverview = PortfolioOverview.build(from: snapshot)
        let priorPortfolioOverview = priorSnapshot.map(PortfolioOverview.build)
        let allocationItems = ranked(
            concentrationItems(from: snapshot, priorSnapshot: priorSnapshot, readState: readState)
                + sectorConcentrationItems(from: portfolioOverview)
                + cashDragItems(from: portfolioOverview)
                + concentrationDriftItems(from: portfolioOverview, priorOverview: priorPortfolioOverview)
        )
        let rankedItems = ranked(
            allocationItems
                + incomeItems(from: snapshot)
                + bigMoverItems(from: snapshot, priorSnapshot: priorSnapshot)
        )
        let totalValue = snapshot.totalValue
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        let freshness = FreshnessLedger.build(
            from: snapshot,
            detailRefreshOutcome: effectiveDetailRefreshOutcome,
            today: today
        )
        let recentMovesByQuoteID = recentMoves(from: snapshot.priceSeries)
        let nextIncomeEventsByQuoteID = nextIncomeEventsByQuoteID(from: snapshot)
        let topHoldingSummaries = snapshot.openHoldings
            .sorted(by: ranksByAllocation)
            .map {
                HoldingSummary(
                    name: $0.name,
                    quoteId: $0.quoteId,
                    weight: $0.weight,
                    worth: $0.worth,
                    price: validMoney($0.price),
                    copyableIdentifier: $0.copyableIdentifier,
                    isin: $0.isin,
                    recentMove: recentMovesByQuoteID[$0.quoteId],
                    nextIncomeEvent: nextIncomeEventsByQuoteID[$0.quoteId],
                    averageBuyPrice: $0.averageBuyPrice,
                    gainLoss: $0.gainLoss,
                    gainLossPercentage: $0.gainLossPercentage
                )
            }
        var supportingDataSlots = [
            SupportingDataSlot(
                id: "allocation.overview",
                facet: "allocation",
                label: "Portfolio overview",
                itemCount: portfolioOverview.openHoldingCount
            ),
            SupportingDataSlot(
                id: "allocation.holdings",
                facet: "allocation",
                label: "Open holdings",
                itemCount: snapshot.openHoldings.count
            ),
            SupportingDataSlot(
                id: "allocation.sectors",
                facet: "allocation",
                label: "Sector breakdown",
                itemCount: snapshot.sectors.count
            ),
            SupportingDataSlot(
                id: "income.calendar",
                facet: "income",
                label: "Calendar events",
                itemCount: snapshot.incomeEvents.count
            ),
            SupportingDataSlot(
                id: "bigMovers.prices",
                facet: "bigMovers",
                label: "Price rows",
                itemCount: snapshot.priceSeries.count
            ),
        ]
        if let priorSnapshot {
            supportingDataSlots.append(
                SupportingDataSlot(
                    id: "bigMovers.priorSnapshot",
                    facet: "bigMovers",
                    label: "Prior snapshot",
                    itemCount: priorSnapshot.openHoldings.count
                )
            )
            supportingDataSlots.append(
                SupportingDataSlot(
                    id: "allocation.priorSnapshot",
                    facet: "allocation",
                    label: "Prior allocation snapshot",
                    itemCount: priorSnapshot.openHoldings.count
                )
            )
        }

        return PortfolioPulseModel(
            asOf: snapshot.asOf,
            allQuiet: rankedItems.isEmpty,
            allQuietSignal: AllQuietSignal(
                title: "All quiet",
                detail: "No attention items right now.",
                totalValue: totalValue
            ),
            rankedAttentionItems: rankedItems,
            portfolioGlance: PortfolioGlanceContext(
                totalValue: totalValue,
                openHoldingCount: snapshot.openHoldings.count,
                worstPriceAsOf: freshness.worstPriceAsOf,
                priorSnapshotAsOf: priorSnapshot?.asOf
            ),
            portfolioPerformance: snapshot.performance ?? PortfolioPerformanceSummary(),
            facetSnapshots: FacetSnapshots(
                allocation: AllocationSnapshot(
                    totalValue: totalValue,
                    openHoldingCount: snapshot.openHoldings.count,
                    topHoldings: topHoldingSummaries,
                    sectorBreakdown: snapshot.sectors,
                    assetTypeBreakdown: snapshot.assetTypes,
                    xRayHoldings: snapshot.xRayHoldings,
                    portfolioOverview: portfolioOverview,
                    allocationPressureItems: allocationItems
                ),
                income: IncomeSnapshot(
                    upcomingEvents: snapshot.incomeEvents.sorted { $0.date < $1.date },
                    dividendRowCount: snapshot.dividendRowCount
                ),
                bigMovers: BigMoversSnapshot(
                    priceSeriesCount: snapshot.priceSeries.count,
                    maxMove: maxMove(from: snapshot.priceSeries)
                ),
                freshness: freshness,
                dataHealth: DataHealth.build(
                    DataHealthInput.default(
                        freshness: freshness,
                        readState: readState,
                        detailRefreshOutcome: effectiveDetailRefreshOutcome
                    )
                )
            ),
            supportingDataSlots: supportingDataSlots
        )
    }

    private static func ranked(_ items: [AttentionItem]) -> [AttentionItem] {
        items
            .sorted(by: ranksBefore)
            .enumerated()
            .map { offset, item in
                var rankedItem = item
                rankedItem.rank = offset + 1
                return rankedItem
            }
    }

    private static func dayDate(from value: String) -> Date? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return dateCalendar.date(
            from: DateComponents(
                calendar: dateCalendar,
                timeZone: dateCalendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }

    private static var dateCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func ranksBefore(_ lhs: AttentionItem, _ rhs: AttentionItem) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.typedFacet == .allocation,
           rhs.typedFacet == .allocation,
           let lhsWeight = lhs.currentWeight,
           let rhsWeight = rhs.currentWeight,
           lhsWeight != rhsWeight
        {
            return lhsWeight > rhsWeight
        }
        if lhs.typedFacet == .allocation,
           rhs.typedFacet == .allocation,
           let lhsName = lhs.holdingIdentity?.name,
           let rhsName = rhs.holdingIdentity?.name,
           lhsName != rhsName
        {
            return lhsName < rhsName
        }
        return lhs.id < rhs.id
    }

    private static func concentrationItems(
        from snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        readState: PulseReadState?
    ) -> [AttentionItem] {
        let priorHoldings = priorSnapshot?.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holding
        }
        let readFingerprints = readState.map { Set($0.readFingerprints) } ?? []
        return concentrationMaterialItems(from: snapshot)
            .compactMap { item in
                guard priorSnapshot != nil else { return item }
                let priorWeight = item.holdingIdentity.flatMap { priorHoldings?[$0.quoteId]?.weight } ?? 0
                var itemWithPrior = item
                itemWithPrior.explanation.priorValue = AttentionExplanationFact(
                    key: "priorValue",
                    label: "Prior",
                    value: percent(priorWeight),
                    numericValue: priorWeight,
                    unit: "fraction"
                )
                if priorWeight < concentrationThreshold {
                    var freshItem = itemWithPrior
                    freshItem.resetsReadState = true
                    return freshItem
                }
                guard let prefix = itemWithPrior.concentrationReadFingerprintPrefix else {
                    return nil
                }
                let changedReadFingerprintExists = readFingerprints.contains { fingerprint in
                    fingerprint.hasPrefix(prefix) && fingerprint != itemWithPrior.readFingerprint
                }
                return changedReadFingerprintExists ? itemWithPrior : nil
            }
    }

    private static func concentrationMaterialItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        snapshot.openHoldings
            .filter { $0.weight >= concentrationThreshold }
            .sorted(by: ranksByAllocation)
            .enumerated()
            .map { offset, holding in
                let score = concentrationScore(weight: holding.weight, threshold: concentrationThreshold)
                return AttentionItem(
                    id: "allocation.concentration.\(holding.quoteId)",
                    facet: "allocation",
                    rank: offset + 1,
                    title: "\(holding.name) concentration",
                    detail: percent(holding.weight),
                    severity: score >= 0.8 ? "high" : "medium",
                    score: score,
                    holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
                    currentWeight: holding.weight,
                    threshold: concentrationThreshold,
                    supportingDataSlotIDs: ["allocation.holdings"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Concentration line crossed"
                        ),
                        severity: explanationSeverity(
                            severity: score >= 0.8 ? "high" : "medium",
                            score: score
                        ),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: percent(concentrationThreshold),
                            numericValue: concentrationThreshold,
                            unit: "fraction"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: percent(holding.weight),
                            numericValue: holding.weight,
                            unit: "fraction"
                        ),
                        supportingSourceSlots: explanationSourceSlots(["allocation.holdings"])
                    )
                )
            }
    }

    private static func sectorConcentrationItems(from overview: PortfolioOverviewSummary) -> [AttentionItem] {
        overview.sectorSummary
            .filter { ($0.percentage / 100.0) >= sectorConcentrationThreshold }
            .enumerated()
            .map { offset, sector in
                let weight = sector.percentage / 100.0
                let score = concentrationScore(weight: weight, threshold: sectorConcentrationThreshold)
                let title = "\(distributionLabel(sector.name)) sector concentration"
                return AttentionItem(
                    id: "allocation.sector.\(stableIDToken(sector.name))",
                    facet: "allocation",
                    rank: offset + 1,
                    title: title,
                    detail: percent(weight),
                    severity: score >= 0.8 ? "high" : "medium",
                    score: score,
                    currentWeight: weight,
                    threshold: sectorConcentrationThreshold,
                    supportingDataSlotIDs: ["allocation.sectors"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Sector concentration line crossed"
                        ),
                        severity: explanationSeverity(
                            severity: score >= 0.8 ? "high" : "medium",
                            score: score
                        ),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: percent(sectorConcentrationThreshold),
                            numericValue: sectorConcentrationThreshold,
                            unit: "fraction"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: percent(weight),
                            numericValue: weight,
                            unit: "fraction"
                        ),
                        supportingSourceSlots: explanationSourceSlots(["allocation.sectors"])
                    )
                )
            }
    }

    private static func cashDragItems(from overview: PortfolioOverviewSummary) -> [AttentionItem] {
        guard let cash = overview.cashSummary,
              cash.weight >= cashDragThreshold
        else {
            return []
        }
        let score = concentrationScore(weight: cash.weight, threshold: cashDragThreshold)
        return [
            AttentionItem(
                id: "allocation.cashDrag",
                facet: "allocation",
                rank: 1,
                title: "Cash drag",
                detail: "\(percent(cash.weight)); \(display(cash.value))",
                severity: score >= 0.8 ? "high" : "medium",
                score: score,
                currentWeight: cash.weight,
                threshold: cashDragThreshold,
                supportingDataSlotIDs: ["allocation.overview"],
                explanation: AttentionExplanation(
                    trigger: AttentionExplanationFact(
                        key: "trigger",
                        label: "Trigger",
                        value: "Cash allocation line crossed"
                    ),
                    severity: explanationSeverity(
                        severity: score >= 0.8 ? "high" : "medium",
                        score: score
                    ),
                    threshold: AttentionExplanationFact(
                        key: "threshold",
                        label: "Threshold",
                        value: percent(cashDragThreshold),
                        numericValue: cashDragThreshold,
                        unit: "fraction"
                    ),
                    currentValue: AttentionExplanationFact(
                        key: "currentValue",
                        label: "Current",
                        value: "\(percent(cash.weight)); \(display(cash.value))",
                        numericValue: cash.weight,
                        unit: "fraction"
                    ),
                    supportingSourceSlots: explanationSourceSlots(["allocation.overview"])
                )
            ),
        ]
    }

    private static func concentrationDriftItems(
        from overview: PortfolioOverviewSummary,
        priorOverview: PortfolioOverviewSummary?
    ) -> [AttentionItem] {
        guard let current = overview.topNConcentration,
              let prior = priorOverview?.topNConcentration,
              current.rankCount == prior.rankCount
        else {
            return []
        }
        let drift = current.weight - prior.weight
        guard drift >= concentrationDriftThreshold else {
            return []
        }
        let score = concentrationScore(weight: drift, threshold: concentrationDriftThreshold)
        return [
            AttentionItem(
                id: "allocation.concentrationDrift.top\(current.rankCount)",
                facet: "allocation",
                rank: 1,
                title: "Top \(current.rankCount) concentration drift",
                detail: "\(percent(prior.weight)) -> \(percent(current.weight))",
                severity: score >= 0.8 ? "high" : "medium",
                score: score,
                currentWeight: current.weight,
                threshold: concentrationDriftThreshold,
                beforeWeight: prior.weight,
                afterWeight: current.weight,
                supportingDataSlotIDs: ["allocation.overview", "allocation.priorSnapshot"],
                explanation: AttentionExplanation(
                    trigger: AttentionExplanationFact(
                        key: "trigger",
                        label: "Trigger",
                        value: "Top concentration drift crossed"
                    ),
                    severity: explanationSeverity(
                        severity: score >= 0.8 ? "high" : "medium",
                        score: score
                    ),
                    threshold: AttentionExplanationFact(
                        key: "threshold",
                        label: "Threshold",
                        value: percent(concentrationDriftThreshold),
                        numericValue: concentrationDriftThreshold,
                        unit: "fraction"
                    ),
                    currentValue: AttentionExplanationFact(
                        key: "currentValue",
                        label: "Current",
                        value: percent(current.weight),
                        numericValue: current.weight,
                        unit: "fraction"
                    ),
                    priorValue: AttentionExplanationFact(
                        key: "priorValue",
                        label: "Prior",
                        value: percent(prior.weight),
                        numericValue: prior.weight,
                        unit: "fraction"
                    ),
                    supportingSourceSlots: explanationSourceSlots(["allocation.overview", "allocation.priorSnapshot"])
                )
            ),
        ]
    }

    private static func ranksByAllocation(_ lhs: NormalizedHolding, _ rhs: NormalizedHolding) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight > rhs.weight
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.quoteId < rhs.quoteId
    }

    private static func nextIncomeEventsByQuoteID(from snapshot: PortfolioSnapshot) -> [Int: IncomeEventSummary] {
        guard let asOfDate = dayDate(from: snapshot.asOf) else {
            return [:]
        }

        let openQuoteIDs = Set(snapshot.openHoldings.map(\.quoteId))
        return snapshot.incomeEvents
            .filter { isIncomeCalendarEventKind($0.kind) }
            .filter { event in
                guard let quoteId = event.quoteId,
                      openQuoteIDs.contains(quoteId),
                      let eventDate = dayDate(from: event.date)
                else {
                    return false
                }
                return eventDate >= asOfDate
            }
            .sorted(by: incomeCalendarEventRanksBefore)
            .reduce(into: [Int: IncomeEventSummary]()) { eventsByQuoteID, event in
                guard let quoteId = event.quoteId,
                      eventsByQuoteID[quoteId] == nil
                else {
                    return
                }
                eventsByQuoteID[quoteId] = event
            }
    }

    private struct BigMoverSignal {
        var beforeDecimal: Decimal
        var afterDecimal: Decimal
        var absoluteDecimalMove: Decimal
        var moveSize: Double
        var currency: String?
        var windowStart: String
        var windowEnd: String

        func hasSameValues(as other: BigMoverSignal) -> Bool {
            beforeDecimal == other.beforeDecimal && afterDecimal == other.afterDecimal
        }
    }

    private enum PriorBigMoverSignal {
        case triggered(BigMoverSignal)
        case belowThreshold
        case unavailable
    }

    private static func bigMoverItems(from snapshot: PortfolioSnapshot, priorSnapshot: PortfolioSnapshot?) -> [AttentionItem] {
        let priorHoldings = priorSnapshot?.openHoldings.reduce(into: [Int: NormalizedHolding]()) { holdings, holding in
            holdings[holding.quoteId] = holdings[holding.quoteId] ?? holding
        } ?? [:]
        let priceHistorySignals = bigMoverSignals(from: snapshot.priceSeries)
        let moverThreshold = Decimal(string: String(bigMoverThreshold)) ?? 0
        return snapshot.openHoldings.compactMap { holding -> AttentionItem? in
            var canUsePriceHistory = priorHoldings[holding.quoteId] == nil
            if let priorHolding = priorHoldings[holding.quoteId] {
                switch priorSnapshotSignal(
                   holding: holding,
                   priorHolding: priorHolding,
                   priorSnapshot: priorSnapshot,
                   currentAsOf: snapshot.asOf,
                   threshold: moverThreshold
                ) {
                case .triggered(let signal):
                    var emittedSignal = signal
                    if let historySignal = priceHistorySignals[holding.quoteId],
                       historySignal.hasSameValues(as: signal)
                    {
                        emittedSignal.windowStart = historySignal.windowStart
                        emittedSignal.windowEnd = historySignal.windowEnd
                    }
                    return bigMoverItem(
                        holding: holding,
                        signal: emittedSignal,
                        beforeWeight: priorHolding.weight,
                        sourceSlotIDs: ["bigMovers.priorSnapshot", "bigMovers.prices"]
                    )
                case .belowThreshold:
                    return nil
                case .unavailable:
                    canUsePriceHistory = true
                }
            }

            guard canUsePriceHistory,
                  let signal = priceHistorySignals[holding.quoteId],
                  signal.absoluteDecimalMove >= moverThreshold
            else { return nil }

            return bigMoverItem(
                holding: holding,
                signal: signal,
                beforeWeight: nil,
                sourceSlotIDs: ["bigMovers.prices"]
            )
        }
    }

    private static func priorSnapshotSignal(
        holding: NormalizedHolding,
        priorHolding: NormalizedHolding,
        priorSnapshot: PortfolioSnapshot?,
        currentAsOf: String,
        threshold: Decimal
    ) -> PriorBigMoverSignal {
        guard let priorSnapshot,
              let priorPrice = priorHolding.price,
              let price = holding.price,
              let beforeDecimal = posixDecimal(priorPrice.value),
              let afterDecimal = posixDecimal(price.value),
              beforeDecimal != 0
        else { return .unavailable }

        let decimalMove = (afterDecimal - beforeDecimal) / beforeDecimal
        let absoluteDecimalMove = decimalMove < 0 ? -decimalMove : decimalMove
        guard absoluteDecimalMove >= threshold else { return .belowThreshold }

        return .triggered(BigMoverSignal(
            beforeDecimal: beforeDecimal,
            afterDecimal: afterDecimal,
            absoluteDecimalMove: absoluteDecimalMove,
            moveSize: rounded(Double(truncating: decimalMove as NSDecimalNumber), places: 4),
            currency: price.currency,
            windowStart: priorSnapshot.asOf,
            windowEnd: currentAsOf
        ))
    }

    private static func bigMoverSignals(from priceSeries: [PricePoint]) -> [Int: BigMoverSignal] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: priceSeries, by: \.quoteId)
                .compactMap { quoteId, points -> (Int, BigMoverSignal)? in
                    guard let signal = bigMoverSignal(points: points) else {
                        return nil
                    }
                    return (quoteId, signal)
                }
        )
    }

    private static func bigMoverSignal(points: [PricePoint]) -> BigMoverSignal? {
        guard points.count >= 2 else { return nil }
        let datedPoints: [(point: PricePoint, date: Date, close: Decimal)] = points.compactMap { point in
            guard let date = dayDate(from: point.date),
                  let close = posixDecimal(point.closeAdjusted),
                  close > 0
            else {
                return nil
            }
            return (point, date, close)
        }
        guard datedPoints.count == points.count else { return nil }

        let sorted = datedPoints.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.close < $1.close
        }
        guard let first = sorted.first,
              let last = sorted.last,
              first.date < last.date
        else {
            return nil
        }

        let change = (last.close - first.close) / first.close
        let absoluteChange = change < 0 ? -change : change
        return BigMoverSignal(
            beforeDecimal: first.close,
            afterDecimal: last.close,
            absoluteDecimalMove: absoluteChange,
            moveSize: rounded(Double(truncating: change as NSDecimalNumber), places: 4),
            currency: last.point.closeCurrency ?? first.point.closeCurrency,
            windowStart: first.point.date,
            windowEnd: last.point.date
        )
    }

    private static func bigMoverItem(
        holding: NormalizedHolding,
        signal: BigMoverSignal,
        beforeWeight: Double?,
        sourceSlotIDs: [String]
    ) -> AttentionItem? {
        let currency = signal.currency ?? holding.price?.currency ?? holding.worth.currency
        let beforeValue = Double(truncating: signal.beforeDecimal as NSDecimalNumber)
        let afterValue = Double(truncating: signal.afterDecimal as NSDecimalNumber)
        let score = rounded(min(1.0, abs(signal.moveSize) / 0.20), places: 2)
        let valueCopy = "from \(currency) \(decimalString(String(beforeValue), places: 2)) to \(currency) \(decimalString(String(afterValue), places: 2))"
        let detailSuffix = beforeWeight.map {
            " while portfolio weight changed \(percent($0)) -> \(percent(holding.weight))."
        } ?? " over price history window."
        return AttentionItem(
            id: "bigMovers.move.\(holding.quoteId)",
            facet: "bigMovers",
            rank: 0,
            title: "\(holding.name) moved \(signedPercent(signal.moveSize))",
            detail: "\(holding.name) moved \(signedPercent(signal.moveSize)) \(valueCopy)\(detailSuffix)",
            severity: abs(signal.moveSize) >= 0.20 ? "high" : "medium",
            score: score,
            holdingIdentity: HoldingIdentity(name: holding.name, quoteId: holding.quoteId),
            beforeValue: beforeValue,
            afterValue: afterValue,
            moveSize: signal.moveSize,
            beforeWeight: beforeWeight,
            afterWeight: holding.weight,
            valueCurrency: currency,
            windowStart: signal.windowStart,
            windowEnd: signal.windowEnd,
            supportingDataSlotIDs: sourceSlotIDs,
            explanation: AttentionExplanation(
                trigger: AttentionExplanationFact(
                    key: "trigger",
                    label: "Trigger",
                    value: "Price move crossed recent-window line"
                ),
                severity: explanationSeverity(
                    severity: abs(signal.moveSize) >= 0.20 ? "high" : "medium",
                    score: score
                ),
                threshold: AttentionExplanationFact(
                    key: "threshold",
                    label: "Threshold",
                    value: percent(bigMoverThreshold),
                    numericValue: bigMoverThreshold,
                    unit: "fraction"
                ),
                currentValue: AttentionExplanationFact(
                    key: "currentValue",
                    label: "Current",
                    value: "\(currency) \(decimalString(String(afterValue), places: 2))",
                    numericValue: afterValue,
                    unit: currency
                ),
                priorValue: AttentionExplanationFact(
                    key: "priorValue",
                    label: "Prior",
                    value: "\(currency) \(decimalString(String(beforeValue), places: 2))",
                    numericValue: beforeValue,
                    unit: currency
                ),
                supportingSourceSlots: explanationSourceSlots(sourceSlotIDs)
            )
        )
    }

    private static func incomeItems(from snapshot: PortfolioSnapshot) -> [AttentionItem] {
        let incomeWindowEnd = dayString(daysFrom: snapshot.asOf, days: 30) ?? snapshot.asOf
        guard let incomeWindowStartDate = dayDate(from: snapshot.asOf),
              let incomeWindowEndDate = dayDate(from: incomeWindowEnd)
        else {
            return []
        }
        return snapshot.incomeEvents
            .filter { $0.kind == "ex-dividend" && !$0.estimated }
            .filter { event in
                guard let eventDate = dayDate(from: event.date) else {
                    return false
                }
                return eventDate >= incomeWindowStartDate && eventDate <= incomeWindowEndDate
            }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { offset, event in
                let identity = event.quoteId.map {
                    HoldingIdentity(name: event.symbolName, quoteId: $0)
                }
                return AttentionItem(
                    id: incomeItemID(for: event),
                    facet: "income",
                    rank: offset + 1,
                    title: "\(event.symbolName) ex-dividend",
                    detail: incomeCopy(for: event),
                    severity: "low",
                    score: 0.45,
                    holdingIdentity: identity,
                    eventDate: event.date,
                    amount: event.amount,
                    changePercent: event.priorAmount == nil ? nil : event.changePercent,
                    windowStart: snapshot.asOf,
                    windowEnd: incomeWindowEnd,
                    supportingDataSlotIDs: ["income.calendar"],
                    explanation: AttentionExplanation(
                        trigger: AttentionExplanationFact(
                            key: "trigger",
                            label: "Trigger",
                            value: "Ex-dividend date in income window"
                        ),
                        severity: explanationSeverity(severity: .low, score: 0.45),
                        threshold: AttentionExplanationFact(
                            key: "threshold",
                            label: "Threshold",
                            value: "\(snapshot.asOf)..\(incomeWindowEnd)"
                        ),
                        currentValue: AttentionExplanationFact(
                            key: "currentValue",
                            label: "Current",
                            value: event.date
                        ),
                        priorValue: event.priorAmount.map {
                            AttentionExplanationFact(
                                key: "priorValue",
                                label: "Prior",
                                value: display($0)
                            )
                        },
                        supportingSourceSlots: explanationSourceSlots(["income.calendar"])
                    )
                )
            }
    }

    private static func incomeItemID(for event: IncomeEventSummary) -> String {
        if let quoteId = event.quoteId {
            return "income.ex-dividend.\(quoteId)"
        }
        if let symbolId = event.symbolId {
            return "income.ex-dividend.symbol.\(symbolId)"
        }
        return "income.ex-dividend.\(event.symbolName)"
    }

    private static func incomeCopy(for event: IncomeEventSummary) -> String {
        let base = "\(event.symbolName) has an ex-dividend date on \(event.date)"
        guard let amount = event.amount else {
            return "\(base)."
        }
        guard let changePercent = event.changePercent,
              let priorAmount = event.priorAmount
        else {
            return "\(base); latest recorded dividend \(display(amount))."
        }

        let direction = changePercent >= 0 ? "up" : "down"
        return "\(base); latest recorded dividend \(display(amount)), \(direction) \(percent(abs(changePercent))) from prior \(display(priorAmount))."
    }

    private static func explanationSeverity(severity: AttentionSeverity, score: Double) -> AttentionExplanationFact {
        AttentionExplanationFact(
            key: "severity",
            label: "Severity",
            value: severity.rawValue,
            numericValue: score
        )
    }

    private static func explanationSourceSlots(_ ids: [String]) -> [AttentionExplanationSourceSlot] {
        ids.map {
            AttentionExplanationSourceSlot(id: $0, label: explanationSourceLabel(for: $0))
        }
    }

    private static func explanationSourceLabel(for id: String) -> String? {
        switch id {
        case "allocation.overview":
            return "Portfolio overview"
        case "allocation.holdings":
            return "Open holdings"
        case "allocation.sectors":
            return "Sector breakdown"
        case "allocation.priorSnapshot":
            return "Prior allocation snapshot"
        case "income.calendar":
            return "Calendar events"
        case "bigMovers.priorSnapshot":
            return "Prior snapshot"
        case "bigMovers.prices":
            return "Price rows"
        default:
            return nil
        }
    }

    private static func dayString(daysFrom value: String, days: Int) -> String? {
        guard let date = dayDate(from: value),
              let result = dateCalendar.date(byAdding: .day, value: days, to: date)
        else {
            return nil
        }
        let components = dateCalendar.dateComponents([.year, .month, .day], from: result)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func concentrationScore(weight: Double, threshold: Double) -> Double {
        let relativeExcess = (weight - threshold) / threshold
        return rounded(min(1.0, 0.5 + (relativeExcess * 0.75)), places: 2)
    }

    private static func maxMove(from prices: [PricePoint]) -> PriceMoveSummary? {
        let grouped = Dictionary(grouping: prices, by: \.quoteId)
        return grouped.compactMap { quoteId, points -> PriceMoveSummary? in
            let sorted = points.sorted { $0.date < $1.date }
            guard let first = sorted.first,
                  let last = sorted.last,
                  let firstClose = Decimal(string: first.closeAdjusted),
                  let lastClose = Decimal(string: last.closeAdjusted),
                  firstClose != 0
            else { return nil }

            let change = (lastClose - firstClose) / firstClose
            return PriceMoveSummary(
                quoteId: quoteId,
                fromDate: first.date,
                toDate: last.date,
                percentChange: rounded(Double(truncating: change as NSDecimalNumber), places: 4)
            )
        }
        .max { abs($0.percentChange) < abs($1.percentChange) }
    }

    private static func recentMoves(from prices: [PricePoint]) -> [Int: PriceMoveSummary] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: prices, by: \.quoteId)
                .compactMap { quoteId, points -> (Int, PriceMoveSummary)? in
                    guard let summary = recentMove(quoteId: quoteId, points: points) else {
                        return nil
                    }
                    return (quoteId, summary)
                }
        )
    }

    private static func recentMove(quoteId: Int, points: [PricePoint]) -> PriceMoveSummary? {
        guard points.count >= 2 else { return nil }
        let datedPoints: [(point: PricePoint, date: Date, close: Decimal)] = points.compactMap { point in
            guard let date = dayDate(from: point.date),
                  let close = posixDecimal(point.closeAdjusted),
                  close > 0
            else {
                return nil
            }
            return (point, date, close)
        }
        guard datedPoints.count == points.count else { return nil }

        let sorted = datedPoints.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.point.closeAdjusted < $1.point.closeAdjusted
        }
        guard let first = sorted.first,
              let last = sorted.last,
              first.date < last.date
        else {
            return nil
        }

        let change = (last.close - first.close) / first.close
        return PriceMoveSummary(
            quoteId: quoteId,
            fromDate: first.point.date,
            toDate: last.point.date,
            percentChange: rounded(Double(truncating: change as NSDecimalNumber), places: 4)
        )
    }
}
