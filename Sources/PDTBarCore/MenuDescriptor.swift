import Foundation

public struct StatusVisualState: Codable, Equatable {
    public static let defaultBarHeights = [0.5, 1.0, 0.667]

    public var barHeights: [Double]
    public var filledBarCount: Int
    public var isDimmed: Bool
    public var statusCopy: String

    public init(
        barHeights: [Double] = StatusVisualState.defaultBarHeights,
        filledBarCount: Int = 0,
        isDimmed: Bool = false,
        statusCopy: String = ""
    ) {
        self.barHeights = Array(barHeights.prefix(3))
        while self.barHeights.count < 3 {
            self.barHeights.append(StatusVisualState.defaultBarHeights[self.barHeights.count])
        }
        if self.barHeights.count > 1 {
            self.barHeights[1] = 1.0
        }
        self.filledBarCount = max(0, min(3, filledBarCount))
        self.isDimmed = isDimmed
        self.statusCopy = statusCopy
    }

    enum CodingKeys: String, CodingKey {
        case barHeights
        case filledBarCount
        case isDimmed
        case statusCopy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            barHeights: try container.decodeIfPresent([Double].self, forKey: .barHeights)
                ?? StatusVisualState.defaultBarHeights,
            filledBarCount: try container.decodeIfPresent(Int.self, forKey: .filledBarCount) ?? 0,
            isDimmed: try container.decodeIfPresent(Bool.self, forKey: .isDimmed) ?? false,
            statusCopy: try container.decodeIfPresent(String.self, forKey: .statusCopy) ?? ""
        )
    }

    public func withDimming(_ isDimmed: Bool) -> StatusVisualState {
        StatusVisualState(
            barHeights: barHeights,
            filledBarCount: filledBarCount,
            isDimmed: isDimmed,
            statusCopy: statusCopy
        )
    }

    public func withStatusCopy(_ statusCopy: String) -> StatusVisualState {
        StatusVisualState(
            barHeights: barHeights,
            filledBarCount: filledBarCount,
            isDimmed: isDimmed,
            statusCopy: statusCopy
        )
    }
}

enum PortfolioValueProtectionState: Equatable {
    case complete
    case hidden
}

public struct MenuDescriptor: Codable, Equatable {
    public var statusTitle: String
    public var statusBadge: String?
    public var statusVisual: StatusVisualState
    public var statusAccessibilityIdentifier: String
    public var sections: [MenuSection] {
        didSet {
            portfolioValueProtectionState = nil
        }
    }
    var portfolioValueProtectionState: PortfolioValueProtectionState?

    public init(
        statusTitle: String,
        statusBadge: String? = nil,
        statusVisual: StatusVisualState = StatusVisualState(),
        statusAccessibilityIdentifier: String = "pdtbar.status",
        sections: [MenuSection]
    ) {
        self.statusTitle = statusTitle
        self.statusBadge = statusBadge
        var visual = statusVisual
        if visual.statusCopy.isEmpty {
            visual.statusCopy = statusBadge.map { "\(statusTitle) [\($0)]" } ?? statusTitle
        }
        self.statusVisual = visual
        self.statusAccessibilityIdentifier = statusAccessibilityIdentifier
        self.sections = sections
        self.portfolioValueProtectionState = nil
    }

    enum CodingKeys: String, CodingKey {
        case statusTitle
        case statusBadge
        case statusVisual
        case statusAccessibilityIdentifier
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusTitle = try container.decode(String.self, forKey: .statusTitle)
        statusBadge = try container.decodeIfPresent(String.self, forKey: .statusBadge)
        statusVisual = try container.decodeIfPresent(StatusVisualState.self, forKey: .statusVisual)
            ?? StatusVisualState()
        statusAccessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .statusAccessibilityIdentifier)
            ?? "pdtbar.status"
        sections = try container.decode([MenuSection].self, forKey: .sections)
        portfolioValueProtectionState = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusTitle, forKey: .statusTitle)
        if let statusBadge {
            try container.encode(statusBadge, forKey: .statusBadge)
        } else {
            try container.encodeNil(forKey: .statusBadge)
        }
        try container.encode(statusVisual, forKey: .statusVisual)
        try container.encode(statusAccessibilityIdentifier, forKey: .statusAccessibilityIdentifier)
        try container.encode(sections, forKey: .sections)
    }
}

public struct MenuSection: Codable, Equatable {
    public var id: String
    public var title: String
    public var accessibilityIdentifier: String
    public var rows: [MenuRow]

    public init(id: String, title: String, accessibilityIdentifier: String? = nil, rows: [MenuRow]) {
        self.id = id
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier ?? "pdtbar.section.\(id)"
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case accessibilityIdentifier
        case rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        accessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .accessibilityIdentifier)
            ?? "pdtbar.section.\(id)"
        rows = try container.decode([MenuRow].self, forKey: .rows)
    }
}

