import SwiftUI
import WalletWeatherKit

/// The frame every page sits in: the pages chosen for the tab bar (#158; at
/// first the web app's phone bar), then More, in the system's own tab bar
/// (which iOS stands down the right edge on the iPhone Duo, closed or open
/// on its side), and the round button beside it for Search. A page's own
/// actions, such as +, sit in its top corner. Which place is open is kept
/// per window, so closing or opening the Duo keeps it.
struct RootView: View {
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
            Tab("More", systemImage: "ellipsis.circle", value: .more) {
                MoreView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        // A page taken out of the bar while open: More, where it's listed now.
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
