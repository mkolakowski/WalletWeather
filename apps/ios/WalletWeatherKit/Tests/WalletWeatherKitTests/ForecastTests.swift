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

    // MARK: A one-off's name, planned date and planned amount (#316)

    /// A line as the server sends it, built by hand: unpaid by default,
    /// planned -40.00 on Nov 20.
    func oneOff(paid: Bool = false, recurringId: Int? = nil, transferId: Int? = nil,
                transactionId: Int? = 77) -> ForecastLine {
        let planned = Money(Decimal(-40))
        let day = LocalDay(year: 2026, month: 11, day: 20)
        return ForecastLine(forecastDate: day, actualDate: paid ? LocalDay(year: 2026, month: 11, day: 21) : day,
                            description: "Haircut", category: nil, categoryId: 3, notes: "tip", forecastAmount: planned,
                            forecastBalance: .zero, actualAmount: paid ? Money(Decimal(-45)) : planned, actualBalance: .zero,
                            diffAmount: nil, diffBalance: .zero, isActualReal: paid, recurringId: recurringId,
                            transactionId: transactionId, transferId: transferId)
    }

    @Test func aOneOffsDraftTakesItsNameDateAndPlannedAmount() throws {
        let draft = LineDraft(oneOff(), today: today)
        #expect(draft.editsPlan)
        #expect(draft.name == "Haircut" && draft.plannedOn == LocalDay("2026-11-20") && draft.plannedAmountText == "40")
        #expect(draft.problem == nil)
        // The existing members mean what they did.
        #expect(!draft.paid && draft.amountText == "40" && draft.notes == "tip" && draft.categoryId == 3)
        let paid = LineDraft(oneOff(paid: true), today: today)
        #expect(paid.paid && paid.amountText == "45" && paid.plannedAmountText == "40")
        #expect(paid.plannedOn == LocalDay("2026-11-20") && paid.paidOn == LocalDay("2026-11-21"))
    }

    @Test func onlyASavedLineYouAddedHasTheFields() throws {
        let month: ForecastMonth = try sample("forecast")
        #expect(oneOff().isOneOff)
        #expect(try line(month, "Department store").isOneOff)
        #expect(!(try line(month, "Rent")).isOneOff, "a projected date of a bill")
        #expect(!oneOff(recurringId: 2).isOneOff, "a bill's saved date")
        #expect(!oneOff(transferId: 9).isOneOff, "a transfer")
        #expect(!oneOff(transactionId: nil).isOneOff)
        #expect(!LineDraft(oneOff(recurringId: 2), today: today).editsPlan)
    }

    @Test func eachPlannedFieldAloneChangesOnlyItsOwnPartOfTheBody() throws {
        let line = oneOff()
        let before = try json(TransactionBody(line: line, draft: LineDraft(line, today: today)))
        #expect(before["description"] == AnyHashable("Haircut") && before["forecast_date"] == AnyHashable("2026-11-20"))
        #expect(before["forecast_amount"] == -40 as AnyHashable && before["amount"] == -40 as AnyHashable)

        func changed(_ edit: (inout LineDraft) -> Void) throws -> Set<String> {
            var draft = LineDraft(line, today: today)
            edit(&draft)
            let after = try json(TransactionBody(line: line, draft: draft))
            return Set(after.keys.filter { after[$0] != before[$0] })
        }
        #expect(try changed { $0.name = "  Haircut and beard " } == ["description"])
        #expect(try changed { $0.plannedOn = LocalDay("2026-11-24")! } == ["forecast_date"])
        // Unpaid: the amount follows the planned one, and it stays unpaid.
        #expect(try changed { $0.plannedAmountText = "$52.50" } == ["forecast_amount", "amount"])
        var draft = LineDraft(line, today: today)
        draft.name = "Haircut and beard"
        draft.plannedOn = LocalDay("2026-11-24")!
        draft.plannedAmountText = "52.50"
        let body = try json(TransactionBody(line: line, draft: draft))
        #expect(body["description"] == AnyHashable("Haircut and beard"))
        #expect(body["forecast_date"] == AnyHashable("2026-11-24"))
        #expect(body["forecast_amount"] == -52.5 as AnyHashable && body["amount"] == -52.5 as AnyHashable)
        #expect(body["is_actual"] == false as AnyHashable && body["actual_date"] == AnyHashable("null"))
        #expect(body["category_id"] == 3 as AnyHashable && body["notes"] == AnyHashable("tip"))
    }

    @Test func changingThePlanLeavesAPaidLinesRealAmountAndDate() throws {
        let line = oneOff(paid: true)
        var draft = LineDraft(line, today: today)
        draft.plannedAmountText = "60"
        draft.plannedOn = LocalDay("2026-11-18")!
        let body = try json(TransactionBody(line: line, draft: draft))
        #expect(body["forecast_amount"] == -60 as AnyHashable && body["forecast_date"] == AnyHashable("2026-11-18"))
        #expect(body["amount"] == -45 as AnyHashable && body["actual_date"] == AnyHashable("2026-11-21"))
        #expect(body["is_actual"] == true as AnyHashable)
    }

    @Test func aOneOffThatIsIncomeKeepsItsSign() throws {
        let income = ForecastLine(forecastDate: today, actualDate: today, description: "Refund", category: nil, categoryId: nil,
                                  notes: nil, forecastAmount: Money(Decimal(20)), forecastBalance: .zero,
                                  actualAmount: Money(Decimal(20)), actualBalance: .zero, diffAmount: nil, diffBalance: .zero,
                                  isActualReal: false, recurringId: nil, transactionId: 5, transferId: nil)
        var draft = LineDraft(income, today: today)
        draft.plannedAmountText = "25"
        let body = try json(TransactionBody(line: income, draft: draft))
        #expect(body["forecast_amount"] == 25 as AnyHashable && body["amount"] == 25 as AnyHashable)
    }

    @Test func otherLinesSendWhatTheyAlwaysDid() throws {
        let month: ForecastMonth = try sample("forecast")
        let rent = try line(month, "Rent")
        let transfer = oneOff(transferId: 9)
        let fromBill = oneOff(recurringId: 2)
        for line in [rent, transfer, fromBill] {
            var untouched = LineDraft(line, today: today)
            untouched.paid = true
            let expected = try json(TransactionBody(line: line, draft: untouched))
            // Even a draft whose plan values were changed sends the line's own.
            var edited = untouched
            edited.name = "Something else"
            edited.plannedOn = LocalDay("2026-12-30")!
            edited.plannedAmountText = "1"
            #expect(try json(TransactionBody(line: line, draft: edited)) == expected)
            #expect(expected["description"] == AnyHashable(line.description))
            #expect(expected["forecast_date"] == AnyHashable(line.forecastDate!.description))
            #expect(edited.problem == nil, "nothing to check on fields that aren't shown")
        }
    }

    @Test func theEditedPlanIsChecked() {
        var draft = LineDraft(oneOff(), today: today)
        draft.name = "   "
        #expect(draft.problem == "Give it a name.")
        draft.name = String(repeating: "x", count: LineDraft.nameMax + 1)
        #expect(draft.problem == "A name can be up to 500 characters.")
        draft.name = String(repeating: "x", count: LineDraft.nameMax)
        #expect(draft.problem == nil)
        for bad in ["", "abc", "1.2.3", "-"] {
            draft.plannedAmountText = bad
            #expect(draft.problem == "Enter the amount it's planned for.", "\(bad)")
        }
        draft.plannedAmountText = "0"
        #expect(draft.problem == nil, "zero is allowed")
        // Checked whether or not it's paid, and before the paid amount.
        draft.paid = true
        draft.amountText = "x"
        #expect(draft.problem == "Enter the amount it really came to.")
        draft.plannedAmountText = "x"
        #expect(draft.problem == "Enter the amount it's planned for.")
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
