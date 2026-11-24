import Foundation
import Testing
@testable import WalletWeatherKit

/// Add a transaction and Mark a bill paid (Plans/outside-the-app.md, phase 5,
/// #332): the Add transaction sheet filled in from the Shortcut; Mark a bill
/// paid against the household on this iPhone and against a server's answers;
/// and its refusals (no connection or only the demo, a locked phone, Nothing,
/// a bill not on the connection in front, an account this sign-in can't
/// change, the app lock before and after Face ID).
extension StubServerSuites {
    @Suite struct ShortcutActionTests {
        // A Tuesday, with Rent due on the 20th and the phone bill on the 5th.
        let today = LocalDay(year: 2026, month: 11, day: 10)
        let household: LocalServer
        let client: APIClient

        init() throws {
            household = try LocalServer.inMemory()
            client = APIClient(connection: household.connection)
        }

        /// Checking with Rent on the 20th; its id and the bill's.
        func setUp() async throws -> (account: Int, rent: Int) {
            let account = try await client.createAccount(AccountBody(name: "Checking", startingBalance: 3000,
                                                                     startingDate: LocalDay(year: 2026, month: 1, day: 1))).id
            var draft = BillDraft(today: LocalDay(year: 2026, month: 1, day: 1))
            draft.name = "Rent"
            draft.amountText = "1500"
            draft.kind = .spending
            draft.dayOfMonth = 20
            try await client.addRecurring(draft, account: account)
            let rent = try #require(try await client.recurring(today: today).items.first { $0.description == "Rent" })
            return (account, rent.id)
        }

        func summary(keepsNumbers: Bool = true, canChange: Bool = true, id: UUID) -> ConnectionSummary {
            ConnectionSummary(id: id, name: "Home", kind: .server, madeAt: .now, keepsNumbers: keepsNumbers,
                              accounts: [.init(id: 1, name: "Checking", balance: Money(10.0), monthLow: Money(5.0),
                                               monthLowDate: nil, toConfirm: canChange ? 0 : nil)],
                              bills: [.init(id: 7, name: "Rent", accountId: 1, accountName: "Checking",
                                            amount: Money(-1500.0), nextDate: today)])
        }

        // MARK: Add a transaction

        @Test func addATransactionFillsInTheSheet() {
            let draft = NewTransactionDraft.fromShortcut(amount: Decimal(string: "12.5")!, name: "  Coffee  ", date: today)
            #expect(draft.kind == .spending)
            #expect(draft.name == "Coffee")
            #expect(draft.amount == Decimal(string: "12.5"))
            #expect(draft.date == today)
            #expect(draft.paid)
            #expect(draft.problem == nil)
            // A negative amount is still spending (the sheet can change it); none leaves the field empty.
            #expect(NewTransactionDraft.fromShortcut(amount: -20, name: "Gas", date: today).amount == 20)
            #expect(NewTransactionDraft.fromShortcut(amount: 0, name: "Gas", date: today).amountText.isEmpty)
            #expect(NewTransactionDraft.fromShortcut(amount: 1, name: String(repeating: "a", count: 900), date: today)
                .name.count == LineDraft.nameMax)
        }

        // MARK: Mark a bill paid, on the household on this iPhone

