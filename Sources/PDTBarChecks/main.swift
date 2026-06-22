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

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
