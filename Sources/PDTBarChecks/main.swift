import Foundation
import PDTBarCore

let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fixture = packageRoot.appending(path: "docs/pdt/fixtures/quiet-no-pressure.json")
let allFixtures = [
    "concentration-pressure.json",
    "income-event.json",
    "big-mover.json",
    "quiet-no-pressure.json",
].map { packageRoot.appending(path: "docs/pdt/fixtures/\($0)") }

let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
let model = PressureEngine.buildModel(from: snapshot)
let modelJSON = try stableJSONData(model)
let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: modelJSON)
try check(decoded.allQuiet, "quiet fixture should set allQuiet=true")
try check(decoded.attentionItems == [], "quiet fixture should emit no attention items")
try check(decoded.rankedAttentionItems == [], "quiet fixture should emit no ranked attention items")
try check(decoded.facetSnapshots.allocation.openHoldingCount == 9, "quiet fixture should load holdings")
try check(decoded.portfolioGlance.openHoldingCount == 9, "quiet model should expose open holding count glance context")
try check(decoded.portfolioGlance.totalValue == Money(value: "51200.00", currency: "EUR"), "quiet model should expose total value glance context")
try check(decoded.portfolioGlance.worstPriceAsOf == "2026-06-22", "quiet model should expose price freshness glance context")
try check(!decoded.facetSnapshots.freshness.stale, "quiet model should expose fresh EOD state")
try check(decoded.supportingDataSlots.map(\.id).contains("bigMovers.prices"), "model should expose supporting data slots")
var legacyModelObject = try require(
    JSONSerialization.jsonObject(with: modelJSON) as? [String: Any],
    "model JSON should decode as an object for legacy compatibility check"
)
legacyModelObject.removeValue(forKey: "portfolioGlance")
let legacyModelWithoutGlance = try JSONDecoder().decode(
    PortfolioPulseModel.self,
    from: JSONSerialization.data(withJSONObject: legacyModelObject, options: [.sortedKeys])
)
try check(
    legacyModelWithoutGlance.portfolioGlance.openHoldingCount == 9,
    "legacy v1 model JSON should default open holding glance context"
)
try check(
    legacyModelWithoutGlance.portfolioGlance.worstPriceAsOf == "2026-06-22",
    "legacy v1 model JSON should default freshness glance context"
)
let legacyConstructedModel = PortfolioPulseModel(
    asOf: decoded.asOf,
    allQuiet: decoded.allQuiet,
    allQuietSignal: decoded.allQuietSignal,
    rankedAttentionItems: decoded.rankedAttentionItems,
    facetSnapshots: decoded.facetSnapshots,
    supportingDataSlots: decoded.supportingDataSlots
)
try check(
    legacyConstructedModel.portfolioGlance.openHoldingCount == 9,
    "legacy model initializer should default open holding glance context"
)

