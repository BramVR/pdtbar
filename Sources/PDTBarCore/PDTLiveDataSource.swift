import Foundation

public protocol PDTLiveToolClient {
    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data
}

public enum PDTReadTools {
    public static let requiredV1 = [
        "pdt-get-portfolio-holdings",
        "pdt-get-portfolio-distributions",
        "pdt-list-x-ray-holdings",
        "pdt-list-calendar-events",
        "pdt-list-dividends",
        "pdt-list-symbol-prices",
        "pdt-get-symbol-quote",
    ]
    public static let performance = [
        "pdt-get-portfolio-performance",
        "pdt-get-portfolio-gains",
    ]
    public static let allowedV1 = requiredV1 + ["pdt-get-symbol"] + performance

    public static func missingRequiredV1Tools(in availableTools: Set<String>) -> [String] {
        requiredV1.filter { !availableTools.contains($0) }
    }
}

/// Single source of truth for the Claude CLI `--disallowedTools` denylist used
/// during read-only PDT syncs. Both the production connection
/// (`ClaudeLocalConnection`) and the `manual-claude-pdt` smoke must consume
/// this policy so the smoke keeps exercising the exact read-only policy the
/// app ships with. Production additionally denies non-requested PDT read
/// tools per call on top of this base list.
public enum ClaudePDTReadOnlyToolPolicy {
    /// Built-in Claude CLI tools denied during read-only PDT sync calls.
    /// ToolSearch is intentionally absent: it stays allowed so Claude can
    /// hydrate deferred remote MCP tools.
    public static let disallowedBuiltInTools = [
        "AskUserQuestion",
        "Bash",
        "CronCreate",
        "CronDelete",
        "CronList",
        "DesignSync",
        "Edit",
        "EnterPlanMode",
        "EnterWorktree",
        "ExitPlanMode",
        "ExitWorktree",
        "ListMcpResourcesTool",
        "Monitor",
        "NotebookEdit",
        "PushNotification",
        "Read",
        "ReadMcpResourceTool",
        "RemoteTrigger",
        "ScheduleWakeup",
        "Skill",
        "Task",
        "TaskCreate",
        "TaskGet",
        "TaskList",
        "TaskOutput",
        "TaskStop",
        "TaskUpdate",
        "WebFetch",
        "WebSearch",
        "Workflow",
        "Write",
    ]

    /// Wildcard selectors denying every known PDT mutating tool name shape.
    public static let disallowedPDTMutationSelectors = [
        "mcp__*__pdt-add-*",
        "mcp__*__pdt-create-*",
        "mcp__*__pdt-delete-*",
        "mcp__*__pdt-patch-*",
        "mcp__*__pdt-post-*",
        "mcp__*__pdt-put-*",
        "mcp__*__pdt-remove-*",
        "mcp__*__pdt-set-*",
        "mcp__*__pdt-update-*",
    ]

    /// The full shared denylist: denied built-ins plus PDT mutator selectors.
    public static let disallowedTools = disallowedBuiltInTools + disallowedPDTMutationSelectors
}

public protocol PDTMCPConnector {
    func availableReadTools() throws -> Set<String>
    func availableReadTools(required: Set<String>) throws -> Set<String>
    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data
    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?
    ) throws -> PDTMCPConnectorCallResult
    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?,
        cancellation: PDTCancellation?
    ) throws -> PDTMCPConnectorCallResult
}

public protocol PDTMCPConnectorProgressReporting {
    func availableReadTools(
        required: Set<String>,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String>
    func availableReadTools(
        required: Set<String>,
        cancellation: PDTCancellation?,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String>
}

public extension PDTMCPConnectorProgressReporting {
    func availableReadTools(
        required: Set<String>,
        cancellation: PDTCancellation? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Set<String> {
        guard cancellation?.isCancelled != true else {
            throw PDTMCPConnectorError.timeout("PDT tool discovery cancelled")
        }
        let tools = try availableReadTools(required: required, progress: progress)
        guard cancellation?.isCancelled != true else {
            throw PDTMCPConnectorError.timeout("PDT tool discovery cancelled")
        }
        return tools
    }
}

public extension PDTMCPConnector {
    func availableReadTools(required: Set<String>) throws -> Set<String> {
        try availableReadTools().intersection(required)
    }

    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?
    ) throws -> PDTMCPConnectorCallResult {
        if let retryDeadline, Date() >= retryDeadline {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
            throw PDTMCPConnectorCallFailure(underlyingError: timeout, attemptCount: 0)
        }
        do {
            let data = try callReadTool(name, arguments: arguments)
            if let retryDeadline, Date() >= retryDeadline {
                throw PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
            }
            return PDTMCPConnectorCallResult(data: data, attemptCount: 1)
        } catch {
            let deadlineExpired = retryDeadline.map { Date() >= $0 } ?? false
            let underlyingError = deadlineExpired && pdtDetailRefreshFailureCategory(for: error).isRetryable
                ? PDTMCPConnectorError.timeout("PDT \(name) call deadline expired")
                : error
            throw PDTMCPConnectorCallFailure(underlyingError: underlyingError, attemptCount: 1)
        }
    }

    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?,
        cancellation: PDTCancellation? = nil
    ) throws -> PDTMCPConnectorCallResult {
        guard cancellation?.isCancelled != true else {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call cancelled")
            throw PDTMCPConnectorCallFailure(underlyingError: timeout, attemptCount: 0)
        }
        let result = try callReadToolReportingAttempts(
            name,
            arguments: arguments,
            retryDeadline: retryDeadline
        )
        guard cancellation?.isCancelled != true else {
            let timeout = PDTMCPConnectorError.timeout("PDT \(name) call cancelled")
            throw PDTMCPConnectorCallFailure(
                underlyingError: timeout,
                attemptCount: result.attemptCount
            )
        }
        return result
    }
}

public struct PDTMCPConnectorCallResult: Sendable {
    public var data: Data
    public var attemptCount: Int