public enum MenuRowRole: String, Codable, Equatable {
    case row
    case setupProbe
    case setupStatus
    case setupLogin
    case setupRetry
    case setupFailure
    case fetchStatus
    case fetchRetry
    case pulseSummary
    case pulseQuiet
    case pulseAttention
    case pulseAttentionExpansion
    case pulseMarkRead
    case portfolioSummary
    case portfolioOverview
    case portfolioOverviewChart
    case portfolioOverviewDetails
    case portfolioOverviewHoldings
    case portfolioOverviewConcentration
    case portfolioOverviewSector
    case portfolioOverviewAssetType
    case portfolioOverviewCash
    case allocationHolding
    case allocationDrillDown
    case incomeEmpty
    case incomeSummary
    case incomeNext
    case incomeEvent
    case incomeEventDate
    case incomeEventKind
    case incomeEventState
    case incomeEventAmount
    case incomeEventChange
    case incomeDrillDown
    case bigMoverSummary
    case freshnessSummary
    case freshnessStaleCount
    case freshnessOldestPrice
    case freshnessOldestRows
    case freshnessOldestHolding
    case freshnessDetailFill
    case freshnessCaveats
    case dataHealthSummary
    case dataHealthSource
    case dataHealthCache
    case dataHealthDetailFill
    case dataHealthReadState
    case dataHealthDiagnostic
    case dataHealthDiagnosticCopy
    case holdingIdentifierCopy
    case openPDT
    case settings

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let role = MenuRowRole(rawValue: value) {
            self = role
            return
        }
        switch value {
        case "glance":
            self = .pulseAttention
        case "expansion":
            self = .pulseAttentionExpansion
        default:
            self = .row
        }
    }
}

public enum MenuRowActionTargetKind: String, Codable, Equatable {
    case incomeEvent
    case copyHoldingIdentifier
    case copyDataHealthDiagnostic
}

public struct IncomeEventActionTarget: Codable, Equatable {
    public var eventID: String
    public var rowID: String
    public var date: String
    public var kind: String
    public var symbolName: String
    public var estimated: Bool
    public var symbolId: Int?
    public var quoteId: Int?

    public init(
        eventID: String,
        rowID: String,
        date: String,
        kind: String,
        symbolName: String,
        estimated: Bool,
        symbolId: Int? = nil,
        quoteId: Int? = nil
    ) {
        self.eventID = eventID
        self.rowID = rowID
        self.date = date
        self.kind = kind
        self.symbolName = symbolName
        self.estimated = estimated
        self.symbolId = symbolId
        self.quoteId = quoteId
    }
}

public struct MenuRowActionTarget: Codable, Equatable {
    public var kind: MenuRowActionTargetKind
    public var id: String
    public var incomeEvent: IncomeEventActionTarget?
    public var copyText: String?

    public init(
        kind: MenuRowActionTargetKind,
        id: String,
        incomeEvent: IncomeEventActionTarget? = nil,
        copyText: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.incomeEvent = incomeEvent
        self.copyText = copyText
    }
}

public struct MenuRowBarChart: Codable, Equatable {
    public var bars: [Bar]

    public init(bars: [Bar]) {
        self.bars = bars
    }

    public struct Bar: Codable, Equatable {
        public var id: String
        public var label: String
        public var axisLabel: String?
        public var weight: Double
        public var percentageLabel: String
        public var detail: String

        public init(
            id: String,
            label: String,
            axisLabel: String? = nil,
            weight: Double,
            percentageLabel: String,
            detail: String
        ) {
            self.id = id
            self.label = label
            self.axisLabel = axisLabel
            self.weight = weight
            self.percentageLabel = percentageLabel
            self.detail = detail
        }
    }
}

public struct MenuRowPortfolioSummary: Codable, Equatable {
    public var totalValue: String
    public var cagr: String
    public var totalIncrease: String

    public init(totalValue: String, cagr: String, totalIncrease: String) {
        self.totalValue = totalValue
        self.cagr = cagr
        self.totalIncrease = totalIncrease
    }

    public var accessibilityLabel: String {
        "Total portfolio value, \(totalValue); CAGR, \(cagr); Total increase, \(totalIncrease)"
    }
}

public struct PortfolioValueDisplaySettings: Codable, Equatable, Sendable {
    public static let hiddenPlaceholder = "######"

    public var showPortfolioValues: Bool

    public init(showPortfolioValues: Bool = true) {
        self.showPortfolioValues = showPortfolioValues
    }
}

struct PortfolioValueText: Codable, Equatable {
    enum Component: Codable, Equatable {
        case literal(String)
        case money(Money)
        case unresolvedSensitive(String)
    }

    var components: [Component]

    init(_ components: [Component]) {
        self.components = components
    }

    static func money(_ money: Money) -> PortfolioValueText {
        PortfolioValueText([.money(money)])
    }

    func rendered(settings: PortfolioValueDisplaySettings) -> String {
        components.map { component in
            switch component {
            case .literal(let value):
                return value
            case .money(let money):
                return display(money, settings: settings)
            case .unresolvedSensitive(let value):
                return settings.showPortfolioValues
                    ? value
                    : PortfolioValueDisplaySettings.hiddenPlaceholder
            }
        }.joined()
    }
}

