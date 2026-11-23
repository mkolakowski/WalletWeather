import Foundation
import Testing
@testable import WalletWeatherKit

/// The shared JavaScript core in JavaScriptCore (#234) gives the server's
/// answers: every case in packages/core/answer-key/, compared inside
/// JavaScript so every number is checked to the last bit, as the server's
/// own tests do (apps/server/tests/test_core_answer_key.py).
struct CoreTests {
    /// The repository's root, from this file's place in it.
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let households = ["basics", "edges", "two-accounts", "imports", "matching"]

    /// Runs every case of one answer-key file and lists what differs.
    static let checker = #"""
    function __checkHousehold(text) {
      const cases = JSON.parse(text).cases;
      const report = [];
      for (const c of cases) {
        const got = JSON.parse(WalletWeatherCore.run(c.function, JSON.stringify(c.input)));
        const problems = [];
        (function diff(a, b, path) {
          if (typeof b === "number" && typeof a === "number") {
            if (a !== b) problems.push(path + ": " + a + " != " + b);
          } else if (Array.isArray(b)) {
            if (!Array.isArray(a) || a.length !== b.length) problems.push(path + ": lengths differ");
            else b.forEach((x, i) => diff(a[i], x, path + "[" + i + "]"));
          } else if (b !== null && typeof b === "object") {
            const ka = Object.keys(a || {}).sort().join(), kb = Object.keys(b).sort().join();
            if (ka !== kb) problems.push(path + ": keys " + ka + " != " + kb);
            else for (const k of Object.keys(b)) diff(a[k], b[k], path + "." + k);
          } else if (a !== b) {
            problems.push(path + ": " + JSON.stringify(a) + " != " + JSON.stringify(b));
          }
        })(got, c.expected, "$");
        report.push({ name: c.name, problems: problems.slice(0, 5) });
      }
      return JSON.stringify(report);
    }
    """#

    struct Result: Decodable {
        let name: String
        let problems: [String]
    }

    @Test func theCopyMatchesTheOriginal() throws {
        let original = try Data(contentsOf: Self.repo.appending(path: "packages/core/walletweather-core.js"))
        let copy = try #require(Core.source())
        #expect(Data(copy.utf8) == original, "Run Scripts/copy-core.sh: the package's copy of the core is out of date.")
    }

    @Test(arguments: households)
    func theCoreGivesTheServersAnswers(household: String) throws {
        let text = try String(contentsOf: Self.repo.appending(path: "packages/core/answer-key/\(household).json"),
                              encoding: .utf8)
        let core = Core()
        _ = try core.evaluate(Self.checker + "\n\"loaded\"")
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [text]), as: UTF8.self)
        let answer = try core.evaluate("__checkHousehold(\(literal)[0])")
        let results = try JSONDecoder().decode([Result].self, from: Data(answer.utf8))
        #expect(!results.isEmpty)
        for result in results {
            #expect(result.problems.isEmpty, "\(household): \(result.name): \(result.problems.joined(separator: "; "))")
        }
    }

    @Test func everyFunctionIsCovered() throws {
        var functions = Set<String>()
        for household in Self.households {
            let data = try Data(contentsOf: Self.repo.appending(path: "packages/core/answer-key/\(household).json"))
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            for c in object["cases"] as? [[String: Any]] ?? [] { functions.insert(c["function"] as? String ?? "") }
        }
        #expect(functions == ["forecast", "actualBalanceAsOf", "upcomingDates", "calendar", "dashboard", "dashboardCharts",
                             "recurringList", "searchTransactions", "search", "csvPreview", "csvCommit",
                             "bankMatch", "bankUnmatched", "bankCandidates", "bankNear", "bankCatchUp"])
    }

    @Test func plainValuesGoInAndComeOut() throws {
        let dates = try #require(try Core.shared.run("upcomingDates", [
            "today": "2028-02-01", "count": 2,
            "recurring": ["frequency": "monthly_day", "day_of_month": 31, "active": true,
                          "anchor_date": NSNull(), "end_date": NSNull(), "amount": -1, "description": "Rent"],
        ] as [String: Any]) as? [String])
        #expect(dates == ["2028-02-29", "2028-03-31"])
    }

    @Test func anUnknownFunctionIsAProblemNotACrash() {
        #expect(throws: Core.Problem.self) { _ = try Core.shared.run("noSuchFunction", json: Data("{}".utf8)) }
        // The core still answers afterwards.
        #expect(throws: Never.self) { _ = try Core.shared.run("upcomingDates", json: Data(#"{"today":"2026-01-01","recurring":{"active":false}}"#.utf8)) }
    }
}
