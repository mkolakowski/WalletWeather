import SwiftUI
import WalletWeatherKit

/// The frame every page sits in: the five places of the web app's phone
/// bar, in the system's own tab bar (which iOS stands down the right edge on
/// the iPhone Duo, closed or open on its side), and the round button beside
/// it for Search. A page's own actions, such as +, sit in its top corner. Which
/// place is open is kept per window, so closing or opening the Duo keeps it.
struct RootView: View {
    enum Place: String, Codable, Hashable { case dashboard, forecast, bills, calendar, more, search }

    /// The page a new window was opened on (#90); nil for the first window.
    var start: Place?
    @SceneStorage("place") private var place: Place = .dashboard
    @State private var started = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView(selection: $place) {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: .dashboard) {
                DashboardView()
            }
            Tab("Forecast", systemImage: "chart.line.uptrend.xyaxis", value: .forecast) {
                ForecastView()
            }
            Tab("Bills & income", systemImage: "arrow.left.arrow.right", value: .bills) {
                BillsView()
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }
            Tab("More", systemImage: "ellipsis.circle", value: .more) {
                MoreView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .onAppear {
            if let start, !started { place = start }
            // Debug only: `WW_DEBUG_NEW_WINDOW=<place>` opens a second window.
            if start == nil, !started, let second = AppModel.debugSetting("WW_DEBUG_NEW_WINDOW").flatMap(Place.init(rawValue:)) {
                openWindow(value: second)
            }
            started = true
            if let debug = AppModel.debugSetting("WW_DEBUG_PLACE").flatMap(Place.init(rawValue:)) { place = debug }
        }
    }
}
