import XCTest

/// One thing a check noticed on a screen.
struct Finding: Codable {
    /// The check's id, stable: the report folds findings by it, and
    /// `learnings.md` refers to it.
    let check: String
    /// "bug" (plainly broken), "slip" (against a convention) or "note" (for a person to judge).
    let level: String
    let label: String
    /// x, y, width, height in points.
    let frame: [Double]
    let detail: String
}

/// An element as the checks see it, flattened out of a snapshot.
struct Seen {
    let type: XCUIElement.ElementType
    let label: String
    let value: String
    var placeholder = ""
    let identifier: String
    let frame: CGRect
    let enabled: Bool
    /// The chain of element types above it.
    let path: [XCUIElement.ElementType]
    let depth: Int
    /// Its place in the flattened list, and the places of the elements above it.
    var index = 0
    var above: [Int] = []
    /// What the scrolling areas above it leave showing, and the nearest one's own frame.
    var showing: CGRect = .null
    var scroller: CGRect?

    var text: String { label.isEmpty ? value : label }
    var isControl: Bool {
        [.button, .link, .switch, .toggle, .textField, .secureTextField, .slider, .stepper, .segmentedControl, .picker, .menuButton, .popUpButton]
            .contains(type)
    }
}

/// What one picture of a screen measured, for comparing screens with each other.
struct Measures: Codable {
    var window: [Double] = []
    /// The left edge most text starts at.
    var leftMargin: Double = 0
    var navigationBarHeight: Double = 0
    var title: String = ""
    /// "bottom", "side" or "none".
    var tabBar: String = "none"
    var elements: Int = 0
    /// How amounts are written here: "cents", "whole", "minus-before-symbol", "minus-after-symbol", "true-minus", "hyphen-minus", "brackets".
    var amountStyles: [String] = []
    /// "short" (Nov 12), "iso", "numeric" (11/12), "long" (November 12), "weekday".
    var dateStyles: [String] = []
    /// Every string on screen, for reading and for comparing words.
    var strings: [String] = []
}

enum Checks {
    /// The whole tree, flattened, with only what's at least partly on screen.
    static func flatten(_ snapshot: XCUIElementSnapshot, window: CGRect) -> [Seen] {
        var seen: [Seen] = []
        func walk(_ element: XCUIElementSnapshot, path: [XCUIElement.ElementType], above: [Int], clip: CGRect, scroller: CGRect?) {
            let frame = element.frame
            var next = above
            // Something scrolled out of its area is in the tree, but not on screen.
            if frame.width > 0, frame.height > 0, frame.intersects(clip) {
                seen.append(Seen(type: element.elementType, label: element.label, value: (element.value as? String) ?? "",
                                 placeholder: element.placeholderValue ?? "",
                                 identifier: element.identifier, frame: frame, enabled: element.isEnabled, path: path, depth: path.count,
                                 index: seen.count, above: above, showing: frame.intersection(clip), scroller: scroller))
                next.append(seen.count - 1)
            }
            let scrolls = [.scrollView, .collectionView, .table].contains(element.elementType)
            for child in element.children {
                walk(child, path: path + [element.elementType], above: next, clip: scrolls ? clip.intersection(frame) : clip,
                     scroller: scrolls ? frame : scroller)
            }
        }
        walk(snapshot, path: [], above: [], clip: window, scroller: nil)
        return seen
    }

    /// The tree as text, one element a line, for working out why a check said what it said (`WW_UI_TREE=1`).
    static func tree(_ seen: [Seen]) -> String {
        seen.map { element in
            let frame = box(element.frame).map { String(Int($0)) }.joined(separator: ",")
            return String(repeating: "  ", count: element.above.count) + "\(name(element.type)) [\(frame)] \"\(element.label)\""
                + (element.value.isEmpty ? "" : " = \"\(element.value)\"") + (element.identifier.isEmpty ? "" : " #\(element.identifier)")
        }.joined(separator: "\n")
    }