let descriptor = MenuDescriptorRenderer.render(model: decoded)
let launchSurface = MenuBarSurfaceRenderer.render(descriptor: descriptor)
let noArgumentLaunch = try PDTBarLaunchOptionParser.parse(
    arguments: [],
    environment: [
        "PDTBAR_APP_SUPPORT_DIR": "/tmp/pdtbar-checks-app-support",
        "PDTBAR_FIXTURE": fixture.path,
    ]
)
try check(
    noArgumentLaunch.mode == .claudeFirst,
    "no-argument launch should enter real Claude-first mode, not fixture mode"
)
try check(
    noArgumentLaunch.snapshotDirectory == nil,
    "no-argument launch should not inherit fixture snapshot state"
)
try check(
    noArgumentLaunch.appSupportDirectory == URL(fileURLWithPath: "/tmp/pdtbar-checks-app-support"),
    "no-argument launch should allow isolated real app state"
)
let fixtureLaunch = try PDTBarLaunchOptionParser.parse(arguments: ["--fixture", fixture.path], environment: [:])
try check(
    fixtureLaunch.mode == .fixture(fixture),
    "fixture launch should require explicit --fixture"
)
try check(
    fixtureLaunch.snapshotDirectory == nil,
    "fixture launch should not require real app state"
)
let setupDescriptor = ClaudeSetupMenuDescriptor.loggedOut()
let setupSurface = MenuBarSurfaceRenderer.render(descriptor: setupDescriptor)
let openingClaudeDescriptor = ClaudeLaunchFlow.descriptor(for: .openingClaude)
let missingClaudeDescriptor = ClaudeLaunchFlow.descriptor(for: .missingClaude)
let probingDescriptor = ClaudeLaunchFlow.descriptor(for: .probingClaude)
let probingSurface = MenuBarSurfaceRenderer.render(descriptor: probingDescriptor)
try check(
    ClaudeLaunchFlow.state(afterReadinessProbe: nil) == .probingClaude,
    "real launch should enter an explicit Claude probing state before setup UI"
)
try check(
    probingDescriptor.statusTitle == "Checking Claude",
    "Claude probing state should have distinct status copy"
)
try check(
    probingDescriptor.statusVisual.isDimmed && probingDescriptor.statusVisual.filledBarCount == 0,
    "Claude probing state should dim the icon without filling notification bars"
)
try check(
    probingSurface.sections.flatMap(\.rows).map(\.title) == ["Checking Claude setup - No prompts opened"],
    "Claude probing state should not show login UI yet"
)
try check(
    ClaudeLaunchFlow.state(afterReadinessProbe: .ready) == .fetchingPortfolio,
    "ready Claude/PDT probe should transition toward first fetch"
)
try check(
    ClaudeLaunchFlow.state(afterReadinessProbe: .missingClaudeLogin) == .missingClaudeLogin,
    "missing Claude login probe should transition to a retryable signed-out setup state"
)
try check(
    ClaudeLaunchFlow.state(afterReadinessProbe: .missingPDTMCP) == .missingPDTMCP,
    "missing PDT MCP probe should transition to a retryable PDT setup state"
)
let firstFetchDescriptor = ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio)
try check(
    firstFetchDescriptor.statusVisual.isDimmed && firstFetchDescriptor.statusVisual.filledBarCount == 0,
    "first-fetch state should dim the icon without filling notification bars"
)
try check(
    firstFetchDescriptor.sections.flatMap(\.rows).map(\.title) == ["Fetching portfolio"],
    "first-fetch state should render without the logged-out menu"
)
try check(
    !firstFetchDescriptor.sections.flatMap(\.rows).map(\.title).contains("Log in with Claude"),
    "ready launch should skip visible login UI"
)
try check(
    ClaudeLaunchFlow.state(afterReadinessProbe: .failed) == .probeFailed,
    "probe failures should be represented as an explicit launch state"
)
let probeFailedDescriptor = ClaudeLaunchFlow.descriptor(for: .probeFailed)
try check(
    probeFailedDescriptor.sections.flatMap(\.rows).map(\.title).contains("Could not check Claude"),
    "probe failure state should explain that readiness could not be checked"
)
let fetchFailedDescriptor = ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed)
try check(
    fetchFailedDescriptor.sections.flatMap(\.rows).map(\.title) == ["Could not fetch portfolio", "Try again"],
    "first-fetch failure should show a retry action without publishing a portfolio pulse"
)
try check(
    MenuBarSurfaceRenderer.render(descriptor: fetchFailedDescriptor).status.visual.isDimmed,
    "first-fetch failure may dim the status icon without changing attention fill"
)
let cachedRefreshDescriptor = ClaudeLaunchFlow.descriptor(for: .fetchingPortfolio, cachedPulse: descriptor)
try check(
    cachedRefreshDescriptor.statusTitle == descriptor.statusTitle
        && cachedRefreshDescriptor.sections.map(\.id).contains("pulse")
        && cachedRefreshDescriptor.sections.flatMap(\.rows).map(\.title).contains("Refreshing portfolio"),
    "returning launch should keep the cached pulse visible while a refresh is running"
)
let cachedFailureDescriptor = ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed, cachedPulse: descriptor)
try check(
    cachedFailureDescriptor.statusTitle == descriptor.statusTitle
        && cachedFailureDescriptor.sections.map(\.id).contains("pulse")
        && cachedFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Could not fetch portfolio")
        && cachedFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Try again"),
    "returning launch fetch failure should preserve the cached pulse and expose retry"
)
try check(
    cachedFailureDescriptor.statusVisual.isDimmed
        && cachedFailureDescriptor.statusVisual.barHeights == descriptor.statusVisual.barHeights
        && cachedFailureDescriptor.statusVisual.filledBarCount == descriptor.statusVisual.filledBarCount,
    "returning launch fetch failure should dim the icon while preserving cached concentration shape and fill"
)
try check(
    setupDescriptor.sections.map(\.id) == ["claudeSetup"],
    "logged-out real launch should render a Claude-only setup section"
)
try check(
    setupSurface.sections.flatMap(\.rows).map(\.title) == ["Not connected - Use Claude Desktop for PDT", "Log in with Claude"],
    "logged-out real launch should render Claude setup status and login rows"
)
try check(
    openingClaudeDescriptor.sections.flatMap(\.rows).map(\.title) == ["Opening Claude Desktop"],
    "login handoff should render progress while Claude Desktop is opening"
)
try check(
    missingClaudeDescriptor.sections.flatMap(\.rows).map(\.title) == ["Claude Desktop not found", "Log in with Claude"],
    "failed login handoff should render missing-Claude setup state with a retryable login action"
)
let missingLoginDescriptor = ClaudeLaunchFlow.descriptor(for: .missingClaudeLogin)
try check(
    missingLoginDescriptor.sections.flatMap(\.rows).map(\.title) == ["Not connected", "Log in with Claude", "Check again"],
    "missing Claude login should render signed-out setup copy with a readiness retry action"
)
try check(
    missingLoginDescriptor.sections.flatMap(\.rows).last?.role == .setupRetry,
    "missing Claude login Check again row should rerun readiness instead of login handoff"
)
let missingPDTMCPDescriptor = ClaudeLaunchFlow.descriptor(for: .missingPDTMCP)
try check(
    missingPDTMCPDescriptor.sections.flatMap(\.rows).map(\.title) == ["Add the PDT MCP server in Claude Desktop", "Check again"],
    "missing PDT MCP should render product-facing setup copy with a readiness retry action"
)
try check(
    missingPDTMCPDescriptor.sections.flatMap(\.rows).last?.role == .setupRetry,
    "missing PDT MCP Check again row should rerun readiness instead of login handoff"
)
let readinessProbeGate = ClaudeReadinessProbeGate()
try check(readinessProbeGate.begin(), "readiness probe gate should allow the first setup probe")
try check(!readinessProbeGate.begin(), "readiness probe gate should reject duplicate concurrent setup probes")
readinessProbeGate.finish()
try check(readinessProbeGate.begin(), "readiness probe gate should allow Check again after the prior probe finishes")
readinessProbeGate.finish()
let descriptorObject = try require(
    JSONSerialization.jsonObject(with: try stableJSONData(descriptor)) as? [String: Any],
    "descriptor JSON should encode as an object"
)
try check(
    descriptor.statusTitle == "EUR 51,200.00 - All quiet",
    "quiet fixture descriptor should render the all-quiet status"
)
try check(
    descriptor.statusVisual.filledBarCount == 0,
    "quiet descriptor should expose zero filled notification bars"
)
try check(!descriptor.statusVisual.isDimmed, "quiet descriptor should not dim a fresh status icon")
try check(descriptor.statusVisual.statusCopy == descriptor.statusTitle, "quiet descriptor visual should expose full status copy")
try check(descriptor.statusVisual.barHeights.count == 3, "quiet descriptor should expose three concentration bars")
try check(descriptorObject.keys.contains("statusBadge"), "descriptor JSON should explicitly encode statusBadge")
try check(descriptorObject.keys.contains("statusVisual"), "descriptor JSON should encode the plain status visual state")
try check(descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness"], "descriptor should expose drill-down sections")
try check(
    descriptor.statusAccessibilityIdentifier == "pdtbar.status",
    "descriptor should expose a stable status accessibility identifier"
)
try check(
    launchSurface.status.title == "EUR 51,200.00 - All quiet",
    "fixture launch surface should render the descriptor status title"
)
try check(
    launchSurface.status.badge == nil,
    "quiet fixture launch surface should preserve an empty descriptor badge"
)
try check(
    launchSurface.status.menuBarTitle.isEmpty,
    "fixture launch surface should not expose status text as menu-bar title"
)
try check(
    launchSurface.status.visual == descriptor.statusVisual,
    "fixture launch surface should preserve core status visual state for AppKit drawing"
)
let shortVisual = try JSONDecoder().decode(
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
try check(
    shortVisual.barHeights == [0.9, 0.45, 0.45]
        && shortVisual.filledBarCount == 3
        && shortVisual.isDimmed
        && shortVisual.statusCopy == "Decoded status",
    "decoded status visual state should preserve its normalized plain state"
)
try check(
    launchSurface.status.accessibilityIdentifier == "pdtbar.status",
    "fixture launch surface should preserve the status accessibility identifier"
)
try check(
    launchSurface.sections.map(\.accessibilityIdentifier) == descriptor.sections.map(\.accessibilityIdentifier),
    "fixture launch surface should preserve descriptor section selectors"
)
try check(
    launchSurface.sections.flatMap(\.rows).map(\.accessibilityIdentifier)
        == descriptor.sections.flatMap(\.rows).map(\.accessibilityIdentifier),
    "fixture launch surface should preserve descriptor row selectors"
)
try check(
    launchSurface.sections.first { $0.id == "pulse" }?.rows.first?.title
        == "EUR 51,200.00 - All quiet",
    "fixture launch surface should put displaced status copy in the top Pulse row"
)
try check(
    descriptor.sections.first { $0.id == "pulse" }?.rows.dropFirst().first?.children.map(\.id)
        == ["pulse.quiet.value", "pulse.quiet.holdings", "pulse.quiet.freshness"],
    "quiet pulse row should expose compact nested readouts"
)
try check(
    descriptor.sections.map(\.accessibilityIdentifier) == [
        "pdtbar.section.pulse",
        "pdtbar.section.allocation",
        "pdtbar.section.income",
        "pdtbar.section.bigMovers",
        "pdtbar.section.freshness",
    ],
    "descriptor should expose stable section accessibility identifiers"
)
let quietPulseRow = try require(
    descriptor.sections.first { $0.id == "pulse" }?.rows.first { $0.id == "pulse.quiet" },
    "quiet descriptor should expose the pulse quiet row by stable id"
)
try check(quietPulseRow.role == .pulseQuiet, "quiet pulse row should expose a typed role")
try check(
    quietPulseRow.accessibilityIdentifier == "pdtbar.row.pulse.quiet",
    "quiet pulse row should expose a stable accessibility identifier"
)
try check(
    descriptor.sections.first { $0.id == "income" }?.rows.map(\.id) == ["income.empty"],
    "quiet income rows should expose stable ids"
)
try check(
    descriptor.sections.first { $0.id == "income" }?.rows.first?.detail == "No calendar events in the next window",
    "quiet income empty state should avoid developer fixture copy"
)
try check(
    descriptor.sections.first { $0.id == "bigMovers" }?.rows.map(\.id) == ["bigMovers.summary"],
    "quiet big-mover rows should expose stable ids"
)
try check(
    descriptor.sections.first { $0.id == "freshness" }?.rows.map(\.id) == ["freshness.summary"],
    "quiet freshness rows should expose stable ids"
)
try check(
    descriptor.sections.first { $0.id == "freshness" }?.rows.first?.detail == "Fresh",
    "quiet descriptor should render freshness from model facts"
)

let zeroWorthFixtureDirectory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-zero-worth-fixture")
defer {
    try? FileManager.default.removeItem(at: zeroWorthFixtureDirectory.directory)
}
let zeroWorthFixture = zeroWorthFixtureDirectory.directory.appending(path: "zero-worth-open-holding.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Live Holding",
        "symbolQuoteId": 9101,
        "currentPriceDate": "2026-06-21T23:59:59+00:00",
        "currentPriceLocal": { "value": "155.74", "currency": "EUR" },
        "currentWorth": { "value": "1557.42", "currency": "EUR" },
        "currentWorthLocal": { "value": "1557.42", "currency": "EUR" },
        "portfolioWeight": 0.1557,
        "closedAt": null
      },
      {
        "symbolName": "Zero Worth Open Holding",
        "symbolQuoteId": 9102,
        "currentPriceDate": "2026-06-20T23:59:59+00:00",
        "currentPriceLocal": { "value": "10.00", "currency": "EUR" },
        "currentWorth": { "value": "0.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "0.00", "currency": "EUR" },
        "portfolioWeight": 0.0443,
        "closedAt": null
      }
    ]
  }
}
""".utf8).write(to: zeroWorthFixture)
let zeroWorthSnapshot = try PDTFixtureDataSource.snapshot(from: zeroWorthFixture)
try check(
    zeroWorthSnapshot.openHoldings.map(\.name) == ["Live Holding"],
    "zero currentWorth holdings should be excluded from live portfolio facts"
)
try check(
    zeroWorthSnapshot.openHoldings.first?.worth == Money(value: "1557.42", currency: "EUR"),
    "PDT Money objects should parse into currency-aware facts"
)
try check(
    zeroWorthSnapshot.openHoldings.first?.weight == 0.1557,
    "portfolioWeight should remain a fraction"
)
try check(
    zeroWorthSnapshot.openHoldings.first?.priceAsOf == "2026-06-21",
    "currentPriceDate should expose EOD freshness day"
)

let emptyHoldingsFixture = zeroWorthFixtureDirectory.directory.appending(path: "empty-open-holdings.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": { "holdings": [] }
}
""".utf8).write(to: emptyHoldingsFixture)
let emptyHoldingsModel = PressureEngine.buildModel(
    from: try PDTFixtureDataSource.snapshot(from: emptyHoldingsFixture)
)
try check(
    !emptyHoldingsModel.facetSnapshots.freshness.stale,
    "empty open holdings should preserve the previous non-stale freshness behavior"
)

