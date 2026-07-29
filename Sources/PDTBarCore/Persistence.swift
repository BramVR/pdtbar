import Darwin
import Foundation

public struct PulseReadState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var readFingerprints: [String]

    public init(schemaVersion: Int = 1, readFingerprints: [String] = []) {
        self.schemaVersion = schemaVersion
        self.readFingerprints = Array(Set(readFingerprints)).sorted()
    }

    public func contains(_ fingerprint: String) -> Bool {
        Set(readFingerprints).contains(fingerprint)
    }
}

public struct PulseReadStore: Sendable {
    public var directory: URL
    private static let mutationQueue = DispatchQueue(label: "PDTBarCore.PulseReadStore.mutation")

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> PulseReadState {
        try Self.mutationQueue.sync {
            try loadUnlocked()
        }
    }

    public func save(_ state: PulseReadState) throws {
        try Self.mutationQueue.sync {
            try saveUnlocked(state)
        }
    }

    public func markRead(_ fingerprint: String) throws {
        try Self.mutationQueue.sync {
            var state = try loadUnlocked()
            state = PulseReadState(
                schemaVersion: state.schemaVersion,
                readFingerprints: state.readFingerprints + [fingerprint]
            )
            try saveUnlocked(state)
        }
    }

    public func removeReadFingerprints(_ fingerprints: Set<String>) throws -> PulseReadState {
        try Self.mutationQueue.sync {
            let state = try loadUnlocked()
            let resetState = PulseReadState(
                schemaVersion: state.schemaVersion,
                readFingerprints: state.readFingerprints.filter { !fingerprints.contains($0) }
            )
            if resetState != state {
                try saveUnlocked(resetState)
            }
            return resetState
        }
    }

    private func loadUnlocked() throws -> PulseReadState {
        let target = stateFile
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return PulseReadState()
        }
        if !isDirectory.boolValue {
            try OwnerOnlyLocalStore.protectExistingFile(target)
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            if !FileManager.default.fileExists(atPath: target.path) {
                return PulseReadState()
            }
            throw error
        }
        guard let state = try? JSONDecoder().decode(PulseReadState.self, from: data) else {
            return PulseReadState()
        }
        return state
    }

    private func saveUnlocked(_ state: PulseReadState) throws {
        try OwnerOnlyLocalStore.write(stableJSONData(state), to: stateFile)
    }

    private var stateFile: URL {
        directory.appending(path: "pulse-read-state.json")
    }
}

private enum OwnerOnlyLocalStore {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    static func protectExistingFile(_ target: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return
        }
        try prepareDirectory(target.deletingLastPathComponent())
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: target.path
        )
    }

    static func write(_ data: Data, to target: URL) throws {
        let directory = target.deletingLastPathComponent()
        try prepareDirectory(directory)
        let temporary = directory.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: filePermissions]
        ) else {
            throw POSIXError(.EIO)
        }
        var removeTemporaryOnFailure = true
        defer {
            if removeTemporaryOnFailure {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: temporary.path
        )
        let renameResult = temporary.withUnsafeFileSystemRepresentation { temporaryPath in
            target.withUnsafeFileSystemRepresentation { targetPath in
                guard let temporaryPath, let targetPath else {
                    return -1
                }
                return Int(Darwin.rename(temporaryPath, targetPath))
            }
        }
        guard renameResult == 0 else {
            let failure = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(failure)
        }
        removeTemporaryOnFailure = false
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: target.path
        )
    }
}

public enum PulseReadFilter {
    public static func apply(to model: PortfolioPulseModel, readState: PulseReadState) -> PortfolioPulseModel {
        let visibleItems = model.rankedAttentionItems.filter { !readState.contains($0.readFingerprint) }
        var filtered = model
        filtered.rankedAttentionItems = visibleItems
        filtered.attentionItems = visibleItems
        filtered.allQuiet = visibleItems.isEmpty
        if visibleItems.isEmpty, !model.rankedAttentionItems.isEmpty {
            filtered.allQuietSignal = AllQuietSignal(
                title: "All caught up",
                detail: "No unread items.",
                totalValue: model.allQuietSignal.totalValue
            )
        }
        return filtered
    }
}

public enum PulseLifecycleSource: String, Codable, Equatable {
    case cachedSnapshot
    case fetchedSnapshot
    case refreshedSnapshot
}

