import Foundation
import Testing
@testable import WalletWeatherKit

/// Bank sync in the app (bank-sync phase 5, #197): the status row's words
/// for each state, Sync now, and a bill's two match settings.
struct BankSyncTests {
    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
        return try APIClient.decoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// Times as the row writes them, so the words can be checked.
    func when(_ date: Date) -> String { "T\(Int(date.timeIntervalSince1970))" }

    /// A moment between the samples' last sync and next one.
    let now = BankStatus.date("2026-11-17T20:00:00Z")!

    @Test func serverTimesReadWithAndWithoutFractions() {
        #expect(BankStatus.date("2026-11-17T14:06:16.123456Z") != nil)
        #expect(BankStatus.date("2026-11-17T14:06:16Z") == BankStatus.date("2026-11-17T14:06:16.000000Z"))
        #expect(BankStatus.date(nil) == nil)
        #expect(BankStatus.date("yesterday") == nil)
        let date = BankStatus.date("2026-11-17T14:06:16Z")!
        #expect(BankStatus.date(BankStatus.text(date)) == date)
    }

    // MARK: Each state, from samples shaped as the server answers

    @Test func connectedAndSyncedShowsTheLastSyncAndTheNext() throws {
        let status: BankStatus = try sample("bank-status-connected")
        let summary = status.summary(now: now, when: when)
        #expect(summary.tone == .ok)
        #expect(summary.headline == "Synced T\(Int(BankStatus.date(status.lastSyncAt)!.timeIntervalSince1970))")
        #expect(summary.detail == "2 new lines, 1 matched a bill, 14 already here")
        #expect(summary.next?.hasPrefix("Syncs by itself again about T") == true)
        #expect(summary.canSync && summary.waitText == nil)
        #expect(status.syncsLeftToday == 19)
    }

    @Test func neverConnectedSaysConnectingIsDoneInTheWebApp() throws {
        let status: BankStatus = try sample("bank-status-never")
        #expect(status.linkedAccountIds == nil && status.lastSyncAt == nil)
        let summary = status.summary(now: now, when: when)
        #expect(summary.headline == "No bank connected")
        #expect(summary.detail == "Connecting a bank is done in the web app: Settings → Bank sync.")
        #expect(summary.tone == .neutral && !summary.canSync)
    }

    @Test func switchedOffOnTheServerSaysWhoCanSwitchItOn() throws {
        let summary = try (sample("bank-status-off") as BankStatus).summary(now: now, when: when)
        #expect(summary.headline == "Bank sync is off")
        #expect(summary.detail?.contains("admin") == true && !summary.canSync)
        // Connected earlier, then switched off by an admin.
        let off = BankStatus(enabled: false, connected: true, linkedAccountIds: [1])
        #expect(off.summary(now: now, when: when).headline == "Bank sync is switched off")
        #expect(!off.summary(now: now, when: when).canSync)
    }

    @Test func aFailingSyncShowsTheErrorInPlainWords() throws {
        let status: BankStatus = try sample("bank-status-failing")
        let summary = status.summary(now: now, when: when)
        #expect(summary.tone == .warning)
        #expect(summary.headline == "Last sync failed")
        #expect(summary.detail?.hasSuffix("SimpleFIN answered with an error (HTTP 500). Try again in a while.") == true)
        #expect(summary.next?.contains("again about") == true)
        #expect(summary.canSync)   // it can be tried by hand
        #expect(status.failingOverADay == true)
    }

    @Test func theDailyLimitSaysWhenItCanRunAgainAndBlocksSyncNow() throws {
        let status: BankStatus = try sample("bank-status-limit")
        let summary = status.summary(now: now, when: when)
        #expect(!summary.canSync)
        // The web app's words, with minutes worked out from 5,400 seconds.
        #expect(summary.waitText == "Bank sync has asked SimpleFIN 20 times in the last 24 hours, the most it allows without risking your connection. It can run again in 90 minutes.")
        let one = BankStatus(enabled: true, connected: true, linkedAccountIds: [1], syncWaitSeconds: 1)
        #expect(one.summary(now: now, when: when).waitText?.hasSuffix("in 1 minute.") == true)
    }

