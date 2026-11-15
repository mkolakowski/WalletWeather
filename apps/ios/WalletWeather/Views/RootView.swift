import SwiftUI
import WalletWeatherKit

/// The frame every page sits in: the five places of the web app's phone
/// bar, in the system's own tab bar (which iOS stands down the right edge on
/// the iPhone Duo, closed or open on its side), and the round button beside
/// it for Search. A page's own actions, such as +, sit in its top corner. Which
/// place is open is kept per window, so closing or opening the Duo keeps it.
struct RootView: View {
    enum Place: String { case dashboard, forecast, bills, calendar, more, search }

    @SceneStorage("place") private var place: Place = .dashboard

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
            if let debug = AppModel.debugSetting("WW_DEBUG_PLACE").flatMap(Place.init(rawValue:)) { place = debug }
        }
    }
}
