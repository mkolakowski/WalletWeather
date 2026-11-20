import Foundation
import SwiftData

/// The backup to iCloud Drive (Plans/standalone.md, phase 6, #237): the
/// phase 5 file (the server's own sealed backup, so a server's Settings →
/// Restore opens it too) written to the app's iCloud Drive folder, which
/// shows in the Files app.
///
/// - **When** (open question 5, decided 2026-11-18): at most once a day, and
///   only when something changed since the last backup. iOS gives an app no
///   timer, so the app asks when it opens and when it goes to the background.
/// - **How many:** the last 14 are kept; older ones are deleted.
/// - **Turned on** from the first account (decided 2026-11-20), with the
///   backup passphrase of phase 5; a person can turn it off in Settings.
///
/// Everything here takes the folder as an argument, so the tests run it in a
/// temporary folder; `iCloudFolder()` finds the real one.
public enum CloudBackup {
    /// The app's iCloud Drive container (WalletWeather.entitlements).
    public static let containerID = "iCloud.net.iptater.walletweather"
    /// Backups kept.
    public static let keep = 14

    /// One backup file: the day it was made and where it is. `downloaded` is
    /// false for one iCloud has listed but not yet brought to this phone.
    public struct Entry: Identifiable, Equatable, Sendable {
        public let day: LocalDay
        public let url: URL
        public let downloaded: Bool
        public var id: String { url.lastPathComponent }
    }

    public enum Problem: Error, LocalizedError, Equatable {
        case unavailable
        case notDownloaded
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                "iCloud Drive isn't available. In the Settings app, sign in to iCloud and turn on iCloud Drive, and allow WalletWeather there."
            case .notDownloaded:
                "That backup hasn't finished downloading from iCloud. Check the connection and try again in a moment."
            case let .failed(message):
                message
            }
        }
    }

    // MARK: - Files

    public static func fileName(for day: LocalDay) -> String { "walletweather-\(day).json" }

    /// The day a backup's file name carries, or nil for any other file.
    static func day(fromFileName name: String) -> LocalDay? {
        guard name.hasPrefix("walletweather-"), name.hasSuffix(".json") else { return nil }
        return LocalDay(String(name.dropFirst("walletweather-".count).dropLast(".json".count)))
    }

    /// The Backups folder in the app's iCloud Drive container, made when it
    /// isn't there; nil when iCloud Drive is off or the app has no container.
    /// This can wait on the system: call it off the main thread.
    public static func iCloudFolder() -> URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        let folder = root.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: "Backups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The backups in `folder`, newest first. A file iCloud hasn't downloaded
    /// is a hidden placeholder (`.name.icloud`); it's listed under its real
    /// name with `downloaded` false.
    public static func entries(in folder: URL) -> [Entry] {
        var found: [String: Entry] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            var real = name
            var placeholder = false
            if real.hasPrefix("."), real.hasSuffix(".icloud") {
                real = String(real.dropFirst().dropLast(".icloud".count))
                placeholder = true
            }
            guard let day = day(fromFileName: real) else { continue }
            let entry = Entry(day: day, url: folder.appending(path: real), downloaded: !placeholder)
            // The real file wins when both are there.
            if found[real] == nil || entry.downloaded { found[real] = entry }
        }
        return found.values.sorted { $0.day > $1.day }
    }

    /// Deletes all but the newest `count` backups; returns how many went.
    @discardableResult
    public static func prune(in folder: URL, keeping count: Int = keep) -> Int {
        let old = entries(in: folder).dropFirst(count)
        for entry in old {
            let placeholder = folder.appending(path: ".\(entry.url.lastPathComponent).icloud")
            for url in [entry.url, placeholder] where FileManager.default.fileExists(atPath: url.path) {
                coordinatedDelete(url)
            }
        }
        return old.count
    }

    private static func coordinatedDelete(_ url: URL) {
        var failure: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &failure) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Writes the file for `day`, replacing that day's earlier one.
    @discardableResult
    public static func write(_ data: Data, day: LocalDay, in folder: URL) throws -> Entry {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: fileName(for: day))
        var failure: NSError?
        var written: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &failure) { url in
            do { try data.write(to: url, options: .atomic) } catch { written = error }
        }
        if let error = failure ?? (written as NSError?) { throw Problem.failed("The backup couldn't be saved: \(error.localizedDescription)") }
        return Entry(day: day, url: target, downloaded: true)
    }

    /// The file's bytes. One iCloud hasn't downloaded is asked for and
    /// waited on, up to `timeout` seconds.
    public static func read(_ entry: Entry, timeout: TimeInterval = 90) async throws -> Data {
        let fm = FileManager.default
        if !entry.downloaded || !fm.fileExists(atPath: entry.url.path) {
            do { try fm.startDownloadingUbiquitousItem(at: entry.url) } catch {
                throw Problem.failed("iCloud couldn't be asked for that backup: \(error.localizedDescription)")
            }
            let deadline = Date.now.addingTimeInterval(timeout)
            while !isDownloaded(entry.url) {
                if Date.now > deadline { throw Problem.notDownloaded }
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        var failure: NSError?
        var data: Data?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: entry.url, options: [], error: &failure) { url in
            do { data = try Data(contentsOf: url) } catch { readError = error }
        }
        if let data { return data }
        throw Problem.failed("That backup couldn't be read: \((failure ?? (readError as NSError?))?.localizedDescription ?? "unknown error")")
    }

    private static func isDownloaded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        return status == nil || status == .current
    }

    // MARK: - Backing up

    /// Backs up when it's due (turned on, something changed since the last
    /// backup, and none made today yet), or whenever with `force`. Seals the
    /// household with `passphrase` (scrypt takes a moment: off the main
    /// thread), writes today's file and prunes. Returns the file, or nil
    /// when nothing was due.
    @discardableResult
    public static func runIfDue(_ server: LocalServer, passphrase: String, in folder: URL,
                                today: LocalDay = .today(), force: Bool = false,
                                params: (n: Int, r: Int, p: Int)? = nil) throws -> Entry? {
        guard force || server.isBackupDue(today: today) else { return nil }
        // The change stamp first: a change made while this runs stays due.
        let covered = server.changeStamp
        let payload = try server.backupPayload()
        let data: Data
        if let params {
            data = try BackupFile.seal(payload, passphrase: passphrase, kind: "user", cost: params)
        } else {
            data = try BackupFile.seal(payload, passphrase: passphrase)
        }
        let entry = try write(data, day: today, in: folder)
        server.markBackedUp(covering: covered, on: today)
        prune(in: folder)
        return entry
    }
}

