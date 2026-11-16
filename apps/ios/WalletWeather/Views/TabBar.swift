import SwiftUI
import WalletWeatherKit

// Choosing the tab bar's pages (#158).

extension EnvironmentValues {
    /// The page is pushed inside More's navigation rather than standing in
    /// its own tab, so it doesn't start a navigation stack of its own.
    @Entry var embeddedPage = false
}

/// A page's own navigation stack, left out when the page is pushed from
/// More (a stack inside a stack breaks navigation).
struct PageStack<Content: View>: View {
    @Environment(\.embeddedPage) private var embedded
    @ViewBuilder let content: Content

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }
}

extension TabPage {
    /// The page itself: in its tab (with its own stack), or pushed from More.
    @ViewBuilder
    func view(embedded: Bool) -> some View {
        switch self {
        case .dashboard: DashboardView().environment(\.embeddedPage, embedded)
        case .forecast: ForecastView().environment(\.embeddedPage, embedded)
        case .bills: BillsView().environment(\.embeddedPage, embedded)
        case .calendar: CalendarView().environment(\.embeddedPage, embedded)
        case .netWorth: PageStack { NetWorthView() }.environment(\.embeddedPage, embedded)
        case .budgets: PageStack { BudgetsView() }.environment(\.embeddedPage, embedded)
        case .reports: PageStack { ReportsView() }.environment(\.embeddedPage, embedded)
        }
    }
}

/// More → This phone → Tab bar: the pages in the bar (drag to reorder,
/// switch off to move into More), then the others (switch on to add, while
/// there's room). More and Search always stay.
struct TabBarSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Group {
                Section {
                    if settings.tabs.isEmpty {
                        Text("Only More and Search.").foregroundStyle(.secondary)
                    }
                    ForEach(settings.tabs) { page in
                        Toggle(isOn: Binding(get: { true }, set: { if !$0 { settings.tabs.removeAll { $0 == page } } })) {
                            Label(page.title, systemImage: page.symbol)
                        }
                    }
                    .onMove { settings.tabs.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("In the tab bar")
                } footer: {
                    Text("Drag to change the order. More and Search are always in the bar, and up to \(TabPage.maxInBar) pages fit beside them.")
                }
                Section {
                    let others = TabPage.notIn(settings.tabs)
                    if others.isEmpty {
                        Text("Every page is in the tab bar.").foregroundStyle(.secondary)
                    }
                    ForEach(others) { page in
                        Toggle(isOn: Binding(get: { false }, set: { if $0 { settings.tabs.append(page) } })) {
                            Label(page.title, systemImage: page.symbol)
                        }
                        .disabled(settings.tabs.count >= TabPage.maxInBar)
                    }
                } header: {
                    Text("In More")
                } footer: {
                    if settings.tabs.count >= TabPage.maxInBar {
                        Text("The tab bar is full. Switch a page off above to make room.")
                    }
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
