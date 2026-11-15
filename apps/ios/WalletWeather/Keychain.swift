import Foundation
import Security
import WalletWeatherKit

/// The sign-in (server address, token, Cloudflare sign-in) in the Keychain:
/// on this device only, readable only while it's unlocked, never synced to
/// iCloud and never moved to another phone by a backup. Besides it the app
/// keeps its settings and, only with Last-known numbers, the pages last
/// loaded (`KeptResponses`, phase 8). Signing out deletes all of it.
enum Keychain {
    private static let service = "net.iptater.walletweather"
    private static let account = "connection"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    static func loadConnection() -> Connection? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Connection.self, from: data)
    }

    static func saveConnection(_ connection: Connection) {
        guard let data = try? JSONEncoder().encode(connection) else { return }
        deleteConnection()
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func deleteConnection() {
        SecItemDelete(query as CFDictionary)
    }
}
