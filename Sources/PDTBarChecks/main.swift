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
            "REST fixture provenance for \(scenario) should list its replies in replay order: \(files)"
        )
        try check(
            replies.allSatisfy { $0.request.hasPrefix("GET /v1/") },
            "REST fixture provenance for \(scenario) should name a GET request for every reply"
        )
    }
}

private func checkCoalescedAPIFirstFetch() throws {
    let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-api-first-fetch-check")
    defer {
        try? FileManager.default.removeItem(at: store.directory)
    }
    let transport = ScriptedPDTHTTPTransport([checkHoldingsReply()])
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
    func replies(prices priceReply: ScriptedPDTHTTPTransport.Reply) -> [ScriptedPDTHTTPTransport.Reply] {
        [
            checkHoldingsReply(),
            checkReply(#"{"data":{"sectors":[{"categoryName":"Technology","totalValue":{"value":"100.00","currency":"EUR"},"percentage":100}],"assetTypes":[]}}"#),
            checkReply(#"{"data":{"items":[{"weight":25.0}],"hasMore":false}}"#),
            checkReply(emptyPage),
            checkReply(emptyPage),
            priceReply,
        ]
    }
    func refresh(_ replies: [ScriptedPDTHTTPTransport.Reply]) throws -> PDTBackgroundDetailRefreshResult {
        try PDTAPIBackgroundDetailRefresh(
            client: checkAPIClient(ScriptedPDTHTTPTransport(replies)),
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
    func refresh(_ replies: [ScriptedPDTHTTPTransport.Reply], asOf: String) -> PDTAPIBackgroundDetailRefresh {
        PDTAPIBackgroundDetailRefresh(
            client: PDTAPIClient(
                transport: ScriptedPDTHTTPTransport(replies),
                tokenProvider: InMemoryPDTAPITokenProvider(token: PDTAPIToken(token)),
                policy: PDTAPIRequestPolicy(maxAttempts: 1)
            ),
            snapshotStore: store,
            asOf: asOf
        )
    }
    let emptyPage = #"{"data":[],"meta":{"currentPage":1,"lastPage":1}}"#
    let completeSync = [
        #"{"data":[{"symbolName":"Check Holding","symbolQuoteId":1,"symbolId":1001,"currentPriceDate":"2026-03-27T23:59:59+00:00","portfolioWeight":"1","closedAt":null,"currentWorthLocal":{"value":"100.00","currency":"EUR"}}]}"#,
        #"{"data":{"sectors":[],"assetTypes":[]}}"#,
        #"{"data":{"items":[],"hasMore":false}}"#,
        emptyPage,
        emptyPage,
        #"{"data":{"prices":[[{"date":"2026-03-27","closeAdjusted":"10.00","closeCurrency":"EUR","symbolQuoteId":1}]]}}"#,
    ].map { ScriptedPDTHTTPTransport.Reply.response(status: 200, body: Data($0.utf8)) }
    _ = try refresh(completeSync, asOf: "2026-03-28").refresh()

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
        _ = try refresh([rateLimited], asOf: "2026-03-29").refresh()
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
        [$0.title, $0.detail]
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
