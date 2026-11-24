import CoreSpotlight
import UniformTypeIdentifiers
import WalletWeatherKit

/// Bills and accounts in the phone's search (Plans/outside-the-app.md, phase
/// 4, #331): Core Spotlight, driven by the summary store (WalletWeatherKit's
/// `SearchIndexing`). Names only. The index is its own, named and protected
/// like the summary: nothing in it is searchable while the phone is locked.
///
/// Its name, `SearchEntry.id` (the item identifiers) and the connection ids
/// (the domain identifiers) are stable: never rename them.
final class PhoneSearchIndex: SearchIndexing {
    static let indexName = "net.iptater.walletweather.search"

    private enum Change {
        case replace(UUID, [SearchEntry])
        case remove(UUID)
        case removeAll
    }

    private let changes: AsyncStream<Change>.Continuation

    nonisolated init() {
        let (stream, continuation) = AsyncStream<Change>.makeStream()
        changes = continuation
        let index = CSSearchableIndex(name: Self.indexName, protectionClass: .complete)
        // One change at a time, in order: a connection's entries are removed
        // before its new ones go in.
        Task.detached(priority: .utility) {
            for await change in stream {
                switch change {
                case let .replace(connection, entries):
                    try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain(connection)])
                    if !entries.isEmpty { try? await index.indexSearchableItems(entries.map(Self.item)) }
                case let .remove(connection):
                    try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain(connection)])
                case .removeAll:
                    try? await index.deleteAllSearchableItems()
                }
            }
        }
    }

    nonisolated func replace(connection: UUID, with entries: [SearchEntry]) { changes.yield(.replace(connection, entries)) }
    nonisolated func remove(connection: UUID) { changes.yield(.remove(connection)) }
    nonisolated func removeAll() { changes.yield(.removeAll) }

    private nonisolated static func domain(_ connection: UUID) -> String { connection.uuidString.lowercased() }

    private nonisolated static func item(_ entry: SearchEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.contentDescription = entry.detail
        attributes.keywords = entry.keywords
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: domain(entry.connection),
                                attributeSet: attributes)
    }

    /// The page a search result opens: a bill on its connection's Bills &
    /// income, an account in its connection's Forecast.
    static func opens(_ activity: NSUserActivity) -> WidgetOpen? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let link = SearchLink(id: id) else { return nil }
        switch link {
        case let .bill(connection, _): return WidgetOpen(page: .bills, connection: connection, account: nil)
        case let .account(connection, account): return WidgetOpen(page: .forecast, connection: connection, account: account)
        }
    }
}
