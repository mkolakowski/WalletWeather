import Foundation
import Testing
@testable import WalletWeatherKit

/// Matching bank lines from the app with a server (duo-more phase 3, #306):
/// the server's two reads decoded from recorded samples, the count on
/// Settings' Bank sync row, and the demo's sample lines.
struct UnmatchedTests {
    let client = APIClient(connection: Demo.connection)
    let today = LocalDay(year: 2026, month: 11, day: 23)

    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
        return try APIClient.decoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: The server's shapes

    @Test func theUnmatchedListDecodes() throws {
        let list: BankUnmatched = try sample("bank-unmatched")
        #expect(list.count == 2 && list.lines.count == 2)
        let first = list.lines[0]
        #expect(first.description == "PAYROLL ACME" && first.amount == Money(2500.0) && first.source == "bank")
        #expect(first.date == LocalDay(year: 2026, month: 11, day: 22) && first.notes == nil)
        #expect(list.lines[1].amount.isNegative)
    }

    @Test func theCandidatesDecode() throws {
        let found: BankCandidates = try sample("bank-unmatched-candidates")
        #expect(found.line.id == 10 && found.line.learnName == "CORNER GROCERY" && found.line.bankText == nil)
        let choice = try #require(found.choices.first)
        #expect(found.choices.count == 1)
        #expect(choice.recurringId == 5 && choice.transactionId == nil)
        #expect(choice.description == "Groceries" && choice.amount == Money(-60.0))
        #expect(choice.daysApart == 0 && choice.daysAfter == 0 && choice.amountDiff == Money(17.5))
        #expect(choice.sameDirection && choice.withinDays)
        #expect(choice.id == "r5-2026-11-21")
    }

    // MARK: The count on Settings' Bank sync row

    @Test func linesWaitingReplaceTheSyncTime() {
        let when: (Date) -> String = { _ in "7:22 AM" }
        let synced = BankStatus(enabled: true, connected: true, lastSyncAt: "2026-11-23T12:22:00Z", lastSyncOk: true)
        #expect(synced.settingsValue(when: when) == "1 bank · synced 7:22 AM")
        #expect(synced.settingsValue(unmatched: 0, when: when) == "1 bank · synced 7:22 AM")
        #expect(synced.settingsValue(unmatched: 3, when: when) == "3 to match")
        // A problem with the bank still comes first, and off is off.
        let broken = BankStatus(enabled: true, connected: true, needsReconnect: true)
        #expect(broken.settingsValue(unmatched: 3, when: when) == "Needs reconnecting")
        #expect(BankStatus(enabled: false, connected: false).settingsValue(unmatched: 3, when: when) == "Off")
        // Someone with only a shared account to match.
        let shared = BankStatus(enabled: true, connected: false, shared: [
            SharedBankAccount(accountId: 3, accountName: "Credit Card", unmatchedCount: 2)])
        #expect(shared.settingsValue(when: when) == "1 shared account")
        #expect(shared.settingsValue(unmatched: 2, when: when) == "2 to match")

        var phone = PhoneBankState()
        phone.lastSyncAt = .now
        phone.lastSyncOk = true
        #expect(phone.settingsValue(connected: true, when: when) == "1 bank · synced 7:22 AM")
        phone.unmatched = 4
        #expect(phone.settingsValue(connected: true, when: when) == "4 to match")
        #expect(phone.settingsValue(connected: false, when: when) == "No bank connected")
        phone.needsReconnect = true
        #expect(phone.settingsValue(connected: true, when: when) == "Needs reconnecting")
    }

    @Test func whichAccountsAreAskedAndHowTheyAreCounted() {
        let status = BankStatus(
            enabled: true, connected: true, linkedAccountIds: [1, 2, 3],
            connections: [
                BankConnection(id: 1, provider: "simplefin", providerName: "SimpleFIN", name: "A", linkedAccountIds: [1, 2]),
                BankConnection(id: 2, provider: "teller", providerName: "Teller", name: "B", linkedAccountIds: [2, 4]),
            ],
            shared: [SharedBankAccount(accountId: 3, accountName: "Card", unmatchedCount: 2)])
        // The shared account's count is in the status; the rest are asked, each once.
        #expect(status.ownLinkedAccountIds == [1, 2, 4])
        let counts = [1: 3, 4: 1, 3: 2]
        #expect(status.connections?[0].unmatched(in: counts) == 3)
        #expect(status.connections?[1].unmatched(in: counts) == 1)
        // A server from before the connections list has the one list on top.
        let old = BankStatus(enabled: true, connected: true, linkedAccountIds: [5, 6])
        #expect(old.ownLinkedAccountIds == [5, 6])
    }

    // MARK: The demo

    @Test func theDemoCountsItsWaitingLines() async throws {
        let status = try #require(try await client.bankStatus())
        let counts = await client.unmatchedCounts(for: status)
        #expect(counts == [3: 2])
    }

    @Test func theDemoListsTwoSampleLinesOnTheCreditCard() async throws {
        let list = try await client.bankUnmatched(account: 3)
        #expect(list.count == 2 && list.lines.map(\.description) == ["VERIZON WIRELESS", "TARGET"])
        #expect(list.lines.allSatisfy { $0.source == "bank" && $0.amount.isNegative })
        // Made from today, newest first.
        #expect(list.lines[0].date > list.lines[1].date)
        #expect(list.lines[0].date <= LocalDay.today())
        // The other accounts have none waiting.
        #expect(try await client.bankUnmatched(account: 1).lines.isEmpty)
    }

    @Test func theDemoOffersAClosePhoneBillAndTheOtherLineIsFarFromIt() async throws {
        let list = try await client.bankUnmatched(account: 3)
        let close = try await client.bankCandidates(account: 3, line: list.lines[0].id)
        #expect(close.line.learnName == "VERIZON WIRELESS" && close.line.bankText == "VERIZON WIRELESS 800-555-0142 NY")
        let choice = try #require(close.choices.first)
        #expect(choice.description == "Phone bill" && choice.recurringId == 7 && choice.sameDirection)
        #expect(choice.withinDays == (choice.daysApart <= 5))
        #expect(choice.amountDiff == Money(-2.4))
        // The bank's date minus the planned one, as the server says.
        let planned = try #require(LocalDay(choice.forecastDate.description))
        #expect(list.lines[0].date.days(since: planned) == choice.daysAfter)
        #expect(planned.day == 20)
        let other = try await client.bankCandidates(account: 3, line: list.lines[1].id)
        #expect(other.choices.first?.amountDiff == Money(30.88))
    }

    @Test func theDemoRefusesMatchAndLeaveAndKnowsOnlyItsLines() async throws {
        let list = try await client.bankUnmatched(account: 3)
        let choice = try #require(try await client.bankCandidates(account: 3, line: list.lines[0].id).choices.first)
        await #expect(throws: APIError.demoReadOnly) {
            _ = try await client.bankMatch(account: 3, line: list.lines[0].id, to: choice, remember: true)
        }
        await #expect(throws: APIError.demoReadOnly) { try await client.bankLeave(account: 3, line: list.lines[1].id) }
        // A line that isn't on the list is a missing page, as on the server.
        await #expect(throws: APIError.self) { _ = try await client.bankCandidates(account: 3, line: 123456) }
    }
}
