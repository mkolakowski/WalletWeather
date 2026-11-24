import AppIntents
import WalletWeatherKit
import WidgetKit

// What a widget is set to (#318): a connection, the one in front when it's
// added, changed by editing the widget; and for Balance, an account. Both are
// picked from the summaries the app wrote, which can only be read while the
// phone is unlocked, as editing a widget is.

/// A saved connection that has a summary. Its id is the summary's.
struct ConnectionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Connection"
    static let defaultQuery = ConnectionQuery()

    let id: UUID
    let name: String

    init(_ summary: ConnectionSummary) {
        id = summary.id
        name = summary.name
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ConnectionQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ConnectionEntity] {
        let all = SummaryStore.shared?.all() ?? []
        return identifiers.compactMap { id in all.first { $0.id == id }.map(ConnectionEntity.init) }
    }

    func suggestedEntities() async throws -> [ConnectionEntity] {
        (SummaryStore.shared?.all() ?? []).map(ConnectionEntity.init)
    }

    /// A new widget starts on the connection in front.
    func defaultResult() async -> ConnectionEntity? {
        let all = SummaryStore.shared?.all() ?? []
        let front = OutsideSettings.shared.front
        return (all.first { $0.id == front } ?? all.first).map(ConnectionEntity.init)
    }
}

/// An account in a connection's summary: `<connection id>/<account id>`.
struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    let id: String
    let name: String

    init(connection: UUID, account: ConnectionSummary.Account) {
        id = "\(connection.uuidString.lowercased())/\(account.id)"
        name = account.name
    }

    var accountID: Int? { id.split(separator: "/").last.flatMap { Int($0) } }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AccountQuery: EntityQuery {
    /// The accounts offered are the chosen connection's.
    @IntentParameterDependency<BalanceConfiguration>(\.$connection) var configuration

    private func accounts(of summary: ConnectionSummary) -> [AccountEntity] {
        summary.accounts.map { AccountEntity(connection: summary.id, account: $0) }
    }

    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        let all = (SummaryStore.shared?.all() ?? []).flatMap(accounts(of:))
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        let chosen: UUID?
        if let picked = configuration?.connection.id { chosen = picked } else { chosen = await ConnectionQuery().defaultResult()?.id }
        guard let chosen, case let .found(summary)? = SummaryStore.shared?.read(chosen) else { return [] }
        return accounts(of: summary)
    }

    func defaultResult() async -> AccountEntity? { try? await suggestedEntities().first }
}

/// Balance: a connection and one of its accounts.
struct BalanceConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Balance"
    static let description = IntentDescription("One account's balance and the month's low.")

    @Parameter(title: "Connection") var connection: ConnectionEntity?
    @Parameter(title: "Account") var account: AccountEntity?

    init() {}
}

/// Next bills and To confirm: a connection.
struct ConnectionConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Connection"
    static let description = IntentDescription("Which connection the widget shows.")

    @Parameter(title: "Connection") var connection: ConnectionEntity?

    init() {}
}
