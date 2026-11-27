import Foundation

// The Duo's big screen (Plans/ios-app.md, phase 4, #90): what Compare and
// the "To confirm" switch work out, with no screen.

// MARK: - To confirm

extension ForecastMonth {
    /// The lines still to confirm on `today`: not paid, planned for today or
    /// earlier, oldest first. What you tick off with your bank's app open
    /// beside WalletWeather.
    public func toConfirm(today: LocalDay) -> [ForecastLine] {
        rows.filter { !$0.isPaid && ($0.plannedDate.map { $0 <= today } ?? false) }
            .sorted { ($0.plannedDate ?? today) < ($1.plannedDate ?? today) }
    }
}

extension LineDraft {
    /// Paid at a different amount (typed without a sign; the line keeps its
    /// own), on the day a swipe would use.
    public static func paid(_ line: ForecastLine, amountText: String, today: LocalDay) -> LineDraft {
        var draft = LineDraft.paidAsPlanned(line, today: today)
        draft.amountText = amountText.trimmingCharacters(in: .whitespaces)
        return draft
    }

    /// A To confirm row's Paid as planned (no amount) or Paid (the amount
    /// typed), on the day picked on the row's chip (#349). A day still to
    /// come is taken as today: nothing is paid in the future.
    public static func confirmed(_ line: ForecastLine, amountText: String?, on day: LocalDay, today: LocalDay) -> LineDraft {
        var draft = amountText.map { paid(line, amountText: $0, today: today) } ?? paidAsPlanned(line, today: today)
        draft.paidOn = min(day, today)
        return draft
    }
}

// MARK: - Compare

/// One row of Compare: a day of the month, with each side's lines that day.
/// Two months line up by day of the month (the 5th beside the 5th), so the
/// two sides scroll together.
public struct CompareDay: Sendable, Equatable, Identifiable {
    public let day: Int
    public let left: [ForecastLine]
    public let right: [ForecastLine]
    public var id: Int { day }

    public func lines(on side: CompareSide) -> [ForecastLine] { side == .left ? left : right }
}

/// One side of Compare.
public enum CompareSide: String, Sendable, CaseIterable {
    case left, right
}

public enum Compare {
    /// Under this width (points) two columns are too narrow to read, so
    /// Compare shows one side at a time with a switch (#359). The closed
    /// Duo, an iPhone and a narrow window are under it; the open Duo is not.
    public static let narrowWidth: Double = 600

    public static func isNarrow(width: Double) -> Bool { width < narrowWidth }

    /// The days that have a line on one side only, in order: what that side
    /// shows when it has the whole width to itself.
    public static func days(of side: CompareSide, left: [ForecastLine], right: [ForecastLine]) -> [CompareDay] {
        days(left: left, right: right).filter { !($0.lines(on: side)).isEmpty }
    }

    /// Each day of the month that has a line on either side, in order.
    public static func days(left: [ForecastLine], right: [ForecastLine]) -> [CompareDay] {
        func byDay(_ lines: [ForecastLine]) -> [Int: [ForecastLine]] {
            Dictionary(grouping: lines.filter { $0.plannedDate != nil }) { $0.plannedDate!.day }
        }
        let l = byDay(left), r = byDay(right)
        return Set(l.keys).union(r.keys).sorted().map { CompareDay(day: $0, left: l[$0] ?? [], right: r[$0] ?? []) }
    }

    /// The balance after the last line on or before `day` on one side (what
    /// the Forecast shows as Balance), or the month's opening balance before
    /// its first line.
    public static func balance(through day: Int, in month: ForecastMonth) -> Money {
        month.rows.last { ($0.plannedDate?.day ?? 0) <= day }?.actualBalance ?? month.openingBalance
    }
}

extension YearMonth {
    /// The `day`th of this month, or nil past its end (a 31st in November).
    public func day(_ day: Int) -> LocalDay? {
        day >= 1 && day <= end.day ? LocalDay(year: year, month: month, day: day) : nil
    }
}