    @Test func aConnectionSimpleFINRefusesSaysToConnectAgain() throws {
        let summary = try (sample("bank-status-reconnect") as BankStatus).summary(now: now, when: when)
        #expect(summary.tone == .warning)
        #expect(summary.headline == "Needs connecting again")
        #expect(summary.detail?.contains("web app") == true && !summary.canSync)
    }

    @Test func connectedWithNothingMatchedOrNotYetSynced() {
        let nothing = BankStatus(enabled: true, connected: true, linkedAccountIds: [])
        #expect(nothing.summary(now: now, when: when).headline == "Connected, no account matched")
        #expect(!nothing.summary(now: now, when: when).canSync)
        let fresh = BankStatus(enabled: true, connected: true, linkedAccountIds: [1])
        let summary = fresh.summary(now: now, when: when)
        #expect(summary.headline == "Connected" && summary.detail == "Not synced yet." && summary.canSync)
    }

    @Test func aSyncThatIsDueNowSaysSo() {
        let due = BankStatus(enabled: true, connected: true, linkedAccountIds: [1],
                             lastSyncAt: "2026-11-16T10:00:00Z", lastSyncOk: true, lastSyncStatus: "0 new lines",
                             nextSyncAt: "2026-11-17T09:30:00Z")
        #expect(due.summary(now: now, when: when).next == "The next sync by itself is due now.")
    }

    // MARK: Every connection (bank-providers phase 4, #257)

    @Test func eachConnectionIsListedWithItsProviderBankAndState() throws {
        let status: BankStatus = try sample("bank-status-connections")
        let rows = status.connectionRows(now: now, when: when)
        #expect(rows.map(\.id) == [1, 2, 3, 4])
        #expect(rows.map(\.title) == ["Northwind Bank", "Contoso Credit Union", "Plaid Bank", "Teller"])
        #expect(rows.map(\.provider) == ["SimpleFIN", "Teller", "Plaid", "Teller"])
        #expect(status.connections?.map(\.provider) == ["simplefin", "teller", "plaid", "teller"])
        #expect(status.connections?[1].linkedAccountIds == [2])
    }

    @Test func eachConnectionSaysItsOwnStateInPlainWords() throws {
        let rows = try (sample("bank-status-connections") as BankStatus).connectionRows(now: now, when: when)
        // SimpleFIN, synced.
        #expect(rows[0].summary.tone == .ok && rows[0].summary.canSync)
        #expect(rows[0].summary.detail == "2 new lines, 1 matched a bill, 14 already here")
        // Teller, failing and over its day's limit: its words, naming Teller, and no Sync now.
        let teller = rows[1].summary
        #expect(teller.tone == .warning && teller.headline == "Last sync failed")
        #expect(teller.detail?.hasSuffix("Teller answered with an error (HTTP 502). Try again in a while.") == true)
        #expect(teller.waitText == "Bank sync has asked Teller 20 times in the last 24 hours, the most it allows without risking your connection. It can run again in 90 minutes.")
        #expect(!teller.canSync)
        // Plaid, refused by the bank: the provider is named, not SimpleFIN.
        let plaid = rows[2].summary
        #expect(plaid.tone == .warning && plaid.headline == "Needs connecting again")
        #expect(plaid.detail?.hasPrefix("Plaid no longer accepts this connection.") == true && !plaid.canSync)
        // Teller, connected with nothing matched yet.
        #expect(rows[3].summary.headline == "Connected, no account matched" && !rows[3].summary.canSync)
    }

