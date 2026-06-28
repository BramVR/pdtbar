import Foundation
import Testing
import PDTBarCore

@Suite("Status visual")
struct StatusVisualTests {
    @Test("Decoded visual state normalizes bar shape and fill count")
    func decodedVisualStateNormalizesBarShapeAndFillCount() throws {
        let visual = try JSONDecoder().decode(
            StatusVisualState.self,
            from: Data("""
            {
              "barHeights": [0.9],
              "filledBarCount": 5,
              "isDimmed": true,
              "statusCopy": "Decoded status"
            }
            """.utf8)
        )

        #expect(visual.barHeights == [0.9, 1.0, 0.667])
        #expect(visual.filledBarCount == 3)
        #expect(visual.isDimmed)
        #expect(visual.statusCopy == "Decoded status")
    }

    @Test("Attention count fills notification bars without changing concentration silhouette")
    func attentionCountFillsNotificationBarsWithoutChangingConcentrationSilhouette() throws {
        let baseModel = PressureEngine.buildModel(from: try fixtureSnapshot("quiet-no-pressure.json"))
        let baseHeights = MenuDescriptorRenderer.render(model: baseModel).statusVisual.barHeights
        let attention = AttentionItem(
            id: "allocation.nova",
            facet: "allocation",
            rank: 1,
            title: "Nova concentration",
            severity: "medium",
            score: 0.7,
            supportingDataSlotIDs: ["allocation.holdings"]
        )

        var twoAttentionModel = baseModel
        twoAttentionModel.allQuiet = false
        twoAttentionModel.attentionItems = [attention, attention]
        twoAttentionModel.rankedAttentionItems = [attention, attention]
        let twoAttentionVisual = MenuDescriptorRenderer.render(model: twoAttentionModel).statusVisual

        var crowdedAttentionModel = baseModel
        crowdedAttentionModel.allQuiet = false
        crowdedAttentionModel.attentionItems = [attention, attention, attention, attention]
        crowdedAttentionModel.rankedAttentionItems = [attention, attention, attention, attention]
        let crowdedVisual = MenuDescriptorRenderer.render(model: crowdedAttentionModel).statusVisual

        #expect(twoAttentionVisual.filledBarCount == 2)
        #expect(twoAttentionVisual.barHeights == baseHeights)
        #expect(crowdedVisual.filledBarCount == 3)
        #expect(crowdedVisual.barHeights == baseHeights)
    }

    @Test("X-ray look-through weights scale side bars only")
    func xRayLookThroughWeightsScaleSideBarsOnly() throws {
        var model = PressureEngine.buildModel(from: try fixtureSnapshot("quiet-no-pressure.json"))
        model.facetSnapshots.allocation.openHoldingCount = 2
        model.facetSnapshots.allocation.topHoldings = Array(model.facetSnapshots.allocation.topHoldings.prefix(2))
        model.facetSnapshots.allocation.topHoldings[0].weight = 0.5
        model.facetSnapshots.allocation.topHoldings[1].weight = 0.5

        let directHeights = MenuDescriptorRenderer.render(model: model).statusVisual.barHeights

        var diversifiedXRayModel = model
        diversifiedXRayModel.facetSnapshots.allocation.xRayHoldings = [
            XRayHoldingSummary(weight: 0.12),
            XRayHoldingSummary(weight: 0.10),
            XRayHoldingSummary(weight: 0.08),
            XRayHoldingSummary(weight: 0.05),
        ]
        let diversifiedHeights = MenuDescriptorRenderer.render(model: diversifiedXRayModel).statusVisual.barHeights

        var concentratedXRayModel = model
        concentratedXRayModel.facetSnapshots.allocation.xRayHoldings = [
            XRayHoldingSummary(weight: 0.5),
            XRayHoldingSummary(weight: 0.5),
        ]
        let concentratedHeights = MenuDescriptorRenderer.render(model: concentratedXRayModel).statusVisual.barHeights

        var skewedXRayModel = model
        skewedXRayModel.facetSnapshots.allocation.xRayHoldings = [
            XRayHoldingSummary(weight: 0.62),
            XRayHoldingSummary(weight: 0.18),
            XRayHoldingSummary(weight: 0.10),
            XRayHoldingSummary(weight: 0.06),
            XRayHoldingSummary(weight: 0.04),
        ]
        let skewedHeights = MenuDescriptorRenderer.render(model: skewedXRayModel).statusVisual.barHeights

        #expect(directHeights == StatusVisualState().barHeights)
        #expect(diversifiedHeights[0] != directHeights[0])
        #expect(diversifiedHeights[2] > diversifiedHeights[0])
        #expect(diversifiedHeights[1] == 1.0)
        #expect(concentratedHeights[0] < diversifiedHeights[0])
        #expect(concentratedHeights[2] < diversifiedHeights[2])
        #expect(concentratedHeights[1] == 1.0)
        #expect(skewedHeights[0] < diversifiedHeights[0])
        #expect(skewedHeights[2] > skewedHeights[0])
        #expect(skewedHeights[1] == 1.0)
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func fixtureSnapshot(_ name: String) throws -> PortfolioSnapshot {
    try PDTFixtureDataSource.snapshot(from: packageRoot.appending(path: "docs/pdt/fixtures/\(name)"))
}
