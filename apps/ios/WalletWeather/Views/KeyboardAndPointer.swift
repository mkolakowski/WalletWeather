import SwiftUI
import WalletWeatherKit

// Keyboard and pointer (duo-more phase 4, #307). The shortcuts come from the
// Kit's `KeyShortcuts` table, the row menus' items from `RowAction`, so what
// holding ⌘ lists, what a test checks and what a Debug sheet shows are one
// list. There is no setting for either: nobody would want a shortcut or a
// long-press menu off, and touch works as it did.

// MARK: - Shortcuts

extension KeyShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "return": .return
        case "escape": .escape
        default: KeyEquivalent(key.first ?? " ")
        }
    }

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) { result, modifier in
            switch modifier {
            case .command: result.insert(.command)
            case .shift: result.insert(.shift)
            case .option: result.insert(.option)
            case .control: result.insert(.control)
            }
        }
    }
}

/// One shortcut a page answers: what to do, whether it can now, and
/// optionally a title that says more than the table's (the tab bar's
/// buttons name the page they go to).
struct ShortcutHandler {
    let action: ShortcutAction
    var title: String?
    var enabled = true
    let run: () -> Void

    init(_ action: ShortcutAction, title: String? = nil, enabled: Bool = true, run: @escaping () -> Void) {
        self.action = action
        self.title = title
        self.enabled = enabled
        self.run = run
    }
}

