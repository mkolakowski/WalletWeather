import XCTest

/// The simulator walk (Plans/ios-ui-review.md, phase 2, #345): opens the app
/// on every screen in `Screen.all`, in the demo, and on each one saves
/// pictures, runs Apple's accessibility audit and the checks in `Checks`,
/// and writes down what it measured. It looks for faults; it doesn't pin the
/// look, so a finding is written to the run's folder rather than failing the
/// test. `Scripts/ui-walk.sh` runs it once per configuration and
/// `Scripts/ui-report.py` reads what it wrote.
///
/// What it's told, through the test runner's environment
/// (`TEST_RUNNER_<name>` to xcodebuild):
/// - `WW_UI_OUT`: the folder to write into (required; without it nothing runs).
/// - `WW_UI_CONFIG`: this configuration's name, e.g. `duo-closed.light.large`.
/// - `WW_UI_LOOK`: `light`, `dark`, … (`WW_DEBUG_LOOK`).
/// - `WW_UI_TEXT`: `large` (the default), `xxxl`, `ax-l`, `ax-xxxl`.
/// - `WW_UI_DATES`: `iso` or `short` (`WW_DEBUG_DATES`).
/// - `WW_UI_TODAY`: the app's date and clock, pinned, e.g. `2026-11-15T10:00`.
/// - `WW_UI_ENV`: more launch settings for every screen, `NAME=value,NAME=value`.
/// - `WW_UI_ONLY`: screens to visit, by name or the start of one, with commas.
/// - `WW_UI_AUDIT`: `all` of Apple's audit, only its `contrast` part (a dark
///   look), only its `text` parts (a large text size), or `0` for none. It's
///   the slow part.
/// - `WW_UI_SCROLL`: how many screenfuls down to go on each screen (0 for the top only).
/// - `WW_UI_ROTATE=1`: also turn the phone on its side on the main pages.
@MainActor
final class WalkTests: XCTestCase {
    struct Options {
        let out: URL
        let config: String
        let look: String?
        let text: String
        let dates: String?
        let only: [String]
        let audit: String
        let scroll: Int
        let rotate: Bool
        /// `WW_UI_TODAY=2026-11-15T10:00`: the app's date and clock, pinned (`WW_DEBUG_TODAY`), for pictures that compare across days.
        let today: String?
        /// `WW_UI_TREE=1`: also write each screen's element tree as text.
        let tree: Bool
        /// `WW_UI_ENV=WW_DEBUG_TINT=none,…`: launch settings added to every screen's.
        let extra: [String: String]

        init?(_ environment: [String: String]) {
            guard let out = environment["WW_UI_OUT"], !out.isEmpty else { return nil }
            config = environment["WW_UI_CONFIG"] ?? "walk"
            self.out = URL(fileURLWithPath: out).appendingPathComponent(config)
            look = environment["WW_UI_LOOK"]
            text = environment["WW_UI_TEXT"] ?? "large"
            dates = environment["WW_UI_DATES"]
            only = (environment["WW_UI_ONLY"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            audit = environment["WW_UI_AUDIT"] ?? "all"
            scroll = Int(environment["WW_UI_SCROLL"] ?? "") ?? 4
            rotate = environment["WW_UI_ROTATE"] == "1"
            tree = environment["WW_UI_TREE"] == "1"
            today = environment["WW_UI_TODAY"].flatMap { $0.isEmpty ? nil : $0 }
            extra = Dictionary((environment["WW_UI_ENV"] ?? "").split(separator: ",").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }, uniquingKeysWith: { $1 })
        }

        /// A name or the start of one; `forecast$` is that screen alone.
        func wants(_ name: String) -> Bool {
            only.isEmpty || only.contains { $0.hasSuffix("$") ? name == $0.dropLast() : name.hasPrefix($0) }
        }

        /// The launch arguments that set the app's text size, leaving the simulator's own alone.
        var textArguments: [String] {
            let sizes = ["xs": "ExtraSmall", "small": "Small", "medium": "Medium", "xl": "ExtraLarge", "xxl": "ExtraExtraLarge",
                         "xxxl": "ExtraExtraExtraLarge", "ax-m": "AccessibilityM", "ax-l": "AccessibilityL", "ax-xl": "AccessibilityXL",
                         "ax-xxl": "AccessibilityXXL", "ax-xxxl": "AccessibilityXXXL"]
            guard let name = sizes[text] else { return [] }
            return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory\(name)"]
        }
    }

