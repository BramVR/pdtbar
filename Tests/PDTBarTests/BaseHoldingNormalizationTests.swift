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
                    copyableIdentifier: " PUBC ",
                    isin: " nl0010273215 "
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
                    name: "Negative Worth",
                    quoteId: 1005,
                    currentPriceDate: "2026-06-24T21:59:00+00:00",
                    currentPriceLocal: Money(value: "2.00", currency: "EUR"),
                    currentWorth: Money(value: "-10.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "-10.00", currency: "EUR"),
                    portfolioWeight: 0.05,
                    closedAt: nil,
                    copyableIdentifier: "NEGV"
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
        #expect(holding.isin == "NL0010273215")
        #expect(holding.averageBuyPrice == Money(value: "40.0000", currency: "EUR"))
        #expect(holding.gainLoss == Money(value: "180.00", currency: "EUR"))
        #expect(holding.gainLossPercentage == 0.5625)
        #expect(normalized.totalValue == Money(value: "500.00", currency: "EUR"))
    }

    @Test("Multi-currency holdings total in the portfolio currency")
    func multiCurrencyHoldingsTotalInThePortfolioCurrency() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "US Traded Co",
                    quoteId: 2001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "347.66", currency: "EUR"),
                    currentExchangeRate: 1.154,
                    currentWorth: Money(value: "9347.40", currency: "USD"),
                    currentWorthLocal: Money(value: "8100.00", currency: "EUR"),
                    portfolioWeight: 0.34,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "EU Traded Co",
                    quoteId: 2002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "612.40", currency: "EUR"),
                    currentExchangeRate: 1,
                    currentWorth: Money(value: "15500.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "15500.00", currency: "EUR"),
                    portfolioWeight: 0.66,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        #expect(normalized.openHoldings.map(\.quoteId) == [2001, 2002])
        #expect(normalized.totalValue == Money(value: "23600.00", currency: "EUR"))
    }

    @Test("Portfolio currency inference requires a local-currency consensus")
    func portfolioCurrencyInferenceRequiresLocalCurrencyConsensus() {
        let usdHoldings = [
            testHolding(quoteId: 6101, localWorth: Money(value: "500.00", currency: "USD")),
            testHolding(quoteId: 6102, localWorth: Money(value: "250.00", currency: "USD")),
        ]
        let mixedHoldings = [
            testHolding(
                quoteId: 6201,
                currentWorth: Money(value: "250.00", currency: "DKK"),
                localWorth: Money(value: "250.00", currency: "DKK")
            ),
            testHolding(quoteId: 6202, localWorth: Money(value: "500.00", currency: "EUR")),
        ]

        #expect(PDTBaseHoldingNormalizer.portfolioCurrency(from: usdHoldings, fallback: "EUR") == "USD")
        #expect(PDTBaseHoldingNormalizer.portfolioCurrency(from: mixedHoldings, fallback: "EUR") == "EUR")
    }

    @Test("Headline total prefers each holding's portfolio-currency worth over the first holding's currency")
    func headlineTotalPrefersEachHoldingsPortfolioCurrencyWorth() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Trading Currency Local",
                    quoteId: 3001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "50.00", currency: "USD"),
                    currentWorth: Money(value: "400.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "500.00", currency: "USD"),
                    portfolioWeight: 0.30,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 3002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.70,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // 400.00 EUR + 1000.00 EUR; never 500 USD + 1000 EUR labeled "USD".
        #expect(normalized.openHoldings.map(\.quoteId) == [3001, 3002])
        #expect(normalized.totalValue == Money(value: "1400.00", currency: "EUR"))
    }

    @Test("Headline total converts trading-only worth with the holding exchange rate")
    func headlineTotalConvertsTradingOnlyWorthWithTheHoldingExchangeRate() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Danish Traded Co",
                    quoteId: 4001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "25.00", currency: "DKK"),
                    currentExchangeRate: 2.0,
                    currentWorth: Money(value: "250.00", currency: "DKK"),
                    currentWorthLocal: Money(value: "250.00", currency: "DKK"),
                    portfolioWeight: 0.20,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 4002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.80,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // 250.00 DKK / 2.0 = 125.00 EUR, plus 1000.00 EUR.
        #expect(normalized.openHoldings.map(\.quoteId) == [4001, 4002])
        #expect(normalized.totalValue == Money(value: "1125.00", currency: "EUR"))
    }

    @Test("Headline total keeps the portfolio currency when a worth cannot be converted")
    func headlineTotalKeepsThePortfolioCurrencyWhenAWorthCannotBeConverted() {
        let normalized = PDTBaseHoldingNormalizer.normalize(
            [
                PDTBaseHoldingInput(
                    name: "Unconvertible Co",
                    quoteId: 5001,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "25.00", currency: "USD"),
                    currentWorthLocal: Money(value: "250.00", currency: "USD"),
                    portfolioWeight: 0.20,
                    closedAt: nil
                ),
                PDTBaseHoldingInput(
                    name: "Portfolio Currency Co",
                    quoteId: 5002,
                    currentPriceDate: "2026-06-26T21:59:00+00:00",
                    currentPriceLocal: Money(value: "10.00", currency: "EUR"),
                    currentWorth: Money(value: "1000.00", currency: "EUR"),
                    currentWorthLocal: Money(value: "1000.00", currency: "EUR"),
                    portfolioWeight: 0.80,
                    closedAt: nil
                ),
            ],
            currency: "EUR"
        )

        // The USD-only worth stays visible as a holding but is excluded from the
        // headline total instead of being mixed into an EUR-labeled sum.
        #expect(normalized.openHoldings.map(\.quoteId) == [5001, 5002])
        #expect(normalized.openHoldings[0].worth == Money(value: "250.00", currency: "USD"))
        #expect(normalized.totalValue == Money(value: "1000.00", currency: "EUR"))
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

    @Test("Live connector sums multi-currency holdings in the portfolio currency")
    func liveConnectorSumsMultiCurrencyHoldingsInThePortfolioCurrency() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(multiCurrencyHoldingsJSON.utf8),
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

        #expect(snapshot.openHoldings.map(\.quoteId) == [2001, 2002])
        // 8100.00 EUR (PDT-converted USD worth) + 250.00 DKK / 2.0 = 8225.00 EUR.
        #expect(snapshot.totalValue == Money(value: "8225.00", currency: "EUR"))
    }

    @Test("Live connector derives non-EUR portfolio currency from local worths")
    func liveConnectorDerivesNonEURPortfolioCurrencyFromLocalWorths() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(nonEURPortfolioHoldingsJSON.utf8),
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

        #expect(snapshot.openHoldings.map(\.quoteId) == [6001, 6002])
        #expect(snapshot.totalValue == Money(value: "750.00", currency: "USD"))
    }

    @Test("Live wrapped setup error is classified as unavailable")
    func liveWrappedSetupErrorIsClassifiedAsUnavailable() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpTextContent(
                "PDT MCP setup required before reading holdings",
                isError: true
            ),
        ])

        do {
            _ = try PDTMCPConnectorDataSource(
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
            Issue.record("Expected wrapped setup error to be classified as unavailable")
        } catch PDTLiveDataSourceError.unavailableToolResult(let tool) {
            #expect(tool == "pdt-get-portfolio-holdings")
        }
    }

    @Test("Live wrapped result auth error is classified as unavailable")
    func liveWrappedResultAuthErrorIsClassifiedAsUnavailable() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpResultObject(["error": "authentication required"]),
        ])

        do {
            _ = try PDTMCPConnectorDataSource(
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
            Issue.record("Expected wrapped result auth error to be classified as unavailable")
        } catch PDTLiveDataSourceError.unavailableToolResult(let tool) {
            #expect(tool == "pdt-get-portfolio-holdings")
        }
    }

    @Test("Live plain wrapped text auth error is classified as unavailable")
    func livePlainWrappedTextAuthErrorIsClassifiedAsUnavailable() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpTextContent("authentication required"),
        ])

        do {
            _ = try PDTMCPConnectorDataSource(
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
            Issue.record("Expected wrapped text auth error to be classified as unavailable")
        } catch PDTLiveDataSourceError.unavailableToolResult(let tool) {
            #expect(tool == "pdt-get-portfolio-holdings")
        }
    }

    @Test("Live wrapped transient unavailable error is classified as retryable")
    func liveWrappedTransientUnavailableErrorIsClassifiedAsRetryable() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpTextContent(
                "PDT MCP server unavailable; try again later",
                isError: true
            ),
        ])

        do {
            _ = try PDTMCPConnectorDataSource(
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
            Issue.record("Expected wrapped transient unavailable error")
        } catch PDTLiveDataSourceError.transientUnavailableToolResult(let tool) {
            #expect(tool == "pdt-get-portfolio-holdings")
        }
    }

    @Test("Live connector decodes large wrapped MCP holdings payload")
    func liveConnectorDecodesLargeWrappedMCPHoldingsPayload() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpTextContent(largeWrappedHoldingsJSON()),
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

    @Test("Live wrapped MCP content ignores non-text items before JSON text")
    func liveWrappedMCPContentIgnoresNonTextItemsBeforeJSONText() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpContentItems([
                ["type": "image", "text": "authentication required"],
                ["type": "text", "text": baseHoldingsJSON],
            ]),
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

    @Test("Live connector decodes object data-wrapped MCP holdings payload")
    func liveConnectorDecodesObjectDataWrappedMCPHoldingsPayload() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": try mcpDataObject(baseHoldingsJSON),
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

    @Test("Filtered live holdings do not trigger quote lookup or price history")
    func filteredLiveHoldingsDoNotTriggerQuoteLookupOrPriceHistory() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(filteredLiveHoldingsJSON.utf8),
            "pdt-get-symbol-quote?id=1001": Data(#"{"id":1001,"code":"PUBC","symbolId":5001}"#.utf8),
            "pdt-list-symbol-prices?date_from=2026-06-19&date_to=2026-06-26&symbol_quote_id=1001": Data("""
            {
              "data": [
                { "date": "2026-06-25", "closeAdjusted": "9.75", "symbolQuoteId": 1001 },
                { "date": "2026-06-26", "closeAdjusted": "10.25", "symbolQuoteId": 1001 }
              ]
            }
            """.utf8),
        ])
        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: true
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.map(\.quoteId) == [1001])
        #expect(snapshot.priceSeries.map(\.quoteId) == [1001, 1001])
        let model = PressureEngine.buildModel(from: snapshot)
        #expect(model.facetSnapshots.allocation.openHoldingCount == 1)
        #expect(model.facetSnapshots.allocation.topHoldings.map(\.quoteId) == [1001])
        #expect(model.rankedAttentionItems.isEmpty)
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.count == 1)
        #expect(connector.calls.filter { $0 == "pdt-list-symbol-prices" }.count == 1)
    }

    @Test("Live connector paginates income calendar events")
    func liveConnectorPaginatesIncomeCalendarEvents() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(baseHoldingsJSON.utf8),
            "pdt-list-calendar-events?date_from=2026-06-26&date_to=2026-07-26&page=1&per_page=250": Data("""
            {
              "data": [
                { "date": "2026-06-26", "type": "no-events-today", "isEstimated": false, "symbolId": null, "symbolName": null },
                { "date": "2026-06-29", "type": "payment-dividend", "isEstimated": false, "symbolId": 5001, "symbolName": "Open Public Co" }
              ],
              "meta": { "last_page": 2 }
            }
            """.utf8),
            "pdt-list-calendar-events?date_from=2026-06-26&date_to=2026-07-26&page=2&per_page=250": Data("""
            {
              "data": [
                { "date": "2026-07-02", "type": "ex-dividend", "isEstimated": false, "symbolId": 5001, "symbolName": "Open Public Co" }
              ],
              "meta": { "last_page": 2 }
            }
            """.utf8),
            "pdt-get-symbol-quote?id=1001": Data(#"{"id":1001,"code":"PUBC","symbolId":5001}"#.utf8),
        ])

        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: true,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: false
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.incomeEvents.map(\.kind) == ["payment-dividend", "ex-dividend"])
        #expect(snapshot.incomeEvents.map(\.quoteId) == [1001, 1001])
        #expect(connector.calls.filter { $0 == "pdt-list-calendar-events" }.count == 2)
    }

    @Test("Optional symbol lookup absence is cached per live snapshot")
    func optionalSymbolLookupAbsenceIsCachedPerLiveSnapshot() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(twoOpenHoldingsJSON.utf8),
            "pdt-get-symbol-quote?id=1001": Data(#"{"id":1001,"code":"PUBC","symbolId":5001}"#.utf8),
            "pdt-get-symbol-quote?id=1002": Data(#"{"id":1002,"code":"OTHR","symbolId":5002}"#.utf8),
        ])
        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: false
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.map(\.copyableIdentifier) == ["PUBC", "OTHR"])
        #expect(snapshot.openHoldings.map(\.isin) == [nil, nil])
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.count == 2)
        #expect(connector.calls.filter { $0 == "pdt-get-symbol" }.count == 1)
    }

    @Test("Transient optional symbol lookup outage stops later optional lookups")
    func transientOptionalSymbolLookupOutageStopsLaterOptionalLookups() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(twoOpenHoldingsJSON.utf8),
            "pdt-get-symbol-quote?id=1001": Data(#"{"id":1001,"code":"PUBC","symbolId":5001}"#.utf8),
            "pdt-get-symbol-quote?id=1002": Data(#"{"id":1002,"code":"OTHR","symbolId":5002}"#.utf8),
            "pdt-get-symbol?id=5001": try mcpTextContent(
                "PDT MCP server unavailable; try again later",
                isError: true
            ),
            "pdt-get-symbol?id=5002": try mcpTextContent(
                "PDT MCP server unavailable; try again later",
                isError: true
            ),
        ])
        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: false
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.map(\.copyableIdentifier) == ["PUBC", "OTHR"])
        #expect(snapshot.openHoldings.map(\.isin) == [nil, nil])
        #expect(connector.calls.filter { $0 == "pdt-get-symbol" }.count == 1)
    }

    @Test("Live connector skips optional symbol lookup when holdings already include ISIN")
    func liveConnectorSkipsOptionalSymbolLookupWhenHoldingsAlreadyIncludeISIN() throws {
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(baseHoldingsJSON.utf8),
            "pdt-get-symbol-quote?id=1001": Data(#"{"id":1001,"code":"PUBC","symbolId":5001}"#.utf8),
        ])
        let snapshot = try PDTMCPConnectorDataSource(
            connector: connector,
            liveOptions: PDTLiveDataSourceOptions(
                includeDistributions: false,
                includeXRayHoldings: false,
                includeIncomeEvents: false,
                includeDividends: false,
                includeIncomeQuoteLookups: true,
                includePriceSeries: false
            )
        ).snapshot(asOf: "2026-06-26")

        #expect(snapshot.openHoldings.first?.copyableIdentifier == "PUBC")
        #expect(snapshot.openHoldings.first?.isin == "NL0010273215")
        #expect(connector.calls.filter { $0 == "pdt-get-symbol-quote" }.count == 1)
        #expect(connector.calls.filter { $0 == "pdt-get-symbol" }.isEmpty)
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

    @Test("Background detail refresh derives non-EUR portfolio currency from local worths")
    func backgroundDetailRefreshDerivesNonEURPortfolioCurrencyFromLocalWorths() throws {
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-base-normalization-background-currency-test")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let connector = ScriptedPDTMCPConnector(responses: [
            "pdt-get-portfolio-holdings": Data(nonEURPortfolioHoldingsJSON.utf8),
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
        #expect(snapshot.openHoldings.map(\.quoteId) == [6001, 6002])
        #expect(snapshot.totalValue == Money(value: "750.00", currency: "USD"))
    }

    private func model(_ fixtureName: String, withPrior: Bool = false) throws -> PortfolioPulseModel {
        let fixture = packageRoot.appending(path: "docs/pdt/fixtures/\(fixtureName).json")
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let prior = withPrior ? try? PDTFixtureDataSource.priorSnapshot(from: fixture) : nil
        return PressureEngine.buildModel(from: snapshot, priorSnapshot: prior)
    }

    private func testHolding(
        quoteId: Int,
        currentWorth: Money? = nil,
        localWorth: Money
    ) -> PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: "Test Holding \(quoteId)",
            quoteId: quoteId,
            currentPriceDate: "2026-06-26T21:59:00+00:00",
            currentPriceLocal: localWorth,
            currentWorth: currentWorth ?? localWorth,
            currentWorthLocal: localWorth,
            portfolioWeight: 0.5,
            closedAt: nil
        )
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func mcpTextContent(_ text: String, isError: Bool = false) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "isError": isError,
            "content": [
                [
                    "type": "text",
                    "text": text,
                ],
            ],
        ],
        options: [.sortedKeys]
    )
}

