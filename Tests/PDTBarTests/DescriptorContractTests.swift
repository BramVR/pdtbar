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
            PDTLaunchMenu.descriptor(for: .checkingConnection),
            PDTLaunchMenu.descriptor(for: .connecting),
            PDTLaunchMenu.descriptor(for: .disconnecting),
            PDTLaunchMenu.descriptor(for: .notConnected(signInWouldBe: .saved)),
            PDTLaunchMenu.descriptor(for: .notConnected(signInWouldBe: .saved), notice: .signInFailed(.portBusy)),
            PDTLaunchMenu.descriptor(for: .notConnected(signInWouldBe: .saved), notice: .disconnected(revokeAt: PDTOAuthEndpoints.connectedApps)),
            PDTLaunchMenu.descriptor(for: .needsReconnect(.browserSession, .signInExpired)),
            PDTLaunchMenu.descriptor(for: .needsReconnect(.personalToken, .tokenRevoked)),
            PDTLaunchMenu.descriptor(for: .needsReconnect(.personalToken, .readAccessMissing)),
            PDTLaunchMenu.descriptor(for: .subscriptionPaused),
            PDTLaunchMenu.descriptor(for: .keychainUnavailable(.missingEntitlement)),
            PDTLaunchMenu.descriptor(for: .keychainUnavailable(.failed)),
            PDTLaunchMenu.descriptor(for: .connected(.fetching, .saved)),
            PDTLaunchMenu.descriptor(for: .connected(.failed, .saved)),
            PDTLaunchMenu.descriptor(for: .connected(.fetching, .thisSessionOnly(.missingEntitlement))),
            PDTLaunchMenu.descriptor(for: .connected(.failed, .thisSessionOnly(.failed))),
            quietDescriptor,
            nonQuietDescriptor,
        ]

        // Report only the broken rule and its location; echoing the copy could leak a token into CI logs.
        for (descriptorIndex, descriptor) in descriptors.enumerated() {
            for (textIndex, visibleText) in visibleMenuText(descriptor).enumerated() {
                let violation = visibleCopyRuleViolation(visibleText)
                #expect(violation == nil, "descriptor \(descriptorIndex), visible text \(textIndex)")
            }
        }
    }

    @Test("Visible copy may name a token but never internal terms or a token value")
    func visibleCopyRulesAllowTokenWordButNotTokenValues() {
        #expect(visibleCopyRuleViolation("Paste a read-only PDT token") == nil)
        #expect(visibleCopyRuleViolation("Token expires on 2027-11-09") == nil)
        #expect(visibleCopyRuleViolation("Sign in with PDT") == nil)
        #expect(visibleCopyRuleViolation("Connected with pdt_AbC123xyz") == "token-shaped value")
        #expect(visibleCopyRuleViolation("OAuth sign-in failed") == "forbidden term: oauth")
        #expect(visibleCopyRuleViolation("Paste your API key") == "forbidden term: api key")
        #expect(visibleCopyRuleViolation("Loaded fixture data") == "forbidden term: fixture")
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

// ADR-0002: "token" is allowed in setup and expiry copy; protocol jargon,
// internal tooling names, and anything shaped like a PDT token value are not.
private let forbiddenVisibleTerms = ["codex", "oauth", "api key", "fixture", "mcporter"]

/// Names the broken rule without echoing the copy, so a failure never prints a token value.
private func visibleCopyRuleViolation(_ value: String) -> String? {
    let lowered = value.lowercased()
    if let term = forbiddenVisibleTerms.first(where: { lowered.contains($0) }) {
        return "forbidden term: \(term)"
    }
    if value.range(of: #"pdt_[A-Za-z0-9]"#, options: .regularExpression) != nil {
        return "token-shaped value"
    }
    return nil
}

private func containsAdviceLikeLanguage(_ value: String) -> Bool {
    let pattern = #"\b(buy|sell|rebalance|trim|reduce|recommend|should)\b"#
    return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}
