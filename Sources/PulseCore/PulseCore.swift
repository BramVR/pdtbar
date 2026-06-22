import Foundation

public struct PulseModel: Equatable, Sendable {
    public var statusSignal: String
    public var attentionItems: [AttentionItem]
    public var allocationSnapshot: AllocationSnapshot?

    public init(statusSignal: String, attentionItems: [AttentionItem], allocationSnapshot: AllocationSnapshot? = nil) {
        self.statusSignal = statusSignal
        self.attentionItems = attentionItems
        self.allocationSnapshot = allocationSnapshot
    }
}

public struct AttentionItem: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var facet: Facet
    public var severity: Severity
    public var allocation: AllocationAttentionData?

    public init(
        title: String,
        detail: String,
        facet: Facet,
        severity: Severity,
        allocation: AllocationAttentionData? = nil
    ) {
        self.title = title
        self.detail = detail
        self.facet = facet
        self.severity = severity
        self.allocation = allocation
    }
}

public enum Facet: String, Equatable, Sendable {
    case allocation
    case income
    case performance
    case cash
}

public enum Severity: String, Equatable, Sendable {
    case info
    case pressure
}

public enum FacetPressureState: String, Equatable, Sendable {
    case allQuiet
    case activePressure
}

public struct PulseView: Equatable, Sendable {
    public var status: PulseStatusView
    public var card: PulseCardView
    public var allocationDrillDown: PulseDrillDownView?
}

public struct PulseStatusView: Equatable, Sendable {
    public var title: String
    public var badge: String?
}

public struct PulseCardView: Equatable, Sendable {
    public var title: String
    public var rows: [PulseRowView]
}

public struct PulseRowView: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var facet: Facet
}

public struct PulseDrillDownView: Equatable, Sendable {
    public var title: String
    public var rows: [PulseRowView]
}

public enum PulseRenderer {
    private static let maxGlanceRows = 3

    public static func render(_ model: PulseModel) -> PulseView {
        let rows = model.attentionItems.prefix(maxGlanceRows).map { item in
            PulseRowView(title: item.title, detail: item.detail, facet: item.facet)
        }
        let pressureCount = model.attentionItems.count
        let allocationDrillDown = model.allocationSnapshot.map { snapshot in
            PulseDrillDownView(
                title: "Allocation",
                rows: snapshot.holdings.map { holding in
                    PulseRowView(
                        title: holding.ticker,
                        detail: "\(percentText(holding.portfolioWeightFraction)) of portfolio",
                        facet: .allocation
                    )
                }
            )
        }

        return PulseView(
            status: PulseStatusView(
                title: model.allocationSnapshot == nil ? model.statusSignal : "◌",
                badge: pressureCount > 0 ? "• \(pressureCount)" : nil
            ),
            card: PulseCardView(
                title: cardTitle(pressureCount: pressureCount, allocationState: model.allocationSnapshot?.state),
                rows: rows
            ),
            allocationDrillDown: allocationDrillDown
        )
    }

    private static func cardTitle(pressureCount: Int, allocationState: FacetPressureState?) -> String {
        switch (pressureCount, allocationState) {
        case (0, .some(.allQuiet)):
            return "All quiet · Portfolio"
        case (_, .some(.activePressure)):
            return "Allocation pressure"
        case (0, _):
            return "All quiet"
        default:
            return "\(pressureCount) pressure item\(pressureCount == 1 ? "" : "s")"
        }
    }

    private static func percentText(_ fraction: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: fraction * Decimal(100)).doubleValue
        if percent.rounded() == percent {
            return "\(Int(percent))%"
        }

        return String(format: "%.1f%%", percent)
    }
}

public extension PulseModel {
    static let quietFixture = AllocationFacet().model(
        from: PortfolioFacts(
            baseCurrency: "USD",
            liveHoldings: [
                fixtureHolding(ticker: "KO", name: "The Coca-Cola Company", weight: "0.19"),
                fixtureHolding(ticker: "PEP", name: "PepsiCo, Inc.", weight: "0.08")
            ],
            freshness: []
        )
    )
    static let pressureFixture = AllocationFacet().model(
        from: PortfolioFacts(
            baseCurrency: "USD",
            liveHoldings: [
                fixtureHolding(ticker: "NVDA", name: "NVIDIA Corporation", weight: "0.22"),
                fixtureHolding(ticker: "AAPL", name: "Apple Inc.", weight: "0.18")
            ],
            freshness: []
        )
    )

    private static func fixtureHolding(ticker: String, name: String?, weight: String) -> PortfolioHoldingFact {
        PortfolioHoldingFact(
            ticker: ticker,
            name: name,
            currentWorth: Money(decimal: Decimal(100), currency: "USD"),
            portfolioWeightFraction: Decimal(string: weight)!,
            eodDate: nil
        )
    }
}
