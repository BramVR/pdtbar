import Foundation
import PDTBarCore
import Security

/// The production PDT credential store (ADR-0002). The Keychain has no
/// cross-process mutex, so the store-wide lock is `pdt-connection.lock` in
/// `lockDirectory`.
public struct KeychainPDTCredentialStore: PDTCredentialStore {
    public struct SecItemAPI: Sendable {
        public var copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        public var add: @Sendable (CFDictionary) -> OSStatus
        public var update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
        public var delete: @Sendable (CFDictionary) -> OSStatus
        /// The code signature carries `keychain-access-groups`. Without it
        /// the data protection keychain refuses every write with
        /// `errSecMissingEntitlement`.
        public var isEntitled: Bool

        public init(
            copyMatching: @escaping @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus,
            add: @escaping @Sendable (CFDictionary) -> OSStatus,
            update: @escaping @Sendable (CFDictionary, CFDictionary) -> OSStatus,
            delete: @escaping @Sendable (CFDictionary) -> OSStatus,
            isEntitled: Bool
        ) {
            self.copyMatching = copyMatching
            self.add = add
            self.update = update
            self.delete = delete
            self.isEntitled = isEntitled
        }

        public static let system = SecItemAPI(
            copyMatching: { SecItemCopyMatching($0, $1) },
            add: { SecItemAdd($0, nil) },
            update: { SecItemUpdate($0, $1) },
            delete: { SecItemDelete($0) },
            isEntitled: signatureHasKeychainAccessGroups()
        )

        /// No Keychain call, no prompt. An ad-hoc build cannot fake the
        /// entitlement: macOS kills one that claims it without a provisioning
        /// profile.
        private static func signatureHasKeychainAccessGroups() -> Bool {
            guard let task = SecTaskCreateFromSelf(nil) else {
                return true
            }
            return SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) != nil
        }
    }

    public static let service = "com.bramvr.pdtbar.pdt-connection"
    private static let account = "pdt"
    private let lock: PDTCredentialFileLock
    private let secItem: SecItemAPI

    public init(lockDirectory: URL, secItem: SecItemAPI = .system) {
        lock = PDTCredentialFileLock(url: lockDirectory.appending(path: "pdt-connection.lock"))
        self.secItem = secItem
    }

    public var persistence: PDTCredentialPersistence {
        secItem.isEntitled ? .saved : .thisSessionOnly(.missingEntitlement)
    }

    public func withExclusiveAccess<Value>(_ body: () throws -> Value) throws -> Value {
        try lock.hold(body)
    }

    public func load() throws -> PDTStoredConnection {
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
            return try PDTStoredConnection(storedData: data)
        case errSecItemNotFound:
            return .empty
        default:
            throw Self.failure(status)
        }
    }

    public func save(_ connection: PDTStoredConnection) throws {
        guard connection != .empty else {
            let status = secItem.delete(Self.itemQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Self.failure(status)
            }
            return
        }
        let data = try connection.storedData()
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
                throw Self.failure(status)
            }
        default:
            throw Self.failure(update)
        }
    }

    private static func failure(_ status: OSStatus) -> PDTCredentialStoreError {
        status == errSecMissingEntitlement ? .missingKeychainEntitlement : .keychain(status: status)
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