let weekendFreshnessFixture = zeroWorthFixtureDirectory.directory.appending(path: "weekend-freshness.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Weekend Holding",
        "symbolQuoteId": 9103,
        "currentPriceDate": "2026-06-19T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "1000.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "1000.00", "currency": "EUR" },
        "portfolioWeight": 0.10,
        "closedAt": null
      }
    ]
  }
}
""".utf8).write(to: weekendFreshnessFixture)
let weekendFreshnessModel = PressureEngine.buildModel(
    from: try PDTFixtureDataSource.snapshot(from: weekendFreshnessFixture)
)
try check(
    !weekendFreshnessModel.facetSnapshots.freshness.stale,
    "normal weekend business-day price lag should not mark EOD freshness stale"
)

var nonQuietModel = decoded
let attention = AttentionItem(
    id: "allocation.nova",
    facet: "allocation",
    rank: 1,
    title: "Nova concentration",
    severity: "medium",
    score: 0.7,
    supportingDataSlotIDs: ["allocation.holdings"]
)
let secondAttention = AttentionItem(
    id: "income.helix",
    facet: "income",
    rank: 2,
    title: "Helix ex-dividend",
    severity: "low",
    score: 0.45,
    supportingDataSlotIDs: ["income.calendar"]
)
let thirdAttention = AttentionItem(
    id: "bigMovers.orbit",
    facet: "bigMovers",
    rank: 3,
    title: "Orbit moved +11.0%",
    severity: "medium",
    score: 0.55,
    supportingDataSlotIDs: ["bigMovers.prices"]
)
let fourthAttention = AttentionItem(
    id: "income.nova",
    facet: "income",
    rank: 4,
    title: "Nova payment landed",
    severity: "low",
    score: 0.35,
    supportingDataSlotIDs: ["income.calendar"]
)
nonQuietModel.allQuiet = false
nonQuietModel.attentionItems = [attention]
nonQuietModel.rankedAttentionItems = [attention]
let nonQuietDescriptor = MenuDescriptorRenderer.render(model: nonQuietModel)
try check(
    nonQuietDescriptor.statusTitle == "EUR 51,200.00 - Nova concentration",
    "non-quiet descriptor should use the top attention item in status"
)
try check(
    nonQuietDescriptor.sections.first { $0.id == "pulse" }?.rows.dropFirst().first?.children.isEmpty == false,
    "attention pulse rows should expose nested drill-down readouts instead of flat expansion rows"
)
try check(
    nonQuietDescriptor.statusVisual.filledBarCount == 1,
    "one attention item should fill one notification bar"
)
var twoAttentionModel = decoded
twoAttentionModel.allQuiet = false
twoAttentionModel.attentionItems = [attention, secondAttention]
twoAttentionModel.rankedAttentionItems = [attention, secondAttention]
try check(
    MenuDescriptorRenderer.render(model: twoAttentionModel).statusVisual.filledBarCount == 2,
    "two attention items should fill two notification bars"
)
var crowdedAttentionModel = decoded
crowdedAttentionModel.allQuiet = false
crowdedAttentionModel.attentionItems = [attention, secondAttention, thirdAttention, fourthAttention]
crowdedAttentionModel.rankedAttentionItems = [attention, secondAttention, thirdAttention, fourthAttention]
try check(
    MenuDescriptorRenderer.render(model: crowdedAttentionModel).statusVisual.filledBarCount == 3,
    "three or more attention items should cap at three filled notification bars"
)

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
try check(legacyAttention.detail == "", "legacy attention JSON should default missing detail")

let legacyMenuRow = try JSONDecoder().decode(
    MenuRow.self,
    from: Data("""
    {
      "title": "Legacy row",
      "detail": "Descriptor row before id and role existed"
    }
    """.utf8)
)
try check(legacyMenuRow.id == "", "legacy menu row JSON should default missing id")
try check(legacyMenuRow.role == .row, "legacy menu row JSON should default missing role")
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
try check(legacyQuietMenuRow.role == .pulseQuiet, "legacy quiet glance row should decode as typed quiet role")

var incompleteAllocationModel = decoded
let incompleteAllocationAttention = AttentionItem(
    id: "allocation.incomplete",
    facet: "allocation",
    rank: 1,
    title: "Nova incomplete concentration",
    severity: "medium",
    score: 0.5,
    holdingIdentity: HoldingIdentity(name: "Nova Lithography", quoteId: 9001),
    supportingDataSlotIDs: ["allocation.holdings"]
)
incompleteAllocationModel.allQuiet = false
incompleteAllocationModel.attentionItems = [incompleteAllocationAttention]
incompleteAllocationModel.rankedAttentionItems = [incompleteAllocationAttention]
let incompleteAllocationRow = try require(
    MenuDescriptorRenderer.render(model: incompleteAllocationModel)
        .sections
        .first { $0.id == "allocation" }?
        .rows
        .first { $0.title == "Nova Lithography" },
    "allocation row should exist for incomplete attention metadata"
)
try check(
    incompleteAllocationRow.role == .allocationHolding
        && incompleteAllocationRow.detail == "11.7% of portfolio",
    "allocation drill-down should fall back when current weight or threshold is missing"
)

let userFacingDescriptors = [
    setupDescriptor,
    openingClaudeDescriptor,
    missingClaudeDescriptor,
    probingDescriptor,
    firstFetchDescriptor,
    probeFailedDescriptor,
    fetchFailedDescriptor,
    missingLoginDescriptor,
    missingPDTMCPDescriptor,
    descriptor,
    nonQuietDescriptor,
]
let forbiddenVisibleTerms = ["codex", "oauth", "api key", "token", "fixture", "mcporter"]
for visibleText in userFacingDescriptors.flatMap(visibleMenuText) {
    let lowered = visibleText.lowercased()
    for term in forbiddenVisibleTerms {
        try check(
            !lowered.contains(term),
            "Claude-first menu copy should not expose \(term): \(visibleText)"
        )
    }
}

let concentrationFixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
let snapshotDirectory = FileManager.default.temporaryDirectory
    .appending(path: "pdtbar-checks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: snapshotDirectory)
}

let emptySnapshotStore = try SnapshotStore.temporaryTestStore()
defer {
    try? FileManager.default.removeItem(at: emptySnapshotStore.directory)
}
let missingPriorSnapshot = try emptySnapshotStore.loadPriorSnapshot()
try check(
    missingPriorSnapshot == nil,
    "temp-dir SnapshotStore should load nil when no prior snapshot exists"
)
let quietSnapshotStore = try SnapshotStore.temporaryTestStore()
defer {
    try? FileManager.default.removeItem(at: quietSnapshotStore.directory)
}
let quietSnapshot = try PDTFixtureDataSource.snapshot(from: fixture)
let quietCommit = try quietSnapshotStore.commitCurrentSnapshot(quietSnapshot)
try check(quietCommit.written, "SnapshotStore should commit the current snapshot")
try check(
    FileManager.default.fileExists(atPath: quietCommit.path),
    "SnapshotStore commit should write the latest snapshot file"
)
let loadedQuietSnapshot = try quietSnapshotStore.loadPriorSnapshot()
try check(
    loadedQuietSnapshot == quietSnapshot,
    "SnapshotStore should load the committed snapshot as the prior snapshot"
)
let quietFixtureDataSource = PDTFixtureDataSource(fixture: fixture)
let quietRunFromDataSource = try PressureRunner.run(
    dataSource: quietFixtureDataSource,
    snapshotStore: quietSnapshotStore
)
try check(
    quietRunFromDataSource.model.allQuiet,
    "PressureRunner should run from a PortfolioDataSource adapter"
)
try check(
    quietRunFromDataSource.descriptor.statusTitle == "EUR 51,200.00 - All quiet",
    "PortfolioDataSource runner path should preserve fixture descriptor behavior"
)

let scriptedLiveStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-live-check")
defer {
    try? FileManager.default.removeItem(at: scriptedLiveStore.directory)
}
let scriptedConnectorResponses = [
    "pdt-get-portfolio-holdings": try mcpContent("""
    {
      "holdings": [
        {
          "symbolName": "Live Adapter Co",
          "symbolQuoteId": 9101,
          "currentPriceDate": "2026-06-22T22:00:00+00:00",
          "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
          "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
          "portfolioWeight": 0.25,
          "closedAt": null
        },
        {
          "symbolName": "Closed Adapter Co",
          "symbolQuoteId": 9102,
          "currentPriceDate": "2026-06-22T22:00:00+00:00",
          "currentPriceLocal": { "value": "0.00", "currency": "EUR" },
          "currentWorthLocal": { "value": "0.00", "currency": "EUR" },
          "portfolioWeight": 0.0,
          "closedAt": "2026-06-01T00:00:00+00:00"
        }
      ]
    }
    """),
    "pdt-get-portfolio-distributions": try mcpResult("""
    {
      "sectors": [
        { "categoryName": "Technology", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
      ],
      "assetTypes": [
        { "categoryName": "Stock", "totalValue": { "value": "250.00", "currency": "EUR" }, "percentage": 100.0 }
      ]
    }
    """),
    "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28": try mcpContent("""
    {
      "data": [
        { "date": "2026-03-29", "type": "no-events-today", "isEstimated": false, "symbolId": null, "symbolName": null },
        { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": 5101, "symbolName": "Live Adapter Co" }
      ]
    }
    """),
    "pdt-list-dividends?date_from=2025-03-24&date_to=2026-04-28&page=1&per_page=250": try mcpResult("""
    {
      "data": [
        { "date": "2026-03-28T08:13:00+00:00", "amount": { "value": "8.00", "currency": "EUR" }, "symbolQuoteId": 9101 }
      ],
      "meta": { "last_page": 1 }
    }
    """),
    "pdt-get-symbol-quote?id=9101": try mcpContent("""
    { "id": 9101, "symbolId": 5101 }
    """),
    "pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9101": try mcpContent("""
    {
      "data": [
        { "date": "2026-03-27", "closeAdjusted": "19.00", "symbolQuoteId": 9101 },
        { "date": "2026-03-29", "closeAdjusted": "20.00", "symbolQuoteId": 9101 }
      ]
    }
    """),
]
let scriptedLiveRun = try PressureRunner.run(
    dataSource: PDTLiveDataSource(toolClient: ScriptedPDTLiveToolClient(responses: scriptedConnectorResponses)),
    snapshotStore: scriptedLiveStore,
    asOf: "2026-03-29"
)
try check(scriptedLiveRun.snapshotCommit.written, "live data source run should write only isolated snapshot state")
try check(
    scriptedLiveRun.model.facetSnapshots.allocation.openHoldingCount == 1,
    "live data source should normalize open holdings and filter closed positions"
)
try check(
    scriptedLiveRun.model.facetSnapshots.allocation.sectorBreakdown.count == 1,
    "live data source should normalize sector distributions from wrapped mcporter payloads"
)
try check(
    scriptedLiveRun.model.facetSnapshots.allocation.assetTypeBreakdown.count == 1,
    "live data source should normalize asset type distributions from wrapped mcporter payloads"
)
try check(
    scriptedLiveRun.model.rankedAttentionItems.map(\.id).contains("allocation.concentration.9101"),
    "live data source should feed normalized holdings into pressure ranking"
)
try check(
    scriptedLiveRun.model.rankedAttentionItems.map(\.id).contains("income.ex-dividend.9101"),
    "live data source should join calendar events to dividend quote ids"
)
try check(
    scriptedLiveRun.model.facetSnapshots.income.upcomingEvents.count == 1,
    "live data source should filter calendar no-event sentinel rows"
)
try check(
    scriptedLiveRun.model.facetSnapshots.bigMovers.priceSeriesCount == 2,
    "live data source should normalize symbol price rows for the big-mover facet"
)
try check(
    scriptedLiveRun.descriptor.sections.first { $0.id == "pulse" }?.rows.isEmpty == false,
    "live data source should render through the user-visible pulse descriptor"
)
try check(
    FileManager.default.fileExists(atPath: scriptedLiveRun.snapshotCommit.path),
    "live data source should commit a snapshot inside the passed store"
)
let connectorStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-scripted-connector-check")
defer {
    try? FileManager.default.removeItem(at: connectorStore.directory)
}
let scriptedConnector = ScriptedPDTMCPConnector(responses: scriptedConnectorResponses)
let coalescedConnectorFetch = PDTCoalescedFirstPortfolioFetch(
    dataSource: PDTMCPConnectorDataSource(connector: scriptedConnector),
    snapshotStore: connectorStore,
    asOf: "2026-03-29"
)
let firstConnectorFetch = try coalescedConnectorFetch.fetch()
let secondConnectorFetch = try coalescedConnectorFetch.fetch()
try check(firstConnectorFetch == secondConnectorFetch, "coalesced scripted connector fetch should return the first result")
let connectorCallCounts = Dictionary(grouping: scriptedConnector.calls, by: { $0 }).mapValues(\.count)
try check(
    Set(scriptedConnector.calls).isSubset(of: Set(PDTReadTools.requiredV1)),
    "scripted connector path should call only required v1 read tools"
)
try check(
    PDTReadTools.requiredV1.allSatisfy { connectorCallCounts[$0] == 1 },
    "coalesced scripted connector fetch should call every required v1 read tool exactly once"
)
try check(scriptedConnector.availabilityChecks == 1, "scripted connector fetch should check required tool availability once")
let scriptedConnectorConfiguration = ScriptedPDTMCPConnectorConfiguration(
    responses: scriptedConnectorResponses.mapValues { String(decoding: $0, as: UTF8.self) },
    asOf: "2026-03-29"
)
let configuredConnector = try scriptedConnectorConfiguration.connector()
try check(
    configuredConnector.availableTools == Set(PDTReadTools.requiredV1),
    "scripted connector config should default to the complete required read-tool list"
)
let configuredFetchStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-configured-first-fetch-check")
defer {
    try? FileManager.default.removeItem(at: configuredFetchStore.directory)
}
let configuredFirstFetch = try PDTCoalescedFirstPortfolioFetch(
    dataSource: PDTMCPConnectorDataSource(connector: configuredConnector),
    snapshotStore: configuredFetchStore,
    asOf: scriptedConnectorConfiguration.asOf
).fetch()
try check(
    configuredFirstFetch.snapshotCommit.written
        && FileManager.default.fileExists(atPath: configuredFirstFetch.snapshotCommit.path),
    "complete configured first fetch should write latest-portfolio-snapshot.json before publishing"
)
try check(
    configuredFirstFetch.descriptor.sections.map(\.id).contains("pulse"),
    "complete configured first fetch should publish a pulse descriptor from normalized data"
)
let missingToolConnector = ScriptedPDTMCPConnector(
    availableTools: Set(PDTReadTools.requiredV1.filter { $0 != "pdt-list-dividends" }),
    responses: scriptedConnectorResponses
)
let missingToolStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-missing-tool-first-fetch-check")
defer {
    try? FileManager.default.removeItem(at: missingToolStore.directory)
}
do {
    _ = try PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTMCPConnectorDataSource(connector: missingToolConnector),
        snapshotStore: missingToolStore,
        asOf: "2026-03-29"
    ).fetch()
    throw CheckFailure("missing read tool should block scripted connector fetch")
} catch PDTMCPConnectorError.missingRequiredReadTools(let missing) {
    try check(missing == ["pdt-list-dividends"], "missing read tool error should name the unavailable v1 tool")
    try check(missingToolConnector.calls.isEmpty, "missing read tool should block before any tool call")
    try check(
        !FileManager.default.fileExists(atPath: missingToolStore.directory.appending(path: "latest-portfolio-snapshot.json").path),
        "missing read tool should not write a first-fetch snapshot"
    )
}
let setupErrorConnector = ScriptedPDTMCPConnector(
    responses: scriptedConnectorResponses,
    failure: .setupUnavailable("Claude Desktop needs PDT setup")
)
do {
    _ = try PDTMCPConnectorDataSource(connector: setupErrorConnector).snapshot(asOf: "2026-03-29")
    throw CheckFailure("setup unavailable should propagate from scripted connector")
} catch PDTMCPConnectorError.setupUnavailable {
}
let transientErrorConnector = ScriptedPDTMCPConnector(
    responses: scriptedConnectorResponses,
    failure: .transientFailure("Claude call timed out")
)
do {
    _ = try PDTMCPConnectorDataSource(connector: transientErrorConnector).snapshot(asOf: "2026-03-29")
    throw CheckFailure("transient failure should propagate from scripted connector")
} catch PDTMCPConnectorError.transientFailure {
}
let transientConfiguration = ScriptedPDTMCPConnectorConfiguration(
    responses: scriptedConnectorResponses.mapValues { String(decoding: $0, as: UTF8.self) },
    asOf: "2026-03-29",
    failure: "transientFailure",
    failureMessage: "Claude call timed out"
)
do {
    _ = try PDTMCPConnectorDataSource(connector: transientConfiguration.connector()).snapshot(asOf: "2026-03-29")
    throw CheckFailure("scripted connector configuration should represent transient refresh failure")
} catch PDTMCPConnectorError.transientFailure(let message) {
    try check(message == "Claude call timed out", "scripted transient failure should keep its configured message")
}
var malformedResponses = scriptedConnectorResponses
malformedResponses["pdt-get-portfolio-holdings"] = Data("{".utf8)
do {
    _ = try PDTMCPConnectorDataSource(
        connector: ScriptedPDTMCPConnector(responses: malformedResponses)
    ).snapshot(asOf: "2026-03-29")
    throw CheckFailure("malformed scripted payload should not produce a snapshot")
} catch PDTLiveDataSourceError.malformedToolResult(let tool) {
    try check(tool == "pdt-get-portfolio-holdings", "malformed payload should report the failing read tool")
}
do {
    _ = try PDTLiveDataSource(toolClient: ScriptedPDTLiveToolClient(responses: [
        "pdt-get-portfolio-holdings": try mcpErrorContent("""
        authentication required; please login with cached credentials before calling PDT
        """),
    ])).snapshot(asOf: "2026-03-29")
    throw CheckFailure("exit-zero live PDT auth payload should not decode as a snapshot")
} catch let error as PDTLiveDataSourceError {
    try check(error.shouldSkipLiveSmoke, "exit-zero live PDT auth payload should be classified as a skip")
}
let quietRunWithPrior = try PressureRunner.run(
    fixture: fixture,
    snapshotDirectory: quietSnapshotStore.directory
)
try check(quietRunWithPrior.model.allQuiet, "quiet fixture with matching prior snapshot should be all quiet")
try check(quietRunWithPrior.model.attentionItems == [], "quiet fixture with matching prior snapshot should emit no attention items")
try check(
    quietRunWithPrior.model.portfolioGlance.priorSnapshotAsOf == "2026-06-22",
    "quiet E2E model should expose matching prior snapshot context"
)
try check(
    quietRunWithPrior.descriptor.statusTitle == "EUR 51,200.00 - All quiet",
    "quiet E2E descriptor should render all quiet"
)
try check(
    quietRunWithPrior.descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness"],
    "quiet E2E descriptor should keep drill-down sections reachable"
)
let malformedSnapshotStore = try SnapshotStore.temporaryTestStore()
defer {
    try? FileManager.default.removeItem(at: malformedSnapshotStore.directory)
}
try Data("{".utf8).write(
    to: malformedSnapshotStore.directory.appending(path: "latest-portfolio-snapshot.json")
)
let quietRunWithMalformedPrior = try PressureRunner.run(
    fixture: fixture,
    snapshotDirectory: malformedSnapshotStore.directory
)
try check(quietRunWithMalformedPrior.model.allQuiet, "malformed prior snapshot should fall back to cold-start modeling")
try check(
    quietRunWithMalformedPrior.model.portfolioGlance.priorSnapshotAsOf == nil,
    "malformed prior snapshot should not populate prior glance context"
)
let replacedMalformedPrior = try malformedSnapshotStore.loadPriorSnapshot()
try check(
    replacedMalformedPrior == quietSnapshot,
    "malformed prior snapshot should be replaced by the current committed snapshot"
)

let bigMoverFixture = packageRoot.appending(path: "docs/pdt/fixtures/big-mover.json")
let bigMoverStore = try SnapshotStore.temporaryTestStore()
defer {
    try? FileManager.default.removeItem(at: bigMoverStore.directory)
}
let bigMoverPriorSnapshot = try PDTFixtureDataSource.priorSnapshot(from: bigMoverFixture)
try _ = bigMoverStore.commitCurrentSnapshot(bigMoverPriorSnapshot)
let seededBigMoverStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-seed-prior-check")
defer {
    try? FileManager.default.removeItem(at: seededBigMoverStore.directory)
}
let seededBigMoverCommit = try PressureRunner.seedPriorSnapshot(
    fixture: bigMoverFixture,
    snapshotDirectory: seededBigMoverStore.directory
)
try check(seededBigMoverCommit.written, "seed-prior should write the fixture prior snapshot")
try check(seededBigMoverCommit.asOf == "2026-06-15", "seed-prior should report the fixture prior snapshot date")
let loadedSeededBigMoverSnapshot = try SnapshotStore(directory: seededBigMoverStore.directory).loadPriorSnapshot()
try check(
    loadedSeededBigMoverSnapshot == bigMoverPriorSnapshot,
    "seed-prior should make the fixture prior snapshot loadable"
)
let bigMoverRun = try PressureRunner.run(
    fixture: bigMoverFixture,
    snapshotDirectory: bigMoverStore.directory
)
try check(bigMoverRun.snapshotCommit.written, "big-mover run should update the current snapshot")
let loadedBigMoverSnapshot = try SnapshotStore(directory: bigMoverStore.directory).loadPriorSnapshot()
let currentBigMoverSnapshot = try PDTFixtureDataSource.snapshot(from: bigMoverFixture)
try check(
    loadedBigMoverSnapshot == currentBigMoverSnapshot,
    "big-mover run should replace the prior snapshot with current holdings"
)
var duplicatePriorBigMoverSnapshot = bigMoverPriorSnapshot
duplicatePriorBigMoverSnapshot.openHoldings.append(bigMoverPriorSnapshot.openHoldings[0])
let duplicatePriorBigMoverModel = PressureEngine.buildModel(
    from: currentBigMoverSnapshot,
    priorSnapshot: duplicatePriorBigMoverSnapshot
)
try check(
    duplicatePriorBigMoverModel.rankedAttentionItems.contains { $0.id == "bigMovers.move.9001" },
    "duplicate prior quote ids should not prevent big-mover modeling"
)
try check(!bigMoverRun.model.allQuiet, "prior snapshot plus current fixture should not be all quiet")
let bigMoverItem = try require(
    bigMoverRun.model.rankedAttentionItems.first { $0.facet == "bigMovers" },
    "prior snapshot plus current fixture should emit a big-mover item"
)
try check(bigMoverItem.severity == "medium", "big-mover item should expose severity")
try check(abs(bigMoverItem.score - 0.62) < 0.001, "big-mover item should expose score")
try check(
    bigMoverItem.holdingIdentity?.name == "Nova Lithography"
        && bigMoverItem.holdingIdentity?.quoteId == 9001,
    "big-mover item should expose holding identity"
)
try check(abs((bigMoverItem.beforeValue ?? 0) - 545.00) < 0.001, "big-mover item should expose before value")
try check(abs((bigMoverItem.afterValue ?? 0) - 612.40) < 0.001, "big-mover item should expose after value")
try check(abs((bigMoverItem.moveSize ?? 0) - 0.1237) < 0.0001, "big-mover item should expose move size")
try check(
    bigMoverItem.detail == "Nova Lithography moved +12.4% from EUR 545.00 to EUR 612.40 while portfolio weight changed 9.4% -> 11.6%.",
    "big-mover item copy should describe before and after values without advice"
)
try check(!bigMoverItem.detail.localizedCaseInsensitiveContains("sell"), "big-mover copy should not prescribe selling")
try check(!bigMoverItem.detail.localizedCaseInsensitiveContains("buy"), "big-mover copy should not prescribe buying")
try check(!bigMoverItem.detail.localizedCaseInsensitiveContains("should"), "big-mover copy should not be prescriptive")
let bigMoverExpansion = try require(
    bigMoverRun.descriptor.sections.first { $0.id == "pulse" }?
        .rows
        .first { $0.id == "bigMovers.move.9001.glance" }?
        .children
        .first { $0.id == "bigMovers.move.9001.readout" },
    "descriptor should expose big-mover expansion row as a nested readout"
)
try check(
    bigMoverExpansion.detail == "EUR 545.00 -> EUR 612.40; move +12.4%; score 0.62",
    "big-mover descriptor should render before/after support"
)

let incomeFixture = packageRoot.appending(path: "docs/pdt/fixtures/income-event.json")
let incomeSnapshotStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-income-check")
defer {
    try? FileManager.default.removeItem(at: incomeSnapshotStore.directory)
}
let incomeRun = try PressureRunner.run(
    fixture: incomeFixture,
    snapshotDirectory: incomeSnapshotStore.directory
)
try check(!incomeRun.model.allQuiet, "income fixture should not be all quiet")
let incomeItem = try require(
    incomeRun.model.rankedAttentionItems.first { $0.facet == "income" },
    "income fixture should emit an income attention item"
)
try check(incomeItem.id == "income.ex-dividend.9003", "income item should key on the joined quote id")
try check(incomeItem.severity == "low", "income item should expose severity")
try check(abs(incomeItem.score - 0.45) < 0.001, "income item should expose score")
try check(incomeItem.eventDate == "2026-06-24", "income item should expose the relevant date")
try check(incomeItem.amount == Money(value: "78.00", currency: "EUR"), "income item should expose latest amount")
try check(incomeItem.changePercent == nil, "income item should not derive change from raw payment totals")
try check(
    incomeItem.holdingIdentity?.name == "Helix Pharma A/S"
        && incomeItem.holdingIdentity?.quoteId == 9003,
    "income item should expose the normalized holding identity"
)
try check(
    incomeItem.detail == "Helix Pharma A/S has an ex-dividend date on 2026-06-24; latest recorded dividend EUR 78.00.",
    "income item copy should describe date and amount without advice"
)
try check(!incomeItem.detail.localizedCaseInsensitiveContains("buy"), "income copy should not prescribe buying")
try check(!incomeItem.detail.localizedCaseInsensitiveContains("sell"), "income copy should not prescribe selling")
try check(!incomeItem.detail.localizedCaseInsensitiveContains("should"), "income copy should not be prescriptive")
let incomeExpansion = try require(
    incomeRun.descriptor.sections.first { $0.id == "pulse" }?
        .rows
        .first { $0.id == "income.ex-dividend.9003.glance" }?
        .children
        .first { $0.id == "income.ex-dividend.9003.readout" },
    "descriptor should expose income expansion row as a nested readout"
)
try check(
    incomeExpansion.detail == "2026-06-24; EUR 78.00; score 0.45",
    "income descriptor should render date, amount, and score"
)
let incomeRows = incomeRun.descriptor.sections.first { $0.id == "income" }?.rows ?? []
let incomeDrillDownRow = incomeRows.first {
    $0.role == .incomeDrillDown && $0.title == "Helix Pharma A/S"
}
try check(
    incomeDrillDownRow?.detail == "ex-dividend on 2026-06-24; EUR 78.00",
    "income section should expand event date and amount support"
)
let incomePaymentRow = incomeRows.first { $0.id == "income.quote.9003.payment-dividend.2026-07-10" }
try check(
    incomePaymentRow?.role == .incomeEvent
        && incomePaymentRow?.detail == "payment-dividend on 2026-07-10",
    "income section should not attach historical amount to unrelated calendar events"
)
try check(
    Set(incomeRows.map(\.id)).count == incomeRows.count,
    "income section should expose unique row ids"
)
var unmappedIncomeSnapshot = try PDTFixtureDataSource.snapshot(from: incomeFixture)
unmappedIncomeSnapshot.incomeEvents.append(
    IncomeEventSummary(
        date: "2026-06-25",
        kind: "ex-dividend",
        symbolName: "Unmapped Income Co",
        estimated: false,
        symbolId: 5011
    )
)
let unmappedIncomeModel = PressureEngine.buildModel(from: unmappedIncomeSnapshot)
try check(
    unmappedIncomeModel.rankedAttentionItems.contains {
        $0.id == "income.ex-dividend.symbol.5011"
            && $0.facet == "income"
            && $0.holdingIdentity == nil
    },
    "income engine should not drop non-estimated ex-dividend events without quote resolution"
)

let correctionFixtureDirectory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-income-correction-fixture")
defer {
    try? FileManager.default.removeItem(at: correctionFixtureDirectory.directory)
}
let correctionFixture = correctionFixtureDirectory.directory.appending(path: "income-correction.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "listCalendarEvents": {
    "data": [
      { "id": 2001, "date": "2026-06-24", "type": "ex-dividend", "isEstimated": false, "symbolId": 5010, "symbolName": "Correction Corp" }
    ]
  },
  "listDividends": {
    "data": [
      { "id": 81000001, "date": "2026-06-22T08:13:00+00:00", "amount": { "value": "61.20", "currency": "EUR" }, "symbolQuoteId": 9010 },
      { "id": 81000002, "date": "2026-03-30T08:20:00+00:00", "amount": { "value": "-61.20", "currency": "EUR" }, "symbolQuoteId": 9010 }
    ]
  },
  "getSymbolQuotes": [
    { "id": 9010, "symbolId": 5010 }
  ]
}
""".utf8).write(to: correctionFixture)
let correctionModel = PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: correctionFixture))
let correctionItem = try require(
    correctionModel.rankedAttentionItems.first { $0.id == "income.ex-dividend.9010" },
    "correction fixture should emit an income item"
)
try check(correctionItem.amount == nil, "income item should not expose reversed dividend corrections as real amounts")
try check(
    correctionItem.detail == "Correction Corp has an ex-dividend date on 2026-06-24.",
    "income copy should omit corrected-away amounts"
)

