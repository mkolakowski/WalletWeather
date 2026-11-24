import Foundation
import Testing
@testable import WalletWeatherKit

/// Open To confirm and What's my balance (Plans/outside-the-app.md, phase 3,
/// #320): where Open To confirm lands, and What's my balance's answer for
/// each case — unlocked, the app lock on (before and after Face ID), a server
/// set to Nothing, the demo (no saved connection), a locked phone and a
/// summary not written yet. Built from summaries in memory: never the app
/// group.
struct ShortcutAnswerTests {
    static let made = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let front = UUID()
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func summary(name: String = "Home", keepsNumbers: Bool = true,
                 accounts: [ConnectionSummary.Account]? = nil) -> ConnectionSummary {
        let accounts = accounts ?? [
            .init(id: 1, name: "Checking", balance: Money(1234.56), monthLow: Money(400.0), monthLowDate: nil, toConfirm: 1),
            .init(id: 2, name: "Savings", balance: Money(5000.0), monthLow: Money(5000.0), monthLowDate: nil, toConfirm: 3),
            .init(id: 3, name: "Joint", balance: Money(-20.5), monthLow: Money(-20.5), monthLowDate: nil, toConfirm: nil),
        ]
        return ConnectionSummary(id: front, name: name, kind: .server, madeAt: Self.made, keepsNumbers: keepsNumbers,
                                 accounts: accounts, bills: [])
    }

    func answer(_ read: SummaryRead, front: UUID?? = .none, lockOn: Bool = false, unlocked: Bool = false) -> BalanceAnswer {
        BalanceAnswer.decide(front: front ?? self.front, read: read, lockOn: lockOn, unlocked: unlocked)
    }

    /// No amount, nor any digit that could be one.
    func holdsNoNumber(_ text: String) -> Bool {
        !text.contains("$") && !text.contains(where: \.isNumber)
    }

    // MARK: What's my balance

    @Test func unlockedTellsEachBalanceWithTheNameAndWhen() {
        let found = summary()
        let result = answer(.found(found))
        #expect(result == .balances(found))
        let text = result.text(now: Self.made.addingTimeInterval(2 * 3600 + 60), calendar: calendar)
        #expect(text == "In Home, as of 2 hours ago: Checking has $1,234.56, Savings has $5,000.00 and Joint has -$20.50.")
    }

    @Test func oneAccountReadsPlainly() {
        let one = summary(accounts: [.init(id: 1, name: "Checking", balance: Money(80.0), monthLow: Money(80.0),
                                           monthLowDate: nil, toConfirm: nil)])
        #expect(answer(.found(one)).text(now: Self.made, calendar: calendar) == "In Home, as of just now: Checking has $80.00.")
    }

    @Test func appLockOnAsksFirstAndTellsNoAmount() {
        let result = answer(.found(summary()), lockOn: true)
        #expect(result == .appLocked)
        #expect(holdsNoNumber(result.text()))
        #expect(!result.text().contains("Checking"))
    }

    @Test func appLockOnTellsOnceFaceIDPasses() {
        let found = summary()
        #expect(answer(.found(found), lockOn: true, unlocked: true) == .balances(found))
    }

    @Test func nothingSaysNoNumbersAreKept() {
        let nothing = summary(name: "Work server", keepsNumbers: false)
        // Asked whether or not the lock is on: there's no amount to hide, so
        // no Face ID either.
        for lockOn in [false, true] {
            let result = answer(.found(nothing), lockOn: lockOn)
            #expect(result == .keepsNothing(name: "Work server"))
            #expect(result.text().contains("Work server keeps no numbers on this iPhone"))
            #expect(result.text().contains("Last-known numbers"))
            #expect(holdsNoNumber(result.text()))
        }
    }

    @Test func theDemoHasNothingToTell() {
        // Only the demo used: nothing saved, so no connection in front.
        let result = answer(.missing, front: .some(nil))
        #expect(result == .noConnection)
        #expect(result.text().contains("demo"))
        #expect(holdsNoNumber(result.text()))
        // Even a summary found on the way doesn't answer for the demo.
        #expect(answer(.found(summary()), front: .some(nil)) == .noConnection)
    }

    @Test func aLockedPhoneTellsNothing() {
        let result = answer(.unreadable)
        #expect(result == .phoneLocked)
        #expect(result.text() == "Unlock your iPhone to hear your balance.")
        #expect(answer(.unreadable, lockOn: true) == .phoneLocked)
    }

    @Test func noSummaryYetSaysToOpenTheApp() {
        let result = answer(.missing)
        #expect(result == .notLoaded)
        #expect(holdsNoNumber(result.text()))
    }

    @Test func noAccountsSaysSo() {
        let result = answer(.found(summary(accounts: [])), lockOn: true)
        #expect(result == .noAccounts(name: "Home"))
        #expect(result.text() == "Home has no accounts yet.")
    }

    @Test func whenTheNumbersAreFromReadsAloud() {
        func asOf(_ seconds: TimeInterval) -> String {
            BalanceAnswer.asOf(Self.made, now: Self.made.addingTimeInterval(seconds), calendar: calendar)
        }
        // Self.made is 2026-05-09 at 2:13 AM ET, so 5 hours on is still that day.
        #expect(asOf(30) == "as of just now")
        #expect(asOf(60) == "as of 1 minute ago")
        #expect(asOf(12 * 60) == "as of 12 minutes ago")
        #expect(asOf(3600) == "as of 1 hour ago")
        #expect(asOf(5 * 3600) == "as of 5 hours ago")
        #expect(asOf(24 * 3600) == "as of yesterday")
        #expect(asOf(4 * 24 * 3600).hasPrefix("as of "))
        #expect(asOf(4 * 24 * 3600) != "as of yesterday")
    }

    @Test func joinsWithAnd() {
        #expect(BalanceAnswer.join([]) == "")
        #expect(BalanceAnswer.join(["A"]) == "A")
        #expect(BalanceAnswer.join(["A", "B"]) == "A and B")
        #expect(BalanceAnswer.join(["A", "B", "C"]) == "A, B and C")
    }

    // MARK: Open To confirm

    @Test func openToConfirmLandsOnTheAccountWithTheMostWaiting() {
        let target = ToConfirmTarget.decide(front: front, read: .found(summary()))
        #expect(target == ToConfirmTarget(connection: front, account: 2))
    }

    @Test func openToConfirmWithoutNumbersOpensTheConnection() {
        for read in [SummaryRead.found(summary(keepsNumbers: false)), .unreadable, .missing] {
            #expect(ToConfirmTarget.decide(front: front, read: read) == ToConfirmTarget(connection: front, account: nil))
        }
        #expect(ToConfirmTarget.decide(front: nil, read: .found(summary())) == ToConfirmTarget(connection: nil, account: nil))
    }
}