    @Test func aConnectionsSummaryUsesItsOwnLimitAndProviderNotTheTotals() {
        let teller = BankConnection(id: 7, provider: "teller", providerName: "Teller", name: "Contoso", linkedAccountIds: [1],
                                    lastSyncAt: "2026-11-17T14:00:00Z", lastSyncOk: true, lastSyncStatus: "0 new lines",
                                    syncsLeftToday: 0, syncWaitSeconds: 60)
        let summary = teller.summary(now: now, when: when)
        #expect(summary.waitText?.hasPrefix("Bank sync has asked Teller 20 times") == true)
        #expect(summary.waitText?.hasSuffix("in 1 minute.") == true && !summary.canSync)
        let never = BankConnection(id: 8, provider: "plaid", providerName: "Plaid", name: "Plaid", linkedAccountIds: [1])
        #expect(never.summary(now: now, when: when).headline == "Connected")
        #expect(never.summary(now: now, when: when).detail == "Not synced yet.")
    }

    @Test func aServerWithoutTheListKeepsTheOneRowItHad() throws {
        // Servers 1.70.0 to 1.85.0 send no `connections`: the top-level fields are the one.
        let status: BankStatus = try sample("bank-status-connected")
        #expect(status.connections == nil)
        #expect(status.connectionRows(now: now, when: when).isEmpty)
        #expect(status.summary(now: now, when: when).headline.hasPrefix("Synced"))
    }

    @Test func nothingConnectedOrSwitchedOffListsNoConnections() throws {
        #expect(try (sample("bank-status-never") as BankStatus).connectionRows(now: now, when: when).isEmpty)
        #expect(try (sample("bank-status-off") as BankStatus).connectionRows(now: now, when: when).isEmpty)
        // Connections the server still lists after an admin switches it off aren't offered a Sync now.
        var off = try sample("bank-status-connections") as BankStatus
        off = BankStatus(enabled: false, connected: true, linkedAccountIds: off.linkedAccountIds, connections: off.connections)
        #expect(off.connectionRows(now: now, when: when).isEmpty)
        #expect(off.summary(now: now, when: when).headline == "Bank sync is switched off")
    }

    @Test func theTopLevelFieldsAreStillReadForAnOlderAppsSake() throws {
        let status: BankStatus = try sample("bank-status-connections")
        #expect(status.linkedAccountIds == [1, 2, 3] && status.syncsLeftToday == 12)
        #expect(status.needsReconnect == true && status.failingOverADay == true)
    }

    // MARK: Connect a bank from the app (bank-providers phase 5, #258)

    @Test func theConnectPageAnswerReadsAsANewConnectionOrWhyNot() throws {
        let done = try #require(AppLink(URL(string: "walletweather://bank-connected?connection=7")!))
        #expect(done == .bankConnected(connection: 7, state: nil))
        #expect(done.state == nil)
        #expect(AppLink(URL(string: "walletweather://bank-connected?state=exited")!) == .bankConnected(connection: nil, state: "exited"))
        // Nothing usable, or not a number: not an answer the app knows.
        #expect(AppLink(URL(string: "walletweather://bank-connected")!) == nil)
        #expect(AppLink(URL(string: "walletweather://bank-connected?connection=abc")!) == nil)
        #expect(AppLink(URL(string: "walletweather://bank-connected?connection=-3")!) == nil)
    }

    @Test func theSheetOpensTheServersConnectPage() throws {
        let address = try ServerAddress.parse("https://ww.example.com")
        #expect(BankConnect.url(server: address).absoluteString == "https://ww.example.com/app-connect-bank")
    }

    @Test func connectIsOfferedWhenSyncIsOnTheServerHasThePageAndTheTokenCanWrite() throws {
        let on = BankStatus(enabled: true, connected: false)
        #expect(BankConnect.offered(on, serverVersion: "1.89.0", readOnly: false))
        #expect(BankConnect.offered(on, serverVersion: "1.90.2", readOnly: false))
        #expect(!BankConnect.offered(on, serverVersion: "1.88.0", readOnly: false))   // no page yet
        #expect(!BankConnect.offered(on, serverVersion: nil, readOnly: false))
        #expect(!BankConnect.offered(on, serverVersion: "1.89.0", readOnly: true))
        #expect(!BankConnect.offered(BankStatus(enabled: false, connected: false), serverVersion: "1.89.0", readOnly: false))
        // Alongside connections already there, too.
        let status: BankStatus = try sample("bank-status-connections")
        #expect(BankConnect.offered(status, serverVersion: "1.89.0", readOnly: false))
    }

