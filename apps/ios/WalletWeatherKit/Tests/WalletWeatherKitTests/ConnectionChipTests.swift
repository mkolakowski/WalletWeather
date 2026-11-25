import Foundation
import Testing
@testable import WalletWeatherKit

/// The connection chip and what runs behind (connections phase 4, #302).
struct ConnectionChipTests {
    private func server(_ host: String, name: String? = nil, ended: Bool? = nil) -> SavedConnection {
        SavedConnection(connection: Connection(server: URL(string: "https://\(host)")!, token: "t"), name: name,
                        account: "me@example.com", signInEnded: ended)
    }

    private let open = ConnectionsVisibility(locked: false)

    private func chip(_ saved: [SavedConnection], front: LockGate.Front, household: Bool = false,
                      visibility: ConnectionsVisibility? = nil) -> ConnectionChipState? {
        ConnectionChipState.make(saved: saved, front: front, householdExists: household, visibility: visibility ?? open)
    }

    // MARK: - Whether it shows, and what it says

    @Test func oneServerHasNoChip() {
        let home = server("home.example.com", name: "Home")
        #expect(chip([home], front: .saved(home.id)) == nil)
        #expect(chip([], front: .nothing) == nil)
        #expect(chip([home], front: .unsaved) == nil)
    }

    @Test func oneHouseholdAloneHasNoChip() {
        let phone = SavedConnection(connection: LocalServer.connection)
        #expect(chip([phone], front: .saved(phone.id), household: true) == nil)
        #expect(chip([], front: .household, household: true) == nil)
    }

