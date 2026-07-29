import Foundation
import PDTBarCore
import Testing

@Suite("PDT cancellation")
struct CancellationTests {
    @Test("Cancelling mid-refresh prevents another CLI call")
    func cancellingMidRefreshPreventsAnotherCall() throws {
        let cancellation = PDTCancellation()
        let connector = CancellingRetryConnector(cancellation: cancellation)
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-cancel-retry")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        #expect(throws: (any Error).self) {
            _ = try PDTBackgroundDetailRefresh(
                connector: connector,
                snapshotStore: store,
                asOf: "2026-03-29",
                options: PDTBackgroundDetailRefreshOptions(
                    optionalRetryCount: 3,
                    retryBackoffSeconds: 0
                )
            ).refresh(cancellation: cancellation)
        }

        let callsAtReturn = connector.callCount
        Thread.sleep(forTimeInterval: 0.1)
        #expect(callsAtReturn == 1)
        #expect(connector.callCount == callsAtReturn)
    }

    @Test("Price timeout grace waits for a cancelling worker")
    func priceTimeoutGraceWaitsForCancellingWorker() throws {
        let connector = PriceCancellationConnector(mode: .cooperative(cleanupDelay: 0.2))
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-cancel-grace")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        let started = Date()
        let result = try refresh(connector: connector, store: store)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.outcome == .degraded)
        #expect(elapsed >= 0.18)
        #expect(elapsed < 1.5)
        #expect(!connector.priceCallIsActive)
        #expect(connector.priceCallCount == 1)
    }

    @Test("Price timeout does not cancel the later performance phase")
    func priceTimeoutDoesNotCancelLaterPerformancePhase() throws {
        let connector = PriceCancellationConnector(
            mode: .cooperative(cleanupDelay: 0),
            includesPerformance: true
        )
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-cancel-phase-local")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        let result = try refresh(connector: connector, store: store)

        #expect(result.outcome == .degraded)
        #expect(connector.performanceCallCount == 2)
        #expect(try store.loadPriorSnapshot()?.performance != nil)
    }

    @Test("Parent cancellation during performance aborts the refresh")
    func parentCancellationDuringPerformanceAbortsRefresh() throws {
        let cancellation = PDTCancellation()
        let connector = PriceCancellationConnector(
            mode: .cooperative(cleanupDelay: 0),
            includesPerformance: true,
            cancelOnPerformance: cancellation
        )
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-parent-cancel-performance")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        #expect(throws: (any Error).self) {
            _ = try PDTBackgroundDetailRefresh(
                connector: connector,
                snapshotStore: store,
                asOf: "2026-03-29",
                options: PDTBackgroundDetailRefreshOptions(
                    priceHistoryConcurrencyLimit: 1,
                    priceHistoryTimeoutSeconds: 0.05,
                    retryBackoffSeconds: 0
                )
            ).refresh(cancellation: cancellation)
        }
        #expect(cancellation.isCancelled)
        #expect(connector.performanceCallCount == 1)
    }

    @Test("Price timeout grace stays bounded for a worker that never finishes")
    func priceTimeoutGraceStaysBoundedForWorkerThatNeverFinishes() throws {
        let connector = PriceCancellationConnector(mode: .never)
        defer {
            connector.releaseNeverFinishingWorker()
        }
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-cancel-bounded")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }

        let started = Date()
        let result = try refresh(connector: connector, store: store)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.outcome == .degraded)
        #expect(elapsed >= 2.9)
        #expect(elapsed < 3.6)
        #expect(connector.priceCallIsActive)
    }

    @Test("A late price worker cannot mutate assembled state")
    func latePriceWorkerCannotMutateAssembledState() throws {
        let connector = PriceCancellationConnector(mode: .stubborn(delay: 3.7))
        let store = try SnapshotStore.temporaryTestStore(prefix: "pdtbar-cancel-late-worker")
        defer {
            try? FileManager.default.removeItem(at: store.directory)
        }
        let progress = CancellationProgressRecorder()

        let started = Date()
        let result = try refresh(
            connector: connector,
            store: store,
            progress: progress.record
        )
        let elapsed = Date().timeIntervalSince(started)
        let progressCountAtReturn = progress.count
        let priceSeriesAtReturn = try #require(try store.loadPriorSnapshot()).priceSeries

        #expect(result.outcome == .degraded)
        #expect(elapsed >= 2.9)
        #expect(elapsed < 3.6)
        #expect(connector.priceCallIsActive)
        #expect(priceSeriesAtReturn.isEmpty)

        #expect(connector.waitForPriceCallToFinish(timeout: 1.5))
        Thread.sleep(forTimeInterval: 0.1)
        #expect(!connector.priceCallIsActive)
        #expect(progress.count == progressCountAtReturn)
        #expect(try store.loadPriorSnapshot()?.priceSeries == priceSeriesAtReturn)
    }

    private func refresh(
        connector: PriceCancellationConnector,
        store: SnapshotStore,
        progress: @escaping @Sendable (BackgroundDetailRefreshProgress) -> Void = { _ in }
    ) throws -> PDTBackgroundDetailRefreshResult {
        try PDTBackgroundDetailRefresh(
            connector: connector,
            snapshotStore: store,
            asOf: "2026-03-29",
            options: PDTBackgroundDetailRefreshOptions(
                priceHistoryConcurrencyLimit: 1,
                priceHistoryTimeoutSeconds: 0.05,
                retryBackoffSeconds: 0
            )
        ).refresh(progress: progress)
    }
}