    public init(data: Data, attemptCount: Int) {
        self.data = data
        self.attemptCount = max(0, attemptCount)
    }
}

public struct PDTMCPConnectorCallFailure: Error {
    public var underlyingError: any Error
    public var attemptCount: Int

    public init(underlyingError: any Error, attemptCount: Int) {
        self.underlyingError = underlyingError
        self.attemptCount = max(0, attemptCount)
    }
}

public enum PDTMCPConnectorError: Error, CustomStringConvertible, Equatable {
    case missingRequiredReadTools([String])
    case setupUnavailable(String)
    case transientFailure(String)
    case timeout(String)
    case nonReadTool(String)
    case missingScriptedResponse(String)

    public var description: String {
        switch self {
        case .missingRequiredReadTools(let tools):
            "PDT MCP connector missing required read tools: \(tools.joined(separator: ", "))"
        case .setupUnavailable(let message):
            "PDT MCP connector setup unavailable: \(message)"
        case .transientFailure(let message):
            "PDT MCP connector transient failure: \(message)"
        case .timeout(let message):
            "PDT MCP connector timeout: \(message)"
        case .nonReadTool(let tool):
            "PDT MCP connector refused non-v1 read tool: \(tool)"
        case .missingScriptedResponse(let key):
            "PDT MCP connector missing scripted response for \(key)"
        }
    }
}

public struct PDTMCPConnectorDataSource: PortfolioDataSource {
    public var connector: any PDTMCPConnector
    public var liveOptions: PDTLiveDataSourceOptions
    public var onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)?

    public init(
        connector: any PDTMCPConnector,
        liveOptions: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions(),
        onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)? = nil
    ) {
        self.connector = connector
        self.liveOptions = liveOptions
        self.onOptionalFacetFailure = onOptionalFacetFailure
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        let requiredTools = Set(liveOptions.requiredReadTools)
        let availableTools = try connector.availableReadTools(required: requiredTools)
        let missing = liveOptions.requiredReadTools.filter { !availableTools.contains($0) }
        guard missing.isEmpty else {
            throw PDTMCPConnectorError.missingRequiredReadTools(missing)
        }
        return try PDTLiveDataSource(
            toolClient: PDTMCPConnectorToolClient(connector: connector),
            options: liveOptions,
            onOptionalFacetFailure: onOptionalFacetFailure
        ).snapshot(asOf: asOf)
    }
}

public struct PDTMCPConnectorToolClient: PDTLiveToolClient {
    public var connector: any PDTMCPConnector

    public init(connector: any PDTMCPConnector) {
        self.connector = connector
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        guard PDTReadTools.allowedV1.contains(name) else {
            throw PDTMCPConnectorError.nonReadTool(name)
        }
        return try connector.callReadTool(name, arguments: arguments)
    }
}

public final class ScriptedPDTMCPConnector: PDTMCPConnector {
    public var availableTools: Set<String>
    public var responses: [String: Data]
    public var failure: PDTMCPConnectorError?
    public var initialCallDelaySeconds: Double?
    public private(set) var availabilityChecks = 0
    public private(set) var calls: [String] = []
    private let lock = NSLock()

    public init(
        availableTools: Set<String> = Set(PDTReadTools.requiredV1),
        responses: [String: Data],
        failure: PDTMCPConnectorError? = nil,
        initialCallDelaySeconds: Double? = nil
    ) {
        self.availableTools = availableTools
        self.responses = responses
        self.failure = failure
        self.initialCallDelaySeconds = initialCallDelaySeconds
    }

    public func availableReadTools() throws -> Set<String> {
        lock.lock()
        defer {
            lock.unlock()
        }
        availabilityChecks += 1
        return availableTools
    }

    public func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.lock()
        calls.append(name)
        if let delay = initialCallDelaySeconds, delay > 0 {
            initialCallDelaySeconds = nil
            lock.unlock()
            Thread.sleep(forTimeInterval: delay)
        } else {
            lock.unlock()
        }
        lock.lock()
        defer {
            lock.unlock()
        }
        if let failure {
            throw failure
        }
        let suffix = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let key = suffix.isEmpty ? name : "\(name)?\(suffix)"
        guard let response = responses[key] ?? responses[name] else {
            throw PDTMCPConnectorError.missingScriptedResponse(key)
        }
        return response
    }
}

public enum ScriptedPDTMCPConnectorConfigurationError: Error, Equatable {
    case emptyResponses
}

public struct ScriptedPDTMCPConnectorConfiguration: Codable, Equatable, Sendable {
    public var availableTools: [String]?
    public var responses: [String: String]
    public var asOf: String?
    public var failure: String?
    public var failureMessage: String?
    public var initialCallDelaySeconds: Double?

    public init(
        availableTools: [String]? = nil,
        responses: [String: String],
        asOf: String? = nil,
        failure: String? = nil,
        failureMessage: String? = nil,
        initialCallDelaySeconds: Double? = nil
    ) {
        self.availableTools = availableTools
        self.responses = responses
        self.asOf = asOf
        self.failure = failure
        self.failureMessage = failureMessage
        self.initialCallDelaySeconds = initialCallDelaySeconds
    }

