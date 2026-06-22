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
try check(decoded.supportingDataSlots.map(\.id).contains("bigMovers.prices"), "model should expose supporting data slots")

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

let concentrationFixture = packageRoot.appending(path: "docs/pdt/fixtures/concentration-pressure.json")
let snapshotDirectory = FileManager.default.temporaryDirectory
    .appending(path: "pdtbar-checks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: snapshotDirectory)
}

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
