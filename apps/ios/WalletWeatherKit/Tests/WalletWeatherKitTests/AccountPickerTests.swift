import Foundation
import Testing
@testable import WalletWeatherKit

/// The account picker (account-picker phase 3, #379), which replaced the
/// connection chip of #302, and what runs behind.
struct AccountPickerTests {
    private func server(_ host: String, name: String? = nil, ended: Bool? = nil, person: String? = nil,
                        used: Date = .now) -> SavedConnection {
        SavedConnection(connection: Connection(server: URL(string: "https://\(host)")!, token: "t"), name: name,
                        added: used, account: "me@example.com", signInEnded: ended, personName: person)
    }

    private let open = ConnectionsVisibility(locked: false)

    private func picker(_ saved: [SavedConnection], front: LockGate.Front, beforeDemo: LockGate.Front? = nil,
                        person: Initials.Person? = nil, visibility: ConnectionsVisibility? = nil) -> AccountPickerState? {
        AccountPickerState.make(saved: saved, front: front, beforeDemo: beforeDemo, person: person,
                                visibility: visibility ?? open)
    }

    // MARK: - Whether it shows, and what it shows

    @Test func itShowsWithOneServerToo() {
        let home = server("home.example.com", name: "Home", person: "Pat Smith")
        #expect(picker([home], front: .saved(home.id))
            == AccountPickerState(face: .person(connection: home.id, initials: "PS"), label: "Home"))
        // Nothing in front: the first screen or the sign-in screen.
        #expect(picker([home], front: .nothing) == nil)
        #expect(picker([], front: .nothing) == nil)
    }

    @Test func whatMeSaysWinsOverWhatWasKept() {
        let home = server("home.example.com", name: "Home", person: "Pat Smith")
        #expect(picker([home], front: .saved(home.id), person: Initials.Person(name: "Robin Jones"))?.face
            == .person(connection: home.id, initials: "RJ"))
        // Before its name is known: the email's.
        let unnamed = server("home.example.com")
        #expect(picker([unnamed], front: .saved(unnamed.id))?.face == .person(connection: unnamed.id, initials: "M"))
    }

    @Test func theHouseholdHasTheIPhoneIcon() {
        let phone = SavedConnection(connection: LocalServer.connection)
        let household = AccountPickerState(face: .symbol("iphone"), label: "On this iPhone")
        #expect(picker([phone], front: .saved(phone.id)) == household)
        #expect(picker([], front: .household) == household)
    }

    @Test func aDebugServerShowsItsPersonsInitialsWithoutAPicture() {
        #expect(picker([], front: .unsaved, person: Initials.Person(name: "Pat Smith"))?.face
            == .person(connection: nil, initials: "PS"))
        #expect(picker([], front: .unsaved)?.face == .person(connection: nil, initials: "?"))
    }

    @Test func theDemoShowsThePictureItGoesBackToWithABadge() {
        let home = server("home.example.com", name: "Home", person: "Pat Smith")
        let parents = server("ww.parents.example", name: "Mum & Dad", person: "Robin Jones")
        let badge = AccountPickerState(face: .person(connection: parents.id, initials: "RJ"), demoBadge: true,
                                       label: "Demo, sample numbers")
        #expect(picker([home, parents], front: .demo, beforeDemo: .saved(parents.id)) == badge)
        // Locked in the demo, the same (decided 2026-11-25).
        #expect(picker([home, parents], front: .demo, beforeDemo: .saved(parents.id),
                       visibility: ConnectionsVisibility(locked: true)) == badge)
    }

    @Test func theDemoWithNothingBeforeItShowsTheServerUsedLast() {
        let home = server("home.example.com", name: "Home", person: "Pat Smith", used: .now)
        let parents = server("ww.parents.example", name: "Mum & Dad", used: .now.addingTimeInterval(-60))
        #expect(picker([home, parents], front: .demo, beforeDemo: .nothing)?.face
            == .person(connection: home.id, initials: "PS"))
        #expect(picker([home, parents], front: .demo)?.demoBadge == true)
    }

    @Test func theDemoAloneOrBeforeTheHouseholdHasItsSparkles() {
        let home = server("home.example.com", name: "Home")
        let phone = SavedConnection(connection: LocalServer.connection)
        let sparkles = AccountPickerState(face: .symbol("sparkles"), label: "Demo, sample numbers")
        #expect(picker([], front: .demo) == sparkles)
        #expect(picker([phone], front: .demo, beforeDemo: .saved(phone.id)) == sparkles)
        #expect(picker([home, phone], front: .demo, beforeDemo: .household) == sparkles)
        // A server since signed out of: the one used last.
        #expect(picker([home], front: .demo, beforeDemo: .saved(UUID())) == sparkles)
    }

    @Test func anEndedSignInIsMarkedOnTheButton() {
        let home = server("home.example.com", name: "Home")
        let parents = server("ww.parents.example", name: "Mum & Dad", ended: true)
        #expect(picker([home, parents], front: .saved(parents.id))?.warning == true)
        #expect(picker([home, parents], front: .saved(home.id))?.warning == false)
    }

    @Test func lockedAServerNamedAfterItsAddressReadsServer() {
        let a = server("home.example.com")
        let b = server("ww.parents.example", name: "Mum & Dad")
        let locked = ConnectionsVisibility(locked: true)
        // Never reached while locked (the demo is in front), but the name
        // follows the same rule as the menu.
        #expect(picker([a, b], front: .saved(a.id), visibility: locked)?.label == "Server")
        #expect(picker([a, b], front: .saved(a.id))?.label == "home.example.com")
    }

    // MARK: - Initials, as the web app writes them

    @Test func initialsFollowTheWebApp() {
        #expect(Initials.of(.init(name: "Pat Smith")) == "PS")
        #expect(Initials.of(.init(name: "  pat   q smith ")) == "PQ")
        #expect(Initials.of(.init(name: "Cher", email: "x@example.com")) == "C")
        #expect(Initials.of(.init(name: "", email: "pat.smith+ww@example.com")) == "PS")
        #expect(Initials.of(.init(email: "you@example.com")) == "Y")
        #expect(Initials.of(.init(name: "Élodie Ørsted")) == "ÉØ")
        #expect(Initials.of(.init()) == "?")
        #expect(Initials.of(.init(email: "+@x")) == "?")
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
        let suite = "ww-picker-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: FileManager.default.temporaryDirectory.appending(path: "picker-\(suite)"))
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
