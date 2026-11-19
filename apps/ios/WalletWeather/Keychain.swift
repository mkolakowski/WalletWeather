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

/// The backup passphrase (Plans/standalone.md, phase 5, #236; decided
/// 2026-11-18, open question 4): chosen once, the first time a backup is
/// exported, and kept in iCloud Keychain, so the person's other devices
/// (and a new phone) open their backups by themselves. Unlike the sign-in it
/// syncs, and it's readable whenever the phone is unlocked. Nobody can
/// recover it: the app says so when it's chosen.
enum BackupPassphrase {
    private static let service = "net.iptater.walletweather.backup"
    private static let account = "passphrase"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: true]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ passphrase: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData as String] = Data(passphrase.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        q[kSecAttrLabel as String] = "WalletWeather backup passphrase"
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