    // MARK: Your own Teller and Plaid keys (own-bank-keys phase 3, #278)

    @Test func ownKeysReadAsTheServerWritesThemWithTheEnvironmentOnly() throws {
        let status: BankStatus = try sample("bank-status-own-keys")
        #expect(status.providersTicked == ["simplefin", "teller", "plaid"])
        #expect(status.ownKeys == OwnBankKeys(teller: .init(environment: "development"), plaid: nil))
        let rows = BankKeys.rows(status)
        #expect(rows.map(\.provider) == ["teller", "plaid"])
        #expect(rows.map(\.text) == ["Your own keys · Development", "No keys yet"])
        #expect(rows.map(\.hasKeys) == [true, false])
        #expect(BankKeys.buttonTitle(status) == "Your bank keys")
        // An older server says neither, so the card lists nothing and offers no page.
        let older: BankStatus = try sample("bank-status-connected")
        #expect(older.ownKeys == nil && older.providersTicked == nil && BankKeys.rows(older).isEmpty)
        #expect(!BankKeys.offered(older, serverVersion: "1.97.0", readOnly: false))
    }

    @Test func theKeysCardListsServicesWithKeysOrTickedWhileSyncIsOn() {
        func rows(enabled: Bool = true, ticked: [String], own: OwnBankKeys) -> [String] {
            BankKeys.rows(BankStatus(enabled: enabled, connected: false, providersAllowed: [],
                                     providersTicked: ticked, ownKeys: own)).map(\.provider)
        }
        #expect(rows(ticked: ["teller", "plaid"], own: OwnBankKeys()) == ["teller", "plaid"])
        #expect(rows(ticked: ["simplefin"], own: OwnBankKeys()).isEmpty)          // SimpleFIN takes no keys
        #expect(rows(ticked: [], own: OwnBankKeys(plaid: .init(environment: "sandbox"))) == ["plaid"])   // unticked, keys still shown
        #expect(rows(enabled: false, ticked: ["teller"], own: OwnBankKeys()).isEmpty)                     // switched off: nothing to add
        #expect(BankKeys.environmentName("production") == "Production" && BankKeys.environmentName("odd") == "odd")
        let none = BankStatus(enabled: true, connected: false, providersAllowed: [], providersTicked: ["plaid"], ownKeys: OwnBankKeys())
        #expect(BankKeys.buttonTitle(none) == "Add your bank keys")
    }

    @Test func theKeysPageIsOfferedFromServer1_97WithAWritingTokenAndSomethingToList() throws {
        let status: BankStatus = try sample("bank-status-own-keys")
        #expect(BankKeys.offered(status, serverVersion: "1.97.0", readOnly: false))
        #expect(BankKeys.offered(status, serverVersion: "1.98.2", readOnly: false))
        #expect(!BankKeys.offered(status, serverVersion: "1.96.0", readOnly: false))   // no page yet
        #expect(!BankKeys.offered(status, serverVersion: nil, readOnly: false))
        #expect(!BankKeys.offered(status, serverVersion: "1.97.0", readOnly: true))
        let address = try ServerAddress.parse("https://ww.example.com")
        #expect(BankKeys.url(server: address).absoluteString == "https://ww.example.com/app-bank-keys")
    }

    @Test func theKeysPageAnswerSaysWhetherAnythingChangedAndNeverCarriesAKey() throws {
        let changed = try #require(AppLink(URL(string: "walletweather://bank-keys?state=changed")!))
        #expect(changed == .bankKeys(state: "changed") && changed.state == nil)
        #expect(BankKeys.outcome(changed)?.text == "Your bank keys are updated.")
        #expect(BankKeys.outcome(changed)?.failed == false)
        #expect(BankKeys.outcome(AppLink(URL(string: "walletweather://bank-keys?state=closed")!)) == nil)
        #expect(BankKeys.outcome(AppLink(URL(string: "walletweather://bank-keys?state=off")!))?.failed == true)
        #expect(BankKeys.outcome(nil) == nil)                       // closed by hand
        #expect(AppLink(URL(string: "walletweather://bank-keys")!) == nil)
        // Connect a bank's answer isn't this page's.
        #expect(BankKeys.outcome(AppLink(URL(string: "walletweather://bank-connected?connection=7")!)) == nil)
    }

