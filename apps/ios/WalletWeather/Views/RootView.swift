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
    /// ⌘F's count, which Search watches (#307), and the Debug shortcut table.
    @State private var searchFocusRequest = 0
    @State private var showingShortcutTable = false
    /// Debug only: `WW_DEBUG_WIDGETS=<mode>` shows the widgets' faces (#318).
    @State private var widgetGallery: String?
    /// The window's own bottom inset (the home indicator), and the open
    /// page's, which includes a bar along the bottom; nil until measured.
    @State private var windowBottom: CGFloat = 0
    @State private var pageBottom: CGFloat?
    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Down the side when the page's bottom inset is no more than the
    /// window's (a bar along the bottom is at least 30 points tall), and in
    /// a window of regular height, where the side bar holds six buttons.
    private var barOnSide: Bool {
        guard let pageBottom, verticalSizeClass == .regular else { return false }
        return pageBottom - windowBottom < 20
    }

    private var shown: [TabPage] { TabPage.shown(settings.tabs, onSide: barOnSide) }

    /// The bar's places in order, for ⌘1 to ⌘5: the pages shown, then
    /// Settings, then Search (#307). These only change tab, so they open no
    /// connection and skip nothing the lock asks for.
    private var tabShortcuts: [ShortcutHandler] {
        let places: [(Place, String)] = shown.map { (Place($0), $0.title) } + [(.more, "Settings"), (.search, "Search")]
        let actions: [ShortcutAction] = [.tab1, .tab2, .tab3, .tab4, .tab5]
        let tabs = zip(actions, places).map { action, entry in
            ShortcutHandler(action, title: "Go to \(entry.1)") { place = entry.0 }
        }
        return tabs + [ShortcutHandler(.search) {
            searchFocusRequest += 1
            place = .search
        }]
    }

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
        .environment(\.searchFocusRequest, searchFocusRequest)
        .pageShortcuts(.everywhere, tabShortcuts)
        // Debug only: `WW_DEBUG_SHORTCUTS=1` shows the shortcut table as a sheet (#307).
        .sheet(isPresented: $showingShortcutTable) { ShortcutTableSheet() }
        #if DEBUG
        .fullScreenCover(item: Binding(get: { widgetGallery.map(GalleryMode.init) }, set: { widgetGallery = $0?.id })) {
            WidgetGallery(mode: $0.id)
        }
        #endif
        .environment(\.barOnSide, barOnSide)
        // A page taken out of the bar while open, or a fourth page when the
        // bar moves to the bottom: Settings, where it's listed now.
        .onChange(of: shown) { _, shown in
            if pageBottom != nil, let page = place.page, !shown.contains(page) { place = .more }
        }
        // A widget tapped (#318): its connection in front, then its page,
        // in the first window to take it.
        .onChange(of: model.widgetOpen, initial: true) { _, open in
            guard let open else { return }
            model.widgetOpen = nil
            Task {
                guard let target = await model.follow(open) else { return }
                if let page = target.page, !shown.contains(page) {
                    place = .more   // not in the tab bar: Settings lists it under More pages
                } else {
                    place = target
                }
            }
        }
        .onAppear {
            if let start, !started { place = start }
            // Debug only: `WW_DEBUG_NEW_WINDOW=<place>` opens a second window.
            if start == nil, !started, let second = AppModel.debugSetting("WW_DEBUG_NEW_WINDOW").flatMap(Place.init(rawValue:)) {
                openWindow(value: second)
            }
            started = true
            if AppModel.debugSetting("WW_DEBUG_SHORTCUTS") == "1" { showingShortcutTable = true }
            // Debug only: after the summary has had a moment to be written.
            if let mode = AppModel.debugSetting("WW_DEBUG_WIDGETS") {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    widgetGallery = mode
                }
            }
            // Debug only: `WW_DEBUG_SETTINGS=<page>` opens Settings on that page (#294).
            // `WW_DEBUG_COPY` opens Move to a server with Copy to a server over it (#328).
            if AppModel.debugSetting("WW_DEBUG_SETTINGS") != nil || AppModel.debugSetting("WW_DEBUG_COPY") != nil { place = .more }
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

#if DEBUG
/// The Debug widget gallery's mode, as a sheet's item.
private struct GalleryMode: Identifiable {
    let id: String
    init(_ id: String) { self.id = id }
}
#endif
