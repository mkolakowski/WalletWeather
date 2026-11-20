import Foundation
import SwiftData

/// A household kept on this iPhone, for using the app without a server
/// (Plans/standalone.md, phase 4, #235): the same rows the server's database
/// holds for one person, in SwiftData.
///
/// - **Protected:** the store's folder and files have complete file
///   protection, as kept numbers do (#101): they can't be read while the
///   phone is locked.
/// - **Backed up with the phone:** unlike kept numbers, which are a copy of
///   the server's, this is the only copy, so it goes into the phone's own
///   iCloud or computer backup. Phase 6 adds a sealed backup to iCloud Drive.
/// - **Synced through iCloud** (phase 7, #238): with "Sync with iCloud" on
///   (the default, decided 2026-11-20) the store mirrors to the person's
///   private CloudKit database, also in the background, so the file then
///   stays readable after the phone's first unlock instead of only while
///   it's unlocked. Two devices' copies are joined by `LocalServer.reconcile`.
///
/// Every row's `id` is a random number below 2^52, not a count: phase 7
/// syncs between devices, where two phones adding a row at once mustn't pick
/// the same id. JavaScript (the core) holds such a number exactly. Rows are
/// handed to the core in the order they were added (`added`, then `id`), as
/// the server hands them over in id order.
enum LocalModels {
    static let all: [any PersistentModel.Type] = [
        LocalAccount.self, LocalCategory.self, LocalRecurring.self, LocalSkip.self,
        LocalTransaction.self, LocalTransfer.self, LocalFlag.self,
    ]

    static func newID() -> Int { Int.random(in: 1..<(1 << 52)) }
}

@Model final class LocalAccount {
    var id: Int = 0
    var name: String = ""
    var startingBalance: Double = 0
    /// "YYYY-MM-DD".
    var startingDate: String = ""
    var archived: Bool = false
    var added: Date = Date.now

    init(name: String, startingBalance: Double, startingDate: String) {
        id = LocalModels.newID()
        self.name = name
        self.startingBalance = startingBalance
        self.startingDate = startingDate
    }
}

@Model final class LocalCategory {
    var id: Int = 0
    var name: String = ""
    var color: String?
    var added: Date = Date.now

    init(name: String, color: String?) {
        id = LocalModels.newID()
        self.name = name
        self.color = color
    }
}

/// A bill or income: a repeating item (the server's RecurringTransaction).
@Model final class LocalRecurring {
    var id: Int = 0
    var accountID: Int = 0
    var name: String = ""
    var amount: Double = 0
    /// monthly_day, weekly or biweekly.
    var frequency: String = "monthly_day"
    var dayOfMonth: Int?
    var anchorDate: String?
    var endDate: String?
    var categoryID: Int?
    var notes: String?
    var active: Bool = true
    var matchDays: Int = 5
    var matchPercent: Int = 10
    /// The bank lines' name a server taught it (#224), kept so a move back
    /// to a server keeps it (#236).
    var matchText: String?
    var added: Date = Date.now

    init(accountID: Int) {
        id = LocalModels.newID()
        self.accountID = accountID
    }
}

/// A date deleted from a repeating item's forecast. `id` (random, phase 7)
/// lets two devices that skipped the same date keep the same one.
@Model final class LocalSkip {
    var id: Int = 0
    var recurringID: Int = 0
    var date: String = ""

    init(recurringID: Int, date: String) {
        id = LocalModels.newID()
        self.recurringID = recurringID
        self.date = date
    }
}

/// A line (the server's Transaction).
@Model final class LocalTransaction {
    var id: Int = 0
    var accountID: Int = 0
    var recurringID: Int?
    var categoryID: Int?
    var transferID: Int?
    var name: String = ""
    var notes: String?
    var amount: Double = 0
    var forecastAmount: Double?
    var forecastDate: String?
    var actualDate: String?
    var isActual: Bool = false
    var added: Date = Date.now

    init(accountID: Int) {
        id = LocalModels.newID()
        self.accountID = accountID
    }
}

/// Money moved between two accounts; its two lines carry its id.
@Model final class LocalTransfer {
    var id: Int = 0
    var fromAccountID: Int = 0
    var toAccountID: Int = 0
    var amount: Double = 0
    var date: String = ""
    var name: String = ""
    var notes: String?
    var added: Date = Date.now

