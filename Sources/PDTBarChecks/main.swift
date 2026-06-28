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
try check(
    decoded.facetSnapshots.allocation.portfolioOverview.totalValue == Money(value: "51200.00", currency: "EUR")
        && decoded.facetSnapshots.allocation.portfolioOverview.openHoldingCount == 9
        && decoded.facetSnapshots.allocation.portfolioOverview.topNConcentration?.rankCount == 3
        && decoded.facetSnapshots.allocation.portfolioOverview.cashSummary?.value == Money(value: "1895.00", currency: "EUR"),
    "quiet model should carry structured portfolio overview context"
)
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
let pressureFixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
let pressureSnapshot = try PDTFixtureDataSource.snapshot(from: pressureFixture)
let pressureModel = PressureEngine.buildModel(from: pressureSnapshot)
let pressureItem = try require(
    pressureModel.rankedAttentionItems.first,
    "pressure fixture should emit an attention item for read-state checks"
)
try check(
    pressureItem.readFingerprint.contains("quote:9001")
        && pressureItem.readFingerprint.contains("threshold-bp:2000")
        && pressureItem.readFingerprint.contains("weight-bucket-bp:2400"),
    "concentration read fingerprint should include holding identity, threshold, severity, and weight bucket"
)
try check(
    pressureItem.explanation.trigger.value == "Concentration line crossed"
        && pressureItem.explanation.threshold?.value == "20.0%"
        && pressureItem.explanation.currentValue?.value == "24.2%"
        && pressureItem.explanation.supportingSourceSlots.map(\.id) == ["allocation.holdings"],
    "concentration attention should carry structured explanation facts for renderer formatting"
)
let sectorPressureItem = try require(
    pressureModel.rankedAttentionItems.first { $0.id == "allocation.sector.information-technology" },
    "pressure fixture should emit sector allocation pressure when a sector crosses 30%"
)
try check(
    sectorPressureItem.explanation.trigger.value == "Sector concentration line crossed"
        && sectorPressureItem.explanation.threshold?.value == "30.0%"
        && sectorPressureItem.explanation.currentValue?.value == "30.9%"
        && sectorPressureItem.explanation.supportingSourceSlots.map(\.id) == ["allocation.sectors"],
    "sector pressure should carry structured threshold/current/source facts"
)
try check(
    pressureModel.facetSnapshots.allocation.allocationPressureItems.map(\.id)
        .contains("allocation.sector.information-technology"),
    "allocation snapshot should carry allocation-derived pressure facts"
)
let pressureDescriptor = MenuDescriptorRenderer.render(model: pressureModel)
try check(
    pressureDescriptor.sections.first { $0.id == "pulse" }?.rows
        .contains { $0.id == "allocation.sector.information-technology.glance" } == true
        && pressureDescriptor.sections.first { $0.id == "allocation" }?.rows
            .contains { $0.id == "allocation.sector.information-technology.allocation" } == true
        && pressureDescriptor.sections.first { $0.id == "allocation" }?.rows
            .first { $0.id == "allocation.portfolio.details" }?
            .children.contains { $0.id == "allocation.portfolio.sectors" } == true,
    "sector pressure should render in Pulse and Allocation without hiding portfolio detail facts"
)
var highCashSnapshot = snapshot
let cashIndex = try require(
    highCashSnapshot.openHoldings.firstIndex { $0.name == "Cash" },
    "quiet fixture should include a cash holding for cash-drag checks"
)
highCashSnapshot.openHoldings[cashIndex].weight = 0.12
highCashSnapshot.openHoldings[cashIndex].worth = Money(value: "6144.00", currency: "EUR")
highCashSnapshot.assetTypes = [
    DistributionSummary(name: "cash", percentage: 12.0, totalValue: Money(value: "6144.00", currency: "EUR")),
]
let highCashModel = PressureEngine.buildModel(from: highCashSnapshot)
try check(
    highCashModel.rankedAttentionItems.first { $0.id == "allocation.cashDrag" }?.explanation.currentValue?.value
        == "12.0%; EUR 6,144.00",
    "cash drag should surface only from present cash data over the chosen threshold"
)
var missingCashSnapshot = snapshot
missingCashSnapshot.openHoldings.removeAll { $0.name == "Cash" }
missingCashSnapshot.assetTypes = []
let missingCashModel = PressureEngine.buildModel(from: missingCashSnapshot)
try check(
    !missingCashModel.rankedAttentionItems.contains { $0.id == "allocation.cashDrag" },
    "cash drag should stay quiet when cash data is missing"
)
let driftModel = PressureEngine.buildModel(
    from: driftCheckSnapshot(weights: [0.20, 0.15, 0.10]),
    priorSnapshot: driftCheckSnapshot(weights: [0.18, 0.12, 0.08], asOf: "2026-06-21")
)
try check(
    driftModel.rankedAttentionItems.first { $0.id == "allocation.concentrationDrift.top3" }?.explanation.priorValue?.value
        == "38.0%",
    "top concentration drift should surface from prior complete snapshot data"
)
let quietAllocationPressure = PressureEngine.buildModel(
    from: driftCheckSnapshot(weights: [0.19, 0.14, 0.10]),
    priorSnapshot: driftCheckSnapshot(weights: [0.18, 0.13, 0.08], asOf: "2026-06-21")
)
try check(
    quietAllocationPressure.facetSnapshots.allocation.allocationPressureItems.isEmpty,
    "allocation pressure should stay quiet below sector, cash, and drift thresholds"
)
let readStore = try temporaryPulseReadStore()
let emptyReadState = try readStore.load()
try check(emptyReadState.readFingerprints.isEmpty, "read store should load empty when no local state exists")
for item in pressureModel.rankedAttentionItems {
    try readStore.markRead(item.readFingerprint)
}
let reloadedReadState = try PulseReadStore(directory: readStore.directory).load()
try check(
    reloadedReadState.contains(pressureItem.readFingerprint),
    "read store should persist marked fingerprints across reload"
)
let readSnapshotStore = SnapshotStore(directory: readStore.directory)
_ = try readSnapshotStore.commitCurrentSnapshot(pressureSnapshot)
let caughtUpPulse = try require(
    PressureRunner.cachedPulse(snapshotStore: readSnapshotStore, pulseReadStore: readStore),
    "cached pulse lifecycle should load the committed read-state snapshot"
)
try check(caughtUpPulse.source == .cachedSnapshot, "cached pulse lifecycle should report cached source")
try check(caughtUpPulse.snapshotCommit.written == false, "cached pulse lifecycle should not rewrite snapshot state")
try check(caughtUpPulse.model.rankedAttentionItems.isEmpty, "same read fingerprint should hide Pulse attention rows")
try check(caughtUpPulse.descriptor.statusBadge == nil, "same read fingerprint should clear status badge count")
try check(caughtUpPulse.descriptor.statusVisual.filledBarCount == 0, "same read fingerprint should clear status fill count")
try check(caughtUpPulse.descriptor.statusTitle.contains("All caught up"), "all-read pressure should render caught-up copy")
try check(
    caughtUpPulse.descriptor.sections.first { $0.id == "allocation" }?
        .rows
        .first { $0.id == "allocation.portfolio.details" }?
        .children
        .contains { $0.title == "Nova Lithography" } == true,
    "read attention should not hide allocation drill-down facts"
)
var changedPressureSnapshot = pressureSnapshot
changedPressureSnapshot.openHoldings[0].weight = 0.265
let changedPulse = try PressureRunner.run(
    dataSource: StaticPortfolioDataSource(snapshot: changedPressureSnapshot),
    snapshotStore: readSnapshotStore,
    pulseReadStore: readStore
)
try check(
    changedPulse.model.rankedAttentionItems.first?.holdingIdentity?.quoteId == pressureItem.holdingIdentity?.quoteId
        && changedPulse.model.rankedAttentionItems.first?.readFingerprint != pressureItem.readFingerprint,
    "changed material fingerprint should resurface as unread"
)
let markReadRow = MenuDescriptorRenderer.render(model: pressureModel)
    .sections
    .flatMap(\.rows)
    .flatMap(\.children)
    .first { $0.role == .pulseMarkRead }
