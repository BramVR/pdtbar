import Foundation

public final class PDTCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let parent: PDTCancellation?
    private var cancelled = false

    public init() {
        parent = nil
    }

    init(parent: PDTCancellation) {
        self.parent = parent
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        let locallyCancelled = cancelled
        lock.unlock()
        return locallyCancelled || parent?.isCancelled == true
    }
}
