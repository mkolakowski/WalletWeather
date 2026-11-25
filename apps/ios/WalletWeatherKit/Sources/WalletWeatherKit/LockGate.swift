import Foundation

// The lock and the demo (Plans/connections.md, phase 3, #301; decided
// 2026-11-23, docs/dev/decisions/ios-review.md): with the lock on and "When
// locked, show the demo" on, the app opens in the demo, and goes back to it
// after a minute away. It stays there until a real connection is chosen,
// which asks for Face ID or Touch ID (the passcode behind it). With the
// switch off, a locked app shows the lock screen as before. The app keeps
// one `LockGate` and asks it; the rules are here so the tests can check them.

/// When the lock falls due, what the app shows, and what leaving the demo
/// needs.
public struct LockGate: Equatable, Sendable {
    /// Away this long or more and the lock falls due again (the lock's clock
    /// since 2026-11-14).
    public static let lockAfter: TimeInterval = 60

    /// What's in front of the app, as the lock sees it.
    public enum Front: Hashable, Sendable {
        /// A saved connection: a server, or the household on this iPhone.
        case saved(UUID)
        /// The household on this iPhone, in front but not saved (the
        /// Keychain wouldn't take it).
        case household
        case demo
        /// A sign-in that isn't saved: one kept before connections that
        /// couldn't be carried over, or a Debug launch's server. The demo
        /// can't lead back to it, so the lock screen covers it instead.
        case unsaved
        /// Nothing: the first screen or the sign-in screen.
        case nothing

        /// A connection with someone's own numbers.
        public var isReal: Bool {
            switch self {
            case .saved, .household, .unsaved: true
            case .demo, .nothing: false
            }
        }
    }

    /// What the app shows when the lock falls due.
    public enum Show: Equatable, Sendable {
        /// What it showed: nothing to hide (the first screen, the lock off).
        case asItIs
        /// The lock screen over the app, as before #301.
        case lockScreen
        /// The demo, in front until a real connection is chosen.
        case demo
    }

    /// What the lock did, and what the demo leads back to.
    public struct Decision: Equatable, Sendable {
        public var show: Show
        /// What was in front before the demo, for the demo to go back to;
        /// nil when the demo isn't shown.
        public var remember: Front?

        public init(show: Show, remember: Front? = nil) {
            self.show = show
            self.remember = remember
        }
    }

    public var lockOn: Bool
    /// Settings → Privacy & lock → When locked, show the demo.
    public var showsDemo: Bool
    /// The lock sent the app to the demo and nobody has unlocked since:
    /// opening a real connection asks first.
    public private(set) var lockedInDemo: Bool

    public init(lockOn: Bool, showsDemo: Bool, lockedInDemo: Bool = false) {
        self.lockOn = lockOn
        self.showsDemo = showsDemo
        self.lockedInDemo = lockOn && lockedInDemo
    }

    /// Whether coming back after `away` seconds locks again. Nil is a fresh
    /// start, which always does.
    public static func isDue(away: TimeInterval?) -> Bool {
        guard let away else { return true }
        return away >= lockAfter
    }

    /// The app starts (`away` nil) or comes back after `away` seconds with
    /// `front` in front; `beforeDemo` is what was in front before the demo,
    /// when the demo is. Within the minute nothing changes.
    public mutating func comeBack(away: TimeInterval?, front: Front, beforeDemo: Front? = nil) -> Decision {
        guard lockOn, Self.isDue(away: away) else { return Decision(show: .asItIs) }
        guard showsDemo else { return Decision(show: .lockScreen) }
        switch front {
        case .nothing:
            // The first screen shows no one's numbers.
            return Decision(show: .asItIs)
        case .unsaved:
            return Decision(show: .lockScreen)
        case .demo:
            lockedInDemo = true
            return Decision(show: .demo, remember: beforeDemo ?? .nothing)
        case .saved, .household:
            lockedInDemo = true
            return Decision(show: .demo, remember: front)
        }
    }

    /// Whether opening `target` asks for Face ID, Touch ID or the passcode
    /// first: any real connection while locked in the demo. Unlocked,
    /// switching asks for nothing.
    public func needsAuthentication(toOpen target: Front) -> Bool {
        lockedInDemo && target.isReal
    }

    /// Whether anything else that leaves the demo for someone's numbers
    /// (adding a server, setting up or restoring the household on this
    /// iPhone, a link from the web app) asks first.
    public var leavingNeedsAuthentication: Bool { lockedInDemo }

    /// Whether turning the lock off, or the demo switch off, asks first: it
    /// would open the numbers to whoever holds the phone.
    public var changingTheLockNeedsAuthentication: Bool { lockedInDemo }

    /// Face ID, Touch ID or the passcode said yes.
    public mutating func authenticated() {
        lockedInDemo = false
    }

    /// The lock or the demo switch was turned off (after asking, when locked
    /// in the demo): nothing is locked in the demo any more.
    public mutating func turnedOff() {
        lockedInDemo = false
    }
}

// MARK: - What Connections shows (phase 3)

