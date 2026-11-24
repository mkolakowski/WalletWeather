import Foundation

// Copy to a server (#328, idea F11 of the iOS review): the household on this
// iPhone copied to a saved server connection, inside the app, with no file.
//
// - The payload is the backup Export for a server seals (`backupPayload`),
//   sent as it is: over the connection's HTTPS, under its own sign-in token,
//   with no passphrase. The server's `POST /api/backup/import` takes a plain
//   backup as well as a sealed one (`unwrap` in apps/server/app/backup.py),
//   so nothing new is needed there.
// - The chosen connection's own token is used; the one in front (the
//   household) stays in front.
// - Add to what's there (merge) or Replace what's there (replace) is asked
//   before anything is sent, as the web app's Restore asks. Neither is
//   chosen to start with.
// - This iPhone keeps its copy: nothing here deletes anything on the phone.

/// What happens to what's already on the server.
public enum CopyMode: String, CaseIterable, Identifiable, Sendable {
    /// Keep the server's numbers and add these beside them.
    case merge
    /// Delete the server's accounts, categories and tags first.
    case replace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .merge: "Add to what's there"
        case .replace: "Replace what's there"
        }
    }

    /// One line under the title, after the web app's Restore ("Merge (add to
    /// existing)", "Replace (wipe my data first)").
    public var detail: String {
        switch self {
        case .merge: "Merge: the server keeps its numbers, and these are added beside them."
        case .replace: "Replace: the server's accounts, categories and tags are deleted first."
        }
    }
}

/// What goes: counted from the household's own backup.
public struct CopyContents: Equatable, Sendable {
    public let accounts, bills, lines, transfers: Int

    public init(accounts: Int, bills: Int, lines: Int, transfers: Int) {
        self.accounts = accounts
        self.bills = bills
        self.lines = lines
        self.transfers = transfers
    }

    /// Counted from a backup in the server's format (`backupPayload`).
    public init(payload: [String: Any]) {
        let accounts = payload["accounts"] as? [[String: Any]] ?? []
        self.accounts = accounts.count
        bills = accounts.reduce(0) { $0 + ($1["recurring"] as? [Any] ?? []).count }
        lines = accounts.reduce(0) { $0 + ($1["transactions"] as? [Any] ?? []).count }
        transfers = (payload["transfers"] as? [Any] ?? []).count
    }

    public var isEmpty: Bool { accounts == 0 }

    /// "2 accounts, 6 bills and income, 6 lines and 1 transfer".
    public var summary: String {
        CopyAnswer.list(accounts: accounts, bills: bills, lines: lines, transfers: transfers)
    }
}

/// The household's backup, written as JSON once, ready to send.
public struct CopyPayload: Sendable {
    /// The backup as JSON. Never logged: it is the household.
    public let json: Data
    public let contents: CopyContents

    public init(_ payload: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(payload) else { throw CopyRefusal.notABackup }
        json = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        contents = CopyContents(payload: payload)
    }

    /// The household on this phone, as Export for a server builds it.
    public init(household: LocalServer, now: Date = .now) throws {
        try self.init(household.backupPayload(now: now))
    }

    /// The request's body: `{"mode": …, "payload": …}`, the payload as it
    /// was written, with no passphrase (it isn't sealed).
    func body(mode: CopyMode) -> Data {
        Data("{\"mode\":\"\(mode.rawValue)\",\"payload\":".utf8) + json + Data("}".utf8)
    }
}

/// `POST /api/backup/import`'s answer: what the server made.
public struct CopyAnswer: Decodable, Equatable, Sendable {
    public struct Imported: Decodable, Equatable, Sendable {
        public let accounts: Int
        public let recurring: Int
        public let transactions: Int
        public let transfers: Int?
        public let categories: Int?
        public let tags: Int?
    }

    public let ok: Bool
    public let imported: Imported
    /// False for what the app sends: a plain backup.
    public let encrypted: Bool?

    /// "Copied 2 accounts, 6 bills and income, 6 lines and 1 transfer to Home."
    public func summary(to name: String) -> String {
        "Copied " + Self.list(accounts: imported.accounts, bills: imported.recurring, lines: imported.transactions,
                              transfers: imported.transfers ?? 0) + " to \(name)."
    }