    struct Capture: Codable {
        let file: String
        /// "top", or "scroll-<region>-<n>".
        let part: String
        let measures: Measures
        var findings: [Finding]
    }

    struct ScreenResult: Codable {
        let name: String
        var seconds: Double = 0
        /// Where the time went: opening, the audit, scrolling.
        var timings: [String: Double] = [:]
        var captures: [Capture] = []
        /// Findings about the screen as a whole: a crash, a step that failed, the audit.
        var findings: [Finding] = []
        /// Checks the table says this screen trips for a reason.
        var expected: [String: String] = [:]
    }

    struct Report: Codable {
        let config: String
        let device: String
        let system: String
        let look: String
        let text: String
        let dates: String
        var screens: [ScreenResult] = []
    }

    private var options: Options!
    private var report: Report!
    /// `walk.json` for the walk, `use.json` for the flows.
    private var file = "walk.json"
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        guard let options = Options(environment) else {
            throw XCTSkip("Run through apps/ios/Scripts/ui-walk.sh (it sets WW_UI_OUT).")
        }
        self.options = options
        try FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
        report = Report(config: options.config, device: environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name,
                        system: UIDevice.current.systemVersion, look: options.look ?? "as set", text: options.text,
                        dates: options.dates ?? "as set")
    }

    // MARK: The walk

    func testWalk() throws {
        for screen in Screen.all where options.wants(screen.name) {
            let started = Date()
            var result = ScreenResult(name: screen.name, expected: screen.expected)
            visit(screen, into: &result)
            result.seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
            report.screens.append(result)
            try write()
        }
        app.terminate()
        // The checks checking themselves: every planted fault has to be found.
        if let test = report.screens.first(where: { $0.name == "self-test" }) {
            let found = Set(test.captures.flatMap(\.findings).map(\.check))
            let planted = ["leaked-code", "negative-zero", "unnamed-control", "all-capitals", "small-target", "off-edge",
                           "text-overlap", "mixed-minus", "mixed-dates"]
            let missed = planted.filter { !found.contains($0) }
            XCTAssert(missed.isEmpty, "The planted faults these checks should find went unnoticed: \(missed.joined(separator: ", "))")
        }
    }

    // MARK: Using the app

    private struct Stuck: Error { let why: String }

