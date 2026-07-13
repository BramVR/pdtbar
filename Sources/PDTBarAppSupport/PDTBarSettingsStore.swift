import Combine
import Foundation
import PDTBarCore

@MainActor
public final class PDTBarSettingsStore: ObservableObject {
    public nonisolated static let showPortfolioValuesKey = "showPortfolioValues"
    public nonisolated static let userDefaultsSuiteEnvironmentKey = "PDTBAR_USER_DEFAULTS_SUITE"

    private let userDefaults: UserDefaults

    @Published public var showPortfolioValues: Bool {
        didSet {
            userDefaults.set(showPortfolioValues, forKey: Self.showPortfolioValuesKey)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.showPortfolioValues = userDefaults.object(forKey: Self.showPortfolioValuesKey) as? Bool ?? true
    }

    public nonisolated static func userDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        guard let suite = environment[userDefaultsSuiteEnvironmentKey],
              !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let defaults = UserDefaults(suiteName: suite)
        else {
            return .standard
        }
        return defaults
    }

    public var displaySettings: PortfolioValueDisplaySettings {
        PortfolioValueDisplaySettings(showPortfolioValues: showPortfolioValues)
    }
}
