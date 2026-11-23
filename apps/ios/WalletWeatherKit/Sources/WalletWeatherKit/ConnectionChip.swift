import Foundation

/// The connection chip (Plans/connections.md, phase 4, #302): what it says
/// and whether it shows. It sits under the Dashboard's title and at the top
/// of Settings (decided 2026-11-23), names the connection in front with a
/// small icon, and opens the menu of the connections. It is the demo's chip
/// of phase 3 made general: the demo's reads "Demo · sample numbers".
///
/// It shows only when there is something to switch between: two or more
/// connections (the saved ones, plus the household on this iPhone when it
/// isn't saved yet), or the demo in front, which is the way out of it. With
/// one connection, and not in the demo, there is no chip, so there is no
/// switch for it in Settings: people with one connection never see it.
public struct ConnectionChipState: Equatable, Sendable {
    /// What the chip says: the connection's name, "On this iPhone" or
    /// "Demo · sample numbers".
    public let title: String
    /// The small icon before it.
    public let symbol: String
    /// The connection in front has had its sign-in end: the chip carries
    /// `ConnectionRow.warningSymbol` too.
    public let warning: Bool

    public static let demoTitle = "Demo · sample numbers"

    /// The chip for what's in front, or nil when none shows. Locked in the
    /// demo (`visibility`), a server still named after its address reads
    /// "Server", as in the menu.
    public static func make(saved: [SavedConnection], front: LockGate.Front, householdExists: Bool,
                            visibility: ConnectionsVisibility) -> ConnectionChipState? {
        switch front {
        case .demo:
            return ConnectionChipState(title: demoTitle, symbol: "sparkles", warning: false)
        case .nothing, .unsaved:
            return nil
        case .household, .saved:
            break
        }
        let savedHousehold = saved.contains { $0.kind == .thisPhone }
        // What Connections lists, the demo apart.
        let choices = saved.count + (savedHousehold || !(householdExists || front == .household) ? 0 : 1)
        guard choices >= 2 else { return nil }
        switch front {
        case let .saved(id):
            guard let connection = saved.first(where: { $0.id == id }) else { return nil }
            return ConnectionChipState(title: visibility.name(of: connection, among: saved),
                                       symbol: connection.kind == .server ? "server.rack" : "iphone",
                                       warning: connection.needsSignIn)
        default:
            return ConnectionChipState(title: "On this iPhone", symbol: "iphone", warning: false)
        }
    }
}

/// When the household on this iPhone's iCloud Drive backup and bank sync
/// may run (#302). The household is one store on the phone whatever is in
/// front, so they run when they're due with a server in front, the demo in
/// front (locked or not) or nothing in front, as with the household in
/// front. They need a household, and the phone's protected data (the
/// store can't be read while the phone is locked).
public enum HouseholdRuns {
    public static func mayRun(householdExists: Bool, protectedDataAvailable: Bool, front: LockGate.Front) -> Bool {
        // `front` doesn't change the answer: that is the rule.
        _ = front
        return householdExists && protectedDataAvailable
    }
}
