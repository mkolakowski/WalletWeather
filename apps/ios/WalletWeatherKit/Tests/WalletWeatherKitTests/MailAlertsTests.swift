import Foundation
import Testing
@testable import WalletWeatherKit

/// Email alerts in the iPhone app (Plans/bank-alert-emails.md, phase 6,
/// #211): the server's `/api/mail/status` read and put in plain words for
/// each state, the Bank sync row's value, Check now's request and what it
/// says, the demo's sample, and the household on this iPhone having none.
extension StubServerSuites {
    @Suite struct MailAlertsTests {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func when(_ date: Date) -> String { "\(Int(now.timeIntervalSince(date) / 60)) min" }
        func at(_ minutes: Double) -> String { BankStatus.text(now.addingTimeInterval(minutes * 60)) }

        /// `/api/mail/status` as server 1.98 answers it for a connected
        /// mailbox (`_mail_short_status`), with the fields the app ignores.
        func recorded(_ changes: [String: Any] = [:]) throws -> MailStatus {
            var body: [String: Any] = [
                "enabled": true, "connected": true, "providers_allowed": ["microsoft"], "shared": [],
                "check_minutes": 60, "last_check_at": at(-12), "last_check_ok": true,
                "last_check_status": "2 new lines, 1 matched", "last_ok_at": at(-12), "needs_reconnect": false,
                "paused": false, "failing_since": NSNull(), "failing_over_a_day": false,
                "next_check_at": at(48), "unread_count": 0,
            ]
            for (key, value) in changes { body[key] = value }
            return try APIClient.decoder().decode(MailStatus.self, from: JSONSerialization.data(withJSONObject: body))
        }

        // MARK: In plain words

        @Test func aCheckedMailboxSaysWhenAndWhatCameIn() throws {
            let summary = try recorded().summary(now: now, when: when)
            #expect(summary.tone == .ok)
            #expect(summary.headline == "Checked 12 min")
            #expect(summary.lines == ["2 new lines, 1 matched"])
            #expect(summary.next == "Next check -48 min.")
            #expect(summary.canCheck)
        }

        @Test func alertsThatCouldntBeReadPointToTheWebApp() throws {
            let one = try recorded(["unread_count": 1]).summary(now: now, when: when)
            #expect(one.tone == .warning)
            #expect(one.lines.last == "1 alert couldn't be read: see it in the web app's Settings → Email alerts.")
            let three = try recorded(["unread_count": 3]).summary(now: now, when: when)
            #expect(three.lines.last == "3 alerts couldn't be read: see them in the web app's Settings → Email alerts.")
        }