    public func connector() throws -> ScriptedPDTMCPConnector {
        guard !responses.isEmpty else {
            throw ScriptedPDTMCPConnectorConfigurationError.emptyResponses
        }
        return ScriptedPDTMCPConnector(
            availableTools: Set(availableTools ?? PDTReadTools.requiredV1),
            responses: responses.mapValues { Data($0.utf8) },
            failure: scriptedFailure(),
            initialCallDelaySeconds: initialCallDelaySeconds
        )
    }

    private func scriptedFailure() -> PDTMCPConnectorError? {
        guard let failure else {
            return nil
        }
        let message = failureMessage ?? "scripted PDT MCP failure"
        switch failure {
        case "setupUnavailable", "authSetupError":
            return .setupUnavailable(message)
        case "transientFailure":
            return .transientFailure(message)
        default:
            return .transientFailure(message)
        }
    }
}

public final class PDTCoalescedFirstPortfolioFetch {
    private let lock = NSLock()
    private var result: PressureRunResult?
    private let dataSource: any PortfolioDataSource
    private let snapshotStore: SnapshotStore
    private let pulseReadStore: PulseReadStore?
    private let asOf: String?

    public init(
        dataSource: any PortfolioDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil,
        pulseReadStore: PulseReadStore? = nil
    ) {
        self.dataSource = dataSource
        self.snapshotStore = snapshotStore
        self.asOf = asOf
        self.pulseReadStore = pulseReadStore
    }

    public func fetch() throws -> PressureRunResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        if let result {
            return result
        }
        let freshResult = try PressureRunner.run(
            dataSource: dataSource,
            snapshotStore: snapshotStore,
            asOf: asOf,
            pulseReadStore: pulseReadStore
        )
        result = freshResult
        return freshResult
    }
}

public enum PDTLiveDataSourceError: Error, CustomStringConvertible {
    case malformedToolResult(String)
    case unavailableToolResult(String)
    case transientUnavailableToolResult(String)

    public var shouldSkipLiveSmoke: Bool {
        switch self {
        case .unavailableToolResult, .transientUnavailableToolResult:
            true
        case .malformedToolResult:
            false
        }
    }

    public var description: String {
        switch self {
        case .malformedToolResult(let tool):
            "live PDT tool \(tool) did not return the expected read-only JSON shape"
        case .unavailableToolResult(let tool):
            "live PDT tool \(tool) reported missing auth or unavailable local access"
        case .transientUnavailableToolResult(let tool):
            "live PDT tool \(tool) reported a transient unavailable response"
        }
    }
}

public enum PDTLiveUnavailableKind: Equatable, Sendable {
    case authOrSetup
    case transient
}

public enum PDTLiveUnavailableClassifier {
    public static func shouldSkip(_ value: String) -> Bool {
        unavailableKind(in: value) != nil
    }

    public static func unavailableKind(in value: String) -> PDTLiveUnavailableKind? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            return unavailableKind(in: object)
        }
        return unavailableKind(inText: trimmed)
    }

    static func shouldSkipObject(_ object: Any) -> Bool {
        unavailableKind(in: object) != nil
    }

    static func shouldSkipErrorPayload(_ object: Any) -> Bool {
        unavailableKind(in: object, forceErrorContext: true) != nil
    }

    static func unavailableKind(in object: Any, forceErrorContext: Bool = false) -> PDTLiveUnavailableKind? {
        var sawTransient = false
        for text in unavailableTexts(in: object, forceErrorContext: forceErrorContext) {
            switch unavailableKind(inText: text) {
            case .authOrSetup:
                return .authOrSetup
            case .transient:
                sawTransient = true
            case nil:
                continue
            }
        }
        return sawTransient ? .transient : nil
    }

    private static func unavailableKind(inText value: String) -> PDTLiveUnavailableKind? {
        let lower = value.lowercased()
        if authOrSetupPhrases.contains(where: { lower.contains($0) }) {
            return .authOrSetup
        }
        if transientUnavailablePhrases.contains(where: { lower.contains($0) }) {
            return .transient
        }
        return nil
    }

    private static let authOrSetupPhrases = [
        "not authenticated",
        "authentication required",
        "oauth",
        "missing credential",
        "credentials not found",
        "login required",
        "please login",
        "not logged in",
        "token expired",
        "session expired",
        "unauthorized",
        "forbidden",
        "server not found",
        "unknown mcp server",
        "setup required",
        "setup unavailable",
        "missing setup",
        "needs setup",
    ]

    private static let transientUnavailablePhrases = [
        "offline",
        "connection refused",
        "failed to connect",
        "could not connect",
        "econnrefused",
        "server unavailable",
    ]

    private static let errorTextKeys = Set([
        "error",
        "message",
        "detail",
        "details",
        "description",
        "status",
        "code",
    ])

    private static func unavailableTexts(in object: Any, forceErrorContext: Bool = false) -> [String] {
        if let string = object as? String {
            if forceErrorContext {
                return [string]
            }
            if let data = string.data(using: .utf8),
               let nested = try? JSONSerialization.jsonObject(with: data)
            {
                return unavailableTexts(in: nested)
            }
            return []
        }
        if let array = object as? [Any] {
            return forceErrorContext ? array.flatMap { unavailableTexts(in: $0, forceErrorContext: true) } : []
        }
        guard let dictionary = object as? [String: Any] else {
            return []
        }

        let isError = forceErrorContext || dictionary["isError"] as? Bool == true || dictionary["is_error"] as? Bool == true
        var texts: [String] = []
        for (key, value) in dictionary {
            if errorTextKeys.contains(key) {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            } else if key == "content", isError {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            } else if isError && (key == "text" || key == "title") {
                texts.append(contentsOf: unavailableTexts(in: value, forceErrorContext: true))
            }
        }
        return texts
    }
}