let concentrationRun = try PressureRunner.run(
    fixture: concentrationFixture,
    snapshotDirectory: snapshotDirectory
)
try check(concentrationRun.snapshotCommit.written, "cold-start run should commit the first snapshot")
try check(
    FileManager.default.fileExists(atPath: concentrationRun.snapshotCommit.path),
    "cold-start run should write a snapshot file"
)
try check(!concentrationRun.model.allQuiet, "concentration fixture should not be all quiet")
try check(
    concentrationRun.model.facetSnapshots.freshness.worstPriceAsOf == "2026-06-18",
    "concentration fixture should expose the oldest PDT price date"
)
try check(
    concentrationRun.model.facetSnapshots.freshness.stale,
    "concentration fixture should mark stale EOD facts"
)
try check(
    concentrationRun.model.rankedAttentionItems.count == 1,
    "concentration fixture should produce one attention item"
)
let concentrationItem = try require(
    concentrationRun.model.rankedAttentionItems.first,
    "concentration fixture should include an attention item"
)
try check(concentrationItem.facet == "allocation", "attention item should expose allocation facet")
try check(concentrationItem.severity == "medium", "attention item should expose severity")
try check(abs(concentrationItem.score - 0.66) < 0.001, "attention item should expose score")
try check(
    concentrationItem.holdingIdentity?.name == "Nova Lithography"
        && concentrationItem.holdingIdentity?.quoteId == 9001,
    "attention item should expose holding identity"
)
try check(
    abs((concentrationItem.currentWeight ?? 0) - 0.2421875) < 0.000001,
    "attention item should expose current weight"
)
try check(
    abs((concentrationItem.threshold ?? 0) - 0.20) < 0.000001,
    "attention item should expose threshold"
)
try check(
    concentrationItem.detail == "Nova Lithography is 24.2% of the portfolio, above the 20.0% concentration line.",
    "attention item copy should be descriptive"
)
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("sell"), "copy should not prescribe selling")
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("buy"), "copy should not prescribe buying")
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("should"), "copy should not be prescriptive")
try check(concentrationRun.descriptor.statusBadge == "1", "descriptor should expose a badge")
let concentrationSurface = MenuBarSurfaceRenderer.render(descriptor: concentrationRun.descriptor)
try check(
    concentrationRun.descriptor.statusVisual.filledBarCount == 1,
    "concentration descriptor should fill one notification bar"
)
try check(
    concentrationRun.descriptor.statusVisual.isDimmed,
    "stale concentration descriptor may dim the whole icon without lowering attention fill"
)
try check(
    concentrationRun.descriptor.statusVisual.barHeights[0] > concentrationRun.descriptor.statusVisual.barHeights[1],
    "concentration descriptor should make the leading concentration bar taller"
)
try check(
    concentrationSurface.status.badge == "1",
    "fixture launch surface should render non-quiet descriptor badge"
)
try check(
    concentrationSurface.status.menuBarTitle.isEmpty,
    "pressure fixture launch surface should keep status text out of the menu bar title"
)
try check(
    concentrationSurface.sections.first { $0.id == "pulse" }?.rows.dropFirst().map(\.role)
        == [.pulseAttention],
    "fixture launch surface should keep attention items compact at the top level"
)
try check(
    concentrationRun.descriptor.sections.first?.rows.first { $0.role == .pulseAttention }?.children.contains {
        $0.role == .pulseAttentionExpansion
    } == true,
    "descriptor should expose pulse attention expansion rows as a nested drill-down"
)
let allocationRows = concentrationRun.descriptor.sections.first { $0.id == "allocation" }?.rows ?? []
let allocationDrillDownRow = allocationRows.first {
    $0.role == .allocationDrillDown && $0.title == "Nova Lithography"
}
try check(
    allocationRows.count == concentrationRun.model.facetSnapshots.allocation.openHoldingCount,
    "allocation drill-down should list every open holding"
)
try check(
    allocationDrillDownRow?.detail == "24.2% of portfolio; concentration line 20.0%",
    "descriptor should expose allocation drill-down for the item"
)
try check(
    concentrationRun.descriptor.sections.first { $0.id == "freshness" }?.rows.first?.detail == "Stale",
    "descriptor should render stale freshness from model facts"
)