    @Test func tickedWithoutKeysIsToldToAddThemNotThatAnAdminChooses() throws {
        let status: BankStatus = try sample("bank-status-own-keys")
        #expect(status.addKeysFirst == false)   // Teller has keys, so Teller is offered
        let noKeys = BankStatus(enabled: true, connected: false, providersAllowed: ["simplefin"],
                                providersTicked: ["simplefin", "teller", "plaid"], ownKeys: OwnBankKeys())
        #expect(noKeys.addKeysFirst && noKeys.mayConnect && !noKeys.mayConnectInApp)
        #expect(noKeys.summary(now: now, when: when).detail?.hasPrefix("Teller and Plaid each need keys") == true)
        let onlyTeller = BankStatus(enabled: true, connected: false, providersAllowed: [],
                                    providersTicked: ["teller"], ownKeys: OwnBankKeys())
        #expect(onlyTeller.addKeysFirst && onlyTeller.mayConnect)
        // An older server doesn't say, so nothing changes.
        let older = BankStatus(enabled: true, connected: false, providersAllowed: [])
        #expect(!older.addKeysFirst && !older.mayConnect)
    }

    // MARK: Who may connect, and shared accounts (sync-access phase 4, #267)

    @Test func connectIsOfferedOnlyToSomeoneTickedForTellerOrPlaid() throws {
        func offered(_ allowed: [String]?) -> Bool {
            BankConnect.offered(BankStatus(enabled: true, connected: false, providersAllowed: allowed),
                                serverVersion: "1.92.1", readOnly: false)
        }
        #expect(offered(["teller"]) && offered(["plaid"]) && offered(["simplefin", "teller", "plaid"]))
        #expect(!offered([]))                // not ticked for anything
        #expect(!offered(["simplefin"]))     // SimpleFIN is connected in the web app
        // A server before 1.92.1 doesn't say, so it's offered as it was.
        #expect(offered(nil))
        let status: BankStatus = try sample("bank-status-connected")
        #expect(status.providersAllowed == nil && status.mayConnect && status.mayConnectInApp)
    }

    @Test func anUntickedPersonIsToldAnAdminChoosesNotToConnectInTheWebApp() throws {
        let status: BankStatus = try sample("bank-status-shared")
        #expect(status.providersAllowed == [] && !status.mayConnect && !status.mayConnectInApp)
        let summary = status.summary(now: now, when: when)
        #expect(summary.headline == "No bank connected")
        #expect(summary.detail?.contains("Admin → Users") == true)
        // Ticked for one but nothing connected yet: the web app is where it's done.
        let ticked = BankStatus(enabled: true, connected: false, providersAllowed: ["simplefin"])
        #expect(ticked.summary(now: now, when: when).detail == "Connecting a bank is done in the web app: Settings → Bank sync.")
    }

    @Test func aSharedAccountReadsAsTheServerWritesItAndSaysWhoseConnection() throws {
        let status: BankStatus = try sample("bank-status-shared")
        let account = try #require(status.shared?.first)
        #expect(account.id == 7 && account.accountName == "Joint checking" && account.level == "edit")
        #expect(account.from == "Synced from Sam's SimpleFIN connection")
        let summary = account.summary(now: now, when: when)
        #expect(summary.tone == .ok && summary.canSync && summary.waitText == nil)
        #expect(summary.headline == "Synced T\(Int(BankStatus.date(account.lastSyncAt)!.timeIntervalSince1970))")
        #expect(summary.detail == "2 new lines, 1 matched a bill, 3 already here")
        #expect(summary.next?.hasPrefix("Syncs by itself again about T") == true)
        #expect(account.unmatchedCount == 2)
        // An older server has no `shared`, which is none.
        let older: BankStatus = try sample("bank-status-connected")
        #expect(older.shared == nil)
    }

