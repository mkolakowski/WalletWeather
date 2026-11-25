import Foundation
import Testing
@testable import WalletWeatherKit

/// The sort button (#350), on the Forecast and Bills samples seen on Nov 15, 2026.
struct ListSortTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func confirm() throws -> [ForecastLine] {
        try (DecodingTests().sample("forecast") as ForecastMonth).toConfirm(today: today)
    }

    func bills() throws -> [RecurringItem] {
        try (DecodingTests().sample("recurring") as RecurringList).items
    }

    @Test func storedAndRead() {
        for choice in ListSort.choices { #expect(ListSort(rawValue: choice.rawValue) == choice) }
        #expect(ListSort.choices.count == 6)
        #expect(ListSort.stored("", default: .billsDefault) == .billsDefault)
        #expect(ListSort.stored("colour.up", default: .toConfirmDefault) == .toConfirmDefault)
        #expect(ListSort.stored("amount.down", default: .billsDefault) == ListSort(.amount, ascending: false))
    }

    /// Each list's default is the order it had before the button.
    @Test func defaultsKeepTodaysOrder() throws {
        let lines = try confirm()
        #expect(ListSort.toConfirmDefault.apply(to: lines).map(\.id) == lines.map(\.id))
        let items = try bills()
        #expect(ListSort.billsDefault.apply(to: items).map(\.id) == items.map(\.id))
    }

    @Test func toConfirmByEachKey() throws {
        let lines = try confirm()
        #expect(ListSort(.date, ascending: false).apply(to: lines).map(\.description)
                == ["Streaming service", "Electric", "Paycheck", "Gym", "Rent"])
        // By size, income and bills alike.
        #expect(ListSort(.amount, ascending: false).apply(to: lines).map(\.description)
                == ["Paycheck", "Rent", "Electric", "Gym", "Streaming service"])
        #expect(ListSort(.amount, ascending: true).apply(to: lines).first?.description == "Streaming service")
        #expect(ListSort(.name, ascending: true).apply(to: lines).map(\.description)
                == ["Electric", "Gym", "Paycheck", "Rent", "Streaming service"])
        #expect(ListSort(.name, ascending: false).apply(to: lines).first?.description == "Streaming service")
    }

    @Test func billsByNextDate() throws {
        let items = try bills()
        #expect(ListSort(.date, ascending: true).apply(to: items).map(\.description)
                == ["Streaming service", "Internet", "Phone bill", "Paycheck", "Rent", "Gym", "Electric"])
        #expect(ListSort(.date, ascending: false).apply(to: items).first?.description == "Electric")
    }

    /// A missing date goes last whichever way round; equal keys fall back to the name.
    @Test func missingDatesAndTies() {
        struct Row { let name: String; let day: LocalDay?; let amount: Decimal }
        let d = LocalDay(year: 2026, month: 11, day: 1)
        let rows = [Row(name: "b", day: nil, amount: 5), Row(name: "c", day: d, amount: 5), Row(name: "a", day: d, amount: 5)]
        for ascending in [true, false] {
            let sorted = ListSort(.date, ascending: ascending).apply(to: rows, date: \.day, amount: \.amount, name: \.name)
            #expect(sorted.map(\.name) == ["a", "c", "b"])
        }
        #expect(ListSort(.amount, ascending: false).apply(to: rows, date: \.day, amount: \.amount, name: \.name).map(\.name)
                == ["a", "b", "c"])
    }

    @Test func titles() {
        #expect(ListSort(.date, ascending: true).title(future: false) == "Oldest first")
        #expect(ListSort(.date, ascending: true).title(future: true) == "Soonest first")
        #expect(ListSort(.amount, ascending: false).title(future: true) == "Largest first")
        #expect(ListSort(.name, ascending: true).spoken(future: true) == "Name, a to z")
        #expect(ListSort(.date, ascending: false).spoken(future: false) == "Date, newest first")
    }
}