// MARK: - What the household remembers

/// The household's own notes on its backup, kept as settings in the store
/// (never in a backup file): whether it's on, when something last changed,
/// and what the last backup covered.
extension LocalServer {
    static let backupSettingFlag = "icloud_backup", changedFlag = "changed_at"
    static let backedUpDayFlag = "icloud_backed_up_on", backedUpStampFlag = "icloud_backed_up_for"

    /// Stamps a change; every answer and import that changes the household
    /// does, in the same save.
    func markChanged(_ context: ModelContext) {
        setFlag(Self.changedFlag, String(Date.now.timeIntervalSince1970), context)
    }

    private func read(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return flag(name, ModelContext(container))
    }

    private func write(_ pairs: [(String, String)]) {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        for (name, value) in pairs { setFlag(name, value, context) }
        try? context.save()
    }

    /// True or false once decided; nil before (the first account asks).
    public var cloudBackupOn: Bool? {
        read(Self.backupSettingFlag).map { $0 == "on" }
    }

    public func setCloudBackup(_ on: Bool) {
        write([(Self.backupSettingFlag, on ? "on" : "off")])
    }

    /// The last change's stamp, "" when nothing has changed.
    var changeStamp: String { read(Self.changedFlag) ?? "" }

    /// The day of the last backup.
    public var lastBackupDay: LocalDay? {
        read(Self.backedUpDayFlag).flatMap(LocalDay.init)
    }

    func markBackedUp(covering stamp: String, on day: LocalDay) {
        write([(Self.backedUpStampFlag, stamp), (Self.backedUpDayFlag, day.description)])
    }

    /// On, changed since the last backup, and none yet today.
    public func isBackupDue(today: LocalDay) -> Bool {
        guard cloudBackupOn == true else { return false }
        let changed = changeStamp
        guard !changed.isEmpty, changed != read(Self.backedUpStampFlag) else { return false }
        return lastBackupDay != today
    }
}
