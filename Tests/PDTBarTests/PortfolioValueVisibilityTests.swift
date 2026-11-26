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
        let hiddenAfterRoundTripText = renderedText(in: hiddenAfterRoundTrip)
        let hiddenJSON = try #require(String(data: stableJSONData(hiddenAtAppChoke), encoding: .utf8))
        let monetaryDisplays = try monetaryDisplays(in: snapshot)

        #expect(
            monetaryDisplays.contains(where: shownText.contains),
            "Visible \(fixtureName) descriptor did not render a snapshot monetary value"
        )
        #expect(hiddenText.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(hiddenAtAppChoke == hidden)
        #expect(hiddenAfterRoundTripText.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(
            try leakedAmounts(in: hiddenAfterRoundTripText, snapshot: snapshot, model: model).isEmpty,
            "Decoded hidden \(fixtureName) descriptor leaked snapshot amounts"
        )
        #expect(
            hidden.applying(
                settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
            ) == hidden
        )
        #expect(
            try leakedAmounts(in: hiddenText, snapshot: snapshot, model: model).isEmpty,
            "Hidden \(fixtureName) descriptor leaked snapshot amounts"
        )
        #expect(
            try leakedAmounts(in: descriptorJSON(hiddenAtAppChoke), snapshot: snapshot, model: model).isEmpty,
            "Hidden \(fixtureName) descriptor JSON leaked snapshot amounts"
        )
        #expect(!hiddenJSON.contains("\"portfolioValueDetail\""))
        #expect(!hiddenJSON.contains("\"portfolioValueBarDetails\""))
        #expect(!hiddenJSON.contains("\"portfolioValueSummaryTotal\""))
        #expect(!hiddenJSON.contains("\"portfolioValueProtectionState\""))
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
        let leaked = try leakedAmounts(in: text + descriptorJSON(descriptor), snapshot: snapshot, model: model)

        #expect(text.contains("Total portfolio value"))
        #expect(text.contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
        #expect(leaked.isEmpty, "Hidden \(fixtureName) surface leaked: \(leaked)")
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
        #expect(try leakedAmounts(in: renderedText(in: hidden.descriptor), snapshot: snapshot, model: hidden.model).isEmpty)
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
        let model = PressureEngine.buildModel(from: snapshot)
        let descriptor = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let leaked = try leakedAmounts(in: renderedText(in: descriptor), snapshot: snapshot, model: model)

        #expect(leaked.isEmpty, "Hidden GBp descriptor leaked: \(leaked)")
    }

    @Test("Hidden mode hides the cash drag value in Pulse and its explanation")
    func hiddenModeHidesCashDragValue() throws {
        var snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        let cash = try #require(snapshot.openHoldings.lastIndex { $0.name == "Cash" })
        snapshot.openHoldings[cash].weight = 0.12
        snapshot.openHoldings[cash].worth = Money(value: "6144.00", currency: "EUR")
        let model = PressureEngine.buildModel(from: snapshot)
        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let cashDrag = try #require(row(withID: "allocation.cashDrag.glance", in: hidden))
        let leaked = try leakedAmounts(
            in: renderedText(in: hidden) + descriptorJSON(hidden),
            snapshot: snapshot,
            model: model
        )

        #expect(cashDrag.detail == "12.0%; \(PortfolioValueDisplaySettings.hiddenPlaceholder)")
        #expect(leaked.isEmpty, "Hidden cash drag descriptor leaked: \(leaked)")
    }

    @Test("A decoded fact's key cannot unmask its numeric value")
    func decodedFactKeyCannotUnmaskNumericValue() throws {
        var snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        let cash = try #require(snapshot.openHoldings.lastIndex { $0.name == "Cash" })
        snapshot.openHoldings[cash].weight = 0.12
        var model = PressureEngine.buildModel(from: snapshot)
        let cashDrag = try #require(model.rankedAttentionItems.firstIndex { $0.id == "allocation.cashDrag" })
        model.rankedAttentionItems[cashDrag].explanation.currentValue = try JSONDecoder().decode(
            AttentionExplanationFact.self,
            from: Data(#"{"key": "severity", "label": "Current", "value": "EUR 123.45", "numericValue": 123.45}"#.utf8)
        )
        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let current = try #require(row(withID: "allocation.cashDrag.currentValue", in: hidden))
        let json = try #require(String(data: stableJSONData(hidden), encoding: .utf8))

        #expect(current.detail == PortfolioValueDisplaySettings.hiddenPlaceholder)
        #expect(!json.contains("123.45"))
    }

    @Test(
        "A decoded Severity fact never shows its own number",
        arguments: [
            (
                #"{"key": "currentValue", "label": "Severity", "value": "medium", "numericValue": 123.45, "unit": "EUR"}"#,
                "medium"
            ),
            (
                #"{"key": "severity", "label": "Severity", "value": "medium", "numericValue": 123.45}"#,
                "medium; score 0.66"
            ),
        ]
    )
    func decodedSeverityFactNeverShowsItsOwnNumber(_ severityFact: String, _ expected: String) throws {
        let item = try JSONDecoder().decode(AttentionItem.self, from: Data("""
        {
          "id": "allocation.concentration.9001",
          "facet": "allocation",
          "rank": 1,
          "title": "Nova Lithography concentration",
          "detail": "24.2%",
          "severity": "medium",
          "score": 0.66,
          "supportingDataSlotIDs": ["allocation.holdings"],
          "explanation": {
            "trigger": {"key": "trigger", "label": "Trigger", "value": "Concentration line crossed"},
            "severity": \(severityFact),
            "supportingSourceSlots": []
          }
        }
        """.utf8))
        var model = PressureEngine.buildModel(from: try visibilitySnapshot("concentration-pressure.json"))
        model.rankedAttentionItems = [item]

        for showPortfolioValues in [true, false] {
            let descriptor = MenuDescriptorRenderer.render(
                model: model,
                settings: PortfolioValueDisplaySettings(showPortfolioValues: showPortfolioValues)
            )
            let severity = try #require(row(withID: "allocation.concentration.9001.severity", in: descriptor))
            let json = try #require(String(data: stableJSONData(descriptor), encoding: .utf8))

            #expect(severity.detail == expected)
            #expect(!json.contains("123.45"))
        }
    }

    @Test("The severity row's score is the item's own, whatever number its fact holds")
    func severityRowScoreIsTheItemsOwn() throws {
        var model = PressureEngine.buildModel(from: try visibilitySnapshot("concentration-pressure.json"))
        model.rankedAttentionItems[0].explanation.severity.numericValue = 123.45
        let hidden = MenuDescriptorRenderer.render(
            model: model,
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let severity = try #require(row(withID: "allocation.concentration.9001.severity", in: hidden))

        #expect(severity.detail == "medium; score 0.66")
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

    @Test(
        "Metadata-free descriptors fail closed regardless of section ID",
        arguments: ["pulse", "custom"]
    )
    func metadataFreePortfolioDescriptorsFailClosed(_ sectionID: String) throws {
        let descriptor = MenuDescriptor(
            statusTitle: "Legacy portfolio",
            sections: [
                MenuSection(
                    id: sectionID,
                    title: "Legacy",
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
                                cagr: nil,
                                totalIncrease: nil
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

    @Test("Trusted setup descriptors preserve nonfinancial details when values are hidden")
    func trustedSetupDescriptorsPreserveNonfinancialDetails() throws {
        let descriptor = PDTLaunchMenu.descriptor(for: .checkingConnection)
        let hidden = descriptor.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let setupRow = try #require(row(withID: "pdtConnection.status", in: hidden))

        #expect(setupRow.detail == "No prompts opened")
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

    @Test("Serialized protection markers cannot bypass the app choke point")
    func serializedProtectionMarkersCannotBypassAppChokePoint() throws {
        let descriptor = MenuDescriptor(
            statusTitle: "Untrusted cached portfolio",
            sections: [
                MenuSection(
                    id: "allocation",
                    title: "Allocation",
                    rows: [
                        MenuRow(
                            id: "untrusted.detail",
                            title: "Untrusted detail",
                            detail: "GBp 54,321.09"
                        ),
                    ]
                ),
            ]
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: stableJSONData(descriptor)) as? [String: Any]
        )
        object["portfolioValueProtectionState"] = "hidden"
        let forgedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(MenuDescriptor.self, from: forgedData)

        let hidden = decoded.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )

        #expect(!renderedText(in: hidden).contains("54,321.09"))
        #expect(renderedText(in: hidden).contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
    }

    @Test("Public section mutation invalidates trusted value metadata")
    func publicSectionMutationInvalidatesTrustedValueMetadata() throws {
        let snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        var descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: snapshot)
        )
        descriptor.sections.append(
            MenuSection(
                id: "extension",
                title: "Extension",
                rows: [
                    MenuRow(
                        id: "extension.money",
                        title: "Extension value",
                        detail: "GBp 54,321.09"
                    ),
                ]
            )
        )

        let hidden = descriptor.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )

        #expect(!renderedText(in: hidden).contains("54,321.09"))
        #expect(renderedText(in: hidden).contains(PortfolioValueDisplaySettings.hiddenPlaceholder))
    }

    @Test("Duplicate quote IDs retain ordered chart value metadata")
    func duplicateQuoteIDsRetainOrderedChartValueMetadata() throws {
        let snapshot = try visibilitySnapshot("quiet-no-pressure.json")
        var model = PressureEngine.buildModel(from: snapshot)
        var duplicate = try #require(
            model.facetSnapshots.allocation.portfolioOverview.topHoldings.first
        )
        duplicate.name = "Duplicate quote holding"
        duplicate.worth = Money(value: "54321.09", currency: "GBp")
        model.facetSnapshots.allocation.portfolioOverview.topHoldings.append(duplicate)

        let shown = MenuDescriptorRenderer.render(model: model)
        let hidden = shown.applying(
            settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
        )
        let chartRow = try #require(row(withID: "allocation.portfolio", in: shown))

        #expect(chartRow.barChart?.bars.count == model.facetSnapshots.allocation.portfolioOverview.topHoldings.count)
        #expect(renderedText(in: shown).contains("54,321.09"))
        #expect(!renderedText(in: hidden).contains("54,321.09"))
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

    @Test(
        "Income attention describes the first ex-dividend event PDT lists for its quote and date",
        arguments: [true, false]
    )
    func incomeAttentionDescribesFirstListedEvent(_ showPortfolioValues: Bool) throws {
        let snapshot = try incomeEventSnapshot { events in
            let confirmed = try #require(events.firstIndex { $0["id"] as? Int == 1001 })
            var estimate = events[confirmed]
            estimate["id"] = 1000
            estimate["isEstimated"] = true
            events.insert(estimate, at: confirmed)
        }
        let descriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: snapshot),
            settings: PortfolioValueDisplaySettings(showPortfolioValues: showPortfolioValues)
        )
        let attention = try #require(row(withID: "income.ex-dividend.9003.glance", in: descriptor))

        #expect(attention.detail == "Helix Pharma A/S has an ex-dividend date on 2026-06-24.")
    }

    @Test("Income attention without a quote hides its whole copy with portfolio values")
    func incomeAttentionWithoutQuoteHidesWholeCopy() throws {
        let snapshot = try incomeEventSnapshot { events in
            let confirmed = try #require(events.firstIndex { $0["id"] as? Int == 1001 })
            events[confirmed]["symbolId"] = 5999
        }
        let model = PressureEngine.buildModel(from: snapshot)
        let id = "income.ex-dividend.symbol.5999.glance"
        let shown = try #require(row(withID: id, in: MenuDescriptorRenderer.render(model: model)))
        let hidden = try #require(
            row(
                withID: id,
                in: MenuDescriptorRenderer.render(
                    model: model,
                    settings: PortfolioValueDisplaySettings(showPortfolioValues: false)
                )
            )
        )

        #expect(shown.detail == "Helix Pharma A/S has an ex-dividend date on 2026-06-24.")
        #expect(hidden.detail == PortfolioValueDisplaySettings.hiddenPlaceholder)
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

private func incomeEventSnapshot(
    editingCalendarEvents edit: (inout [[String: Any]]) throws -> Void
) throws -> PortfolioSnapshot {
    let source = visibilityPackageRoot.appending(path: "docs/pdt/fixtures/income-event.json")
    var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
    var calendar = try #require(payload["listCalendarEvents"] as? [String: Any])
    var events = try #require(calendar["data"] as? [[String: Any]])
    try edit(&events)
    calendar["data"] = events
    payload["listCalendarEvents"] = calendar
    let edited = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-income-event-\(UUID().uuidString).json")
    try JSONSerialization.data(withJSONObject: payload).write(to: edited)
    defer { try? FileManager.default.removeItem(at: edited) }
    return try PDTFixtureDataSource.snapshot(from: edited)
}

private func monetaryDisplays(in snapshot: PortfolioSnapshot) throws -> Set<String> {
    Set(try snapshotMoney(in: snapshot).map(formattedMoney))
}

private func leakedAmounts(
    in text: String,
    snapshot: PortfolioSnapshot,
    model: PortfolioPulseModel
) throws -> [String] {
    let items = model.rankedAttentionItems + model.attentionItems
        + model.facetSnapshots.allocation.allocationPressureItems
    let scanned = items.reduce(text) { text, item in
        text.replacingOccurrences(
            of: "\(item.severity); score \(decimalStringForTest(String(item.score), places: 2))",
            with: "\(item.severity); score"
        )
    }
    var values = try snapshotMoney(in: snapshot).map(\.value)
    values.append(contentsOf: snapshot.priceSeries.map(\.closeAdjusted))
    let forms = Set(values.flatMap { value in
        [
            value,
            decimalStringForTest(value, places: 2),
            decimalStringForTest(value, places: 2, grouped: false),
        ]
    })
    return forms.filter { form in
        let number = NSRegularExpression.escapedPattern(for: form)
        return scanned.range(of: #"(?<!\d)\#(number)(?!\d)"#, options: .regularExpression) != nil
    }.sorted()
}

private func descriptorJSON(_ descriptor: MenuDescriptor) throws -> String {
    try #require(String(data: stableJSONData(descriptor), encoding: .utf8))
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

private func decimalStringForTest(_ value: String, places: Int, grouped: Bool = true) -> String {
    guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
        return value
    }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = grouped
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
        row.actionPayload,
    ]
    values.append(contentsOf: row.barChart?.bars.flatMap {
        [$0.label, $0.percentageLabel, $0.detail]
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
        [$0.label, $0.percentageLabel, $0.detail]
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
    "worst-case-height.json",
]
