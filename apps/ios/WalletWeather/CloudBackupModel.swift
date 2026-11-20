import Foundation
import WalletWeatherKit

/// The iCloud Drive backup of the household on this iPhone (Plans/standalone.md,
/// phase 6, #237): whether it's on, when it last ran and what it says. The
/// work itself is `CloudBackup` in WalletWeatherKit; this runs it off the
/// main thread (sealing takes a moment) when the app opens, goes to the
/// background, or is asked.
@MainActor @Observable
final class CloudBackupModel {
    /// On or off once decided; nil until the first account asks.
    private(set) var on: Bool?
    private(set) var lastDay: LocalDay?
    private(set) var working = false
    /// What the last run said, and whether it failed.
    private(set) var message: String?
    private(set) var failed = false

    /// Reads the household's notes on its backup.
    func refresh() {
        guard let server = try? LocalServer.openShared() else { return }
        on = server.cloudBackupOn
        lastDay = server.lastBackupDay
    }

    func setOn(_ value: Bool) {
        guard let server = try? LocalServer.openShared() else { return }
        server.setCloudBackup(value)
        message = nil
        refresh()
        if value { Task { await run(force: true) } }
    }

    /// Back up now, whether or not one is due.
    func backUpNow() async { await run(force: true) }

    /// Back up if one is due: when the app opens or goes to the background.
    func runIfDue() async { await run(force: false) }

    private func run(force: Bool) async {
        guard !working, let server = try? LocalServer.openShared() else { return }
        guard force || server.isBackupDue(today: .today()) else { return }
        guard let passphrase = BackupPassphrase.load() else {
            if force { report("Choose a backup passphrase first.", failed: true) }
            return
        }
        working = true
        defer { working = false }
        do {
            let entry = try await Task.detached(priority: .utility) { () throws -> CloudBackup.Entry? in
                guard let folder = CloudBackup.iCloudFolder() else { throw CloudBackup.Problem.unavailable }
                return try CloudBackup.runIfDue(server, passphrase: passphrase, in: folder, force: force)
            }.value
            refresh()
            if entry != nil { report("Backed up to iCloud Drive.") }
        } catch {
            report(AppModel.describe(error), failed: true)
        }
    }

    private func report(_ text: String, failed: Bool = false) {
        message = text
        self.failed = failed
    }

    /// The backups in iCloud Drive, newest first.
    nonisolated static func backups() async throws -> [CloudBackup.Entry] {
        try await Task.detached(priority: .userInitiated) {
            guard let folder = CloudBackup.iCloudFolder() else { throw CloudBackup.Problem.unavailable }
            return CloudBackup.entries(in: folder)
        }.value
    }
}
