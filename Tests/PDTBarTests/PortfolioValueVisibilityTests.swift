import Foundation
import Testing
import PDTBarAppSupport
import PDTBarCore

@Suite("Portfolio value visibility")
struct PortfolioValueVisibilityTests {
    @Test(
        "Portfolio values show by default and hide behind one placeholder",
        arguments: portfolioValueFixtureNames
    )
    func portfolioValuesShowByDefaultAndHideBehindOnePlaceholder(_ fixtureName: String) throws {
        let snapshot = try visibilitySnapshot(fixtureName)
        let model = PressureEngine.buildModel(from: snapshot)
        let shown = MenuDescriptorRenderer.render(model: model)
        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let hiddenAtAppChoke = shown.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let decodedShown = try JSONDecoder().decode(
            MenuDescriptor.self,
            from: stableJSONData(shown)
        )
        let hiddenAfterRoundTrip = decodedShown.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let shownText = renderedText(in: shown)
        let hiddenText = renderedText(in: hidden)
        let hiddenJSON = try #require(String(data: stableJSONData(hiddenAtAppChoke), encoding: .utf8))
        let monetaryDisplays = try monetaryDisplays(in: snapshot)

        #expect(
            monetaryDisplays.contains(where: shownText.contains),
            "Visible \(fixtureName) descriptor did not render a snapshot monetary value"
        )
        #expect(hiddenText.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(hiddenAtAppChoke == hidden)
        #expect(hiddenAfterRoundTrip == hidden)
        #expect(
            hidden.applying(
                settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
            ) == hidden
        )
        #expect(
            try monetaryDigitGroups(in: snapshot).filter(hiddenText.contains).isEmpty,
            "Hidden \(fixtureName) descriptor leaked snapshot monetary digit groups"
        )
        #expect(!hiddenJSON.contains("\"portfolioValueDetail\""))
        #expect(!hiddenJSON.contains("\"portfolioValueBarDetails\""))
        #expect(!hiddenJSON.contains("\"portfolioValueSummaryTotal\""))
    }

    @Test(
        "Hidden descriptor covers nested rows, charts, summaries, labels, and tooltips",
        arguments: portfolioValueFixtureNames
    )
    func hiddenDescriptorCoversEveryRenderedSurface(_ fixtureName: String) throws {
        let snapshot = try visibilitySnapshot(fixtureName)
        let model = PressureEngine.buildModel(from: snapshot)
        let descriptor = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let surface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
        let text = renderedText(in: descriptor) + renderedText(in: surface)
        let leaked = try monetaryDigitGroups(in: snapshot).filter(text.contains)

        #expect(text.contains("Total portfolio value"))
        #expect(text.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(leaked.isEmpty, "Hidden \(fixtureName) surface leaked: \(leaked.sorted())")
    }

    @Test(
        "Toggling visibility re-renders the same in-memory pulse without refetching",
        arguments: portfolioValueFixtureNames
    )
    func togglingVisibilityRerendersSamePulseWithoutRefetching(_ fixtureName: String) throws {
        let snapshot = try visibilitySnapshot(fixtureName)
        let dataSource = CountingDataSource(snapshot: snapshot)
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
        #expect(
            try monetaryDigitGroups(in: snapshot)
                .filter(renderedText(in: hidden.descriptor).contains)
                .isEmpty
        )
        #expect(
            try monetaryDisplays(in: snapshot).contains(where: renderedText(in: restored.descriptor).contains),
            "Restored \(fixtureName) descriptor did not render a snapshot monetary value"
        )
        #expect(dataSource.calls == 1)
    }

    @Test("Hidden mode catches mixed-case currency codes outside the old regex")
    func hiddenModeCatchesMixedCaseCurrencyCode() throws {
        var snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Sterling Test Holding",
                estimated: false,
                symbolId: 777,
                quoteId: 7777,
                amount: Money(value: "54321.09", currency: "GBp"),
                priorAmount: Money(value: "43210.98", currency: "GBp"),
                changePercent: 0.2571
            ),
        ]
        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: snapshot),
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let text = renderedText(in: descriptor)
        let leaked = try monetaryDigitGroups(in: snapshot).filter(text.contains)

        #expect(leaked.isEmpty, "Hidden GBp descriptor leaked: \(leaked.sorted())")
    }

    @Test("Unresolved sensitive attention data fails closed")
    func unresolvedSensitiveAttentionDataFailsClosed() throws {
        var snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Unresolved Sterling Holding",
                estimated: false,
                symbolId: 778,
                quoteId: 7778,
                amount: Money(value: "65432.10", currency: "GBp"),
                priorAmount: Money(value: "54321.09", currency: "GBp"),
                changePercent: 0.2045
            ),
        ]
        var model = PressureEngine.buildModel(from: snapshot)
        model.facetSnapshots.income.upcomingEvents = []

        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )

        #expect(!renderedText(in: hidden).contains("65,432.10"))
        #expect(!renderedText(in: hidden).contains("54,321.09"))
        #expect(renderedText(in: hidden).contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
    }

    @Test("Metadata-free portfolio descriptors fail closed")
    func metadataFreePortfolioDescriptorsFailClosed() throws {
        let descriptor = MenuDescriptor(
            statusTitle: "Legacy portfolio",
            sections: [
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: [
                        MenuRow(
                            id: "legacy.detail",
                            title: "Legacy detail",
                            detail: "GBp 54,321.09"
                        ),
                        MenuRow(
                            id: "legacy.chart",
                            title: "Legacy chart",
                            barChart: MenuRowBarChart(
                                bars: [
                                    MenuRowBarChart.Bar(
                                        id: "legacy.chart.bar",
                                        label: "Legacy",
                                        weight: 1,
                                        percentageLabel: "100.0%",
                                        detail: "Legacy; GBp 54,321.09"
                                    ),
                                ]
                            )
                        ),
                        MenuRow(
                            id: "legacy.summary",
                            title: "Legacy summary",
                            portfolioSummary: MenuRowPortfolioSummary(
                                totalValue: "GBp 54,321.09",
                                cagr: "Unavailable",
                                totalIncrease: "Unavailable"
                            )
                        ),
                    ]
                ),
            ]
        )

        let hidden = descriptor.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let text = renderedText(in: hidden)

        #expect(!text.contains("54,321.09"))
        #expect(
            text.components(separatedBy: PortfolioValueDisplaySettings.hiddenPlaceholder).count >= 4
        )
        #expect(
            hidden.applying(
                settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
            ) == hidden
        )
    }

    @Test("Legacy fallback clears typed value metadata before encoding")
    func legacyFallbackClearsTypedValueMetadataBeforeEncoding() throws {
        let event = IncomeEventSummary(
            date: "2026-06-25",
            kind: "ex-dividend",
            symbolName: "Legacy Typed Holding",
            estimated: false,
            symbolId: 779,
            quoteId: 7779,
            amount: Money(value: "54321.09", currency: "GBp")
        )
        let descriptor = MenuDescriptor(
            statusTitle: "Legacy typed portfolio",
            sections: [
                MenuSection(
                    id: "income",
                    title: "Income",
                    rows: IncomeCalendarDescriptor.rows(
                        for: IncomeCalendar.build(events: [event], asOf: "2026-06-22")
                    )
                ),
            ]
        )

        let hidden = descriptor.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let hiddenJSON = try #require(String(data: stableJSONData(hidden), encoding: .utf8))

        #expect(!hiddenJSON.contains("54,321.09"))
        #expect(!hiddenJSON.contains("\"portfolioValueDetail\""))
        #expect(!hiddenJSON.contains("\"portfolioValueBarDetails\""))
        #expect(!hiddenJSON.contains("\"portfolioValueSummaryTotal\""))
        #expect(
            hidden.applying(
                settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
            ) == hidden
        )
    }

    @Test("Income attention resolves same-name events by quote identity")
    func incomeAttentionResolvesSameNameEventsByQuoteIdentity() throws {
        var snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        snapshot.incomeEvents = [
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Dual Listed Holding",
                estimated: false,
                symbolId: 701,
                quoteId: 7001,
                amount: Money(value: "111.11", currency: "GBp")
            ),
            IncomeEventSummary(
                date: "2026-06-25",
                kind: "ex-dividend",
                symbolName: "Dual Listed Holding",
                estimated: false,
                symbolId: 702,
                quoteId: 7002,
                amount: Money(value: "222.22", currency: "GBp")
            ),
        ]
        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: snapshot)
        )
        let first = try #require(row(withID: "income.ex-dividend.7001.glance", in: descriptor))
        let second = try #require(row(withID: "income.ex-dividend.7002.glance", in: descriptor))

        #expect(first.detail?.contains("GBp 111.11") == true)
        #expect(!((first.detail ?? "").contains("GBp 222.22")))
        #expect(second.detail?.contains("GBp 222.22") == true)
        #expect(!((second.detail ?? "").contains("GBp 111.11")))
    }

    @Test("App applies portfolio value visibility at one menu installation choke point")
    func appHasSinglePortfolioValueVisibilityChokePoint() throws {
        let source = try String(
            contentsOf: visibilityPackageRoot.appending(path: "Sources/PDTBarApp/main.swift"),
            encoding: .utf8
        )
        let applications = source.components(separatedBy: ".applying(settings:").count - 1

        #expect(applications == 1)
        #expect(
            source.contains(
                "descriptor: descriptor.applying(settings: settingsStore.displaySettings)"
            )
        )
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