var crowdedAllocationModel = concentrationRun.model
crowdedAllocationModel.rankedAttentionItems = [
    crowdedAllocationItem(id: "allocation.concentration.9501", name: "Alpha Concentration", quoteId: 9501, weight: 0.31),
    crowdedAllocationItem(id: "allocation.concentration.9502", name: "Beta Concentration", quoteId: 9502, weight: 0.30),
    crowdedAllocationItem(id: "allocation.concentration.9503", name: "Gamma Concentration", quoteId: 9503, weight: 0.29),
    crowdedAllocationItem(id: "allocation.concentration.9504", name: "Delta Concentration", quoteId: 9504, weight: 0.28),
]
crowdedAllocationModel.attentionItems = crowdedAllocationModel.rankedAttentionItems
let crowdedDescriptor = MenuDescriptorRenderer.render(model: crowdedAllocationModel)
let crowdedPulseRows = crowdedDescriptor.sections.first { $0.id == "pulse" }?.rows ?? []
try check(crowdedDescriptor.statusBadge == "4", "glance badge should count all pressure items")
try check(
    crowdedPulseRows.filter { $0.role == .pulseAttention }.map(\.title) == [
        "Alpha Concentration concentration",
        "Beta Concentration concentration",
        "Gamma Concentration concentration",
    ],
    "glance should cap pressure rows at three model-ranked items"
)
try check(
    !crowdedPulseRows.contains { $0.id == "allocation.concentration.9504.glance" },
    "glance should omit pressure rows beyond the cap"
)

