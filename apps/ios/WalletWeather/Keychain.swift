import Foundation
import Security
import WalletWeatherKit

// The sign-ins (server address, token, Cloudflare sign-in) are in the
// Keychain too, one item per connection: `KeychainConnectionSecrets` and
// `ConnectionStore` in WalletWeatherKit (Plans/connections.md, #299).

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
