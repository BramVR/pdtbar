import Foundation
import PDTBarCore

let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fixtureNames = [
    "concentration-pressure.json",
    "income-event.json",
    "big-mover.json",
    "quiet-no-pressure.json",
    "worst-case-height.json",
]
let fixtures = fixtureNames.map { packageRoot.appending(path: "docs/pdt/fixtures/\($0)") }

try checkFixtureCorpus(fixtures)
try checkAPIFixtureProvenance()
try checkCoalescedAPIFirstFetch()
try checkAPIBackgroundDetailRefresh()
try checkPDTAPIDataHealth()
try checkProductSpawnsNothing()
try checkFormalCodeAnchors()
try checkNoEmptySafeExpectations()
try checkConcurrencyEscapeHatches()
try checkFeatureGuidesQuoteMenuCopy(fixtures)
try checkCommentCounts()
try checkVerifySkillNamesEveryCommand()
try checkCIRunsWhenCheckInputsChange()

print("pdtbar-checks: passed")

private func checkFixtureCorpus(_ fixtures: [URL]) throws {
    for fixture in fixtures {
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        let model = PressureEngine.buildModel(from: snapshot)
        let modelJSON = try stableJSONData(model)
        let decoded = try JSONDecoder().decode(PortfolioPulseModel.self, from: modelJSON)
        let descriptor = MenuDescriptorRenderer.render(model: decoded)

        try check(!descriptor.sections.isEmpty, "\(fixture.lastPathComponent) should render menu sections")
        try check(
            descriptor.statusAccessibilityIdentifier == "pdtbar.status",
            "\(fixture.lastPathComponent) should expose status accessibility id"
        )
        try check(
            descriptor.sections.allSatisfy { !$0.id.isEmpty && $0.accessibilityIdentifier == "pdtbar.section.\($0.id)" },
            "\(fixture.lastPathComponent) should expose stable section ids and accessibility ids"
        )
        let renderedRows = descriptor.sections.flatMap(\.rows)
        try check(
            Set(renderedRows.map(\.id)).count == renderedRows.count,
            "\(fixture.lastPathComponent) should expose unique top-level row ids"
        )
        try check(
            renderedRows.allSatisfy { !$0.id.isEmpty && $0.accessibilityIdentifier == "pdtbar.row.\($0.id)" },
            "\(fixture.lastPathComponent) should expose stable top-level row ids and accessibility ids"
        )
        try check(
            renderedRows.allSatisfy { $0.role != .row },
            "\(fixture.lastPathComponent) should expose typed top-level row roles"
        )
        try check(
            decoded.supportingDataSlots.map(\.id).contains("allocation.overview")
                && decoded.supportingDataSlots.count == 5,
            "\(fixture.lastPathComponent) should include supporting slots"
        )
        try check(
            !decoded.facetSnapshots.allocation.totalValue.value.contains(","),
            "\(fixture.lastPathComponent) should keep Money.value canonical"
        )
        try assertInformationalCopy(model: decoded, descriptor: descriptor, fixtureName: fixture.lastPathComponent)
    }
}

private func checkAPIFixtureProvenance() throws {
    struct Provenance: Decodable {
        struct Spec: Decodable {
            var version: String
        }

        struct Reply: Decodable {
            var file: String
            var request: String
        }

        var synthetic: Bool
        var spec: Spec
        var scenarios: [String: [Reply]]
    }
    let root = packageRoot.appending(path: "docs/pdt/fixtures/api")
    let provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: root.appending(path: "provenance.json")))
    try check(provenance.synthetic, "REST fixture provenance should mark the bodies synthetic")
    try check(
        !provenance.spec.version.trimmingCharacters(in: .whitespaces).isEmpty,
        "REST fixture provenance should name the PDT API spec version"
    )
    let scenarios = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map(\.lastPathComponent)
    try check(
        Set(provenance.scenarios.keys) == Set(scenarios),
        "REST fixture provenance should list exactly the scenario directories \(scenarios.sorted())"
    )
    for (scenario, replies) in provenance.scenarios {
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: scenario).path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        try check(
            replies.map(\.file) == files,
            "REST fixture provenance for \(scenario) should list every reply file: \(files)"
        )
        try check(
            replies.allSatisfy { $0.request.hasPrefix("GET /v1/") && ScriptedPDTHTTPTransport.Request(parsing: $0.request) != nil },
            "REST fixture provenance for \(scenario) should name a GET request for every reply"
        )
    }
}