public struct MenuRow: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var accessibilityIdentifier: String
    public var actionTarget: MenuRowActionTarget?
    public var title: String
    public var detail: String?
    public var barChart: MenuRowBarChart?
    public var portfolioSummary: MenuRowPortfolioSummary?
    public var actionPayload: String?
    public var children: [MenuRow]
    var portfolioValueDetail: PortfolioValueText?
    var portfolioValueBarDetails: [PortfolioValueText]?
    var portfolioValueSummaryTotal: Money?

    public init(
        id: String = "",
        role: MenuRowRole = .row,
        accessibilityIdentifier: String? = nil,
        actionTarget: MenuRowActionTarget? = nil,
        title: String,
        detail: String? = nil,
        barChart: MenuRowBarChart? = nil,
        portfolioSummary: MenuRowPortfolioSummary? = nil,
        actionPayload: String? = nil,
        children: [MenuRow] = []
    ) {
        self.id = id
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier ?? Self.defaultAccessibilityIdentifier(for: id)
        self.actionTarget = actionTarget
        self.title = title
        self.detail = detail
        self.barChart = barChart
        self.portfolioSummary = portfolioSummary
        self.actionPayload = actionPayload
        self.children = children
        self.portfolioValueDetail = nil
        self.portfolioValueBarDetails = nil
        self.portfolioValueSummaryTotal = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case accessibilityIdentifier
        case actionTarget
        case title
        case detail
        case barChart
        case portfolioSummary
        case actionPayload
        case children
        case portfolioValueDetail
        case portfolioValueBarDetails
        case portfolioValueSummaryTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let decodedRole = try container.decodeIfPresent(MenuRowRole.self, forKey: .role) ?? .row
        role = id == "quiet" && decodedRole == .pulseAttention ? .pulseQuiet : decodedRole
        accessibilityIdentifier = try container.decodeIfPresent(String.self, forKey: .accessibilityIdentifier)
            ?? Self.defaultAccessibilityIdentifier(for: id)
        actionTarget = try container.decodeIfPresent(MenuRowActionTarget.self, forKey: .actionTarget)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        barChart = try container.decodeIfPresent(MenuRowBarChart.self, forKey: .barChart)
        portfolioSummary = try container.decodeIfPresent(MenuRowPortfolioSummary.self, forKey: .portfolioSummary)
        actionPayload = try container.decodeIfPresent(String.self, forKey: .actionPayload)
        children = try container.decodeIfPresent([MenuRow].self, forKey: .children) ?? []
        portfolioValueDetail = try container.decodeIfPresent(
            PortfolioValueText.self,
            forKey: .portfolioValueDetail
        )
        portfolioValueBarDetails = try container.decodeIfPresent(
            [PortfolioValueText].self,
            forKey: .portfolioValueBarDetails
        )
        portfolioValueSummaryTotal = try container.decodeIfPresent(
            Money.self,
            forKey: .portfolioValueSummaryTotal
        )
    }

    private static func defaultAccessibilityIdentifier(for id: String) -> String {
        id.isEmpty ? "" : "pdtbar.row.\(id)"
    }
}

public struct MenuBarSurface: Codable, Equatable {
    public var status: MenuBarStatusSurface
    public var sections: [MenuBarSectionSurface]

    public init(status: MenuBarStatusSurface, sections: [MenuBarSectionSurface]) {
        self.status = status
        self.sections = sections
    }
}

public struct MenuBarStatusSurface: Codable, Equatable {
    public var title: String
    public var badge: String?
    public var menuBarTitle: String
    public var visual: StatusVisualState
    public var accessibilityIdentifier: String
    public var accessibilityLabel: String
    public var toolTip: String

    public init(
        title: String,
        badge: String?,
        menuBarTitle: String,
        visual: StatusVisualState,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        toolTip: String
    ) {
        self.title = title
        self.badge = badge
        self.menuBarTitle = menuBarTitle
        self.visual = visual
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.toolTip = toolTip
    }
}

public struct MenuBarSectionSurface: Codable, Equatable {
    public var id: String
    public var title: String
    public var accessibilityIdentifier: String
    public var rows: [MenuBarRowSurface]

    public init(id: String, title: String, accessibilityIdentifier: String, rows: [MenuBarRowSurface]) {
        self.id = id
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.rows = rows
    }
}

public struct MenuBarRowSurface: Codable, Equatable {
    public var id: String
    public var role: MenuRowRole
    public var title: String
    public var detail: String?
    public var accessibilityIdentifier: String
    public var actionTarget: MenuRowActionTarget?
    public var barChart: MenuRowBarChart?
    public var portfolioSummary: MenuRowPortfolioSummary?
    public var actionPayload: String?
    public var children: [MenuBarRowSurface]

    public init(
        id: String,
        role: MenuRowRole,
        title: String,
        detail: String? = nil,
        accessibilityIdentifier: String,
        actionTarget: MenuRowActionTarget? = nil,
        barChart: MenuRowBarChart? = nil,
        portfolioSummary: MenuRowPortfolioSummary? = nil,
        actionPayload: String? = nil,
        children: [MenuBarRowSurface] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.detail = detail
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actionTarget = actionTarget
        self.barChart = barChart
        self.portfolioSummary = portfolioSummary
        self.actionPayload = actionPayload
        self.children = children
    }
}