public enum PriorSnapshotLoadFailureKind: String, Codable, Equatable, Sendable {
    case decode
    case io
}

public enum PriorSnapshotLoadStatus: Codable, Equatable, Sendable {
    case notRequested
    case missing
    case loaded
    case failed(PriorSnapshotLoadFailureKind)
}

public enum PriorSnapshotLoadResult: Codable, Equatable {
    case missing
    case loaded(PortfolioSnapshot)
    case failed(PriorSnapshotLoadFailureKind)

    public var snapshot: PortfolioSnapshot? {
        guard case .loaded(let snapshot) = self else {
            return nil
        }
        return snapshot
    }

    public var status: PriorSnapshotLoadStatus {
        switch self {
        case .missing:
            return .missing
        case .loaded:
            return .loaded
        case .failed(let kind):
            return .failed(kind)
        }
    }
}

public struct PriorSnapshotLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    public var kind: PriorSnapshotLoadFailureKind

    public init(kind: PriorSnapshotLoadFailureKind) {
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .decode:
            return "Prior snapshot could not be decoded"
        case .io:
            return "Prior snapshot could not be read"
        }
    }
}

public struct PulseLifecycleResult: Codable, Equatable {
    public var unfilteredModel: PortfolioPulseModel
    public var model: PortfolioPulseModel
    public var snapshotCommit: SnapshotCommit
    public var descriptor: MenuDescriptor
    public var readState: PulseReadState?
    public var source: PulseLifecycleSource
    public var priorSnapshotLoadStatus: PriorSnapshotLoadStatus?

    public init(
        unfilteredModel: PortfolioPulseModel,
        model: PortfolioPulseModel,
        snapshotCommit: SnapshotCommit,
        descriptor: MenuDescriptor,
        readState: PulseReadState? = nil,
        source: PulseLifecycleSource,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
    ) {
        self.unfilteredModel = unfilteredModel
        self.model = model
        self.snapshotCommit = snapshotCommit
        self.descriptor = descriptor
        self.readState = readState
        self.source = source
        self.priorSnapshotLoadStatus = priorSnapshotLoadStatus
    }

    public func applyingReadState(_ readState: PulseReadState?) -> PulseLifecycleResult {
        var model = PressureRunner.modelAfterApplyingReadState(unfilteredModel, readState: readState)
        var dataHealth = model.facetSnapshots.dataHealth
        let readFingerprintCount = readState?.readFingerprints.count ?? 0
        dataHealth.readState = DataHealthReadStateSnapshot(
            readFingerprintCount: readFingerprintCount,
            detail: "\(readFingerprintCount) read"
        )
        model.facetSnapshots.dataHealth = dataHealth
        return PulseLifecycleResult(
            unfilteredModel: unfilteredModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model),
            readState: readState,
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus ?? .notRequested
        )
    }

    public func rendered(settings: PortfolioValueDisplaySettings) -> PulseLifecycleResult {
        PulseLifecycleResult(
            unfilteredModel: unfilteredModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model, settings: settings),
            readState: readState,
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus ?? .notRequested
        )
    }
}

public typealias PressureRunResult = PulseLifecycleResult

public struct SnapshotCommit: Codable, Equatable {
    public var written: Bool
    public var path: String
    public var asOf: String

    public init(written: Bool, path: String, asOf: String) {
        self.written = written
        self.path = path
        self.asOf = asOf
    }
}

public protocol PortfolioDataSource {
    func snapshot(asOf: String?) throws -> PortfolioSnapshot
}

public extension PortfolioDataSource {
    func snapshot() throws -> PortfolioSnapshot {
        try snapshot(asOf: nil)
    }
}

public protocol PortfolioPriorSnapshotDataSource {
    func priorSnapshot(asOf: String?) throws -> PortfolioSnapshot
}

public extension PortfolioPriorSnapshotDataSource {
    func priorSnapshot() throws -> PortfolioSnapshot {
        try priorSnapshot(asOf: nil)
    }
}

