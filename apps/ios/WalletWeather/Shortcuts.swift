import AppIntents
import LocalAuthentication
import WalletWeatherKit
import WidgetKit

// Open To confirm and What's my balance (Plans/outside-the-app.md, phase 3,
// #320), Add a transaction and Mark a bill paid (phase 5, #332), offered as App Shortcuts so they also work from Siri, Spotlight and
// the Action button. What each does is decided in WalletWeatherKit
// (ShortcutAnswers.swift, ShortcutActions.swift), where the tests check the privacy rules. Only
// Mark a bill paid reaches a server (the connection in front's own, through
// the same call as a swipe on Forecast); the others read the summary the app
// wrote for the widgets.
//
// The intents' type names are their identifiers in people's shortcuts and on
// the Action button: never rename them.
//
// Their titles, descriptions and phrases must not name Apple's products
// ("iPhone", "iPad", "Siri", "Apple"): App Store Connect turns the build away
// (ITMS-90626, #337), and Scripts/testflight.sh checks before uploading.

/// Opens the app on the lines waiting to confirm, on the connection in front,
/// as the To confirm widget does. The app's own lock still asks first.
nonisolated struct OpenToConfirmIntent: AppIntent {
    static let title: LocalizedStringResource = "Open To confirm"
    static let description = IntentDescription("Opens WalletWeather on the lines waiting to confirm, on the connection in front.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        let front = OutsideSettings.shared.front
        let read = front.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        let target = ToConfirmTarget.decide(front: front, read: read)
        ShortcutOpen.send(WidgetOpen(page: .toConfirm, connection: target.connection, account: target.account))
        return .result()
    }
}

/// Tells each account's balance on the connection in front, naming it and
/// when its numbers are from. Only with the phone unlocked (Siri asks to
/// unlock first), and after Face ID while the app's lock is on.
nonisolated struct BalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "What's my balance"
    static let description = IntentDescription(
        "Tells the balance of each account on the connection in front, and when the numbers are from. Needs the phone unlocked, and Face ID while WalletWeather's lock is on.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = OutsideSettings.shared
        let front = settings.front
        let read = front.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        var answer = BalanceAnswer.decide(front: front, read: read, lockOn: settings.lockOn, unlocked: false)
        if answer == .appLocked, await ShortcutUnlock.ask("Hear your balance") {
            answer = BalanceAnswer.decide(front: front, read: read, lockOn: true, unlocked: true)
        }
        return .result(dialog: IntentDialog(stringLiteral: answer.text()))
    }
}

/// Opens the app's Add transaction sheet on the connection in front, filled
/// in from the Shortcut, for a last look before Save (decided 2026-11-23).
/// The app's own lock asks first, as it does whenever the app opens.
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a transaction"
    static let description = IntentDescription(
        "Opens WalletWeather's Add transaction, filled in with the amount, description and date, on the connection in front. Check it and tap Save.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var name: String

    @Parameter(title: "Date", description: "Today when left empty.")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$name)") { \.$date }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let amount = Decimal(string: String(format: "%.2f", self.amount)) ?? 0
        let draft = NewTransactionDraft.fromShortcut(amount: amount, name: name, date: .today(now: date ?? .now))
        // With no saved connection (only the demo), the app opens as it is:
        // there's nowhere to add it.
        ShortcutOpen.send(WidgetOpen(page: .dashboard, connection: OutsideSettings.shared.front, account: nil,
                                     draft: OutsideSettings.shared.front == nil ? nil : draft))
        return .result()
    }
}

