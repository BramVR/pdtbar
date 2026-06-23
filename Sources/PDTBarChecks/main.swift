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
let descriptorObject = try require(
    JSONSerialization.jsonObject(with: try stableJSONData(descriptor)) as? [String: Any],
    "descriptor JSON should encode as an object"
)
try check(
    descriptor.statusTitle == "EUR 51,200.00 - All quiet",
    "quiet fixture descriptor should render the all-quiet status"
)
try check(descriptorObject.keys.contains("statusBadge"), "descriptor JSON should explicitly encode statusBadge")
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
        == "All quiet - No ranked attention items from the fixture.",
    "fixture launch surface should render row title and detail for AppKit menu rows"
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
    descriptor.sections.first { $0.id == "bigMovers" }?.rows.map(\.id) == ["bigMovers.summary"],
    "quiet big-mover rows should expose stable ids"
)
try check(
    descriptor.sections.first { $0.id == "freshness" }?.rows.map(\.id) == ["freshness.summary"],
    "quiet freshness rows should expose stable ids"
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
nonQuietModel.allQuiet = false
nonQuietModel.attentionItems = [attention]
nonQuietModel.rankedAttentionItems = [attention]
let nonQuietDescriptor = MenuDescriptorRenderer.render(model: nonQuietModel)
try check(
    nonQuietDescriptor.statusTitle == "EUR 51,200.00 - Nova concentration",
    "non-quiet descriptor should use the top attention item in status"
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
        .first { $0.id == "bigMovers.move.9001.expansion" },
    "descriptor should expose big-mover expansion row"
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
        .first { $0.id == "income.ex-dividend.9003.expansion" },
    "descriptor should expose income expansion row"
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
    concentrationSurface.status.badge == "1",
    "fixture launch surface should render non-quiet descriptor badge"
)
try check(
    concentrationSurface.status.menuBarTitle == "\(concentrationRun.descriptor.statusTitle) [1]",
    "fixture launch surface should render descriptor badge in the app-visible status title"
)
try check(
    concentrationSurface.sections.first { $0.id == "pulse" }?.rows.map(\.role)
        == [.pulseAttention, .pulseAttentionExpansion],
    "fixture launch surface should include pulse drill-down entries"
)
try check(
    concentrationRun.descriptor.sections.first?.rows.map(\.role) == [.pulseAttention, .pulseAttentionExpansion],
    "descriptor should expose pulse attention and expansion rows"
)
let allocationRows = concentrationRun.descriptor.sections.first { $0.id == "allocation" }?.rows ?? []
let allocationDrillDownRow = allocationRows.first {
    $0.role == .allocationDrillDown && $0.title == "Nova Lithography"
}
try check(
    allocationDrillDownRow?.detail == "24.2% of portfolio; concentration line 20.0%",
    "descriptor should expose allocation drill-down for the item"
)

for fixture in allFixtures {
    let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
    let model = PressureEngine.buildModel(from: snapshot)
    let modelJSON = try stableJSONData(model)
    let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: modelJSON)
    let descriptor = MenuDescriptorRenderer.render(model: decoded)
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
