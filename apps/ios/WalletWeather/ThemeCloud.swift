import Foundation
import WalletWeatherKit

/// Where custom themes are kept (ios-settings phase 4, #297; decided
/// 2026-11-23): the iCloud key-value store, so they reach the person's
/// other iPhones, mirrored in the app's preferences so with iCloud off they
/// stay on this iPhone. Names and colours only (`CustomThemeStore`), never
/// a number. A theme made or changed on another iPhone arrives through the
/// store's external-change notification. One lives as long as the app's
/// `AppSettings`, so its observer is never removed.
@MainActor
final class ThemeCloud {
    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    /// Called with the whole list when iCloud brings a change.
    var arrived: (@MainActor ([CustomTheme]) -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                guard let self, keys.contains(CustomThemeStore.key) else { return }
                self.arrived?(self.incoming(replacing: reason == NSUbiquitousKeyValueStoreServerChange))
            }
        }
        cloud.synchronize()
    }

    /// The themes at launch: iCloud's copy with any of this iPhone's it
    /// doesn't have, or this iPhone's alone when iCloud has none.
    func load() -> [CustomTheme] {
        guard cloud.data(forKey: CustomThemeStore.key) != nil else { return local }
        return incoming(replacing: false)
    }

    /// Saves the whole list in both places.
    func save(_ themes: [CustomTheme]) {
        let data = CustomThemeStore.encode(themes)
        defaults.set(data, forKey: CustomThemeStore.key)
        cloud.set(data, forKey: CustomThemeStore.key)
    }

    private var local: [CustomTheme] { CustomThemeStore.decode(defaults.data(forKey: CustomThemeStore.key)) }

    /// iCloud's copy merged with this iPhone's (`CustomThemeStore.incoming`),
    /// kept in the mirror, and written back when the merge added to it.
    private func incoming(replacing: Bool) -> [CustomTheme] {
        let fromCloud = CustomThemeStore.decode(cloud.data(forKey: CustomThemeStore.key))
        let themes = CustomThemeStore.incoming(cloud: fromCloud, local: local, replacing: replacing)
        defaults.set(CustomThemeStore.encode(themes), forKey: CustomThemeStore.key)
        if themes != fromCloud { cloud.set(CustomThemeStore.encode(themes), forKey: CustomThemeStore.key) }
        return themes
    }
}