struct PDTListPage<Cursor, Item> {
    var items: [Item]
    var nextCursor: Cursor?
}

let pdtMaximumPagesPerList = 50

public enum PDTListPaginationPolicy {
    /// Both PDT list-tool schemas document "max: 100" for `per_page`;
    /// observed live on 2026-07-29.
    public static let pageSize = 100
}

enum PDTListPaginationTruncation {
    case pageCap
    case deadline
}

struct PDTListPaginationResult<Item> {
    var items: [Item]
    var pageCount: Int
    var truncation: PDTListPaginationTruncation?

    func truncationDiagnostic(
        toolName: String,
        phase: BackgroundDetailRefreshPhase,
        argumentShape: [String]
    ) -> PDTDetailRefreshFailureDiagnostic? {
        guard truncation != nil else {
            return nil
        }
        return PDTDetailRefreshFailureDiagnostic(
            toolName: toolName,
            phase: phase,
            attemptCount: max(1, pageCount),
            category: .timeout,
            argumentShape: argumentShape
        )
    }
}

func paginatePDTList<Cursor, Item>(
    initialCursor: Cursor,
    maxPages: Int,
    deadline: Date,
    now: @Sendable () -> Date,
    treatErrorAsDeadline: (Error) -> Bool = { _ in false },
    fetchPage: (Cursor) throws -> PDTListPage<Cursor, Item>
) throws -> PDTListPaginationResult<Item> {
    var cursor = initialCursor
    var items: [Item] = []
    var pageCount = 0
    while true {
        guard now() < deadline else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        let page: PDTListPage<Cursor, Item>
        do {
            page = try fetchPage(cursor)
        } catch {
            guard now() >= deadline, treatErrorAsDeadline(error) else {
                throw error
            }
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        pageCount += 1
        items.append(contentsOf: page.items)
        // Empty pages terminate even when stale server metadata claims more.
        guard !page.items.isEmpty, let nextCursor = page.nextCursor else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: nil)
        }
        guard pageCount < maxPages else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .pageCap)
        }
        guard now() < deadline else {
            return PDTListPaginationResult(items: items, pageCount: pageCount, truncation: .deadline)
        }
        cursor = nextCursor
    }
}

func pdtPaginationErrorIsRetryable(_ error: Error) -> Bool {
    if let wrapped = error as? PDTDetailRefreshToolError {
        return wrapped.diagnostic.category.isRetryable
    }
    return pdtDetailRefreshFailureCategory(for: error).isRetryable
}

public enum PDTIncomeQuoteLookupScope: Equatable, Sendable {
    case allOpenHoldings
    case calendarSymbolIDs
}

public struct PDTLiveDataSourceOptions: Equatable, Sendable {
    public var includeDistributions: Bool
    public var includeXRayHoldings: Bool
    public var includeIncomeEvents: Bool
    public var includeDividends: Bool
    public var includeIncomeQuoteLookups: Bool
    public var includePriceSeries: Bool
    public var paginationTimeoutSeconds: Double
    public var maxPagesPerList: Int
    public var incomeQuoteLookupScope: PDTIncomeQuoteLookupScope

    public init(
        includeDistributions: Bool = true,
        includeXRayHoldings: Bool = true,
        includeIncomeEvents: Bool = true,
        includeDividends: Bool = true,
        includeIncomeQuoteLookups: Bool = true,
        includePriceSeries: Bool = true,
        paginationTimeoutSeconds: Double = 240,
        maxPagesPerList: Int = 50,
        incomeQuoteLookupScope: PDTIncomeQuoteLookupScope = .allOpenHoldings
    ) {
        self.includeDistributions = includeDistributions
        self.includeXRayHoldings = includeXRayHoldings
        self.includeIncomeEvents = includeIncomeEvents
        self.includeDividends = includeDividends
        self.includeIncomeQuoteLookups = includeIncomeQuoteLookups
        self.includePriceSeries = includePriceSeries
        self.paginationTimeoutSeconds = max(0.01, paginationTimeoutSeconds)
        self.maxPagesPerList = min(pdtMaximumPagesPerList, max(1, maxPagesPerList))
        self.incomeQuoteLookupScope = incomeQuoteLookupScope
    }

    public static var firstFetch: PDTLiveDataSourceOptions {
        PDTLiveDataSourceOptions(
            includeDistributions: false,
            includeXRayHoldings: false,
            includeIncomeEvents: false,
            includeDividends: false,
            includeIncomeQuoteLookups: false,
            includePriceSeries: false,
            incomeQuoteLookupScope: .calendarSymbolIDs
        )
    }

    public var effectivePaginationTimeoutSeconds: Double {
        paginationTimeoutSeconds
    }

    public var requiredReadTools: [String] {
        var tools = ["pdt-get-portfolio-holdings"]
        if includeDistributions {
            tools.append("pdt-get-portfolio-distributions")
        }
        if includeXRayHoldings {
            tools.append("pdt-list-x-ray-holdings")
        }
        if includeIncomeEvents {
            tools.append("pdt-list-calendar-events")
        }
        if includeDividends {
            tools.append("pdt-list-dividends")
        }
        if includeIncomeQuoteLookups {
            tools.append("pdt-get-symbol-quote")
        }
        if includePriceSeries {
            tools.append("pdt-list-symbol-prices")
        }
        return tools
    }
}