public enum PressureRunner {
    /// Rebuilds a pulse from the cached snapshot. Freshness is evaluated
    /// against `today` (defaulting to the current day), never only against the
    /// cached snapshot's own asOf, so a snapshot from a prior day cannot be
    /// relabeled fresh on relaunch. Tests inject `today` for determinism.
    public static func cachedPulse(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        today: String? = nil
    ) throws -> PulseLifecycleResult? {
        let snapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        guard case .loaded(let snapshot) = snapshotLoad else {
            if case .failed(let kind) = snapshotLoad {
                throw PriorSnapshotLoadError(kind: kind)
            }
            return nil
        }
        let commit = SnapshotCommit(
            written: false,
            path: snapshotStore.currentSnapshotPath.path,
            asOf: snapshot.asOf
        )
        return try lifecycleResult(
            snapshot: snapshot,
            priorSnapshot: nil,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .cachedSnapshot,
            resetsReappearedReadState: false,
            detailRefreshDiagnostic: cachedDetailRefreshDiagnostic(for: snapshot, snapshotStore: snapshotStore),
            priorSnapshotLoadStatus: snapshotLoad.status,
            today: today ?? currentDayString()
        )
    }

    private static func cachedDetailRefreshDiagnostic(
        for snapshot: PortfolioSnapshot,
        snapshotStore: SnapshotStore
    ) -> PDTDetailRefreshFailureDiagnostic? {
        guard snapshot.latestDetailFillOutcome == .degraded else {
            return nil
        }
        return try? snapshotStore.loadLastDetailRefreshDiagnostic()
    }

    public static func cachedPulseDescriptor(
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        today: String? = nil
    ) throws -> MenuDescriptor? {
        try cachedPulse(
            snapshotStore: snapshotStore,
            pulseReadStore: pulseReadStore,
            today: today
        )?.descriptor
    }

    public static func seedPriorSnapshot(
        dataSource: any PortfolioPriorSnapshotDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil
    ) throws -> SnapshotCommit {
        let priorSnapshot = try dataSource.priorSnapshot(asOf: asOf)
        return try snapshotStore.commitCurrentSnapshot(priorSnapshot)
    }

    public static func seedPriorSnapshot(fixture: URL, snapshotDirectory: URL) throws -> SnapshotCommit {
        try seedPriorSnapshot(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: SnapshotStore(directory: snapshotDirectory)
        )
    }

    public static func run(
        dataSource: any PortfolioDataSource,
        snapshotStore: SnapshotStore,
        asOf: String? = nil,
        pulseReadStore: PulseReadStore? = nil
    ) throws -> PressureRunResult {
        var snapshot = try dataSource.snapshot(asOf: asOf)
        let priorSnapshotLoad = try snapshotStore.loadPriorSnapshotResult()
        let priorSnapshot = priorSnapshotLoad.snapshot
        if hasOptionalDetailSlice(snapshot) {
            snapshot.latestCompleteDetailFillAsOf = snapshot.asOf
            snapshot.latestDetailFillOutcome = .completed
        } else if let priorSnapshot {
            snapshot.latestCompleteDetailFillAsOf = snapshot.latestCompleteDetailFillAsOf
                ?? priorSnapshot.latestCompleteDetailFillAsOf
            snapshot.latestDetailFillOutcome = snapshot.latestDetailFillOutcome
                ?? priorSnapshot.latestDetailFillOutcome
        }
        let loadedReadState = displayReadState(from: pulseReadStore)
        let commit = try snapshotStore.commitCurrentSnapshot(snapshot)
        return try lifecycleResult(
            snapshot: snapshot,
            priorSnapshot: priorSnapshot,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .fetchedSnapshot,
            loadedReadState: loadedReadState,
            resetsReappearedReadState: true,
            priorSnapshotLoadStatus: priorSnapshotLoad.status
        )
    }

    private static func hasOptionalDetailSlice(_ snapshot: PortfolioSnapshot) -> Bool {
        !snapshot.sectors.isEmpty
            || !snapshot.assetTypes.isEmpty
            || !(snapshot.xRayHoldings ?? []).isEmpty
            || !snapshot.incomeEvents.isEmpty
            || snapshot.dividendRowCount > 0
            || !snapshot.priceSeries.isEmpty
    }

