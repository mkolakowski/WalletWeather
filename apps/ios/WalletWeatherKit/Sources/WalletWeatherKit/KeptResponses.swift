import CryptoKit
import Foundation

/// What this phone keeps, chosen at set-up and changeable in Settings
/// (Plans/ios-app.md, phase 8; decided 2026-11-14 and 2026-11-15).
public enum KeepChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    /// The default: the app needs a connection, and keeps no numbers.
    case nothing
    /// The pages last loaded, shown with their age when the server can't be
    /// reached.
    case lastKnown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nothing: "Nothing"
        case .lastKnown: "Last-known numbers"
        }
    }
}

/// The server's last answers to the pages' read requests, kept on the phone
/// when the person chose Last-known numbers, so a page can still open when
/// the server can't be reached.
///
/// - Each answer is a file, written with complete file protection: it can't
///   be read while the phone is locked.
/// - The folder and every file are left out of iCloud and computer backups,
///   so a restored phone starts empty.
/// - `deleteAll()` removes the folder, on signing out and on choosing
///   Nothing; a new sign-in starts empty too.
/// - At most `limit` answers are kept; the oldest go first.
public struct KeptResponses: Sendable {
    public let directory: URL
    public let limit: Int

    public init(directory: URL, limit: Int = 300) {
        self.directory = directory
        self.limit = limit
    }

    /// The app's own: `Application Support/Kept`, inside the app's
    /// container.
    public static var standard: KeptResponses {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return KeptResponses(directory: base.appending(path: "Kept", directoryHint: .isDirectory))
    }

    /// The key for a request: the server, the method, the path and the query,
    /// leaving out `today` so yesterday's copy still answers today.
    public static func key(server: URL, method: String, path: String, query: [String: String]) -> String {
        let q = query.filter { $0.key != "today" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(server.absoluteString)|\(method) \(path)?\(q)"
    }

    private func file(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name + ".json", directoryHint: .notDirectory)
    }

    /// Keeps `data` as the answer for `key`, replacing an older one.
    public func save(_ data: Data, for key: String) {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directory.path(percentEncoded: false)) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                var folder = directory
                try Self.excludeFromBackup(&folder)
            }
            var url = file(for: key)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            try Self.excludeFromBackup(&url)
            prune()
        } catch {
            // Keeping is a convenience: a page that can't be kept still shows.
        }
    }

    /// The kept answer for `key` and when it was kept, if there is one.
    public func load(_ key: String) -> (data: Data, keptAt: Date)? {
        let url = file(for: key)
        guard let data = try? Data(contentsOf: url),
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return (data, date)
    }

    /// Every kept answer, and the folder they're in.
    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// How many answers are kept (for tests, and the settings footer).
    public var count: Int { files().count }

    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }

    private func prune() {
        let all = files()
        guard all.count > limit else { return }
        let dated = all.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(all.count - limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// How the API client tells a page where its numbers came from: a date when
/// it answered from the phone's kept copy, nil when the server answered.
public typealias KeptObserver = @MainActor @Sendable (Date?) -> Void
