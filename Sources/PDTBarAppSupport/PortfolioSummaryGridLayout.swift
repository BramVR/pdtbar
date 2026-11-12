import CoreGraphics

public struct PortfolioSummaryGridLayout: Equatable, Sendable {
    public static let horizontalPadding: CGFloat = 14
    public static let columnGap: CGFloat = 12
    public static let baseSystemFontSize: CGFloat = 13

    public var width: CGFloat
    public var systemFontSize: CGFloat

    /// Return figures PDT supplied: 0 shows the total alone, 1 lets the lone figure span the row.
    public var performanceColumns: Int

    public init(width: CGFloat, systemFontSize: CGFloat = Self.baseSystemFontSize, performanceColumns: Int = 2) {
        self.width = width
        self.systemFontSize = max(Self.baseSystemFontSize, systemFontSize)
        self.performanceColumns = performanceColumns
    }

    public var columnWidth: CGFloat {
        let content = width - Self.horizontalPadding * 2
        guard performanceColumns > 1 else { return max(0, content) }
        return max(0, (content - Self.columnGap) / 2)
    }

    public var rowHeight: CGFloat {
        (performanceColumns > 0 ? 86 : 46) * systemFontSize / Self.baseSystemFontSize
    }
}
