import CoreGraphics

public struct PortfolioSummaryGridLayout: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case columns
        case stacked
    }

    public static let minimumColumnWidth: CGFloat = 110
    public static let horizontalPadding: CGFloat = 14
    public static let columnGap: CGFloat = 12

    public var width: CGFloat
    public var textScale: CGFloat

    public init(width: CGFloat, textScale: CGFloat = 1) {
        self.width = width
        self.textScale = max(1, textScale)
    }

    public var mode: Mode {
        let contentWidth = width - Self.horizontalPadding * 2 - Self.columnGap
        return contentWidth / 2 >= Self.minimumColumnWidth * textScale ? .columns : .stacked
    }

    public var rowHeight: CGFloat {
        mode == .columns ? 86 * textScale : 126 * textScale
    }
}