        @Test func marksTheNextDatePaidOnTheHousehold() async throws {
            let (account, rent) = try await setUp()
            let paid = try #require(try await BillPaying.pay(bill: rent, account: account, client: client, today: today))
            #expect(paid.name == "Rent")
            #expect(paid.amount == Money(1500.0))
            #expect(paid.planned == LocalDay(year: 2026, month: 11, day: 20))
            // Paid early: dated today, as a swipe does.
            #expect(paid.paidOn == today)
            let rows = try await client.forecast(account: account, month: YearMonth(today), today: today).rows
            let line = try #require(rows.first { $0.recurringId == rent })
            #expect(line.isPaid)
            #expect(BillPaying.said(paid, bill: "Rent", connection: "On this iPhone")
                == "Rent is marked paid on \(today.short), $1,500.00, on On this iPhone.")
        }

        @Test func withThisMonthPaidNextMonthsDateIsNext() async throws {
            let (account, rent) = try await setUp()
            _ = try await BillPaying.pay(bill: rent, account: account, client: client, today: today)
            let second = try #require(try await BillPaying.pay(bill: rent, account: account, client: client, today: today))
            #expect(second.planned == LocalDay(year: 2026, month: 12, day: 20))
        }

        @Test func aBillWithNoDateLeftSaysSo() async throws {
            let (account, _) = try await setUp()
            #expect(try await BillPaying.pay(bill: 999, account: account, client: client, today: today) == nil)
            #expect(BillPaying.said(nil, bill: "Rent", connection: "Home") == "Rent has no date left to pay this month or next.")
        }

        // MARK: Mark a bill paid, on a server

        @Test func marksTheNextDatePaidOnAServer() async throws {
            let (account, rent) = try await setUp()
            // The server answers this month's forecast as the household would.
            let month = YearMonth(today)
            let (status, forecast) = household.answer(method: "GET", path: "/api/accounts/\(account)/forecast",
                                                      query: ["start": month.start.description, "end": month.end.description,
                                                              "today": today.description], body: nil)
            #expect(status == 200)
            StubServer.answer([(200, forecast), (200, Data("{}".utf8))])
            let server = APIClient(connection: Connection(server: URL(string: "https://money.example.test")!, token: "ww_t"),
                                   session: StubServer.session())
            let paid = try #require(try await BillPaying.pay(bill: rent, account: account, client: server, today: today))
            #expect(paid.planned == LocalDay(year: 2026, month: 11, day: 20))
            let post = try #require(StubServer.lastRequest)
            #expect(post.httpMethod == "POST")
            #expect(post.url?.path() == "/api/accounts/\(account)/transactions")
            let body = try #require(try JSONSerialization.jsonObject(with: StubServer.lastBody ?? Data()) as? [String: Any])
            #expect(body["recurring_id"] as? Int == rent)
            #expect(body["is_actual"] as? Bool == true)
            #expect(body["actual_date"] as? String == today.description)
        }

        @Test func aServersRefusalComesBack() async throws {
            let (account, rent) = try await setUp()
            let month = YearMonth(today)
            let (_, forecast) = household.answer(method: "GET", path: "/api/accounts/\(account)/forecast",
                                                 query: ["start": month.start.description, "end": month.end.description,
                                                         "today": today.description], body: nil)
            StubServer.answer([(200, forecast), (403, Data(#"{"detail":"Read-only token"}"#.utf8))])
            let server = APIClient(connection: Connection(server: URL(string: "https://money.example.test")!, token: "ww_t"),
                                   session: StubServer.session())
            await #expect(throws: APIError.self) {
                _ = try await BillPaying.pay(bill: rent, account: account, client: server, today: today)
            }
        }

        // MARK: The refusals

        @Test func goesAheadOnTheConnectionInFront() {
            let front = UUID()
            let found = summary(id: front)
            let check = MarkPaidCheck.decide(front: front, read: .found(found), link: .bill(front, 7), lockOn: false, unlocked: false)
            #expect(check == .ready(found.bills[0], connection: found))
            #expect(check.refusal == nil)
        }

        @Test func theDemoOrNoConnectionIsRefused() {
            // Only the demo used: no saved connection in front.
            let check = MarkPaidCheck.decide(front: nil, read: .found(summary(id: UUID())), link: .bill(UUID(), 7),
                                             lockOn: false, unlocked: false)
            #expect(check == .noConnection)
            #expect(check.refusal?.contains("demo") == true)
        }

        @Test func aLockedPhoneIsRefused() {
            let front = UUID()
            let check = MarkPaidCheck.decide(front: front, read: .unreadable, link: .bill(front, 7), lockOn: false, unlocked: false)
            #expect(check == .phoneLocked)
            #expect(MarkPaidCheck.decide(front: front, read: .missing, link: .bill(front, 7), lockOn: false, unlocked: false)
                == .notLoaded)
        }

        @Test func nothingIsRefused() {
            let front = UUID()
            let check = MarkPaidCheck.decide(front: front, read: .found(summary(keepsNumbers: false, id: front)),
                                             link: .bill(front, 7), lockOn: true, unlocked: true)
            #expect(check == .keepsNothing(name: "Home"))
            #expect(check.refusal?.contains("keeps no numbers") == true)
        }

        @Test func aBillNotOnTheConnectionInFrontIsRefused() {
            let front = UUID()
            let found = summary(id: front)
            #expect(MarkPaidCheck.decide(front: front, read: .found(found), link: .bill(UUID(), 7), lockOn: false, unlocked: false)
                == .notHere(name: "Home"))
            #expect(MarkPaidCheck.decide(front: front, read: .found(found), link: .bill(front, 8), lockOn: false, unlocked: false)
                == .notHere(name: "Home"))
            #expect(MarkPaidCheck.decide(front: front, read: .found(found), link: .account(front, 1), lockOn: false, unlocked: false)
                == .notHere(name: "Home"))
        }

        @Test func anAccountThisSignInCantChangeIsRefused() {
            let front = UUID()
            let check = MarkPaidCheck.decide(front: front, read: .found(summary(canChange: false, id: front)),
                                             link: .bill(front, 7), lockOn: false, unlocked: false)
            #expect(check == .cannotChange(account: "Checking"))
        }

        @Test func theAppLockAsksForFaceIDFirst() {
            let front = UUID()
            let found = summary(id: front)
            let locked = MarkPaidCheck.decide(front: front, read: .found(found), link: .bill(front, 7), lockOn: true, unlocked: false)
            #expect(locked == .appLocked)
            #expect(locked.refusal?.contains("$") == false)
            #expect(MarkPaidCheck.decide(front: front, read: .found(found), link: .bill(front, 7), lockOn: true, unlocked: true)
                == .ready(found.bills[0], connection: found))
        }
    }
}
