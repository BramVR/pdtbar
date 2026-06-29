import AppKit

public struct PortfolioAllocationChartLayout {
    public static let visibleSlotCount = 30
    public static let chartHeight: CGFloat = 114
    public static let minimumPositiveBarHeight: CGFloat = 10
    public static let barCornerRadius: CGFloat = 2

    public var bounds: NSRect
    public var weights: [Double]

    public init(bounds: NSRect, weights: [Double]) {
        self.bounds = bounds
        self.weights = weights
    }

    public static func contentWidth(viewportWidth: CGFloat, barCount: Int) -> CGFloat {
        let visibleWidth = max(viewportWidth, 1)
        let slotCount = max(barCount, Self.visibleSlotCount)
        return visibleWidth * CGFloat(slotCount) / CGFloat(Self.visibleSlotCount)
    }

    public static func totalSlotCount(for barCount: Int) -> Int {
        max(barCount, Self.visibleSlotCount)
    }

    public static func leadingSlotCount(for barCount: Int) -> Int {
        max((Self.visibleSlotCount - barCount) / 2, 0)
    }

    public static func plotRect(in bounds: NSRect) -> NSRect {
        let topInset: CGFloat = 16
        let bottomInset: CGFloat = 6
        return NSRect(
            x: 0,
            y: topInset,
            width: bounds.width,
            height: max(1, bounds.height - topInset - bottomInset)
        )
    }

    public static func clampedWeight(_ weight: Double) -> CGFloat {
        guard weight.isFinite, weight > 0 else { return 0 }
        return CGFloat(min(weight, 1))
    }

    public static func scaleMaxWeight(for weights: [Double]) -> CGFloat {
        max(weights.map(Self.clampedWeight).max() ?? 0, 0.01)
    }

    public static func tickValues(for weights: [Double]) -> [CGFloat] {
        let scaleMax = Self.scaleMaxWeight(for: weights)
        let step = Self.tickStep(for: scaleMax)
        var values: [CGFloat] = []
        var tick: CGFloat = 0
        while tick <= scaleMax + 0.000001 {
            values.append(tick)
            tick += step
        }
        return values
    }

    public static func tickStep(for maxWeight: CGFloat) -> CGFloat {
        switch maxWeight {
        case ...0.05:
            return 0.01
        case ...0.15:
            return 0.05
        case ...0.30:
            return 0.10
        case ...0.60:
            return 0.25
        default:
            return 0.25
        }
    }

    public var plotRect: NSRect {
        Self.plotRect(in: bounds)
    }

    public var totalSlotCount: Int {
        Self.totalSlotCount(for: weights.count)
    }

    public var leadingSlotCount: Int {
        Self.leadingSlotCount(for: weights.count)
    }

    public var slotWidth: CGFloat {
        plotRect.width / CGFloat(totalSlotCount)
    }

    public var scaleMaxWeight: CGFloat {
        Self.scaleMaxWeight(for: weights)
    }

    public func slotCenterX(at index: Int) -> CGFloat {
        plotRect.minX + slotWidth * (CGFloat(leadingSlotCount + index) + 0.5)
    }

    public func labelRect(at index: Int, axisHeight: CGFloat) -> NSRect {
        let centerX = slotCenterX(at: index)
        let labelWidth = max(slotWidth, 10)
        return NSRect(
            x: centerX - labelWidth / 2,
            y: 0,
            width: labelWidth,
            height: axisHeight
        )
    }

    public func barRect(at index: Int) -> NSRect {
        let weight = Self.clampedWeight(weights[index])
        let rawHeight = plotRect.height * weight / scaleMaxWeight
        let barHeight = weight > 0 ? min(plotRect.height, max(Self.minimumPositiveBarHeight, rawHeight)) : 0
        let barWidth = Self.barWidth(slotWidth: slotWidth)
        let centerX = slotCenterX(at: index)
        return NSRect(
            x: centerX - barWidth / 2,
            y: plotRect.maxY - barHeight,
            width: barWidth,
            height: barHeight
        )
    }

    public func index(at location: NSPoint) -> Int? {
        guard bounds.contains(location), !weights.isEmpty else { return nil }
        let plotWidth = max(bounds.width, 1)
        let slotWidth = plotWidth / CGFloat(totalSlotCount)
        let rawSlot = Int(floor(location.x / slotWidth))
        let index = rawSlot - leadingSlotCount
        guard weights.indices.contains(index) else { return nil }
        return index
    }

    private static func barWidth(slotWidth: CGFloat) -> CGFloat {
        slotWidth * 0.5 + 4
    }
}
