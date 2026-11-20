import Foundation
import Testing
@testable import WalletWeatherKit

/// Tags in the household on this iPhone (Plans/phone-tags.md, phase 1,
/// #250): the server's tag routes with its checks, and tags on every row.
struct LocalTagTests {
    let server: LocalServer
    let client: APIClient
    let day = LocalDay(year: 2026, month: 3, day: 10)

    init() throws {
        server = try LocalServer.inMemory()
        client = APIClient(connection: server.connection)
    }

    /// A request straight to the household, and its JSON.
    @discardableResult
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, query: [String: String] = [:]) throws -> (Int, Any) {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, answer) = server.answer(method: method, path: path, query: query, body: data)
        return (status, try JSONSerialization.jsonObject(with: answer, options: [.fragmentsAllowed]))
    }

    func id(_ answer: (Int, Any)) throws -> Int {
        try #require(answer.0 == 200, "\(answer.1)")
        return try #require((answer.1 as? [String: Any])?["id"] as? Int)
    }

    func names(_ tags: Any?) -> [String] { (tags as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }

    @Test func tagsAreMadeRenamedAndDeletedWithTheServersChecks() throws {
        let work = try id(try call("POST", "/api/tags", ["name": "  Work trip ", "color": "#58a6ff"]))
        _ = try id(try call("POST", "/api/tags", ["name": "Ärzte"]))
        _ = try id(try call("POST", "/api/tags", ["name": "beach"]))
        let (_, list) = try call("GET", "/api/tags")
        // In name order, as the server's ORDER BY name.
        #expect(names(list) == ["Work trip", "beach", "Ärzte"])
        #expect(((list as? [[String: Any]])?.first?["color"] as? String) == "#58a6ff")
        #expect(try call("POST", "/api/tags", ["name": "Work trip"]).0 == 409)
        #expect(try call("POST", "/api/tags", ["name": "   "]).0 == 400)
        #expect(try call("POST", "/api/tags", ["name": String(repeating: "x", count: 61)]).0 == 400)
        #expect(try call("POST", "/api/tags", ["name": "red", "color": "red"]).0 == 400)
        let (status, renamed) = try call("PATCH", "/api/tags/\(work)", ["name": "Travel", "color": ""])
        #expect(status == 200)
        #expect((renamed as? [String: Any])?["name"] as? String == "Travel" && (renamed as? [String: Any])?["color"] is NSNull)
        #expect(try call("PATCH", "/api/tags/\(work)", ["name": "beach"]).0 == 409)
        #expect(try call("PATCH", "/api/tags/424242", ["name": "x"]).0 == 404)
        #expect(try call("DELETE", "/api/tags/\(work)").0 == 200)
        #expect(names(try call("GET", "/api/tags").1) == ["beach", "Ärzte"])
        #expect(try call("DELETE", "/api/tags/\(work)").0 == 404)
    }

    @Test func linesAndBillsCarryTagsEverywhere() async throws {
        let trip = try id(try call("POST", "/api/tags", ["name": "trip"]))
        let food = try id(try call("POST", "/api/tags", ["name": "food"]))
        let checking = try await client.createAccount(AccountBody(name: "Checking", startingBalance: 100, startingDate: day)).id
        // A bill with a tag; a line paid from it starts with the bill's tags (#118).
        let bill = try id(try call("POST", "/api/accounts/\(checking)/recurring", [
            "description": "Hotel", "amount": -90, "frequency": "monthly_day", "day_of_month": 15, "tag_ids": [trip]]))
        let paid = try id(try call("POST", "/api/accounts/\(checking)/transactions", [
            "description": "Hotel", "amount": -90, "forecast_date": "2026-03-15", "actual_date": "2026-03-15",
            "is_actual": true, "recurring_id": bill]))
        let lunch = try id(try call("POST", "/api/accounts/\(checking)/transactions", [
            "description": "Lunch", "amount": -12, "actual_date": "2026-03-09", "is_actual": true, "tag_ids": [food, trip, food]]))
        #expect(try call("POST", "/api/accounts/\(checking)/transactions", [
            "description": "Bad", "amount": -1, "tag_ids": [424242]]).0 == 404)

        let (_, forecast) = try call("GET", "/api/accounts/\(checking)/forecast",
                                     query: ["start": "2026-03-01", "end": "2026-03-31", "today": day.description])
        let rows = try #require(((forecast as? [String: Any])?["rows"] as? [[String: Any]]) ?? (forecast as? [String: Any])?["lines"] as? [[String: Any]])
        let byName = Dictionary(rows.map { ($0["description"] as? String ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        #expect(names(byName["Hotel"]?["tags"]) == ["trip"])
        // Each tag once, in name order.
        #expect(names(byName["Lunch"]?["tags"]) == ["food", "trip"])
        let (_, bills) = try call("GET", "/api/recurring", query: ["today": day.description])
        let items = try #require((bills as? [String: Any])?["items"] as? [[String: Any]])
        #expect(names(items.first?["tags"]) == ["trip"])

        // Changing a line's tags replaces them; leaving tag_ids out keeps them.
        #expect(try call("PATCH", "/api/transactions/\(lunch)", [
            "description": "Lunch", "amount": -12, "actual_date": "2026-03-09", "is_actual": true, "tag_ids": [food]]).0 == 200)
        #expect(try call("PATCH", "/api/transactions/\(paid)", [
            "description": "Hotel stay", "amount": -90, "forecast_date": "2026-03-15", "actual_date": "2026-03-15", "is_actual": true]).0 == 200)
        let (_, found) = try call("GET", "/api/transactions/search", query: ["tag_id": String(trip)])
        let results = (found as? [String: Any])?["results"] as? [[String: Any]] ?? []
        #expect(results.compactMap { $0["description"] as? String } == ["Hotel stay"])
        #expect(try call("GET", "/api/transactions/search", query: ["tag_id": "424242"]).0 == 404)
        // The search box finds tags.
        let (_, everything) = try call("GET", "/api/search", query: ["q": "foo", "today": day.description])
        let tagGroup = (everything as? [String: Any])?["tags"] as? [String: Any]
        #expect(names(tagGroup?["results"]) == ["food"])

        // Deleting a tag takes it off every line and bill.
        #expect(try call("DELETE", "/api/tags/\(trip)").0 == 200)
        let (_, after) = try call("GET", "/api/recurring", query: ["today": day.description])
        let afterItems = (after as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let afterTags = names(afterItems.first?["tags"])
        #expect(afterTags.isEmpty)
        // Deleting a line drops its links.
        #expect(try call("DELETE", "/api/transactions/\(lunch)").0 == 200)
        #expect(try call("GET", "/api/transactions/search", query: ["tag_id": String(food)]).1 is [String: Any])
    }

    @Test func aCSVImportTagsLinesWithTagsThatExist() async throws {
        let work = try id(try call("POST", "/api/tags", ["name": "Work trip"]))
        let checking = try await client.createAccount(AccountBody(name: "Checking", startingBalance: 0, startingDate: day)).id
        var body = CSVImportBody(csvText: "Date,Description,Amount,Tags\n2026-03-05,Taxi,-20,\"work TRIP; nope\"\n")
        body.mapping = try await client.previewImport(body, account: checking).mapping
        #expect(try await client.commitImport(body, account: checking).inserted == 1)
        let (_, found) = try call("GET", "/api/transactions/search", query: ["tag_id": String(work)])
        #expect(((found as? [String: Any])?["results"] as? [[String: Any]])?.count == 1)
    }

    /// Through the app's own calls (#251): tags read on lines, bills and
    /// search hits; sent only when changed, so a bill's date marked paid
    /// still takes the bill's tags.
    @Test func theAppsCallsReadAndChangeTags() async throws {
        let trip = try await client.createTag(name: "trip", color: "#58a6ff")
        let food = try await client.createTag(name: "food", color: nil)
        #expect(try await client.tags().map(\.name) == ["food", "trip"])
        let checking = try await client.createAccount(AccountBody(name: "Checking", startingBalance: 100, startingDate: day)).id
        var bill = BillDraft(today: day)
        bill.name = "Hotel"
        bill.amountText = "90"
        bill.dayOfMonth = 20
        bill.tagIds = [trip.id]
        try await client.addRecurring(bill, account: checking)
        var lunch = NewTransactionDraft(today: day)
        lunch.name = "Lunch"
        lunch.amountText = "12"
        lunch.tagIds = [food.id]
        try await client.add(lunch, account: checking)

        let month = try await client.forecast(account: checking, month: YearMonth(day), today: day)
        let hotel = try #require(month.rows.first { $0.description == "Hotel" })
        #expect(hotel.tags?.map(\.name) == ["trip"] && hotel.isProjection)
        // Marked paid unchanged: no tag_ids sent, the bill's tags come along.
        try await client.save(hotel, draft: LineDraft.paidAsPlanned(hotel, today: day), account: checking)
        let line = try #require(try await client.forecast(account: checking, month: YearMonth(day), today: day)
            .rows.first { $0.description == "Lunch" })
        #expect(line.tags?.map(\.name) == ["food"])
        // Changed: sent.
        var draft = LineDraft(line, today: day)
        draft.tagIds = [food.id, trip.id]
        try await client.save(line, draft: draft, account: checking)
        let after = try await client.forecast(account: checking, month: YearMonth(day), today: day)
        #expect(after.rows.first { $0.description == "Hotel" }?.tags?.map(\.name) == ["trip"])
        #expect(after.rows.first { $0.description == "Lunch" }?.tags?.map(\.name) == ["food", "trip"])
        // A bill's tags changed through its editor.
        let item = try #require(try await client.recurring(today: day).items.first)
        #expect(item.tags?.map(\.name) == ["trip"])
        var edit = BillDraft(item, today: day)
        edit.tagIds = []
        try await client.updateRecurring(item.id, RecurringBody(edit, active: item.active))
        #expect(try await client.recurring(today: day).items.first?.tags == [])
        // Search hits carry tags; a tag's lines.
        let hits = try await client.searchTransactions("lunch")
        #expect(hits.results.first?.tags?.map(\.name) == ["food", "trip"])
        #expect(hits.results.first?.line.tags?.count == 2)
        try await client.updateTag(trip.id, name: "Travel", color: nil)
        try await client.deleteTag(food.id)
        #expect(try await client.tags() == [TagInfo(id: trip.id, name: "Travel", color: nil)])
    }
}
