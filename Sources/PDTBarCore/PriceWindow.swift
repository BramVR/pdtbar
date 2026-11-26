import Foundation

struct PriceWindow {
    struct Close {
        let point: PricePoint
        let day: Date
        let value: Decimal
    }

    let first: Close
    let last: Close

    static func byQuote(_ prices: [PricePoint]) -> [Int: PriceWindow] {
        Dictionary(grouping: prices, by: \.quoteId).compactMapValues { PriceWindow(points: $0) }
    }

    private init?(points: [PricePoint]) {
        var closes: [Close] = []
        for point in points {
            guard let day = PressureEngine.dayDate(from: point.date),
                  let value = posixDecimal(point.closeAdjusted),
                  value > 0
            else { return nil }
            closes.append(Close(point: point, day: day, value: value))
        }
        let ordersBefore: (Close, Close) -> Bool = { ($0.day, $0.value) < ($1.day, $1.value) }
        guard let first = closes.min(by: ordersBefore),
              let last = closes.max(by: ordersBefore),
              first.day < last.day
        else { return nil }
        self.first = first
        self.last = last
    }

    var change: Decimal {
        (last.value - first.value) / first.value
    }

    var roundedChange: Double {
        rounded(Double(truncating: change as NSDecimalNumber), places: 4)
    }

    var summary: PriceMoveSummary {
        PriceMoveSummary(
            quoteId: last.point.quoteId,
            fromDate: first.point.date,
            toDate: last.point.date,
            percentChange: roundedChange
        )
    }
}
