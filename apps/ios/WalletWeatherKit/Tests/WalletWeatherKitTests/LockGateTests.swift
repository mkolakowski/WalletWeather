import Foundation
import Testing
@testable import WalletWeatherKit

/// The lock and the demo (connections phase 3, #301): with the lock on and
/// When locked, show the demo on, the app opens in the demo and goes back to
/// it after a minute away; a real connection then asks for Face ID first.
struct LockGateTests {
    let home = UUID()

    // MARK: - When the lock falls due

    @Test func lockedMeansTheDemoIsInFront() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        let launch = gate.comeBack(away: nil, front: .saved(home))
        #expect(launch == LockGate.Decision(show: .demo, remember: .saved(home)))
        #expect(gate.lockedInDemo)
        // The household on this iPhone, saved or not, is remembered too.
        var phone = LockGate(lockOn: true, showsDemo: true)
        #expect(phone.comeBack(away: nil, front: .household) == LockGate.Decision(show: .demo, remember: .household))
    }

    @Test func theMinuteAway() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        // Back within the minute: nothing changes.
        #expect(gate.comeBack(away: 59, front: .saved(home)) == LockGate.Decision(show: .asItIs))
        #expect(!gate.lockedInDemo)
        // A minute or more: the demo.
        #expect(gate.comeBack(away: 60, front: .saved(home)) == LockGate.Decision(show: .demo, remember: .saved(home)))
        #expect(gate.lockedInDemo)
        #expect(LockGate.isDue(away: nil))
        #expect(!LockGate.isDue(away: 10))
        #expect(LockGate.isDue(away: LockGate.lockAfter))
    }

    /// Already in the demo (chosen, or locked there): it stays, and still
    /// leads back to what was in front before it.
    @Test func inTheDemoAlreadyItRemembersWhatWasBefore() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        #expect(gate.comeBack(away: 120, front: .demo, beforeDemo: .saved(home))
                == LockGate.Decision(show: .demo, remember: .saved(home)))
        #expect(gate.lockedInDemo)
        var fresh = LockGate(lockOn: true, showsDemo: true)
        #expect(fresh.comeBack(away: 120, front: .demo) == LockGate.Decision(show: .demo, remember: .nothing))
    }

    @Test func theLockOffOrTheSwitchOff() {
        var off = LockGate(lockOn: false, showsDemo: true)
        #expect(off.comeBack(away: nil, front: .saved(home)) == LockGate.Decision(show: .asItIs))
        #expect(off.comeBack(away: 600, front: .saved(home)) == LockGate.Decision(show: .asItIs))
        #expect(!off.lockedInDemo)
        // The switch off: the lock screen, as before #301.
        var plain = LockGate(lockOn: true, showsDemo: false)
        #expect(plain.comeBack(away: nil, front: .saved(home)) == LockGate.Decision(show: .lockScreen))
        #expect(plain.comeBack(away: 60, front: .household) == LockGate.Decision(show: .lockScreen))
        #expect(!plain.lockedInDemo)
        // A lock that's off can't be locked in the demo.
        #expect(!LockGate(lockOn: false, showsDemo: true, lockedInDemo: true).lockedInDemo)
    }

    /// The first screen shows no one's numbers; a sign-in the demo can't
    /// lead back to gets the lock screen.
    @Test func nothingInFrontOrASignInThatIsNotSaved() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        #expect(gate.comeBack(away: nil, front: .nothing) == LockGate.Decision(show: .asItIs))
        #expect(!gate.lockedInDemo)
        #expect(gate.comeBack(away: nil, front: .unsaved) == LockGate.Decision(show: .lockScreen))
        #expect(!gate.lockedInDemo)
    }

    // MARK: - Leaving the demo

    @Test func unlockingOpensTheConnectionChosen() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        _ = gate.comeBack(away: nil, front: .saved(home))
        // Locked: every real connection asks; the demo itself doesn't.
        #expect(gate.needsAuthentication(toOpen: .saved(home)))
        #expect(gate.needsAuthentication(toOpen: .saved(UUID())))
        #expect(gate.needsAuthentication(toOpen: .household))
        #expect(!gate.needsAuthentication(toOpen: .demo))
        #expect(gate.leavingNeedsAuthentication)
        #expect(gate.changingTheLockNeedsAuthentication)
        gate.authenticated()
        // Unlocked: switching asks for nothing, as in phase 2.
        #expect(!gate.lockedInDemo)
        #expect(!gate.needsAuthentication(toOpen: .saved(home)))
        #expect(!gate.leavingNeedsAuthentication)
        #expect(!gate.changingTheLockNeedsAuthentication)
    }

    @Test func turningTheLockOffUnlocks() {
        var gate = LockGate(lockOn: true, showsDemo: true)
        _ = gate.comeBack(away: nil, front: .saved(home))
        gate.turnedOff()
        #expect(!gate.lockedInDemo)
        #expect(!gate.needsAuthentication(toOpen: .household))
    }

    @Test func neverLockedNothingAsks() {
        let gate = LockGate(lockOn: true, showsDemo: true)
        #expect(!gate.needsAuthentication(toOpen: .saved(home)))
        #expect(!gate.leavingNeedsAuthentication)
    }

    // MARK: - What Connections shows

    private func server(_ host: String, name: String? = nil, account: String? = "me@example.com") -> SavedConnection {
        SavedConnection(connection: Connection(server: URL(string: "https://\(host)")!, token: "t"), name: name, account: account)
    }

    @Test func connectionsRowsWithServersTheHouseholdAndTheDemo() {
        let a = server("home.example.com", name: "Home")
        let b = server("ww.parents.example", name: "Mum & Dad")
        let phone = SavedConnection(connection: LocalServer.connection)
        let rows = ConnectionRow.rows(saved: [a, b, phone], front: .saved(a.id), householdExists: true,
                                      email: "now@example.com", visibility: ConnectionsVisibility(locked: false))
        #expect(rows.map(\.target) == [.saved(a.id), .saved(b.id), .saved(phone.id), .demo])
        #expect(rows.map(\.name) == ["Home", "Mum & Dad", "On this iPhone", "Demo"])
        #expect(rows.map(\.detail) == ["home.example.com · now@example.com", "ww.parents.example · me@example.com",
                                       "Your household, with no server", "Sample numbers · nothing is saved"])
        #expect(rows.map(\.symbol) == ["server.rack", "server.rack", "iphone", "sparkles"])
        #expect(rows.map(\.ticked) == [true, false, false, false])
        #expect(rows.map(\.opensPage) == [true, true, true, false])
        #expect(rows.map(\.front) == [.saved(a.id), .saved(b.id), .saved(phone.id), .demo])
    }

    @Test func connectionsRowsWithNoHouseholdYet() {
        let a = server("home.example.com", name: "Home")
        let rows = ConnectionRow.rows(saved: [a], front: .saved(a.id), householdExists: false,
                                      visibility: ConnectionsVisibility(locked: false))
        #expect(rows.map(\.target) == [.saved(a.id), .thisIPhone, .demo])
        #expect(rows[1].name == "Use on this iPhone")
        #expect(rows[1].detail == "A household kept on this iPhone, with no server")
        #expect(rows[1].front == .household)
        #expect(!rows[1].ticked)
        // A household on the phone but not among the saved ones opens as it is.
        let kept = ConnectionRow.rows(saved: [a], front: .saved(a.id), householdExists: true,
                                      visibility: ConnectionsVisibility(locked: false))
        #expect(kept[1].name == "On this iPhone")
        #expect(kept[1].detail == "Your household, with no server")
        // Nothing saved at all: On this iPhone and the demo.
        let none = ConnectionRow.rows(saved: [], front: .nothing, householdExists: false,
                                      visibility: ConnectionsVisibility(locked: false))
        #expect(none.map(\.target) == [.thisIPhone, .demo])
    }

    @Test func connectionsRowsWithTheDemoInFront() {
        let a = server("home.example.com", name: "Home")
        let phone = SavedConnection(connection: LocalServer.connection)
        let rows = ConnectionRow.rows(saved: [a, phone], front: .demo, householdExists: true,
                                      visibility: ConnectionsVisibility(locked: false))
        #expect(rows.map(\.ticked) == [false, false, true])
        #expect(rows.last?.target == .demo)
    }

    /// Locked in the demo: names and icons only, no address or email, no
    /// connection's own page; a server still named after its address shows
    /// as "Server".
    @Test func lockedConnectionsShowNamesAndIconsOnly() {
        let named = server("home.example.com", name: "Home")
        let bare = server("ww.parents.example")
        let other = server("ww.work.example")
        let phone = SavedConnection(connection: LocalServer.connection)
        let locked = ConnectionsVisibility(locked: true)
        let rows = ConnectionRow.rows(saved: [named, bare, other, phone], front: .demo, householdExists: true,
                                      email: "me@example.com", visibility: locked)
        #expect(rows.map(\.name) == ["Home", "Server 1", "Server 2", "On this iPhone", "Demo"])
        #expect(rows.map(\.detail) == [nil, nil, nil, "Your household, with no server", "Sample numbers · nothing is saved"])
        #expect(rows.allSatisfy { !$0.opensPage })
        for row in rows {
            #expect(!row.name.contains("example"), "\(row.name)")
            #expect(!(row.detail ?? "").contains("@"), "\(row.detail ?? "")")
        }
        #expect(rows.map(\.symbol) == ["server.rack", "server.rack", "server.rack", "iphone", "sparkles"])
        // One server named after its address: plain "Server".
        #expect(locked.name(of: bare, among: [named, bare]) == "Server")
        #expect(!locked.showsDetail)
        #expect(!locked.opensConnectionPages)
        // Unlocked, the address is its name again.
        #expect(ConnectionsVisibility(locked: false).name(of: bare, among: [bare]) == "ww.parents.example")
    }
}
