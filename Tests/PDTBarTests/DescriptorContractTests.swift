import Foundation
import Testing
import PDTBarCore

@Suite("Descriptor contract")
struct DescriptorContractTests {
    @Test("Fixture corpus round-trips through model JSON and descriptor contracts")
    func fixtureCorpusRoundTripsThroughModelJSONAndDescriptorContracts() throws {
        for fixture in fixtureNames {
            let snapshot = try PDTFixtureDataSource.snapshot(from: fixtureURL(fixture))
            let model = PressureEngine.buildModel(from: snapshot)
            let decoded = try JSONDecoder().decode(
                PortfolioPulseModel.self,
                from: try stableJSONData(model)
            )
            let descriptor = MenuDescriptorRenderer.render(model: decoded)
            let rows = descriptor.sections.flatMap(\.rows)

            #expect(!descriptor.sections.isEmpty)
            #expect(descriptor.statusAccessibilityIdentifier == "pdtbar.status")
            #expect(descriptor.sections.allSatisfy { !$0.id.isEmpty })
            #expect(descriptor.sections.allSatisfy { $0.accessibilityIdentifier == "pdtbar.section.\($0.id)" })
            #expect(rows.allSatisfy { !$0.id.isEmpty })
            #expect(rows.allSatisfy { $0.accessibilityIdentifier == "pdtbar.row.\($0.id)" })
            #expect(rows.allSatisfy { $0.role != .row })
            #expect(Set(rows.map(\.id)).count == rows.count)
            #expect(decoded.supportingDataSlots.map(\.id).contains("allocation.overview"))
            #expect(decoded.supportingDataSlots.count == 5)
            #expect(!decoded.facetSnapshots.allocation.totalValue.value.contains(","))
            #expect(renderedCopy(from: decoded, descriptor: descriptor).allSatisfy { !containsAdviceLikeLanguage($0) })
        }
    }

    @Test("Legacy descriptor JSON keeps compatibility defaults")
    func legacyDescriptorJSONKeepsCompatibilityDefaults() throws {
        let legacyAttention = try JSONDecoder().decode(
            AttentionItem.self,
            from: Data("""
            {
              "id": "allocation.legacy",
              "facet": "allocation",
              "rank": 1,
              "title": "Legacy allocation",
              "severity": "medium",
              "score": 0.5,
              "supportingDataSlotIDs": []
            }
            """.utf8)
        )
        let legacyMenuRow = try JSONDecoder().decode(
            MenuRow.self,
            from: Data("""
            {
              "title": "Legacy row",
              "detail": "Descriptor row before id and role existed"
            }
            """.utf8)
        )
        let legacyQuietMenuRow = try JSONDecoder().decode(
            MenuRow.self,
            from: Data("""
            {
              "id": "quiet",
              "role": "glance",
              "title": "All quiet"
            }
            """.utf8)
        )

        #expect(legacyAttention.detail == "")
        #expect(legacyMenuRow.id == "")
        #expect(legacyMenuRow.role == .row)
        #expect(legacyQuietMenuRow.role == .pulseQuiet)
    }

    @Test("User-facing launch descriptors avoid internal setup terms")
    func userFacingLaunchDescriptorsAvoidInternalSetupTerms() throws {
        let quietDescriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: fixtureURL("quiet-no-pressure.json")))
        )
        let nonQuietDescriptor = MenuDescriptorRenderer.render(
            model: PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: fixtureURL("concentration-pressure.json")))
        )
        let descriptors = [
            ClaudeSetupMenuDescriptor.loggedOut(),
            ClaudeLaunchFlow.descriptor(for: .openingClaude),
            ClaudeLaunchFlow.descriptor(for: .missingClaude),
            ClaudeLaunchFlow.descriptor(for: .probingClaude),
            ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio),
            ClaudeLaunchFlow.descriptor(for: .probeFailed),
            ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed),
            ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin),
            ClaudeLaunchFlow.descriptor(for: .missingPDTMCP),
            quietDescriptor,
            nonQuietDescriptor,
        ]
        let forbiddenVisibleTerms = ["codex", "oauth", "api key", "token", "fixture", "mcporter"]

        for visibleText in descriptors.flatMap(visibleMenuText) {
            let lowered = visibleText.lowercased()
            #expect(forbiddenVisibleTerms.allSatisfy { !lowered.contains($0) })
        }
    }
}

private let fixtureNames = [
    "concentration-pressure.json",
    "income-event.json",
    "big-mover.json",
    "quiet-no-pressure.json",
]

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func fixtureURL(_ name: String) -> URL {
    packageRoot.appending(path: "docs/pdt/fixtures/\(name)")
}

private func renderedCopy(from model: PortfolioPulseModel, descriptor: MenuDescriptor) -> [String] {
    var copy: [String?] = [
        model.allQuietSignal.title,
        model.allQuietSignal.detail,
        descriptor.statusTitle,
    ]
    copy.append(contentsOf: model.rankedAttentionItems.flatMap {
        [$0.title, $0.detail]
    })
    copy.append(contentsOf: model.supportingDataSlots.map(\.label))
    copy.append(contentsOf: descriptor.sections.map(\.title))
    copy.append(contentsOf: descriptor.sections.flatMap { visibleMenuText($0.rows) })
    return copy.compactMap { $0 }.filter { !$0.isEmpty }
}

private func visibleMenuText(_ descriptor: MenuDescriptor) -> [String] {
    [descriptor.statusTitle] + descriptor.sections.flatMap { section in
        [section.title] + visibleMenuText(section.rows)
    }
}

private func visibleMenuText(_ rows: [MenuRow]) -> [String] {
    rows.flatMap { row in
        [row.title, row.detail].compactMap { $0 } + visibleMenuText(row.children)
    }
}

private func containsAdviceLikeLanguage(_ value: String) -> Bool {
    let pattern = #"\b(buy|sell|rebalance|trim|reduce|recommend|should)\b"#
    return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}