    @Test func twoServersNameTheOneInFront() {
        let home = server("home.example.com", name: "Home")
        let parents = server("ww.parents.example", name: "Mum & Dad")
        #expect(chip([home, parents], front: .saved(parents.id))
            == ConnectionChipState(title: "Mum & Dad", symbol: "server.rack", warning: false))
        #expect(chip([home, parents], front: .saved(home.id))?.title == "Home")
    }

    @Test func aServerAndTheHousehold() {
        let home = server("home.example.com", name: "Home")
        let phone = SavedConnection(connection: LocalServer.connection)
        #expect(chip([home, phone], front: .saved(phone.id), household: true)
            == ConnectionChipState(title: "On this iPhone", symbol: "iphone", warning: false))
        #expect(chip([home, phone], front: .saved(home.id), household: true)?.title == "Home")
        // A household on the phone that isn't saved yet is still a choice.
        #expect(chip([home], front: .saved(home.id), household: true)?.title == "Home")
        #expect(chip([home], front: .household, household: true)?.title == "On this iPhone")
        // With no household on the phone, there's nothing to switch to.
        #expect(chip([home], front: .saved(home.id), household: false) == nil)
    }

    @Test func theDemoInFrontAlwaysHasTheChip() {
        let home = server("home.example.com", name: "Home")
        let demo = ConnectionChipState(title: "Demo · sample numbers", symbol: "sparkles", warning: false)
        #expect(chip([], front: .demo) == demo)
        #expect(chip([home], front: .demo) == demo)
        #expect(chip([home], front: .demo, visibility: ConnectionsVisibility(locked: true)) == demo)
    }

    @Test func anEndedSignInIsMarkedOnTheChip() {
        let home = server("home.example.com", name: "Home")
        let parents = server("ww.parents.example", name: "Mum & Dad", ended: true)
        #expect(chip([home, parents], front: .saved(parents.id))
            == ConnectionChipState(title: "Mum & Dad", symbol: "server.rack", warning: true))
        #expect(chip([home, parents], front: .saved(home.id))?.warning == false)
    }

    @Test func lockedAServerNamedAfterItsAddressReadsServer() {
        let a = server("home.example.com")
        let b = server("ww.parents.example", name: "Mum & Dad")
        let locked = ConnectionsVisibility(locked: true)
        // Never reached while locked (the demo is in front), but the name
        // follows the same rule as the menu.
        #expect(chip([a, b], front: .saved(a.id), visibility: locked)?.title == "Server")
    }

    // MARK: - The ended mark in the rows

    @Test func anEndedConnectionsRowSaysSignInAgain() {
        let home = server("home.example.com", name: "Home")
        let parents = server("ww.parents.example", name: "Mum & Dad", ended: true)
        let rows = ConnectionRow.rows(saved: [home, parents], front: .saved(home.id), householdExists: false, visibility: open)
        #expect(rows.map(\.warning) == [false, true, false])
        #expect(rows[1].detail == "Sign in again")
        #expect(rows[1].name == "Mum & Dad")
        #expect(rows[0].detail == "home.example.com · me@example.com")
        // Locked in the demo it shows too: it reveals nothing.
        let locked = ConnectionRow.rows(saved: [home, parents], front: .demo, householdExists: false,
                                        visibility: ConnectionsVisibility(locked: true))
        #expect(locked.map(\.warning) == [false, true, false])
        #expect(locked[0].detail == nil)
        #expect(locked[1].detail == "Sign in again")
        #expect(locked[1].opensPage == false)
    }

    // MARK: - What runs behind

    @Test func theHouseholdRunsWhateverIsInFront() {
        let a = UUID()
        for front: LockGate.Front in [.saved(a), .household, .demo, .unsaved, .nothing] {
            #expect(HouseholdRuns.mayRun(householdExists: true, protectedDataAvailable: true, front: front))
            #expect(!HouseholdRuns.mayRun(householdExists: false, protectedDataAvailable: true, front: front))
            #expect(!HouseholdRuns.mayRun(householdExists: true, protectedDataAvailable: false, front: front))
            #expect(!HouseholdRuns.mayRun(householdExists: false, protectedDataAvailable: false, front: front))
        }
    }

    // MARK: - Recording and clearing the ended mark

    @Test func savedConnectionsWithoutTheFieldStillDecode() throws {
        let id = UUID()
        let old = """
        {"id":"\(id.uuidString)","kind":"server","name":"Home","added":800000000,"lastUsed":800000000,\
        "connection":{"server":"https:\\/\\/home.example.com","token":"t"},"keep":"nothing"}
        """
        let saved = try JSONDecoder().decode(SavedConnection.self, from: Data(old.utf8))
        #expect(saved.id == id)
        #expect(saved.signInEnded == nil)
        #expect(!saved.needsSignIn)
        // And what's written without it reads back the same.
        let again = try JSONDecoder().decode(SavedConnection.self, from: JSONEncoder().encode(saved))
        #expect(again == saved)
        #expect(!(String(data: try JSONEncoder().encode(saved), encoding: .utf8) ?? "").contains("signInEnded"))
    }

    @Test func theMarkIsRecordedAndClearedBySigningInAgain() throws {
        let suite = "ww-chip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: FileManager.default.temporaryDirectory.appending(path: "chip-\(suite)"))
        let home = try #require(store.add(Connection(server: URL(string: "https://home.example.com")!, token: "old"),
                                          account: "me@example.com"))
        // A late answer to a token that has since been replaced doesn't mark it.
        #expect(store.markSignInEnded(home.id, token: "something-else") == nil)
        #expect(store.load(home.id)?.needsSignIn == false)
        #expect(store.markSignInEnded(home.id, token: "old")?.needsSignIn == true)
        #expect(store.load(home.id)?.signInEnded == true)
        // It survives switching to it (which only notes when it was used).
        #expect(store.activate(home.id)?.needsSignIn == true)
        // A new sign-in clears it, and keeps the rest.
        let renewed = try #require(store.renew(home.id, with: Connection(server: home.connection.server, token: "new"),
                                               account: "me@example.com"))
        #expect(!renewed.needsSignIn)
        #expect(store.load(home.id)?.connection.token == "new")
        // The household is never marked.
        let phone = try #require(store.add(LocalServer.connection))
        #expect(store.markSignInEnded(phone.id, token: nil) == nil)
    }
}