private func visibilitySnapshot(_ fixtureName: String) throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(
        from: visibilityPackageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName)")
    )
}

private func monetaryDisplays(in snapshot: PortfolioSnapshot) throws -> Set<String> {
    Set(try snapshotMoney(in: snapshot).map(formattedMoney))
}

private func monetaryDigitGroups(in snapshot: PortfolioSnapshot) throws -> Set<String> {
    var values = try snapshotMoney(in: snapshot).map(\.value)
    values.append(contentsOf: snapshot.priceSeries.map(\.closeAdjusted))
    return Set(values.map { decimalStringForTest($0, places: 2) })
}

private func snapshotMoney(in snapshot: PortfolioSnapshot) throws -> [Money] {
    var values: [Money] = []
    collectMoney(
        in: try JSONSerialization.jsonObject(with: stableJSONData(snapshot)),
        into: &values
    )
    values.append(contentsOf: snapshot.priceSeries.compactMap { point in
        point.closeCurrency.map { Money(value: point.closeAdjusted, currency: $0) }
    })
    return values
}

private func collectMoney(in object: Any, into values: inout [Money]) {
    if let dictionary = object as? [String: Any] {
        if let value = dictionary["value"] as? String,
           let currency = dictionary["currency"] as? String
        {
            values.append(Money(value: value, currency: currency))
        }
        dictionary.values.forEach { collectMoney(in: $0, into: &values) }
    } else if let array = object as? [Any] {
        array.forEach { collectMoney(in: $0, into: &values) }
    }
}

private func formattedMoney(_ money: Money) -> String {
    "\(money.currency) \(decimalStringForTest(money.value, places: 2))"
}

private func decimalStringForTest(_ value: String, places: Int) -> String {
    guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
        return value
    }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    return formatter.string(from: decimal as NSDecimalNumber) ?? value
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

private func row(withID id: String, in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections.lazy
        .flatMap(\.rows)
        .compactMap { row(withID: id, in: $0) }
        .first
}

private func row(withID id: String, in candidate: MenuRow) -> MenuRow? {
    if candidate.id == id {
        return candidate
    }
    return candidate.children.lazy.compactMap { row(withID: id, in: $0) }.first
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

private let portfolioValueFixtureNames = [
    "quiet-no-pressure.json",
    "big-mover.json",
    "concentration-pressure.json",
    "income-event.json",
]
