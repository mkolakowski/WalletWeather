import Foundation

// The demo's Unmatched list (duo-more phase 3, #306): two sample bank lines on
// the Credit Card account (the one the sample status says has two waiting),
// one of them close to the Phone bill. The shapes are the server's
// (`GET /api/accounts/{id}/bank-unmatched` and `.../{line}/candidates`, the
// recorded samples of `Tests/.../Samples/bank-unmatched*.json`); the dates
// are made from today. Match and Leave are POSTs, which the demo refuses
// (`Demo.allows`): "The demo doesn't save changes."

extension Demo {
    /// `Demo/unmatched.json`: the account, its lines (with how many days
    /// ago each came) and the bills a line could pay.
    private static func unmatchedSamples() -> [String: Any] { object("unmatched") as? [String: Any] ?? [:] }

    private static func unmatchedLines(account: Int, today: LocalDay) -> [[String: Any]] {
        let samples = unmatchedSamples()
        guard samples["account_id"] as? Int == account else { return [] }
        return (samples["lines"] as? [[String: Any]] ?? []).map { line in
            var line = line
            line["date"] = today.adding(days: -(line["days_ago"] as? Int ?? 0)).description
            line.removeValue(forKey: "days_ago")
            return line
        }
    }

    /// `GET /api/accounts/{id}/bank-unmatched`: newest first; an account
    /// with none waiting answers an empty list.
    static func bankUnmatched(account: Int, today: LocalDay) -> Data {
        let lines = unmatchedLines(account: account, today: today).map { line in
            line.filter { ["id", "date", "description", "amount", "notes", "source"].contains($0.key) }
                .merging(["notes": line["notes"] ?? NSNull()]) { _, new in new }
        }
        return json(["count": lines.count, "lines": lines])
    }

    /// `GET .../bank-unmatched/{line}/candidates`: each bill once, at its
    /// nearest date, the way the line's amount and day compare. Nil for a
    /// line that isn't on the list.
    static func bankCandidates(account: Int, line id: Int, today: LocalDay) -> Data? {
        guard let line = unmatchedLines(account: account, today: today).first(where: { $0["id"] as? Int == id }),
              let day = (line["date"] as? String).flatMap(LocalDay.init),
              let amount = line["amount"] as? Double else { return nil }
        let bills = unmatchedSamples()["bills"] as? [[String: Any]] ?? []
        var choices: [[String: Any]] = bills.compactMap { bill in
            guard let dom = bill["day_of_month"] as? Int, let planned = bill["amount"] as? Double else { return nil }
            let date = nearest(dayOfMonth: dom, to: day)
            let after = day.days(since: date)
            let sameWay = (amount < 0) == (planned < 0)
            return [
                "transaction_id": NSNull(), "recurring_id": bill["recurring_id"] ?? NSNull(),
                "forecast_date": date.description, "amount": planned, "description": bill["description"] ?? "",
                "days_apart": abs(after), "days_after": after,
                "amount_diff": ((amount - planned) * 100).rounded() / 100,
                "same_direction": sameWay, "within_days": abs(after) <= (bill["match_days"] as? Int ?? 5),
            ]
        }
        choices.sort { ($0["days_apart"] as? Int ?? 0) < ($1["days_apart"] as? Int ?? 0) }
        return json([
            "line": [
                "id": id, "date": day.description, "description": line["description"] ?? "", "amount": amount,
                "source": line["source"] ?? "bank", "bank_text": line["bank_text"] ?? NSNull(),
                "learn_name": line["description"] ?? "",
            ],
            "choices": choices,
        ])
    }

    /// The date of a monthly bill (the `dayOfMonth`th, held to the month's
    /// end) nearest to `day`, looking at the month before, this one and the next.
    private static func nearest(dayOfMonth: Int, to day: LocalDay) -> LocalDay {
        let month = YearMonth(day)
        let dates = [month.previous, month, month.next].map { m in
            LocalDay(year: m.year, month: m.month, day: min(dayOfMonth, m.end.day))
        }
        return dates.min { abs(day.days(since: $0)) < abs(day.days(since: $1)) } ?? dates[1]
    }
}
