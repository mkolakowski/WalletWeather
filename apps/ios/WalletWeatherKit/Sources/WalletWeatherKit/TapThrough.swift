import Foundation

// Tap through (duo-more phase 2, #305): what the Dashboard's chosen account
// and the Calendar's tapped line work out off screen.

// MARK: - Coming up

extension ForecastMonth {
    /// The next lines still to be paid on an account: not paid, planned for
    /// `today` or later, earliest first, at most `limit`. `following` is the
    /// next month's forecast, read when this month has fewer than `limit`
    /// left, so the list runs across a month's end. Lines on the same day
    /// keep the order the forecast gives them.
    public func comingUp(today: LocalDay, following: ForecastMonth? = nil, limit: Int = 5) -> [ForecastLine] {
        func unpaid(_ month: ForecastMonth) -> [ForecastLine] {
            let due = month.rows.enumerated().filter { _, line in
                !line.isPaid && (line.plannedDate.map { $0 >= today } ?? false)
            }
            return due.sorted { l, r in
                let (a, b) = (l.element.plannedDate ?? today, r.element.plannedDate ?? today)
                return a == b ? l.offset < r.offset : a < b
            }.map(\.element)
        }
        let here = unpaid(self)
        let all = here.count >= limit ? here : here + (following.map(unpaid) ?? [])
        return Array(all.prefix(max(limit, 0)))
    }
}

// MARK: - A Calendar line, as a Forecast line

extension ForecastMonth {
    /// The Forecast line a Calendar line is: by its transaction when it has
    /// one (a saved line, a paid one, either side of a transfer), else, for a
    /// repeating bill or paycheck with nothing saved for that date yet, by
    /// the bill and the planned date. Nil when this month doesn't hold it.
    public func line(for event: CalendarEvent) -> ForecastLine? {
        if let transactionId = event.transactionId {
            return rows.first { $0.transactionId == transactionId }
        }
        guard let recurringId = event.recurringId else { return nil }
        return rows.first { $0.recurringId == recurringId && $0.plannedDate == event.date && $0.transferId == nil }
    }
}

extension CalendarEvent {
    /// The months of the account's Forecast to look in, best first: the
    /// month the Calendar shows the line in, then the ones either side, for
    /// a line paid in a different month from the one it was planned in.
    public var forecastMonths: [YearMonth] {
        let own = YearMonth(date)
        return [own, own.previous, own.next]
    }
}

extension APIClient {
    /// A Calendar line as the Forecast line the editor takes: reads the
    /// account's Forecast for the line's month (and its neighbours, only if
    /// it isn't there) and finds it. Nil when it isn't in any of them.
    public func forecastLine(for event: CalendarEvent) async throws(APIError) -> ForecastLine? {
        for month in event.forecastMonths {
            let forecast = try await forecast(account: event.accountId, month: month)
            if let line = forecast.line(for: event) { return line }
        }
        return nil
    }
}
