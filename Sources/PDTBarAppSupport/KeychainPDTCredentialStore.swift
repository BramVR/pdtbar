import Foundation
import PDTBarCore
import Security

/// The production PDT credential store (ADR-0002): one generic-password item
/// scoped to PDTBar, readable after first unlock, never synced or migrated to
/// another Mac. The Keychain has no cross-process mutex, so the store-wide
/// lock is `pdt-connection.lock` in the given PDTBar-owned directory. Tests
/// and smokes never construct it.
public struct KeychainPDTCredentialStore: PDTCredentialStore {
    /// The `SecItem` calls the store makes, injectable so tests check the
    /// queries without touching the real Keychain.
    public struct SecItemAPI: Sendable {
        public var copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        public var add: @Sendable (CFDictionary) -> OSStatus
        public var update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
        public var delete: @Sendable (CFDictionary) -> OSStatus

        public init(
            copyMatching: @escaping @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus,
            add: @escaping @Sendable (CFDictionary) -> OSStatus,
            update: @escaping @Sendable (CFDictionary, CFDictionary) -> OSStatus,
            delete: @escaping @Sendable (CFDictionary) -> OSStatus
        ) {
            self.copyMatching = copyMatching
            self.add = add
            self.update = update
            self.delete = delete
        }

        public static let system = SecItemAPI(
            copyMatching: { SecItemCopyMatching($0, $1) },
            add: { SecItemAdd($0, nil) },
            update: { SecItemUpdate($0, $1) },
            delete: { SecItemDelete($0) }
        )
    }

    public static let service = "com.bramvr.pdtbar.pdt-connection"
    private static let account = "pdt"
    private let lock: PDTCredentialFileLock
    private let secItem: SecItemAPI

    public init(lockDirectory: URL, secItem: SecItemAPI = .system) {
        lock = PDTCredentialFileLock(url: lockDirectory.appending(path: "pdt-connection.lock"))
        self.secItem = secItem
    }

    public func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try lock.hold(body)
    }

    public func load() throws -> PDTConnectionState {
        var query = Self.itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = secItem.copyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw PDTCredentialStoreError.unreadable
            }
            return try PDTConnectionState(storedData: data)
        case errSecItemNotFound:
            return .disconnected
        default:
            throw PDTCredentialStoreError.keychain(status: status)
        }
    }

    public func save(_ state: PDTConnectionState) throws {
        guard state != .disconnected else {
            let status = secItem.delete(Self.itemQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PDTCredentialStoreError.keychain(status: status)
            }
            return
        }
        let data = try state.storedData()
        let update = secItem.update(Self.itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = Self.itemQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = secItem.add(item as CFDictionary)
            guard status == errSecSuccess else {
                throw PDTCredentialStoreError.keychain(status: status)
            }
        default:
            throw PDTCredentialStoreError.keychain(status: update)
        }
    }

    private static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            // Without the data protection keychain, macOS stores the item in the
            // legacy login keychain and ignores the ThisDeviceOnly accessibility class.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