    /// Uses the app as a person would, in the demo: changes tabs, opens and
    /// closes a line (by Cancel, by a pull down, by Save) and a bill, adds a
    /// transaction, changes month, searches, goes into Settings and back,
    /// leaves and returns. A step that can't be done, or
    /// the app stopping, is a finding; so is anything the checks see on the
    /// way. Written to `use.json` beside `walk.json`.
    func testUse() throws {
        file = "use.json"
        func start() {
            launch(Screen("use", .demo, ["WW_DEBUG_PLACE": "dashboard"]))
            _ = app.wait(for: .runningForeground, timeout: 20)
            _ = settle()
        }
        func tap(_ label: String) throws {
            if let problem = perform(.tap(label)) { throw Stuck(why: problem) }
        }
        @discardableResult func expect(_ words: String) throws -> State {
            let state = settle(timeout: 6)
            guard app.state == .runningForeground else { throw Stuck(why: "The app stopped.") }
            guard state.seen.contains(where: { $0.text.localizedCaseInsensitiveContains(words) || $0.identifier == words }) else {
                throw Stuck(why: "Expected \"\(words)\" on screen, and it isn't.")
            }
            return state
        }
        func flow(_ name: String, _ steps: (inout ScreenResult) throws -> Void) {
            let began = Date()
            var result = ScreenResult(name: "use-\(name)")
            start()   // each flow from a fresh launch, so one can't leave the next a keyboard or a sheet
            do {
                try steps(&result)
            } catch let stuck as Stuck {
                let state = settle(timeout: 3)
                if app.state == .runningForeground {
                    result.captures.append(capture("use-\(name)", part: "stuck", state: state))
                    try? Checks.tree(state.seen).write(to: options.out.appendingPathComponent("use-\(name).stuck.tree.txt"), atomically: true, encoding: .utf8)
                }
                let crashed = app.state != .runningForeground
                result.findings.append(Finding(check: crashed ? "crashed" : "flow-stuck", level: "bug", label: name, frame: [],
                                               detail: stuck.why + (crashed ? " The run's crashes folder has the report, and report.md its top frames."
                                                                            : " Either the app is at fault or the flow in UITests/WalkTests.swift is out of date.")))
            } catch {
                result.findings.append(Finding(check: "flow-stuck", level: "bug", label: name, frame: [], detail: "\(error)"))
            }
            result.seconds = (Date().timeIntervalSince(began) * 10).rounded() / 10
            report.screens.append(result)
            try? write()
        }
        func picture(_ result: inout ScreenResult, _ name: String, _ part: String) {
            result.captures.append(capture("use-\(name)", part: part, state: settle(timeout: 4)))
        }

        flow("tabs") { _ in
            for (tab, shows) in [("Forecast", "All lines"), ("Bills & income", "Bills a month"), ("Settings", "More pages"),
                                 ("Search", "Search everything"), ("Dashboard", "Balance today")] {
                try tap(tab)
                try expect(shows)
            }
        }
        flow("open-line") { result in
            try tap("Forecast")
            try expect("All lines")
            try tap("Rent")
            try expect("Planned amount")
            picture(&result, "open-line", "editor")
            try tap("Cancel")
            try expect("All lines")
        }
        flow("add") { result in
            try tap("Forecast")
            try tap("Add")
            picture(&result, "add", "menu")
            let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' OR label BEGINSWITH 'New '")).firstMatch
            guard add.waitForExistence(timeout: 3) else { throw Stuck(why: "The Add menu offered nothing that starts with Add.") }
            add.tap()
            try expect("Amount")
            app.typeText("12.34")
            let name = app.textFields.element(boundBy: 1)
            guard name.exists else { throw Stuck(why: "Add transaction has no second field for the name.") }
            name.tap()
            app.typeText("Coffee")
            picture(&result, "add", "filled-in")
            try tap("Add")
            let after = settle(timeout: 5)
            result.captures.append(capture("use-add", part: "after-add", state: after))
            let stillOpen = after.seen.contains { $0.text == "Amount" }
            let saysWhy = after.seen.contains { $0.text.localizedCaseInsensitiveContains("demo") || $0.text.localizedCaseInsensitiveContains("save") }
            if stillOpen, !saysWhy {
                result.findings.append(Finding(check: "nothing-happened", level: "bug", label: "Add", frame: [],
                                               detail: "Add was tapped in the demo, the sheet is still open, and nothing on it says why."))
            }
            if stillOpen { try tap("Cancel") }
            try expect("All lines")
        }
        flow("month") { result in
            try tap("Forecast")
            try tap("Next month")
            try expect("December 2026")
            try tap("Previous month")
            try tap("Previous month")
            try expect("October 2026")
            try tap("October 2026")
            picture(&result, "month", "menu")
            if perform(.tap("This month")) != nil { throw Stuck(why: "The month's menu has no This month.") }
            try expect("November 2026")
        }
        flow("search") { result in
            try tap("Search")
            let field = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
            guard field.waitForExistence(timeout: 3) else { throw Stuck(why: "Search has no field to type in.") }
            field.tap()
            app.typeText("rent")
            try expect("Lines")
            picture(&result, "search", "typed")
        }
        flow("settings-and-back") { result in
            try tap("Settings")
            for page in ["Appearance", "Dates & display", "Privacy & lock"] {
                try tap(page)
                _ = settle(timeout: 4)
                let back = app.buttons["BackButton"].firstMatch
                guard back.waitForExistence(timeout: 3) else {
                    // Open on the Duo, the page is beside the list: nothing to go back from.
                    continue
                }
                back.tap()
                try expect(page)   // its row again, wherever the list was scrolled to
            }
            picture(&result, "settings-and-back", "back")
        }
        flow("open-bill") { result in
            try tap("Bills & income")
            try expect("Bills a month")
            try tap("Rent")
            try expect("Repeats")
            picture(&result, "open-bill", "editor")
            try tap("Cancel")
            // The list is still scrolled down to Rent, so its header is above the
            // screen; the bar's title is there whatever the scroll (#372).
            try expect("Bills & income")
        }
        flow("swipe-a-line-away") { _ in
            try tap("Forecast")
            try expect("All lines")
            try tap("Rent")
            try expect("Planned amount")
            // Pull the sheet down by its bar, as a thumb would.
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
            top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
            try expect("All lines")
        }
        flow("save-a-line") { result in
            try tap("Forecast")
            try tap("Rent")
            try expect("Planned amount")
            try tap("Paid")
            try tap("Save")
            let after = settle(timeout: 5)
            guard app.state == .runningForeground else { throw Stuck(why: "The app stopped.") }
            result.captures.append(capture("use-save-a-line", part: "after-save", state: after))
            let saysWhy = after.seen.contains { $0.text.localizedCaseInsensitiveContains("demo") }
            if !saysWhy, after.seen.contains(where: { $0.text == "Planned amount" }) {
                result.findings.append(Finding(check: "nothing-happened", level: "bug", label: "Save", frame: [],
                                               detail: "Save was tapped in the demo, the editor is still open, and nothing on it says why."))
            }
        }
        flow("leave-and-return") { result in
            try tap("Dashboard")
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 1.5)
            app.activate()
            try expect("Balance today")
            picture(&result, "leave-and-return", "returned")
        }
        app.terminate()
    }

    private func visit(_ screen: Screen, into result: inout ScreenResult) {
        let opened = Date()
        launch(screen)
        guard app.wait(for: .runningForeground, timeout: 20) else {
            result.findings.append(Finding(check: "did-not-open", level: "bug", label: screen.name, frame: [], detail: "The app didn't come to the front."))
            return
        }
        var state = settle()
        for step in screen.steps {
            if let problem = perform(step) {
                result.findings.append(Finding(check: "step-failed", level: "note", label: screen.name, frame: [], detail: problem))
            }
            state = settle()
        }
        guard app.state == .runningForeground else {
            result.findings.append(Finding(check: "crashed", level: "bug", label: screen.name, frame: [], detail: "The app stopped while opening this screen."))
            return
        }
        if let shows = screen.shows, !state.seen.contains(where: { $0.text.localizedCaseInsensitiveContains(shows) || $0.identifier == shows }) {
            result.findings.append(Finding(check: "not-what-it-says", level: "bug", label: screen.name, frame: [],
                                           detail: "\"\(shows)\" isn't on the screen: the launch settings no longer open it, or the page has changed. Check UITests/Screens.swift against apps/ios/README.md."))
        }
        if !state.settled {
            result.findings.append(Finding(check: "never-settles", level: "note", label: screen.name, frame: [], detail: "The screen was still changing after 10 seconds."))
        }
        for alert in app.alerts.allElementsBoundByIndex where alert.exists {
            result.findings.append(Finding(check: "alert-on-open", level: "note", label: alert.label, frame: Checks.box(alert.frame),
                                           detail: "An alert was showing when the screen opened: \(alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / "))"))
        }
        result.captures.append(capture(screen.name, part: "top", state: state))
        if options.tree {
            try? Checks.tree(state.seen).write(to: options.out.appendingPathComponent("\(screen.name).tree.txt"), atomically: true, encoding: .utf8)
        }
        var mark = Date()
        func lap(_ name: String) {
            result.timings[name] = (Date().timeIntervalSince(mark) * 10).rounded() / 10
            mark = Date()
        }
        result.timings["open"] = (Date().timeIntervalSince(opened) * 10).rounded() / 10

        if options.audit != "0" { result.findings += audit() }
        lap("audit")

        if screen.scrolls, options.scroll > 0 { scrollThrough(screen.name, from: state, into: &result) }
        lap("scroll")

        if options.rotate, ["dashboard", "forecast", "bills", "calendar", "settings", "line-editor"].contains(screen.name) {
            XCUIDevice.shared.orientation = .landscapeLeft
            let turned = settle()
            if app.state == .runningForeground {
                result.captures.append(capture(screen.name, part: "on-its-side", state: turned))
            } else {
                result.findings.append(Finding(check: "crashed", level: "bug", label: screen.name, frame: [], detail: "The app stopped when the phone was turned on its side."))
            }
            XCUIDevice.shared.orientation = .portrait
        }
    }

    private func launch(_ screen: Screen) {
        var environment: [String: String] = [:]
        switch screen.household {
        case .demo: environment["WW_DEBUG_DEMO"] = "1"
        case .sample: environment["WW_DEBUG_LOCAL"] = "sample"
        case .asGiven: break
        }
        let today = options.today.map { String($0.prefix(10)) }
            ?? ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        if let pinned = options.today { environment["WW_DEBUG_TODAY"] = pinned }
        for (name, value) in screen.settings { environment[name] = value == "today" ? today : value }
        if let look = options.look {
            environment["WW_DEBUG_LOOK"] = look
            // custom-light and custom-dark are the sample themes.
            if look.hasPrefix("custom-") { environment["WW_DEBUG_CUSTOM_THEMES"] = "sample" }
        }
        environment.merge(options.extra) { $1 }
        if let dates = options.dates { environment["WW_DEBUG_DATES"] = dates }
        app.launchEnvironment = environment
        app.launchArguments = options.textArguments
        app.launch()
    }

    // MARK: Looking at a screen

    struct State {
        var seen: [Seen] = []
        var window: CGRect = .zero
        var settled = false
    }

    private func look() -> State {
        guard let snapshot = try? app.snapshot() else { return State() }
        let window = Checks.window(of: snapshot)
        return State(seen: Checks.flatten(snapshot, window: window), window: window)
    }

    /// Waits until two looks in a row match and nothing is spinning, for up to `timeout` seconds.
    private func settle(timeout: TimeInterval = 10) -> State {
        let deadline = Date().addingTimeInterval(timeout)
        var last = look()
        var signature = Checks.signature(last.seen)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            var next = look()
            let nextSignature = Checks.signature(next.seen)
            let spinning = next.seen.contains { $0.type == .activityIndicator }
            if nextSignature == signature, !spinning, !next.seen.isEmpty {
                next.settled = true
                return next
            }
            last = next
            signature = nextSignature
        }
        return last
    }

    private func capture(_ name: String, part: String, state: State) -> Capture {
        let file = "\(name).\(part).jpg"
        let image = picture(of: state.window)
        // Wide enough to read, small enough to keep a whole run.
        let pixels = image.size.width * image.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale * min(1, 1100 / pixels)
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        try? small.jpegData(compressionQuality: 0.82)?.write(to: options.out.appendingPathComponent(file))
        return Capture(file: file, part: part, measures: Checks.measure(state.seen, window: state.window),
                       findings: Checks.run(state.seen, window: state.window))
    }

    /// A picture of the screen the app is on. Open, the Duo has two screens and the front one is
    /// black, which is the one `app.screenshot()` takes: so this takes every screen and keeps
    /// the one the size of the app's window.
    private func picture(of window: CGRect) -> UIImage {
        let shots = XCUIScreen.screens.map { $0.screenshot().image }
        func distance(_ image: UIImage) -> CGFloat { abs(image.size.width - window.width) + abs(image.size.height - window.height) }
        return shots.min { distance($0) < distance($1) } ?? app.screenshot().image
    }

    /// Apple's own audit of what's on screen. Each issue becomes a finding; none fails the test.
    private func audit() -> [Finding] {
        var findings: [Finding] = []
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element-detection"), (.hitRegion, "hit-region"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamic-type"), (.textClipped, "text-clipped"), (.trait, "trait"),
        ]
        let kinds: XCUIAccessibilityAuditType = switch options.audit {
        case "contrast": [.contrast]
        case "text": [.dynamicType, .textClipped]
        default: .all
        }
        do {
            try app.performAccessibilityAudit(for: kinds) { issue in
                let name = names.first { issue.auditType == $0.0 }?.1 ?? "other"
                var label = ""
                var frame: [Double] = []
                if let element = issue.element, element.exists {
                    label = element.label.isEmpty ? element.identifier : element.label
                    frame = Checks.box(element.frame)
                }
                findings.append(Finding(check: "audit-\(name)", level: "note", label: String(label.prefix(120)), frame: frame,
                                        detail: issue.compactDescription + (issue.detailedDescription.isEmpty ? "" : " — " + issue.detailedDescription)))
                return true   // noted, not failed
            }
        } catch {
            findings.append(Finding(check: "audit-failed", level: "note", label: "", frame: [], detail: "\(error)"))
        }
        return findings
    }

    /// Scrolls each large scrolling area to its end, a screenful at a time, with a picture and the checks at each stop.
    private func scrollThrough(_ name: String, from start: State, into result: inout ScreenResult) {
        let window = start.window
        var regions: [CGRect] = []
        for element in start.seen where [.scrollView, .table, .collectionView].contains(element.type) {
            let frame = element.frame.intersection(window)
            guard frame.height >= window.height * 0.45, frame.width >= window.width * 0.25 else { continue }
            // One area per place: a list and the scroll view around it are the same thing.
            if regions.contains(where: { $0.intersection(frame).width > min($0.width, frame.width) * 0.6 }) { continue }
            regions.append(frame)
        }
        // A bar along the bottom, or a keyboard, is where a drag has to start above. (Open, the Duo's bar is along the top: not in the way.)
        let barTop = start.seen.filter { (($0.type == .tabBar && $0.frame.width > $0.frame.height) || $0.type == .keyboard) && $0.frame.midY > window.midY }
            .map(\.frame.minY).min() ?? window.maxY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for (index, region) in regions.sorted(by: { $0.minX < $1.minX }).enumerated() {
            var before = Checks.signature(start.seen.filter { $0.frame.intersects(region) })
            for stop in 1...max(1, options.scroll) {
                let top = region.minY + region.height * 0.15
                let bottom = min(region.minY + region.height * 0.85, barTop - 30)
                guard bottom - top > 80 else { break }
                let from = origin.withOffset(CGVector(dx: region.midX, dy: bottom))
                let to = origin.withOffset(CGVector(dx: region.midX, dy: top))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.3)
                let state = settle(timeout: 5)
                guard app.state == .runningForeground else {
                    result.findings.append(Finding(check: "crashed", level: "bug", label: name, frame: [], detail: "The app stopped while scrolling."))
                    return
                }
                let after = Checks.signature(state.seen.filter { $0.frame.intersects(region) })
                if after == before { break }
                before = after
                result.captures.append(capture(name, part: "scroll-\(index + 1)-\(stop)", state: state))
            }
        }
    }

    // MARK: Steps

    /// The first element with this label that's on screen. Two things XCTest
    /// gets wrong about iOS 26's bars: the tab bar's Search has a hidden twin
    /// with no frame, which a first match lands on; and a bar button with a
    /// symbol over it isn't "hittable" though a finger would hit it. So this
    /// looks at every match, takes the first whose middle is in the window,
    /// and the tap goes to that middle.
    private func find(_ label: String) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        func onScreen(_ element: XCUIElement) -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            return !frame.isEmpty && !frame.isInfinite && window.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let queries = [app.buttons, app.links, app.switches, app.cells, app.staticTexts, app.otherElements]
        for query in queries {
            let matches = query.matching(identifier: label)
            for index in 0..<min(matches.count, 4) {
                let element = matches.element(boundBy: index)
                if onScreen(element) { return element }
            }
        }
        let starts = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label))
        for index in 0..<min(starts.count, 4) {
            let element = starts.element(boundBy: index)
            if onScreen(element) { return element }
        }
        return nil
    }

    /// Does the step; says what went wrong, or nil.
    private func perform(_ step: Screen.Step) -> String? {
        switch step {
        case let .tap(label), let .tapIfThere(label):
            for attempt in 0..<6 {
                // Give a page that's still arriving a moment before scrolling it away.
                let deadline = Date().addingTimeInterval(attempt == 0 ? 2.5 : 0.5)
                repeat {
                    if let element = find(label) {
                        if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                        return nil
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                } while Date() < deadline
                app.swipeUp(velocity: .slow)
            }
            if case .tapIfThere = step { return nil }
            return "Nothing to tap called \"\(label)\"."
        case let .type(text):
            app.typeText(text)
            return nil
        case let .wait(seconds):
            Thread.sleep(forTimeInterval: seconds)
            return nil
        }
    }

    private func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: options.out.appendingPathComponent(file))
    }
}
