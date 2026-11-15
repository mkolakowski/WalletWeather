import Foundation
import Testing
@testable import WalletWeatherKit

/// The Forecast page's data (#88), from samples recorded from the demo
/// server at app 1.52.0: Checking in November 2026, seen on Nov 15.
struct ForecastTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try DecodingTests().sample(name)
    }

    func line(_ month: ForecastMonth, _ name: String) throws -> ForecastLine {
        try #require(month.rows.first { $0.description == name })
    }

    func json(_ body: TransactionBody) throws -> [String: AnyHashable] {
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let dict = try #require(object as? [String: Any])
        return dict.mapValues { $0 is NSNull ? AnyHashable("null") : (($0 as? AnyHashable) ?? AnyHashable("?")) }
    }

    // MARK: Reading

    @Test func decodesTheMonth() throws {
        let month: ForecastMonth = try sample("forecast")
        #expect(month.rows.count == 11)
        #expect(month.currentBalance.formatted == "$4,854.97")
        #expect(month.forecastEndingBalance.formatted == "$7,594.98")  // 7594.980000000001 on the wire
        let rent = try line(month, "Rent")
        #expect(rent.isProjection && !rent.isPaid)
        #expect(rent.id == "r2-2026-11-01")
        #expect(rent.categoryId == 5 && rent.category == "Rent/Mortgage")
        let store = try line(month, "Department store")
        #expect(store.id == "t5" && store.isPaid && !store.isProjection)
        #expect(!store.differsFromPlan)
        #expect(store.canEdit(onEditableAccount: true))
        #expect(!store.canEdit(onEditableAccount: false))
    }

    @Test func summary() throws {
        let month: ForecastMonth = try sample("forecast")
        let s = ForecastSummary(month, today: today)
        #expect(s.incomePlanned.formatted == "$5,600.00")
        #expect(s.incomeSoFar == .zero)
        #expect(s.spendingSoFar.formatted == "-$263.21")
        #expect(s.spendingPlanned.formatted == "-$2,112.69")
        // Streaming on the 15th, Internet, and the second paycheck.
        #expect(s.comingCount == 3)
        #expect(s.comingNet.formatted == "$2,724.52")
        #expect(s.overdue.map(\.description) == ["Rent", "Gym", "Paycheck", "Electric"])
        #expect(s.low.balance.formatted == "$2,242.88" && s.low.date == LocalDay("2026-11-11"))
        #expect(s.high.balance.formatted == "$7,594.98" && s.high.date == LocalDay("2026-11-25"))
        #expect(s.differing.isEmpty)
    }

    @Test func summaryOfAnEmptyMonthIsTheOpeningBalance() {
        let month = ForecastMonth(openingBalance: Money(Decimal(120)), forecastEndingBalance: Money(Decimal(120)),
                                  actualEndingBalance: Money(Decimal(120)), currentBalance: Money(Decimal(120)), rows: [])
        let s = ForecastSummary(month, today: today)
        #expect(s.low.balance == Money(Decimal(120)) && s.low.date == nil)
        #expect(s.comingCount == 0 && s.overdue.isEmpty)
    }

    @Test func categoriesAndMe() throws {
        let cats: [TransactionCategory] = try sample("categories")
        #expect(cats.contains { $0.id == 5 && $0.name == "Rent/Mortgage" })
        let me: Me = try sample("me")
        #expect(me.tokenAccess == "full" && !me.isReadOnly)
    }

    @Test func searchHitOpensAsALine() throws {
        let found: TransactionSearch = try sample("search")
        #expect(found.total == 7)
        let gas = try #require(found.results.first)
        #expect(gas.description == "Gas station" && gas.accountName == "Checking")
        let line = gas.line
        #expect(line.transactionId == gas.id && line.isPaid)
        #expect(line.amount.formatted == "-$48.70")
        #expect(LineDraft(line, today: today).paid)
    }

    // MARK: Months

    @Test func months() {
        let dec = YearMonth(year: 2026, month: 12)
        #expect(dec.next == YearMonth(year: 2027, month: 1))
        #expect(YearMonth(year: 2027, month: 1).previous == dec)
        #expect(dec.end == LocalDay("2026-12-31"))
        #expect(YearMonth(year: 2028, month: 2).end == LocalDay("2028-02-29"))
        #expect(YearMonth("2026-11") == YearMonth(today))
        #expect(YearMonth("2026-13") == nil)
        #expect(dec.contains(LocalDay("2026-12-05")!) && !dec.contains(today))
    }

    // MARK: Changing a line

    @Test func swipeDatesAnOldBillOnItsDayAndAnEarlyOneToday() throws {
        let month: ForecastMonth = try sample("forecast")
        let rent = LineDraft.paidAsPlanned(try line(month, "Rent"), today: today)
        #expect(rent.paid && rent.paidOn == LocalDay("2026-11-01") && rent.paidAmount == 1650)
        let internet = LineDraft.paidAsPlanned(try line(month, "Internet"), today: today)
        #expect(internet.paidOn == today)
    }

    @Test func markingAProjectionPaidAtADifferentAmount() throws {
        let month: ForecastMonth = try sample("forecast")
        let rent = try line(month, "Rent")
        var draft = LineDraft(rent, today: today)
        #expect(!draft.paid && draft.amountText == "1650")
        draft.paid = true
        draft.amountText = "1,700.25"
        draft.paidOn = LocalDay("2026-11-02")!
        draft.notes = "  late fee  "
        #expect(draft.problem == nil)
        let body = try json(TransactionBody(line: rent, draft: draft))
        #expect(body["description"] == AnyHashable("Rent"))
        #expect(body["amount"] == -1700.25 as AnyHashable)
        #expect(body["forecast_amount"] == -1650 as AnyHashable)
        #expect(body["forecast_date"] == AnyHashable("2026-11-01"))
        #expect(body["actual_date"] == AnyHashable("2026-11-02"))
        #expect(body["is_actual"] == true as AnyHashable)
        #expect(body["recurring_id"] == 2 as AnyHashable)
        #expect(body["category_id"] == 5 as AnyHashable)
        #expect(body["notes"] == AnyHashable("late fee"))
        #expect(body["tag_ids"] == nil, "tags are left as they are")
    }

    @Test func undoingPaidClearsTheRealDate() throws {
        let month: ForecastMonth = try sample("forecast")
        let store = try line(month, "Department store")
        let body = try json(TransactionBody(line: store, draft: .unpaid(store, today: today)))
        #expect(body["is_actual"] == false as AnyHashable)
        #expect(body["amount"] == -72.18 as AnyHashable)
        #expect(body["actual_date"] == AnyHashable("null"), "sent as null, so the server clears it")
        #expect(body["notes"] == AnyHashable("null"))
        #expect(body["category_id"] == 9 as AnyHashable)
    }

    @Test func aPaidLineNeedsAnAmount() throws {
        let month: ForecastMonth = try sample("forecast")
        var draft = LineDraft(try line(month, "Gym"), today: today)
        draft.paid = true
        draft.amountText = "abc"
        #expect(draft.problem != nil)
        draft.paid = false
        #expect(draft.problem == nil)
    }

    @Test func addingAOneOff() throws {
        var draft = NewTransactionDraft(today: today)
        #expect(draft.paid && draft.kind == .spending && draft.date == today)
        #expect(draft.problem == "Give it a name.")
        draft.name = " Coffee "
        #expect(draft.problem == "Enter an amount above zero.")
        draft.amountText = "4.50"
        #expect(draft.problem == nil)
        var body = try json(TransactionBody(new: draft))
        #expect(body["description"] == AnyHashable("Coffee"))
        #expect(body["amount"] == -4.5 as AnyHashable)
        #expect(body["forecast_amount"] == -4.5 as AnyHashable)
        #expect(body["actual_date"] == AnyHashable("2026-11-15") && body["is_actual"] == true as AnyHashable)
        #expect(body["recurring_id"] == AnyHashable("null"))

        draft.kind = .income
        draft.paid = false
        draft.date = LocalDay("2026-11-20")!
        body = try json(TransactionBody(new: draft))
        #expect(body["amount"] == 4.5 as AnyHashable)
        #expect(body["actual_date"] == AnyHashable("null") && body["is_actual"] == false as AnyHashable)
        #expect(body["forecast_date"] == AnyHashable("2026-11-20"))
    }

    @Test(arguments: [("1,234.50", Decimal(string: "1234.5")), ("$12", 12), ("-3", 3), ("0", 0),
                      ("abc", nil), ("1.2.3", nil), ("", nil), (" ", nil)] as [(String, Decimal?)])
    func parsesTypedAmounts(_ text: String, _ value: Decimal?) {
        #expect(parseAmount(text) == value)
    }
}