        @Test func switchedOffOrNotConnectedOffersNoCheck() throws {
            let off = MailStatus(enabled: false, connected: false).summary(now: now, when: when)
            #expect(off.headline == "Email alerts are switched off on this server")
            #expect(!off.canCheck)
            // Not connected: the server sends no more than these.
            let none = try APIClient.decoder().decode(MailStatus.self, from: Data(
                #"{"enabled": true, "connected": false, "providers_allowed": ["microsoft"], "shared": []}"#.utf8))
            let summary = none.summary(now: now, when: when)
            #expect(summary.headline == "No mailbox connected")
            #expect(summary.lines.first?.contains("the web app's Settings → Email alerts") == true)
            #expect(!summary.canCheck)
        }

        @Test func needsReconnectingOrPausedOffersNoCheck() throws {
            let reconnect = try recorded(["needs_reconnect": true, "unread_count": 2]).summary(now: now, when: when)
            #expect(reconnect.tone == .warning)
            #expect(reconnect.headline == "Needs reconnecting")
            #expect(reconnect.lines.count == 2)
            #expect(!reconnect.canCheck)
            let paused = try recorded(["paused": true]).summary(now: now, when: when)
            #expect(paused.headline == "Paused")
            #expect(!paused.canCheck)
        }

        @Test func aFailedCheckSaysWhyAndSinceWhen() throws {
            let failed = try recorded(["last_check_ok": false, "last_check_status": "The folder Bank alerts is gone",
                                       "failing_since": at(-26 * 60), "failing_over_a_day": true]).summary(now: now, when: when)
            #expect(failed.tone == .warning)
            #expect(failed.headline == "Last check failed")
            #expect(failed.lines == ["The last check didn't work: The folder Bank alerts is gone", "Failing since 1560 min."])
            #expect(failed.canCheck)
        }

        @Test func neverCheckedSaysSo() throws {
            let fresh = try recorded(["last_check_at": NSNull(), "last_check_ok": NSNull(), "last_check_status": NSNull()])
            let summary = fresh.summary(now: now, when: when)
            #expect(summary.headline == "Not checked yet")
            #expect(summary.canCheck)
        }

        // MARK: The Bank sync row

        @Test func theRowShowsTheMailboxOnlyWhenTheBanksAreFine() throws {
            let banks = try APIClient.decoder().decode(BankStatus.self, from: Demo.bankStatus(now: now))
            let fine = banks.settingsValue(unmatched: 0, when: when)
            #expect(banks.settingsValue(unmatched: 0, mail: try recorded(), when: when) == fine)
            #expect(banks.settingsValue(unmatched: 0, mail: try recorded(["unread_count": 2]), when: when) == "2 alerts unread")
            #expect(banks.settingsValue(unmatched: 0, mail: try recorded(["needs_reconnect": true]), when: when) == "Alerts: reconnect")
            #expect(banks.settingsValue(unmatched: 0, mail: try recorded(["last_check_ok": false]), when: when) == "Alerts: check failed")
            // Lines to match on the banks come first.
            #expect(banks.settingsValue(unmatched: 3, mail: try recorded(["unread_count": 2]), when: when) == "3 to match")
            #expect(banks.settingsValue(unmatched: 0, mail: nil, when: when) == fine)
        }

        // MARK: Check now

        @Test func checkNowSendsTheOffsetAndSaysWhatCameIn() async throws {
            StubServer.answer(200, Data(#"{"added": 2, "matched": 1, "skipped": 0, "unread": 0, "more": false, "status": {}}"#.utf8))
            let client = APIClient(connection: Connection(server: URL(string: "https://money.example.test")!, token: "ww_t"),
                                   session: StubServer.session())
            let result = try await client.checkMailNow(utcOffsetMinutes: -300)
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path() == "/api/mail/check")
            let body = try #require(try JSONSerialization.jsonObject(with: StubServer.lastBody ?? Data()) as? [String: Int])
            #expect(body == ["utc_offset_minutes": -300])
            #expect(result.said == "2 new lines, 1 paid a planned bill.")
            #expect(MailCheckResult(added: 0, matched: 0, skipped: 0, unread: 0).said == "No new alerts.")
            #expect(MailCheckResult(added: 0, matched: nil, skipped: nil, unread: 1).said == "No new lines; 1 alert couldn't be read.")
            #expect(MailCheckResult(added: 1, matched: nil, skipped: nil, unread: nil).said == "1 new line.")
        }

        @Test func checkNowRefusedComesBack() async throws {
            StubServer.answer(409, Data(#"{"detail": "A check is already running. Try again in a minute."}"#.utf8))
            let client = APIClient(connection: Connection(server: URL(string: "https://money.example.test")!, token: "ww_t"),
                                   session: StubServer.session())
            await #expect(throws: APIError.self) { _ = try await client.checkMailNow() }
        }

        @Test func anOlderServerHasNoStatus() async throws {
            StubServer.answer(404, Data(#"{"detail": "Not Found"}"#.utf8))
            let client = APIClient(connection: Connection(server: URL(string: "https://money.example.test")!, token: "ww_t"),
                                   session: StubServer.session())
            #expect(try await client.mailStatus() == nil)
        }

        // MARK: The demo and this iPhone

        @Test func theDemoShowsASample() async throws {
            let status = try #require(try await APIClient(connection: Demo.connection).mailStatus())
            #expect(status.connected && status.enabled)
            #expect(status.unreadCount == 1)
            #expect(status.summary(when: { _ in "earlier" }).headline == "Checked earlier")
            // Check now isn't something the demo does.
            await #expect(throws: APIError.self) { _ = try await APIClient(connection: Demo.connection).checkMailNow() }
        }

        @Test func theHouseholdOnThisIPhoneHasNone() async throws {
            let household = try LocalServer.inMemory()
            #expect(try await APIClient(connection: household.connection).mailStatus() == nil)
        }
    }
}