    init(fromAccountID: Int, toAccountID: Int, amount: Double, date: String, name: String, notes: String?) {
        id = LocalModels.newID()
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.amount = amount
        self.date = date
        self.name = name
        self.notes = notes
    }
}

/// A named setting of the household, such as the Important notice agreed
/// to. `id` (random, phase 7) picks which of two devices' copies stays.
@Model final class LocalFlag {
    var id: Int = 0
    var name: String = ""
    var value: String = ""

    init(name: String, value: String) {
        id = LocalModels.newID()
        self.name = name
        self.value = value
    }
}

/// Where the household lives, and making and erasing it.
public enum LocalStore {
    /// `Application Support/Household`, inside the app's own container.
    public static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Household", directoryHint: .isDirectory)
    }

    static var file: URL { folder.appending(path: "household.store") }

    /// Whether a household has been set up on this phone.
    public static var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    // MARK: Sync with iCloud (#238)

    private static let syncKey = "household.icloudSync"

    /// "Sync with iCloud", this device's own choice: on unless turned off.
    public static var syncOn: Bool {
        get { UserDefaults.standard.object(forKey: syncKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: syncKey) }
    }

    /// Turns sync on or off and opens the household again with it. Off
    /// leaves every number on the phone; on joins it with iCloud's.
    public static func setSync(_ on: Bool) throws {
        syncOn = on
        LocalServer.closeShared()
        try LocalServer.openShared()
    }

    /// Whether the open store is syncing: sync on, and CloudKit took it.
    nonisolated(unsafe) public private(set) static var syncing = false

    /// The store on disk, made (with its protected folder) the first time.
    /// With sync on it mirrors to the private CloudKit database; when
    /// CloudKit can't be used (no iCloud entitlement, as in the tests) it
    /// opens on the phone alone.
    static func container(at folder: URL, sync: Bool = syncOn) throws -> ModelContainer {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // Background sync opens the file while the phone is locked.
        let level: FileProtectionType = sync ? .completeUntilFirstUserAuthentication : .complete
        protect(folder, level)
        func open(_ database: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
            let config = ModelConfiguration("Household", schema: Schema(LocalModels.all),
                                            url: folder.appending(path: "household.store"),
                                            cloudKitDatabase: database)
            return try ModelContainer(for: Schema(LocalModels.all), configurations: [config])
        }
        let container: ModelContainer
        if sync, cloudKitAvailable, let synced = try? open(.private(CloudBackup.containerID)) {
            container = synced
            syncing = true
        } else {
            container = try open(.none)
            syncing = false
        }
        // SQLite's own files (-wal, -shm) are made inside the folder and take
        // its protection; set it on each as well.
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            protect(folder.appending(path: name), level)
        }
        return container
    }

    /// CloudKit needs the app's iCloud entitlement; a test runner or a
    /// build without it has none.
    static var cloudKitAvailable: Bool {
        #if os(iOS)
        return Bundle.main.bundleIdentifier == "net.iptater.walletweather"
        #else
        return false
        #endif
    }

    /// A store in memory only, for the tests.
    static func memoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: Schema(LocalModels.all), isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(LocalModels.all), configurations: [config])
    }

    /// File protection: complete (unreadable while the phone is locked), or
    /// until the first unlock while syncing in the background.
    static func protect(_ url: URL, _ level: FileProtectionType = .complete) {
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: level], ofItemAtPath: url.path)
        #endif
    }

    /// Erases the household from the phone.
    public static func erase() {
        LocalServer.closeShared()
        try? FileManager.default.removeItem(at: folder)
    }

    /// The categories a new household starts with: the server's own
    /// (`DEFAULT_CATEGORIES` in apps/server/app/main.py).
    static let defaultCategories: [(String, String)] = [
        ("Groceries", "#3fb950"), ("Dining", "#f0883e"), ("Transportation", "#58a6ff"),
        ("Utilities", "#56d4dd"), ("Rent/Mortgage", "#a371f7"), ("Insurance", "#2ea043"),
        ("Healthcare", "#ff7b72"), ("Entertainment", "#e3b341"), ("Shopping", "#db61a2"),
        ("Subscriptions", "#7c6be6"), ("Income", "#3fb950"), ("Savings", "#d29922"),
        ("Other", "#8b949e"),
    ]
}
