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
try check(
    descriptor.statusTitle == "EUR 51,200.00 - All quiet",
    "quiet fixture descriptor should render the all-quiet status"
)
try check(descriptor.sections.map(\.id) == ["pulse", "allocation", "income", "bigMovers", "freshness"], "descriptor should expose drill-down sections")

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
try check(legacyMenuRow.role == "row", "legacy menu row JSON should default missing role")

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
    incompleteAllocationRow.role == "allocationHolding"
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
try check(
    concentrationRun.descriptor.sections.first?.rows.map(\.role) == ["glance", "expansion"],
    "descriptor should expose glance and expansion rows"
)
try check(
    concentrationRun.descriptor.sections
        .first { $0.id == "allocation" }?
        .rows
        .contains {
            $0.role == "allocationDrillDown"
                && $0.title == "Nova Lithography"
                && $0.detail == "24.2% of portfolio; concentration line 20.0%"
        } == true,
    "descriptor should expose allocation drill-down for the item"
)

for fixture in allFixtures {
    let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
    let model = PressureEngine.buildModel(from: snapshot)
    let modelJSON = try stableJSONData(model)
    let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: modelJSON)
    let descriptor = MenuDescriptorRenderer.render(model: decoded)
    try check(!descriptor.sections.isEmpty, "\(fixture.lastPathComponent) should render menu sections")
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
