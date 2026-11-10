import Foundation

/// Holds the one PDT connection. Saving `.disconnected` deletes the item.
/// Production uses the Keychain store in PDTBarAppSupport; tests and smokes
/// use `InMemoryPDTCredentialStore`, and dev proof uses `FilePDTCredentialStore`.
public protocol PDTCredentialStore: Sendable {
    func load() throws -> PDTConnectionState
    func save(_ state: PDTConnectionState) throws
}

public enum PDTCredentialStoreError: Error, Equatable, Sendable {
    case unreadable
    case writeFailed(code: Int32)
    case keychain(status: Int32)
}

public final class InMemoryPDTCredentialStore: PDTCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PDTConnectionState

    public init(_ state: PDTConnectionState = .disconnected) {
        self.state = state
    }

    public func load() throws -> PDTConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func save(_ state: PDTConnectionState) throws {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
    }
}

/// Dev-only store at an explicit path, written with mode 0600 so live proof
/// never touches the Keychain (a re-signed dev build would prompt).
public struct FilePDTCredentialStore: PDTCredentialStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> PDTConnectionState {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .disconnected
        }
        return try PDTConnectionState(storedData: data)
    }

    public func save(_ state: PDTConnectionState) throws {
        guard state != .disconnected else {
            if unlink(url.path) != 0, errno != ENOENT {
                throw PDTCredentialStoreError.writeFailed(code: errno)
            }
            return
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        let data = try state.storedData()
        // Created 0600 from the first byte, then renamed over the old file.
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            throw PDTCredentialStoreError.writeFailed(code: errno)
        }
        let complete = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) } == data.count
        close(descriptor)
        guard complete, rename(temporary.path, url.path) == 0 else {
            let code = errno
            unlink(temporary.path)
            throw PDTCredentialStoreError.writeFailed(code: code)
        }
    }
}

public extension PDTConnectionState {
    /// The serialized form a store writes. It holds secrets; only stores see it.
    func storedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    init(storedData: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            self = try decoder.decode(PDTConnectionState.self, from: storedData)
        } catch {
            throw PDTCredentialStoreError.unreadable
        }
    }
}