public struct PDTLiveDataSource: PortfolioDataSource {
    public var toolClient: any PDTLiveToolClient
    public var options: PDTLiveDataSourceOptions
    public var onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)?
    private let now: @Sendable () -> Date

    public init(
        toolClient: any PDTLiveToolClient,
        options: PDTLiveDataSourceOptions = PDTLiveDataSourceOptions(),
        onOptionalFacetFailure: (@Sendable (PDTDetailRefreshFailureDiagnostic) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.toolClient = toolClient
        self.options = options
        self.onOptionalFacetFailure = onOptionalFacetFailure
        self.now = now
    }

    public func snapshot(asOf: String? = nil) throws -> PortfolioSnapshot {
        let snapshotAsOf = asOf ?? currentDayString()
        let incomeDateRange = [
            "date_from": snapshotAsOf,
            "date_to": dayString(snapshotAsOf, addingDays: 30),
        ]
        let dividendDateRange = [
            "date_from": dayString(snapshotAsOf, addingDays: -370),
            "date_to": incomeDateRange["date_to"] ?? snapshotAsOf,
        ]
        let holdingsEnvelope: LiveHoldingsEnvelope = try decodeLiveTool(
            "pdt-get-portfolio-holdings",
            data: toolClient.callReadTool("pdt-get-portfolio-holdings", arguments: [:])
        )

        var optionalFacetFailed = false
        var skipRemainingOptionalFacets = false
        func recordOptionalFacetFailure(
            _ error: Error,
            tool: String,
            phase: BackgroundDetailRefreshPhase,
            argumentShape: [String] = []
        ) {
            optionalFacetFailed = true
            let diagnostic = PDTDetailRefreshFailureDiagnostic(
                toolName: tool,
                phase: phase,
                attemptCount: 1,
                category: pdtDetailRefreshFailureCategory(for: error),
                argumentShape: argumentShape
            )
            onOptionalFacetFailure?(diagnostic)
            if diagnostic.category.indicatesUnavailableSetup {
                skipRemainingOptionalFacets = true
            }
        }
        func recordPaginationTruncation(_ diagnostic: PDTDetailRefreshFailureDiagnostic?) {
            guard let diagnostic else {
                return
            }
            optionalFacetFailed = true
            onOptionalFacetFailure?(diagnostic)
        }

        var distributionsEnvelope: LiveDistributionsEnvelope?
        if options.includeDistributions, !skipRemainingOptionalFacets {
            do {
                distributionsEnvelope = try decodeLiveTool(
                    "pdt-get-portfolio-distributions",
                    data: toolClient.callReadTool("pdt-get-portfolio-distributions", arguments: [:])
                )
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-get-portfolio-distributions",
                    phase: .allocation
                )
            }
        }

        var xRayHoldings: [PDTXRayHoldingInput]?
        if options.includeXRayHoldings, !skipRemainingOptionalFacets {
            do {
                let xRay = try liveXRayHoldings()
                xRayHoldings = xRay.holdings
                recordPaginationTruncation(xRay.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-x-ray-holdings",
                    phase: .xRay,
                    argumentShape: ["limit", "offset"]
                )
            }
        }

        let incomePaginationDeadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        var calendarEvents: [LiveCalendarEvent] = []
        if options.includeIncomeEvents, !skipRemainingOptionalFacets {
            do {
                let calendarPagination = try liveCalendarEvents(
                    arguments: incomeDateRange,
                    deadline: incomePaginationDeadline
                )
                calendarEvents = calendarPagination.events
                recordPaginationTruncation(calendarPagination.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-calendar-events",
                    phase: .income,
                    argumentShape: Array(incomeDateRange.keys) + ["page", "per_page"]
                )
            }
        }

        var dividends: [LiveDividend] = []
        if options.includeDividends, !skipRemainingOptionalFacets {
            do {
                let dividendPagination = try liveDividends(
                    arguments: dividendDateRange,
                    deadline: incomePaginationDeadline
                )
                dividends = dividendPagination.dividends
                recordPaginationTruncation(dividendPagination.diagnostic)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-dividends",
                    phase: .income,
                    argumentShape: Array(dividendDateRange.keys) + ["page", "per_page"]
                )
            }
        }

        let holdingInputs = holdingsEnvelope.holdings.map(\.baseHoldingInput)
        let portfolioCurrency = PDTBaseHoldingNormalizer.portfolioCurrency(from: holdingInputs, fallback: "EUR")
        let baseSnapshot = PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: portfolioCurrency,
                holdings: holdingInputs
            )
        )
        let neededCalendarSymbolIDs = Set(calendarEvents.filter { $0.type != "no-events-today" }.compactMap(\.symbolId))
        var quoteMetadata = SymbolQuoteMetadata()
        if options.includeIncomeQuoteLookups, !skipRemainingOptionalFacets {
            do {
                quoteMetadata = try liveSymbolQuoteMetadata(
                    for: baseSnapshot.openHoldings,
                    neededCalendarSymbolIDs: neededCalendarSymbolIDs
                )
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-get-symbol-quote",
                    phase: .income,
                    argumentShape: ["id"]
                )
            }
        }

        var priceSeries: [PDTPriceInput] = []
        if options.includePriceSeries, !skipRemainingOptionalFacets {
            do {
                priceSeries = try livePriceRows(for: baseSnapshot.openHoldings, asOf: snapshotAsOf)
            } catch {
                recordOptionalFacetFailure(
                    error,
                    tool: "pdt-list-symbol-prices",
                    phase: .priceHistory,
                    argumentShape: ["date_from", "date_to", "symbol_quote_id"]
                )
            }
        }
        return PDTSnapshotNormalizer.normalize(
            PDTSnapshotNormalizationInput(
                asOf: snapshotAsOf,
                currency: portfolioCurrency,
                holdings: holdingInputs,
                symbolQuotes: quoteMetadata.snapshotNormalizationInputs,
                distributions: distributionsEnvelope?.optionalDetailInput,
                xRayHoldings: xRayHoldings,
                calendarEvents: calendarEvents.map(\.optionalDetailInput),
                dividends: dividends.map(\.optionalDetailInput),
                priceRows: priceSeries,
                latestDetailFillOutcome: optionalFacetFailed ? .degraded : nil
            )
        )
    }

    private func liveSymbolQuoteMetadata(
        for holdings: [NormalizedHolding],
        neededCalendarSymbolIDs: Set<Int>
    ) throws -> SymbolQuoteMetadata {
        var metadata = SymbolQuoteMetadata()
        var remainingCalendarSymbolIDs = neededCalendarSymbolIDs
        var attemptedSymbolIDs = Set<Int>()
        var isinsBySymbolID: [Int: String] = [:]
        var symbolLookupUnavailable = false
        let lookupHoldings: [NormalizedHolding]
        switch options.incomeQuoteLookupScope {
        case .allOpenHoldings:
            lookupHoldings = holdings
        case .calendarSymbolIDs:
            guard !remainingCalendarSymbolIDs.isEmpty else {
                return metadata
            }
            lookupHoldings = Array(holdings.reversed())
        }
        for holding in lookupHoldings {
            let quote: LiveSymbolQuoteEnvelope = try decodeLiveTool(
                "pdt-get-symbol-quote",
                data: toolClient.callReadTool("pdt-get-symbol-quote", arguments: ["id": String(holding.quoteId)])
            )
            if options.incomeQuoteLookupScope == .calendarSymbolIDs {
                guard remainingCalendarSymbolIDs.remove(quote.symbolId) != nil else {
                    continue
                }
            }
            metadata.quoteIDsBySymbolID[quote.symbolId] = quote.id
            if let code = safePublicIdentifier(quote.code) {
                metadata.codesByQuoteID[quote.id] = code
            }
            if options.incomeQuoteLookupScope == .calendarSymbolIDs, remainingCalendarSymbolIDs.isEmpty {
                break
            }
            guard holding.isin == nil, !symbolLookupUnavailable else {
                continue
            }
            if let isin = isinsBySymbolID[quote.symbolId] {
                metadata.isinsByQuoteID[quote.id] = isin
                continue
            }
            guard attemptedSymbolIDs.insert(quote.symbolId).inserted else {
                continue
            }
            do {
                let symbol: LiveSymbolEnvelope = try decodeLiveTool(
                    "pdt-get-symbol",
                    data: toolClient.callReadTool("pdt-get-symbol", arguments: ["id": String(quote.symbolId)])
                )
                if let isin = PDTBaseHoldingNormalizer.safeISIN(symbol.isin) {
                    isinsBySymbolID[quote.symbolId] = isin
                    metadata.isinsByQuoteID[quote.id] = isin
                }
            } catch {
                symbolLookupUnavailable = shouldStopOptionalSymbolLookups(after: error)
            }
        }
        return metadata
    }

    private func shouldStopOptionalSymbolLookups(after error: Error) -> Bool {
        switch error {
        case is PDTMCPConnectorError:
            return true
        case PDTLiveDataSourceError.unavailableToolResult,
             PDTLiveDataSourceError.transientUnavailableToolResult:
            return true
        default:
            return false
        }
    }

    private func liveXRayHoldings()
        throws -> (holdings: [PDTXRayHoldingInput], diagnostic: PDTDetailRefreshFailureDiagnostic?)
    {
        let limit = 500
        let deadline = now().addingTimeInterval(options.effectivePaginationTimeoutSeconds)
        let pagination = try paginatePDTList(
            initialCursor: 0,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { offset in
            let arguments = ["limit": String(limit), "offset": String(offset)]
            let envelope: XRayHoldingsEnvelope = try decodeLiveTool(
                "pdt-list-x-ray-holdings",
                data: toolClient.callReadTool(
                    "pdt-list-x-ray-holdings",
                    arguments: arguments
                )
            )
            return PDTListPage(
                items: envelope.items.map(\.optionalDetailInput),
                nextCursor: envelope.hasMore == true ? offset + limit : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-x-ray-holdings",
                phase: .xRay,
                argumentShape: ["limit", "offset"]
            )
        )
    }

    private func liveCalendarEvents(
        arguments baseArguments: [String: String],
        deadline: Date
    ) throws -> (events: [LiveCalendarEvent], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            let envelope: LiveCalendarEventsEnvelope = try decodeLiveTool(
                "pdt-list-calendar-events",
                data: toolClient.callReadTool("pdt-list-calendar-events", arguments: arguments)
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-calendar-events",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
    }

    private func liveDividends(
        arguments baseArguments: [String: String],
        deadline: Date
    ) throws -> (dividends: [LiveDividend], diagnostic: PDTDetailRefreshFailureDiagnostic?) {
        let pagination = try paginatePDTList(
            initialCursor: 1,
            maxPages: options.maxPagesPerList,
            deadline: deadline,
            now: now,
            treatErrorAsDeadline: pdtPaginationErrorIsRetryable
        ) { page in
            let arguments = baseArguments.merging([
                "page": String(page),
                "per_page": String(PDTListPaginationPolicy.pageSize),
            ]) { _, new in new }
            let envelope: LiveDividendsEnvelope = try decodeLiveTool(
                "pdt-list-dividends",
                data: toolClient.callReadTool("pdt-list-dividends", arguments: arguments)
            )
            let lastPage = envelope.meta?.lastPage ?? page
            return PDTListPage(
                items: envelope.data,
                nextCursor: page < lastPage ? page + 1 : nil
            )
        }
        return (
            pagination.items,
            pagination.truncationDiagnostic(
                toolName: "pdt-list-dividends",
                phase: .income,
                argumentShape: Array(baseArguments.keys) + ["page", "per_page"]
            )
        )
    }

    private func livePriceRows(for holdings: [NormalizedHolding], asOf: String) throws -> [PDTPriceInput] {
        let priceDateRange = [
            "date_from": dayString(asOf, addingDays: -7),
            "date_to": asOf,
        ]
        return try holdings.flatMap { holding in
            let prices: LivePricesEnvelope = try decodeLiveTool(
                "pdt-list-symbol-prices",
                data: toolClient.callReadTool(
                    "pdt-list-symbol-prices",
                    arguments: priceDateRange.merging(["symbol_quote_id": String(holding.quoteId)]) { _, new in new }
                )
            )
            return prices.data.map(\.optionalDetailInput)
        }
    }
}

struct LivePortfolioPerformanceEnvelope: Decodable {
    var oldestPortfolioDate: String?
    var latestPortfolioDate: String?
}

struct LivePortfolioGainsEnvelope: Decodable {
    var totalGainsPercentage: Double?
}

struct LiveHoldingsEnvelope: Decodable {
    var holdings: [LiveHolding]
}

struct LiveHolding: Decodable {
    var symbolName: String
    var symbolQuoteId: Int
    var currentPriceDate: String
    var currentPriceLocal: Money?
    var currentExchangeRate: Double?
    var currentWorth: Money?
    var currentWorthLocal: Money
    var portfolioWeight: Double
    var unrealisedBoughtPriceAverageLocal: Money?
    var unrealisedBoughtPriceTotalLocal: Money?
    var unrealisedBoughtShares: Double?
    var unrealisedGains: Money?
    var unrealisedGainsPercentage: Double?
    var closedAt: String?
    var isin: String?

    enum CodingKeys: String, CodingKey {
        case symbolName
        case symbolQuoteId
        case currentPriceDate
        case currentPriceLocal
        case currentExchangeRate
        case currentWorth
        case currentWorthLocal
        case portfolioWeight
        case unrealisedBoughtPriceAverageLocal
        case unrealisedBoughtPriceTotalLocal
        case unrealisedBoughtShares
        case unrealisedGains
        case unrealisedGainsPercentage
        case closedAt
        case isin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        symbolQuoteId = try container.decode(Int.self, forKey: .symbolQuoteId)
        currentPriceDate = try container.decode(String.self, forKey: .currentPriceDate)
        currentPriceLocal = try? container.decodeIfPresent(Money.self, forKey: .currentPriceLocal)
        currentExchangeRate = try? container.decodeIfPresent(Double.self, forKey: .currentExchangeRate)
        currentWorth = try? container.decodeIfPresent(Money.self, forKey: .currentWorth)
        currentWorthLocal = try container.decode(Money.self, forKey: .currentWorthLocal)
        portfolioWeight = try container.decode(Double.self, forKey: .portfolioWeight)
        unrealisedBoughtPriceAverageLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceAverageLocal
        )
        unrealisedBoughtPriceTotalLocal = try? container.decodeIfPresent(
            Money.self,
            forKey: .unrealisedBoughtPriceTotalLocal
        )
        unrealisedBoughtShares = try? container.decodeIfPresent(Double.self, forKey: .unrealisedBoughtShares)
        unrealisedGains = try? container.decodeIfPresent(Money.self, forKey: .unrealisedGains)
        unrealisedGainsPercentage = try? container.decodeIfPresent(Double.self, forKey: .unrealisedGainsPercentage)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
    }
}

