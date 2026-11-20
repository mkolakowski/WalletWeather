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
