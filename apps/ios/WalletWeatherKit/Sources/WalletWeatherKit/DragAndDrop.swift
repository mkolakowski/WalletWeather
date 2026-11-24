import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - A line dragged onto a Calendar day (#308)

/// A line on its way to a Calendar day, from Forecast or the Calendar's own
/// lists, in this window or another WalletWeather window. It carries what
/// finds the line again and saves it: the account, the transaction and the
/// date it's planned for now. Only a one-off you added can be dragged: its
/// planned date is a field in the editor (#316); a date that comes from a
/// repeating bill changes in its bill.
public struct LineDrag: Sendable, Codable, Equatable {
    /// The app's own type for a dragged line, declared in the app's
    /// Info.plist (`UTExportedTypeDeclarations`). Never rename it: a drag
    /// between two windows of different builds would stop matching.
    public static let typeIdentifier = "net.iptater.walletweather.line"

    public let accountId: Int
    public let transactionId: Int
    public let name: String
    public let plannedOn: LocalDay

    public init(accountId: Int, transactionId: Int, name: String, plannedOn: LocalDay) {
        self.accountId = accountId
        self.transactionId = transactionId
        self.name = name
        self.plannedOn = plannedOn
    }

    /// Whether lines may be dragged at all: an account this person may change
    /// (which a read-only token never may), and not while the lock has the
    /// demo in front of a real household.
    public static func allowed(canEdit: Bool, lockedInDemo: Bool) -> Bool { canEdit && !lockedInDemo }

    /// A Forecast line, when it can be moved: `canChange` is
    /// `allowed(canEdit:lockedInDemo:)` for its account. A one-off not yet
    /// paid (a paid line shows on the day it was paid, so moving its plan
    /// would look like nothing happened).
    public init?(line: ForecastLine, accountId: Int, canChange: Bool) {
        guard canChange, line.isOneOff, !line.isPaid, let id = line.transactionId, let planned = line.plannedDate else { return nil }
        self.init(accountId: accountId, transactionId: id, name: line.description, plannedOn: planned)
    }

    /// A Calendar line, by the same rule.
    public init?(event: CalendarEvent, canChange: Bool) {
        guard canChange, !event.isTransfer, event.recurringId == nil, !event.isPaid, let id = event.transactionId else { return nil }
        self.init(accountId: event.accountId, transactionId: id, name: event.description, plannedOn: event.date)
    }

    /// Whether a drop on `day` changes anything: the same day does nothing.
    public func moves(to day: LocalDay) -> Bool { day != plannedOn }

    /// The Forecast month that holds the line now.
    public var month: YearMonth { YearMonth(plannedOn) }

    /// The line itself in a freshly read month, or nil when it's gone.
    public func line(in month: ForecastMonth) -> ForecastLine? {
        month.rows.first { $0.transactionId == transactionId }
    }

    /// The same line after a drop on `day`: what Undo moves back.
    public func moved(to day: LocalDay) -> LineDrag {
        LineDrag(accountId: accountId, transactionId: transactionId, name: name, plannedOn: day)
    }
}

extension LineDrag: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        // Only WalletWeather's own windows (one process) can take it, so a
        // line's name never lands in another app.
        CodableRepresentation(contentType: UTType(exportedAs: typeIdentifier, conformingTo: .data))
            .visibility(.ownProcess)
    }
}

extension LineDraft {
    /// What the editor would save if only the planned date were changed to
    /// `day` (#308), the way its "Planned for" picker does: a line not yet
    /// paid also has its actual date follow. Nil for a line whose date
    /// can't change here (from a bill, a transfer, or paid).
    public static func moved(_ line: ForecastLine, to day: LocalDay, today: LocalDay) -> LineDraft? {
        guard line.isOneOff, !line.isPaid else { return nil }
        var draft = LineDraft(line, today: today)
        draft.plannedOn = day
        draft.paidOn = paidOn(planned: day, today: today)
        return draft
    }
}

// MARK: - A CSV dropped on Forecast or the Dashboard (#308)

/// A bank's CSV dragged in from Files (or anything that offers one): which
/// of the item's types to read, or nil to refuse it.
public enum CSVDrop {
    /// `text/csv`, `text/comma-separated-values` and a `.csv` file.
    public static let csvType = "public.comma-separated-values-text"
    static let textTypes: Set<String> = ["public.utf8-plain-text", "public.plain-text", "public.text"]
    static let fileTypes: Set<String> = ["public.data", "public.content", "public.item", "public.file-url"]

    /// The type to read from an item offering `identifiers` (in the order it
    /// offers them), called `name`: CSV when it says so; otherwise only a
    /// file named `.csv`, read as its text or its bytes. A line dragged in
    /// the app, a picture or a plain note is refused.
    public static func typeToRead(_ identifiers: [String], name: String?) -> String? {
        if identifiers.contains(csvType) { return csvType }
        guard let name, name.lowercased().hasSuffix(".csv"), !identifiers.contains(LineDrag.typeIdentifier) else { return nil }
        return identifiers.first { textTypes.contains($0) } ?? identifiers.first { fileTypes.contains($0) }
    }

    /// Whether any of the dropped items is a CSV the page can read.
    public static func accepts(_ items: [(identifiers: [String], name: String?)]) -> Bool {
        items.contains { typeToRead($0.identifiers, name: $0.name) != nil }
    }

    /// The file name the import sheet shows: the item's own, with `.csv`
    /// added when it has none.
    public static func fileName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Dropped file.csv" }
        return trimmed.lowercased().hasSuffix(".csv") ? trimmed : trimmed + ".csv"
    }
}

// MARK: - Debug pictures

public enum DropDebug {
    /// `WW_DEBUG_DROP` on the Calendar (Debug builds): `day` highlights the
    /// day after today (or the 15th when today isn't in the month shown), a
    /// `YYYY-MM-DD` in the month highlights that day; anything else nothing.
    public static func highlightedDay(_ setting: String?, month: YearMonth, today: LocalDay) -> LocalDay? {
        guard let setting else { return nil }
        if setting == "day" {
            let tomorrow = today.adding(days: 1)
            return month.contains(tomorrow) ? tomorrow : LocalDay(year: month.year, month: month.month, day: 15)
        }
        guard let day = LocalDay(setting), month.contains(day) else { return nil }
        return day
    }
}