let thresholdFixtureDirectory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-allocation-threshold-fixture")
defer {
    try? FileManager.default.removeItem(at: thresholdFixtureDirectory.directory)
}
let thresholdFixture = thresholdFixtureDirectory.directory.appending(path: "allocation-threshold.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Threshold Holding",
        "symbolQuoteId": 9201,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "2000.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "2000.00", "currency": "EUR" },
        "portfolioWeight": 0.20,
        "closedAt": null
      },
      {
        "symbolName": "Quiet Holding",
        "symbolQuoteId": 9202,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "80.00", "currency": "EUR" },
        "currentWorth": { "value": "1800.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "1800.00", "currency": "EUR" },
        "portfolioWeight": 0.18,
        "closedAt": null
      }
    ]
  }
}
""".utf8).write(to: thresholdFixture)
let thresholdModel = PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: thresholdFixture))
try check(!thresholdModel.allQuiet, "holding at the 20% allocation line should create pressure")
try check(
    thresholdModel.rankedAttentionItems.map(\.id) == ["allocation.concentration.9201"],
    "holding at or above 20% should emit one concentration item"
)
try check(
    thresholdModel.rankedAttentionItems.first?.currentWeight == 0.20,
    "threshold concentration item should expose its allocation ranking input"
)
try check(
    thresholdModel.rankedAttentionItems.first?.detail
        == "Threshold Holding is 20.0% of the portfolio, at the 20.0% concentration line.",
    "threshold concentration copy should describe equality accurately"
)

let rankingFixtureDirectory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-allocation-ranking-fixture")
defer {
    try? FileManager.default.removeItem(at: rankingFixtureDirectory.directory)
}
let rankingFixture = rankingFixtureDirectory.directory.appending(path: "allocation-ranking.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Alpha Equal Concentration",
        "symbolQuoteId": 9301,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "2500.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "2500.00", "currency": "EUR" },
        "portfolioWeight": 0.25,
        "closedAt": null
      },
      {
        "symbolName": "Beta Equal Concentration",
        "symbolQuoteId": 9302,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "2500.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "2500.00", "currency": "EUR" },
        "portfolioWeight": 0.25,
        "closedAt": null
      },
      {
        "symbolName": "Zeta Slightly Heavier",
        "symbolQuoteId": 9303,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "2510.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "2510.00", "currency": "EUR" },
        "portfolioWeight": 0.251,
        "closedAt": null
      },
      {
        "symbolName": "Omega Heaviest",
        "symbolQuoteId": 9304,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "3100.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "3100.00", "currency": "EUR" },
        "portfolioWeight": 0.31,
        "closedAt": null
      }
    ]
  }
}
""".utf8).write(to: rankingFixture)
let rankingModel = PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: rankingFixture))
try check(
    rankingModel.rankedAttentionItems.map(\.holdingIdentity?.name) == [
        "Omega Heaviest",
        "Zeta Slightly Heavier",
        "Alpha Equal Concentration",
        "Beta Equal Concentration",
    ],
    "multiple concentration items should rank by raw weight before stable name fallback"
)
try check(
    rankingModel.facetSnapshots.allocation.topHoldings.map(\.name) == [
        "Omega Heaviest",
        "Zeta Slightly Heavier",
        "Alpha Equal Concentration",
        "Beta Equal Concentration",
    ],
    "allocation snapshot should use the same stable ranking inputs"
)

