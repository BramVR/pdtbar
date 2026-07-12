import CoreGraphics

public struct PortfolioSummaryGridLayout: Equatable, Sendable {
    public static let horizontalPadding: CGFloat = 14
    public static let columnGap: CGFloat = 12
    public static let baseSystemFontSize: CGFloat = 13

    public var width: CGFloat
    public var systemFontSize: CGFloat

    public init(width: CGFloat, systemFontSize: CGFloat = Self.baseSystemFontSize) {
        self.width = width
        self.systemFontSize = max(Self.baseSystemFontSize, systemFontSize)
    }

    public var columnWidth: CGFloat {
        max(0, (width - Self.horizontalPadding * 2 - Self.columnGap) / 2)
    }

    public var rowHeight: CGFloat {
        86 * systemFontSize / Self.baseSystemFontSize
    }
}
