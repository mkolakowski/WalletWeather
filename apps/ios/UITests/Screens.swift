import Foundation

/// One stop on the walk (Plans/ios-ui-review.md, phase 2, #345): a name, the
/// Debug launch settings that open the app there (`apps/ios/README.md`,
/// "Screenshots without signing in by hand"), and any taps that follow.
struct Screen {
    /// What the app opens on.
    enum Household {
        /// "Try the demo": sample numbers, nothing saved, nothing contacted.
        case demo
        /// The household on this iPhone, started again as the small sample
        /// one (`WW_DEBUG_LOCAL=sample`). It replaces the simulator's own.
        case sample
        /// Whatever the launch settings say (the first screens).
        case asGiven
    }

    enum Step {
        /// Tap the first button, cell, link or text with this label.
        case tap(String)
        /// The same, when it's there; no finding when it isn't.
        case tapIfThere(String)
        case type(String)
        case wait(Double)
    }

    /// Stable: the pictures and findings are filed under it.
    let name: String
    var household: Household = .demo
    var settings: [String: String] = [:]
    var steps: [Step] = []
    /// False for a sheet or a state that would be lost by scrolling.
    var scrolls = true
    /// Words that have to be on the screen for it to be the one its name
    /// says: a launch setting that has stopped working would otherwise have
    /// the walk reviewing the Dashboard under another name.
    var shows: String?
    /// Checks this screen is known to trip for a good reason, each with it.
    var expected: [String: String] = [:]

    init(_ name: String, _ household: Household = .demo, _ settings: [String: String] = [:], shows: String? = nil,
         steps: [Step] = [], scrolls: Bool = true, expected: [String: String] = [:]) {
        self.name = name
        self.household = household
        self.settings = settings
        self.shows = shows
        self.steps = steps
        self.scrolls = scrolls
        self.expected = expected
    }
}

extension Screen {
    /// The Calendar in the bar's first place: along the bottom of an ordinary
    /// iPhone the bar holds three pages, and a fourth is left out.
    private static let everyTab = "calendar,dashboard,forecast"
    private static let moreTabs = "netWorth,budgets,reports"