extension LiveHolding {
    var baseHoldingInput: PDTBaseHoldingInput {
        PDTBaseHoldingInput(
            name: symbolName,
            quoteId: symbolQuoteId,
            currentPriceDate: currentPriceDate,
            currentPriceLocal: currentPriceLocal,
            currentExchangeRate: currentExchangeRate,
            currentWorth: currentWorth,
            currentWorthLocal: currentWorthLocal,
            portfolioWeight: portfolioWeight,
            unrealisedBoughtPriceAverageLocal: unrealisedBoughtPriceAverageLocal,
            unrealisedBoughtPriceTotalLocal: unrealisedBoughtPriceTotalLocal,
            unrealisedBoughtShares: unrealisedBoughtShares,
            unrealisedGains: unrealisedGains,
            unrealisedGainsPercentage: unrealisedGainsPercentage,
            closedAt: closedAt,
            isin: isin
        )
    }
}

struct XRayHoldingsEnvelope: Decodable {
    var items: [XRayHolding]
    var hasMore: Bool?
}

struct XRayHolding: Decodable {
    var weight: Double

    var optionalDetailInput: PDTXRayHoldingInput {
        PDTXRayHoldingInput(weight: weight)
    }
}

struct LiveDistributionsEnvelope: Decodable {
    var sectors: [LiveDistribution]
    var assetTypes: [LiveDistribution]