/// Marks a bill's next date paid, as planned, without opening the app, on
/// the connection in front, and says what it did (decided 2026-11-23). The
/// phone must be unlocked, and Face ID passed while the app's lock is on.
struct MarkBillPaidIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a bill paid"
    static let description = IntentDescription(
        "Marks a bill's next date paid, as planned, on the connection in front, and says what it did. Needs the phone unlocked, and Face ID while WalletWeather's lock is on.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Bill")
    var bill: BillEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$bill) paid")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = OutsideSettings.shared
        let front = settings.front
        let read = front.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        guard let link = SearchLink(id: bill.id) else { return .result(dialog: "That bill can't be found.") }
        var check = MarkPaidCheck.decide(front: front, read: read, link: link, lockOn: settings.lockOn, unlocked: false)
        if check == .appLocked, await ShortcutUnlock.ask("Mark \(bill.name) paid") {
            check = MarkPaidCheck.decide(front: front, read: read, link: link, lockOn: true, unlocked: true)
        }
        guard case let .ready(found, summary) = check else {
            return .result(dialog: IntentDialog(stringLiteral: check.refusal ?? ""))
        }
        let store = ConnectionStore(secrets: KeychainConnectionSecrets())
        guard let saved = store.load(summary.id) else {
            return .result(dialog: IntentDialog(stringLiteral: MarkPaidCheck.notLoaded.refusal ?? ""))
        }
        let client = APIClient(connection: saved.connection)
        do {
            let paid = try await BillPaying.pay(bill: found.id, account: found.accountId, client: client)
            if paid != nil { await Self.refreshSummary(saved, client: client) }
            return .result(dialog: IntentDialog(stringLiteral: BillPaying.said(paid, bill: found.name, connection: summary.name)))
        } catch {
            let why = await MainActor.run { AppModel.describe(error) }
            return .result(dialog: IntentDialog(stringLiteral: "\(found.name) wasn't marked paid. \(why)"))
        }
    }

    /// The widgets, reminders' expanded view and the phone's search follow
    /// what was just paid; if the numbers can't be loaded, the summary
    /// before stays until the app next loads them.
    private static func refreshSummary(_ saved: SavedConnection, client: APIClient) async {
        guard let summaries = SummaryStore.shared?.searchable(PhoneSearchIndex()),
              let summary = try? await ConnectionSummary.fetch(saved, client: client, readOnly: false) else { return }
        if summaries.write(summary) { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// A bill on the connection in front, for Mark a bill paid: picked from its
/// summary's bills (not income), soonest first. Its id is the bill's entry
/// in the phone's search (`SearchLink`), so it names its connection too.
nonisolated struct BillEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bill"
    static let defaultQuery = BillQuery()

    let id: String
    let name: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ bill: ConnectionSummary.Bill, on summary: ConnectionSummary) {
        id = SearchLink.bill(summary.id, bill.id).id
        name = bill.name
        detail = [bill.accountName, bill.nextDate.map { "next \($0.short)" }].compactMap { $0 }.joined(separator: " · ")
    }
}

nonisolated struct BillQuery: EntityStringQuery {
    /// A bill saved in a Shortcut is found on whichever connection holds it,
    /// so Mark a bill paid can say it isn't on the one in front.
    func entities(for identifiers: [BillEntity.ID]) async throws -> [BillEntity] {
        let all = (SummaryStore.shared?.all() ?? []).flatMap { summary in summary.bills.map { BillEntity($0, on: summary) } }
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BillEntity] { Self.frontBills() }

    func entities(matching string: String) async throws -> [BillEntity] {
        Self.frontBills().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    /// The bills of the connection in front, soonest first; none for the
    /// demo, a server set to Nothing, or a locked phone.
    private static func frontBills() -> [BillEntity] {
        guard let front = OutsideSettings.shared.front, case let .found(summary)? = SummaryStore.shared?.read(front) else {
            return []
        }
        return summary.bills.filter { !$0.isIncome }
            // No next date sorts last ("9999" after any ISO date).
            .sorted { ($0.nextDate?.description ?? "9999", $0.name) < ($1.nextDate?.description ?? "9999", $1.name) }
            .map { BillEntity($0, on: summary) }
    }
}

/// Face ID (or the passcode), as the app's own lock asks.
nonisolated enum ShortcutUnlock {
    static func ask(_ reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// The phrases Siri knows, and the actions Shortcuts and the Action button
/// offer without setting anything up.
nonisolated struct WalletWeatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BalanceIntent(),
                    phrases: ["What's my balance in \(.applicationName)",
                              "What's my \(.applicationName) balance",
                              "Ask \(.applicationName) for my balance"],
                    shortTitle: "What's my balance",
                    systemImageName: "dollarsign.circle")
        AppShortcut(intent: MarkBillPaidIntent(),
                    phrases: ["Mark a bill paid in \(.applicationName)",
                              "Mark \(\.$bill) paid in \(.applicationName)",
                              "Pay a bill in \(.applicationName)"],
                    shortTitle: "Mark a bill paid",
                    systemImageName: "checkmark.circle")
        AppShortcut(intent: AddTransactionIntent(),
                    phrases: ["Add a transaction in \(.applicationName)",
                              "Add to \(.applicationName)"],
                    shortTitle: "Add a transaction",
                    systemImageName: "plus.circle")
        AppShortcut(intent: OpenToConfirmIntent(),
                    phrases: ["Open To confirm in \(.applicationName)",
                              "Show what to confirm in \(.applicationName)"],
                    shortTitle: "Open To confirm",
                    systemImageName: "checklist")
    }
}

/// Hands Open To confirm to the app's windows, as a widget's tap does. When
/// the shortcut launches the app, it can run before the windows are ready:
/// it waits here until they are.
enum ShortcutOpen {
    static var handler: ((WidgetOpen) -> Void)? {
        didSet {
            guard let handler, let waiting else { return }
            self.waiting = nil
            handler(waiting)
        }
    }

    private static var waiting: WidgetOpen?

    static func send(_ open: WidgetOpen) {
        if let handler { handler(open) } else { waiting = open }
    }
}
