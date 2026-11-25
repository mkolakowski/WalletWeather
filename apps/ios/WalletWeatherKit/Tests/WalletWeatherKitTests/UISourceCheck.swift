import Foundation

/// The source check (Plans/ios-ui-review.md, phase 1, #344): rules matched
/// against the app's own Swift, for slips a screen would only show in one
/// look, at one text size or to VoiceOver. `UISourceTests` runs it; the
/// baseline beside the tests (`Tests/UISourceBaseline.txt`) lists the slips
/// that were there when a rule arrived, and only shrinks.
///
/// A line that's right as written says so where it stands:
/// `// ui-check: allow <rule> — why`, on the line or the one above it.
enum UISource {
    /// One rule. `patterns` are ICU regular expressions tried on each line
    /// of code (comments and Debug-only code left out); `bad` and `good` are
    /// lines the rule must and mustn't catch, which `UISourceTests` checks.
    struct Rule: Sendable, CustomStringConvertible {
        let id: String
        /// What's wrong with it, and where that was decided.
        let why: String
        let fix: String
        var patterns: [String] = []
        /// Files the rule leaves alone, each with the reason.
        var skipFiles: [String: String] = [:]
        /// A hit is dropped when this matches the same line…
        var unlessLine: String?
        /// …or within this many lines either side…
        var unlessNear: (pattern: String, lines: Int)?
        /// …or anywhere in the file.
        var unlessFile: String?
        /// A last say on a hit, given the matched text.
        var accept: (@Sendable (_ match: String) -> Bool)?
        /// A rule that needs more than a line at a time: the indexes of the
        /// lines at fault, given the file's code lines.
        var wholeFile: (@Sendable (_ lines: [String]) -> [Int])?
        var bad: [String] = []
        var good: [String] = []

        var description: String { id }
    }

    struct Slip: Hashable, Sendable {
        let rule: String
        /// Relative to `apps/ios`.
        let file: String
        let line: Int
        /// The line, trimmed: what the baseline keeps, so a slip stays
        /// recognised when lines above it come and go.
        let text: String

        var key: String { "\(rule)\t\(file)\t\(text)" }
    }

    // MARK: The rules

