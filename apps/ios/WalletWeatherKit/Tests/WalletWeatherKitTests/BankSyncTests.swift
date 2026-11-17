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