    public static func refreshedPulse(
        snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        snapshotStore: SnapshotStore,
        pulseReadStore: PulseReadStore? = nil,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested
    ) throws -> PulseLifecycleResult {
        let loadedReadState = displayReadState(from: pulseReadStore)
        var committedSnapshot = snapshot
        if let detailRefreshOutcome {
            committedSnapshot.latestDetailFillOutcome = detailRefreshOutcome
        }
        if detailRefreshOutcome == .completed {
            committedSnapshot.latestCompleteDetailFillAsOf = committedSnapshot.asOf
        }
        let commit = try snapshotStore.commitCurrentSnapshot(committedSnapshot)
        return try lifecycleResult(
            snapshot: committedSnapshot,
            priorSnapshot: priorSnapshot,
            snapshotCommit: commit,
            pulseReadStore: pulseReadStore,
            source: .refreshedSnapshot,
            loadedReadState: loadedReadState,
            resetsReappearedReadState: true,
            detailRefreshOutcome: detailRefreshOutcome,
            detailRefreshDiagnostic: detailRefreshDiagnostic,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus
        )
    }

    static func displayReadState(from pulseReadStore: PulseReadStore?) -> PulseReadState? {
        guard let pulseReadStore else {
            return nil
        }
        return try? pulseReadStore.load()
    }

    public static func run(fixture: URL, snapshotDirectory: URL) throws -> PressureRunResult {
        try run(
            dataSource: PDTFixtureDataSource(fixture: fixture),
            snapshotStore: SnapshotStore(directory: snapshotDirectory)
        )
    }

    static func modelAfterApplyingReadState(
        _ model: PortfolioPulseModel,
        readState: PulseReadState?
    ) -> PortfolioPulseModel {
        guard let readState else {
            return model
        }
        return PulseReadFilter.apply(to: model, readState: readState)
    }

    static func lifecycleResult(
        snapshot: PortfolioSnapshot,
        priorSnapshot: PortfolioSnapshot?,
        snapshotCommit: SnapshotCommit,
        pulseReadStore: PulseReadStore?,
        source: PulseLifecycleSource,
        loadedReadState: PulseReadState? = nil,
        resetsReappearedReadState: Bool,
        detailRefreshOutcome: PDTBackgroundDetailRefreshOutcome? = nil,
        detailRefreshDiagnostic: PDTDetailRefreshFailureDiagnostic? = nil,
        priorSnapshotLoadStatus: PriorSnapshotLoadStatus = .notRequested,
        today: String? = nil
    ) throws -> PulseLifecycleResult {
        let displayReadState = loadedReadState ?? displayReadState(from: pulseReadStore)
        let effectiveDetailRefreshOutcome = detailRefreshOutcome ?? snapshot.latestDetailFillOutcome
        var rawModel = PressureEngine.buildModel(
            from: snapshot,
            priorSnapshot: priorSnapshot,
            readState: displayReadState,
            detailRefreshOutcome: effectiveDetailRefreshOutcome,
            today: today
        )
        rawModel.facetSnapshots.dataHealth = DataHealth.build(
            DataHealthInput.default(
                freshness: rawModel.facetSnapshots.freshness,
                pulseSource: source,
                readState: displayReadState,
                detailRefreshOutcome: effectiveDetailRefreshOutcome,
                diagnostic: detailRefreshDiagnostic,
                priorSnapshotLoadStatus: priorSnapshotLoadStatus
            )
        )
        let readState = resetsReappearedReadState
            ? try readStateAfterResettingReappearedItems(
                in: rawModel,
                loadedReadState: displayReadState,
                pulseReadStore: pulseReadStore
            )
            : displayReadState
        var model = modelAfterApplyingReadState(rawModel, readState: readState)
        model.facetSnapshots.dataHealth = DataHealth.build(
            DataHealthInput.default(
                freshness: model.facetSnapshots.freshness,
                pulseSource: source,
                readState: readState,
                detailRefreshOutcome: effectiveDetailRefreshOutcome,
                diagnostic: detailRefreshDiagnostic,
                priorSnapshotLoadStatus: priorSnapshotLoadStatus
            )
        )
        return PulseLifecycleResult(
            unfilteredModel: rawModel,
            model: model,
            snapshotCommit: snapshotCommit,
            descriptor: MenuDescriptorRenderer.render(model: model),
            readState: readState,
            source: source,
            priorSnapshotLoadStatus: priorSnapshotLoadStatus
        )
    }

