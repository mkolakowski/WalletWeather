import Foundation
import Testing
@testable import WalletWeatherKit

/// Drag and drop (#308): which lines can be dragged onto a Calendar day, the
/// draft a drop saves, and which dropped items are a CSV to import.
struct DragAndDropTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)
    let forecast = ForecastTests()

    func event(paid: Bool = false, recurringId: Int? = nil, transferId: Int? = nil, transactionId: Int? = 77) -> CalendarEvent {
        CalendarEvent(date: LocalDay(year: 2026, month: 11, day: 20), accountId: 3, accountName: "Checking",
                      description: "Haircut", amount: Money(Decimal(-40)), categoryName: nil, categoryColor: nil,
                      recurringId: recurringId, transactionId: transactionId, transferId: transferId,
                      isActualReal: paid, notes: nil)
    }

    // MARK: Which lines drag

    @Test func onlyAnEditableAccountOutsideTheLockedDemoDrags() {
        #expect(LineDrag.allowed(canEdit: true, lockedInDemo: false))
        #expect(!LineDrag.allowed(canEdit: false, lockedInDemo: false), "read-only, or an account shared to view")
        #expect(!LineDrag.allowed(canEdit: true, lockedInDemo: true), "the lock has the demo in front")
    }

    @Test func aForecastOneOffNotYetPaidDrags() throws {
        let drag = try #require(LineDrag(line: forecast.oneOff(), accountId: 3, canChange: true))
        #expect(drag == LineDrag(accountId: 3, transactionId: 77, name: "Haircut", plannedOn: LocalDay("2026-11-20")!))
    }

    @Test func otherForecastLinesDoNotDrag() throws {
        #expect(LineDrag(line: forecast.oneOff(), accountId: 3, canChange: false) == nil, "not allowed here")
        #expect(LineDrag(line: forecast.oneOff(paid: true), accountId: 3, canChange: true) == nil, "paid")
        #expect(LineDrag(line: forecast.oneOff(recurringId: 2), accountId: 3, canChange: true) == nil, "a bill's date")
        #expect(LineDrag(line: forecast.oneOff(transferId: 9), accountId: 3, canChange: true) == nil, "a transfer")
        #expect(LineDrag(line: forecast.oneOff(transactionId: nil), accountId: 3, canChange: true) == nil)
        let month = try forecast.sample("forecast", as: ForecastMonth.self)
        #expect(LineDrag(line: try forecast.line(month, "Rent"), accountId: 1, canChange: true) == nil, "a projected bill")
    }

    @Test func calendarLinesFollowTheSameRule() throws {
        let drag = try #require(LineDrag(event: event(), canChange: true))
        #expect(drag == LineDrag(accountId: 3, transactionId: 77, name: "Haircut", plannedOn: LocalDay("2026-11-20")!))
        #expect(LineDrag(event: event(), canChange: false) == nil)
        #expect(LineDrag(event: event(paid: true), canChange: true) == nil)
        #expect(LineDrag(event: event(recurringId: 2), canChange: true) == nil)
        #expect(LineDrag(event: event(transferId: 9), canChange: true) == nil)
        #expect(LineDrag(event: event(transactionId: nil), canChange: true) == nil)
    }

    @Test func aDragTravelsAsJSONAndFindsItsLineAgain() throws {
        let month = try forecast.sample("forecast", as: ForecastMonth.self)
        let store = try forecast.line(month, "Department store")
        let drag = LineDrag(accountId: 1, transactionId: try #require(store.transactionId), name: store.description,
                            plannedOn: try #require(store.plannedDate))
        let data = try JSONEncoder().encode(drag)
        #expect(try JSONDecoder().decode(LineDrag.self, from: data) == drag)
        #expect(drag.line(in: month) == store)
        #expect(drag.month == YearMonth(store.plannedDate!))
        #expect(LineDrag(accountId: 1, transactionId: 999_999, name: "Gone", plannedOn: today).line(in: month) == nil)
        #expect(LineDrag.typeIdentifier == "net.iptater.walletweather.line")
    }

    // MARK: The date a drop produces

    @Test func aDropMovesOnlyThePlannedDate() throws {
        let line = forecast.oneOff()
        let day = LocalDay(year: 2026, month: 11, day: 25)
        let draft = try #require(LineDraft.moved(line, to: day, today: today))
        var expected = LineDraft(line, today: today)
        expected.plannedOn = day
        expected.paidOn = today
        #expect(draft == expected)
        let body = try forecast.json(TransactionBody(line: line, draft: draft))
        #expect(body["forecast_date"] == AnyHashable("2026-11-25"))
        #expect(body["description"] == AnyHashable("Haircut"))
        #expect(body["is_actual"] == AnyHashable(false))
    }

    @Test func aDropOnAnEarlierDayKeepsTheActualDateWithIt() throws {
        let day = LocalDay(year: 2026, month: 11, day: 3)
        let draft = try #require(LineDraft.moved(forecast.oneOff(), to: day, today: today))
        #expect(draft.plannedOn == day && draft.paidOn == day)
    }

    @Test func aDropNeverMovesALineWhoseDateIsNotItsOwn() {
        let day = LocalDay(year: 2026, month: 11, day: 25)
        #expect(LineDraft.moved(forecast.oneOff(paid: true), to: day, today: today) == nil)
        #expect(LineDraft.moved(forecast.oneOff(recurringId: 2), to: day, today: today) == nil)
        #expect(LineDraft.moved(forecast.oneOff(transferId: 9), to: day, today: today) == nil)
    }

    @Test func theSameDayIsNoMoveAndUndoGoesBack() {
        let drag = LineDrag(accountId: 3, transactionId: 77, name: "Haircut", plannedOn: LocalDay("2026-11-20")!)
        #expect(!drag.moves(to: LocalDay("2026-11-20")!))
        #expect(drag.moves(to: LocalDay("2026-11-21")!))
        let moved = drag.moved(to: LocalDay("2026-12-02")!)
        #expect(moved.plannedOn == LocalDay("2026-12-02")! && moved.month == YearMonth(year: 2026, month: 12))
        #expect(moved.transactionId == 77 && moved.accountId == 3)
    }

    // MARK: A dropped CSV

    @Test func aCSVIsReadAsCSV() {
        #expect(CSVDrop.typeToRead(["public.comma-separated-values-text"], name: "bank.csv") == CSVDrop.csvType)
        #expect(CSVDrop.typeToRead(["public.file-url", "public.comma-separated-values-text"], name: nil) == CSVDrop.csvType)
    }

    @Test func aFileNamedCSVIsReadAsItsTextOrBytes() {
        #expect(CSVDrop.typeToRead(["public.data", "public.plain-text"], name: "Export.CSV") == "public.plain-text")
        #expect(CSVDrop.typeToRead(["public.data"], name: "export.csv") == "public.data")
    }

    @Test func anythingElseIsRefused() {
        #expect(CSVDrop.typeToRead(["public.png"], name: "photo.png") == nil)
        #expect(CSVDrop.typeToRead(["public.plain-text"], name: "note.txt") == nil)
        #expect(CSVDrop.typeToRead(["public.plain-text"], name: nil) == nil)
        #expect(CSVDrop.typeToRead([LineDrag.typeIdentifier, "public.data"], name: "Haircut.csv") == nil, "a dragged line")
        #expect(CSVDrop.typeToRead(["public.png"], name: "odd.csv") == nil, "a .csv with nothing readable")
        #expect(!CSVDrop.accepts([]))
        #expect(!CSVDrop.accepts([(["public.png"], "photo.png")]))
        #expect(CSVDrop.accepts([(["public.png"], "photo.png"), (["public.comma-separated-values-text"], "bank.csv")]))
    }

    @Test func theSheetShowsTheFilesName() {
        #expect(CSVDrop.fileName("bank.csv") == "bank.csv")
        #expect(CSVDrop.fileName("Checking export") == "Checking export.csv")
        #expect(CSVDrop.fileName(nil) == "Dropped file.csv")
        #expect(CSVDrop.fileName("  ") == "Dropped file.csv")
    }

    // MARK: Debug pictures

    @Test func theDebugSettingPicksADay() {
        let november = YearMonth(year: 2026, month: 11)
        #expect(DropDebug.highlightedDay("day", month: november, today: today) == LocalDay("2026-11-16"))
        #expect(DropDebug.highlightedDay("day", month: november, today: LocalDay("2026-11-30")!) == LocalDay("2026-11-15"))
        #expect(DropDebug.highlightedDay("2026-11-04", month: november, today: today) == LocalDay("2026-11-04"))
        #expect(DropDebug.highlightedDay("2026-12-04", month: november, today: today) == nil)
        #expect(DropDebug.highlightedDay("csv", month: november, today: today) == nil)
        #expect(DropDebug.highlightedDay(nil, month: november, today: today) == nil)
    }
}