try check(
    markReadRow?.title == "Mark as read" && markReadRow?.actionPayload == pressureItem.readFingerprint,
    "attention row should expose one Mark as read action with the material fingerprint payload"
)
let noArgumentLaunch = try PDTBarLaunchOptionParser.parse(
    arguments: [],
    environment: [
        "PDTBAR_APP_SUPPORT_DIR": "/tmp/pdtbar-checks-app-support",
        "PDTBAR_FIXTURE": fixture.path,
        "PDTBAR_CLAUDE_BIN": "/tmp/pdtbar-checks-env-handoff-script",
        "PDTBAR_CLAUDE_LOGIN_BIN": "/tmp/pdtbar-checks-env-login-script",
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
try check(
    noArgumentLaunch.claudeLoginBinaryOverride == nil,
    "no-argument launch should ignore inherited scripted Claude login binary hooks"
)
let explicitScriptedLoginLaunch = try PDTBarLaunchOptionParser.parse(
    arguments: ["--scripted-claude-login-bin", "/tmp/pdtbar-checks-login-script"],
    environment: [:]
)
try check(
    explicitScriptedLoginLaunch.claudeLoginBinaryOverride == "/tmp/pdtbar-checks-login-script",
    "scripted Claude login binary should require an explicit launch option"
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
    probingSurface.sections.flatMap(\.rows).map(\.title) == [
        "Checking Claude setup",
        "Log in with Claude",
    ],
    "Claude probing state should keep the login action available"
)
try check(
    probingSurface.sections.flatMap(\.rows).map(\.detail) == [
        "No prompts opened",
        nil,
    ],
    "Claude probing surface should expose setup detail as secondary row text"
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
let firstFetchProgressDescriptor = ClaudeLaunchFlow.descriptor(
    for: .fetchingPortfolio,
    fetchingElapsedSeconds: 12
)
try check(
    firstFetchDescriptor.statusVisual.isDimmed && firstFetchDescriptor.statusVisual.filledBarCount == 0,
    "first-fetch state should dim the icon without filling notification bars"
)
try check(
    firstFetchDescriptor.sections.flatMap(\.rows).map(\.title) == ["Fetching portfolio"],
    "first-fetch state should render without the logged-out menu"
)
try check(
    firstFetchProgressDescriptor.statusTitle == "Fetching portfolio 0:12"
        && firstFetchProgressDescriptor.sections.flatMap(\.rows).map(\.detail) == ["Read-only through Claude - working for 0:12"],
    "first-fetch state should expose elapsed working time while it is running"
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
    fetchFailedDescriptor.sections.flatMap(\.rows).map(\.title) == [
        "Could not fetch portfolio",
        "Try again",
        "Log in with Claude",
    ],
    "first-fetch failure should show retry and login actions without publishing a portfolio pulse"
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
try check(
    cachedRefreshDescriptor.sections.first { $0.id == "actions" }?
        .rows.first { $0.id == "actions.refreshNow" }?.role == .fetchStatus
        && cachedRefreshDescriptor.sections.first { $0.id == "actions" }?
            .rows.first { $0.id == "actions.refreshNow" }?.title == "Refreshing now"
        && cachedRefreshDescriptor.sections.first { $0.id == "actions" }?
            .rows.first { $0.id == "actions.openPDT" }?.role == .openPDT,
    "active cached refresh should coalesce Refresh now and keep Open PDT available"
)
let cachedRefreshActionDescriptor = ClaudeLaunchFlow.descriptorWithRefreshDetailsAction(cachedPulse: descriptor)
try check(
    cachedRefreshActionDescriptor.statusTitle == descriptor.statusTitle
        && freshnessRefreshDetailsAction(in: cachedRefreshActionDescriptor)?.role == .fetchRetry
        && !cachedRefreshActionDescriptor.sections.map(\.id).contains("portfolioFetch"),
    "cached pulse should expose a manual details refresh action under freshness detail"
)
try check(
    cachedRefreshActionDescriptor.sections.first { $0.id == "actions" }?
        .rows.first { $0.id == "actions.refreshNow" }?.role == .fetchRetry
        && cachedRefreshActionDescriptor.sections.first { $0.id == "actions" }?
            .rows.first { $0.id == "actions.openPDT" }?.role == .openPDT,
    "idle cached pulse should expose top-level Refresh now and Open PDT actions"
)
let backgroundFailureDescriptor = ClaudeLaunchFlow.descriptorForBackgroundRefreshFailure(cachedPulse: descriptor)
try check(
    backgroundFailureDescriptor.statusTitle == descriptor.statusTitle
        && backgroundFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed")
        && backgroundFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Fill details again")
        && !backgroundFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Log in with Claude"),
    "background refresh failure should preserve the cached pulse and expose a detail-fill retry"
)
let backgroundProgressDescriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailProgress(
    cachedPulse: descriptor,
    progress: BackgroundDetailRefreshProgress(
        phase: .priceHistory,
        completedUnitCount: 12,
        totalUnitCount: 19
    )
)
try check(
    backgroundProgressDescriptor.sections.flatMap(\.rows).map(\.title).contains("Filling details")
        && backgroundProgressDescriptor.sections.flatMap(\.rows).map(\.title).contains("Step 5/5: Price history")
        && backgroundProgressDescriptor.sections.flatMap(\.rows).map(\.title).contains("12/19 price histories checked")
        && !backgroundProgressDescriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed"),
    "background detail retry should render active phase/count progress instead of stale failure"
)
try check(
    backgroundProgressDescriptor.sections.first { $0.id == "freshness" }?
        .rows.first { $0.id == "dataHealth" }?
        .children.first { $0.id == "dataHealth.detailFill" }?
        .detail == "Price history 12/19",
    "cached refresh descriptor should preserve the pulse while surfacing active Data health detail-fill state"
)
try check(
    backgroundProgressDescriptor.sections.first { $0.id == "actions" }?
        .rows.first { $0.id == "actions.refreshNow" }?.role == .fetchStatus
        && backgroundProgressDescriptor.sections.first { $0.id == "actions" }?
            .rows.first { $0.id == "actions.openPDT" }?.role == .openPDT,
    "background detail progress should keep top-level actions while preventing duplicate refresh work"
)
let backgroundDegradedDescriptor = ClaudeLaunchFlow.descriptorForBackgroundDetailDegraded(cachedPulse: descriptor)
try check(
    backgroundDegradedDescriptor.sections.flatMap(\.rows).map(\.title).contains("Details partially filled")
        && backgroundDegradedDescriptor.sections.flatMap(\.rows).map(\.title).contains("Fill details again")
        && !backgroundDegradedDescriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed"),
    "degraded detail completion should preserve the pulse and expose retry without stale failure copy"
)
try check(
    backgroundDegradedDescriptor.sections.first { $0.id == "freshness" }?
        .rows.first { $0.id == "dataHealth" }?
        .children.first { $0.id == "dataHealth.detailFill" }?
        .detail == "Degraded",
    "degraded descriptor should preserve the pulse while surfacing Data health degradation"
)
let cachedFailureDescriptor = ClaudeLaunchFlow.descriptor(for: .portfolioFetchFailed, cachedPulse: descriptor)
try check(
    cachedFailureDescriptor.statusTitle == descriptor.statusTitle
        && cachedFailureDescriptor.sections.map(\.id).contains("pulse")
        && cachedFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed")
        && cachedFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Fill details again")
        && !cachedFailureDescriptor.sections.flatMap(\.rows).map(\.title).contains("Log in with Claude"),
    "returning launch fetch failure should preserve the cached pulse and expose a detail-fill retry"
)
try check(
    cachedFailureDescriptor.statusVisual.isDimmed
        && cachedFailureDescriptor.statusVisual.barHeights == descriptor.statusVisual.barHeights
        && cachedFailureDescriptor.statusVisual.filledBarCount == descriptor.statusVisual.filledBarCount,
    "returning launch fetch failure should dim the icon while preserving cached concentration shape and fill"
)
let launchRuntime = PDTLaunchRuntime()
let runtimeLaunch = launchRuntime.launch(cachedPulse: caughtUpPulse)
let runtimeReady = launchRuntime.completeReadinessProbe(.ready)
let runtimeDuplicateReady = launchRuntime.completeReadinessProbe(.ready)
let runtimeBackgroundProgress = try require(
    launchRuntime.backgroundDetailRefreshProgress(
        BackgroundDetailRefreshProgress(
            phase: .priceHistory,
            completedUnitCount: 12,
            totalUnitCount: 19
        )
    ),
    "launch runtime should render background detail progress while refresh is in flight"
)
let runtimeCachedFailure = launchRuntime.completeBackgroundDetailRefresh(.failed("scripted detail fill failed"))
try check(
    runtimeLaunch.effect == .probeReadiness
        && runtimeLaunch.descriptor.statusTitle == caughtUpPulse.descriptor.statusTitle
        && runtimeLaunch.descriptor.sections.flatMap(\.rows).map(\.title).contains("Checking Claude setup"),
    "launch runtime should render cached pulse while probing readiness"
)
try check(
    runtimeReady.effect == .startBackgroundDetailRefresh
        && runtimeReady.descriptor.statusTitle == caughtUpPulse.descriptor.statusTitle
        && runtimeReady.descriptor.sections.flatMap(\.rows).map(\.title).contains("Filling details")
        && runtimeReady.descriptor.sections.flatMap(\.rows).map(\.title).contains("Step 1/5: Base holdings"),
    "launch runtime should keep cached pulse visible while background detail fill starts"
)
try check(
    runtimeDuplicateReady.effect == .none
        && runtimeDuplicateReady.descriptor.statusTitle == caughtUpPulse.descriptor.statusTitle,
    "launch runtime should ignore duplicate ready completions while background detail fill is already in flight"
)
try check(
    runtimeBackgroundProgress.descriptor.sections.flatMap(\.rows).map(\.title).contains("Step 5/5: Price history")
        && runtimeBackgroundProgress.descriptor.sections.flatMap(\.rows).map(\.title).contains("12/19 price histories checked")
        && !runtimeBackgroundProgress.descriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed"),
    "launch runtime should render returning-launch background detail progress"
)
try check(
    runtimeCachedFailure.descriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed")
        && runtimeCachedFailure.descriptor.sections.flatMap(\.rows).map(\.title).contains("Fill details again")
        && launchRuntime.currentPulse?.source == .cachedSnapshot,
    "launch runtime should preserve cached pulse and retry state after returning-launch background detail failure"
)
let runtimeRetry = try require(launchRuntime.retryFirstFetch(), "launch runtime should allow retry after fetch failure")
let runtimeProgress = try require(
    launchRuntime.backgroundDetailRefreshProgress(
        BackgroundDetailRefreshProgress(
            phase: .priceHistory,
            completedUnitCount: 12,
            totalUnitCount: 19
        )
    ),
    "launch runtime should render retry progress while background detail refresh is in flight"
)
let runtimeDuplicateRetry = launchRuntime.retryFirstFetch()
let runtimeComplete = launchRuntime.completeBackgroundDetailRefresh(.succeeded(changedPulse, outcome: .completed))
try check(
    runtimeRetry.effect == .startBackgroundDetailRefresh
        && runtimeDuplicateRetry == nil
        && runtimeProgress.descriptor.statusTitle == caughtUpPulse.descriptor.statusTitle
        && runtimeProgress.descriptor.sections.flatMap(\.rows).map(\.title).contains("12/19 price histories checked")
        && runtimeComplete.descriptor.statusTitle == changedPulse.descriptor.statusTitle
        && launchRuntime.currentPulse?.source == .fetchedSnapshot,
    "launch runtime should own retry gating, progress descriptors, and completed background pulse publication"
)
let staleRuntime = PDTLaunchRuntime()
_ = staleRuntime.launch(cachedPulse: nil)
let staleFirstAttemptID = staleRuntime.readinessAttemptID
_ = staleRuntime.completeLoginHandoff(.succeeded)
let staleSecondAttemptID = staleRuntime.readinessAttemptID
let staleReadinessFailure = staleRuntime.completeReadinessProbe(.failed, attemptID: staleFirstAttemptID)
let staleReadinessReady = staleRuntime.completeReadinessProbe(.ready, attemptID: staleSecondAttemptID)
let staleReadinessComplete = staleRuntime.completeFirstFetch(.succeeded(changedPulse))
let staleLateFailure = staleRuntime.completeReadinessProbe(.missingClaudeLogin, attemptID: staleFirstAttemptID)
try check(
    staleReadinessFailure.effect == .none
        && staleReadinessFailure.descriptor.statusTitle == "Checking Claude"
        && staleReadinessReady.effect == .startFirstFetch
        && staleReadinessComplete.descriptor.statusTitle == changedPulse.descriptor.statusTitle
        && staleLateFailure.descriptor.statusTitle == changedPulse.descriptor.statusTitle
        && freshnessRefreshDetailsAction(in: staleLateFailure.descriptor)?.role == .fetchRetry,
    "launch runtime should ignore stale readiness completions from earlier attempts"
)
let staleCachedFailureRuntime = PDTLaunchRuntime()
_ = staleCachedFailureRuntime.launch(cachedPulse: caughtUpPulse)
let staleCachedFailureFirstAttemptID = staleCachedFailureRuntime.readinessAttemptID
_ = staleCachedFailureRuntime.completeLoginHandoff(.succeeded)
let staleCachedFailureSecondAttemptID = staleCachedFailureRuntime.readinessAttemptID
_ = staleCachedFailureRuntime.completeReadinessProbe(.ready, attemptID: staleCachedFailureSecondAttemptID)
_ = staleCachedFailureRuntime.completeBackgroundDetailRefresh(.failed("scripted details fill failed"))
let staleCachedFailure = staleCachedFailureRuntime.completeReadinessProbe(
    .failed,
    attemptID: staleCachedFailureFirstAttemptID
)
try check(
    staleCachedFailure.descriptor.sections.flatMap(\.rows).map(\.title).contains("Details fill failed")
        && staleCachedFailure.descriptor.sections.flatMap(\.rows).map(\.title).contains("Fill details again")
        && freshnessRefreshDetailsAction(in: staleCachedFailure.descriptor) == nil,
    "stale readiness completions should preserve cached fetch failure copy"
)
let staleSetupRuntime = PDTLaunchRuntime()
_ = staleSetupRuntime.launch(cachedPulse: caughtUpPulse)
let staleSetupFirstAttemptID = staleSetupRuntime.readinessAttemptID
_ = staleSetupRuntime.completeLoginHandoff(.succeeded)
let staleSetupSecondAttemptID = staleSetupRuntime.readinessAttemptID
_ = staleSetupRuntime.completeReadinessProbe(.missingPDTMCP, attemptID: staleSetupSecondAttemptID)
let staleSetupFailure = staleSetupRuntime.completeReadinessProbe(.failed, attemptID: staleSetupFirstAttemptID)
try check(
    staleSetupFailure.descriptor.statusTitle == "Add the PDT MCP server to Claude"
        && staleSetupFailure.descriptor.sections.flatMap(\.rows).map(\.title).contains("Check again")
        && freshnessRefreshDetailsAction(in: staleSetupFailure.descriptor) == nil,
    "stale readiness completions should preserve active setup copy"
)
try check(
    setupDescriptor.sections.map(\.id) == ["claudeSetup"],
    "logged-out real launch should render a Claude-only setup section"
)
try check(
    setupSurface.sections.flatMap(\.rows).map(\.title) == ["Not connected", "Log in with Claude"],
    "logged-out real launch should render Claude setup title and login rows"
)
try check(
    setupSurface.sections.flatMap(\.rows).map(\.detail) == ["Use Claude CLI for PDT", nil],
    "logged-out real launch should expose setup detail as secondary row text"
)
try check(
    openingClaudeDescriptor.sections.flatMap(\.rows).map(\.title) == ["Signing in with Claude", "Try login again"],
    "login handoff should render progress and a retry action while claude auth login is running"
)
try check(
    ClaudeLaunchFlow.action(afterLoginHandoff: .succeeded) == .recheckReadiness,
    "successful login handoff should re-run readiness before deciding the next onboarding state"
)
try check(
    ClaudeLaunchFlow.action(afterLoginHandoff: .failed) == .showMissingClaude,
    "failed login handoff should render the retryable missing-Claude setup state"
)
try check(
    missingClaudeDescriptor.sections.flatMap(\.rows).map(\.title) == ["Claude CLI not found", "Log in with Claude"],
    "failed login handoff should render missing-Claude setup state with a retryable login action"
)
try check(
    ClaudeLaunchFlow.descriptor(forLoginFailure: .timedOut).sections.flatMap(\.rows).map(\.title) == [
        "Claude login timed out",
        "Log in with Claude",
    ],
    "timed-out claude auth login should render CodexBar-aligned login failure copy"
)
try check(
    ClaudeLaunchFlow.descriptor(forLoginFailure: .failed).sections.flatMap(\.rows).map(\.title) == [
        "Claude login failed",
        "Log in with Claude",
    ],
    "failed claude auth login should render CodexBar-aligned login failure copy"
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
    missingPDTMCPDescriptor.sections.flatMap(\.rows).map(\.title) == ["Add the PDT MCP server to Claude", "Log in with Claude", "Check again"],
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
try check(
    StatusVisualState().barHeights == [0.5, 1.0, 0.667],
    "unknown weights should default to the deterministic concentration-stack silhouette"
)
try check(
    descriptor.statusVisual.barHeights[1] == 1.0,
    "diversified quiet descriptor should render the middle concentration bar at max height"
)
try check(
    descriptor.statusVisual.barHeights == StatusVisualState().barHeights,
    "missing X-ray data should use the deterministic fallback silhouette"
)
var twoETFDirectModel = decoded
twoETFDirectModel.facetSnapshots.allocation.openHoldingCount = 2
twoETFDirectModel.facetSnapshots.allocation.topHoldings = Array(twoETFDirectModel.facetSnapshots.allocation.topHoldings.prefix(2))
twoETFDirectModel.facetSnapshots.allocation.topHoldings[0].weight = 0.5
twoETFDirectModel.facetSnapshots.allocation.topHoldings[1].weight = 0.5
let twoETFDirectHeights = MenuDescriptorRenderer.render(model: twoETFDirectModel).statusVisual.barHeights
var twoETFLikeModel = twoETFDirectModel
twoETFLikeModel.facetSnapshots.allocation.xRayHoldings = decoded.facetSnapshots.allocation.topHoldings.map {
    XRayHoldingSummary(weight: $0.weight)
}
let twoETFXRayHeights = MenuDescriptorRenderer.render(model: twoETFLikeModel).statusVisual.barHeights
try check(
    twoETFDirectHeights == StatusVisualState().barHeights
        && twoETFXRayHeights[0] != twoETFDirectHeights[0]
        && twoETFXRayHeights[2] > twoETFXRayHeights[0]
        && twoETFXRayHeights[1] == 1.0
        && twoETFDirectHeights[1] == 1.0,
    "X-ray look-through weights should scale the side silhouette while the middle bar remains max height"
)
var concentratedXRayModel = twoETFDirectModel
concentratedXRayModel.facetSnapshots.allocation.xRayHoldings = [
    XRayHoldingSummary(weight: 0.5),
    XRayHoldingSummary(weight: 0.5),
]
let concentratedXRayHeights = MenuDescriptorRenderer.render(model: concentratedXRayModel).statusVisual.barHeights
try check(
    concentratedXRayHeights[0] < twoETFXRayHeights[0]
        && concentratedXRayHeights[2] < twoETFXRayHeights[2]
        && concentratedXRayHeights[1] == 1.0,
    "high X-ray concentration should scale side bars downward from the default silhouette"
)
var skewedXRayModel = twoETFDirectModel
skewedXRayModel.facetSnapshots.allocation.xRayHoldings = [
    XRayHoldingSummary(weight: 0.62),
    XRayHoldingSummary(weight: 0.18),
    XRayHoldingSummary(weight: 0.10),
    XRayHoldingSummary(weight: 0.06),
    XRayHoldingSummary(weight: 0.04),
]
let skewedXRayHeights = MenuDescriptorRenderer.render(model: skewedXRayModel).statusVisual.barHeights
try check(
    skewedXRayHeights[0] < twoETFXRayHeights[0]
        && skewedXRayHeights[2] > skewedXRayHeights[0]
        && skewedXRayHeights[1] == 1.0,
    "skewed X-ray concentration should lower the side silhouette while keeping the right side taller than the left"
)
try check(descriptorObject.keys.contains("statusBadge"), "descriptor JSON should explicitly encode statusBadge")
try check(descriptorObject.keys.contains("statusVisual"), "descriptor JSON should encode the plain status visual state")
try check(
    descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness", "actions"],
    "descriptor should expose drill-down sections and top-level actions"
)
try check(
    descriptor.sections.first { $0.id == "actions" }?.rows.map(\.id) == ["actions.refreshNow", "actions.openPDT"]
        && descriptor.sections.first { $0.id == "actions" }?.rows.first?.role == .fetchRetry
        && descriptor.sections.first { $0.id == "actions" }?.rows.last?.role == .openPDT,
    "descriptor should expose Refresh now and Open PDT as typed top-level actions"
)
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
    shortVisual.barHeights == [0.9, 1.0, 0.667]
        && shortVisual.filledBarCount == 3
        && shortVisual.isDimmed
        && shortVisual.statusCopy == "Decoded status",
    "decoded status visual state should normalize to a max-height middle bar and capped fill count"
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
        == ["pulse.quiet.value", "pulse.quiet.holdings", "pulse.quiet.topAllocation", "pulse.quiet.freshness"],
    "quiet pulse row should expose compact portfolio overview readouts"
)
try check(
    descriptor.sections.map(\.accessibilityIdentifier) == [
        "pdtbar.section.pulse",
        "pdtbar.section.allocation",
        "pdtbar.section.income",
        "pdtbar.section.bigMovers",
        "pdtbar.section.freshness",
        "pdtbar.section.actions",
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
let quietAllocationRows = try require(
    descriptor.sections.first { $0.id == "allocation" }?.rows,
    "descriptor should expose allocation rows"
)
let portfolioAllocationRow = try require(
    quietAllocationRows.first,
    "allocation section should start with a portfolio allocation chart row"
)
let portfolioDetailsRow = try require(
    quietAllocationRows.dropFirst().first,
    "allocation section should place detailed info below the portfolio allocation chart"
)
let expectedPortfolioDetails = "Top \(PortfolioOverview.topHoldingLimit) of 9 holdings"
try check(
    portfolioAllocationRow.id == "allocation.portfolio"
        && portfolioAllocationRow.role == MenuRowRole.portfolioOverviewChart
        && portfolioAllocationRow.detail == nil
        && portfolioAllocationRow.barChart?.bars.map(\.label)
            == ["Nova", "Orbit", "Helix", "Atlas", "Axis"]
        && portfolioAllocationRow.barChart?.bars.map(\.axisLabel)
            == ["N", "O", "H", "A", "A"]
        && portfolioDetailsRow.id == "allocation.portfolio.details"
        && portfolioDetailsRow.role == MenuRowRole.portfolioOverviewDetails
        && portfolioDetailsRow.detail == expectedPortfolioDetails,
    "allocation section should render bounded portfolio allocation chart before detailed info"
)
try check(
    portfolioDetailsRow.children.prefix(5).map { $0.id } == [
        "allocation.portfolio.holdings",
        "allocation.portfolio.concentration",
        "allocation.portfolio.sectors",
        "allocation.portfolio.assetTypes",
        "allocation.portfolio.cash",
    ],
    "portfolio detailed info submenu should expose holdings, concentration, sectors, asset types, and cash"
)
try check(
    portfolioDetailsRow.children.dropFirst(5).first?.id == "allocation.9001",
    "portfolio detailed info submenu should expose individual holding drill-down rows"
)
try check(
    portfolioDetailsRow.children.first { $0.id == "allocation.portfolio.holdings.remainder" }?.title
        == "4 more holdings",
    "portfolio detailed info submenu should expose a remainder affordance when holdings are capped"
)
try check(
    portfolioDetailsRow.children.dropFirst(5).first?
        .children.first { $0.id == "allocation.9001.isin" }?.detail == "NL0000000001",
    "portfolio detailed info submenu should expose sanitized ISIN when available"
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
    descriptor.sections.first { $0.id == "freshness" }?.rows.map(\.id) == ["freshness.summary", "dataHealth"],
    "quiet freshness rows should expose stable freshness and data-health ids"
)
try check(
    descriptor.sections.first { $0.id == "freshness" }?.rows.first?.detail == "Fresh",
    "quiet descriptor should render freshness from model facts"
)
let quietFreshnessRow = try require(
    descriptor.sections.first { $0.id == "freshness" }?.rows.first,
    "quiet descriptor should expose freshness summary row"
)
let quietDataHealthRow = try require(
    descriptor.sections.first { $0.id == "freshness" }?.rows.first { $0.id == "dataHealth" },
    "quiet descriptor should expose Data health row"
)
try check(
    decoded.facetSnapshots.dataHealth.status == .healthy
        && decoded.facetSnapshots.dataHealth.source.missingReadTools.isEmpty
        && decoded.facetSnapshots.dataHealth.source.readOnlyPolicy == .enforced,
    "quiet model should carry structured data-health source state"
)
try check(
    quietDataHealthRow.role == .dataHealthSummary
        && quietDataHealthRow.children.map(\.id) == [
            "dataHealth.source",
            "dataHealth.cache",
            "dataHealth.detailFill",
            "dataHealth.readState",
            "dataHealth.diagnostic",
        ]
        && quietDataHealthRow.children.first { $0.id == "dataHealth.source" }?.detail == "Claude ready; PDT ready; 7/7 read tools; read-only",
    "Data health row should expose source, cache, detail-fill, read-state, and diagnostic rows"
)
let missingToolHealth = DataHealth.build(
    DataHealthInput(
        claudeReadiness: .ready,
        pdtMCPReadiness: .ready,
        availableReadTools: Set(PDTReadTools.requiredV1).subtracting(["pdt-list-dividends"]),
        readOnlyPolicy: .enforced,
        pulseSource: nil,
        lastSuccessfulCompleteFetchAsOf: nil,
        cachedPulseAvailable: false,
        detailFill: .notStarted,
        freshness: FreshnessSnapshot(worstPriceAsOf: nil, stale: false),
        readState: PulseReadState()
    )
)
try check(
    missingToolHealth.status == .degraded
        && missingToolHealth.source.readTools == .missingRequired
        && missingToolHealth.source.missingReadTools == ["pdt-list-dividends"]
        && missingToolHealth.cache.summary == "No cached pulse",
    "Data health should flag missing required read tools deterministically"
)
let redactedDiagnosticHealth = DataHealth.build(
    DataHealthInput(
        claudeReadiness: .ready,
        pdtMCPReadiness: .ready,
        availableReadTools: Set(PDTReadTools.requiredV1),
        readOnlyPolicy: .enforced,
        pulseSource: .refreshedSnapshot,
        lastSuccessfulCompleteFetchAsOf: "2026-06-25",
        cachedPulseAvailable: true,
        detailFill: .degraded,
        freshness: FreshnessSnapshot(worstPriceAsOf: "2026-06-24", stale: false),
        readState: PulseReadState(),
        diagnostic: PDTDetailRefreshFailureDiagnostic(
            toolName: "pdt-list-symbol-prices",
            phase: .priceHistory,
            attemptCount: 2,
            category: .transientFailure,
            argumentShape: ["symbol_quote_id", "date_from", "date_to"]
        )
    )
)
try check(
    redactedDiagnosticHealth.status == .degraded
        && redactedDiagnosticHealth.diagnostic?.copyText.contains("argument_keys: date_from,date_to,symbol_quote_id") == true
        && redactedDiagnosticHealth.diagnostic?.copyText.contains("/Users/") == false,
    "Data health diagnostics should be copyable and redacted"
)
try check(
    decoded.facetSnapshots.freshness.status == .fresh
        && decoded.facetSnapshots.freshness.staleHoldingCount == 0
        && decoded.facetSnapshots.freshness.oldestRows.count == 3,
    "quiet model should carry structured freshness ledger detail"
)
try check(
    quietFreshnessRow.children.map(\.id) == [
        "freshness.staleCount",
        "freshness.oldestPrice",
        "freshness.oldestRows",
        "freshness.detailFill",
    ],
    "freshness summary should expose user-facing ledger detail rows without AppKit deriving facts"
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
try check(
    emptyHoldingsModel.facetSnapshots.freshness.status == .unknown,
    "empty open holdings should expose unknown freshness state"
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
try check(
    nonQuietDescriptor.statusVisual.barHeights == descriptor.statusVisual.barHeights,
    "attention items should not change concentration bar heights"
)
var twoAttentionModel = decoded
twoAttentionModel.allQuiet = false
twoAttentionModel.attentionItems = [attention, secondAttention]
twoAttentionModel.rankedAttentionItems = [attention, secondAttention]
try check(
    MenuDescriptorRenderer.render(model: twoAttentionModel).statusVisual.filledBarCount == 2,
    "two attention items should fill two notification bars"
)
try check(
    MenuDescriptorRenderer.render(model: twoAttentionModel).statusVisual.barHeights == descriptor.statusVisual.barHeights,
    "two attention items should still leave concentration bar heights unchanged"
)
var crowdedAttentionModel = decoded
crowdedAttentionModel.allQuiet = false
crowdedAttentionModel.attentionItems = [attention, secondAttention, thirdAttention, fourthAttention]
crowdedAttentionModel.rankedAttentionItems = [attention, secondAttention, thirdAttention, fourthAttention]
try check(
    MenuDescriptorRenderer.render(model: crowdedAttentionModel).statusVisual.filledBarCount == 3,
    "three or more attention items should cap at three filled notification bars"
)
try check(
    MenuDescriptorRenderer.render(model: crowdedAttentionModel).statusVisual.barHeights == descriptor.statusVisual.barHeights,
    "three or more attention items should still leave concentration bar heights unchanged"
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
        .first { $0.id == "allocation.portfolio.details" }?
        .children
        .first { $0.title == "Nova Lithography" },
    "allocation row should exist for incomplete attention metadata"
)
try check(
    incompleteAllocationRow.role == .allocationHolding
        && incompleteAllocationRow.detail == "11.7%",
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
let quietSnapshotDirectoryPermissions = try posixPermissions(of: quietSnapshotStore.directory)
let quietSnapshotFilePermissions = try posixPermissions(of: URL(fileURLWithPath: quietCommit.path))
try check(
    quietSnapshotDirectoryPermissions == 0o700,
    "SnapshotStore should protect snapshot directories with owner-only permissions"
)
try check(
    quietSnapshotFilePermissions == 0o600,
    "SnapshotStore should protect snapshot files with owner-only permissions"
)
try quietSnapshotStore.saveLastDetailRefreshDiagnostic(PDTDetailRefreshFailureDiagnostic(
    toolName: "pdt-list-symbol-prices",
    phase: .priceHistory,
    attemptCount: 1,
    category: .transientFailure,
    argumentShape: ["date_from", "date_to", "symbol_quote_id"]
))
let quietDiagnosticPermissions = try posixPermissions(
    of: quietSnapshotStore.directory.appending(path: "latest-detail-refresh-diagnostic.json")
)
try check(
    quietDiagnosticPermissions == 0o600,
    "SnapshotStore should protect diagnostic files with owner-only permissions"
)
try PulseReadStore(directory: quietSnapshotStore.directory).markRead("pulse:v1:sanitized:fingerprint")
let quietReadStatePermissions = try posixPermissions(
    of: quietSnapshotStore.directory.appending(path: "pulse-read-state.json")
)
try check(
    quietReadStatePermissions == 0o600,
    "PulseReadStore should protect shared state files with owner-only permissions"
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
    "pdt-list-x-ray-holdings?limit=500&offset=0": try mcpResult("""
    {
      "items": [
        { "weight": 25.0 },
        { "weight": 0.5 }
      ],
      "hasMore": false
    }
    """),
    "pdt-list-calendar-events?date_from=2026-03-29&date_to=2026-04-28&page=1&per_page=250": try mcpContent("""
    {
      "data": [
        { "date": "2026-03-29", "type": "no-events-today", "isEstimated": false, "symbolId": null, "symbolName": null },
        { "date": "2026-03-30", "type": "ex-dividend", "isEstimated": false, "symbolId": 5101, "symbolName": "Live Adapter Co" }
      ],
      "meta": { "last_page": 1 }
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
    { "id": 9101, "code": "LIVE", "symbolId": 5101 }
    """),
    "pdt-get-symbol?id=5101": try mcpContent("""
    { "id": 5101, "name": "Live Adapter Co", "isin": "NL0010273215" }
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
    scriptedLiveRun.model.facetSnapshots.allocation.topHoldings.first?.copyableIdentifier == "LIVE",
    "live data source should expose public quote code as copyable holding identifier"
)
try check(
    scriptedLiveRun.model.facetSnapshots.allocation.topHoldings.first?.isin == "NL0010273215",
    "live data source should enrich holdings with public symbol ISIN when available"
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
    scriptedLiveRun.model.facetSnapshots.allocation.xRayHoldings?.map(\.weight) == [0.25, 0.005],
    "live data source should normalize X-ray percentage weights including sub-1% holdings"
)
let partialXRayHeights = MenuDescriptorRenderer.render(model: scriptedLiveRun.model).statusVisual.barHeights
try check(
    partialXRayHeights[0] < 0.8
        && partialXRayHeights[1] == 1.0
        && partialXRayHeights[0] > StatusVisualState().barHeights[0]
        && partialXRayHeights[2] > StatusVisualState().barHeights[2],
    "partial X-ray coverage should use absolute portfolio weights instead of renormalizing to a full distribution"
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
    Set(scriptedConnector.calls).isSubset(of: Set(PDTReadTools.allowedV1)),
    "scripted connector path should call only allowed v1 read tools"
)
try check(
    PDTReadTools.requiredV1.allSatisfy { connectorCallCounts[$0] == 1 },
    "coalesced scripted connector fetch should call every required v1 read tool exactly once"
)
try check(
    connectorCallCounts["pdt-get-symbol"] == 1,
    "coalesced scripted connector fetch should opportunistically call symbol lookup when response is available"
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
    failure: .setupUnavailable("Claude needs PDT setup")
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
var degradedDetailResponses = scriptedConnectorResponses
degradedDetailResponses.removeValue(
    forKey: "pdt-list-symbol-prices?date_from=2026-03-22&date_to=2026-03-29&symbol_quote_id=9101"
)
let degradedDetailStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-progressive-detail-check")
defer {
    try? FileManager.default.removeItem(at: degradedDetailStore.directory)
}
let degradedDetailRefresh = try PDTBackgroundDetailRefresh(
    connector: ScriptedPDTMCPConnector(responses: degradedDetailResponses),
    snapshotStore: degradedDetailStore,
    asOf: "2026-03-29",
    options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
).refresh()
let degradedDetailSnapshot = try require(
    try degradedDetailStore.loadPriorSnapshot(),
    "degraded background detail refresh should commit a partial snapshot"
)
try check(degradedDetailRefresh.outcome == .degraded, "missing optional price history should degrade, not abort")
try check(
    degradedDetailRefresh.model.facetSnapshots.freshness.status == .partial
        && degradedDetailRefresh.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == nil,
    "degraded background detail refresh should feed partial freshness state"
)
try check(
    degradedDetailSnapshot.sectors.count == 1
        && degradedDetailSnapshot.xRayHoldings?.count == 2
        && degradedDetailSnapshot.incomeEvents.count == 1
        && degradedDetailSnapshot.priceSeries.isEmpty,
    "degraded background detail refresh should preserve completed allocation, X-ray, and income phases"
)
let degradedDetailDiagnostic = try require(
    try degradedDetailStore.loadLastDetailRefreshDiagnostic(),
    "degraded background detail refresh should persist a redacted diagnostic"
)
try check(
    degradedDetailDiagnostic.toolName == "pdt-list-symbol-prices"
        && degradedDetailDiagnostic.phase == .priceHistory
        && degradedDetailDiagnostic.argumentShape == ["date_from", "date_to", "symbol_quote_id"]
        && degradedDetailDiagnostic.category == .missingScriptedResponse,
    "detail refresh diagnostic should keep only tool, phase, category, attempts, and argument shape"
)
let repairedDetailRefresh = try PDTBackgroundDetailRefresh(
    connector: ScriptedPDTMCPConnector(responses: scriptedConnectorResponses),
    snapshotStore: degradedDetailStore,
    asOf: "2026-03-29",
    options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
).refresh()
let repairedDetailDiagnostic = try degradedDetailStore.loadLastDetailRefreshDiagnostic()
try check(repairedDetailRefresh.outcome == .completed, "retry after degraded detail refresh should complete with full data")
try check(
    repairedDetailRefresh.model.facetSnapshots.bigMovers.priceSeriesCount == 2
        && repairedDetailRefresh.model.facetSnapshots.freshness.status == .fresh
        && repairedDetailRefresh.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-03-29"
        && repairedDetailDiagnostic == nil,
    "completed detail retry should restore price data, record latest complete detail fill, and clear the last diagnostic"
)
let baseRetryStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-required-base-retry-check")
defer {
    try? FileManager.default.removeItem(at: baseRetryStore.directory)
}
private let baseRetryConnector = OneShotFailingPDTConnector(
    responses: scriptedConnectorResponses,
    failures: [
        "pdt-get-portfolio-holdings": .setupUnavailable("Claude did not call mcp__pdt__pdt-get-portfolio-holdings"),
    ]
)
let baseRetryRefresh = try PDTBackgroundDetailRefresh(
    connector: baseRetryConnector,
    snapshotStore: baseRetryStore,
    asOf: "2026-03-29",
    options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
).refresh()
try check(baseRetryRefresh.outcome == .completed, "required base holdings should retry a missing Claude tool call")
try check(
    baseRetryConnector.calls.filter { $0 == "pdt-get-portfolio-holdings" }.count == 2,
    "required base holdings retry should call holdings twice before completing"
)
let baseFailureStore = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-required-base-failure-check")
defer {
    try? FileManager.default.removeItem(at: baseFailureStore.directory)
}
do {
    _ = try PDTBackgroundDetailRefresh(
        connector: ScriptedPDTMCPConnector(
            responses: scriptedConnectorResponses,
            failure: .setupUnavailable("Claude did not call mcp__pdt__pdt-get-portfolio-holdings")
        ),
        snapshotStore: baseFailureStore,
        asOf: "2026-03-29",
        options: PDTBackgroundDetailRefreshOptions(priceHistoryConcurrencyLimit: 2, retryBackoffSeconds: 0)
    ).refresh()
    throw CheckFailure("required base holdings should fail after retry budget is exhausted")
} catch {
    let diagnostic = try require(
        try baseFailureStore.loadLastDetailRefreshDiagnostic(),
        "required base holdings failure should persist a redacted diagnostic"
    )
    try check(
        diagnostic.toolName == "pdt-get-portfolio-holdings"
            && diagnostic.phase == .baseHoldings
            && diagnostic.attemptCount == 2
            && diagnostic.category == .setupUnavailable
            && diagnostic.argumentShape.isEmpty,
        "required base holdings diagnostic should keep only tool, phase, category, attempts, and argument shape"
    )
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
    quietRunWithPrior.descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness", "actions"],
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
var replacedMalformedPriorFacts = replacedMalformedPrior
replacedMalformedPriorFacts?.latestCompleteDetailFillAsOf = nil
replacedMalformedPriorFacts?.latestDetailFillOutcome = nil
try check(
    replacedMalformedPriorFacts == quietSnapshot,
    "malformed prior snapshot should be replaced by the current committed snapshot"
)
try check(
    replacedMalformedPrior?.latestCompleteDetailFillAsOf == quietSnapshot.asOf
        && replacedMalformedPrior?.latestDetailFillOutcome == .completed,
    "full fixture run should stamp complete freshness detail metadata"
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
var loadedBigMoverFacts = loadedBigMoverSnapshot
loadedBigMoverFacts?.latestCompleteDetailFillAsOf = nil
loadedBigMoverFacts?.latestDetailFillOutcome = nil
try check(
    loadedBigMoverFacts == currentBigMoverSnapshot,
    "big-mover run should replace the prior snapshot with current holdings"
)
try check(
    loadedBigMoverSnapshot?.latestCompleteDetailFillAsOf == currentBigMoverSnapshot.asOf
        && loadedBigMoverSnapshot?.latestDetailFillOutcome == .completed,
    "big-mover full run should stamp complete freshness detail metadata"
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
let bigMoverCurrentExpansion = try require(
    bigMoverRun.descriptor.sections.first { $0.id == "pulse" }?
        .rows
        .first { $0.id == "bigMovers.move.9001.glance" }?
        .children
        .first { $0.id == "bigMovers.move.9001.currentValue" },
    "descriptor should expose big-mover current explanation fact as a nested row"
)
try check(
    bigMoverCurrentExpansion.title == "Current"
        && bigMoverCurrentExpansion.detail == "EUR 612.40",
    "big-mover descriptor should render supplied current explanation fact"
)
let bigMoverPriorExpansion = try require(
    bigMoverRun.descriptor.sections.first { $0.id == "pulse" }?
        .rows
        .first { $0.id == "bigMovers.move.9001.glance" }?
        .children
        .first { $0.id == "bigMovers.move.9001.priorValue" },
    "descriptor should expose big-mover prior explanation fact as a nested row"
)
try check(
    bigMoverPriorExpansion.title == "Prior"
        && bigMoverPriorExpansion.detail == "EUR 545.00",
    "big-mover descriptor should render supplied prior explanation fact"
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
        .first { $0.id == "income.ex-dividend.9003.currentValue" },
    "descriptor should expose income current explanation fact as a nested row"
)
try check(
    incomeExpansion.title == "Current"
        && incomeExpansion.detail == "2026-06-24",
    "income descriptor should render supplied current explanation fact"
)
let incomeRows = incomeRun.descriptor.sections.first { $0.id == "income" }?.rows ?? []
try check(
    incomeRows.map(\.id) == [
        "income.summary",
        "income.next",
        "income.quote.9003.ex-dividend.2026-06-24",
        "income.symbol.5009.ex-dividend.2026-07-02",
        "income.overflow.later",
    ],
    "income section should render calendar summary, capped preview, and overflow rows"
)
let incomeSummaryRow = incomeRows.first { $0.id == "income.summary" }
try check(
    incomeSummaryRow?.role == .incomeSummary
        && incomeSummaryRow?.title == "Income window"
        && incomeSummaryRow?.detail == "4 events through 2026-07-10; 2 confirmed, 2 estimated",
    "income section should summarize the calendar window"
)
let incomeNextRow = incomeRows.first { $0.id == "income.next" }
try check(
    incomeNextRow?.role == .incomeNext
        && incomeNextRow?.title == "Next income: Lumen Luxury"
        && incomeNextRow?.detail == "Dividend payment date on 2026-06-22; confirmed",
    "income section should expose the next income event"
)
try check(
    incomeNextRow?.children.map(\.id) == [
        "income.symbol.5007.payment-dividend.2026-06-22.date",
        "income.symbol.5007.payment-dividend.2026-06-22.kind",
        "income.symbol.5007.payment-dividend.2026-06-22.state",
    ],
    "income next-event row should expose stable detail row ids"
)
try check(
    incomeNextRow?.actionTarget?.kind == .incomeEvent
        && incomeNextRow?.actionTarget?.id == "income.symbol.5007.payment-dividend.2026-06-22"
        && incomeNextRow?.actionTarget?.incomeEvent?.eventID == "income.symbol.5007.payment-dividend.2026-06-22"
        && incomeNextRow?.actionTarget?.incomeEvent?.rowID == "income.next"
        && incomeNextRow?.actionTarget?.incomeEvent?.symbolId == 5007
        && incomeNextRow?.actionTarget?.incomeEvent?.quoteId == nil
        && incomeNextRow?.actionTarget?.incomeEvent?.date == "2026-06-22"
        && incomeNextRow?.actionTarget?.incomeEvent?.kind == "payment-dividend"
        && incomeNextRow?.actionTarget?.incomeEvent?.symbolName == "Lumen Luxury"
        && incomeNextRow?.actionTarget?.incomeEvent?.estimated == false,
    "income next-event row should expose an inert action target with stable event identity"
)
try check(
    incomeNextRow?.children.map(\.role) == [
        .incomeEventDate,
        .incomeEventKind,
        .incomeEventState,
    ],
    "income next-event detail rows should expose typed detail roles"
)
try check(
    incomeNextRow?.children.allSatisfy { child in
        child.actionTarget?.kind == .incomeEvent
            && child.actionTarget?.id == "income.symbol.5007.payment-dividend.2026-06-22"
            && child.actionTarget?.incomeEvent?.eventID == "income.symbol.5007.payment-dividend.2026-06-22"
            && child.actionTarget?.incomeEvent?.rowID == child.id
            && child.actionTarget?.incomeEvent?.symbolId == 5007
            && child.actionTarget?.incomeEvent?.kind == "payment-dividend"
    } == true,
    "income next-event detail rows should preserve parent event identity for future actions"
)
try check(
    incomeNextRow?.children.first { $0.id.hasSuffix(".kind") }?.detail == "Dividend payment date"
        && incomeNextRow?.children.first { $0.id.hasSuffix(".state") }?.detail == "Confirmed",
    "income next-event details should render descriptive kind and confirmed state"
)
let incomeOverflowRow = incomeRows.first { $0.id == "income.overflow.later" }
try check(
    incomeOverflowRow?.role == .incomeDrillDown
        && incomeOverflowRow?.title == "Later"
        && incomeOverflowRow?.children.map(\.id) == [
            "income.overflow.later.income.quote.9003.payment-dividend.2026-07-10",
        ],
    "income overflow row should expose later events through native children"
)
try check(
    incomeOverflowRow?.children.first?.detail == "Dividend payment date on 2026-07-10; estimated"
        && incomeOverflowRow?.children.first?.children.first { $0.id.hasSuffix(".state") }?.detail == "Estimated",
    "income overflow rows should visibly mark estimated payment events"
)
try check(
    incomeOverflowRow?.children.first?.actionTarget?.id == "income.quote.9003.payment-dividend.2026-07-10"
        && incomeOverflowRow?.children.first?.actionTarget?.incomeEvent?.rowID
            == "income.overflow.later.income.quote.9003.payment-dividend.2026-07-10"
        && incomeOverflowRow?.children.first?.children.allSatisfy { child in
            child.actionTarget?.incomeEvent?.eventID == "income.quote.9003.payment-dividend.2026-07-10"
                && child.actionTarget?.incomeEvent?.rowID == child.id
        } == true,
    "income overflow event rows and details should keep canonical event targets despite grouped row ids"
)
try check(
    Set(allRows(in: incomeRows).map(\.id)).count == allRows(in: incomeRows).count,
    "income section should expose unique row ids recursively"
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
var estimatedOnlyIncomeSnapshot = try PDTFixtureDataSource.snapshot(from: incomeFixture)
estimatedOnlyIncomeSnapshot.incomeEvents = [
    IncomeEventSummary(
        date: "2026-06-24",
        kind: "ex-dividend",
        symbolName: "Estimated Pressure Co",
        estimated: true,
        quoteId: 9011
    ),
]
let estimatedOnlyIncomeModel = PressureEngine.buildModel(from: estimatedOnlyIncomeSnapshot)
try check(
    !estimatedOnlyIncomeModel.rankedAttentionItems.contains { $0.facet == "income" },
    "estimated-only income events should stay out of pressure attention items"
)
let estimatedOnlyIncomeRows = MenuDescriptorRenderer.render(model: estimatedOnlyIncomeModel)
    .sections
    .first { $0.id == "income" }?
    .rows ?? []
try check(
    estimatedOnlyIncomeRows.first { $0.id == "income.next" }?.detail == "Ex-dividend date on 2026-06-24; estimated",
    "estimated-only income events should remain browsable with visible estimated state"
)

var joinedHoldingIncomeSnapshot = snapshot
joinedHoldingIncomeSnapshot.incomeEvents = [
    IncomeEventSummary(
        date: "2026-06-25",
        kind: "ex-dividend",
        symbolName: "Nova Lithography",
        estimated: false,
        quoteId: 9001
    ),
]
let joinedHoldingIncomeRows = MenuDescriptorRenderer.render(
    model: PressureEngine.buildModel(from: joinedHoldingIncomeSnapshot)
)
    .sections
    .first { $0.id == "allocation" }?
    .rows ?? []
let joinedHoldingIncomeRow = try require(
    joinedHoldingIncomeRows.first { $0.id == "allocation.portfolio.details" }?
        .children
        .first { $0.id == "allocation.9001" },
    "joined holding income check should find the holding row"
)
try check(
    joinedHoldingIncomeRow.children.first { $0.id == "allocation.9001.nextIncome" }?.detail
        == "Ex-dividend date on 2026-06-25; confirmed",
    "holding drill-down should show next joined ex-dividend event"
)

var estimatedHoldingIncomeSnapshot = snapshot
estimatedHoldingIncomeSnapshot.incomeEvents = [
    IncomeEventSummary(
        date: "2026-06-26",
        kind: "payment-dividend",
        symbolName: "Nova Lithography",
        estimated: true,
        quoteId: 9001
    ),
]
let estimatedHoldingIncomeModel = PressureEngine.buildModel(from: estimatedHoldingIncomeSnapshot)
let estimatedHoldingIncomeRow = try require(
    MenuDescriptorRenderer.render(model: estimatedHoldingIncomeModel)
        .sections
        .first { $0.id == "allocation" }?
        .rows
        .first { $0.id == "allocation.portfolio.details" }?
        .children
        .first { $0.id == "allocation.9001" },
    "estimated holding income check should find the holding row"
)
try check(
    estimatedHoldingIncomeRow.children.first { $0.id == "allocation.9001.nextIncome" }?.detail
        == "Dividend payment date on 2026-06-26; estimated",
    "holding drill-down should label estimated payment events without urgency"
)
try check(
    estimatedHoldingIncomeModel.rankedAttentionItems.isEmpty,
    "estimated holding income event should not create pressure by itself"
)

var absentHoldingIncomeSnapshot = snapshot
absentHoldingIncomeSnapshot.incomeEvents = [
    IncomeEventSummary(
        date: "2026-06-25",
        kind: "ex-dividend",
        symbolName: "Symbol-only Income Co",
        estimated: false,
        symbolId: 5001
    ),
    IncomeEventSummary(
        date: "not-a-date",
        kind: "payment-dividend",
        symbolName: "Nova Lithography",
        estimated: false,
        quoteId: 9001
    ),
    IncomeEventSummary(
        date: "2026-06-25",
        kind: "ex-dividend",
        symbolName: "Unheld Income Co",
        estimated: false,
        quoteId: 9999
    ),
]
let absentHoldingIncomeRow = try require(
    MenuDescriptorRenderer.render(model: PressureEngine.buildModel(from: absentHoldingIncomeSnapshot))
        .sections
        .first { $0.id == "allocation" }?
        .rows
        .first { $0.id == "allocation.portfolio.details" }?
        .children
        .first { $0.id == "allocation.9001" },
    "absent holding income check should find the holding row"
)
try check(
    !absentHoldingIncomeRow.children.contains { $0.id == "allocation.9001.nextIncome" },
    "holding drill-down should omit income row when no joined valid event exists"
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

var longIncomeModel = decoded
longIncomeModel.asOf = "2026-06-22"
longIncomeModel.facetSnapshots.income.upcomingEvents = [
    IncomeEventSummary(date: "2026-06-22", kind: "payment-dividend", symbolName: "Anchor Pay A", estimated: false, quoteId: 9300),
    IncomeEventSummary(date: "2026-06-22", kind: "payment-dividend", symbolName: "Anchor Pay B", estimated: false, quoteId: 9301),
    IncomeEventSummary(date: "2026-06-22", kind: "payment-dividend", symbolName: "Anchor Pay C", estimated: false, quoteId: 9302),
    IncomeEventSummary(date: "2026-06-22", kind: "payment-dividend", symbolName: "Overflow Next", estimated: false, quoteId: 9303),
    IncomeEventSummary(date: "2026-06-23", kind: "ex-dividend", symbolName: "Near Ex", estimated: true, quoteId: 9304),
    IncomeEventSummary(date: "2026-06-26", kind: "ex-dividend", symbolName: "Overflow Week", estimated: false, quoteId: 9305),
    IncomeEventSummary(date: "2026-07-01", kind: "payment-dividend", symbolName: "Overflow Later", estimated: true, quoteId: 9306),
]
let longIncomeRows = MenuDescriptorRenderer.render(model: longIncomeModel)
    .sections
    .first { $0.id == "income" }?
    .rows ?? []
let longPreviewRows = longIncomeRows.filter { $0.role == .incomeNext || $0.role == .incomeEvent }
let longOverflowRows = longIncomeRows.filter { $0.role == .incomeDrillDown }
try check(
    longIncomeRows.prefix(2).map(\.id) == ["income.summary", "income.next"],
    "long income calendar should summarize first, then show the next event"
)
try check(
    longIncomeRows.first?.detail == "7 events through 2026-07-01; 5 confirmed, 2 estimated",
    "long income calendar should summarize the calendar window and estimated state"
)
try check(
    longPreviewRows.count == IncomeCalendarDescriptor.previewLimit,
    "long income calendar should cap direct preview rows at the configured preview limit"
)
try check(
    longPreviewRows.map(\.title) == ["Next income: Anchor Pay A", "Anchor Pay B", "Anchor Pay C"],
    "long income calendar should keep only the next event and capped preview in the main event rows"
)
try check(
    longOverflowRows.map(\.id) == ["income.overflow.next", "income.overflow.this-week", "income.overflow.later"],
    "long income calendar should group overflow into next, this week, and later buckets"
)
try check(
    longOverflowRows.first { $0.id == "income.overflow.next" }?.children.map(\.title) == ["Overflow Next"],
    "long income calendar should anchor next overflow to the model as-of next event date"
)
try check(
    longOverflowRows.first { $0.id == "income.overflow.this-week" }?.children.map(\.title) == ["Near Ex", "Overflow Week"],
    "long income calendar should anchor this-week overflow to the model as-of week"
)
try check(
    longOverflowRows.first { $0.id == "income.overflow.later" }?.children.map(\.title) == ["Overflow Later"],
    "long income calendar should keep later overflow reachable"
)
let longIncomeAllRows = allRows(in: longIncomeRows)
try check(
    Set(longIncomeAllRows.map(\.id)).count == longIncomeAllRows.count,
    "long income calendar should expose unique row ids recursively"
)
try check(
    longIncomeAllRows.allSatisfy { !$0.id.isEmpty && $0.accessibilityIdentifier == "pdtbar.row.\($0.id)" },
    "long income calendar should expose stable accessibility ids recursively"
)
var futureNextIncomeModel = longIncomeModel
futureNextIncomeModel.facetSnapshots.income.upcomingEvents = [
    IncomeEventSummary(date: "2026-07-01", kind: "payment-dividend", symbolName: "Future Pay A", estimated: false, quoteId: 9310),
    IncomeEventSummary(date: "2026-07-01", kind: "payment-dividend", symbolName: "Future Pay B", estimated: false, quoteId: 9311),
    IncomeEventSummary(date: "2026-07-01", kind: "payment-dividend", symbolName: "Future Pay C", estimated: false, quoteId: 9312),
    IncomeEventSummary(date: "2026-07-01", kind: "payment-dividend", symbolName: "Future Pay D", estimated: false, quoteId: 9313),
]
let futureNextOverflowRows = MenuDescriptorRenderer.render(model: futureNextIncomeModel)
    .sections
    .first { $0.id == "income" }?
    .rows
    .filter { $0.role == .incomeDrillDown } ?? []
try check(
    futureNextOverflowRows.map(\.id) == ["income.overflow.next"],
    "future next-date overflow should not duplicate into the later bucket"
)

var semanticIncomeModel = decoded
semanticIncomeModel.asOf = "2026-06-22"
semanticIncomeModel.facetSnapshots.income.upcomingEvents = [
    IncomeEventSummary(
        date: "2026-06-24",
        kind: "payment-dividend",
        symbolName: "Same Day Pay",
        estimated: false,
        quoteId: 9401
    ),
    IncomeEventSummary(
        date: "2026-06-24",
        kind: "ex-dividend",
        symbolName: "Same Day Ex",
        estimated: false,
        quoteId: 9400,
        amount: Money(value: "78.00", currency: "EUR"),
        priorAmount: Money(value: "66.00", currency: "EUR"),
        changePercent: 0.1818
    ),
    IncomeEventSummary(
        date: "2026-06-26",
        kind: "payment-dividend",
        symbolName: "Estimated Pay",
        estimated: true,
        quoteId: 9402,
        amount: Money(value: "10.00", currency: "EUR"),
        changePercent: -0.25
    ),
]
let semanticIncomeRows = MenuDescriptorRenderer.render(model: semanticIncomeModel)
    .sections
    .first { $0.id == "income" }?
    .rows ?? []
try check(
    semanticIncomeRows.map(\.title) == [
        "Income window",
        "Next income: Same Day Ex",
        "Same Day Pay",
        "Estimated Pay",
    ],
    "income events should order by date first and ex-dividend priority on the same date"
)
let semanticNextRow = try require(
    semanticIncomeRows.first { $0.id == "income.next" },
    "semantic income rows should include a next row"
)
try check(
    semanticNextRow.detail == "Ex-dividend date on 2026-06-24; confirmed; EUR 78.00; +18.2% from EUR 66.00",
    "ex-dividend rows should render descriptive copy, amount, change, and confirmed state"
)
try check(
    semanticNextRow.children.first { $0.id.hasSuffix(".change") }?.detail == "+18.2% from EUR 66.00",
    "income change details should include prior amount when available"
)
try check(
    semanticIncomeRows.first { $0.id == "income.quote.9401.payment-dividend.2026-06-24" }?.detail == "Dividend payment date on 2026-06-24; confirmed",
    "payment rows should render distinct descriptive copy"
)
let unsafeEstimatedPayRow = try require(
    semanticIncomeRows.first { $0.id == "income.quote.9402.payment-dividend.2026-06-26" },
    "semantic income rows should include estimated payment row"
)
try check(
    unsafeEstimatedPayRow.detail == "Dividend payment date on 2026-06-26; estimated; EUR 10.00"
        && unsafeEstimatedPayRow.children.contains { $0.id.hasSuffix(".change") } == false,
    "income rows should show estimated state and omit unsafe change details"
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
    concentrationRun.model.rankedAttentionItems.count == 2,
    "concentration fixture should produce holding and sector attention items"
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
    concentrationItem.detail == "24.2%",
    "cold-start concentration copy should stay compact"
)
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("sell"), "copy should not prescribe selling")
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("buy"), "copy should not prescribe buying")
try check(!concentrationItem.detail.localizedCaseInsensitiveContains("should"), "copy should not be prescriptive")
try check(concentrationRun.descriptor.statusBadge == "2", "descriptor should expose a badge")
let concentrationSurface = MenuBarSurfaceRenderer.render(descriptor: concentrationRun.descriptor)
try check(
    concentrationRun.descriptor.statusVisual.filledBarCount == 2,
    "concentration descriptor should fill one notification bar per allocation pressure item"
)
try check(
    concentrationRun.descriptor.statusVisual.isDimmed,
    "stale concentration descriptor may dim the whole icon without lowering attention fill"
)
let concentrationSnapshot = try PDTFixtureDataSource.snapshot(from: concentrationFixture)
let quietPriorSnapshot = try PDTFixtureDataSource.snapshot(from: fixture)
let crossingConcentrationModel = PressureEngine.buildModel(
    from: concentrationSnapshot,
    priorSnapshot: quietPriorSnapshot
)
try check(
    crossingConcentrationModel.rankedAttentionItems.first { $0.id == "allocation.concentration.9001" }?.detail == "24.2%",
    "concentration copy should stay compact when prior snapshot was below the line"
)
let repeatedConcentrationModel = PressureEngine.buildModel(
    from: concentrationSnapshot,
    priorSnapshot: concentrationSnapshot
)
try check(
    !repeatedConcentrationModel.rankedAttentionItems.contains { $0.id == "allocation.concentration.9001" },
    "holding concentration pressure should not repeat when the prior snapshot was already over the line"
)
try check(
    concentrationRun.descriptor.statusVisual.barHeights == StatusVisualState().barHeights,
    "concentration fixture without X-ray data should keep the fallback silhouette"
)
try check(
    concentrationRun.descriptor.statusVisual.barHeights[1] == 1.0,
    "concentration fixture should keep the middle bar at max visual height"
)
try check(
    concentrationSurface.status.badge == "2",
    "fixture launch surface should render non-quiet descriptor badge"
)
try check(
    concentrationSurface.status.menuBarTitle.isEmpty,
    "pressure fixture launch surface should keep status text out of the menu bar title"
)
try check(
    concentrationSurface.sections.first { $0.id == "pulse" }?.rows.dropFirst().allSatisfy {
        $0.role == .pulseAttention
    } == true,
    "fixture launch surface should keep attention items compact at the top level"
)
try check(
    concentrationRun.descriptor.sections.first?.rows.first { $0.role == .pulseAttention }?.children.contains {
        $0.role == .pulseAttentionExpansion
    } == true,
    "descriptor should expose pulse attention expansion rows as a nested drill-down"
)
let allocationRows = concentrationRun.descriptor.sections.first { $0.id == "allocation" }?.rows ?? []
let detailedAllocationRows = allocationRows.first { $0.id == "allocation.portfolio.details" }?.children ?? []
let allocationDrillDownRow = detailedAllocationRows.first {
    $0.role == .allocationDrillDown && $0.title == "Nova Lithography"
}
try check(
    detailedAllocationRows.filter { $0.role == .allocationHolding || $0.role == .allocationDrillDown }.count
        == PortfolioOverview.topHoldingLimit
        && detailedAllocationRows.first { $0.id == "allocation.portfolio.holdings.remainder" }?.title
            == "\(concentrationRun.model.facetSnapshots.allocation.openHoldingCount - PortfolioOverview.topHoldingLimit) more holdings",
    "detailed allocation drill-down should list a bounded top set plus remainder"
)
try check(
    allocationDrillDownRow?.detail == "24.2%",
    "descriptor should expose allocation drill-down for the item"
)
try check(
    concentrationRun.descriptor.sections.first { $0.id == "freshness" }?.rows.first?.detail == "2 stale; oldest 2026-06-18",
    "descriptor should render stale freshness ledger facts"
)

let holdingFactsFixtureDirectory = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-holding-facts-fixture")
defer {
    try? FileManager.default.removeItem(at: holdingFactsFixtureDirectory.directory)
}
let holdingFactsFixture = holdingFactsFixtureDirectory.directory.appending(path: "holding-facts.json")
try Data("""
{
  "_meta": { "asOf": "2026-06-22", "portfolioCurrency": "EUR" },
  "getPortfolioHoldings": {
    "holdings": [
      {
        "symbolName": "Core Facts Holding",
        "symbolQuoteId": 9601,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "50.00", "currency": "EUR" },
        "currentWorth": { "value": "1000.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "1000.00", "currency": "EUR" },
        "portfolioWeight": 0.10,
        "unrealisedBoughtPriceAverageLocal": { "value": "40.00", "currency": "EUR" },
        "unrealisedBoughtPriceTotalLocal": { "value": "9999.00", "currency": "EUR" },
        "unrealisedBoughtShares": 10,
        "unrealisedGains": { "value": "200.00", "currency": "EUR" },
        "unrealisedGainsPercentage": 0.25,
        "totalGains": { "value": "9999.00", "currency": "EUR" },
        "totalGainsPercentage": 9.99,
        "closedAt": null
      },
      {
        "symbolName": "Fallback Facts Holding",
        "symbolQuoteId": 9602,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "25.00", "currency": "EUR" },
        "currentWorth": { "value": "500.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "500.00", "currency": "EUR" },
        "portfolioWeight": 0.05,
        "unrealisedBoughtPriceTotalLocal": { "value": "300.00", "currency": "EUR" },
        "unrealisedBoughtShares": 12,
        "closedAt": null
      },
      {
        "symbolName": "Sparse Facts Holding",
        "symbolQuoteId": 9603,
        "currentPriceDate": "2026-06-22T23:59:59+00:00",
        "currentPriceLocal": { "value": "not-a-number", "currency": "EUR" },
        "currentWorth": { "value": "400.00", "currency": "EUR" },
        "currentWorthLocal": { "value": "400.00", "currency": "EUR" },
        "portfolioWeight": 0.04,
        "unrealisedBoughtPriceAverageLocal": { "value": "not-a-number", "currency": "EUR" },
        "unrealisedBoughtPriceTotalLocal": { "value": "100.00", "currency": "EUR" },
        "unrealisedBoughtShares": 0,
        "unrealisedGains": { "value": "not-a-number", "currency": "EUR" },
        "unrealisedGainsPercentage": "not-a-number",
        "totalGains": { "value": "777.00", "currency": "EUR" },
        "totalGainsPercentage": 7.77,
        "closedAt": null
      }
    ]
  },
  "listSymbolPrices": {
    "data": [
      { "date": "2026-06-22", "closeAdjusted": "50.00", "symbolQuoteId": 9601 },
      { "date": "2026-06-19", "closeAdjusted": "47.50", "symbolQuoteId": 9601 },
      { "date": "2026-06-18", "closeAdjusted": "45.00", "symbolQuoteId": 9601 },
      { "date": "2026-06-22", "closeAdjusted": "not-a-number", "symbolQuoteId": 9602 },
      { "date": "2026-06-21", "closeAdjusted": "25.00", "symbolQuoteId": 9602 },
      { "date": "2026-06-22", "closeAdjusted": "40.00", "symbolQuoteId": 9603 }
    ]
  },
  "getSymbolQuotes": [
    { "id": 9601, "code": "CORE", "symbolId": 5601 },
    { "id": 9602, "symbolId": 5602 },
    { "id": 9603, "code": "9603", "symbolId": 5603 }
  ]
}
""".utf8).write(to: holdingFactsFixture)
let holdingFactsDescriptor = MenuDescriptorRenderer.render(
    model: PressureEngine.buildModel(from: try PDTFixtureDataSource.snapshot(from: holdingFactsFixture))
)
let holdingFactsRow = try require(
    holdingFactsDescriptor.sections.first { $0.id == "allocation" }?
        .rows.first { $0.id == "allocation.portfolio.details" }?
        .children.first { $0.title == "Core Facts Holding" },
    "holding facts descriptor row should exist"
)
let holdingFactsChildren = holdingFactsRow.children
try check(
    holdingFactsRow.detail == "10.0%",
    "allocation parent row should keep inline portfolio weight"
)
try check(
    holdingFactsChildren.contains { $0.id == "allocation.9601.weight" || $0.title == "Weight" } == false,
    "allocation drill-down should omit duplicate child weight row"
)
try check(
    holdingFactsChildren.map(\.title).containsSequence([
        "Worth",
        "Price",
        "Average buy price",
        "Gain/loss",
        "Gain/loss %",
    ]),
    "allocation drill-down should render core holding fact rows"
)
try check(
    holdingFactsChildren.first { $0.title == "Average buy price" }?.detail == "EUR 40.00",
    "allocation drill-down should prefer explicit average buy price"
)
try check(
    holdingFactsChildren.first { $0.title == "Gain/loss" }?.detail == "EUR 200.00"
        && holdingFactsChildren.first { $0.title == "Gain/loss %" }?.detail == "+25.0%",
    "allocation drill-down should render unrealised gain/loss fields instead of total lifetime fields"
)
try check(
    holdingFactsChildren.first { $0.title == "Recent move" }?.detail == "+11.1% from 2026-06-18 to 2026-06-22",
    "allocation drill-down should render recent move percent with date window context"
)
let coreIdentifierAction = holdingFactsChildren.first { $0.id == "allocation.9601.copyIdentifier" }
try check(
    coreIdentifierAction?.role == .holdingIdentifierCopy
        && coreIdentifierAction?.title == "Copy identifier"
        && coreIdentifierAction?.detail == "CORE"
        && coreIdentifierAction?.actionTarget?.kind == .copyHoldingIdentifier
        && coreIdentifierAction?.actionTarget?.copyText == "CORE",
    "allocation drill-down should expose copy identifier action metadata for public quote codes"
)
let fallbackFactsChildren = try require(
    holdingFactsDescriptor.sections.first { $0.id == "allocation" }?
        .rows.first { $0.id == "allocation.portfolio.details" }?
        .children.first { $0.title == "Fallback Facts Holding" }?
        .children,
    "fallback holding descriptor row should exist"
)
try check(
    fallbackFactsChildren.first { $0.title == "Average buy price" }?.detail == "EUR 25.00",
    "allocation drill-down should compute average buy price from total and shares fallback"
)
try check(
    fallbackFactsChildren.map(\.title).contains("Recent move") == false,
    "allocation drill-down should omit recent move when price data is malformed"
)
try check(
    fallbackFactsChildren.contains { $0.id.hasSuffix(".copyIdentifier") } == false,
    "allocation drill-down should omit copy identifier action when no public quote code is present"
)
let sparseFactsChildren = try require(
    holdingFactsDescriptor.sections.first { $0.id == "allocation" }?
        .rows.first { $0.id == "allocation.portfolio.details" }?
        .children.first { $0.title == "Sparse Facts Holding" }?
        .children,
    "sparse holding descriptor row should exist"
)
try check(
    sparseFactsChildren.map(\.title).allSatisfy { ![
        "Price",
        "Recent move",
        "Average buy price",
        "Gain/loss",
        "Gain/loss %",
    ].contains($0) },
    "allocation drill-down should omit unavailable or malformed holding fact rows"
)
try check(
    sparseFactsChildren.contains { $0.id.hasSuffix(".copyIdentifier") } == false,
    "allocation drill-down should omit numeric-only quote codes that could be private identifiers"
)
let holdingFactsSurface = MenuBarSurfaceRenderer.render(descriptor: holdingFactsDescriptor)
let surfaceIdentifierAction = holdingFactsSurface.sections.first { $0.id == "allocation" }?
    .rows.first { $0.id == "allocation.portfolio.details" }?
    .children.first { $0.id == "allocation.9601" }?
    .children.first { $0.id == "allocation.9601.copyIdentifier" }
try check(
    surfaceIdentifierAction?.actionTarget?.kind == .copyHoldingIdentifier
        && surfaceIdentifierAction?.actionTarget?.copyText == "CORE",
    "menu surface rendering should preserve copy identifier action metadata"
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
        == "20.0%",
    "threshold concentration copy should describe equality compactly"
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
    try check(
        decoded.supportingDataSlots.map(\.id).contains("allocation.overview")
            && decoded.supportingDataSlots.count == 5,
        "\(fixture.lastPathComponent) should include supporting slots"
    )
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

private func allRows(in rows: [MenuRow]) -> [MenuRow] {
    rows.flatMap { row in
        [row] + allRows(in: row.children)
    }
}

private func freshnessRefreshDetailsAction(in descriptor: MenuDescriptor) -> MenuRow? {
    descriptor.sections
        .first { $0.id == "freshness" }?
        .rows
        .first { $0.id == "freshness.summary" }?
        .children
        .first { $0.id == "freshness.refreshDetails" }
}

private func containsAdviceLikeLanguage(_ value: String) -> Bool {
    let pattern = #"\b(buy|sell|rebalance|trim|reduce|recommend|should)\b"#
    return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

private extension Array where Element: Equatable {
    func containsSequence(_ sequence: [Element]) -> Bool {
        guard !sequence.isEmpty else { return true }
        var matchIndex = 0
        for element in self where element == sequence[matchIndex] {
            matchIndex += 1
            if matchIndex == sequence.count {
                return true
            }
        }
        return false
    }
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

private func posixPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try require(
        attributes[.posixPermissions] as? NSNumber,
        "expected POSIX permissions for \(url.path)"
    )
    return permissions.intValue & 0o777
}

private func temporaryPulseReadStore() throws -> PulseReadStore {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "pdtbar-checks-pulse-read-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return PulseReadStore(directory: directory)
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

fileprivate final class OneShotFailingPDTConnector: PDTMCPConnector, @unchecked Sendable {
    let responses: [String: Data]
    private var failures: [String: PDTMCPConnectorError]
    private let lock = NSLock()
    private(set) var calls: [String] = []

    init(responses: [String: Data], failures: [String: PDTMCPConnectorError]) {
        self.responses = responses
        self.failures = failures
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        if let failure = failures.removeValue(forKey: name) {
            lock.unlock()
            throw failure
        }
        lock.unlock()

        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw CheckFailure("missing scripted PDT response for \(key)")
        }
        return response
    }
}

private struct StaticPortfolioDataSource: PortfolioDataSource {
    var fixedSnapshot: PortfolioSnapshot

    init(snapshot: PortfolioSnapshot) {
        fixedSnapshot = snapshot
    }

    func snapshot(asOf: String?) throws -> PortfolioSnapshot {
        fixedSnapshot
    }
}

private func driftCheckSnapshot(weights: [Double], asOf: String = "2026-06-22") -> PortfolioSnapshot {
    PortfolioSnapshot(
        asOf: asOf,
        totalValue: Money(value: "1000.00", currency: "EUR"),
        openHoldings: weights.enumerated().map { offset, weight in
            NormalizedHolding(
                name: "Holding \(offset + 1)",
                quoteId: offset + 1,
                weight: weight,
                worth: Money(value: String(format: "%.2f", weight * 1000), currency: "EUR"),
                price: nil,
                priceAsOf: "2026-06-22"
            )
        },
        sectors: [],
        assetTypes: [],
        incomeEvents: [],
        dividendRowCount: 0,
        priceSeries: []
    )
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
