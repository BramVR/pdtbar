import Foundation
import Testing
import PDTBarCore

@Suite("PDT base holding normalization")
struct BaseHoldingNormalizationTests {
    @Test("Shared interface normalizes open base holding facts")
    func sharedInterfaceNormalizesOpenBaseHoldingFacts() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Open Public Co",
                    quoteId: 1001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.25", currency: "EUR"),
                    currentWorth: Money(value: "500.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "500.00", currency: "EUR"),
                    portfolioWeight: 0.25,
                    unrealisedBoughtPriceAverageLocal: nil,
                    unrealisedBoughtPriceTotalLocal: Money(value: "320.00", currency: "EUR"),
                    unrealisedBoughtShares: 8,
                    unrealisedGains: Money(value: "180.00", currency: "EUR"),
                    unrealisedGainsPercentage: 0.5625,
                    closedAt: nil,
                    copyableIdentifier: " PUBC "
                ),
                PDTBaseHoldingInput(
                    name: "Closed Co",
                    quoteId: 1002,
                    currentPriceDate: "2026-06-25T21:59:00+00:00",
                    currentPriceLocal: Money(value: "1.00", currency: "EUR"),
                    currentWorth: Money(value: "0.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "0.00", currency: "EUR"),
                    portfolioWeight: 0.10,
                    closedAt: "2026-06-01T00:00:00+00:00",
                    copyableIdentifier: "CLSD"
                ),
                PDTBaseHoldingInput(
                    name: "Zero Worth",
                    quoteId: 1003,
                    currentPriceDate: "2026-06-24T21:59:00+00:00",
                    currentPriceLocal: Money(value: "2.00", currency: "EUR"),
                    currentWorth: Money(value: "0.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "0.00", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "ZERO"
                ),
                PDTBaseHoldingInput(
                    name: "Invalid Money",
                    quoteId: 1004,
                    currentPriceDate: "2026-06-23T21:59:00+00:00",
                    currentPriceLocal: Money(value: "bad", currency: "EUR"),
                    currentWorth: Money(value: "bad", currency: "EUR"),
                    currentWorthLocal: Money(value: "bad", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "123456"
                ),
            ],
            currency: "EUR",
            reportedTotalValue: Money(value: "not-money", currency: "EUR")
        )

        #expect(normalized.openHoldings.map(\.quoteId) == [1001])
        let holding = normalized.openHoldings[0]
        #expect(holding.worth == Money(value: "500.00", currency: "EUR"))
        #expect(holding.price == Money(value: "10.25", currency: "EUR"))
        #expect(holding.priceAsOf == "2026-06-26")
        #expect(holding.copyableIdentifier == "PUBC")
        #expect(holding.averageBuyPrice == Money(value: "40.0000", currency: "EUR"))
        #expect(holding.gainLoss == Money(value: "180.00", currency: "EUR"))
        #expect(holding.gainLossPercentage == 0.5625)
        #expect(normalized.totalValue == Money(value: "500.00", currency: "EUR"))
    }

    @Test("Fixture-backed Pulse scenarios keep their normalized behavior")
    func fixtureBackedPulseScenariosKeepTheirNormalizedBehavior() throws {
        let concentration = try model("concentration-pressure")
        let income = try model("income-event")
        let bigMover = try model("big-mover", withPrior: true)
        let quiet = try model("quiet-no-pressure")

        #expect(concentration.rankedAttentionItems.first?.facet == "allocation")
        #expect(concentration.facetSnapshots.allocation.openHoldingCount == 12)
        #expect(income.rankedAttentionItems.contains { $0.facet == "income" })
        #expect(income.facetSnapshots.income.upcomingEvents.count == 5)
        #expect(bigMover.supportingDataSlots.contains { $0.facet == "bigMovers" })
        #expect(bigMover.facetSnapshots.bigMovers.priceSeriesCount == 5)
        #expect(quiet.allQuiet)
        #expect(quiet.rankedAttentionItems.isEmpty)
    }

    @Test("Live connector source applies shared base holding filtering")
    func liveConnectorSourceAppliesSharedBaseHoldingFiltering() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(baseHoldingsJSON.utf8),
        ])
        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: false,
                includePriceSeries: false
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.map(\.quoteId) == [1001])
        #expect(snapshot.totalValue == Money(value: "500.00", currency: "EUR"))
    }

    @Test("Background detail refresh applies shared base holding filtering")
    func backgroundDetailRefreshAppliesSharedBaseHoldingFiltering() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-base-normalization-background-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(baseHoldingsJSON.utf8),
            "pdt-get-portfolio-distributions": Data(#"{"sectors":[],"assetTypes":[]}"#.utf8),
            "pdt-list-x-ray-holdings": Data(#"{"items":[],"hasMore":false}"#.utf8),
            "pdt-list-calendar-events": Data(#"{"data":[]}"#.utf8),
            "pdt-list-dividends": Data(#"{"data":[],"meta":{"last_page":1}}"#.utf8),
            "pdt-list-symbol-prices": Data(#"{"data":[]}"#.utf8),
        ])

        _ = try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-06-26",
            options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 1, retryBackoffSeconds: 0)
        ).refresh()

        let snapshot = try #require(try store.loadPriorSnapshot())
        #expect(snapshot.openHoldings.map(\.quoteId) == [1001])
        #expect(snapshot.totalValue == Money(value: "500.00", currency: "EUR"))
    }

    private func model(_ fixtureName: String, withPrior: Bool = false) throws -> PortfolioPulseModel {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let prior = withPrior ? try? PDTFixtureDataSource.priorSnapshot(from: fixture) : nil
        return PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let baseHoldingsJSON = """
{
  "holdings": [
    {
      "symbolName": "Closed Foreign Co",
      "symbolQuoteId": 1002,
      "currentPriceDate": "2026-06-25T21:59:00+00:00",
      "currentPriceLocal": { "value": "1.00", "currency": "USD" },
      "currentWorth": { "value": "0.00", "currency": "USD" },
      "currentWorthLocal": { "value": "0.00", "currency": "USD" },
      "portfolioWeight": 0.10,
      "closedAt": "2026-06-01T00:00:00+00:00"
    },
    {
      "symbolName": "Open Public Co",
      "symbolQuoteId": 1001,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "10.25", "currency": "EUR" },
      "currentWorth": { "value": "500.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "500.00", "currency": "EUR" },
      "portfolioWeight": 0.25,
      "closedAt": null
    },
    {
      "symbolName": "Zero Worth",
      "symbolQuoteId": 1003,
      "currentPriceDate": "2026-06-24T21:59:00+00:00",
      "currentPriceLocal": { "value": "2.00", "currency": "EUR" },
      "currentWorth": { "value": "0.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "0.00", "currency": "EUR" },
      "portfolioWeight": 0.05,
      "closedAt": null
    },
    {
      "symbolName": "Invalid Money",
      "symbolQuoteId": 1004,
      "currentPriceDate": "2026-06-23T21:59:00+00:00",
      "currentPriceLocal": { "value": "bad", "currency": "EUR" },
      "currentWorth": { "value": "bad", "currency": "EUR" },
      "currentWorthLocal": { "value": "bad", "currency": "EUR" },
      "portfolioWeight": 0.05,
      "closedAt": null
    }
  ]
}
"""
