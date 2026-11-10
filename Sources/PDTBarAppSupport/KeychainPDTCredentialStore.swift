import Foundation
import PDTBarCore
import Security

/// The production PDT credential store (ADR-0002): one generic-password item
/// scoped to PDTBar, readable after first unlock, never synced or migrated to
/// another Mac. Tests and smokes never construct it.
public struct KeychainPDTCredentialStore: PDTCredentialStore {
    public static let service = "com.bramvr.pdtbar.pdt-connection"
    private static let account = "pdt"

    public init() {}

    public func load() throws -> PDTConnectionState {
        var query = Self.itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
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
            let status = SecItemDelete(Self.itemQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PDTCredentialStoreError.keychain(status: status)
            }
            return
        }
        let data = try state.storedData()
        let update = SecItemUpdate(Self.itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = Self.itemQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
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
        ]
    }
}
