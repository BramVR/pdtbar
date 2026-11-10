import Foundation

/// Holds the one PDT connection. Saving `.disconnected` deletes the item.
/// Production uses the Keychain store in PDTBarAppSupport; tests and smokes
/// use `InMemoryPDTCredentialStore`, and dev proof uses `FilePDTCredentialStore`.
///
/// `withExclusiveAccess` is the store-wide mutex every `PDTConnection` holds
/// from load through the token endpoint to save, across processes where the
/// store is shared. PDT rotates the refresh token on every refresh, so two
/// refreshes of one stored pair leave the loser with a dead token. The lock
/// is not reentrant.
public protocol PDTCredentialStore: Sendable {
    func load() throws -> PDTConnectionState
    func save(_ state: PDTConnectionState) throws
    func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value
}

public enum PDTCredentialStoreError: Error, Equatable, Sendable {
    case unreadable
    case writeFailed(code: Int32)
    case lockFailed(code: Int32)
    case keychain(status: Int32)
}

public final class InMemoryPDTCredentialStore: PDTCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private let exclusive = NSLock()
    private var state: PDTConnectionState

    public init(_ state: PDTConnectionState = .disconnected) {
        self.state = state
    }

    public func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        exclusive.lock()
        defer { exclusive.unlock() }
        return try body()
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
/// never touches the Keychain (a re-signed dev build would prompt). The
/// sibling `<name>.lock` file carries the `flock`.
public struct FilePDTCredentialStore: PDTCredentialStore {
    /// POSIX `write(2)`: may write fewer bytes than asked, or fail with `EINTR`.
    public typealias Write = @Sendable (_ descriptor: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int

    public let url: URL
    private let writeBytes: Write

    public init(url: URL, write: @escaping Write = { Darwin.write($0, $1, $2) }) {
        self.url = url
        self.writeBytes = write
    }

    public func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try PDTCredentialFileLock(url: url.appendingPathExtension("lock")).hold(body)
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
            if unlink(url.path) != 0 {
                guard errno == ENOENT else {
                    throw PDTCredentialStoreError.writeFailed(code: errno)
                }
                return
            }
            if let failure = Self.syncDirectory(url.deletingLastPathComponent()) {
                throw PDTCredentialStoreError.writeFailed(code: failure)
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
        var failure = writeAll(data, to: descriptor)
        // fsync before rename so a crash can't leave an empty file in place of the credential.
        if failure == nil, fsync(descriptor) != 0 {
            failure = errno
        }
        close(descriptor)
        if failure == nil, rename(temporary.path, url.path) != 0 {
            failure = errno
        }
        if let failure {
            unlink(temporary.path)
            throw PDTCredentialStoreError.writeFailed(code: failure)
        }
        // A crash before the directory entry is durable would bring back the
        // previous, already revoked refresh token.
        if let failure = Self.syncDirectory(directory) {
            throw PDTCredentialStoreError.writeFailed(code: failure)
        }
    }

    private static func syncDirectory(_ directory: URL) -> Int32? {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            return errno
        }
        defer { close(descriptor) }
        return fsync(descriptor) == 0 ? nil : errno
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Int32? {
        data.withUnsafeBytes { buffer -> Int32? in
            var offset = 0
            while offset < buffer.count {
                let written = writeBytes(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return written < 0 ? errno : EIO
                }
            }
            return nil
        }
    }
}

/// An advisory `flock` on a mode-0600 file. `flock` binds to the open file
/// description, so every `hold` contends, across threads and processes.
public struct PDTCredentialFileLock: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func hold<Value>(_ body: () throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw PDTCredentialStoreError.lockFailed(code: errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw PDTCredentialStoreError.lockFailed(code: errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
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
