import Foundation
import Testing
@testable import WalletWeatherKit

/// The backup to iCloud Drive (Plans/standalone.md, phase 6, #237), run in a
/// temporary folder: the real iCloud round trip (turn it on, delete the app,
/// reinstall, restore) is checked on a phone. Done when a restore gives the
/// same Forecast and the old backups are pruned to the number kept.
@Suite(.serialized) struct CloudBackupTests {
    static let passphrase = BackupTests.passphrase
    static let quick = BackupTests.quick

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cloud-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A change the way the pages make one: through the server's answers.
    static func change(_ server: LocalServer, _ name: String = "Checking") throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "starting_balance": 10, "starting_date": "2026-01-01"])
        let (status, _) = server.answer(method: "POST", path: "/api/accounts", query: [:], body: body)
        try #require(status == 200)
    }

    static func day(_ d: Int, month: Int = 2) -> LocalDay { LocalDay(year: 2026, month: month, day: d) }

    @Test func fileNamesCarryTheDay() {
        #expect(CloudBackup.fileName(for: Self.day(9)) == "walletweather-2026-02-09.json")
        #expect(CloudBackup.day(fromFileName: "walletweather-2026-02-09.json") == Self.day(9))
        #expect(CloudBackup.day(fromFileName: "notes.json") == nil)
        #expect(CloudBackup.day(fromFileName: "walletweather-2026-02-09.txt") == nil)
    }

    @Test func backupsAreListedNewestFirstIncludingOnesNotYetDownloaded() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["walletweather-2026-02-01.json", "walletweather-2026-02-09.json", "readme.txt"] {
            try Data("x".utf8).write(to: folder.appending(path: name))
        }
        // iCloud's hidden placeholder for a file it hasn't brought over.
        try Data("x".utf8).write(to: folder.appending(path: ".walletweather-2026-02-05.json.icloud"))
        let entries = CloudBackup.entries(in: folder)
        #expect(entries.map(\.day) == [Self.day(9), Self.day(5), Self.day(1)])
        #expect(entries.map(\.downloaded) == [true, false, true])
        #expect(entries[1].url.lastPathComponent == "walletweather-2026-02-05.json")
    }

    @Test func itBacksUpOnlyWhenOnChangedAndNoneYetToday() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try LocalServer.inMemory()
        func run(_ day: LocalDay) throws -> CloudBackup.Entry? {
            try CloudBackup.runIfDue(server, passphrase: Self.passphrase, in: folder, today: day, params: Self.quick)
        }
        try Self.change(server)
        // Not decided yet, and then switched off: nothing is written.
        #expect(server.cloudBackupOn == nil)
        #expect(try run(Self.day(9)) == nil)
        server.setCloudBackup(false)
        #expect(try run(Self.day(9)) == nil)
        server.setCloudBackup(true)
        // On with a change: written under today's name.
        #expect(try run(Self.day(9))?.url.lastPathComponent == "walletweather-2026-02-09.json")
        #expect(server.lastBackupDay == Self.day(9))
        // Nothing changed since: not again, even on a new day.
        #expect(try run(Self.day(10)) == nil)
        // A change the same day waits for the next day.
        try Self.change(server, "Savings")
        #expect(try run(Self.day(9)) == nil)
        #expect(try run(Self.day(10))?.day == Self.day(10))
        #expect(try run(Self.day(11)) == nil)
        #expect(CloudBackup.entries(in: folder).map(\.day) == [Self.day(10), Self.day(9)])
    }

    @Test func aReadOnlyAnswerIsNotAChange() throws {
        let server = try LocalServer.inMemory()
        server.setCloudBackup(true)
        _ = server.answer(method: "GET", path: "/api/accounts", query: [:], body: nil)
        #expect(!server.isBackupDue(today: Self.day(9)))
        try Self.change(server)
        #expect(server.isBackupDue(today: Self.day(9)))
    }

    @Test func onlyTheNewestFourteenAreKept() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for d in 1...20 { try Data("x".utf8).write(to: folder.appending(path: CloudBackup.fileName(for: Self.day(d, month: 3)))) }
        // A placeholder among the old ones goes too.
        try Data("x".utf8).write(to: folder.appending(path: ".walletweather-2026-03-02.json.icloud"))
        try Data("x".utf8).write(to: folder.appending(path: "keep-me.txt"))
        #expect(CloudBackup.prune(in: folder) == 6)
        let left = CloudBackup.entries(in: folder)
        #expect(left.count == 14)
        #expect(left.first?.day == Self.day(20, month: 3))
        #expect(left.last?.day == Self.day(7, month: 3))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "keep-me.txt").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: ".walletweather-2026-03-02.json.icloud").path))
    }

    @Test func aRestoreGivesTheSameForecast() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let phone = try await BackupTests.household()
        phone.setCloudBackup(true)
        let made = try #require(try CloudBackup.runIfDue(phone, passphrase: Self.passphrase, in: folder,
                                                         today: BackupTests.today, force: true, params: Self.quick))
        // A new phone: read the file back, open it with the passphrase, import.
        let entry = try #require(CloudBackup.entries(in: folder).first)
        #expect(entry == made)
        let data = try await CloudBackup.read(entry)
        let opened = try BackupFile.open(data, passphrase: Self.passphrase)
        #expect(opened.encrypted)
        let fresh = try LocalServer.inMemory()
        try fresh.importBackup(opened.payload)
        let a = try BackupTests.forecasts(phone), b = try BackupTests.forecasts(fresh)
        #expect(NSDictionary(dictionary: a) == NSDictionary(dictionary: b))
        // The restored household is itself due for a backup (it changed).
        fresh.setCloudBackup(true)
        #expect(fresh.isBackupDue(today: Self.day(12)))
    }

    @Test func aFileThatIsntThereIsAnErrorNotACrash() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let entry = CloudBackup.Entry(day: Self.day(1), url: folder.appending(path: "walletweather-2026-02-01.json"), downloaded: true)
        await #expect(throws: (any Error).self) { _ = try await CloudBackup.read(entry, timeout: 1) }
    }
}
