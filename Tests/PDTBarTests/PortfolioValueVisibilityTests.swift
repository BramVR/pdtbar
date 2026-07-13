import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Portfolio value visibility")
struct PortfolioValueVisibilityTests {
    @Test("Portfolio values show by default and hide behind one placeholder")
    func portfolioValuesShowByDefaultAndHideBehindOnePlaceholder() throws {
        let model = PressureEngine.buildModel(from: try visibilitySnapshot())
        let shown = MenuDescriptorRenderer.render(model: model)
        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )

        #expect(renderedText(in: shown).contains("EUR 51,200.00"))
        #expect(renderedText(in: shown).contains("EUR 6,000.00"))
        #expect(renderedText(in: shown).contains("EUR 189.50"))
        #expect(renderedText(in: hidden).contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(renderedText(in: hidden).contains("Nova Lithography"))
        #expect(renderedText(in: hidden).contains("11.7%"))
        #expect(renderedText(in: hidden).contains("Nova Lithography"))

        let leaked = knownFixtureMoneyText().filter { renderedText(in: hidden).contains($0) }
        #expect(leaked.isEmpty)
    }

    @Test("Hidden descriptor covers nested rows, chart details, summary, and surface accessibility")
    func hiddenDescriptorCoversEveryRenderedSurface() throws {
        let model = PressureEngine.buildModel(from: try visibilitySnapshot())
        let descriptor = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let text = renderedText(in: descriptor) + renderedText(in: surface)

        #expect(text.contains("Worth"))
        #expect(text.contains("Price"))
        #expect(text.contains("Average buy price"))
        #expect(text.contains("Gain/loss"))
        #expect(text.contains("Amount"))
        #expect(text.contains("Change"))
        #expect(text.contains("Total portfolio value"))
        #expect(text.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(!text.contains("EUR 51,200.00"))
        #expect(!text.contains("EUR 6,000.00"))
        #expect(!text.contains("EUR 22.40"))
        #expect(!text.contains("EUR 3.10"))
        #expect(!text.contains("EUR 2.90"))
    }

    @Test("Toggling visibility re-renders the same in-memory pulse without refetching")
    func togglingVisibilityRerendersSamePulseWithoutRefetching() throws {
        let dataSource = CountingDataSource(snapshot: try visibilitySnapshot())
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-value-visibility")
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let pulse = try PressureRunner.run(
            dataSource: dataSource,
            snapshotStore: store,
            pulseReadStore: PulseReadStore(directory: store.directory)
        )
        let hidden = pulse.rendered(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let restored = hidden.rendered(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: true)
        )

        #expect(dataSource.calls == 1)
        #expect(pulse.model == hidden.model)
        #expect(hidden.model == restored.model)
        #expect(renderedText(in: hidden.descriptor).contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(!renderedText(in: hidden.descriptor).contains("EUR 51,200.00"))
        #expect(renderedText(in: restored.descriptor).contains("EUR 51,200.00"))
        #expect(dataSource.calls == 1)
    }

    @MainActor
    @Test("Settings default enabled and persist through UserDefaults reload")
    func settingsDefaultEnabledAndPersist() throws {
        let suite = "PortfolioValueVisibilityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = PDTBarSettingsStore(userDefaults: defaults)
        #expect(first.showPortfolioValues)

        first.showPortfolioValues = false
        let second = PDTBarSettingsStore(userDefaults: defaults)
        #expect(!second.showPortfolioValues)

        second.showPortfolioValues = true
        let third = PDTBarSettingsStore(userDefaults: defaults)
        #expect(third.showPortfolioValues)
    }

    @Test("Settings can use an isolated UserDefaults suite from environment")
    func settingsCanUseIsolatedSuiteFromEnvironment() throws {
        let suite = "PortfolioValueVisibilityEnvironmentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolved = PDTBarSettingsStore.userDefaults(
            environment: [PDTBarSettingsStore.userDefaultsSuiteEnvironmentKey: suite]
        )
        resolved.set(false, forKey: PDTBarSettingsStore.showPortfolioValuesKey)

        #expect(defaults.object(forKey: PDTBarSettingsStore.showPortfolioValuesKey) as? Bool == false)
    }
}