    @Test func aSharedAccountTurnsSyncNowOffWhilePausedOrNeedingReconnectOrItsPersonCantSignIn() {
        func account(paused: Bool = false, reconnect: Bool = false, disabled: Bool = false, wait: Int = 0) -> SharedBankAccount {
            SharedBankAccount(accountId: 3, accountName: "Savings", holderName: "Sam", provider: "teller", providerName: "Teller",
                              lastSyncAt: "2026-11-17T10:00:00Z", lastSyncOk: true, lastSyncStatus: "0 new lines, 4 already here",
                              needsReconnect: reconnect, paused: paused, holderDisabled: disabled, syncWaitSeconds: wait)
        }
        let paused = account(paused: true).summary(now: now, when: when)
        #expect(paused.tone == .warning && !paused.canSync && paused.headline == "Paused by an admin")
        #expect(paused.detail == "An admin has paused Sam's Teller connection. This account syncs again once an admin lets Sam use Teller.")
        let reconnect = account(reconnect: true).summary(now: now, when: when)
        #expect(reconnect.tone == .warning && !reconnect.canSync && reconnect.detail?.hasSuffix("Sam needs to connect it again.") == true)
        let disabled = account(disabled: true).summary(now: now, when: when)
        #expect(disabled.tone == .warning && !disabled.canSync && disabled.headline == "Sam can't sign in")
        let waiting = account(wait: 5400).summary(now: now, when: when)
        #expect(!waiting.canSync && waiting.waitText?.hasSuffix("It can run again in 90 minutes.") == true)
        #expect(waiting.tone == .ok)   // its last sync was fine; only the limit holds it
        // Bank sync switched off for the whole server beats everything.
        let off = account().summary(enabled: false, now: now, when: when)
        #expect(off.headline == "Bank sync is switched off" && !off.canSync)
    }

    @Test func aSharedAccountsFailedOrMissingSyncSaysSo() {
        let failed = SharedBankAccount(accountId: 3, accountName: "Savings", holderName: "Sam", providerName: "Teller",
                                       lastSyncAt: "2026-11-17T10:00:00Z", lastSyncOk: false, lastSyncStatus: "Teller didn't answer.")
        let summary = failed.summary(now: now, when: when)
        #expect(summary.tone == .warning && summary.headline == "Last sync failed" && summary.canSync)
        #expect(summary.detail?.hasSuffix(": Teller didn't answer.") == true)
        let never = SharedBankAccount(accountId: 3, accountName: "Savings")
        #expect(never.summary(now: now, when: when).headline == "Not synced yet")
        #expect(never.from == "Synced from someone's bank connection")
    }

    @Test func afterTheSheetTheCardNamesTheNewConnectionAndWhereToMatchIt() throws {
        let status: BankStatus = try sample("bank-status-connections")
        let done = BankConnect.outcome(.bankConnected(connection: 2, state: nil), status: status)
        #expect(done?.text == "Connected Contoso Credit Union through Teller. Match its accounts to yours in the web app: Settings → Bank sync.")
        #expect(done?.failed == false)
        // A number the status doesn't list yet still says it connected.
        #expect(BankConnect.outcome(.bankConnected(connection: 99, state: nil), status: status)?.text.hasPrefix("Connected your bank.") == true)
        #expect(BankConnect.outcome(.bankConnected(connection: nil, state: "exited"), status: status)?.text == "Closed without connecting a bank.")
        #expect(BankConnect.outcome(.bankConnected(connection: nil, state: "expired"), status: status)?.failed == true)
        #expect(BankConnect.outcome(.bankConnected(connection: nil, state: "failed"), status: status)?.failed == true)
        #expect(BankConnect.outcome(.bankConnected(connection: nil, state: "off"), status: status)?.failed == true)
        // Cancel on the page, closing the sheet by hand, or another answer: nothing to say.
        #expect(BankConnect.outcome(.bankConnected(connection: nil, state: "cancelled"), status: status) == nil)
        #expect(BankConnect.outcome(nil, status: status) == nil)
        #expect(BankConnect.outcome(.cancelled(state: "x"), status: status) == nil)
    }