    static func name(_ type: XCUIElement.ElementType) -> String {
        let names: [XCUIElement.ElementType: String] = [
            .application: "application", .window: "window", .other: "other", .button: "button", .staticText: "text", .image: "image",
            .cell: "cell", .scrollView: "scrollView", .collectionView: "collection", .table: "table", .navigationBar: "navigationBar",
            .tabBar: "tabBar", .toolbar: "toolbar", .switch: "switch", .toggle: "toggle", .textField: "textField",
            .secureTextField: "secureField", .segmentedControl: "segmented", .picker: "picker", .slider: "slider", .link: "link",
            .alert: "alert", .sheet: "sheet", .keyboard: "keyboard", .key: "key", .activityIndicator: "spinner",
            .progressIndicator: "progress", .scrollBar: "scrollBar", .menu: "menu", .menuItem: "menuItem", .popover: "popover",
            .searchField: "searchField", .datePicker: "datePicker", .stepper: "stepper", .group: "group", .statusBar: "statusBar",
            .tab: "tab", .tabGroup: "tabGroup", .touchBar: "touchBar", .textView: "textView", .pageIndicator: "pageIndicator",
            .disclosureTriangle: "disclosure", .icon: "icon",
        ]
        return names[type] ?? "type\(type.rawValue)"
    }

    /// The app's own window: the largest one.
    static func window(of snapshot: XCUIElementSnapshot) -> CGRect {
        var best = snapshot.frame
        var area: CGFloat = 0
        func walk(_ element: XCUIElementSnapshot) {
            if element.elementType == .window, element.frame.width * element.frame.height > area {
                best = element.frame
                area = element.frame.width * element.frame.height
            }
            for child in element.children { walk(child) }
        }
        walk(snapshot)
        return best
    }

    /// Two frames in the same place, give or take a point.
    static func near(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 1.5 && abs(first.minY - second.minY) < 1.5 && abs(first.width - second.width) < 1.5 && abs(first.height - second.height) < 1.5
    }

    static func box(_ frame: CGRect) -> [Double] {
        [frame.minX, frame.minY, frame.width, frame.height].map { (Double($0) * 10).rounded() / 10 }
    }

    static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    // MARK: The checks

    static func run(_ seen: [Seen], window: CGRect) -> [Finding] {
        var findings: [Finding] = []
        func add(_ check: String, _ level: String, _ element: Seen, _ detail: String) {
            findings.append(Finding(check: check, level: level, label: String(element.text.prefix(120)), frame: box(element.frame), detail: detail))
        }
        let texts = seen.filter { $0.type == .staticText && !$0.label.isEmpty }
        let inBars = { (element: Seen) in element.path.contains(.tabBar) || element.path.contains(.keyboard) || element.path.contains(.statusBar) }
        // The system keyboard, and its row of typing predictions above the keys (three controls that aren't in the
        // keyboard's own branch of the tree and have no names: the system's to name, not the app's) (#392).
        let keyboardFrames = seen.filter { $0.type == .keyboard || $0.label == "Typing Predictions" }.map(\.frame)
        let onKeyboard = { (element: Seen) in keyboardFrames.contains { $0.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) } }