    /// The walk, in order. A new page, sheet or state gets a line here in
    /// the change that adds it (and a Debug launch setting to open it, when
    /// taps can't reach it).
    static let all: [Screen] = [
        // The checks checking themselves: a Debug-only screen of planted faults.
        Screen("self-test", .demo, ["WW_DEBUG_FAULTS": "1"], shows: "Planted faults", scrolls: false),

        // The pages.
        Screen("dashboard", .demo, ["WW_DEBUG_PLACE": "dashboard"], shows: "Balance today"),
        Screen("forecast", .demo, ["WW_DEBUG_PLACE": "forecast"], shows: "All lines"),
        Screen("bills", .demo, ["WW_DEBUG_PLACE": "bills"], shows: "Bills a month"),
        Screen("calendar", .demo, ["WW_DEBUG_PLACE": "calendar", "WW_DEBUG_TABS": everyTab], shows: "Pick one account"),
        Screen("calendar-account", .demo, ["WW_DEBUG_PLACE": "calendar", "WW_DEBUG_TABS": everyTab, "WW_DEBUG_ACCOUNT": "Checking"], shows: "Calendar"),
        Screen("net-worth", .demo, ["WW_DEBUG_PLACE": "netWorth", "WW_DEBUG_TABS": moreTabs], shows: "Net worth today"),
        Screen("budgets", .demo, ["WW_DEBUG_PLACE": "budgets", "WW_DEBUG_TABS": moreTabs], shows: "Budgeted"),
        Screen("reports", .demo, ["WW_DEBUG_PLACE": "reports", "WW_DEBUG_TABS": moreTabs], shows: "This month's spending"),
        Screen("search-empty", .demo, ["WW_DEBUG_PLACE": "search"], shows: "Search everything", scrolls: false),
        Screen("search-results", .demo, ["WW_DEBUG_PLACE": "search", "WW_DEBUG_SEARCH": "gro"], shows: "Grocery store"),
        Screen("search-nothing", .demo, ["WW_DEBUG_PLACE": "search", "WW_DEBUG_SEARCH": "zzzz"], shows: "zzzz", scrolls: false),

        // Forecast's states and sheets.
        Screen("forecast-filtered", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_FILTER": "Groceries"], shows: "Warehouse club"),
        Screen("forecast-confirm", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_CONFIRM": "1"], shows: "Paid as planned"),
        Screen("forecast-compare", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_COMPARE": "1"], shows: "Compare"),
        Screen("forecast-undo", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_UNDO": "Rent"], shows: "Rent marked paid", scrolls: false,
               expected: ["text-overlap": "The Undo bar floats over the list, by design (#315)."]),
        Screen("forecast-line-menu", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_CONTEXT": "1"], shows: "Line menu", scrolls: false),
        Screen("forecast-drop", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_DROP": "csv"], shows: "Drop to import", scrolls: false),
        Screen("line-editor", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_OPEN_LINE": "Rent"], shows: "Planned amount"),
        Screen("line-editor-save-failed", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_OPEN_LINE": "Rent", "WW_DEBUG_FAIL_SAVE": "offline"], shows: "You're offline", scrolls: false),
        Screen("add-transaction", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_ADD_NAME": "Gr"], shows: "Add to Checking"),

        // Bills & income and the Calendar.
        // (The launch setting that opens a bill doesn't on an ordinary iPhone; a tap does.)
        Screen("bill-editor", .demo, ["WW_DEBUG_PLACE": "bills"], shows: "Repeats", steps: [.tap("Rent")]),
        Screen("calendar-day", .demo, ["WW_DEBUG_PLACE": "calendar", "WW_DEBUG_TABS": everyTab, "WW_DEBUG_ACCOUNT": "Checking", "WW_DEBUG_DAY": "today"], shows: "Calendar"),
        Screen("calendar-drop", .demo, ["WW_DEBUG_PLACE": "calendar", "WW_DEBUG_TABS": everyTab, "WW_DEBUG_ACCOUNT": "Checking", "WW_DEBUG_DROP": "day"], shows: "Calendar", scrolls: false),

        // Settings and its pages.
        Screen("settings", .demo, ["WW_DEBUG_PLACE": "more"], shows: "More pages"),
        Screen("settings-connections", .demo, ["WW_DEBUG_SETTINGS": "connections", "WW_DEBUG_CONNECTIONS": "sample"], shows: "Connections"),
        Screen("settings-connection", .demo, ["WW_DEBUG_SETTINGS": "connection"], shows: "Sample numbers built into the app"),
        Screen("settings-bank", .demo, ["WW_DEBUG_SETTINGS": "bank"], shows: "Sync now"),
        Screen("settings-unmatched", .demo, ["WW_DEBUG_PLACE": "more", "WW_DEBUG_UNMATCHED": "1"], shows: "Unmatched"),
        Screen("settings-tags", .demo, ["WW_DEBUG_SETTINGS": "tags"], shows: "Auto-tag rules"),
        Screen("tag-editor", .demo, ["WW_DEBUG_SETTINGS": "tags", "WW_DEBUG_TAG_EDITOR": "1"], shows: "New tag", scrolls: false),
        Screen("settings-appearance", .demo, ["WW_DEBUG_SETTINGS": "appearance", "WW_DEBUG_CUSTOM_THEMES": "sample"], shows: "AMOLED black"),
        Screen("theme-editor", .demo, ["WW_DEBUG_SETTINGS": "appearance", "WW_DEBUG_CUSTOM_THEMES": "sample", "WW_DEBUG_THEME_EDITOR": "custom-light"], shows: "Edit theme"),
        Screen("settings-privacy", .demo, ["WW_DEBUG_SETTINGS": "privacy"], shows: "In the app switcher"),
        Screen("settings-reminders", .demo, ["WW_DEBUG_SETTINGS": "reminders"], shows: "Bill due tomorrow"),
        Screen("settings-display", .demo, ["WW_DEBUG_SETTINGS": "display"], shows: "Date format"),
        Screen("settings-help", .demo, ["WW_DEBUG_SETTINGS": "help"], shows: "Show Getting started again"),
        Screen("settings-tab-bar", .demo, ["WW_DEBUG_SETTINGS": "tabBar"], shows: "In the tab bar"),
        Screen("settings-notice", .demo, ["WW_DEBUG_SETTINGS": "notice"], shows: "WalletWeather is a planning tool"),

        // Where you are: the chip, the lock's demo, the keys.
        Screen("chip-menu", .demo, ["WW_DEBUG_PLACE": "dashboard", "WW_DEBUG_CONNECTIONS": "sample", "WW_DEBUG_CHIP_MENU": "1"], shows: "Manage connections", scrolls: false),
        Screen("locked-demo", .asGiven, ["WW_DEBUG_LOCKED_DEMO": "1", "WW_DEBUG_CONNECTIONS": "sample", "WW_DEBUG_PLACE": "dashboard"], shows: "Dashboard", scrolls: false),
        Screen("shortcut-table", .demo, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_SHORTCUTS": "1"], shows: "Keyboard shortcuts"),
        Screen("widgets", .demo, ["WW_DEBUG_PLACE": "dashboard", "WW_DEBUG_WIDGETS": "amounts"], shows: "With amounts", steps: [.wait(3)],
               expected: ["off-edge": "The Debug gallery scrolls sideways, one widget size after another."]),

        // The first screens.
        Screen("welcome", .asGiven, ["WW_DEBUG_WELCOME": "1"], shows: "How would you like to use it?"),
        Screen("connect", .asGiven, ["WW_DEBUG_ADDRESS": "https://ww.example.com"], shows: "Your server"),
        Screen("connect-other-ways", .asGiven, ["WW_DEBUG_ADDRESS": "https://ww.example.com", "WW_DEBUG_OTHER_WAYS": "1"], shows: "Email and password"),

        // The household on this iPhone: what the demo can't show.
        Screen("local-dashboard", .sample, ["WW_DEBUG_PLACE": "dashboard"], shows: "Getting started"),
        Screen("local-getting-started-task", .sample, ["WW_DEBUG_PLACE": "dashboard", "WW_DEBUG_START": "tour"], scrolls: false),
        Screen("local-settings", .sample, ["WW_DEBUG_PLACE": "more"], shows: "On this iPhone"),
        Screen("local-backup", .sample, ["WW_DEBUG_SETTINGS": "backup"], shows: "Back up to iCloud Drive"),
        Screen("local-move", .sample, ["WW_DEBUG_SETTINGS": "move"], shows: "Export for a server"),
        Screen("local-bank", .sample, ["WW_DEBUG_SETTINGS": "bank", "WW_DEBUG_BANK": "connected"], shows: "Example Bank"),
        Screen("local-unmatched", .sample, ["WW_DEBUG_PLACE": "more", "WW_DEBUG_BANK": "unmatched"], shows: "Unmatched"),
        Screen("local-change-transfer", .sample, ["WW_DEBUG_PLACE": "forecast", "WW_DEBUG_CHANGE_TRANSFER": "1"], shows: "Change transfer", scrolls: false),
        Screen("local-copy-to-server", .sample, ["WW_DEBUG_COPY": "sample", "WW_DEBUG_CONNECTIONS": "sample"], shows: "Copy to a server", scrolls: false),
    ]
}
