import Foundation

public struct AllocationAttentionData: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var portfolioWeightFraction: Decimal
    public var thresholdFraction: Decimal

    public init(ticker: String, name: String?, portfolioWeightFraction: Decimal, thresholdFraction: Decimal) {
        self.ticker = ticker
        self.name = name
        self.portfolioWeightFraction = portfolioWeightFraction
        self.thresholdFraction = thresholdFraction
    }
}

public struct AllocationSnapshot: Equatable, Sendable {
    public var state: FacetPressureState
    public var concentrationThresholdFraction: Decimal
    public var holdings: [AllocationHoldingSnapshot]

    public init(
        state: FacetPressureState,
        concentrationThresholdFraction: Decimal,
        holdings: [AllocationHoldingSnapshot]
    ) {
        self.state = state
        self.concentrationThresholdFraction = concentrationThresholdFraction
        self.holdings = holdings
    }
}

public struct AllocationHoldingSnapshot: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var portfolioWeightFraction: Decimal
    public var isConcentrationPressure: Bool

    public init(ticker: String, name: String?, portfolioWeightFraction: Decimal, isConcentrationPressure: Bool) {
        self.ticker = ticker
        self.name = name
        self.portfolioWeightFraction = portfolioWeightFraction
        self.isConcentrationPressure = isConcentrationPressure
    }
}

public struct AllocationFacet: Sendable {
    public var concentrationThresholdFraction: Decimal

    public init(concentrationThresholdFraction: Decimal = Decimal(20) / Decimal(100)) {
        self.concentrationThresholdFraction = concentrationThresholdFraction
    }

    public func model(from facts: PortfolioFacts) -> PulseModel {
        let snapshotHoldings = facts.liveHoldings.map { holding in
            AllocationHoldingSnapshot(
                ticker: holding.ticker,
                name: holding.name,
                portfolioWeightFraction: holding.portfolioWeightFraction,
                isConcentrationPressure: isConcentrationPressure(holding)
            )
        }

        let pressureHoldings = facts.liveHoldings
            .filter(isConcentrationPressure)
            .sorted(by: ranksBefore)

        let items = pressureHoldings.map { holding in
            AttentionItem(
                title: "\(holding.ticker) concentration",
                detail: "\(percentText(holding.portfolioWeightFraction)) of portfolio; threshold \(percentText(concentrationThresholdFraction))",
                facet: .allocation,
                severity: .pressure,
                allocation: AllocationAttentionData(
                    ticker: holding.ticker,
                    name: holding.name,
                    portfolioWeightFraction: holding.portfolioWeightFraction,
                    thresholdFraction: concentrationThresholdFraction
                )
            )
        }

        return PulseModel(
            statusSignal: "Pulse",
            attentionItems: items,
            allocationSnapshot: AllocationSnapshot(
                state: items.isEmpty ? .allQuiet : .activePressure,
                concentrationThresholdFraction: concentrationThresholdFraction,
                holdings: snapshotHoldings
            )
        )
    }

    private func isConcentrationPressure(_ holding: PortfolioHoldingFact) -> Bool {
        holding.portfolioWeightFraction >= concentrationThresholdFraction
    }

    private func ranksBefore(_ lhs: PortfolioHoldingFact, _ rhs: PortfolioHoldingFact) -> Bool {
        if lhs.portfolioWeightFraction != rhs.portfolioWeightFraction {
            return lhs.portfolioWeightFraction > rhs.portfolioWeightFraction
        }

        let lhsTicker = lhs.ticker.uppercased()
        let rhsTicker = rhs.ticker.uppercased()
        if lhsTicker != rhsTicker {
            return lhsTicker < rhsTicker
        }

        return (lhs.name ?? "") < (rhs.name ?? "")
    }

    private func percentText(_ fraction: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: fraction * Decimal(100)).doubleValue
        if percent.rounded() == percent {
            return "\(Int(percent))%"
        }

        return String(format: "%.1f%%", percent)
    }
}
