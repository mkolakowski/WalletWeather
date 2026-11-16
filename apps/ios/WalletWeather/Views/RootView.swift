import SwiftUI
import WalletWeatherKit

extension EnvironmentValues {
    /// Switches this window to another place, as Search does to show an
    /// account in Forecast (#112).
    @Entry var openPlace: @MainActor (RootView.Place) -> Void = { _ in }
}

/// The frame every page sits in: the pages chosen for the tab bar (#158;
/// three, #174), then Settings, in the system's own tab bar (which iOS
/// stands down the right edge on the iPhone Duo, closed or open on its
/// side), and the round button beside it for Search. Five in all, so iOS
/// never adds a More of its own. A page's own actions, such as +, sit in its
/// top corner. Which place is open is kept per window, so closing or opening
/// the Duo keeps it.
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
    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView(selection: $place) {
            ForEach(settings.tabs) { page in
                Tab(page.title, systemImage: page.symbol, value: Place(page)) {
                    page.view(embedded: false)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .more) {
                SettingsView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .environment(\.openPlace) { place = $0 }
        // A page taken out of the bar while open: Settings, where it's listed now.
        .onChange(of: settings.tabs) { _, tabs in
            if let page = place.page, !tabs.contains(page) { place = .more }
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
