public struct PulseModel: Equatable, Sendable {
    public var statusSignal: String
    public var attentionItems: [AttentionItem]

    public init(statusSignal: String, attentionItems: [AttentionItem]) {
        self.statusSignal = statusSignal
        self.attentionItems = attentionItems
    }
}

public struct AttentionItem: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var facet: Facet
    public var severity: Severity

    public init(title: String, detail: String, facet: Facet, severity: Severity) {
        self.title = title
        self.detail = detail
        self.facet = facet
        self.severity = severity
    }
}

public enum Facet: String, Equatable, Sendable {
    case allocation
    case income
    case performance
    case cash
}

public enum Severity: String, Equatable, Sendable {
    case info
    case pressure
}

public struct PulseView: Equatable, Sendable {
    public var status: PulseStatusView
    public var card: PulseCardView
}

public struct PulseStatusView: Equatable, Sendable {
    public var title: String
    public var badge: String?
}

public struct PulseCardView: Equatable, Sendable {
    public var title: String
    public var rows: [PulseRowView]
}

public struct PulseRowView: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var facet: Facet
}

public enum PulseRenderer {
    public static func render(_ model: PulseModel) -> PulseView {
        let rows = model.attentionItems.map { item in
            PulseRowView(title: item.title, detail: item.detail, facet: item.facet)
        }
        let pressureCount = model.attentionItems.count

        return PulseView(
            status: PulseStatusView(
                title: model.statusSignal,
                badge: pressureCount > 0 ? "• \(pressureCount)" : nil
            ),
            card: PulseCardView(
                title: pressureCount == 0 ? "All quiet" : "\(pressureCount) pressure item\(pressureCount == 1 ? "" : "s")",
                rows: rows
            )
        )
    }
}

public extension PulseModel {
    static let quietFixture = PulseModel(statusSignal: "Pulse", attentionItems: [])
    static let pressureFixture = PulseModel(
        statusSignal: "Pulse",
        attentionItems: [
            AttentionItem(
                title: "NVDA concentration climbing",
                detail: "22% of portfolio; up from 18%",
                facet: .allocation,
                severity: .pressure
            )
        ]
    )
}
