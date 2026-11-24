import Foundation
import Testing
@testable import WalletWeatherKit

/// Quick add with remembered names (#325): which names are offered for
/// what's typed and in what order, and when the tag rule note shows.
@Suite struct NameSuggestionsTests {
    func day(_ d: Int) -> LocalDay { LocalDay(year: 2026, month: 11, day: d) }

    func use(_ name: String, _ category: Int? = nil, _ catName: String? = nil, _ d: Int? = nil) -> NameUse {
        NameUse(name: name, categoryId: category, categoryName: catName, day: d.map(day))
    }

    func offered(_ typed: String, _ uses: [NameUse], limit: Int = 4) -> [String] {
        NameSuggestions.suggest(typed, in: NameSuggestions.index(uses), limit: limit).map(\.name)
    }

    @Test func oneEntryPerNameWhateverTheCase() {
        let entries = NameSuggestions.index([use("Grocery", 1, "Food", 3), use("grocery ", 2, "Home", 9), use("GROCERY", nil, nil, 5)])
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.count == 3 && entry.lastUsed == day(9))
        // Written as last used, with the category of the latest line that had one.
        #expect(entry.name == "grocery" && entry.categoryId == 2 && entry.categoryName == "Home")
    }

    @Test func categoryIsTheLatestOneThatHadOne() {
        let entry = NameSuggestions.index([use("Gym", 4, "Health", 2), use("Gym", nil, nil, 20)])[0]
        #expect(entry.categoryId == 4 && entry.categoryName == "Health")
        #expect(NameSuggestions.index([use("Gym")])[0].categoryId == nil)
    }

    @Test func nothingUnderTwoLetters() {
        let uses = [use("Grocery", 1, "Food", 3)]
        #expect(offered("", uses).isEmpty && offered("g", uses).isEmpty && offered(" g ", uses).isEmpty)
        #expect(offered("gr", uses) == ["Grocery"])
    }

    @Test func prefixBeforeSubstringThenUsedThenRecent() {
        let uses = [use("Big Grill", 1, nil, 20), use("Big Grill", 1, nil, 21), use("Big Grill", 1, nil, 22),
                    use("Grocery", 1, nil, 2), use("Green Cafe", 1, nil, 9), use("Green Cafe", 1, nil, 9),
                    use("Greek Deli", 1, nil, 15), use("Greek Deli", 1, nil, 3),
                    use("Grain Mill", 1, nil, 30), use("Grain Mill", 1, nil, 1)]
        // "gr": prefix matches (Grocery 1 use; Green Cafe 2; Greek Deli 2; Grain Mill 2), then Big Grill by substring.
        // Between equal counts, the most recent first: Grain Mill (30), Greek Deli (15), Green Cafe (9).
        #expect(offered("gr", uses, limit: 10) == ["Grain Mill", "Greek Deli", "Green Cafe", "Grocery", "Big Grill"])
        #expect(offered("GR", uses, limit: 10) == offered("gr", uses, limit: 10))
    }

    @Test func atMostTheLimit() {
        let uses: [NameUse] = (1...9).map { (n: Int) in use("Shop \(n)", nil, nil, n) }
        #expect(offered("sh", uses).count == 4)
        #expect(offered("sh", uses, limit: 2) == ["Shop 9", "Shop 8"])
    }

    @Test func aNameTypedInFullIsNotOfferedBack() {
        let uses = [use("Grocery", 1, "Food", 3), use("Grocery Outlet", 1, "Food", 4)]
        #expect(offered("Grocery", uses) == ["Grocery Outlet"])
        // Other capitalisation still offers it, for its category.
        #expect(offered("grocery", uses) == ["Grocery Outlet", "Grocery"])
    }

    @Test func transfersAreNotNames() throws {
        let json = #"""
        {"total": 2, "results": [
          {"id": 1, "account_id": 1, "description": "Rent", "amount": -900.00, "actual_date": "2026-11-01",
           "forecast_date": "2026-11-01", "is_actual": true, "category_id": 3, "category_name": "Home", "transfer_id": null},
          {"id": 2, "account_id": 1, "description": "Transfer to Savings", "amount": -50.00, "actual_date": "2026-11-02",
           "forecast_date": "2026-11-02", "is_actual": true, "category_id": null, "category_name": null, "transfer_id": 7}]}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let found = try decoder.decode(TransactionSearch.self, from: Data(json.utf8))
        let uses = NameSuggestions.uses(found.results)
        #expect(uses == [NameUse(name: "Rent", categoryId: 3, categoryName: "Home", day: LocalDay("2026-11-01"))])
    }

    // MARK: - Tag rule note

    func rules() throws -> [TagRule] {
        let json = #"""
        [{"id": 1, "name": "Work", "description_pattern": "uber", "category_id": null, "category_name": null,
          "tag_id": 10, "tag_name": "Work", "tag_color": null, "active": true},
         {"id": 2, "name": null, "description_pattern": "uber eats", "category_id": 5, "category_name": "Dining",
          "tag_id": 11, "tag_name": "Treats", "tag_color": null, "active": true},
         {"id": 3, "name": null, "description_pattern": "lyft", "category_id": null, "category_name": null,
          "tag_id": 10, "tag_name": "Work", "tag_color": null, "active": true},
         {"id": 4, "name": null, "description_pattern": "taxi", "category_id": null, "category_name": null,
          "tag_id": 12, "tag_name": "Cabs", "tag_color": null, "active": false}]
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([TagRule].self, from: Data(json.utf8))
    }

    @Test func noteNamesTheTagsARuleWouldAdd() throws {
        let rules = try rules()
        #expect(TagRuleNote.text(rules: rules, name: "UBER trip", categoryId: nil) == "Will be tagged Work")
        // Substring, case-insensitive, whitespace around the name ignored.
        #expect(TagRuleNote.text(rules: rules, name: "  my Uber ride ", categoryId: 9) == "Will be tagged Work")
        #expect(TagRuleNote.text(rules: rules, name: "Coffee", categoryId: nil) == nil)
        #expect(TagRuleNote.text(rules: rules, name: "", categoryId: nil) == nil)
    }

    @Test func aRuleWithACategoryNeedsThatCategory() throws {
        let rules = try rules()
        #expect(TagRuleNote.text(rules: rules, name: "Uber Eats", categoryId: nil) == "Will be tagged Work")
        #expect(TagRuleNote.text(rules: rules, name: "Uber Eats", categoryId: 5) == "Will be tagged Work and Treats")
    }

    @Test func offRulesAndTagsAlreadyOnTheLineAreLeftOut() throws {
        let rules = try rules()
        #expect(TagRuleNote.text(rules: rules, name: "Taxi", categoryId: nil) == nil)
        #expect(TagRuleNote.text(rules: rules, name: "Uber", categoryId: nil, alreadyTagged: [10]) == nil)
        // Two rules for the same tag name it once.
        #expect(TagRuleNote.text(rules: rules, name: "Uber to Lyft", categoryId: nil) == "Will be tagged Work")
    }

    @Test func theDemoRemembersItsNames() async throws {
        let uses = try await APIClient(connection: Demo.connection).nameHistory()
        #expect(offered("Gr", uses).contains("Grocery store"))
    }
}
