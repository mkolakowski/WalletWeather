import Foundation

/// The account picker (Plans/account-picker.md, phase 3, #379): a round
/// button among the bar's buttons at the top right of the Dashboard and
/// Settings (#383), in place of the connection chip of #302 (decided
/// 2026-11-25). It shows
/// the picture of whoever is signed in to the server in front (their
/// initials until one is set), and opens the menu of the connections the
/// chip had.
///
/// - A server in front: its person's picture or initials.
/// - The household on this iPhone in front: the iPhone icon (it has no
///   picture).
/// - The demo in front: the picture (or initials) of the server the demo
///   goes back to, with a small sparkles badge, also while locked in the
///   demo (decided 2026-11-25); the demo's sparkles alone when the demo goes
///   back to no server.
/// - A Debug launch's server, which isn't saved: its person's initials.
///
/// It shows whenever something is in front, with one connection too
/// (decided 2026-11-25): there is no setting for it.
public struct AccountPickerState: Equatable, Sendable {
    /// What the round button shows.
    public enum Face: Equatable, Sendable {
        /// A person: the picture kept with this saved server when there is
        /// one (nil: not saved, so none is kept), else these initials.
        case person(connection: UUID?, initials: String)
        /// An icon: the household on this iPhone, or the demo's sparkles.
        case symbol(String)
    }

    public let face: Face
    /// The demo is in front: a small sparkles badge on the face.
    public let demoBadge: Bool
    /// The connection in front has had its sign-in end: the button carries
    /// `ConnectionRow.warningSymbol` too.
    public let warning: Bool
    /// What VoiceOver reads: the connection's name, "On this iPhone" or
    /// "Demo, sample numbers".
    public let label: String

    public static let demoLabel = "Demo, sample numbers"

    public init(face: Face, demoBadge: Bool = false, warning: Bool = false, label: String) {
        self.face = face
        self.demoBadge = demoBadge
        self.warning = warning
        self.label = label
    }

    /// The button for what's in front, or nil when nothing is.
    /// `beforeDemo` is what leaving the demo goes back to; `person` is who
    /// `/api/me` says is signed in to the connection in front, fresher than
    /// what the saved connection last recorded. Locked in the demo
    /// (`visibility`), a server still named after its address reads
    /// "Server", as in the menu.
    public static func make(saved: [SavedConnection], front: LockGate.Front, beforeDemo: LockGate.Front?,
                            person: Initials.Person? = nil, visibility: ConnectionsVisibility) -> AccountPickerState? {
        switch front {
        case .nothing:
            return nil
        case .unsaved:
            return AccountPickerState(face: .person(connection: nil, initials: Initials.of(person ?? Initials.Person())),
                                      label: "Server")
        case .household:
            return AccountPickerState(face: .symbol("iphone"), label: "On this iPhone")
        case let .saved(id):
            guard let connection = saved.first(where: { $0.id == id }) else { return nil }
            guard connection.kind == .server else {
                return AccountPickerState(face: .symbol("iphone"), label: "On this iPhone")
            }
            return AccountPickerState(face: .person(connection: id, initials: Initials.of(person ?? connection.person)),
                                      warning: connection.needsSignIn,
                                      label: visibility.name(of: connection, among: saved))
        case .demo:
            guard let back = demoGoesBackTo(saved: saved, beforeDemo: beforeDemo) else {
                return AccountPickerState(face: .symbol("sparkles"), label: demoLabel)
            }
            return AccountPickerState(face: .person(connection: back.id, initials: Initials.of(back.person)),
                                      demoBadge: true, label: demoLabel)
        }
    }

    /// The saved server whose picture the demo shows: the one leaving the
    /// demo goes back to; when the demo was opened with nothing in front,
    /// the server used last. Nil when the demo goes back to the household
    /// on this iPhone, or there is no server.
    public static func demoGoesBackTo(saved: [SavedConnection], beforeDemo: LockGate.Front?) -> SavedConnection? {
        let servers = saved.filter { $0.kind == .server }
        switch beforeDemo {
        case let .saved(id)?:
            return servers.first { $0.id == id }
        case .household?:
            return nil
        case .demo?, .unsaved?, .nothing?, nil:
            return servers.max { ($0.lastUsed, $0.added) < ($1.lastUsed, $1.added) }
        }
    }
}

/// A person's initials, as the web app's account button writes them
/// (`_userInitials`, #288): the first letters of the first two words of
/// their name, else of their email's name before any `+`, upper case; "?"
/// when there's neither.
public enum Initials {
    public struct Person: Equatable, Sendable {
        public var name: String?
        public var email: String?

        public init(name: String? = nil, email: String? = nil) {
            self.name = name
            self.email = email
        }
    }

    public static func of(_ person: Person) -> String {
        let name = (person.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let words: [Substring]
        if !name.isEmpty {
            words = name.split(whereSeparator: \.isWhitespace)
        } else {
            let local = (person.email ?? "").split(separator: "@", omittingEmptySubsequences: false).first ?? ""
            let beforePlus = local.split(separator: "+", omittingEmptySubsequences: false).first ?? ""
            words = beforePlus.split { !($0.isLetter || $0.isNumber) }
        }
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

extension SavedConnection {
    /// Who's signed in to it, as far as the phone last heard.
    public var person: Initials.Person { Initials.Person(name: personName, email: account) }
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