    // MARK: A bill's two match settings

    @Test func aBillCarriesItsMatchSettingsBothWays() throws {
        let list: RecurringList = try sample("recurring")
        let item = try #require(list.items.first)
        #expect(item.matchDays == 5 && item.matchPercent == 10)
        var draft = BillDraft(item, today: LocalDay(year: 2026, month: 11, day: 17))
        #expect(draft.matchDays == 5 && draft.matchPercent == 10 && draft.problem == nil)
        draft.matchDays = 2
        draft.matchPercent = 0
        let body = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RecurringBody(draft))) as? [String: Any]
        #expect(body?["match_days"] as? Int == 2 && body?["match_percent"] as? Int == 0)
        draft.matchDays = 32
        #expect(draft.problem == "Bank match days can be 0 to 31.")
        draft.matchDays = 5
        draft.matchPercent = 101
        #expect(draft.problem == "The amount can differ by 0 to 100 percent.")
    }

    @Test func aServerWithoutTheSettingsLeavesThemOutOfTheRequest() throws {
        // A bill from a server older than 1.73.0 has none; saving it must not
        // send any, which would otherwise reset them to nothing.
        let url = try #require(Bundle.module.url(forResource: "recurring", withExtension: "json", subdirectory: "Samples"))
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        var json = try #require(parsed as? [String: Any])
        var items = try #require(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "match_days")
        items[0].removeValue(forKey: "match_percent")
        json["items"] = items
        let list = try APIClient.decoder().decode(RecurringList.self, from: JSONSerialization.data(withJSONObject: json))
        let item = try #require(list.items.first)
        #expect(item.matchDays == nil && item.matchPercent == nil)
        let body = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RecurringBody(BillDraft(item, today: .today())))) as? [String: Any]
        #expect(body?["match_days"] == nil && body?["match_percent"] == nil)
        #expect(body?["description"] as? String == item.description)
        // A new bill sends none either: the server starts it at 5 days and 10%.
        let new = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RecurringBody(BillDraft(today: .today())))) as? [String: Any]
        #expect(new?["match_days"] == nil)
    }
}

extension StubServerSuites {
    /// The requests Sync now and the status make, to a stand-in server.
    @Suite struct BankSyncRequests {
        static func client() -> APIClient {
            APIClient(connection: Connection(server: URL(string: "https://ww.example.com")!, token: "ww_sample-token-not-real"),
                      session: StubServer.session())
        }

