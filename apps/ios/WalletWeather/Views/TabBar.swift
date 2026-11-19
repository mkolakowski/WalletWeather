import SwiftUI
import WalletWeatherKit

// Choosing the tab bar's pages (#158).

extension EnvironmentValues {
    /// The page is pushed inside Settings' navigation rather than standing in
    /// its own tab, so it doesn't start a navigation stack of its own.
    @Entry var embeddedPage = false
}

/// A page's own navigation stack, left out when the page is pushed from
/// Settings (a stack inside a stack breaks navigation).
struct PageStack<Content: View>: View {
    @Environment(\.embeddedPage) private var embedded
    @ViewBuilder let content: Content

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }
}

extension TabPage {
    /// The page itself: in its tab (with its own stack), or pushed from Settings.
    @ViewBuilder
    func view(embedded: Bool) -> some View {
        switch self {
        case .dashboard: DashboardView().environment(\.embeddedPage, embedded)
        case .forecast: ForecastView().environment(\.embeddedPage, embedded)
        case .bills: BillsView().environment(\.embeddedPage, embedded)
        case .calendar: CalendarView().environment(\.embeddedPage, embedded)
        case .netWorth: PageStack { ServerOnly(page: .netWorth) { NetWorthView() } }.environment(\.embeddedPage, embedded)
        case .budgets: PageStack { ServerOnly(page: .budgets) { BudgetsView() } }.environment(\.embeddedPage, embedded)
        case .reports: PageStack { ServerOnly(page: .reports) { ReportsView() } }.environment(\.embeddedPage, embedded)
        }
    }
}

/// Settings → This phone → Tab bar: the pages in the bar (drag to reorder,
/// Swap for another page, or delete to move it into Settings), then the
/// others (Add while there's room, or Swap in for a page in the bar, #174).
/// Settings and Search always stay. Room is three pages with the bar along
/// the bottom and four down the side; a fourth page saved down the side is
/// kept, marked, while the bar is along the bottom.
struct TabBarSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.barOnSide) private var barOnSide

    var body: some View {
        let others = TabPage.notIn(settings.tabs)
        let room = TabPage.room(onSide: barOnSide)
        let full = settings.tabs.count >= room
        List {
            Group {
                Section {
                    if settings.tabs.isEmpty {
                        Text("Only Settings and Search.").foregroundStyle(.secondary)
                    }
                    ForEach(settings.tabs) { page in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(page.title, systemImage: page.symbol)
                                if let index = settings.tabs.firstIndex(of: page), index >= room {
                                    Text("Shows when the bar has room: down the side of a tall screen").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !others.isEmpty {
                                Menu {
                                    ForEach(others) { other in
                                        Button(other.title, systemImage: other.symbol) {
                                            settings.tabs = TabPage.swapping(page, for: other, in: settings.tabs)
                                        }
                                    }
                                } label: {
                                    Text("Swap")
                                }
                                .accessibilityLabel("Swap \(page.title) for another page")
                            }
                        }
                    }
                    .onMove { settings.tabs.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { settings.tabs.remove(atOffsets: $0) }
                } header: {
                    Text("In the tab bar")
                } footer: {
                    Text("Drag to change the order, Swap to put another page in that place, or delete to move a page into Settings. Settings and Search are always in the bar. Beside them fit \(TabPage.maxAtBottom) pages, or \(TabPage.maxInBar) when the bar runs down the side of a tall screen, as on the iPhone Duo.")
                }
                Section {
                    if others.isEmpty {
                        Text("Every page is in the tab bar.").foregroundStyle(.secondary)
                    }
                    ForEach(others) { page in
                        HStack {
                            Label(page.title, systemImage: page.symbol)
                            Spacer()
                            if !full {
                                Button("Add") { settings.tabs.append(page) }
                                    .accessibilityLabel("Add \(page.title) to the tab bar")
                            } else {
                                Menu {
                                    ForEach(settings.tabs) { old in
                                        Button("In place of \(old.title)", systemImage: old.symbol) {
                                            settings.tabs = TabPage.swapping(old, for: page, in: settings.tabs)
                                        }
                                    }
                                } label: {
                                    Text("Swap in")
                                }
                                .accessibilityLabel("Swap \(page.title) into the tab bar")
                            }
                        }
                        .moveDisabled(true)
                        .deleteDisabled(true)
                    }
                } header: {
                    Text("In Settings")
                } footer: {
                    Text("These are listed at the top of Settings.")
                }
                Section {
                    Button("Back to the usual tab bar") { settings.tabs = TabPage.defaultBar }
                        .disabled(settings.tabs == TabPage.defaultBar)
                }
            }
            .listRowBackground(Palette.row)
        }
        .environment(\.editMode, .constant(.active))  // drag handles, always
        .scrollContentBackground(.hidden)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Tab bar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