extension View {
    /// The page answers these shortcuts. Each is a button out of sight (no
    /// size, no touch, hidden from VoiceOver) that carries the key and the
    /// title the system lists when ⌘ is held; one that can't run now is
    /// listed dimmed.
    func pageShortcuts(_ page: ShortcutPage, _ handlers: [ShortcutHandler]) -> some View {
        background {
            ZStack {
                ForEach(handlers.indices, id: \.self) { index in
                    let handler = handlers[index]
                    if let shortcut = KeyShortcuts.shortcut(handler.action, on: page) {
                        Button(handler.title ?? shortcut.title, action: handler.run)
                            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
                            .disabled(!handler.enabled)
                    }
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The table's key on a button that is already on screen: Save is ⌘↩,
    /// Cancel is Escape.
    func keyShortcut(_ action: ShortcutAction, on page: ShortcutPage = .editor) -> some View {
        modifier(TableShortcut(action: action, page: page))
    }
}

private struct TableShortcut: ViewModifier {
    let action: ShortcutAction
    let page: ShortcutPage

    func body(content: Content) -> some View {
        if let shortcut = KeyShortcuts.shortcut(action, on: page) {
            content.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// Goes up by one each time ⌘F is pressed: Search puts the cursor in its
    /// field when it changes (and when it opens after one).
    @Entry var searchFocusRequest = 0
}

// MARK: - A row's long-press menu

/// The menu on a row (long-press, or right-click with a pointer): the items
/// are the Kit's `RowAction`s, destructive ones in red. Nothing when the
/// person may do nothing to it.
struct RowMenu: ViewModifier {
    let actions: [RowAction]
    let perform: (RowAction) -> Void

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(actions, id: \.self) { action in
                    Button(action.title, systemImage: action.symbol, role: action.isDestructive ? .destructive : nil) {
                        perform(action)
                    }
                }
            }
        }
    }
}

/// A bill's menu: Edit, Skip a date…, End…, on Bills & income and in Search.
struct BillMenu: ViewModifier {
    let item: RecurringItem
    let editable: Bool
    var onEdit: ((RecurringItem) -> Void)?
    let onSkip: (RecurringItem) -> Void
    let onEnd: (RecurringItem) -> Void

    func body(content: Content) -> some View {
        let actions = RowAction.forBill(canChange: editable, expired: item.expired, hasDatesAhead: !item.nextDates.isEmpty)
            .filter { $0 != .edit || onEdit != nil }
        content.modifier(RowMenu(actions: actions) { action in
            switch action {
            case .edit: onEdit?(item)
            case .skipDate: onSkip(item)
            case .end: onEnd(item)
            default: break
            }
        })
    }
}

// MARK: - A Search result's actions

/// What a transaction in Search's lists (and a category's or tag's) can do
/// from its menu: Mark paid as planned with Undo, and Delete after asking.
/// One per list; `.hitActionsHost` shows what it holds.
@MainActor @Observable
final class HitActions {
    var undoOffer: UndoOffer?
    var pendingDelete: TransactionSearch.Hit?
    var problem: ListProblem?
    var paidCount = 0

    func markPaid(_ hit: TransactionSearch.Hit, model: AppModel, settings: AppSettings, reload: @escaping () async -> Void) {
        guard let client = model.client else { return }
        let line = hit.line
        let account = hit.accountId
        Task {
            do {
                try await client.save(line, draft: .paidAsPlanned(line, today: .today()), account: account)
                settings.start.done.insert(.markPaid)  // Getting started (#177)
                paidCount += 1
                undoOffer = UndoOffer(message: "\(line.description) marked paid") { [self] in
                    await undo(line, account: account, model: model, reload: reload)
                }
            } catch {
                problem = ListProblem(error)
            }
            await reload()
        }
    }

    /// Back to not paid at the line as it was; a failure shows the alert.
    private func undo(_ line: ForecastLine, account: Int, model: AppModel, reload: @escaping () async -> Void) async -> Bool {
        guard let client = model.client else { return false }
        var done = false
        do {
            try await client.save(line, draft: .unpaid(line, today: .today()), account: account)
            done = true
        } catch {
            problem = ListProblem(error)
        }
        await reload()
        return done
    }

    func delete(_ hit: TransactionSearch.Hit, model: AppModel, reload: @escaping () async -> Void) {
        guard let client = model.client else { return }
        Task {
            do { try await client.delete(hit.line) } catch { problem = ListProblem(error) }
            await reload()
        }
    }
}

extension View {
    /// The Undo bar, the delete question, the problem alert and the haptic
    /// for a list whose rows use `.hitMenu`.
    func hitActionsHost(_ state: HitActions, reload: @escaping () async -> Void) -> some View {
        modifier(HitActionsHost(state: state, reload: reload))
    }

    /// A transaction result's menu: Mark paid as planned, Edit, Open in
    /// Forecast, Delete: what this person may do to it.
    func hitMenu(_ hit: TransactionSearch.Hit, accounts: [Account], state: HitActions,
                 onEdit: @escaping () -> Void, reload: @escaping () async -> Void) -> some View {
        modifier(HitMenu(hit: hit, accounts: accounts, state: state, onEdit: onEdit, reload: reload))
    }
}

private struct HitActionsHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Bindable var state: HitActions
    let reload: () async -> Void

    func body(content: Content) -> some View {
        content
            .undoBar($state.undoOffer)
            .sensoryFeedback(.success, trigger: state.paidCount)
            .confirmationDialog(state.pendingDelete.map { "Delete \($0.description)?" } ?? "", isPresented: Binding(
                get: { state.pendingDelete != nil }, set: { if !$0 { state.pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: state.pendingDelete) { hit in
                Button("Delete", role: .destructive) { state.delete(hit, model: model, reload: reload) }
            } message: { _ in
                Text("This can't be undone.")
            }
            .problemAlert($state.problem)
    }
}

private struct HitMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openInForecast) private var openInForecast
    let hit: TransactionSearch.Hit
    let accounts: [Account]
    let state: HitActions
    let onEdit: () -> Void
    let reload: () async -> Void

    func body(content: Content) -> some View {
        let account = accounts.first { $0.id == hit.accountId }
        let canChange = account.map { model.canEdit($0) && hit.line.canEdit(onEditableAccount: true) } ?? false
        let actions = RowAction.forLine(canChange: canChange, isPaid: hit.line.isPaid, inSearch: account != nil)
        content.modifier(RowMenu(actions: actions) { action in
            switch action {
            case .markPaid: state.markPaid(hit, model: model, settings: settings, reload: reload)
            case .edit: onEdit()
            case .openInForecast: openInForecast(hit.accountId, false)
            case .delete: state.pendingDelete = hit
            default: break
            }
        })
    }
}

// MARK: - Pointer

extension View {
    /// A row that is a button: a pointer highlights it. Touch is unchanged.
    func pointerRow() -> some View {
        contentShape(.hoverEffect, Rectangle()).hoverEffect(.highlight)
    }

    /// A card that is a button: a pointer lifts it. Touch is unchanged.
    func pointerCard() -> some View {
        contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 22, style: .continuous)).hoverEffect(.lift)
    }
}

// MARK: - Debug sheets

/// `WW_DEBUG_SHORTCUTS=1` (Debug builds): the shortcut table as a sheet, for
/// pictures, since a script can't hold ⌘.
struct ShortcutTableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(KeyShortcuts.all) { shortcut in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortcut.title)
                        Text(shortcut.whereText).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(shortcut.keys).font(.body.monospaced()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("Keyboard shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// `WW_DEBUG_CONTEXT=1` (Debug builds): a line's long-press menu as a
/// sheet, the same items in the same order.
struct RowMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actions: [RowAction]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(actions, id: \.self) { action in
                        Label(action.title, systemImage: action.symbol)
                            .foregroundStyle(action.isDestructive ? Palette.bad : Color.primary)
                    }
                    if actions.isEmpty { Text("No actions: this person can't change it.").foregroundStyle(.secondary) }
                } footer: {
                    Text("The long-press (or right-click) menu of \(title).")
                }
            }
            .navigationTitle("Line menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