private func mcpDataObject(_ json: String) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONSerialization.data(
        withJSONObject: ["data": object],
        options: [.sortedKeys]
    )
}

private func mcpContentItems(_ content: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "isError": false,
            "content": content,
        ],
        options: [.sortedKeys]
    )
}

private func mcpResultObject(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: ["result": object],
        options: [.sortedKeys]
    )
}

private func largeWrappedHoldingsJSON() -> String {
    """
    {
      "metadata": {
        "padding": "\(String(repeating: "x", count: 220_000))"
      },
      "holdings": [
        {
          "symbolName": "Open Public Co",
          "symbolQuoteId": 1001,
          "currentPriceDate": "2026-06-26T21:59:00+00:00",
          "currentPriceLocal": { "value": "10.25", "currency": "EUR" },
          "currentWorth": { "value": "500.00", "currency": "EUR" },
          "currentWorthLocal": { "value": "500.00", "currency": "EUR" },
          "portfolioWeight": 0.25,
          "closedAt": null
        }
      ]
    }
    """
}

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
      "isin": "NL0010273215",
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
    },
    {
      "symbolName": "Negative Worth",
      "symbolQuoteId": 1005,
      "currentPriceDate": "2026-06-24T21:59:00+00:00",
      "currentPriceLocal": { "value": "2.00", "currency": "EUR" },
      "currentWorth": { "value": "-10.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "-10.00", "currency": "EUR" },
      "portfolioWeight": 0.05,
      "closedAt": null
    }
  ]
}
"""

private let multiCurrencyHoldingsJSON = """
{
  "holdings": [
    {
      "symbolName": "US Traded Co",
      "symbolQuoteId": 2001,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "347.66", "currency": "EUR" },
      "currentExchangeRate": 1.154,
      "currentWorth": { "value": "9347.40", "currency": "USD" },
      "currentWorthLocal": { "value": "8100.00", "currency": "EUR" },
      "portfolioWeight": 0.34,
      "closedAt": null
    },
    {
      "symbolName": "Danish Traded Co",
      "symbolQuoteId": 2002,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "25.00", "currency": "DKK" },
      "currentExchangeRate": 2.0,
      "currentWorth": { "value": "250.00", "currency": "DKK" },
      "currentWorthLocal": { "value": "250.00", "currency": "DKK" },
      "portfolioWeight": 0.66,
      "closedAt": null
    }
  ]
}
"""

private let nonEURPortfolioHoldingsJSON = """
{
  "holdings": [
    {
      "symbolName": "US Portfolio Holding",
      "symbolQuoteId": 6001,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "100.00", "currency": "USD" },
      "currentExchangeRate": 0.8,
      "currentWorth": { "value": "400.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "500.00", "currency": "USD" },
      "portfolioWeight": 0.67,
      "closedAt": null
    },
    {
      "symbolName": "Second US Portfolio Holding",
      "symbolQuoteId": 6002,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "25.00", "currency": "USD" },
      "currentWorth": { "value": "250.00", "currency": "USD" },
      "currentWorthLocal": { "value": "250.00", "currency": "USD" },
      "portfolioWeight": 0.33,
      "closedAt": null
    }
  ]
}
"""

private let twoOpenHoldingsJSON = """
{
  "holdings": [
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
      "symbolName": "Other Public Co",
      "symbolQuoteId": 1002,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
      "currentWorth": { "value": "250.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
      "portfolioWeight": 0.125,
      "closedAt": null
    }
  ]
}
"""

private let filteredLiveHoldingsJSON = """
{
  "holdings": [
    {
      "symbolName": "Open Public Co",
      "symbolQuoteId": 1001,
      "currentPriceDate": "2026-06-26T21:59:00+00:00",
      "currentPriceLocal": { "value": "10.25", "currency": "EUR" },
      "currentWorth": { "value": "500.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "500.00", "currency": "EUR" },
      "portfolioWeight": 0.10,
      "isin": "NL0010273215",
      "closedAt": null
    },
    {
      "symbolName": "Zero Worth",
      "symbolQuoteId": 1003,
      "currentPriceDate": "2026-06-24T21:59:00+00:00",
      "currentPriceLocal": { "value": "2.00", "currency": "EUR" },
      "currentWorth": { "value": "0.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "0.00", "currency": "EUR" },
      "portfolioWeight": 0.45,
      "closedAt": null
    },
    {
      "symbolName": "Negative Worth",
      "symbolQuoteId": 1005,
      "currentPriceDate": "2026-06-24T21:59:00+00:00",
      "currentPriceLocal": { "value": "2.00", "currency": "EUR" },
      "currentWorth": { "value": "-10.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "-10.00", "currency": "EUR" },
      "portfolioWeight": 0.50,
      "closedAt": null
    },
    {
      "symbolName": "Closed Co",
      "symbolQuoteId": 1002,
      "currentPriceDate": "2026-06-25T21:59:00+00:00",
      "currentPriceLocal": { "value": "1.00", "currency": "EUR" },
      "currentWorth": { "value": "0.00", "currency": "EUR" },
      "currentWorthLocal": { "value": "0.00", "currency": "EUR" },
      "portfolioWeight": 0.40,
      "closedAt": "2026-06-01T00:00:00+00:00"
    }
  ]
}
"""
