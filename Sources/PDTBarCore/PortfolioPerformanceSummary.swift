import Foundation

public struct PortfolioPerformanceSummary: Codable, Equatable, Sendable {
    public var totalPercentageIncrease: Double?
    public var cagr: Double?
    public var periodStart: String?
    public var periodEnd: String?

    public init(
        totalPercentageIncrease: Double? = nil,
        cagr: Double? = nil,
        periodStart: String? = nil,
        periodEnd: String? = nil
    ) {
        self.totalPercentageIncrease = performanceFinite(totalPercentageIncrease)
        self.cagr = performanceFinite(cagr)
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    /// PDT supplies the selected-method total return directly. Its current MCP
    /// schema does not establish a compatible return basis for deriving CAGR,
    /// so CAGR remains unavailable.
    public static func build(
        totalGainPercentage: Double?,
        periodStart: String?,
        periodEnd: String?
    ) -> PortfolioPerformanceSummary {
        return PortfolioPerformanceSummary(
            totalPercentageIncrease: performanceFinite(totalGainPercentage),
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
}

private func performanceFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}