/// What Connections and the demo's chip may show about the saved
/// connections. Locked in the demo, the phone may be in someone else's
/// hands: names and icons only, a server's name hidden when it's still its
/// address, and no connection's own page (its address, who's signed in,
/// Sign out, its name, Keep on this iPhone) until unlocked.
public struct ConnectionsVisibility: Equatable, Sendable {
    public var locked: Bool

    public init(locked: Bool) {
        self.locked = locked
    }

    /// A line of detail under each name: the host and who's signed in.
    public var showsDetail: Bool { !locked }

    /// The ⓘ beside a connection, opening its own page.
    public var opensConnectionPages: Bool { !locked }

    /// The name shown for a saved connection. Locked, a server still named
    /// after its address reads "Server" instead (numbered when there are
    /// more), since its address is one of the details hidden.
    public func name(of saved: SavedConnection, among all: [SavedConnection]) -> String {
        guard locked, saved.kind == .server,
              saved.name == SavedConnection.defaultName(for: saved.connection) else { return saved.name }
        let unnamed = all.filter { $0.kind == .server && $0.name == SavedConnection.defaultName(for: $0.connection) }
        guard unnamed.count > 1, let place = unnamed.firstIndex(where: { $0.id == saved.id }) else { return "Server" }
        return "Server \(place + 1)"
    }
}

/// One row of Connections, or of the demo chip's menu: a saved connection,
/// On this iPhone when it's on the phone but not saved, or the demo, always
/// last.
public struct ConnectionRow: Equatable, Identifiable, Sendable {
    public enum Target: Hashable, Sendable {
        case saved(UUID)
        /// The household on this iPhone, not saved: open the one already on
        /// the phone.
        case thisIPhone
        case demo
    }

    public let target: Target
    public let name: String
    /// The line under the name; nil when hidden.
    public let detail: String?
    public let symbol: String
    /// In front.
    public let ticked: Bool
    /// The ⓘ opening its own page.
    public let opensPage: Bool
    /// Its sign-in has ended (#302): a small warning symbol, and "Sign in
    /// again" as the detail. Shown locked in the demo too: it says nothing
    /// of the numbers.
    public let warning: Bool
    /// What swiping it shows (#376), in order.
    public let swipes: [Swipe]

    /// A row's swipe actions in Connections (#376): Edit opens its own page
    /// (where it's renamed); Sign out signs out of a server and takes it off
    /// the phone, after asking. The household on this iPhone has Edit only,
    /// since taking it off would erase its numbers (that stays on its page,
    /// as Delete everything). The demo, the phone before it's saved, and
    /// every row while locked in the demo have none.
    public enum Swipe: Hashable, Sendable {
        case edit, signOut
    }

    public var id: Target { target }

    /// The small warning symbol beside a connection whose sign-in ended, in
    /// Connections, the chip's menu and the chip.
    public static let warningSymbol = "exclamationmark.triangle.fill"
    public static let signInAgainDetail = "Sign in again"

    public static let demoName = "Demo"
    public static let demoDetail = "Sample numbers · nothing is saved"

    /// Connections' rows, top to bottom: the saved connections (oldest
    /// first, as the store lists them), On this iPhone when it's on the
    /// phone but isn't one of them, then the demo. `householdExists` is whether a household is on
    /// the phone already; `email` is who's signed in to the one in front.
    public static func rows(saved: [SavedConnection], front: LockGate.Front, householdExists: Bool,
                            email: String? = nil, visibility: ConnectionsVisibility) -> [ConnectionRow] {
        var rows = saved.map { connection -> ConnectionRow in
            let inFront = front == .saved(connection.id)
            let detail: String? = switch connection.kind {
            case .server:
                visibility.showsDetail ? SettingsLayout.connectionDetail(connection, email: inFront ? email : nil) : nil
            case .thisPhone:
                SettingsLayout.connectionDetail(connection)
            }
            return ConnectionRow(target: .saved(connection.id), name: visibility.name(of: connection, among: saved),
                                 detail: connection.needsSignIn ? signInAgainDetail : detail,
                                 symbol: connection.kind == .server ? "server.rack" : "iphone",
                                 ticked: inFront, opensPage: visibility.opensConnectionPages,
                                 warning: connection.needsSignIn,
                                 swipes: !visibility.opensConnectionPages ? []
                                     : connection.kind == .server ? [.edit, .signOut] : [.edit])
        }
        // Listed once it's set up (#373): until then Use on this iPhone is
        // an action under Add a server, not a connection.
        if !saved.contains(where: { $0.kind == .thisPhone }), householdExists || front == .household {
            rows.append(ConnectionRow(target: .thisIPhone, name: "On this iPhone",
                                      detail: "Your household, with no server",
                                      symbol: "iphone", ticked: front == .household, opensPage: false,
                                      warning: false, swipes: []))
        }
        rows.append(ConnectionRow(target: .demo, name: demoName, detail: demoDetail, symbol: "sparkles",
                                  ticked: front == .demo, opensPage: false, warning: false, swipes: []))
        return rows
    }

    /// What choosing this row opens, as the lock sees it.
    public var front: LockGate.Front {
        switch target {
        case let .saved(id): .saved(id)
        case .thisIPhone: .household
        case .demo: .demo
        }
    }
}
