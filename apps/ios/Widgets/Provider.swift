import AppIntents
import WalletWeatherKit
import WidgetKit

extension SummaryEntry {
    /// Reads the summary of the connection a widget is set to: the one
    /// chosen, else the one in front.
    static func read(connection entity: ConnectionEntity?, account: AccountEntity? = nil, now: Date = .now) -> SummaryEntry {
        let id = entity?.id ?? OutsideSettings.shared.front
        let read = id.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        let content = WidgetContent.decide(read, name: entity?.name, lockOn: OutsideSettings.shared.lockOn)
        return SummaryEntry(date: now, connection: id, content: content, account: account?.accountID,
                            accountName: account?.name)
    }
}

/// The widgets only read what the app wrote, so a timeline is one entry,
/// read again every quarter of an hour (and whenever the app writes a
/// summary and asks WidgetKit to reload).
private let rereadAfter: TimeInterval = 15 * 60

struct BalanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .sample }

    func snapshot(for configuration: BalanceConfiguration, in context: Context) async -> SummaryEntry {
        let entry = SummaryEntry.read(connection: configuration.connection, account: configuration.account)
        if context.isPreview, case .noConnection = entry.content { return .sample }
        return entry
    }

    func timeline(for configuration: BalanceConfiguration, in context: Context) async -> Timeline<SummaryEntry> {
        let entry = SummaryEntry.read(connection: configuration.connection, account: configuration.account)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(rereadAfter)))
    }
}

struct ConnectionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .sample }

    func snapshot(for configuration: ConnectionConfiguration, in context: Context) async -> SummaryEntry {
        let entry = SummaryEntry.read(connection: configuration.connection)
        if context.isPreview, case .noConnection = entry.content { return .sample }
        return entry
    }

    func timeline(for configuration: ConnectionConfiguration, in context: Context) async -> Timeline<SummaryEntry> {
        let entry = SummaryEntry.read(connection: configuration.connection)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(rereadAfter)))
    }
}