    /// Words a label may capitalise after its first: names of the app's own
    /// pages, of Apple's and other companies' things, and of days and months.
    static let names: Set<String> = [
        "WalletWeather", "Dashboard", "Forecast", "Calendar", "Reports", "Budgets", "Settings", "Search", "Tags",
        "Connections", "Appearance", "Shortcuts", "Siri", "Spotlight", "Face", "Touch", "Optic", "ID", "Files", "Mail",
        "Safari", "Camera", "Home", "Lock", "Screen", "App", "Store", "Apple", "Google", "Gmail", "Cloudflare", "Access",
        "SimpleFIN", "Teller", "Plaid", "Keychain", "Duo", "Drive", "Notifications", "Wallet", "Light", "Dark", "Sepia",
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    static let rules: [Rule] = [
        Rule(
            id: "fixed-font-size",
            why: "A size in points ignores the phone's text size (decided 2026-11-23, #311).",
            fix: "Use a text style (.font(.title)), or a @ScaledMetric for the size.",
            patterns: [#"\.font\(\.system\(size:\s*[0-9]"#],
            unlessLine: #"relativeTo:"#,
            bad: [#"Image(systemName: "lock.fill").font(.system(size: 44))"#],
            good: [#"Text(net).font(.system(size: scaled ? netSize : 10))"#, #"Text("x").font(.title2.weight(.semibold))"#]),
        Rule(
            id: "colour-outside-theme",
            why: "A colour that isn't the theme's stays the same in every look, so it can vanish in one of them (the looks, #91; custom themes, #297).",
            fix: "Use Palette (Palette.accent, .bad, .text, …) or a system style (.primary, .secondary).",
            patterns: [
                #"\bColor\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|black)\b"#,
                #"\.(foregroundStyle|tint|background|fill|stroke|border)\(\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|black)\b"#,
                #"\bColor\(\s*(red|hue|white):"#, #"\bColor\(\.sRGB"#, #"#colorLiteral"#, #"\bUIColor\(hex:"#,
            ],
            skipFiles: [
                "Theme.swift": "where the theme's colours are made",
                "AppearanceViews.swift": "draws each look's own colours as swatches, and the theme editor's wells",
            ],
            bad: [#".foregroundStyle(.white)"#, #"Rectangle().fill(Color.red.opacity(0.2))"#, #"Color(red: 0.2, green: 0.3, blue: 0.4)"#],
            good: [#".foregroundStyle(Palette.bad)"#, #".foregroundStyle(.secondary)"#, #"Color.clear.frame(height: 10)"#]),
        Rule(
            id: "replaced-api",
            why: "Apple has replaced it; the old one is how an app starts to look and behave dated.",
            fix: "foregroundStyle, clipShape(.rect(cornerRadius:)), NavigationStack, toolbar, tint, navigationTitle, ignoresSafeArea, confirmationDialog, @Observable, #Preview, animation(_:value:).",
            patterns: [
                #"\.foregroundColor\("#, #"\.cornerRadius\("#, #"\bNavigationView\b"#, #"\.navigationBarItems\("#,
                #"\.accentColor\("#, #"\.navigationBarTitle\("#, #"\.edgesIgnoringSafeArea\("#, #"\.actionSheet\("#,
                #"\bUIScreen\.main\b"#, #"\bPreviewProvider\b"#, #"\bObservableObject\b"#,
                #"@(Published|StateObject|ObservedObject|EnvironmentObject)\b"#,
                // A view's .animation with no value: (a binding's `$on.animation(.snappy)` is fine).
                #"(?<![\w)])\.animation\(\.\w+(\([^()]*\))?\)"#,
            ],
            bad: [#"Text("Hi").foregroundColor(.red)"#, #"    .cornerRadius(8)"#, #"    .animation(.default)"#, #"NavigationView {"#],
            good: [#"    .animation(.default, value: model.phase)"#, #"Toggle("Paid", isOn: $open.draft.paid.animation(.snappy))"#,
                   #"NavigationStack {"#]),
        Rule(
            id: "label-case",
            why: "Labels are sentence case, as the web app's are (decided 2026-11-23, #310).",
            fix: "Write \"Add transaction\", not \"Add Transaction\" or \"ADD TRANSACTION\". A name that keeps its capitals goes in UISource.names.",
            patterns: [#"\.textCase\(\.uppercase\)"#, #"\.uppercased\(\)"#, #""[A-Z][a-z]+(?: (?:&|[A-Z][A-Za-z]+))+[.:…?!]?""#],
            accept: { match in
                guard match.hasPrefix("\"") else { return true }
                let words = match.trimmingCharacters(in: CharacterSet(charactersIn: "\".:…?!")).split(separator: " ").dropFirst()
                return words.contains { $0 != "&" && !names.contains(String($0)) }
            },
            bad: [#"SecureField("Client Secret", text: $clientSecret)"#, #"Text(title).textCase(.uppercase)"#, #"Button("Add Transaction") {}"#],
            good: [#"Button("Open Settings") {}"#, #"Text("Bills & income")"#, #"Button("Add transaction") {}"#, #"Text("Try Search")"#]),
        Rule(
            id: "three-dots",
            why: "The app writes one character, … , as iOS does; three full stops read differently to VoiceOver and space differently.",
            fix: "Type … (Option-;).",
            patterns: [#""[^"]*[A-Za-z]\.\.\.[^"]*""#],
            bad: [#"Text("Working...")"#],
            good: [#"Text("Working…")"#, #"for index in 0...3 { print("x") }"#]),
        Rule(
            id: "icon-only-button",
            why: "A button that's only a symbol is read to VoiceOver by the symbol's file name.",
            fix: "Use Label(\"Name\", systemImage:) with .labelStyle(.iconOnly), or add .accessibilityLabel(\"Name\").",
            wholeFile: { iconOnlyLabels(in: $0) },
            bad: ["Button { add() } label: { Image(systemName: \"plus\") }"],
            good: ["Button { add() } label: { Image(systemName: \"plus\") }.accessibilityLabel(\"Add\")",
                   "Button { add() } label: { Label(\"Add\", systemImage: \"plus\") }"]),
        Rule(
            id: "alert",
            why: "A failed save shows in ProblemBanner, with its way forward (decided 2026-11-23, #311). An alert is for a question that needs an answer, or a problem with nowhere else to show.",
            fix: "Report a failed save with .problemBanner. For a question, or a problem outside any editor, mark the line: // ui-check: allow alert — why.",
            patterns: [#"\.alert\("#],
            bad: [#"    .alert("Couldn't save", isPresented: $failed) {"#],
            good: [#"    .confirmationDialog("Delete this line?", isPresented: $asking) {"#]),
        Rule(
            id: "motion",
            why: "Something that slides, grows or springs has to settle for a fade when Reduce Motion is on (decided 2026-11-23 for the fold, #304).",
            fix: "Read @Environment(\\.accessibilityReduceMotion) in the file and fade instead when it's on.",
            patterns: [#"\.transition\(\.(move|slide|scale|push|offset)"#, #"\bmatchedGeometryEffect\b"#, #"\.(bouncy|spring|interpolatingSpring)\b"#,
                       #"\b(phaseAnimator|keyframeAnimator)\b"#],
            unlessFile: #"accessibilityReduceMotion"#,
            bad: [#"    .transition(.move(edge: .bottom).combined(with: .opacity))"#, #"withAnimation(.bouncy) { open = true }"#],
            good: [#"    .transition(.opacity)"#, #"withAnimation(.snappy) { open = true }"#]),
        Rule(
            id: "tap-without-button",
            why: "A tap gesture on a plain view isn't a button to VoiceOver, Switch Control or a keyboard.",
            fix: "Make it a Button, or add .accessibilityAddTraits(.isButton) and a label.",
            patterns: [#"\.onTapGesture\b"#],
            unlessNear: (#"accessibilityAddTraits\(\.isButton\)|accessibilityAction\b"#, 4),
            bad: [#"Circle().onTapGesture { pick() }"#],
            good: [#"Button("Pick") { pick() }"#]),
        Rule(
            id: "date-outside-style",
            why: "A calendar day is written the way Settings → Dates & display says (decided 2026-11-23, #296).",
            fix: "Format it through the app's date style. A weekday-and-month heading that isn't one of the two styles gets a mark saying so.",
            patterns: [#"\.formatted\(date:\s*\.(?!omitted)"#, #"\.dateTime\b(?!\.(hour|minute))"#, #"\bDateFormatter\(\)"#,
                       #"style:\s*\.(date|relative|offset)\b"#, #"\bRelativeDateTimeFormatter\b"#],
            bad: [#"Text(day.date.formatted(date: .complete, time: .omitted))"#, #"Text(date.formatted(.dateTime.month().day()))"#],
            good: [#"Text(date.formatted(date: .omitted, time: .shortened))"#, #"Text(made, format: .dateTime.hour().minute())"#]),
        Rule(
            id: "money-outside-format",
            why: "An amount is written by the Kit's Money, so every page writes it the same way.",
            fix: "Use Money's own text (.text, .short, …).",
            patterns: [#"\.currency\(code:"#, #"\bNumberFormatter\(\)"#, #"\.formatted\(\.number\b"#],
            bad: [#"Text(amount.formatted(.currency(code: "USD")))"#],
            good: [#"Text(balance.text)"#]),
        Rule(
            id: "fixed-frame",
            why: "A fixed width or height of 20 points or more doesn't grow with the phone's text size, so what's in it gets cut (decided 2026-11-23, #311).",
            fix: "Use minWidth or minHeight, or a @ScaledMetric for the number.",
            patterns: [#"\.frame\((?:width|height):\s*(?:[2-9][0-9]|[1-9][0-9]{2,})\b"#, #"\.frame\(width:[^,)]*,\s*height:\s*(?:[2-9][0-9]|[1-9][0-9]{2,})\b"#],
            bad: [#"    .frame(width: 46, height: 34)"#, #"    .frame(height: 170)"#],
            good: [#"    .frame(minHeight: 44)"#, #"Circle().frame(width: 8, height: 8)"#, #"    .frame(width: dayWidth)"#]),
    ]

    /// `label: { … }` closures that hold a symbol and no words, with no
    /// accessibility label on the symbol or just after the closure.
    static func iconOnlyLabels(in lines: [String]) -> [Int] {
        let text = lines.joined(separator: "\n")
        let chars = Array(text)
        var starts: [Int] = []   // line index of each character
        var line = 0
        for char in chars {
            starts.append(line)
            if char == "\n" { line += 1 }
        }
        var found: [Int] = []
        for match in matches(#"label:\s*\{"#, in: text) {
            let open = text.distance(from: text.startIndex, to: match.upperBound) - 1
            var depth = 0
            var close = open
            for index in open..<chars.count {
                if chars[index] == "{" { depth += 1 }
                if chars[index] == "}" { depth -= 1 }
                if depth == 0 { close = index; break }
            }
            guard close > open else { continue }
            let body = String(chars[(open + 1)..<close])
            let after = String(chars[min(close + 1, chars.count)..<min(close + 240, chars.count)])
            // What follows the closure, as far as its own modifiers run.
            var trailer = ""
            for (number, piece) in after.components(separatedBy: "\n").enumerated() {
                guard number == 0 || piece.trimmingCharacters(in: .whitespaces).hasPrefix(".") else { break }
                trailer += piece
            }
            guard body.contains("Image(systemName:"), !body.contains("Text("), !body.contains("Label("),
                  !body.contains("accessibilityLabel"), !trailer.contains("accessibilityLabel") else { continue }
            found.append(starts[open])
        }
        return found
    }

    // MARK: Reading the app

    /// `apps/ios`, from this file's place in the checkout.
    static let iosFolder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let baselineFile = iosFolder.appending(path: "WalletWeatherKit/Tests/UISourceBaseline.txt")

    /// The folders with screens in them.
    static let folders = ["WalletWeather", "Widgets", "Notifications"]

    /// Whole files left out: Debug-only screens nobody is shipped.
    static let skippedFiles: Set<String> = ["DebugBridge.swift", "WidgetGallery.swift"]

    /// Every Swift file under the app's folders, as (path under apps/ios, text).
    static func appFiles() throws -> [(String, String)] {
        var files: [(String, String)] = []
        for folder in folders {
            let root = iosFolder.appending(path: folder)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" && !skippedFiles.contains(url.lastPathComponent) {
                let path = String(url.path.dropFirst(iosFolder.path.count + 1))
                files.append((path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return files.sorted { $0.0 < $1.0 }
    }

    /// The file's lines as the rules see them: a comment line, and code
    /// under `#if DEBUG`, become empty; a trailing comment is cut off.
    static func codeLines(_ text: String) -> [String] {
        var debug: [Bool] = []
        return text.components(separatedBy: "\n").map { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if") { debug.append(trimmed.hasPrefix("#if DEBUG")); return "" }
            // The other branch is what a Release build gets, so it's read.
            if trimmed.hasPrefix("#else") { if debug.popLast() != nil { debug.append(false) }; return "" }
            if trimmed.hasPrefix("#endif") { _ = debug.popLast(); return "" }
            if debug.contains(true) || trimmed.hasPrefix("//") { return "" }
            return stripComment(raw)
        }
    }

    /// The line without a `// …` at its end (a `//` inside a string stays).
    static func stripComment(_ line: String) -> String {
        var inString = false
        var previous: Character = " "
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" && previous != "\\" { inString.toggle() }
            if !inString, char == "/", previous == "/" { return String(line[..<line.index(before: index)]) }
            previous = char
            index = line.index(after: index)
        }
        return line
    }

    /// Compiled patterns, kept: the rules run over some twenty thousand lines.
    /// NSCache is safe to use from any thread.
    private nonisolated(unsafe) static let compiled = NSCache<NSString, NSRegularExpression>()

    static func regex(_ pattern: String) -> NSRegularExpression? {
        if let kept = compiled.object(forKey: pattern as NSString) { return kept }
        guard let made = try? NSRegularExpression(pattern: pattern) else { return nil }
        compiled.setObject(made, forKey: pattern as NSString)
        return made
    }

    static func matches(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = regex(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    static func has(_ pattern: String, in text: String) -> Bool { !matches(pattern, in: text).isEmpty }

    /// Whether `rule` is allowed on line `index` by a mark there or above.
    static func allowed(_ rule: Rule, at index: Int, raw: [String]) -> Bool {
        let mark = "ui-check: allow \(rule.id)"
        return raw[index].contains(mark) || (index > 0 && raw[index - 1].trimmingCharacters(in: .whitespaces).hasPrefix("//") && raw[index - 1].contains(mark))
    }

    /// The slips of `rule` in one file.
    static func slips(of rule: Rule, file: String, text: String) -> [Slip] {
        let name = URL(filePath: file).lastPathComponent
        guard rule.skipFiles[name] == nil else { return [] }
        if let unless = rule.unlessFile, has(unless, in: text) { return [] }
        let raw = text.components(separatedBy: "\n")
        let code = codeLines(text)
        var hits: [Int] = rule.wholeFile?(code) ?? []
        for (index, line) in code.enumerated() where !line.isEmpty {
            let hit = rule.patterns.contains { pattern in
                matches(pattern, in: line).contains { rule.accept?(String(line[$0])) ?? true }
            }
            guard hit else { continue }
            if let unless = rule.unlessLine, has(unless, in: line) { continue }
            if let near = rule.unlessNear {
                let around = code[max(0, index - near.lines)...min(code.count - 1, index + near.lines)].joined(separator: "\n")
                if has(near.pattern, in: around) { continue }
            }
            hits.append(index)
        }
        return Set(hits).sorted().filter { !allowed(rule, at: $0, raw: raw) }.map {
            Slip(rule: rule.id, file: file, line: $0 + 1, text: raw[$0].trimmingCharacters(in: .whitespaces))
        }
    }

    static func allSlips() throws -> [Slip] {
        let files = try appFiles()
        return rules.flatMap { rule in files.flatMap { slips(of: rule, file: $0.0, text: $0.1) } }
    }

    /// The baseline's lines (`rule<TAB>file<TAB>the line`), `#` comments left out.
    static func baseline() -> [String] {
        guard let text = try? String(contentsOf: baselineFile, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The rules the baseline has met (its `# rules:` line). A rule not yet
    /// there is new: `WW_UI_SOURCE_BASELINE=new-rules` adds its slips once.
    static func baselineRules() -> [String] {
        guard let text = try? String(contentsOf: baselineFile, encoding: .utf8),
              let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("# rules:") }) else { return [] }
        return line.dropFirst("# rules:".count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func writeBaseline(_ lines: [String], rules: [String]) throws {
        let header = """
            # The source check's baseline (UISourceCheck.swift, #344): the slips that were
            # in the app when each rule arrived, as rule<TAB>file<TAB>the line. It only
            # shrinks: fix a slip and delete its line here. A new slip is fixed or marked
            # where it stands (// ui-check: allow <rule> — why), never added here.
            # rules: \(rules.joined(separator: ", "))

            """
        try (header + lines.sorted().joined(separator: "\n") + "\n").write(to: baselineFile, atomically: true, encoding: .utf8)
    }

    // MARK: The survey

    /// Counts that aren't right or wrong by themselves, for the design
    /// review to read: how many corner radii, spacings and type styles the
    /// app uses, which symbols, and words that mean the same thing.
    static func survey() throws -> [String: Any] {
        let files = try appFiles()
        let code = files.map { ($0.0, codeLines($0.1).joined(separator: "\n")) }
        func count(_ pattern: String, group: Int = 1) -> [String: Int] {
            var counts: [String: Int] = [:]
            guard let regex = regex(pattern) else { return counts }
            for (_, text) in code {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range(at: group), in: text) else { continue }
                    counts[String(text[range]), default: 0] += 1
                }
            }
            return counts
        }
        // Words people read: string literals with a capital or a space in them,
        // off lines that are plainly not labels.
        var strings: [String: [String]] = [:]
        for (file, text) in code {
            for line in text.components(separatedBy: "\n") where !has(#"debugSetting|forKey:|systemName:|systemImage: "[a-z.0-9]+"\)?$|\bcase "|Logger|identifier|UserDefaults"#, in: line) {
                for range in matches(#""((?:[^"\\]|\\.)*)""#, in: line) {
                    let literal = String(line[range].dropFirst().dropLast())
                    guard literal.count > 1, literal.contains(" ") || literal.first?.isUppercase == true,
                          !has(#"^[a-z0-9_.\-/:]+$"#, in: literal) else { continue }
                    strings[literal, default: []].append(URL(filePath: file).lastPathComponent)
                }
            }
        }
        let groups: [[String]] = [
            ["Delete", "Remove", "Erase", "Clear"], ["Sign out", "Log out", "Disconnect"], ["Sign in", "Log in", "Login"],
            ["Cancel", "Close", "Dismiss", "Done", "OK", "Ok", "Okay", "Got it"], ["can't", "cannot", "can’t", "Couldn't", "Could not", "Unable"],
            ["Edit", "Change"], ["Add", "New", "Create"], ["’", "'"], ["e-mail", "email", "Email", "E-mail"], ["Try again", "Retry"],
            ["Save", "Apply", "Update"], ["Turn on", "Enable", "Switch on"], ["Choose", "Select", "Pick"], ["transaction", "line", "entry"],
        ]
        let terms = groups.map { group in
            Dictionary(uniqueKeysWithValues: group.map { term in
                (term, strings.filter { has(term.count == 1 ? NSRegularExpression.escapedPattern(for: term) : #"\b"# + NSRegularExpression.escapedPattern(for: term) + #"\b"#, in: $0.key) }.count)
            })
        }
        return [
            "cornerRadius": count(#"cornerRadius:\s*([0-9.]+)"#),
            "spacing": count(#"spacing:\s*([0-9.]+)"#),
            "padding": count(#"\.padding\((?:\.[a-zA-Z]+,\s*|\[[^\]]*\],\s*)?([0-9.]+)\)"#),
            "fonts": count(#"\.font\(\.([a-zA-Z0-9]+)"#),
            "symbols": count(#"system(?:Name|Image):\s*"([a-z0-9.]+)""#),
            "lineLimitOne": count(#"(\.lineLimit\(1\))"#),
            "minimumScaleFactor": count(#"(\.minimumScaleFactor)\("#),
            "glass": count(#"(glassEffect|GlassEffectContainer|\.glass\b|\.glassProminent\b)"#),
            "materials": count(#"\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial)\b"#),
            "terms": terms,
            "strings": strings.mapValues { Array(Set($0)).sorted() },
        ]
    }
}