private final class CountingDataSource: PortfolioDataSource {
    private let fixedSnapshot: PortfolioSnapshot
    private(set) var calls = 0

    init(snapshot: PortfolioSnapshot) {
        self.fixedSnapshot = snapshot
    }

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        calls += 1
        return fixedSnapshot
    }
}

private func visibilitySnapshot() throws -> PortfolioSnapshot {
    var snapshot = try PDTFixtureDataSource.snapshot(
        from: visibilityPackageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
    )
    snapshot.openHoldings[0].averageBuyPrice = Money(value: "189.50", currency: "EUR")
    snapshot.incomeEvents = [
        IncomeEventSummary(
            date: "2026-06-25",
            kind: "ex-dividend",
            symbolName: "Nova Lithography",
            estimated: false,
            symbolId: 101,
            quoteId: 9001,
            amount: Money(value: "3.10", currency: "EUR"),
            priorAmount: Money(value: "2.90", currency: "EUR"),
            changePercent: 0.0689655
        ),
    ]
    return snapshot
}

private func knownFixtureMoneyText() -> [String] {
    [
        "EUR 51,200.00",
        "EUR 6,000.00",
        "EUR 5,800.00",
        "EUR 5,500.00",
        "EUR 5,500.00",
        "EUR 5,000.00",
        "EUR 4,900.00",
        "EUR 1,895.00",
        "EUR 598.00",
        "EUR 189.50",
        "EUR 188.10",
        "EUR 22.40",
        "EUR 3.10",
        "EUR 2.90",
    ]
}

private func renderedText(in descriptor: MenuDescriptor) -> String {
    var values = [
        descriptor.statusTitle,
        descriptor.statusBadge,
    ]
    values.append(contentsOf: descriptor.sections.map(\.title))
    values.append(contentsOf: descriptor.sections.flatMap { $0.rows.flatMap(renderedTextValues) })
    return values.compactMap { $0 }.joined(separator: "\n")
}

private func renderedTextValues(in row: MenuRow) -> [String] {
    var values = [
        row.title,
        row.detail,
        row.portfolioSummary?.totalValue,
        row.portfolioSummary?.cagr,
        row.portfolioSummary?.totalIncrease,
        row.portfolioSummary?.accessibilityLabel,
    ]
    values.append(contentsOf: row.barChart?.bars.flatMap {
        [$0.label, $0.axisLabel, $0.percentageLabel, $0.detail]
    } ?? [])
    values.append(contentsOf: row.children.flatMap(renderedTextValues))
    return values.compactMap { $0 }
}

private func renderedText(in surface: MenuBarSurface) -> String {
    var values = [
        surface.status.title,
        surface.status.badge,
        surface.status.accessibilityLabel,
        surface.status.toolTip,
    ]
    values.append(contentsOf: surface.sections.map(\.title))
    values.append(contentsOf: surface.sections.flatMap { $0.rows.flatMap(renderedTextValues) })
    return values.compactMap { $0 }.joined(separator: "\n")
}

private func renderedTextValues(in row: MenuBarRowSurface) -> [String] {
    var values = [
        row.title,
        row.detail,
        row.portfolioSummary?.totalValue,
        row.portfolioSummary?.cagr,
        row.portfolioSummary?.totalIncrease,
        row.portfolioSummary?.accessibilityLabel,
    ]
    values.append(contentsOf: row.barChart?.bars.flatMap {
        [$0.label, $0.axisLabel, $0.percentageLabel, $0.detail]
    } ?? [])
    values.append(contentsOf: row.children.flatMap(renderedTextValues))
    return values.compactMap { $0 }
}

private let visibilityPackageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
