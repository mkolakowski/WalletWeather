/// The pages that can sit in the tab bar, and which do (#158): chosen in
/// More → This phone → Tab bar. More and Search are always there; up to
/// `maxInBar` pages fit beside them, and the rest are listed in More.
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

    /// The SF Symbol for its tab and its row in More.
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

    /// The bar as it came: the web app's phone bar.
    public static let defaultBar: [TabPage] = [.dashboard, .forecast, .bills, .calendar]

    /// Pages beside More and Search: more would send the rest of the bar
    /// into iOS's own overflow.
    public static let maxInBar = 4

    /// The bar from its stored form (raw values joined by commas): unknown
    /// and repeated pages are dropped and it's cut to `maxInBar`; nothing
    /// stored means the default. An empty string is a bar with only More.
    public static func bar(from stored: String?) -> [TabPage] {
        guard let stored else { return defaultBar }
        var seen = Set<TabPage>()
        let pages = stored.split(separator: ",").compactMap { TabPage(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return Array(pages.prefix(maxInBar))
    }

    public static func stored(_ bar: [TabPage]) -> String {
        bar.map(\.rawValue).joined(separator: ",")
    }

    /// The pages not in the bar, in their usual order: what More lists.
    public static func notIn(_ bar: [TabPage]) -> [TabPage] {
        allCases.filter { !bar.contains($0) }
    }
}