    var optionalDetailInput: PDTOptionalDistributionsInput {
        PDTOptionalDistributionsInput(
            sectors: sectors.map(\.optionalDetailInput),
            assetTypes: assetTypes.map(\.optionalDetailInput)
        )
    }
}

struct LiveDistribution: Decodable {
    var categoryName: String
    var totalValue: Money
    var percentage: Double

    var optionalDetailInput: PDTDistributionInput {
        PDTDistributionInput(categoryName: categoryName, totalValue: totalValue, percentage: percentage)
    }
}

struct LiveCalendarEventsEnvelope: Decodable {
    var data: [LiveCalendarEvent]
    var meta: LivePaginationMeta?
}

struct LiveCalendarEvent: Decodable {
    var date: String
    var type: String
    var isEstimated: Bool
    var symbolId: Int?
    var symbolName: String?

    var optionalDetailInput: PDTCalendarEventInput {
        PDTCalendarEventInput(
            date: date,
            type: type,
            isEstimated: isEstimated,
            symbolId: symbolId,
            symbolName: symbolName
        )
    }
}

struct LiveDividendsEnvelope: Decodable {
    var data: [LiveDividend]
    var meta: LivePaginationMeta?
}

struct LivePaginationMeta: Decodable {
    var lastPage: Int

    enum CodingKeys: String, CodingKey {
        case lastPage
        case lastPageSnake = "last_page"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPageSnake)
            ?? container.decodeIfPresent(Int.self, forKey: .lastPage)
            ?? 1
    }
}

