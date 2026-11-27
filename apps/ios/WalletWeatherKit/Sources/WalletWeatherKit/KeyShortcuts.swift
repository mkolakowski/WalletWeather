import Foundation

// Keyboard and pointer (duo-more phase 4, #307): the shortcuts a hardware
// keyboard has, and the actions in a row's long-press (right-click) menu, as
// data. The app builds its buttons and menus from these, so what holding ⌘
// lists, what a test checks and what a Debug sheet shows are the same list.

/// A place a shortcut works: a page, the editors, or `everywhere`.
public enum ShortcutPage: String, CaseIterable, Sendable {
    case everywhere
    case dashboard, forecast, bills, calendar, netWorth, budgets, reports
    case search, settings, compare
    /// The line and bill editors (sheet or pane) and the other sheets.
    case editor

    /// The page a Place's raw value names (`RootView.Place`); Settings is "more".
    public init?(place: String) {
        switch place {
        case "more": self = .settings
        default: self.init(rawValue: place)
        }
    }

    /// Two places overlap when one is `everywhere` or they're the same.
    public func overlaps(_ other: ShortcutPage) -> Bool {
        self == .everywhere || other == .everywhere || self == other
    }
}

public enum ShortcutModifier: String, CaseIterable, Sendable, Comparable {
    case command, shift, option, control

    public static func < (a: ShortcutModifier, b: ShortcutModifier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// The symbol the keyboard's HUD and the Debug sheet write.
    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        }
    }
}

/// What a shortcut does. Raw values are for the table only; nothing is stored.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case addTransaction, addBill
    case search
    case tab1, tab2, tab3, tab4, tab5
    case refresh
    case previousMonth, nextMonth, thisMonth
    case save, cancel
}

/// One shortcut: the key, the modifiers held with it, the title the system
/// lists when ⌘ is held, and where it works.
public struct KeyShortcut: Sendable, Equatable, Identifiable {
    public let action: ShortcutAction
    /// One character, or a named key: "return", "escape".
    public let key: String
    public let modifiers: [ShortcutModifier]
    public let title: String
    public let pages: [ShortcutPage]

    public var id: String { "\(action.rawValue)/\(pages.map(\.rawValue).joined(separator: ","))" }

    public init(_ action: ShortcutAction, key: String, modifiers: [ShortcutModifier] = [.command],
                title: String, on pages: [ShortcutPage]) {
        self.action = action
        self.key = key
        self.modifiers = modifiers.sorted()
        self.title = title
        self.pages = pages
    }

    /// The same keys on a page both work on.
    public func collides(with other: KeyShortcut) -> Bool {
        guard key == other.key, modifiers == other.modifiers else { return false }
        return pages.contains { page in other.pages.contains { page.overlaps($0) } }
    }

    /// "⌘N", "⌘↩", "⎋".
    public var keys: String {
        let name: String
        switch key {
        case "return": name = "↩"
        case "escape": name = "⎋"
        default: name = key.uppercased()
        }
        return modifiers.map(\.symbol).joined() + name
    }

    public func works(on page: ShortcutPage) -> Bool { pages.contains { $0.overlaps(page) } }

    public var whereText: String {
        pages.contains(.everywhere) ? "Everywhere" : pages.map(\.label).joined(separator: ", ")
    }
}

extension ShortcutPage {
    /// For the Debug sheet and a test's messages.
    public var label: String {
        switch self {
        case .everywhere: "Everywhere"
        case .dashboard: "Dashboard"
        case .forecast: "Forecast"
        case .bills: "Bills & income"
        case .calendar: "Calendar"
        case .netWorth: "Net worth"
        case .budgets: "Budgets"
        case .reports: "Reports"
        case .search: "Search"
        case .settings: "Settings"
        case .compare: "Compare"
        case .editor: "Editors and sheets"
        }
    }
}

