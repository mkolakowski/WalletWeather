import Foundation
import WalletWeatherKit

/// Quick add with remembered names (#325): the names Add transaction offers
/// come from the last months' lines the connection in front already
/// answers (`GET /api/transactions/search`, which the household on this
/// iPhone and the demo answer too). They're read once and kept in memory
/// for a few minutes for that connection; nothing is stored.
extension AppModel {
    /// How long the names are reused before they're read again.
    static let nameHistoryLife: TimeInterval = 300

    /// Names to offer, from memory when read lately, else from the
    /// connection. Empty when they can't be read: Add transaction works the
    /// same without.
    func nameSuggestions() async -> [NameSuggestion] {
        guard let connection, let client else { return [] }
        if let kept = nameHistory, kept.connection == connection, Date().timeIntervalSince(kept.at) < Self.nameHistoryLife {
            return kept.names
        }
        guard let uses = try? await client.nameHistory() else { return [] }
        let names = NameSuggestions.index(uses)
        nameHistory = (connection, Date(), names)
        return names
    }

    /// A line was added: read the names again next time.
    func forgetNameHistory() { nameHistory = nil }
}