        for element in seen where !inBars(element) {
            let text = element.text

            // A label that leaks code, or says nothing a person could read.
            if !matches(#"Optional\(|\bnil\b|\bNaN\b|\(null\)|%@|%\d*\.?\d*[dfs]\b|\\\(|<[A-Za-z_]+: 0x|WW_DEBUG|\bundefined\b|\bInfinity\b"#, text).isEmpty {
                add("leaked-code", "bug", element, "The label shows code or an empty value.")
            }
            if !matches(#"[-−]\$?0(\.00)?(?![\d.,])"#, text).isEmpty {
                add("negative-zero", "bug", element, "An amount written as minus zero.")
            }
            if element.isControl || element.type == .image, !matches(#"^[a-z0-9]+(\.[a-z0-9]+)+$"#, element.label).isEmpty {
                add("symbol-name-label", element.isControl ? "bug" : "slip", element,
                    "VoiceOver reads the symbol's file name. Give it a label, or hide it if it's decoration.")
            }
            // (The system's own Back button has no label in the tree; VoiceOver has its own word for it.)
            if element.isControl, element.label.isEmpty, element.value.isEmpty, element.placeholder.isEmpty, element.frame.width > 1,
               element.identifier != "BackButton", !onKeyboard(element),
               !seen.contains(where: { other in
                   !other.text.isEmpty && (other.above.contains(element.index) || (other.index != element.index && near(other.frame, element.frame)))
               }) {
                add("unnamed-control", "bug", element, "A control with no name for VoiceOver.")
            }

            // Capitals: the app writes sentence case (#310).
            let letters = text.filter(\.isLetter)
            if element.type == .staticText || element.isControl, letters.count >= 6, text.contains(" "), letters == letters.uppercased(),
               text.count < 60 {
                add("all-capitals", "slip", element, "A label in capitals; the app writes sentence case.")
            }

            // Tap targets: 44 points each way (Apple's guidance).
            if element.isControl, element.enabled, window.contains(element.frame), !element.path.contains(.navigationBar),
               !element.path.contains(.toolbar), !element.path.contains(.segmentedControl), !element.path.contains(.datePicker),
               ![.switch, .toggle, .segmentedControl, .stepper, .slider, .textField, .secureTextField, .searchField].contains(element.type),
               !element.label.hasPrefix("Reorder "), element.identifier != "BackButton",
               // A control that only wraps a named one of the same size is that one, seen twice.
               !(element.label.isEmpty && seen.contains { $0.index != element.index && near($0.frame, element.frame) && $0.isControl }) {
                let least = min(element.frame.width, element.frame.height)
                if least < 43.5 {
                    add("small-target", least < 28 && element.type != .link ? "slip" : "note", element,
                        "\(Int(element.frame.width.rounded())) × \(Int(element.frame.height.rounded())) points; 44 each way is the least to hit reliably.")
                }
            }

            // Hanging off the side of the window.
            // (A strip that scrolls sideways is meant to run on: its area is short, or stops short of the window's edge.)
            let strip = element.scroller.map { $0.height < 120 || $0.maxX < window.maxX - 1 || $0.minX > window.minX + 1 } ?? false
            if (element.type == .staticText || element.isControl), !text.isEmpty, !strip,
               element.frame.minX < window.minX - 1 || element.frame.maxX > window.maxX + 1,
               element.frame.minY >= window.minY, element.frame.maxY <= window.maxY {
                add("off-edge", "bug", element, "Runs past the side of the window (x \(Int(element.frame.minX)) to \(Int(element.frame.maxX)), window \(Int(window.minX)) to \(Int(window.maxX))).")
            }
        }

        // Text over text: two labels that share more than a fifth of the smaller one.
        // (A title in the bar has the page scrolling under it; that's the bar, not a fault.)
        let placed = texts.filter { !inBars($0) && !$0.path.contains(.navigationBar) && $0.frame.height < 200 }
        for (index, first) in placed.enumerated() {
            for second in placed[(index + 1)...] where first.label != second.label {
                if first.above.contains(second.index) || second.above.contains(first.index) { continue }
                if first.label.contains(second.label) || second.label.contains(first.label) { continue }
                // A row read out as one is a text the size of the row, with its parts inside it.
                let areas = [first.frame.width * first.frame.height, second.frame.width * second.frame.height]
                if areas.max()! > areas.min()! * 3, first.frame.insetBy(dx: -2, dy: -2).contains(second.frame) || second.frame.insetBy(dx: -2, dy: -2).contains(first.frame) { continue }
                let shared = first.frame.intersection(second.frame)
                guard !shared.isNull, shared.width > 2, shared.height > 2 else { continue }
                let smaller = min(first.frame.width * first.frame.height, second.frame.width * second.frame.height)
                if shared.width * shared.height > smaller * 0.2 {
                    add("text-overlap", "bug", first, "Sits over \"\(second.label.prefix(60))\".")
                }
            }
        }

        // A spinner that's still going once the screen has settled.
        for element in seen where element.type == .activityIndicator || (element.type == .progressIndicator && element.value.isEmpty) {
            add("stuck-spinner", "bug", element, "Still spinning after the screen settled.")
        }

        // All but empty.
        let readable = seen.filter { !inBars($0) && !$0.text.isEmpty && ($0.type == .staticText || $0.isControl) }
        if readable.count < 2, let root = seen.first {
            add("empty-screen", "bug", root, "Nothing to read on this screen: \(readable.count) labelled element(s).")
        }

