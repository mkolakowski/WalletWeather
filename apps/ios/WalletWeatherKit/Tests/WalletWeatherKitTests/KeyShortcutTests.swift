import Foundation
import Testing
@testable import WalletWeatherKit

/// The keyboard shortcuts and the long-press menus (#307).
struct KeyShortcutTests {
    /// No two shortcuts use the same keys on a page, `everywhere` ones included.
    @Test func noTwoShortcutsClashOnAPage() {
        // `everywhere` itself isn't a page a person is on; `collisions` below covers it.
        for page in ShortcutPage.allCases where page != .everywhere {
            let onPage = KeyShortcuts.on(page)
            for (index, a) in onPage.enumerated() {
                for b in onPage[(index + 1)...] {
                    #expect(!(a.key == b.key && a.modifiers == b.modifiers),
                            "\(a.title) and \(b.title) both use \(a.keys) on \(page.label)")
                }
            }
        }
        #expect(KeyShortcuts.collisions.isEmpty)
    }

    @Test func everyTitleIsFilledIn() {
        for shortcut in KeyShortcuts.all {
            #expect(!shortcut.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(shortcut.action)")
            #expect(!shortcut.key.isEmpty)
            #expect(!shortcut.pages.isEmpty)
        }
    }

    @Test func eachActionHasAShortcutOnItsPages() {
        // N is two actions on different pages, and nothing else repeats.
        let actions = KeyShortcuts.all.map(\.action)
        #expect(Set(actions).count == actions.count)
        #expect(Set(actions) == Set(ShortcutAction.allCases))
    }

    @Test func theSameKeysOnDifferentPagesDoNotClash() {
        let add = KeyShortcuts.shortcut(.addTransaction, on: .forecast)
        let bill = KeyShortcuts.shortcut(.addBill, on: .bills)
        #expect(add?.keys == "⌘N")
        #expect(bill?.keys == "⌘N")
        #expect(bill?.title == "Add bill or income")
        #expect(KeyShortcuts.shortcut(.addTransaction, on: .bills) == nil)
        #expect(KeyShortcuts.shortcut(.addBill, on: .forecast) == nil)
    }

    /// A clash is caught when one is made: the same keys on a page and on `everywhere`.
    @Test func aClashIsFound() {
        let page = KeyShortcut(.refresh, key: "f", title: "A", on: [.forecast])
        let everywhere = KeyShortcut(.search, key: "f", title: "B", on: [.everywhere])
        let other = KeyShortcut(.thisMonth, key: "f", title: "C", on: [.bills])
        #expect(page.collides(with: everywhere))
        #expect(!page.collides(with: other))
        #expect(!page.collides(with: KeyShortcut(.save, key: "f", modifiers: [.command, .shift], title: "D", on: [.forecast])))
    }

    @Test func theTabsAreCommandOneToFive() {
        for number in 1...5 {
            let shortcut = KeyShortcuts.tab(number)
            #expect(shortcut?.key == String(number))
            #expect(shortcut?.modifiers == [.command])
            #expect(shortcut?.works(on: .calendar) == true)
        }
        #expect(KeyShortcuts.tab(0) == nil)
        #expect(KeyShortcuts.tab(6) == nil)
        #expect(KeyShortcuts.shortcut(.search, on: .reports)?.keys == "⌘F")
    }

    @Test func monthMovesWorkWhereAMonthIs() {
        for page in [ShortcutPage.forecast, .calendar, .compare] {
            #expect(KeyShortcuts.shortcut(.previousMonth, on: page)?.keys == "⌘[")
            #expect(KeyShortcuts.shortcut(.nextMonth, on: page)?.keys == "⌘]")
        }
        #expect(KeyShortcuts.shortcut(.previousMonth, on: .bills) == nil)
        #expect(KeyShortcuts.shortcut(.thisMonth, on: .forecast)?.keys == "⌘T")
    }

    @Test func editorsSaveAndCancel() {
        #expect(KeyShortcuts.shortcut(.save, on: .editor)?.keys == "⌘↩")
        #expect(KeyShortcuts.shortcut(.cancel, on: .editor)?.keys == "⎋")
        #expect(KeyShortcuts.shortcut(.save, on: .forecast) == nil)
    }

    @Test func settingsIsAPlace() {
        #expect(ShortcutPage(place: "more") == .settings)
        #expect(ShortcutPage(place: "forecast") == .forecast)
        #expect(ShortcutPage(place: "nonsense") == nil)
    }

    // MARK: - Menus

    @Test func aLinesMenuIsItsSwipes() {
        #expect(RowAction.forLine(canChange: true, isPaid: false) == [.markPaid, .edit, .delete])
        // A paid line offers Edit, not Mark paid, as its swipe does (#160).
        #expect(RowAction.forLine(canChange: true, isPaid: true) == [.edit, .delete])
        #expect(RowAction.forLine(canChange: false, isPaid: false).isEmpty)
    }

    @Test func aSearchResultAlsoOpensInForecast() {
        #expect(RowAction.forLine(canChange: true, isPaid: false, inSearch: true) == [.markPaid, .edit, .openInForecast, .delete])
        // Read-only: it can still be opened in Forecast.
        #expect(RowAction.forLine(canChange: false, isPaid: false, inSearch: true) == [.openInForecast])
    }

    @Test func aBillsMenuIsItsSwipesAndEdit() {
        #expect(RowAction.forBill(canChange: true, expired: false, hasDatesAhead: true) == [.edit, .skipDate, .end])
        #expect(RowAction.forBill(canChange: true, expired: false, hasDatesAhead: false) == [.edit, .end])
        #expect(RowAction.forBill(canChange: true, expired: true, hasDatesAhead: false) == [.edit])
        #expect(RowAction.forBill(canChange: false, expired: false, hasDatesAhead: true).isEmpty)
    }

    @Test func destructiveItemsAreMarkedAndEveryTitleIsFilledIn() {
        #expect(RowAction.allCases.filter(\.isDestructive) == [.delete, .end])
        for action in RowAction.allCases {
            #expect(!action.title.isEmpty && !action.symbol.isEmpty)
        }
    }
}