public enum KeyShortcuts {
    /// Every shortcut. ⌘1 to ⌘5 are the tab bar's places in order (the
    /// pages shown, then Settings; the app writes each title from the bar as
    /// it is). Month moves use ⌘[ and ⌘], not ⌘← and ⌘→: those move the
    /// cursor in a text field, and the open Duo's editor sits beside the list.
    public static let all: [KeyShortcut] = [
        KeyShortcut(.addTransaction, key: "n", title: "Add a line", on: [.dashboard, .forecast, .calendar]),
        KeyShortcut(.addBill, key: "n", title: "Add bill or income", on: [.bills]),
        KeyShortcut(.search, key: "f", title: "Search", on: [.everywhere]),
        KeyShortcut(.tab1, key: "1", title: "Go to the first tab", on: [.everywhere]),
        KeyShortcut(.tab2, key: "2", title: "Go to the second tab", on: [.everywhere]),
        KeyShortcut(.tab3, key: "3", title: "Go to the third tab", on: [.everywhere]),
        KeyShortcut(.tab4, key: "4", title: "Go to the fourth tab", on: [.everywhere]),
        KeyShortcut(.tab5, key: "5", title: "Go to the fifth tab", on: [.everywhere]),
        KeyShortcut(.refresh, key: "r", title: "Refresh", on: [.dashboard, .forecast, .bills, .calendar, .netWorth, .budgets, .reports, .search]),
        KeyShortcut(.previousMonth, key: "[", title: "Previous month", on: [.forecast, .calendar, .compare]),
        KeyShortcut(.nextMonth, key: "]", title: "Next month", on: [.forecast, .calendar, .compare]),
        KeyShortcut(.thisMonth, key: "t", title: "This month", on: [.forecast, .calendar]),
        KeyShortcut(.save, key: "return", title: "Save", on: [.editor]),
        KeyShortcut(.cancel, key: "escape", modifiers: [], title: "Cancel", on: [.editor]),
    ]

    /// The shortcuts that work on a page, `everywhere` ones included.
    public static func on(_ page: ShortcutPage) -> [KeyShortcut] { all.filter { $0.works(on: page) } }

    /// The shortcut for an action on a page.
    public static func shortcut(_ action: ShortcutAction, on page: ShortcutPage) -> KeyShortcut? {
        all.first { $0.action == action && $0.works(on: page) }
    }

    /// The shortcut for the nth place in the tab bar (1 to 5).
    public static func tab(_ number: Int) -> KeyShortcut? {
        let tabs: [ShortcutAction] = [.tab1, .tab2, .tab3, .tab4, .tab5]
        guard tabs.indices.contains(number - 1) else { return nil }
        return all.first { $0.action == tabs[number - 1] }
    }

    /// Pairs on one page that use the same keys: none, by the test.
    public static var collisions: [(KeyShortcut, KeyShortcut)] {
        var found: [(KeyShortcut, KeyShortcut)] = []
        for (index, a) in all.enumerated() {
            for b in all[(index + 1)...] where a.collides(with: b) { found.append((a, b)) }
        }
        return found
    }
}

// MARK: - A row's long-press menu

/// An item in the menu on a line or a bill (long-press, or right-click with
/// a pointer): the same things its swipes do (#307), and Open in Forecast on
/// a Search result.
public enum RowAction: String, CaseIterable, Sendable, Equatable {
    case markPaid, edit, delete, skipDate, end, openInForecast

    public var title: String {
        switch self {
        case .markPaid: "Mark paid as planned"
        case .edit: "Edit"
        case .delete: "Delete"
        case .skipDate: "Skip a date…"
        case .end: "End…"
        case .openInForecast: "Open in Forecast"
        }
    }

    public var symbol: String {
        switch self {
        case .markPaid: "checkmark.circle"
        case .edit: "pencil"
        case .delete: "trash"
        case .skipDate: "forward.end"
        case .end: "stop.circle"
        case .openInForecast: "chart.line.uptrend.xyaxis"
        }
    }

    /// Shown in red, and last.
    public var isDestructive: Bool { self == .delete || self == .end }

    /// A line's menu, as its swipes: Mark paid as planned (not on a paid
    /// line), Edit, Delete; nothing when this person can't change it.
    /// `inSearch` adds Open in Forecast, which doesn't need the right to change.
    public static func forLine(canChange: Bool, isPaid: Bool, inSearch: Bool = false) -> [RowAction] {
        var items: [RowAction] = []
        if canChange {
            if !isPaid { items.append(.markPaid) }
            items.append(.edit)
            items.append(.delete)
        }
        if inSearch { items.insert(.openInForecast, at: canChange ? items.count - 1 : 0) }
        return items
    }

    /// A bill's menu: Edit, Skip a date… (while it has dates ahead), End…
    /// (not once it has ended); nothing when this person can't change it.
    public static func forBill(canChange: Bool, expired: Bool, hasDatesAhead: Bool) -> [RowAction] {
        guard canChange else { return [] }
        var items: [RowAction] = [.edit]
        if !expired {
            if hasDatesAhead { items.append(.skipDate) }
            items.append(.end)
        }
        return items
    }
}
