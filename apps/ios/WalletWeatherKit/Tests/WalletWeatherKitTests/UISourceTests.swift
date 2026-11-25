import Foundation
import Testing

/// The source check over the app's own Swift (Plans/ios-ui-review.md,
/// phase 1, #344). No simulator: it reads the files in this checkout.
///
/// - `WW_UI_SOURCE_REPORT=<file>` also writes everything it matched, the
///   baseline's slips included, and the survey, as JSON for `/ios-ui-review`.
/// - `WW_UI_SOURCE_BASELINE=prune` rewrites the baseline without the lines
///   that no longer match. `WW_UI_SOURCE_BASELINE=new-rules` adds the slips
///   of a rule the baseline hasn't met yet (its `# rules:` line), once, on
///   the day the rule arrives. Nothing else adds a line.
struct UISourceTests {
    /// A slip that isn't on the baseline fails; so does a baseline line
    /// that no longer matches anything, so the baseline only shrinks.
    @Test func noNewSlips() throws {
        let slips = try UISource.allSlips()
        var waiting = UISource.baseline()
        var new: [UISource.Slip] = []
        for slip in slips {
            if let index = waiting.firstIndex(of: slip.key) { waiting.remove(at: index) } else { new.append(slip) }
        }
        let environment = ProcessInfo.processInfo.environment
        if let report = environment["WW_UI_SOURCE_REPORT"] {
            try Self.writeReport(slips: slips, new: new, to: URL(filePath: report))
        }
        switch environment["WW_UI_SOURCE_BASELINE"] {
        case "prune" where !waiting.isEmpty:
            var kept = UISource.baseline()
            for line in waiting { if let index = kept.firstIndex(of: line) { kept.remove(at: index) } }
            try UISource.writeBaseline(kept, rules: UISource.baselineRules())
            waiting = []
        case "new-rules":
            // A rule the baseline hasn't met brings the slips it finds on the day it arrives.
            let met = UISource.baselineRules()
            let arriving = new.filter { !met.contains($0.rule) }
            try UISource.writeBaseline(UISource.baseline() + arriving.map(\.key), rules: UISource.rules.map(\.id))
            new.removeAll { !met.contains($0.rule) }
        default:
            break
        }
        for slip in new {
            let rule = UISource.rules.first { $0.id == slip.rule }
            Issue.record("""
                \(slip.file):\(slip.line): \(slip.rule): \(slip.text)
                  \(rule?.why ?? "")
                  Fix: \(rule?.fix ?? "")
                  Right as written? Mark the line: // ui-check: allow \(slip.rule) — why
                """)
        }
        for line in waiting {
            Issue.record("""
                The baseline lists a slip that's gone (fixed, or its line changed): \(line.replacingOccurrences(of: "\t", with: " | "))
                  Delete its line from WalletWeatherKit/Tests/UISourceBaseline.txt, or run with WW_UI_SOURCE_BASELINE=prune.
                """)
        }
    }

    /// Each rule catches the lines it's for and leaves the ones beside them alone.
    @Test(arguments: UISource.rules)
    func catchesWhatItsFor(_ rule: UISource.Rule) {
        #expect(!rule.bad.isEmpty && !rule.good.isEmpty)
        for line in rule.bad {
            #expect(UISource.slips(of: rule, file: "WalletWeather/Views/Example.swift", text: line).count == 1, "\(rule.id) should catch: \(line)")
        }
        for line in rule.good {
            #expect(UISource.slips(of: rule, file: "WalletWeather/Views/Example.swift", text: line).isEmpty, "\(rule.id) shouldn't catch: \(line)")
        }
    }

    /// The mark that says a line is right as written, and what's never read.
    @Test func marksAndCommentsAreLeftAlone() throws {
        let rule = try #require(UISource.rules.first { $0.id == "replaced-api" })
        let file = "WalletWeather/Views/Example.swift"
        #expect(UISource.slips(of: rule, file: file, text: "Text(\"a\").foregroundColor(.red)").count == 1)
        #expect(UISource.slips(of: rule, file: file, text: "Text(\"a\").foregroundColor(.red) // ui-check: allow replaced-api — a test").isEmpty)
        #expect(UISource.slips(of: rule, file: file, text: "// ui-check: allow replaced-api — a test\nText(\"a\").foregroundColor(.red)").isEmpty)
        #expect(UISource.slips(of: rule, file: file, text: "// Text(\"a\").foregroundColor(.red)").isEmpty)
        #expect(UISource.slips(of: rule, file: file, text: "#if DEBUG\nText(\"a\").foregroundColor(.red)\n#endif").isEmpty)
        #expect(UISource.slips(of: rule, file: file, text: "#if DEBUG\nText(\"a\")\n#else\nText(\"a\").foregroundColor(.red)\n#endif").count == 1)
        #expect(UISource.stripComment("let url = \"https://example.com\" // a note") == "let url = \"https://example.com\" ")
    }

    /// Every rule id is its own, and every baseline line names a rule that exists.
    @Test func theBaselineIsWellFormed() {
        let ids = UISource.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for line in UISource.baseline() {
            let parts = line.components(separatedBy: "\t")
            #expect(parts.count == 3 && ids.contains(parts[0]), "A baseline line that isn't rule<TAB>file<TAB>line: \(line)")
        }
    }

    static func writeReport(slips: [UISource.Slip], new: [UISource.Slip], to url: URL) throws {
        let newKeys = Set(new)
        let report: [String: Any] = [
            "rules": UISource.rules.map { rule in
                ["id": rule.id, "why": rule.why, "fix": rule.fix, "count": slips.filter { $0.rule == rule.id }.count,
                 "skips": rule.skipFiles] as [String: Any]
            },
            "slips": slips.map { ["rule": $0.rule, "file": $0.file, "line": $0.line, "text": $0.text, "new": newKeys.contains($0)] as [String: Any] },
            "survey": try UISource.survey(),
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
