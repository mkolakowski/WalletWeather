import Foundation
import Testing
@testable import WalletWeatherKit

/// Reminders worked out on the phone (Plans/outside-the-app.md, phase 2,
/// #319): what's scheduled for each switch, nothing when it's off, for the
/// demo or for a server set to Nothing, a dip told once, new bank lines told
/// once, never an amount in the text, and what the expanded view may show.
struct ReminderTests {
    /// Noon on 2026-11-15, in New York.
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))! }
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func day(_ ahead: Int) -> LocalDay { today.adding(days: ahead) }

    func account(_ id: Int, _ name: String, balance: Double, lows: [(Int, Double)]) -> ConnectionSummary.Account {
        ConnectionSummary.Account(id: id, name: name, balance: Money(balance), monthLow: Money(balance), monthLowDate: nil,
                                  toConfirm: 0, weekLows: lows.map { .init(date: day($0.0), low: Money($0.1)) })
    }

    func summary(accounts: [ConnectionSummary.Account]? = nil, bills: [ConnectionSummary.Bill]? = nil,
                 keepsNumbers: Bool = true) -> ConnectionSummary {
        ConnectionSummary(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, name: "Home", kind: .server, madeAt: now,
            keepsNumbers: keepsNumbers,
            accounts: accounts ?? [account(1, "Checking", balance: 900, lows: [(0, 900), (3, 40), (5, 700)]),
                                   account(2, "Credit Card", balance: -1020, lows: [(0, -1020)])],
            bills: bills ?? [
                .init(id: 1, name: "Rent", accountId: 1, accountName: "Checking", amount: Money(-1650.0), nextDate: day(3)),
                .init(id: 2, name: "Phone", accountId: 1, accountName: "Checking", amount: Money(-65.0), nextDate: day(1)),
                .init(id: 3, name: "Paycheck", accountId: 1, accountName: "Checking", amount: Money(2800.0), nextDate: day(2)),
                .init(id: 4, name: "Gym", accountId: 1, accountName: "Checking", amount: Money(-39.99), nextDate: today),
                .init(id: 5, name: "Old", accountId: 1, accountName: "Checking", amount: Money(-10.0), nextDate: nil),
            ])
    }

    func settings(bills: Bool = false, balance: Bool = false, bank: Bool = false) -> ReminderSettings {
        var s = ReminderSettings()
        s.billsOn = bills
        s.balanceOn = balance
        s.bankLinesOn = bank
        return s
    }

    func plan(_ summary: ConnectionSummary?, _ settings: ReminderSettings, state: ReminderState = ReminderState(),
              at time: Date? = nil) -> (reminders: [PlannedReminder], state: ReminderState) {
        ReminderPlan.make(summary, settings: settings, state: state, now: time ?? now, calendar: calendar)
    }

    // MARK: Off, the demo, Nothing

    @Test func theSwitchesStartOff() {
        let start = ReminderSettings()
        #expect(!start.billsOn && !start.balanceOn && !start.bankLinesOn && !start.anyOn)
        #expect(start.billHour == 9 && start.billMinute == 0)
        #expect(start.balanceAmount == Money(100.0))
        #expect(plan(summary(), start).reminders.isEmpty)
    }

    @Test func nothingForTheDemoOrASetToNothingServer() {
        let all = settings(bills: true, balance: true, bank: true)
        // The demo and an unsaved connection have no summary.
        #expect(plan(nil, all).reminders.isEmpty)
        // A server set to Nothing has its name only.
        let nothing = summary(keepsNumbers: false)
        #expect(nothing.bills.isEmpty)
        #expect(plan(nothing, all).reminders.isEmpty)
        // And a dip remembered before is forgotten.
        var state = ReminderState()
        state.dips = ["x/1": today]
        #expect(plan(nil, all, state: state).state.dips.isEmpty)
    }

    // MARK: Bill due tomorrow

    var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 8))! }

    @Test func eachBillAtNineTheDayBefore() throws {
        let reminders = plan(summary(), settings(bills: true), at: morning).reminders
        // Not the paycheck, not one due today (its day before is gone), not one with no date.
        #expect(reminders.map(\.title) == ["Phone is due tomorrow", "Rent is due tomorrow"])
        let phone = try #require(reminders.first)
        #expect(phone.kind == .bill)
        #expect(phone.body == "Checking · Home")
        let times = reminders.map { calendar.dateComponents([.month, .day, .hour, .minute], from: $0.fireAt!) }
        #expect(times.map(\.day) == [15, 17])
        #expect(times.allSatisfy { $0.hour == 9 && $0.minute == 0 })
        #expect(phone.id == "net.iptater.walletweather.reminder.bill.11111111-2222-3333-4444-555555555555.2")
        #expect(phone.userInfo == ["kind": "bill", "connection": "11111111-2222-3333-4444-555555555555", "item": "2",
                                   "day": "2026-11-16"])
    }

    @Test func aTimeAlreadyPastIsLeftOut() {
        // At noon Phone's 9 AM reminder today has gone by.
        let late = plan(summary(), settings(bills: true)).reminders
        #expect(late.map(\.item) == [1])
        #expect(late.allSatisfy { $0.fireAt! > now })
    }

    @Test func theTimeIsChangeable() {
        var s = settings(bills: true)
        s.billHour = 18
        s.billMinute = 30
        let reminders = plan(summary(), s).reminders
        let parts = reminders.map { calendar.dateComponents([.day, .hour, .minute], from: $0.fireAt!) }
        #expect(parts.map(\.day) == [15, 17])
        #expect(parts.allSatisfy { $0.hour == 18 && $0.minute == 30 })
    }

    @Test func noMoreThanFiftyBills() {
        let many = (1...80).map {
            ConnectionSummary.Bill(id: $0, name: "Bill \($0)", accountId: 1, accountName: "Checking",
                                   amount: Money(-1.0), nextDate: day(1 + $0 % 20))
        }
        #expect(plan(summary(bills: many), settings(bills: true)).reminders.count == ReminderPlan.maxBills)
    }

    // MARK: Balance heading under

    @Test func theFirstDipWithinAWeekIsToldOnce() throws {
        let first = plan(summary(), settings(balance: true))
        let warning = try #require(first.reminders.first)
        #expect(first.reminders.count == 1)
        #expect(warning.kind == .balance)
        #expect(warning.title == "Checking is heading low")
        #expect(warning.body == "Forecast to go under your reminder amount on Nov 18 · Home")
        #expect(warning.fireAt == nil)
        #expect(warning.item == 1 && warning.day == day(3))
        // Written again with the same dip: nothing more.
        let again = plan(summary(), settings(balance: true), state: first.state)
        #expect(again.reminders.isEmpty)
        // Back above: forgotten, so the next dip warns again.
        let above = summary(accounts: [account(1, "Checking", balance: 900, lows: [(0, 900), (3, 400)])])
        let recovered = plan(above, settings(balance: true), state: again.state)
        #expect(recovered.reminders.isEmpty && recovered.state.dips.isEmpty)
        #expect(plan(summary(), settings(balance: true), state: recovered.state).reminders.count == 1)
    }

    @Test func oneAccountIsWatchedThePickedOneOrTheFirst() {
        // The first account (Checking) unless another is picked; the credit
        // card, always below, isn't watched unless chosen.
        var s = settings(balance: true)
        #expect(plan(summary(), s).reminders.map(\.item) == [1])
        s.setBalanceAccount(2, for: summary().id)
        #expect(s.balanceAccount(for: summary().id) == 2)
        let card = plan(summary(), s).reminders
        #expect(card.map(\.item) == [2])
        #expect(card.first?.body.contains("today") == true)
        // An account that's gone falls back to the first.
        s.setBalanceAccount(99, for: summary().id)
        #expect(plan(summary(), s).reminders.map(\.item) == [1])
    }

    @Test func theAmountIsTheOnePicked() {
        var s = settings(balance: true)
        s.balanceAmount = Money(30.0)
        #expect(plan(summary(), s).reminders.isEmpty)   // the low is $40
        s.balanceAmount = Money(1000.0)
        #expect(plan(summary(), s).reminders.first?.day == today)   // under from today
    }

    @Test func offForgetsTheDips() {
        let on = plan(summary(), settings(balance: true))
        #expect(!on.state.dips.isEmpty)
        #expect(plan(summary(), settings(), state: on.state).state.dips.isEmpty)
    }

    // MARK: New bank lines

    @Test func moreBankLinesAreToldOnce() throws {
        let s = settings(bank: true)
        // The first count is only noted.
        var result = ReminderPlan.bankLines(2, settings: s, state: ReminderState())
        #expect(result.reminder == nil && result.state.bankLines == 2)
        result = ReminderPlan.bankLines(5, settings: s, state: result.state)
        let reminder = try #require(result.reminder)
        #expect(reminder.title == "New bank lines to match")
        #expect(reminder.body == "3 new lines from your bank wait to be matched.")
        #expect(reminder.id == "net.iptater.walletweather.reminder.bank-lines.phone.all")
        // The same count again, or fewer: nothing.
        result = ReminderPlan.bankLines(5, settings: s, state: result.state)
        #expect(result.reminder == nil)
        result = ReminderPlan.bankLines(1, settings: s, state: result.state)
        #expect(result.reminder == nil)
        #expect(ReminderPlan.bankLines(2, settings: s, state: result.state).reminder?.body
                == "1 new line from your bank waits to be matched.")
        // Off: counted, never told.
        let off = ReminderPlan.bankLines(9, settings: settings(), state: result.state)
        #expect(off.reminder == nil && off.state.bankLines == 9)
    }

    // MARK: No amounts in the text

    @Test func noReminderTextCarriesAnAmount() {
        var s = settings(bills: true, balance: true, bank: true)
        s.balanceAmount = Money(1000.0)
        var all = plan(summary(), s, at: morning).reminders
        all += [ReminderPlan.bankLines(4, settings: s, state: { var st = ReminderState(); st.bankLines = 1; return st }()).reminder!]
        #expect(all.count >= 4)
        for reminder in all {
            let text = reminder.title + " " + reminder.body
            #expect(!text.contains("$"), "\(text)")
            for figure in ["1650", "1,650", "65", "39.99", "900", "40", "1000", "1,000"] {
                #expect(!text.contains(figure), "\(text) has \(figure)")
            }
            #expect(!reminder.userInfo.values.contains { $0.contains("$") || $0.contains(".") && $0.first?.isNumber == true })
        }
    }

    // MARK: The expanded view

    @Test func theExpandedViewShowsTheAmountOnlyWhenAllowed() {
        let home = summary()
        let bill = plan(home, settings(bills: true), at: morning).reminders.first!
        let dip = plan(home, settings(balance: true)).reminders.first!
        let found: (UUID) -> SummaryRead = { _ in .found(home) }
        #expect(ReminderDetail.decide(bill.userInfo, read: found, lockOn: false)
                == .bill(name: "Phone", amount: "-$65.00", due: day(1)))
        #expect(ReminderDetail.decide(dip.userInfo, read: found, lockOn: false)
                == .balance(account: "Checking", low: "$40.00", day: day(3)))
        // The app lock hides them.
        #expect(ReminderDetail.decide(bill.userInfo, read: found, lockOn: true)
                == .bill(name: "Phone", amount: "••••", due: day(1)))
        // A locked phone can't read the summary: hidden, and the name isn't known.
        #expect(ReminderDetail.decide(dip.userInfo, read: { _ in .unreadable }, lockOn: false)
                == .balance(account: "This account", low: "••••", day: day(3)))
        // Signed out since, or set to Nothing: hidden.
        #expect(ReminderDetail.decide(bill.userInfo, read: { _ in .found(.nameOnly(SavedConnection(
            connection: Connection(server: URL(string: "https://x.test")!, token: "t")))) }, lockOn: false)
                == .bill(name: "This bill", amount: "••••", due: day(1)))
        #expect(ReminderDetail.decide(["kind": "bank-lines"], read: found, lockOn: false) == .none)
    }

    // MARK: Kept

    @Test func settingsAndStateAreKept() throws {
        let suite = "ww-reminders-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ReminderSettings.load(from: defaults) == ReminderSettings())
        var s = settings(bills: true)
        s.billHour = 7
        s.setBalanceAccount(3, for: summary().id)
        s.save(to: defaults)
        #expect(ReminderSettings.load(from: defaults) == s)
        #expect(defaults.data(forKey: "reminders.settings") != nil)
        var state = ReminderState()
        state.bankLines = 4
        state.save(to: defaults)
        #expect(ReminderState.load(from: defaults) == state)
    }

    // MARK: The summary's week

    @Test func theSummaryKeepsEachDaysLowForAWeek() async throws {
        let demo = APIClient(connection: Demo.connection)
        let saved = SavedConnection(connection: Connection(server: URL(string: "https://x.test")!, token: "t"), keep: .lastKnown)
        let november = LocalDay(year: 2026, month: 11, day: 27)   // the week crosses into December
        let summary = try await ConnectionSummary.fetch(saved, client: demo, readOnly: false, today: november)
        for account in summary.accounts {
            let lows = try #require(account.weekLows)
            #expect(lows.first == .init(date: november, low: account.balance))
            #expect(lows.allSatisfy { $0.date >= november && $0.date <= november.adding(days: 7) })
            #expect(lows.map(\.date) == lows.map(\.date).sorted())
        }
        // The lowest of a day's lines, and lines outside the week left out.
        func line(_ day: LocalDay, _ balance: Double) throws -> ForecastLine {
            let json = """
            {"forecast_date":"\(day)","actual_date":"\(day)","description":"x","forecast_balance":\(balance),
             "actual_balance":\(balance),"diff_balance":0,"is_actual_real":false}
            """
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ForecastLine.self, from: Data(json.utf8))
        }
        let lows = ConnectionSummary.lows([try line(day(-1), 1), try line(day(2), 500), try line(day(2), 300),
                                           try line(day(8), 5)], balance: Money(800.0), today: today)
        #expect(lows == [.init(date: today, low: Money(800.0)), .init(date: day(2), low: Money(300.0))])
    }
}
