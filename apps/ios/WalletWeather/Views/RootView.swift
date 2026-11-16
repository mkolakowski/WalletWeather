import SwiftUI
import WalletWeatherKit

extension EnvironmentValues {
    /// Switches this window to another place, as Search does to show an
    /// account in Forecast (#112).
    @Entry var openPlace: @MainActor (RootView.Place) -> Void = { _ in }
    /// The tab bar runs down the side of a screen tall enough for six
    /// buttons, so a fourth page fits (#174).
    @Entry var barOnSide = false
}

/// The frame every page sits in: the pages chosen for the tab bar (#158),
/// then Settings, in the system's own tab bar, and the round button beside
/// it for Search. iOS stands the bar down the right edge on the iPhone Duo
/// in most poses, with room for four pages; along the bottom it shows five
/// buttons before adding a More of its own, so three pages show there and a
/// fourth waits in Settings (#174). Neither the window's shape nor its size
/// classes say where the bar is (the closed Duo is a tall compact window with
/// the bar on the side), so the pages measure it: a bar along the bottom adds
/// to their bottom inset. A side bar in a window of compact height (the
/// closed Duo on its side) has room for five buttons too. A page's own actions, such as +, sit in its top
/// corner. Which place is open is kept per window, so closing or opening the
/// Duo keeps it.
struct RootView: View {
    /// `more` is the Settings tab: it keeps its old name, since windows
    /// and scene storage already hold it (#174).
    enum Place: String, Codable, Hashable {
        case dashboard, forecast, bills, calendar, netWorth, budgets, reports, more, search

        init(_ page: TabPage) { self = Place(rawValue: page.rawValue) ?? .more }
        var page: TabPage? { TabPage(rawValue: rawValue) }
    }

    /// The page a new window was opened on (#90); nil for the first window.
    var start: Place?
    @SceneStorage("place") private var place: Place = .dashboard
    @State private var started = false
    /// The window's own bottom inset (the home indicator), and the open
    /// page's, which includes a bar along the bottom; nil until measured.
    @State private var windowBottom: CGFloat = 0
    @State private var pageBottom: CGFloat?
    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var settings
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Down the side when the page's bottom inset is no more than the
    /// window's (a bar along the bottom is at least 30 points tall), and in
    /// a window of regular height, where the side bar holds six buttons.
    private var barOnSide: Bool {
        guard let pageBottom, verticalSizeClass == .regular else { return false }
        return pageBottom - windowBottom < 20
    }

    private var shown: [TabPage] { TabPage.shown(settings.tabs, onSide: barOnSide) }

    var body: some View {
        TabView(selection: $place) {
            ForEach(shown) { page in
                Tab(page.title, systemImage: page.symbol, value: Place(page)) {
                    page.view(embedded: false).modifier(MeasureBottom(bottom: $pageBottom))
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .more) {
                SettingsView().modifier(MeasureBottom(bottom: $pageBottom))
            }
            Tab(value: .search, role: .search) {
                SearchView().modifier(MeasureBottom(bottom: $pageBottom))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { windowBottom = $0 }
        .environment(\.openPlace) { place = $0 }
        .environment(\.barOnSide, barOnSide)
        // A page taken out of the bar while open, or a fourth page when the
        // bar moves to the bottom: Settings, where it's listed now.
        .onChange(of: shown) { _, shown in
            if pageBottom != nil, let page = place.page, !shown.contains(page) { place = .more }
        }
        .onAppear {
            if let start, !started { place = start }
            // Debug only: `WW_DEBUG_NEW_WINDOW=<place>` opens a second window.
            if start == nil, !started, let second = AppModel.debugSetting("WW_DEBUG_NEW_WINDOW").flatMap(Place.init(rawValue:)) {
                openWindow(value: second)
            }
            started = true
            if let debug = AppModel.debugSetting("WW_DEBUG_PLACE").flatMap(Place.init(rawValue:)) { place = debug }
            if let page = place.page, !settings.tabs.contains(page) { place = settings.tabs.first.map(Place.init) ?? .more }
        }
    }
}

/// Reports the page's bottom safe-area inset, which includes the tab bar
/// when it's along the bottom (#174).
private struct MeasureBottom: ViewModifier {
    @Binding var bottom: CGFloat?

    func body(content: Content) -> some View {
        // The keyboard adds 200 points or more: not a tab bar, so not counted.
        content.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { if $0 < 200 { bottom = $0 } }
    }
}