let closedConcentrationFixtureDirectory = try SnapshotStore.temporaryTestStore(
    prefix: "pdtbar-allocation-closed-fixture"
)
defer {
    try? FileManager.default.removeItem(at: closedConcentrationFixtureDirectory.directory)
}
let closedConcentrationFixture = closedConcentrationFixtureDirectory.directory
    .appending(path: "allocation-closed.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Closed Concentration",
        "symbolQuoteId": 9401,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "8000.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "8000.00", "currency": "EUR" },
        "portfolioWeight": 0.80,
        "closedAt": "2026-06-20T10:00:00+00:00"
      },
      {
        "symbolName": "Open Quiet Holding",
        "symbolQuoteId": 9402,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "100.00", "currency": "EUR" },
        "currentWorth": { "value": "1900.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "1900.00", "currency": "EUR" },
        "portfolioWeight": 0.19,
        "closedAt": null
      }
    ]
  }
}
""".utf8).write(to: closedConcentrationFixture)
let closedConcentrationModel = PressureEngine.buildModel(
    from: try PDTFixtureDataSource.snapshot(from: closedConcentrationFixture)
)
try check(
    closedConcentrationModel.allQuiet,
    "closed high-weight holdings should not create allocation pressure"
)
try check(
    closedConcentrationModel.facetSnapshots.allocation.topHoldings.map(\.name) == ["Open Quiet Holding"],
    "allocation snapshot should exclude closed holdings"
)

for fixture in allFixtures {
    let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
    let model = PressureEngine.buildModel(from: snapshot)
    let modelJSON = try stableJSONData(model)
    let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: modelJSON)
    let descriptor = MenuDescriptorRenderer.render(model: decoded)
    try assertInformationalCopy(model: decoded, descriptor: descriptor, fixtureName: fixture.lastPathComponent)
    try check(!descriptor.sections.isEmpty, "\(fixture.lastPathComponent) should render menu sections")
    try check(descriptor.statusAccessibilityIdentifier == "pdtbar.status", "\(fixture.lastPathComponent) should expose status accessibility id")
    try check(
        descriptor.sections.allSatisfy { !$0.id.isEmpty && $0.accessibilityIdentifier == "pdtbar.section.\($0.id)" },
        "\(fixture.lastPathComponent) should expose stable section ids and accessibility ids"
    )
    let renderedRows = descriptor.sections.flatMap(\.rows)
    try check(
        Set(renderedRows.map(\.id)).count == renderedRows.count,
        "\(fixture.lastPathComponent) should expose unique row ids"
    )
    try check(
        renderedRows.allSatisfy { !$0.id.isEmpty && $0.accessibilityIdentifier == "pdtbar.row.\($0.id)" },
        "\(fixture.lastPathComponent) should expose stable row ids and accessibility ids"
    )
    try check(
        renderedRows.allSatisfy { $0.role != .row },
        "\(fixture.lastPathComponent) should expose typed row roles"
    )
    try check(decoded.supportingDataSlots.count == 4, "\(fixture.lastPathComponent) should include supporting slots")
    try check(!decoded.facetSnapshots.allocation.totalValue.value.contains(","), "\(fixture.lastPathComponent) should keep Money.value canonical")
}

private func crowdedAllocationItem(id: String, name: String, quoteId: Int, weight: Double) -> AttentionItem {
    AttentionItem(
        id: id,
        facet: "allocation",
        rank: 0,
        title: "\(name) concentration",
        detail: "\(name) is \(weight * 100)% of the portfolio.",
        severity: "medium",
        score: weight,
        holdingIdentity: HoldingIdentity(name: name, quoteId: quoteId),
        currentWeight: weight,
        threshold: PressureEngine.concentrationThreshold,
        supportingDataSlotIDs: ["allocation.holdings"]
    )
}

private func assertInformationalCopy(
    model: PortfolioPulseModel,
    descriptor: MenuDescriptor,
    fixtureName: String
) throws {
    let copy = renderedCopy(from: model, descriptor: descriptor)
    for value in copy where containsAdviceLikeLanguage(value) {
        throw CheckFailure("\(fixtureName) should not render advice-like copy: \(value)")
    }
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

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(message)
    }
}

private func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CheckFailure(message)
    }
    return value
}

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct ScriptedPDTLiveToolClient: PDTLiveToolClient {
    var responses: [String: Data]

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw CheckFailure("missing scripted live PDT response for \(key)")
        }
        return response
    }
}

private func mcpContent(_ json: String) throws -> Data {
    try mcpContent(json, isError: false)
}

private func mcpErrorContent(_ text: String) throws -> Data {
    try mcpContent(text, isError: true)
}

private func mcpContent(_ text: String, isError: Bool) throws -> Data {
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

private func mcpResult(_ json: String) throws -> Data {
    let payload = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONSerialization.data(
        withJSONObject: ["result": payload],
        options: [.sortedKeys]
    )
}