    static func readStateAfterResettingReappearedItems(
        in model: PortfolioPulseModel,
        loadedReadState: PulseReadState?,
        pulseReadStore: PulseReadStore?
    ) throws -> PulseReadState? {
        guard let loadedReadState,
              let pulseReadStore
        else {
            return loadedReadState
        }
        let reappearedFingerprints = Set(
            model.rankedAttentionItems
                .filter(\.resetsReadState)
                .map(\.readFingerprint)
        )
        let staleFingerprints = staleReadFingerprints(in: model, readState: loadedReadState)
        let fingerprintsToRemove = reappearedFingerprints.union(staleFingerprints)
        guard !fingerprintsToRemove.isEmpty else {
            return loadedReadState
        }
        return try pulseReadStore.removeReadFingerprints(fingerprintsToRemove)
    }

    private static func staleReadFingerprints(
        in model: PortfolioPulseModel,
        readState: PulseReadState
    ) -> Set<String> {
        var currentFingerprintsByPrefix: [String: Set<String>] = [:]
        for item in model.rankedAttentionItems {
            guard let prefix = item.staleReadPruningPrefix else {
                continue
            }
            currentFingerprintsByPrefix[prefix, default: []].insert(item.readFingerprint)
        }
        guard !currentFingerprintsByPrefix.isEmpty else {
            return []
        }
        return Set(readState.readFingerprints.filter { fingerprint in
            currentFingerprintsByPrefix.contains { prefix, currentFingerprints in
                fingerprint.hasPrefix(prefix) && !currentFingerprints.contains(fingerprint)
            }
        })
    }
}

public struct SnapshotStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func temporaryTestStore(prefix: String = "pdtbar-snapshot-store") throws -> SnapshotStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        try OwnerOnlyLocalStore.prepareDirectory(directory)
        return SnapshotStore(directory: directory)
    }

    public func loadPriorSnapshot() throws -> PortfolioSnapshot? {
        switch try loadPriorSnapshotResult() {
        case .missing:
            return nil
        case .loaded(let snapshot):
            return snapshot
        case .failed(let kind):
            throw PriorSnapshotLoadError(kind: kind)
        }
    }

    public func loadPriorSnapshotResult() throws -> PriorSnapshotLoadResult {
        let target = currentSnapshotPath
        guard FileManager.default.fileExists(atPath: target.path) else {
            return .missing
        }
        do {
            try OwnerOnlyLocalStore.protectExistingFile(target)
        } catch {
            return .failed(.io)
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            return .failed(.io)
        }
        do {
            return .loaded(try JSONDecoder().decode(PortfolioSnapshot.self, from: data))
        } catch {
            return .failed(.decode)
        }
    }

    public func commitCurrentSnapshot(_ snapshot: PortfolioSnapshot) throws -> SnapshotCommit {
        let target = currentSnapshotPath
        try OwnerOnlyLocalStore.write(stableJSONData(snapshot), to: target)
        return SnapshotCommit(written: true, path: target.path, asOf: snapshot.asOf)
    }

    public func write(snapshot: PortfolioSnapshot) throws -> SnapshotCommit {
        try commitCurrentSnapshot(snapshot)
    }

    public func loadLastDetailRefreshDiagnostic() throws -> PDTDetailRefreshFailureDiagnostic? {
        let target = detailRefreshDiagnosticFile
        guard FileManager.default.fileExists(atPath: target.path) else {
            return nil
        }
        try OwnerOnlyLocalStore.protectExistingFile(target)
        return try JSONDecoder().decode(PDTDetailRefreshFailureDiagnostic.self, from: Data(contentsOf: target))
    }

    public func saveLastDetailRefreshDiagnostic(_ diagnostic: PDTDetailRefreshFailureDiagnostic) throws {
        try OwnerOnlyLocalStore.write(stableJSONData(diagnostic), to: detailRefreshDiagnosticFile)
    }

    public func clearLastDetailRefreshDiagnostic() throws {
        let target = detailRefreshDiagnosticFile
        guard FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    private var detailRefreshDiagnosticFile: URL {
        directory.appending(path: "latest-detail-refresh-diagnostic.json")
    }

    public var currentSnapshotPath: URL {
        directory.appending(path: "latest-portfolio-snapshot.json")
    }
}

public typealias SnapshotFileStore = SnapshotStore
