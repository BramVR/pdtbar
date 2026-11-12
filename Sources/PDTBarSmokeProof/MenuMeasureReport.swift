import CryptoKit
import Foundation

/// What `pdtbar-capture measure` keeps of a row's visible text. By default only what the layout
/// metrics need: the length, a salted digest of the primary label, and error flags. The raw text,
/// which can carry portfolio values and holding names, is kept only when the caller opts in.
public struct MeasuredRowText: Codable, Equatable, Sendable {
    public enum Flag: String, Codable, Sendable, CaseIterable {
        case unavailable, failed, error, zeroChecked, unknown, zeroAmount, zeroCount
    }

    public var length: Int
    /// Equal for two rows of one report when their primary labels match. The salt is per report
    /// and never written, so a digest cannot be matched against a guessed holding name.
    public var primaryLabelDigest: String
    public var flags: [Flag]
    public var text: String?

    public init(_ raw: String, salt: Data, includeText: Bool) {
        length = raw.count
        primaryLabelDigest = Self.digest(Self.primaryLabel(raw), salt: salt)
        flags = Self.flags(in: raw)
        text = includeText ? raw : nil
    }

    /// The text before the first comma or ` |`, lowercased: the part two repeated rows share.
    public static func primaryLabel(_ raw: String) -> String {
        let end = [raw.range(of: ","), raw.range(of: " |")].compactMap { $0?.lowerBound }.min() ?? raw.endIndex
        return raw[..<end].trimmingCharacters(in: .whitespaces).lowercased()
    }

    public static func flags(in raw: String) -> [Flag] {
        let lower = raw.lowercased()
        return Flag.allCases.filter { flag in
            switch flag {
            case .unavailable: lower.contains("unavailable")
            case .failed: lower.contains("failed")
            case .error: lower.contains("error")
            case .zeroChecked: lower.range(of: #"\b0 [a-z ]*checked"#, options: .regularExpression) != nil
            case .unknown: lower.contains("unknown")
            case .zeroAmount: raw.range(of: #"\b[A-Z]{3} -?0[.,]00\b"#, options: .regularExpression) != nil
            case .zeroCount: lower.range(of: #"\b0 [a-z]"#, options: .regularExpression) != nil
            }
        }
    }

    static func digest(_ label: String, salt: Data) -> String {
        SHA256.hash(data: salt + Data(label.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

public struct MeasuredRow: Codable, Equatable, Sendable {
    public var role: String
    /// The row's `pdtbar.*` identifier with every digit run masked, so quote ids and dates stay out.
    public var kind: String?
    public var text: MeasuredRowText
    public var y: Int
    public var height: Int
    public var hasSubmenu: Bool
    public var enabled: Bool

    public init(
        role: String, identifier: String?, rawText: String, salt: Data, includeText: Bool,
        y: Int, height: Int, hasSubmenu: Bool, enabled: Bool
    ) {
        self.role = role
        kind = identifier.map { $0.replacingOccurrences(of: #"[0-9]+"#, with: "#", options: .regularExpression) }
        text = MeasuredRowText(rawText, salt: salt, includeText: includeText)
        self.y = y
        self.height = height
        self.hasSubmenu = hasSubmenu
        self.enabled = enabled
    }
}

public struct MeasureReport: Codable, Equatable, Sendable {
    public var fixture: String
    public var menuWidth: Int
    /// Height of the menu window on screen. When macOS clamps a tall menu to the screen and
    /// scrolls it, this is the clamp, not the menu (#296).
    public var menuHeight: Int
    /// Height the rows need: their extent plus the same padding above and below.
    public var contentHeight: Int
    public var clampedToScreen: Bool
    public var sensitiveText: Bool
    public var rows: [MeasuredRow]

    public init(fixture: String, menuWidth: Int, menuHeight: Int, sensitiveText: Bool, rows: [MeasuredRow]) {
        self.fixture = fixture
        self.menuWidth = menuWidth
        self.menuHeight = menuHeight
        let top = rows.map(\.y).min() ?? 0
        contentHeight = (rows.map { $0.y + $0.height }.max() ?? 0) + top
        clampedToScreen = contentHeight > menuHeight
        self.sensitiveText = sensitiveText
        self.rows = rows
    }

    public static func newSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }
}
