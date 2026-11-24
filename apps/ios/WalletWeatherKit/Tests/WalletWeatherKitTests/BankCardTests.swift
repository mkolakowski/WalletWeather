import Foundation
import Testing
@testable import WalletWeatherKit

/// Which lines the Dashboard's bank card shows for each bank state (#321).
struct BankCardTests {
    func connection(_ id: Int, _ name: String, accounts: [Int], reconnect: Bool = false) -> BankConnection {
        BankConnection(id: id, provider: "teller", providerName: "Teller", name: name,
                       linkedAccountIds: accounts, needsReconnect: reconnect)
    }

    func status(enabled: Bool = true, connected: Bool = true, connections: [BankConnection]? = nil,
                shared: [SharedBankAccount]? = nil, reconnect: Bool? = nil, linked: [Int]? = nil) -> BankStatus {
        BankStatus(enabled: enabled, connected: connected, linkedAccountIds: linked, needsReconnect: reconnect,
                   connections: connections, shared: shared)
    }

    @Test func nothingToDoShowsNoCard() {
        let healthy = status(connections: [connection(1, "Northwind Bank", accounts: [1])])
        #expect(BankCard.lines(status: healthy, counts: [:]).isEmpty)
        #expect(BankCard.lines(status: healthy, counts: [1: 0]).isEmpty)
        #expect(BankCard.lines(status: nil, counts: [1: 3]).isEmpty)
        #expect(BankCard.lines(status: status(connected: false), counts: [:]).isEmpty)
    }

    @Test func linesToMatchAreCountedAcrossAccountsAndOpenTheirList() {
        let two = status(connections: [connection(1, "Northwind Bank", accounts: [1, 2]), connection(2, "Contoso", accounts: [3])])
        let lines = BankCard.lines(status: two, counts: [1: 2, 3: 1, 9: 5])
        #expect(lines.count == 1)
        #expect(lines[0].text == "3 bank lines to match")
        #expect(lines[0].action == .unmatched(accounts: [1, 3]))
        #expect(BankCard.lines(status: two, counts: [2: 1])[0].text == "1 bank line to match")
    }

    @Test func aBankThatNeedsReconnectingIsNamedOrCounted() {
        let one = status(connections: [connection(1, "Contoso Credit Union", accounts: [1], reconnect: true),
                                       connection(2, "Northwind Bank", accounts: [2])])
        let line = BankCard.lines(status: one, counts: [:])
        #expect(line.map(\.text) == ["Contoso Credit Union needs reconnecting"])
        #expect(line[0].action == .reconnect)

        let both = status(connections: [connection(1, "A", accounts: [1], reconnect: true),
                                        connection(2, "B", accounts: [2], reconnect: true)])
        #expect(BankCard.lines(status: both, counts: [:]).map(\.text) == ["2 banks need reconnecting"])
    }

    @Test func reconnectingComesFirstAndTheCardStaysAtTwoLines() {
        let many = status(connections: [connection(1, "A", accounts: [1], reconnect: true),
                                        connection(2, "B", accounts: [2], reconnect: true),
                                        connection(3, "C", accounts: [3])],
                          shared: [SharedBankAccount(accountId: 7, accountName: "Joint", unmatchedCount: 4)])
        let lines = BankCard.lines(status: many, counts: [3: 2, 7: 4])
        #expect(lines.map(\.text) == ["2 banks need reconnecting", "6 bank lines to match"])
        #expect(lines.count <= BankCard.maxLines)
        #expect(Set(lines.map(\.id)).count == lines.count)
    }

    @Test func aServerWithoutAConnectionsListUsesItsTopLevelFields() {
        let old = status(reconnect: true, linked: [1])
        #expect(BankCard.lines(status: old, counts: [1: 1]).map(\.text) == ["Your bank needs reconnecting", "1 bank line to match"])
    }

    @Test func sharedAccountsShowTheirLinesButNeverAskToReconnect() {
        let sharedOnly = status(connected: false,
                                shared: [SharedBankAccount(accountId: 7, accountName: "Joint", needsReconnect: true, unmatchedCount: 2)])
        let lines = BankCard.lines(status: sharedOnly, counts: [7: 2])
        #expect(lines.map(\.text) == ["2 bank lines to match"])
        #expect(lines[0].action == .unmatched(accounts: [7]))
    }

    @Test func bankSyncSwitchedOffShowsNothing() {
        let off = status(enabled: false, connections: [connection(1, "A", accounts: [1], reconnect: true)])
        #expect(BankCard.lines(status: off, counts: [1: 5]).isEmpty)
    }

    @Test func theIPhonesOwnBankFollowsTheSameRules() {
        var state = PhoneBankState()
        #expect(BankCard.lines(phone: state, connected: true).isEmpty)
        state.unmatched = 3
        #expect(BankCard.lines(phone: state, connected: false).isEmpty)
        let match = BankCard.lines(phone: state, connected: true)
        #expect(match.map(\.text) == ["3 bank lines to match"] && match[0].action == .unmatched(accounts: nil))

        state.needsReconnect = true
        #expect(BankCard.lines(phone: state, connected: true).map(\.text) == ["SimpleFIN needs reconnecting", "3 bank lines to match"])
        state.bankAccounts = [SimpleFIN.Account(id: "a", name: "Checking", org: "Northwind Bank")]
        #expect(BankCard.lines(phone: state, connected: true)[0].text == "Northwind Bank needs reconnecting")
    }

    @Test func theDemoShowsLinesToMatchAndNeedsNoReconnectState() async throws {
        let client = APIClient(connection: Demo.connection)
        let status = try await client.bankStatus()
        let counts = await client.unmatchedCounts(for: try #require(status))
        let lines = BankCard.lines(status: status, counts: counts)
        #expect(lines.count == 1 && lines[0].text.hasSuffix("to match"))
    }
}
