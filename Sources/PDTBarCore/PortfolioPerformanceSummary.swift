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

    var hasInsufficientCAGRPeriod: Bool {
        guard let totalPercentageIncrease = performanceFinite(totalPercentageIncrease),
              totalPercentageIncrease >= -1,
              let elapsedDays = performanceElapsedDays(periodStart: periodStart, periodEnd: periodEnd)
        else {
            return false
        }
        return elapsedDays > 0 && elapsedDays < minimumCAGRElapsedDays
    }
}

private func performanceFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

/// Annualizing less than roughly one quarter amplifies ordinary returns into misleading extremes.
private let minimumCAGRElapsedDays = 90.0

private func performanceCAGR(
    totalGainPercentage: Double?,
    periodStart: String?,
    periodEnd: String?
) -> Double? {
    guard let totalGainPercentage = performanceFinite(totalGainPercentage),
          totalGainPercentage >= -1,
          let elapsedDays = performanceElapsedDays(periodStart: periodStart, periodEnd: periodEnd)
    else {
        return nil
    }
    guard elapsedDays >= minimumCAGRElapsedDays else { return nil }
    let elapsedYears = elapsedDays / 365.25
    return performanceFinite(pow(1 + totalGainPercentage, 1 / elapsedYears) - 1)
}

private func performanceElapsedDays(periodStart: String?, periodEnd: String?) -> Double? {
    guard let start = performanceDate(periodStart),
          let end = performanceDate(periodEnd)
    else {
        return nil
    }
    return end.timeIntervalSince(start) / (24 * 60 * 60)
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