private func checkCoalescedAPIFirstFetch() throws {
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-api-first-fetch-check")
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    let transport = ScriptedPDTHTTPTransport(["GET /v1/portfolio/holdings": checkHoldingsReply()])
    let firstFetch = PDTCoalescedFirstPortfolioFetch(
        dataSource: PDTAPIDataSource(client: checkAPIClient(transport), options: .firstFetch),
        snapshotStore: store,
        asOf: "2026-03-28"
    )
    let first = try firstFetch.fetch()
    let second = try firstFetch.fetch()

    try check(first == second, "coalesced API first fetch should return the first result")
    try check(transport.requests.count == 1, "a coalesced second fetch should send no request")
    try check(
        transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/v1/portfolio/holdings" },
        "API first fetch should read holdings only, over GET"
    )
    try check(
        first.snapshotCommit.written && FileManager.default.fileExists(atPath: first.snapshotCommit.path),
        "API first fetch should write a snapshot file before publishing"
    )
    try check(
        first.descriptor.sections.map(\.id).contains("pulse"),
        "API first fetch should publish a pulse descriptor from normalized data"
    )
}

private func checkAPIBackgroundDetailRefresh() throws {
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-api-detail-refresh-check")
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    let emptyPage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1}}"#
    let prices = #"{"data":{"prices":[[{"date":"2026-03-27","closeAdjusted":"19.00","closeCurrency":"EUR","symbolQuoteId":1},{"date":"2026-03-28","closeAdjusted":"20.00","closeCurrency":"EUR","symbolQuoteId":1}]]}}"#
    func replies(prices priceReply: ScriptedPDTHTTPTransport.Reply) -> ScriptedPDTHTTPTransport {
        ScriptedPDTHTTPTransport([
            "GET /v1/portfolio/holdings": checkHoldingsReply(),
            "GET /v1/portfolio/distributions": checkReply(#"{"data":{"sectors":[{"categoryName":"Technology","totalValue":{"value":"100.00","currency":"EUR"},"percentage":100}],"assetTypes":[]}}"#),
            "GET /v1/x-ray": checkReply(#"{"data":{"items":[{"weight":25.0}],"hasMore":false}}"#),
            "GET /v1/calendar-events": checkReply(emptyPage),
            "GET /v1/dividends": checkReply(emptyPage),
            "GET /v1/prices/batch": priceReply,
        ])
    }
    func refresh(_ transport: ScriptedPDTHTTPTransport) throws -> PDTBackgroundDetailRefreshResult {
        try PDTAPIBackgroundDetailRefresh(
            client: checkAPIClient(transport),
            snapshotStore: store,
            asOf: "2026-03-28"
        ).refresh()
    }

    let degraded = try refresh(replies(prices: .response(
        status: 503,
        body: Data(#"{"error":{"code":"SERVICE_UNAVAILABLE","message":"m","details":{},"traceId":"t"}}"#.utf8)
    )))
    let degradedSnapshot = try require(try store.loadPriorSnapshot(), "a degraded API refresh should commit its snapshot")
    try check(degraded.outcome == .degraded, "a failed optional price request should degrade, not abort")
    try check(
        degraded.model.facetSnapshots.freshness.status == .partial
            && degraded.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == nil,
        "a degraded API refresh should feed partial freshness state"
    )
    try check(
        degradedSnapshot.sectors.count == 1 && degradedSnapshot.xRayHoldings?.count == 1 && degradedSnapshot.priceSeries.isEmpty,
        "a degraded API refresh should keep the allocation and x-ray phases it completed"
    )
    try check(
        store.lastSyncFailure()?.phase == .priceHistory && store.lastSyncFailure()?.endpoint == .pricesBatch,
        "a degraded API refresh should store the failed price request as its sync failure"
    )

    let repaired = try refresh(replies(prices: checkReply(prices)))
    try check(repaired.outcome == .completed, "a retry after a degraded API refresh should complete")
    try check(
        repaired.model.facetSnapshots.bigMovers.priceSeriesCount == 2
            && repaired.model.facetSnapshots.freshness.status == .fresh
            && repaired.model.facetSnapshots.freshness.latestCompleteDetailFillAsOf == "2026-03-28"
            && store.lastSyncFailure() == nil,
        "a completed API retry should restore prices, record the complete detail fill, and clear the sync failure"
    )
}

private func checkHoldingsReply() -> ScriptedPDTHTTPTransport.Reply {
    checkReply(#"{"data":[{"symbolName":"Check Holding","symbolQuoteId":1,"symbolId":1001,"currentPriceDate":"2026-03-28T23:59:59+00:00","portfolioWeight":"1","closedAt":null,"currentWorthLocal":{"value":"100.00","currency":"EUR"}}]}"#)
}

private func checkReply(_ body: String) -> ScriptedPDTHTTPTransport.Reply {
    .response(status: 200, body: Data(body.utf8))
}

private func checkAPIClient(_ transport: ScriptedPDTHTTPTransport) -> PDTAPIClient {
    PDTAPIClient(
        transport: transport,
        tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken("pdt_check_token")),
        policy: PDTAPIRequestPolicy(maxAttempts: 1)
    )
}

private func checkPDTAPIDataHealth() throws {
    let token = "pdt_SENTINEL_TOKEN_0123456789abcdef0123456789abcdef"
    let planted = [token, "acct-SENTINEL-4242", "https://api.portfoliodividendtracker.com/v1/accounts/acct-SENTINEL-4242", "RAW_BODY_SENTINEL"]
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-api-data-health-check")
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    func refresh(_ script: KeyValuePairs<ScriptedPDTHTTPTransport.Request, ScriptedPDTHTTPTransport.Reply>, asOf: String) -> PDTAPIBackgroundDetailRefresh {
        PDTAPIBackgroundDetailRefresh(
            client: PDTAPIClient(
                transport: ScriptedPDTHTTPTransport(script),
                tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(token)),
                policy: PDTAPIRequestPolicy(maxAttempts: 1)
            ),
            snapshotStore: store,
            asOf: asOf
        )
    }
    let emptyPage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1}}"#
    _ = try refresh([
        "GET /v1/portfolio/holdings": checkReply(#"{"data":[{"symbolName":"Check Holding","symbolQuoteId":1,"symbolId":1001,"currentPriceDate":"2026-03-27T23:59:59+00:00","portfolioWeight":"1","closedAt":null,"currentWorthLocal":{"value":"100.00","currency":"EUR"}}]}"#),
        "GET /v1/portfolio/distributions": checkReply(#"{"data":{"sectors":[],"assetTypes":[]}}"#),
        "GET /v1/x-ray": checkReply(#"{"data":{"items":[],"hasMore":false}}"#),
        "GET /v1/calendar-events": checkReply(emptyPage),
        "GET /v1/dividends": checkReply(emptyPage),
        "GET /v1/prices/batch": checkReply(#"{"data":{"prices":[[{"date":"2026-03-27","closeAdjusted":"10.00","closeCurrency":"EUR","symbolQuoteId":1}]]}}"#),
    ], asOf: "2026-03-28").refresh()

    let savedCopy = try require(
        try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-03-28"),
        "a complete PDT API sync should leave a saved copy"
    )
    let savedHealth = savedCopy.model.facetSnapshots.dataHealth
    try check(
        savedHealth.freshness.status == .fresh && savedHealth.source.pulse == .cachedSnapshot && savedHealth.access.state == .unverified,
        "a saved copy should report its own current prices but no checked connection"
    )
    try check(
        [DataHealthAccess.unverified, .checking, .connected].allSatisfy {
            DataHealth.snapshot(savedHealth, in: DataHealthRuntime(access: $0)).status != .healthy
        },
        "a saved copy should never be healthy, even with current prices and a connected app"
    )

    let rateLimited = ScriptedPDTHTTPTransport.Reply.response(
        status: 429,
        body: Data(#"{"error":{"code":"RATE_LIMITED","message":"\#(planted[3]) \#(planted[1]) \#(token)","details":{"reason":"\#(planted[1])"},"traceId":"\#(planted[2])"}}"#.utf8),
        headers: ["Retry-After": "120", "X-Request-Id": token, "Authorization": "Bearer \(token)"]
    )
    do {
        _ = try refresh(["GET /v1/portfolio/holdings": rateLimited], asOf: "2026-03-29").refresh()
        throw CheckFailure("a rate-limited base request should fail the PDT API refresh")
    } catch PDTAPIError.rateLimited {}
    let failure = try require(store.lastSyncFailure(), "a failed PDT API refresh should store its typed failure")
    try check(
        failure.kind == .rateLimited(retryAfterSeconds: 120) && failure.endpoint == .holdings && failure.traceID == nil,
        "a rate-limited refresh should store the 429 category, its endpoint, and no untrusted trace id"
    )

    let laterCopy = try require(
        try PressureRunner.cachedPulse(snapshotStore: store, today: "2026-04-10"),
        "a failed PDT API refresh should keep the saved copy"
    )
    let runtime = DataHealthRuntime(access: .connected, sync: .failed(failure))
    let health = DataHealth.snapshot(laterCopy.model.facetSnapshots.dataHealth, in: runtime)
    try check(
        health.cache.lastSyncAsOf == "2026-03-28"
            && health.freshness.oldestPriceAsOf?.hasPrefix("2026-03-27") == true
            && health.freshness.status == .stale
            && health.status == .degraded,
        "last sync should stay the committed snapshot's day, separate from price freshness, after a failed refresh"
    )
    let healthRow = try require(
        laterCopy.descriptor(in: runtime).sections.first { $0.id == "freshness" }?.rows.first { $0.id == "dataHealth" },
        "a failed PDT API refresh should show Data health"
    )
    let details = Dictionary(uniqueKeysWithValues: healthRow.children.map { ($0.id, $0.detail ?? "") })
    try check(
        details["dataHealth.source"]?.contains("saved copy") == true
            && details["dataHealth.access"] == "Connected"
            && details["dataHealth.cache"] == "Last sync 2026-03-28"
            && details["dataHealth.freshness"]?.hasPrefix("1 stale") == true
            && details["dataHealth.detailFill"] == "Failed"
            && details["dataHealth.diagnostic"] == "Base holdings: PDT rate limit; try again in 2 min",
        "Data health should name source, access, last sync, price freshness, detail fill, and what to do, each in its own row"
    )
    let copyText = try require(
        healthRow.children.first { $0.id == "dataHealth.diagnostic" }?.children.first?.actionTarget?.copyText,
        "a recorded sync failure should offer Copy diagnostics"
    )
    try check(
        copyText.contains("request: GET /v1/portfolio/holdings")
            && copyText.contains("failure: rate limited (HTTP 429)")
            && copyText.contains("retry after: 120 s")
            && !copyText.contains("tool:")
            && !copyText.contains("argument_keys"),
        "copied diagnostics should describe the PDT API request, not a Claude tool call"
    )
    let written = [
        copyText,
        visibleMenuText([healthRow]).joined(separator: "\n"),
        String(decoding: try stableJSONData(health), as: UTF8.self),
        try String(contentsOf: store.directory.appending(path: "latest-sync-failure.json"), encoding: .utf8),
    ]
    try check(
        written.allSatisfy { text in planted.allSatisfy { !text.contains($0) } && !text.contains("SENTINEL") },
        "copied diagnostics, Data health rows, Data health JSON, and the stored failure should hold nothing PDT's answer carried"
    )
}

private func checkProductSpawnsNothing() throws {
    let pattern = #"Process\(|NSTask|posix_spawn|execv|claude|mcporter|\bmcp\b"#
    var hits: [String] = []
    for target in ["Sources/PDTBarCore", "Sources/PDTBarAppSupport", "Sources/PDTBarApp"] {
        let directory = packageRoot.appending(path: target)
        for file in try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted() where file.hasSuffix(".swift") {
            let lines = try String(contentsOf: directory.appending(path: file), encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                hits.append("\(target)/\(file):\(index + 1)")
            }
        }
    }
    try check(hits.isEmpty, "product code should start no process and name no CLI or MCP tool: \(hits.joined(separator: ", "))")
}

/// Formal models and their verify skills name code by symbol, never by line
/// number. Line anchors drifted with every edit and took resync commits
/// (#266, #282, #289, #290, #309); a name the code no longer has fails here.
private func checkFormalCodeAnchors() throws {
    let fileManager = FileManager.default
    let formal = packageRoot.appending(path: "formal")
    var documents: [String] = []
    for model in try fileManager.contentsOfDirectory(atPath: formal.path).sorted() {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: formal.appending(path: model).path, isDirectory: &isDirectory), isDirectory.boolValue else {
            continue
        }
        documents += try fileManager.contentsOfDirectory(atPath: formal.appending(path: model).path)
            .filter { $0.hasSuffix(".tla") }
            .sorted()
            .map { "formal/\(model)/\($0)" }
        let skill = ".claude/skills/verify-\(model)/SKILL.md"
        try check(fileManager.fileExists(atPath: packageRoot.appending(path: skill).path), "formal/\(model) needs its verify skill at \(skill)")
        documents.append(skill)
    }

    let word = try Regex(#"[A-Za-z_][A-Za-z0-9_]*"#)
    let tlaComment = try Regex(#"\(\*[\s\S]*?\*\)|\\\*[^\n]*"#)
    var names = Set<String>()
    var fileNames = Set<String>()
    for root in ["Sources", "Tests", "formal", "Scripts"] {
        let directory = packageRoot.appending(path: root)
        for path in try fileManager.subpathsOfDirectory(atPath: directory.path) {
            let file = URL(fileURLWithPath: path)
            fileNames.insert(file.lastPathComponent)
            fileNames.insert(file.deletingPathExtension().lastPathComponent)
            guard ["swift", "tla", "cfg", "sh"].contains(file.pathExtension) else {
                continue
            }
            var text = try String(contentsOf: directory.appending(path: path), encoding: .utf8)
            if ["tla", "cfg"].contains(file.pathExtension) {
                text = text.replacing(tlaComment, with: " ")
            }
            names.formUnion(text.matches(of: word).map { String(text[$0.range]) })
        }
    }

    let lineAnchor = try Regex(#"\.(swift|tla):[0-9]|\b(Core|App):[0-9]|`[^`\n]+` [0-9]{2,4}\b"#)
    let codeSpan = try Regex(#"`([^`\n]+)`"#)
    let qualifiedName = try Regex(#"\b[A-Z][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+"#)
    let identifier = try Regex(#"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\(.*\))?$"#)
    let sha = try Regex(#"^[0-9a-f]{7,40}$"#)
    let fileExtensions: Set<String> = ["swift", "tla", "cfg", "sh"]
    let otherExtensions: Set<String> = ["jar", "json", "md", "png", "svg", "txt", "yml"]
    var problems: [String] = []
    for document in documents {
        let lines = try String(contentsOf: packageRoot.appending(path: document), encoding: .utf8).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let location = "\(document):\(index + 1)"
            if line.contains(lineAnchor) {
                problems.append("\(location) cites a line number; name the symbol instead")
            }
            let tokens = document.hasSuffix(".tla")
                ? line.matches(of: qualifiedName).map { String(line[$0.range]) }
                : line.matches(of: codeSpan).map { String(line[$0.range].dropFirst().dropLast()) }
            for token in tokens {
                let lastPart = token.split(separator: ".").last.map(String.init) ?? token
                if token.contains(" ") || otherExtensions.contains(lastPart) {
                    continue
                }
                if fileExtensions.contains(lastPart) || token.contains("/") {
                    if !fileExtensions.contains(lastPart) {
                        continue
                    }
                    let name = URL(fileURLWithPath: token).lastPathComponent
                    if !fileNames.contains(name) && !fileManager.fileExists(atPath: packageRoot.appending(path: token).path) {
                        problems.append("\(location) names file `\(token)`, which does not exist")
                    }
                    continue
                }
                guard token.wholeMatch(of: identifier) != nil, token.wholeMatch(of: sha) == nil else {
                    continue
                }
                let parts = token.split(separator: "(", maxSplits: 1)[0].split(separator: ".").map(String.init)
                let missing = parts.filter { !names.contains($0) && !fileNames.contains($0) }
                if !missing.isEmpty {
                    problems.append("\(location) names `\(token)`, but no Swift, test, model, or script code has \(missing.joined(separator: ", "))")
                }
            }
        }
    }
    try check(
        problems.isEmpty,
        """
        formal code anchors must name live symbols, never line numbers. Write a removed name as plain text, \
        not a code span. See AGENTS.md "Rules and what enforces them".
        \(problems.joined(separator: "\n"))
        """
    )
}

/// `allSatisfy` is true for an empty collection, so an `#expect` over it kept
/// passing after the rows it checked were gone (#307). Tests use
/// `nonEmptyAllSatisfy` from Tests/PDTBarTests/ExpectationSupport.swift.
private func checkNoEmptySafeExpectations() throws {
    let tests = packageRoot.appending(path: "Tests")
    var hits: [String] = []
    for file in try FileManager.default.subpathsOfDirectory(atPath: tests.path).sorted() where file.hasSuffix(".swift") {
        let lines = try String(contentsOf: tests.appending(path: file), encoding: .utf8).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("#expect(") && line.contains(".allSatisfy") {
            hits.append("Tests/\(file):\(index + 1)")
        }
    }
    try check(
        hits.isEmpty,
        "#expect over allSatisfy passes on an empty collection; use nonEmptyAllSatisfy (Tests/PDTBarTests/ExpectationSupport.swift) or pin the exact elements: \(hits.joined(separator: ", "))"
    )
}

private func checkConcurrencyEscapeHatches() throws {
    let unchecked = "@unchecked" + " Sendable"
    let banned = ["nonisolated" + "(unsafe)", "withLock" + "Unchecked", "unchecked" + "State:"]
    let fix = "hold mutable state in `OSAllocatedUnfairLock<State>` (`init(initialState:)` + `withLock`, compiler-checked) or an actor; see #310"
    let baselinePath = "docs/unchecked-sendable-baseline.txt"

    var counts: [String: Int] = [:]
    var problems: [String] = []
    for root in ["Sources", "Tests"] {
        let directory = packageRoot.appending(path: root)
        for file in try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted() where file.hasSuffix(".swift") {
            let path = "\(root)/\(file)"
            let lines = try String(contentsOf: directory.appending(path: file), encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//")[0]
                for pattern in banned where code.contains(pattern) {
                    problems.append("\(path):\(index + 1) uses `\(pattern)`, which hides shared mutable state from the concurrency checker: \(fix)")
                }
                counts[path, default: 0] += code.components(separatedBy: unchecked).count - 1
            }
        }
    }

    let baseline = try readCountBaseline(baselinePath)
    for path in Set(counts.keys).union(baseline.keys).sorted() {
        let count = counts[path] ?? 0
        let allowed = baseline[path] ?? 0
        if count > allowed {
            problems.append("`\(unchecked)` in \(path) (\(count) > baseline \(allowed)): \(fix)")
        } else if count < allowed {
            let edit = count == 0 ? "remove \(path) from" : "lower \(path) to \(count) in"
            problems.append("baseline stale: \(edit) \(baselinePath) so the ratchet keeps the lower count")
        }
    }
    try check(problems.isEmpty, problems.joined(separator: "\n"))
}

private func checkFeatureGuidesQuoteMenuCopy(_ fixtures: [URL]) throws {
    let guides = ["docs/public/features.en.md", "docs/public/features.nl.md"]
    let guideTexts = try guides.map { try String(contentsOf: packageRoot.appending(path: $0), encoding: .utf8) }
    let allowlistPath = "docs/features-menu-copy-allowlist.txt"
    var allowlist = Set<String>()
    for line in try String(contentsOf: packageRoot.appending(path: allowlistPath), encoding: .utf8).components(separatedBy: "\n")
    where !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
        let parts = line.components(separatedBy: " | ")
        try check(
            parts.count == 2 && !parts[1].trimmingCharacters(in: .whitespaces).isEmpty,
            "\(allowlistPath) entries are `menu copy | reason`: \(line)"
        )
        allowlist.insert(parts[0])
    }

    var menuCopy = Set<String>()
    for fixture in fixtures {
        let names = try namesFromPDT(in: fixture)
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixture)
        var unpriced = snapshot
        unpriced.openHoldings.indices.first.map { unpriced.openHoldings[$0].price = nil }
        for snapshot in [snapshot, unpriced] {
            let model = PressureEngine.buildModel(from: snapshot)
            for showPortfolioValues in [true, false] {
                let settings = PortfolioValueDisplaySettings(showPortfolioValues: showPortfolioValues)
                let descriptor = MenuDescriptorRenderer.render(model: model, settings: settings)
                menuCopy.formUnion(drawnMenuText(descriptor).filter { isFixedCopy($0, names: names) })
            }
        }
    }

    var problems: [String] = []
    for copy in menuCopy.subtracting(allowlist).sorted() {
        for (guide, text) in zip(guides, guideTexts) where !text.contains("`\(copy)`") {
            problems.append(
                "menu copy `\(copy)` is not in \(guide); describe it there and in the other feature guide, or add it to \(allowlistPath) with a reason"
            )
        }
    }
    for copy in allowlist.sorted() {
        if !menuCopy.contains(copy) {
            problems.append("\(allowlistPath) lists `\(copy)`, which the menu no longer draws; remove the entry")
        } else if guideTexts.allSatisfy({ $0.contains("`\(copy)`") }) {
            problems.append("\(allowlistPath) lists `\(copy)`, which both feature guides now quote; remove the entry")
        }
    }
    try check(problems.isEmpty, problems.joined(separator: "\n"))
}

private func drawnMenuText(_ descriptor: MenuDescriptor) -> [String] {
    func walk(_ rows: [MenuRow]) -> [String] {
        rows.flatMap { row in
            let own = row.portfolioSummary.map { [$0.totalValue] + $0.performanceMetrics.map(\.label) }
                ?? [row.title, row.detail].compactMap { $0 }
            return own + walk(row.children)
        }
    }
    return descriptor.sections.map(\.title) + walk(descriptor.sections.flatMap(\.rows))
}

private func namesFromPDT(in fixture: URL) throws -> [String] {
    let nameKeys: Set<String> = ["symbolName", "categoryName", "exchangeName", "code", "isin"]
    var names: [String] = []
    func collect(_ value: Any, key: String?) {
        if let text = value as? String, let key, nameKeys.contains(key) {
            names.append(normalizedWords(text))
        } else if let object = value as? [String: Any] {
            object.forEach { collect($1, key: $0) }
        } else if let array = value as? [Any] {
            array.forEach { collect($0, key: key) }
        }
    }
    collect(try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)), key: nil)
    return names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

private func isFixedCopy(_ text: String, names: [String]) -> Bool {
    let words = normalizedWords(text)
    return text.contains(where: \.isLetter)
        && !text.contains(where: \.isNumber)
        && !names.contains { words.contains($0) }
}

private func normalizedWords(_ text: String) -> String {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
    return " \(words.joined(separator: " ")) "
}

private func assertInformationalCopy(
    model: PortfolioPulseModel,
    descriptor: MenuDescriptor,
    fixtureName: String
) throws {
    for value in renderedCopy(from: model, descriptor: descriptor) where containsAdviceLikeLanguage(value) {
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
        [$0.title, $0.detail.rendered(settings: PortfolioValueDisplaySettings())]
    })
    copy.append(contentsOf: model.supportingDataSlots.map(\.label))
    copy.append(contentsOf: descriptor.sections.map(\.title))
    copy.append(contentsOf: descriptor.sections.flatMap { visibleMenuText($0.rows) })
    return copy.compactMap { $0 }.filter { !$0.isEmpty }
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

private func checkCommentCounts() throws {
    let baselinePath = "docs/comment-baseline.txt"
    let baseline = try readCountBaseline(baselinePath)
    var counts: [String: Int] = [:]
    for path in try repoFiles(under: ["Sources", "Tests", "Scripts", ".github/workflows"]) {
        let marker: String
        switch URL(fileURLWithPath: path).pathExtension {
        case "swift", "mjs", "js": marker = "//"
        case "sh", "py", "yml": marker = "#"
        default: continue
        }
        var inBlock = false
        counts[path] = try readRepoText(path).components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let startsBlock = marker == "//" && trimmed.hasPrefix("/*")
            let counted = inBlock || startsBlock || (trimmed.hasPrefix(marker) && !trimmed.hasPrefix("#!"))
            if inBlock || startsBlock {
                inBlock = !trimmed.contains("*/")
            }
            return counted
        }.count
    }
    var grew: [String] = []
    var dropped: [String] = []
    for path in Set(counts.keys).union(baseline.keys).sorted() {
        let count = counts[path] ?? 0
        let allowed = baseline[path] ?? 0
        if count > allowed {
            grew.append("\(path): \(count) comment lines, baseline \(allowed)")
        } else if count < allowed {
            dropped.append(count == 0 ? "remove \(path)" : "set \(path) to \(count)")
        }
    }
    try check(
        grew.isEmpty,
        """
        comment lines grew. Delete the new comments. Keep one only if it states a contract or a fact about code \
        outside this repo, and then raise that file's count in \(baselinePath) in the same change.
        \(grew.joined(separator: "\n"))
        """
    )
    try check(dropped.isEmpty, "comments were deleted; lower \(baselinePath) to match: \(dropped.joined(separator: ", "))")
}

private func checkVerifySkillNamesEveryCommand() throws {
    let skillRoot = ".cursor/skills/verify-pdtbar"
    let skillText = try repoFiles(under: [skillRoot]).filter { $0.hasSuffix(".md") }.map(readRepoText).joined(separator: "\n")
    let smokeSource = "Sources/PDTBarSmoke/main.swift"
    let verifyScript = "Scripts/verify_pdtbar.sh"
    let smokeText = try readRepoText(smokeSource)
    let verifyText = try readRepoText(verifyScript)
    let verifyDispatch = verifyText.components(separatedBy: "case \"${1:-}\" in").last ?? ""

    func captures(_ pattern: String, in text: String) throws -> [String] {
        try text.matches(of: Regex(pattern)).compactMap { $0.output[1].substring.map(String.init) }
    }
    let smokes = try captures(#"SmokeCommand\(\s*name:\s*"([a-z0-9-]+)""#, in: smokeText)
    let smokeFlags = try captures(#"case "(--[a-z-]+)""#, in: smokeText)
    let verifyCommands = try captures(#"(?m)^  ([a-z][a-z-]*)\)"#, in: verifyDispatch)
    let verifyFlags = try captures(#""(--[a-z-]+)""#, in: verifyText)

    var problems: [String] = []
    let documented = (smokes + smokeFlags).map { ($0, smokeSource) } + verifyCommands.map { ($0, verifyScript) }
    for (name, source) in documented where !skillText.contains(try Regex("(?m)(?:^|[^A-Za-z0-9-])\(name)(?![A-Za-z0-9-])")) {
        problems.append("`\(name)` from \(source) is not in \(skillRoot); say when to run it and whether it can prompt")
    }
    let fenced = try captures(#"(?s)```[a-z]*\n(.*?)```"#, in: skillText)
    let inline = try captures(#"`([^`\n]+)`"#, in: skillText)
    let codeText = (fenced + inline).joined(separator: "\n")
    let invocation = try Regex(#"(pdtbar-smoke|verify_pdtbar\.sh) ([a-z][a-z0-9-]*)([^\n|;&`]*)"#)
    let flag = try Regex(#"--[a-z][a-z-]*"#)
    var wrong = Set<String>()
    for match in codeText.matches(of: invocation) {
        let isSmoke = match.output[1].substring == "pdtbar-smoke"
        let (tool, names, flags) = isSmoke ? (smokeSource, smokes, smokeFlags) : (verifyScript, verifyCommands, verifyFlags)
        let name = String(match.output[2].substring ?? "")
        if !names.contains(name) {
            wrong.insert("\(skillRoot) runs `\(match.output[1].substring ?? "") \(name)`, which \(tool) does not have")
        }
        let tail = match.output[3].substring ?? ""
        for used in tail.matches(of: flag).map({ String(tail[$0.range]) }) where !flags.contains(used) {
            wrong.insert("\(skillRoot) passes `\(used)` to `\(name)`, which \(tool) does not parse")
        }
    }
    problems += wrong.sorted()
    try check(problems.isEmpty, problems.joined(separator: "\n"))
}

private func checkCIRunsWhenCheckInputsChange() throws {
    let workflowPath = ".github/workflows/ci.yml"
    var filters: [[String]] = []
    var current: [String]?
    for line in try readRepoText(workflowPath).components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "paths:" {
            current.map { filters.append($0) }
            current = []
        } else if current != nil, trimmed.hasPrefix("- ") {
            let item = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let quote = item.first, quote == "\"" || quote == "'" {
                current?.append(String(item.dropFirst().prefix { $0 != quote }))
            } else {
                current?.append(item.components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces))
            }
        } else if let list = current, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
            filters.append(list)
            current = nil
        }
    }
    try check(filters.count == 2, "\(workflowPath): expected `paths` filters under push and pull_request, found \(filters.count)")
    let globs = try filters.map { list in
        try list.map { pattern in
            let negated = pattern.hasPrefix("!")
            return (negated: negated, regex: try globRegex(negated ? String(pattern.dropFirst()) : pattern))
        }
    }
    func ciRuns(on path: String) -> Bool {
        globs.allSatisfy { list in
            list.reduce(false) { included, glob in path.wholeMatch(of: glob.regex) != nil ? !glob.negated : included }
        }
    }

    let interpolation = try Regex(#"\\\([^)]*\)|\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*"#)
    let repoPath = try Regex(#"(?:^|[^A-Za-z0-9_.-])((?:docs|\.claude|\.cursor)/[A-Za-z0-9_./*-]+)"#)
    var problems = Set<String>()
    for file in try repoFiles(under: ["Sources", "Tests", "Scripts"]) where ["swift", "sh", "py"].contains(URL(fileURLWithPath: file).pathExtension) {
        for (index, line) in try readRepoText(file).components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
                continue
            }
            let code = line.replacing(interpolation, with: "*")
            for match in code.matches(of: repoPath) {
                guard var named = match.output[1].substring.map(String.init) else {
                    continue
                }
                while named.hasSuffix(".") || named.hasSuffix("/") {
                    named.removeLast()
                }
                for path in try repoFiles(named: named) where !ciRuns(on: path) {
                    problems.insert("\(path) (named in \(file):\(index + 1))")
                }
            }
        }
    }
    try check(
        problems.isEmpty,
        """
        CI never runs when only these gate inputs change; add a pattern for each to both `paths` lists in \(workflowPath):
        \(problems.sorted().joined(separator: "\n"))
        """
    )
}

/// GitHub Actions path glob: `*` stops at `/`, `**` does not.
private func globRegex(_ glob: String) throws -> Regex<AnyRegexOutput> {
    try check(
        !glob.contains(where: "?+[]".contains),
        "ci.yml path `\(glob)` uses `?`, `+`, or `[...]`, which checkCIRunsWhenCheckInputsChange does not model; write it with `*` and `**`"
    )
    var pattern = ""
    var rest = Substring(glob)
    while let character = rest.first {
        if rest.hasPrefix("**/") {
            pattern += "(?:.*/)?"
            rest = rest.dropFirst(3)
            continue
        }
        if rest.hasPrefix("**") {
            pattern += ".*"
            rest = rest.dropFirst(2)
            continue
        }
        pattern += character == "*" ? "[^/]*" : NSRegularExpression.escapedPattern(for: String(character))
        rest = rest.dropFirst()
    }
    return try Regex(pattern)
}

private func readCountBaseline(_ path: String) throws -> [String: Int] {
    var baseline: [String: Int] = [:]
    for line in try readRepoText(path).components(separatedBy: "\n") where !line.hasPrefix("#") && !line.isEmpty {
        let fields = line.split(separator: " ", maxSplits: 1).map(String.init)
        let count = try require(fields.count == 2 ? Int(fields[0]) : nil, "\(path): expected `<count> <path>`, got `\(line)`")
        baseline[fields[1]] = count
    }
    return baseline
}

private func readRepoText(_ path: String) throws -> String {
    try String(contentsOf: packageRoot.appending(path: path), encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
}

private func repoFiles(named path: String) throws -> [String] {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: packageRoot.appending(path: path).path, isDirectory: &isDirectory) {
        return isDirectory.boolValue ? try repoFiles(under: [path]) : [path]
    }
    guard let star = path.firstIndex(of: "*"), let slash = path[..<star].lastIndex(of: "/") else {
        return [path]
    }
    let root = String(path[..<slash])
    guard FileManager.default.fileExists(atPath: packageRoot.appending(path: root).path) else {
        return [path]
    }
    let pattern = try globRegex(path)
    let matches = try repoFiles(under: [root]).filter { $0.wholeMatch(of: pattern) != nil }
    return matches.isEmpty ? [path] : matches
}

private func repoFiles(under roots: [String]) throws -> [String] {
    try roots.flatMap { root in
        try FileManager.default.subpathsOfDirectory(atPath: packageRoot.appending(path: root).path).sorted().compactMap { subpath in
            var isDirectory: ObjCBool = false
            let path = "\(root)/\(subpath)"
            FileManager.default.fileExists(atPath: packageRoot.appending(path: path).path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? nil : path
        }
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

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