private final class CancellingRetryConnector: PDTMCPConnector, @unchecked Sendable {
    private let cancellation: PDTCancellation
    private let lock = NSLock()
    private var calls = 0

    init(cancellation: PDTCancellation) {
        self.cancellation = cancellation
    }

    var callCount: Int {
        lock.withLock {
            calls
        }
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1)
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        lock.withLock {
            calls += 1
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [cancellation] in
            cancellation.cancel()
        }
        Thread.sleep(forTimeInterval: 0.15)
        throw PDTMCPConnectorError.transientFailure("scripted retryable failure")
    }
}

private final class PriceCancellationConnector: PDTMCPConnector, @unchecked Sendable {
    enum Mode {
        case cooperative(cleanupDelay: TimeInterval)
        case stubborn(delay: TimeInterval)
        case never
    }

    private let mode: Mode
    private let includesPerformance: Bool
    private let cancelOnPerformance: PDTCancellation?
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private let neverWorkerRelease = DispatchSemaphore(value: 0)
    private var priceCalls = 0
    private var performanceCalls = 0
    private var activePriceCall = false

    init(
        mode: Mode,
        includesPerformance: Bool = false,
        cancelOnPerformance: PDTCancellation? = nil
    ) {
        self.mode = mode
        self.includesPerformance = includesPerformance
        self.cancelOnPerformance = cancelOnPerformance
    }

    var priceCallCount: Int {
        lock.withLock {
            priceCalls
        }
    }

    var priceCallIsActive: Bool {
        lock.withLock {
            activePriceCall
        }
    }

    var performanceCallCount: Int {
        lock.withLock {
            performanceCalls
        }
    }

    func waitForPriceCallToFinish(timeout: TimeInterval) -> Bool {
        finished.wait(timeout: .now() + timeout) == .success
    }

    func releaseNeverFinishingWorker() {
        neverWorkerRelease.signal()
    }

    func availableReadTools() throws -> Set<String> {
        Set(PDTReadTools.requiredV1 + (includesPerformance ? PDTReadTools.performance : []))
    }

    func callReadTool(_ name: String, arguments: [String: String]) throws -> Data {
        response(for: name)
    }

    func callReadToolReportingAttempts(
        _ name: String,
        arguments: [String: String],
        retryDeadline: Date?,
        cancellation: PDTCancellation?
    ) throws -> PDTMCPConnectorCallResult {
        guard name == "pdt-list-symbol-prices" else {
            if PDTReadTools.performance.contains(name) {
                lock.withLock {
                    performanceCalls += 1
                }
                if let cancelOnPerformance {
                    cancelOnPerformance.cancel()
                    throw PDTMCPConnectorError.timeout("scripted parent cancellation")
                }
            }
            return PDTMCPConnectorCallResult(data: response(for: name), attemptCount: 1)
        }
        lock.withLock {
            priceCalls += 1
            activePriceCall = true
        }
        defer {
            lock.withLock {
                activePriceCall = false
            }
            finished.signal()
        }

        switch mode {
        case .cooperative(let cleanupDelay):
            while cancellation?.isCancelled != true {
                Thread.sleep(forTimeInterval: 0.005)
            }
            Thread.sleep(forTimeInterval: cleanupDelay)
        case .stubborn(let delay):
            Thread.sleep(forTimeInterval: delay)
        case .never:
            neverWorkerRelease.wait()
        }
        return PDTMCPConnectorCallResult(data: response(for: name), attemptCount: 1)
    }

    private func response(for name: String) -> Data {
        let json: String
        switch name {
        case "pdt-get-portfolio-holdings":
            json = """
            {
              "holdings": [{
                "symbolName": "Cancellation Fixture",
                "symbolQuoteId": 9101,
                "currentPriceDate": "2026-03-29T22:00:00+00:00",
                "currentPriceLocal": { "value": "20.00", "currency": "EUR" },
                "currentWorthLocal": { "value": "250.00", "currency": "EUR" },
                "portfolioWeight": 1.0,
                "closedAt": null
              }]
            }
            """
        case "pdt-get-portfolio-distributions":
            json = #"{"sectors":[],"assetTypes":[]}"#
        case "pdt-list-x-ray-holdings":
            json = #"{"items":[],"hasMore":false}"#
        case "pdt-list-calendar-events", "pdt-list-dividends":
            json = #"{"data":[],"meta":{"last_page":1}}"#
        case "pdt-list-symbol-prices":
            json = """
            {
              "data": [{
                "date": "2026-03-29",
                "closeAdjusted": "20.00",
                "symbolQuoteId": 9101
              }]
            }
            """
        case "pdt-get-portfolio-performance":
            json = #"{"oldestPortfolioDate":"2024-03-29","latestPortfolioDate":"2026-03-29"}"#
        case "pdt-get-portfolio-gains":
            json = #"{"totalGainsPercentage":0.21}"#
        default:
            json = #"{}"#
        }
        return Data(json.utf8)
    }
}

private final class CancellationProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BackgroundDetailRefreshProgress] = []

    var count: Int {
        lock.withLock {
            values.count
        }
    }

    func record(_ progress: BackgroundDetailRefreshProgress) {
        lock.withLock {
            values.append(progress)
        }
    }
}
