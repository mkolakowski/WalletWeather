/// The pages that can sit in the tab bar, and which do (#158): chosen in
/// Settings → This iPhone → Tab bar. Settings and Search are always there;
/// three pages fit beside them when the bar is along the bottom and four when
/// it runs down the side (as on the iPhone Duo), and the rest are listed
/// under More pages in Settings (#174, #294).
public enum TabPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard, forecast, bills, calendar, netWorth, budgets, reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .forecast: "Forecast"
        case .bills: "Bills & income"
        case .calendar: "Calendar"
        case .netWorth: "Net worth"
        case .budgets: "Budgets"
        case .reports: "Reports"
        }
    }

    /// The SF Symbol for its tab and its row in Settings.
    public var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .forecast: "chart.line.uptrend.xyaxis"
        case .bills: "arrow.left.arrow.right"
        case .calendar: "calendar"
        case .netWorth: "chart.line.uptrend.xyaxis.circle"
        case .budgets: "chart.bar.doc.horizontal"
        case .reports: "doc.text.magnifyingglass"
        }
    }

    /// The bar as it comes (#174): the web app's phone bar without Calendar,
    /// which is the first page people swap in.
    public static let defaultBar: [TabPage] = [.dashboard, .forecast, .bills]

    /// Pages beside Settings and Search in a bar along the bottom (#174): iOS
    /// shows five buttons there, Search included, and tucks any more into a
    /// More list of its own. Four pages did that on an iPhone held upright.
    public static let maxAtBottom = 3

    /// Pages beside Settings and Search in a bar down the side of the
    /// screen, which has room for six buttons: the most a bar can hold.
    public static let maxInBar = 4

    /// How many pages fit where the bar is now.
    public static func room(onSide: Bool) -> Int { onSide ? maxInBar : maxAtBottom }

    /// The pages the bar shows where it is now: a fourth page waits, listed
    /// in Settings, while the bar is along the bottom.
    public static func shown(_ bar: [TabPage], onSide: Bool) -> [TabPage] {
        Array(bar.prefix(room(onSide: onSide)))
    }

    /// The bar from its stored form (raw values joined by commas): unknown
    /// and repeated pages are dropped and it's cut to `maxInBar`; nothing
    /// stored means the default. An empty string is a bar with only Settings
    /// and Search.
    public static func bar(from stored: String?) -> [TabPage] {
        guard let stored else { return defaultBar }
        var seen = Set<TabPage>()
        let pages = stored.split(separator: ",").compactMap { TabPage(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return Array(pages.prefix(maxInBar))
    }

    public static func stored(_ bar: [TabPage]) -> String {
        bar.map(\.rawValue).joined(separator: ",")
    }

    /// The pages not in the bar, in their usual order: what Settings lists.
    public static func notIn(_ bar: [TabPage]) -> [TabPage] {
        allCases.filter { !bar.contains($0) }
    }

    /// The bar with `page` in the place of `old`, keeping the order; the
    /// bar as it was when `old` isn't in it or `page` already is.
    public static func swapping(_ old: TabPage, for page: TabPage, in bar: [TabPage]) -> [TabPage] {
        guard let index = bar.firstIndex(of: old), !bar.contains(page) else { return bar }
        var swapped = bar
        swapped[index] = page
        return swapped
    }
}
