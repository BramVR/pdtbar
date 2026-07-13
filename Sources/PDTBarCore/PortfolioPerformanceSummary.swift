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

    /// PDT documents CAGR as annualizing the selected-method full-period return.
    /// Keep the direct return separate and annualize only a valid explicit period.
    public static func build(
        totalGainPercentage: Double?,
        periodStart: String?,
        periodEnd: String?
    ) -> PortfolioPerformanceSummary {
        return PortfolioPerformanceSummary(
            totalPercentageIncrease: performanceFinite(totalGainPercentage),
            cagr: performanceCAGR(
                totalGainPercentage: totalGainPercentage,
                periodStart: periodStart,
                periodEnd: periodEnd
            ),
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
}

private func performanceFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

private func performanceCAGR(
    totalGainPercentage: Double?,
    periodStart: String?,
    periodEnd: String?
) -> Double? {
    guard let totalGainPercentage = performanceFinite(totalGainPercentage),
          totalGainPercentage >= -1,
          let start = performanceDate(periodStart),
          let end = performanceDate(periodEnd)
    else {
        return nil
    }
    let elapsedYears = end.timeIntervalSince(start) / (365.25 * 24 * 60 * 60)
    guard elapsedYears > 0 else { return nil }
    return performanceFinite(pow(1 + totalGainPercentage, 1 / elapsedYears) - 1)
}

private func performanceDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = dayFormatter()
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
        return nil
    }
    return date
}