        @Test func syncNowDecodesWhatCameInAndTheNewStatus() async throws {
            let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "bank-sync", withExtension: "json",
                                                                             subdirectory: "Samples")))
            StubServer.answer(200, sample)
            let result = try await Self.client().syncBankNow()
            #expect((result.added, result.matched, result.skipped) == (2, 1, 14))
            #expect(result.status.lastSyncStatus == "2 new lines, 1 matched a bill, 14 already here")
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "POST" && request.url?.path == "/api/bank/sync")
        }

        @Test func theStatusIsReadWithTheToken() async throws {
            let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "bank-status-connected",
                                                                             withExtension: "json", subdirectory: "Samples")))
            StubServer.answer(200, sample)
            let status = try await Self.client().bankStatus()
            #expect(status?.connected == true)
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "GET" && request.url?.path == "/api/bank/status")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ww_sample-token-not-real")
        }

        @Test func theStatusDecodesEveryConnection() async throws {
            let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "bank-status-connections",
                                                                             withExtension: "json", subdirectory: "Samples")))
            StubServer.answer(200, sample)
            let status = try #require(try await Self.client().bankStatus())
            #expect(status.connections?.count == 4)
            #expect(status.connections?.first?.providerName == "SimpleFIN")
        }

        @Test func syncNowForOneConnectionAsksForThatConnectionOnly() async throws {
            let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "bank-sync", withExtension: "json",
                                                                             subdirectory: "Samples")))
            StubServer.answer(200, sample)
            _ = try await Self.client().syncBankNow(connection: 2)
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "POST" && request.url?.path == "/api/bank/sync")
            let body = try #require(StubServer.lastBody)
            #expect(try JSONSerialization.jsonObject(with: body) as? [String: Int] == ["connection_id": 2])
        }

        @Test func syncNowForASharedAccountAsksForThatAccountAndDecodesItsState() async throws {
            let body = #"""
            {"added": 2, "matched": 1, "skipped": 3, "messages": [], "calibrated": [],
             "status": {"enabled": true, "connected": false, "providers_allowed": [], "shared": []},
             "account": {"account_id": 7, "account_name": "Joint checking", "archived": false, "level": "edit",
                         "holder_name": "Sam", "mine": false, "provider": "simplefin", "provider_name": "SimpleFIN",
                         "last_sync_at": "2026-11-21T15:04:05Z", "last_sync_ok": true,
                         "last_sync_status": "2 new lines, 1 matched a bill, 3 already here",
                         "needs_reconnect": false, "paused": false, "holder_disabled": false,
                         "syncs_left_today": 18, "sync_wait_seconds": 0, "unmatched_count": 0}}
            """#
            StubServer.answer(200, Data(body.utf8))
            let result = try await Self.client().syncBankNow(account: 7)
            #expect(result.account?.accountId == 7 && result.account?.syncsLeftToday == 18)
            #expect(result.account?.lastSyncStatus == "2 new lines, 1 matched a bill, 3 already here")
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "POST" && request.url?.path == "/api/bank/sync")
            let sent = try #require(StubServer.lastBody)
            #expect(try JSONSerialization.jsonObject(with: sent) as? [String: Int] == ["account_id": 7])
        }

        @Test func aPausedHoldersRefusalComesThroughInTheServersWords() async {
            let said = "An admin has paused Sam's SimpleFIN connection, so this account can't sync until they're allowed again."
            StubServer.answer(403, Data(#"{"detail":"\#(said)"}"#.utf8))
            await #expect(throws: APIError.server(status: 403, detail: said)) {
                _ = try await Self.client().syncBankNow(account: 7)
            }
        }

        @Test func aConnectionOverItsLimitIsRefusedInTheServersWords() async {
            let said = "Bank sync has asked Teller 20 times in the last 24 hours, the most it allows without risking your connection. It can run again in 5 minutes."
            StubServer.answer(429, Data(#"{"detail":"\#(said)"}"#.utf8))
            await #expect(throws: APIError.server(status: 429, detail: said)) {
                _ = try await Self.client().syncBankNow(connection: 2)
            }
        }

        @Test func aServerOlderThan1700HasNoStatusAndThatIsNotAnError() async throws {
            StubServer.answer(404, Data(#"{"detail":"Not Found"}"#.utf8))
            #expect(try await Self.client().bankStatus() == nil)
            StubServer.answer(200, Data("<html>not the api</html>".utf8))
            #expect(try await Self.client().bankStatus() == nil)
        }

        @Test func overTheLimitTheServersWordsComeThrough() async {
            let said = "Bank sync has asked SimpleFIN 20 times in the last 24 hours, the most it allows without risking your connection. It can run again in 12 minutes."
            StubServer.answer(429, Data(#"{"detail":"\#(said)"}"#.utf8))
            await #expect(throws: APIError.server(status: 429, detail: said)) {
                _ = try await Self.client().syncBankNow()
            }
        }

        @Test func aReadOnlyTokenOrNoBankIsRefusedInTheServersWords() async {
            StubServer.answer(404, Data(#"{"detail":"No bank is connected."}"#.utf8))
            await #expect(throws: APIError.server(status: 404, detail: "No bank is connected.")) {
                _ = try await Self.client().syncBankNow()
            }
            StubServer.answer(403, Data(#"{"detail":"This token can only read."}"#.utf8))
            await #expect(throws: APIError.server(status: 403, detail: "This token can only read.")) {
                _ = try await Self.client().syncBankNow()
            }
        }
    }
}