    static func list(accounts: Int, bills: Int, lines: Int, transfers: Int) -> String {
        func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        var parts = [plural(accounts, "account", "accounts"), "\(bills) bills and income", plural(lines, "line", "lines")]
        if transfers > 0 { parts.append(plural(transfers, "transfer", "transfers")) }
        let last = parts.removeLast()
        return parts.joined(separator: ", ") + " and " + last
    }
}

/// Why a connection can't be copied to.
public enum CopyRefusal: Error, Equatable, Sendable {
    /// Not a server: the household on this iPhone, or the demo.
    case notAServer
    /// Its sign-in has ended: Sign in again first.
    case signInEnded
    /// Its token is read-only.
    case readOnly
    /// The household couldn't be written as a backup.
    case notABackup

    /// As a problem for the banner (#311): the read-only answer is the one
    /// the server would give; an ended sign-in offers signing in again.
    public var problem: APIError {
        switch self {
        case .signInEnded: .tokenExpired
        case .readOnly:
            .server(status: 403, detail: "This connection is signed in read-only, so nothing can be copied to it. Sign in there with full access, then copy")
        case .notAServer:
            .server(status: 400, detail: "Only a server can be copied to")
        case .notABackup:
            .unexpectedResponse("Your numbers couldn't be written as a backup")
        }
    }
}

// MARK: - Where to

/// Whether Move to a server offers Copy to a server, and why not.
public enum CopyAvailability: Equatable, Sendable {
    case available
    /// No household on this iPhone yet.
    case noHousehold
    /// No server saved to copy to.
    case noServer
    /// The demo is in front (the lock sent the app there): not offered.
    case hidden

    public static func decide(householdExists: Bool, saved: [SavedConnection], demoInFront: Bool) -> CopyAvailability {
        if demoInFront { return .hidden }
        if !householdExists { return .noHousehold }
        if !saved.contains(where: { $0.kind == .server }) { return .noServer }
        return .available
    }

    /// The footnote under a disabled row.
    public var footnote: String? {
        switch self {
        case .available, .hidden: nil
        case .noHousehold: "Set up your numbers on this iPhone first."
        case .noServer: "Sign in to a server first: Settings → Connection → Add a server. This iPhone's numbers stay in front."
        }
    }
}

/// A server Copy to a server may be pointed at.
public struct CopyDestination: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    /// Who's signed in there, or "Sign in again".
    public let detail: String?
    /// False while its sign-in has ended.
    public let pickable: Bool

    /// The saved servers, oldest first; the household and the demo aren't
    /// destinations.
    public static func list(_ saved: [SavedConnection]) -> [CopyDestination] {
        saved.filter { $0.kind == .server }.map { s in
            CopyDestination(id: s.id, name: s.name,
                            detail: s.needsSignIn ? ConnectionRow.signInAgainDetail : s.account,
                            pickable: !s.needsSignIn)
        }
    }
}

// MARK: - Copying

/// One copy to one saved server, under that server's own sign-in. Nothing
/// is put in front or saved.
public struct ServerCopy: Sendable {
    public let destination: SavedConnection
    let client: APIClient

    /// Refuses the household, the demo, and a server whose sign-in has
    /// ended. `signInEnded` is told when the server answers that it has.
    public init(to saved: SavedConnection, session: URLSession? = nil,
                signInEnded: SignInEndedObserver? = nil) throws(CopyRefusal) {
        guard saved.kind == .server, !saved.connection.isLocal, !saved.connection.isDemo else { throw .notAServer }
        guard !saved.needsSignIn, saved.connection.token != nil else { throw .signInEnded }
        destination = saved
        client = APIClient(connection: saved.connection, session: session, signInEnded: signInEnded)
    }

    /// Who's signed in there, refusing a read-only token.
    public func check() async throws -> Me {
        let me = try await client.me()
        if me.isReadOnly { throw CopyRefusal.readOnly }
        return me
    }

    /// Checks the token, then sends the backup with `mode`. Nothing is sent
    /// to a read-only connection.
    public func copy(_ payload: CopyPayload, mode: CopyMode) async throws -> CopyAnswer {
        _ = try await check()
        return try await client.importBackup(payload, mode: mode)
    }
}

extension APIClient {
    /// `POST /api/backup/import` with a plain backup and no passphrase.
    func importBackup(_ payload: CopyPayload, mode: CopyMode) async throws(APIError) -> CopyAnswer {
        // A whole household: the server may take a while to write it, longer
        // than the usual 20 seconds.
        try await send("POST", "/api/backup/import", json: payload.body(mode: mode), timeout: 120)
    }
}