struct LiveDividend: Decodable {
    var date: String
    var amount: Money
    var symbolQuoteId: Int

    var optionalDetailInput: PDTDividendInput {
        PDTDividendInput(date: date, amount: amount, symbolQuoteId: symbolQuoteId)
    }
}

struct LiveSymbolQuoteEnvelope: Decodable {
    var id: Int
    var code: String?
    var symbolId: Int
}

private struct LiveSymbolEnvelope: Decodable {
    var isin: String?
}

private struct SymbolQuoteMetadata {
    var quoteIDsBySymbolID: [Int: Int] = [:]
    var codesByQuoteID: [Int: String] = [:]
    var isinsByQuoteID: [Int: String] = [:]
}

private extension SymbolQuoteMetadata {
    var snapshotNormalizationInputs: [PDTSymbolQuoteNormalizationInput] {
        quoteIDsBySymbolID.map { symbolId, quoteId in
            PDTSymbolQuoteNormalizationInput(
                quoteId: quoteId,
                symbolId: symbolId,
                copyableIdentifier: codesByQuoteID[quoteId],
                isin: isinsByQuoteID[quoteId]
            )
        }
    }
}

struct LivePricesEnvelope: Decodable {
    var data: [LivePrice]
}

struct LivePrice: Decodable {
    var date: String
    var closeAdjusted: String
    var closeCurrency: String?
    var symbolQuoteId: Int

    var optionalDetailInput: PDTPriceInput {
        PDTPriceInput(date: date, closeAdjusted: closeAdjusted, symbolQuoteId: symbolQuoteId, closeCurrency: closeCurrency)
    }
}

func safePublicIdentifier(_ raw: String?) -> String? {
    PDTBaseHoldingNormalizer.safePublicIdentifier(raw)
}
func decodeLiveTool<T: Decodable>(_ tool: String, data: Data) throws -> T {
    let extraction = extractLiveToolPayload(from: data)
    if let decoded = try? JSONDecoder().decode(T.self, from: extraction.payloadData) {
        return decoded
    }
    let unavailableKind = extraction.unavailableKind ?? unavailableTextPayloadKind(extraction.payloadData)
    if unavailableKind == .authOrSetup {
        throw PDTLiveDataSourceError.unavailableToolResult(tool)
    }
    if unavailableKind == .transient {
        throw PDTLiveDataSourceError.transientUnavailableToolResult(tool)
    }
    throw PDTLiveDataSourceError.malformedToolResult(tool)
}

private struct LiveToolPayloadExtraction {
    var payloadData: Data
    var unavailableKind: PDTLiveUnavailableKind?
}

private struct ExtractedMCPPayload {
    var data: Data
    var unavailableKind: PDTLiveUnavailableKind?
}

private func extractLiveToolPayload(from data: Data) -> LiveToolPayloadExtraction {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
        return LiveToolPayloadExtraction(
            payloadData: data,
            unavailableKind: unavailableTextPayloadKind(data)
        )
    }
    let extracted = extractedMCPPayload(from: object)
    return LiveToolPayloadExtraction(
        payloadData: extracted?.data ?? data,
        unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: object) ?? extracted?.unavailableKind
    )
}

private func extractedMCPPayload(from object: Any) -> ExtractedMCPPayload? {
    if let dictionary = object as? [String: Any] {
        if let content = dictionary["content"] as? [Any] {
            for item in content {
                guard let item = item as? [String: Any],
                      item["type"] as? String == "text",
                      let text = item["text"] as? String,
                      let textData = text.data(using: .utf8)
                else { continue }
                return ExtractedMCPPayload(data: textData, unavailableKind: nil)
            }
        }
        guard let nested = dictionary["result"],
              let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
        else {
            guard let nested = dictionary["data"] as? [String: Any],
                  let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
            else { return nil }
            return ExtractedMCPPayload(
                data: nestedData,
                unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: nested, forceErrorContext: true)
            )
        }
        return ExtractedMCPPayload(
            data: nestedData,
            unavailableKind: PDTLiveUnavailableClassifier.unavailableKind(in: nested, forceErrorContext: true)
        )
    }
    return nil
}

private func unavailableTextPayload(_ data: Data) -> Bool {
    unavailableTextPayloadKind(data) != nil
}

private func unavailableTextPayloadKind(_ data: Data) -> PDTLiveUnavailableKind? {
    guard let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return PDTLiveUnavailableClassifier.unavailableKind(in: text)
}