        // Amounts and dates written two ways side by side.
        let styles = amountStyles(texts.map(\.label))
        if styles.contains("minus-before-symbol"), styles.contains("minus-after-symbol"), let root = seen.first {
            add("mixed-minus", "slip", root, "Negative amounts written both as -$5 and $-5 on one screen.")
        }
        if styles.contains("true-minus"), styles.contains("hyphen-minus"), let root = seen.first {
            add("mixed-minus-sign", "note", root, "Negative amounts use both − and - on one screen.")
        }
        let dates = dateStyles(texts.map(\.label))
        if dates.contains("iso"), dates.contains("short") || dates.contains("numeric"), let root = seen.first {
            add("mixed-dates", "slip", root, "Dates written both as 2026-11-12 and another way on one screen.")
        }
        return findings
    }

    static func amountStyles(_ strings: [String]) -> Set<String> {
        var styles: Set<String> = []
        for text in strings {
            for amount in matches(#"\(?[-−+]?\$[-−]?[\d,]+(?:\.\d+)?\)?"#, text) {
                styles.insert(amount.contains(".") ? "cents" : "whole")
                if amount.hasPrefix("(") { styles.insert("brackets") }
                if !matches(#"^[-−]\$"#, amount).isEmpty { styles.insert("minus-before-symbol") }
                if !matches(#"\$[-−]"#, amount).isEmpty { styles.insert("minus-after-symbol") }
                if amount.contains("−") { styles.insert("true-minus") }
                if amount.contains("-") { styles.insert("hyphen-minus") }
            }
        }
        return styles
    }

    static func dateStyles(_ strings: [String]) -> Set<String> {
        var styles: Set<String> = []
        let months = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
        let longMonths = "January|February|March|April|June|July|August|September|October|November|December"
        for text in strings {
            if !matches(#"\b\d{4}-\d{2}-\d{2}\b"#, text).isEmpty { styles.insert("iso") }
            if !matches(#"\b(?:"# + months + #")\.? \d{1,2}\b"#, text).isEmpty { styles.insert("short") }
            if !matches(#"\b\d{1,2} (?:"# + months + #")\b"#, text).isEmpty { styles.insert("day-first") }
            if !matches(#"\b(?:"# + longMonths + #") \d{1,2}\b"#, text).isEmpty { styles.insert("long") }
            if !matches(#"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#, text).isEmpty { styles.insert("numeric") }
            if !matches(#"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*,? "#, text).isEmpty { styles.insert("weekday") }
        }
        return styles
    }

    // MARK: What a screen measures

    static func measure(_ seen: [Seen], window: CGRect) -> Measures {
        var measures = Measures()
        measures.window = box(window)
        measures.elements = seen.count
        let content = seen.filter { $0.type == .staticText && !$0.label.isEmpty && !$0.path.contains(.tabBar) && !$0.path.contains(.navigationBar) }
        var edges: [Int: Int] = [:]
        for text in content { edges[Int((text.frame.minX - window.minX).rounded()), default: 0] += 1 }
        measures.leftMargin = Double(edges.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? 0)
        if let bar = seen.first(where: { $0.type == .navigationBar }) {
            measures.navigationBarHeight = Double(bar.frame.height)
            measures.title = bar.identifier.isEmpty ? bar.label : bar.identifier
        }
        // iOS 26's bar isn't always a tab bar to the tree: Settings and Search are always in it.
        if let bar = seen.first(where: { $0.type == .tabBar }) {
            measures.tabBar = bar.frame.width > bar.frame.height ? "bottom" : "side"
        } else if let settings = seen.first(where: { $0.type == .button && $0.label == "Settings" }),
                  let search = seen.first(where: { $0.type == .button && $0.label == "Search" }) {
            measures.tabBar = abs(settings.frame.midX - search.frame.midX) < abs(settings.frame.midY - search.frame.midY) ? "side" : "bottom"
        }
        let strings = seen.filter { !$0.text.isEmpty && ($0.type == .staticText || $0.isControl || $0.type == .cell || $0.type == .other) }.map(\.text)
        var once: [String] = []
        for string in strings where !once.contains(string) { once.append(string) }
        measures.strings = once
        measures.amountStyles = amountStyles(once).sorted()
        measures.dateStyles = dateStyles(once).sorted()
        return measures
    }

    /// What's on screen, as one string: two the same mean nothing moved.
    static func signature(_ seen: [Seen]) -> String {
        seen.filter { $0.type == .staticText || $0.isControl }.map { "\($0.text)@\(Int($0.frame.minX)),\(Int($0.frame.minY))" }.joined(separator: "|")
    }
}
