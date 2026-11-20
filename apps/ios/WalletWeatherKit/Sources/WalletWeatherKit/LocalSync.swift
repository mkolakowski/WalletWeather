import CoreData
import Foundation
import SwiftData

/// Sync with iCloud (Plans/standalone.md, phase 7, #238). CloudKit keeps
/// each record's later edit and keeps deleted records deleted (open question
/// 6). What it can't know is that two devices made the *same* thing apart:
/// each household starts with the server's 13 categories, and settings and
/// skipped dates can be made on both before they sync. `reconcile` joins
/// those, the same way on every device, so they all keep the same copy:
///
/// - **Categories with the same name** become one: the one with the lowest
///   id stays (taking a colour the other had, if it had none), and every
///   line and bill of the others moves to it (decided 2026-11-20: merge).
/// - **Settings with the same name** become one, the lowest id, holding the
///   joined value (`joinedFlag`).
/// - **The same skipped date** of a bill is kept once.
/// - **Tags with the same name** become one, like categories, and a tag on
///   the same line or bill, or the same rule, is kept once (#250).
///
/// Rows from before phase 7 have no id (0); they get one first.
extension LocalServer {
    /// How two copies of a setting join: the latest change stamp and backup,
    /// "agreed" and "on" if any copy says so, otherwise the lowest id's.
    static func joinedFlag(_ name: String, _ rows: [LocalFlag]) -> String? {
        guard !rows.isEmpty else { return nil }
        let values = rows.map(\.value)
        switch name {
        case changedFlag, backedUpStampFlag:
            return values.max { (Double($0) ?? 0) < (Double($1) ?? 0) }
        case backedUpDayFlag:
            return values.max()
        case "notice_acknowledged":
            return values.contains("yes") ? "yes" : values[0]
        case backupSettingFlag:
            return values.contains("on") ? "on" : "off"
        default:
            return rows.min { $0.id < $1.id }?.value
        }
    }

    /// Joins what devices made apart (see above). Returns whether anything
    /// changed; running it again changes nothing.
    @discardableResult
    public func reconcile() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for row in try context.fetch(FetchDescriptor<LocalSkip>(predicate: #Predicate { $0.id == 0 })) { row.id = LocalModels.newID() }
            for row in try context.fetch(FetchDescriptor<LocalFlag>(predicate: #Predicate { $0.id == 0 })) { row.id = LocalModels.newID() }

            // Categories by name.
            var kept: [String: LocalCategory] = [:]
            var moved: [Int: Int] = [:]
            for category in try context.fetch(FetchDescriptor<LocalCategory>()).sorted(by: { $0.id < $1.id }) {
                if let keeper = kept[category.name] {
                    moved[category.id] = keeper.id
                    if keeper.color == nil, let color = category.color { keeper.color = color }
                    context.delete(category)
                } else {
                    kept[category.name] = category
                }
            }
            if !moved.isEmpty {
                for line in try context.fetch(FetchDescriptor<LocalTransaction>()) {
                    if let from = line.categoryID, let to = moved[from] { line.categoryID = to }
                }
                for rec in try context.fetch(FetchDescriptor<LocalRecurring>()) {
                    if let from = rec.categoryID, let to = moved[from] { rec.categoryID = to }
                }
            }

            // Tags by name, as categories; their links and rules follow.
            var keptTags: [String: LocalTag] = [:]
            var movedTags: [Int: Int] = [:]
            for tag in try context.fetch(FetchDescriptor<LocalTag>()).sorted(by: { $0.id < $1.id }) {
                if let keeper = keptTags[tag.name] {
                    movedTags[tag.id] = keeper.id
                    if keeper.color == nil, let color = tag.color { keeper.color = color }
                    context.delete(tag)
                } else {
                    keptTags[tag.name] = tag
                }
            }
            let links = try context.fetch(FetchDescriptor<LocalTagLink>()).sorted(by: { $0.id < $1.id })
            let rules = try context.fetch(FetchDescriptor<LocalTagRule>()).sorted(by: { $0.id < $1.id })
            for link in links { if let to = movedTags[link.tagID] { link.tagID = to } }
            for rule in rules {
                if let to = movedTags[rule.tagID] { rule.tagID = to }
                if let from = rule.categoryID, let to = moved[from] { rule.categoryID = to }
            }
            var seenLinks = Set<String>()
            for link in links where !seenLinks.insert("\(link.tagID)/\(link.transactionID ?? 0)/\(link.recurringID ?? 0)").inserted {
                context.delete(link)
            }
            var seenRules = Set<String>()
            for rule in rules where !seenRules.insert("\(rule.pattern)\u{0}\(rule.tagID)\u{0}\(rule.categoryID ?? 0)").inserted {
                context.delete(rule)
            }

            // Settings by name.
            for (name, rows) in Dictionary(grouping: try context.fetch(FetchDescriptor<LocalFlag>()), by: \.name) where rows.count > 1 {
                let sorted = rows.sorted { $0.id < $1.id }
                let value = Self.joinedFlag(name, sorted) ?? sorted[0].value
                if sorted[0].value != value { sorted[0].value = value }
                for extra in sorted.dropFirst() { context.delete(extra) }
            }

            // Skipped dates by bill and day.
            var seen = Set<String>()
            for skip in try context.fetch(FetchDescriptor<LocalSkip>()).sorted(by: { $0.id < $1.id }) {
                if !seen.insert("\(skip.recurringID)/\(skip.date)").inserted { context.delete(skip) }
            }

            guard context.hasChanges else { return false }
            try context.save()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Delete everywhere (#249)

extension LocalServer {
    /// Deletes every row of the household through the store, so with sync on
    /// CloudKit deletes them in iCloud and on every device too (a deleted
    /// record stays deleted).
    public func emptyHousehold() throws {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try context.delete(model: LocalTransaction.self)
        try context.delete(model: LocalTransfer.self)
        try context.delete(model: LocalSkip.self)
        try context.delete(model: LocalRecurring.self)
        try context.delete(model: LocalAccount.self)
        try context.delete(model: LocalCategory.self)
        try context.delete(model: LocalFlag.self)
        try context.delete(model: LocalTagLink.self)
        try context.delete(model: LocalTagRule.self)
        try context.delete(model: LocalTag.self)
        try context.save()
    }
}

extension LocalStore {
    /// Delete everywhere (decided 2026-11-20, #249): empties the household
    /// through the store, waits for CloudKit to send the deletes to iCloud,
    /// then deletes this phone's files. When iCloud doesn't confirm in
    /// `timeout` (offline, say), the emptied store is kept so the deletes go
    /// up the next time the app runs, and this returns false. Without sync
    /// there's nothing to wait for. The iCloud Drive backups are left alone.
    public static func eraseEverywhere(timeout: TimeInterval = 30) async throws -> Bool {
        let server = try LocalServer.openShared()
        let syncing = Self.syncing
        let saved = Date.now
        // Listen before deleting, so the export that follows isn't missed.
        let confirmed: Task<Bool, Never>? = syncing ? Task { await exported(after: saved, timeout: timeout) } : nil
        try server.emptyHousehold()
        let done = await confirmed?.value ?? true
        if done { erase() } else { LocalServer.closeShared() }
        return done
    }

    /// Waits for a CloudKit export that started after `date` to succeed.
    static func exported(after date: Date, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await note in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                    guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                            as? NSPersistentCloudKitContainer.Event else { continue }
                    if event.type == .export, event.endDate != nil, event.startDate >= date.addingTimeInterval(-1) {
                        return event.succeeded
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
