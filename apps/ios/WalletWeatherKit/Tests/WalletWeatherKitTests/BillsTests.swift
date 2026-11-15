import Foundation
import Testing
@testable import WalletWeatherKit

/// Bills & income, the Calendar and moving money (#89), from samples
/// recorded from the demo server at app 1.53.0, seen on Nov 15, 2026.
struct BillsTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try DecodingTests().sample(name)
    }

    func json(_ value: some Encodable) throws -> [String: AnyHashable] {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value))
        let dict = try #require(object as? [String: Any])
        return dict.mapValues { $0 is NSNull ? AnyHashable("null") : (($0 as? AnyHashable) ?? AnyHashable("?")) }
    }

    func item(_ list: RecurringList, _ name: String) throws -> RecurringItem {
        try #require(list.items.first { $0.description == name })
    }

    // MARK: Reading

    @Test func billsAndTotals() throws {
        let list: RecurringList = try sample("recurring")
        #expect(list.items.count == 7)
        #expect(list.totals.billsCount == 6 && list.totals.incomeCount == 1)
        #expect(list.totals.billsMonthly.formatted == "$1,914.48")
        #expect(list.totals.netMonthly.formatted == "$4,152.19")
        let rent = try item(list, "Rent")
        #expect(rent.kind == .monthly && rent.howOften == "Monthly on the 1st")
        #expect(rent.nextDate == LocalDay("2026-12-01") && rent.nextDates.count == 6)
        #expect(rent.canEdit && !rent.isIncome)
        let pay = try item(list, "Paycheck")
        #expect(pay.kind == .biweekly && pay.isIncome)
        #expect(pay.howOften == "Every 2 weeks, Wednesdays")  // Nov 11, 2026 is a Wednesday
        #expect(pay.nextDate == LocalDay("2026-11-25"))
        #expect(pay.nextDates[1] == LocalDay("2026-12-09"))
    }

    @Test func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(ordinal)
                == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
    }

    @Test func calendarAcrossAccountsHasNoBalance() throws {
        let month: CalendarMonth = try sample("calendar-all")
        #expect(month.dailyBalances == nil && month.balance(on: today) == nil)
        let day = LocalDay("2026-11-11")!
        #expect(month.events(on: day).map(\.description) == ["Gas station", "Paycheck"])
        let s = month.summary(of: day)
        #expect(s.hasBill && s.hasIncome && !s.hasTransfer && s.count == 2)
        #expect(s.net.formatted == "$2,751.30")
        #expect(Set(month.events.map(\.id)).count == month.events.count, "ids are unique")
    }

    @Test func calendarForOneAccountHasEachDaysBalance() throws {
        let month: CalendarMonth = try sample("calendar-checking")
        #expect(month.balance(on: today)?.formatted == "$4,854.97")
        #expect(month.balance(on: LocalDay("2026-11-30")!)?.formatted == "$7,594.98")
        #expect(month.dailyBalances?.count == 30)
        #expect(month.summary(of: LocalDay("2026-11-02")!).count == 0)
    }

    // MARK: Adding and changing

    @Test func aNewMonthlyBill() throws {
        var draft = BillDraft(today: today)
        #expect(draft.frequency == .monthly && draft.dayOfMonth == 15 && draft.kind == .spending)
        #expect(draft.problem == "Give it a name.")
        draft.name = "Phone"
        draft.amountText = "45.50"
        draft.dayOfMonth = 12
        #expect(draft.problem == nil)
        let body = try json(RecurringBody(draft))
        #expect(body["description"] == AnyHashable("Phone"))
        #expect(body["amount"] == -45.5 as AnyHashable)
        #expect(body["frequency"] == AnyHashable("monthly_day"))
        #expect(body["day_of_month"] == 12 as AnyHashable)
        #expect(body["anchor_date"] == AnyHashable("null"), "a monthly bill starts at once unless given a start")
        #expect(body["end_date"] == AnyHashable("null"))
        #expect(body["active"] == true as AnyHashable)
        #expect(body["tag_ids"] == nil, "tags are left as they are")
    }

    @Test func aWeeklyPaycheckUsesItsFirstDate() throws {
        var draft = BillDraft(today: today)
        draft.kind = .income
        draft.name = "Side job"
        draft.amountText = "120"
        draft.frequency = .weekly
        draft.start = LocalDay("2026-11-20")!
        let body = try json(RecurringBody(draft))
        #expect(body["amount"] == 120 as AnyHashable)
        #expect(body["frequency"] == AnyHashable("weekly"))
        #expect(body["day_of_month"] == AnyHashable("null"))
        #expect(body["anchor_date"] == AnyHashable("2026-11-20"))
    }

    @Test func changingKeepsWhatItHas() throws {
        let list: RecurringList = try sample("recurring")
        let pay = try item(list, "Paycheck")
        var draft = BillDraft(pay, today: today)
        #expect(draft.kind == .income && draft.amountText == "2800" && draft.frequency == .biweekly)
        #expect(draft.start == LocalDay("2026-11-11") && !draft.ends)
        draft.amountText = "2,850"
        let body = try json(RecurringBody(draft, active: pay.active))
        #expect(body["amount"] == 2850 as AnyHashable)
        #expect(body["anchor_date"] == AnyHashable("2026-11-11"))
    }

    @Test func endingAfterADate() throws {
        let list: RecurringList = try sample("recurring")
        let gym = try item(list, "Gym")
        let body = try json(RecurringBody(ending: gym, after: LocalDay("2026-12-31")!))
        #expect(body["end_date"] == AnyHashable("2026-12-31"))
        #expect(body["description"] == AnyHashable("Gym") && body["amount"] == -39 as AnyHashable)
        #expect(body["day_of_month"] == 5 as AnyHashable)
        #expect(body["category_id"] == (gym.categoryId.map { AnyHashable($0) } ?? AnyHashable("null")))
    }

    @Test func aBillCantEndBeforeItStarts() {
        var draft = BillDraft(today: today)
        draft.name = "x"
        draft.amountText = "1"
        draft.frequency = .weekly
        draft.ends = true
        draft.endDate = LocalDay("2026-11-01")!
        #expect(draft.problem == "It can't end before it starts.")
    }

    // MARK: Moving money

    @Test func movingMoney() throws {
        var draft = MoveMoneyDraft(today: today, from: 1)
        #expect(draft.problem == "Pick both accounts.")
        draft.toAccountId = 1
        #expect(draft.problem == "Pick two different accounts.")
        draft.toAccountId = 2
        #expect(draft.problem == "Enter an amount above zero.")
        draft.amountText = "250"
        draft.description = "  "
        let body = try json(try #require(TransferBody(draft)))
        #expect(body["from_account_id"] == 1 as AnyHashable && body["to_account_id"] == 2 as AnyHashable)
        #expect(body["amount"] == 250 as AnyHashable)
        #expect(body["transfer_date"] == AnyHashable("2026-11-15"))
        #expect(body["description"] == AnyHashable("Transfer"))
        #expect(body["notes"] == AnyHashable("null"))
    }
}
