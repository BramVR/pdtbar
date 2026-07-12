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

    /// PDT supplies the selected-method total return directly. CAGR is derived
    /// only when the same response period has two valid, increasing dates.
    public static func build(
        totalGainPercentage: Double?,
        periodStart: String?,
        periodEnd: String?
    ) -> PortfolioPerformanceSummary {
        let totalReturn = performanceFinite(totalGainPercentage)
        guard let totalReturn,
              totalReturn >= -1,
              let periodStart,
              let periodEnd,
              let start = dayDate(periodStart),
              let end = dayDate(periodEnd)
        else {
            return PortfolioPerformanceSummary(
                totalPercentageIncrease: totalReturn,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? 0
        guard days > 0 else {
            return PortfolioPerformanceSummary(
                totalPercentageIncrease: totalReturn,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
        let years = Double(days) / 365.2425
        let annualized = pow(1 + totalReturn, 1 / years) - 1
        return PortfolioPerformanceSummary(
            totalPercentageIncrease: totalReturn,
            cagr: annualized,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
}

private func performanceFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

private func dayDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value)
}
