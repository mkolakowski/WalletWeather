import Foundation
import SwiftData

// Bank sync's lines in the household on this phone (Plans/standalone.md,
// phase 8, #239): landing the lines SimpleFIN sent, and the Unmatched list
// with Match… and Leave, answered as the server's routes answer them
// (`_bank_sync_locked`, `/api/accounts/{id}/bank-unmatched...` in
// apps/server/app/main.py). Which bill a line pays, the list, its
// candidates and the catch-up after a taught name come from the shared core
// (bankMatch, bankUnmatched, bankCandidates, bankCatchUp), given the rows
// with amounts as decimal strings, as the server gives them.
extension LocalServer {
    /// What a sync landed.
    struct Landed {
        var added = 0, matched = 0, skipped = 0
        /// Lines on the Unmatched list afterwards, in the matched accounts.
        var unmatched = 0
        /// The bank accounts SimpleFIN listed this time.
        var listed: Set<String> = []
    }

    /// The server's MATCH_TEXT_MAX: a taught bill's bank-line name.
    static let matchTextMax = 120

    /// The core's refusals, and the status the server answers each with.
    static let matchStatus: [String: Int] = [
        "That line isn't on the Unmatched list.": 404,
        "Planned line not found": 404,
        "Bill not found": 404,
        "That line is already paid, or is a transfer: pick a planned line.": 409,
        "That date is already paid or was deleted: pick a planned line.": 409,
        "That bill has no date on that day.": 400,
        "Give transaction_id, or recurring_id and forecast_date.": 400,
    ]

    /// An amount as the core's matching takes it: a decimal string.
    static func decimal(_ value: Double) -> String { "\(value)" }

    // MARK: Landing a sync

    /// The server's bank sync, for the lines SimpleFIN sent: for each
    /// matched bank account, a line already here (by its bank ref) is
    /// skipped; a paid line that came by CSV or by hand with the same date,
    /// amount and name is claimed instead of landing a second; one that pays
    /// a planned bill marks its date paid; the rest land as their own lines,
    /// on the Unmatched list.
    func landBankLines(_ set: SimpleFIN.AccountSet, links: [PhoneBankState.Link], now: Date = .now) throws -> Landed {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var landed = Landed()
        let byID = Dictionary(set.accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let visible = Set(try accounts(context).map(\.id))
        var step = 0.0
        func next() -> Date { step += 1; return now.addingTimeInterval(step / 1_000_000) }
        func key(_ day: String, _ amount: Double, _ name: String) -> String {
            "\(day)|\(Int((amount * 100).rounded()))|\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
        for link in links {
            guard let bank = byID[link.bankAccount] else { continue }
            landed.listed.insert(link.bankAccount)
            guard visible.contains(link.account) else { continue }
            let accountID = link.account
            let lines = try context.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.accountID == accountID }))
            var refs = Set(lines.compactMap(\.bankRef))
            var unclaimed: [String: [LocalTransaction]] = [:]
            for t in lines where t.bankRef == nil && t.isActual {
                if let day = t.actualDate ?? t.forecastDate { unclaimed[key(day, t.amount, t.name), default: []].append(t) }
            }
            var pending: [(line: SimpleFIN.Line, ref: String)] = []
            for tx in bank.transactions where tx.date >= link.startDate {
                let ref = SimpleFIN.lineRef(bank.id, tx.id)
                if refs.contains(ref) { landed.skipped += 1; continue }
                refs.insert(ref)
                let amount = Double(tx.amount) ?? 0
                // A CSV row may carry the bank's full text or a short name.
                let names = [tx.description] + (SimpleFIN.shortName(tx.description).map { [$0] } ?? [])
                if let claim = names.map({ key(tx.date.description, amount, $0) }).first(where: { unclaimed[$0]?.isEmpty == false }) {
                    unclaimed[claim]!.removeLast().bankRef = ref
                    landed.skipped += 1
                    continue
                }
                pending.append((tx, ref))
            }
            guard !pending.isEmpty else { continue }
            // Claims don't change which bill dates are open: one call for all.
            var input = try matchRows(account: accountID, context)
            input["lines"] = pending.map { ["date": $0.line.date.description, "amount": $0.line.amount, "text": $0.line.description] }
            let answers = try run("bankMatch", input) as? [Any] ?? []
            let recs = Dictionary(try context.fetch(FetchDescriptor<LocalRecurring>(predicate: #Predicate { $0.accountID == accountID }))
                .map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (index, item) in pending.enumerated() {
                let amount = Double(item.line.amount) ?? 0
                let day = item.line.date.description
                if index < answers.count, let hit = answers[index] as? [String: Any],
                   let rid = hit["recurring_id"] as? Int, let occ = hit["forecast_date"] as? String, let rec = recs[rid] {
                    let paid = try payBill(rec, occ: occ, day: day, amount: amount, ref: item.ref, raw: item.line.description,
                                           how: "auto", context)
                    paid.added = next()
                    landed.matched += 1
                } else {
                    let own = try ownBankLine(account: accountID, day: day, amount: amount, raw: item.line.description,
                                              ref: item.ref, context)
                    own.added = next()
                    landed.added += 1
                }
            }
        }
        let accounts = Set(links.map(\.account))
        landed.unmatched = try context.fetch(FetchDescriptor<LocalTransaction>())
            .filter { accounts.contains($0.accountID) && isUnmatched($0) }.count
        if context.hasChanges {
            markChanged(context)
            try context.save()
        }
        return landed
    }

    /// The server's _pay_bill_from_bank: one of a bill's dates paid with the
    /// bank's date and amount, keeping the bill's name, category, notes and
    /// tags, and the bank's text.
    @discardableResult
    func payBill(_ rec: LocalRecurring, occ: String, day: String, amount: Double, ref: String?, raw: String,
                 how: String, _ context: ModelContext) throws -> LocalTransaction {
        let t = LocalTransaction(accountID: rec.accountID)
        t.recurringID = rec.id
        t.categoryID = rec.categoryID
        t.forecastDate = occ
        t.actualDate = day
        t.isActual = true
        t.bankMatch = how
        t.bankRef = ref
        t.name = rec.name
        t.amount = amount
        t.forecastAmount = rec.amount
        t.notes = rec.notes
        t.bankText = raw
        context.insert(t)
        try setTags(try billTagIDs(rec.id, context), line: t.id, context)
        return t
    }

    /// The server's _bank_own_line: a bank line landed as its own paid line.
    /// Tag rules see the bank's full text; then the line takes the short
    /// name and keeps the full text in its notes.
    @discardableResult
    func ownBankLine(account: Int, day: String, amount: Double, raw: String, ref: String?, left: Bool = false,
                     _ context: ModelContext) throws -> LocalTransaction {
        let t = LocalTransaction(accountID: account)
        t.actualDate = day
        t.forecastDate = day
        t.isActual = true
        t.bankRef = ref
        t.bankLeft = left
        t.name = raw
        t.amount = amount
        context.insert(t)
        try applyRules(to: t, context)
        if let short = SimpleFIN.shortName(raw) {
            t.name = short
            t.notes = String(raw.prefix(256))
        }
        return t
    }

    // MARK: The rows the core matches with

    /// The matching functions' input for one account: every bill (active or
    /// not) with its match settings, their deleted dates and every line, in
    /// the order they were added.
    func matchRows(account id: Int, _ context: ModelContext) throws -> [String: Any] {
        func null(_ value: Any?) -> Any { value ?? NSNull() }
        let recs = try ordered(LocalRecurring.self, context, added: \.added, id: \.id)
            .filter { $0.accountID == id && !$0.isDeleted }
        let ids = Set(recs.map(\.id))
        let skips = try context.fetch(FetchDescriptor<LocalSkip>()).filter { ids.contains($0.recurringID) && !$0.isDeleted }
            .sorted { $0.recurringID != $1.recurringID ? $0.recurringID < $1.recurringID : $0.date < $1.date }
        let lines = try ordered(LocalTransaction.self, context, added: \.added, id: \.id)
            .filter { $0.accountID == id && !$0.isDeleted }
        return [
            "recurring": recs.map { r in
                ["id": r.id, "frequency": r.frequency, "day_of_month": null(r.dayOfMonth), "anchor_date": null(r.anchorDate),
                 "end_date": null(r.endDate), "active": r.active, "description": r.name, "amount": Self.decimal(r.amount),
                 "match_days": r.matchDays, "match_percent": r.matchPercent, "match_text": null(r.matchText)] as [String: Any]
            },
            "skips": skips.map { ["recurring_id": $0.recurringID, "date": $0.date] },
            "transactions": lines.map { t in
                ["id": t.id, "recurring_id": null(t.recurringID), "transfer_id": null(t.transferID), "description": t.name,
                 "notes": null(t.notes), "amount": Self.decimal(t.amount), "forecast_date": null(t.forecastDate),
                 "actual_date": null(t.actualDate), "is_actual": t.isActual, "bank_match": null(t.bankMatch),
                 "has_bank_ref": t.bankRef != nil, "has_mail_ref": false, "bank_left": t.bankLeft] as [String: Any]
            },
        ]
    }

    /// A matching function, its refusals answered as the server's.
    private func runMatch(_ name: String, _ input: [String: Any]) throws -> Any {
        do {
            return try Core.shared.run(name, input)
        } catch {
            var message = "\(error)"
            if case let .failed(text) = error { message = text }
            if message.hasPrefix("Error: ") { message.removeFirst(7) }
            if let status = Self.matchStatus[message] { throw Problem(status: status, detail: message) }
            throw Problem(status: 500, detail: "The match couldn't be worked out: \(message)")
        }
    }

    /// The server's _unmatched_query, for one line.
    func isUnmatched(_ t: LocalTransaction) -> Bool {
        t.bankRef != nil && t.bankMatch == nil && !t.bankLeft && t.recurringID == nil && t.transferID == nil && t.isActual
            && !t.isDeleted
    }

    func unmatchedCount(account: Int, _ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.accountID == account }))
            .filter(isUnmatched).count
    }

    /// Lines on the Unmatched list in these accounts.
    func unmatchedTotal(accounts: Set<Int>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        return ((try? context.fetch(FetchDescriptor<LocalTransaction>())) ?? [])
            .filter { accounts.contains($0.accountID) && isUnmatched($0) }.count
    }

    /// _bank_text_of: the bank's full text when the name was shortened from it.
    func bankText(of t: LocalTransaction) -> String {
        if let notes = t.notes, SimpleFIN.shortName(notes) == t.name { return notes }
        return t.name
    }

    /// _line_name: the name a bill learns from a synced line.
    func learnName(of t: LocalTransaction) -> String {
        t.notes.flatMap(SimpleFIN.shortName) ?? t.name
    }

    // MARK: The Unmatched list's routes

    /// `GET /api/accounts/{id}/bank-unmatched`: newest first.
    func bankUnmatched(account id: Int?, _ context: ModelContext) throws -> Any {
        let acc = try account(id, context)
        let rows = try matchRows(account: acc.id, context)
        return try runMatch("bankUnmatched", ["transactions": rows["transactions"] ?? []])
    }

    /// `GET .../bank-unmatched/{line}/candidates`: the planned lines and open
    /// bill dates within 60 days, and the match sheet's choices.
    func bankCandidates(account id: Int?, line lineID: Int?, _ context: ModelContext) throws -> Any {
        let acc = try account(id, context)
        let line = try unmatchedLine(acc.id, lineID, context)
        var input = try matchRows(account: acc.id, context)
        input["transaction_id"] = line.id
        return try runMatch("bankCandidates", input)
    }

    private func unmatchedLine(_ account: Int, _ id: Int?, _ context: ModelContext) throws -> LocalTransaction {
        guard let id, let t = try? line(id, context), t.accountID == account, isUnmatched(t) else {
            throw Problem.notFound("That line isn't on the Unmatched list.")
        }
        return t
    }

    /// `POST .../bank-unmatched/{line}/match`: pays a planned line (by
    /// `transaction_id`) or a bill's date (`recurring_id`, `forecast_date`)
    /// with the bank line's date and amount; the bank line's own line goes
    /// away. With `remember`, the bill learns the line's name and the lines
    /// already on the list with it pay its open dates.
    func bankMatchByHand(account id: Int?, line lineID: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let acc = try account(id, context)
        let line = try unmatchedLine(acc.id, lineID, context)
        let day = line.actualDate ?? line.forecastDate ?? LocalDay.today().description
        let raw = bankText(of: line)
        let paid: LocalTransaction
        if let tid = int(body, "transaction_id") {
            guard let t = try? self.line(tid, context), t.accountID == acc.id else { throw Problem.notFound("Planned line not found") }
            if t.isActual || t.transferID != nil {
                throw Problem(status: 409, detail: "That line is already paid, or is a transfer: pick a planned line.")
            }
            if t.forecastAmount == nil { t.forecastAmount = t.amount }
            if t.forecastDate == nil { t.forecastDate = day }
            t.amount = line.amount
            t.actualDate = day
            t.isActual = true
            t.bankMatch = "hand"
            t.bankText = raw
            t.bankRef = line.bankRef
            paid = t
        } else if let rid = int(body, "recurring_id"), let occ = body["forecast_date"] as? String, LocalDay(occ) != nil {
            guard let rec = try context.fetch(FetchDescriptor<LocalRecurring>(predicate: #Predicate { $0.id == rid })).first,
                  rec.accountID == acc.id else { throw Problem.notFound("Bill not found") }
            let dates = try run("occurrences", ["recurring": recurringRow(rec, [:]), "start": occ, "end": occ]) as? [[String: Any]] ?? []
            guard dates.contains(where: { $0["date"] as? String == occ }) else {
                throw Problem.invalid("That bill has no date on that day.")
            }
            let covered = try context.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.recurringID == rid }))
                .contains { $0.forecastDate == occ && !$0.isDeleted }
            let skipped = try context.fetch(FetchDescriptor<LocalSkip>(predicate: #Predicate { $0.recurringID == rid }))
                .contains { $0.date == occ }
            if covered || skipped {
                throw Problem(status: 409, detail: "That date is already paid or was deleted: pick a planned line.")
            }
            paid = try payBill(rec, occ: occ, day: day, amount: line.amount, ref: line.bankRef, raw: raw, how: "hand", context)
        } else {
            throw Problem.invalid("Give transaction_id, or recurring_id and forecast_date.")
        }
        let name = learnName(of: line)
        try dropLinks(line: line.id, context)
        context.delete(line)
        var also = 0
        var learned: Any = NSNull()
        if body["remember"] as? Bool == true, let rid = paid.recurringID,
           let rec = try context.fetch(FetchDescriptor<LocalRecurring>(predicate: #Predicate { $0.id == rid })).first {
            rec.matchText = String(name.prefix(Self.matchTextMax))
            learned = rec.matchText ?? NSNull()
            also = try catchUp(rec, context)
        }
        return ["ok": true, "transaction_id": paid.id, "learned": learned, "also_matched": also]
    }

    /// The server's _catch_up_taught, through the core's bankCatchUp.
    private func catchUp(_ rec: LocalRecurring, _ context: ModelContext) throws -> Int {
        var input = try matchRows(account: rec.accountID, context)
        input["recurring_id"] = rec.id
        var n = 0
        for hit in try runMatch("bankCatchUp", input) as? [[String: Any]] ?? [] {
            guard let tid = hit["transaction_id"] as? Int, let occ = hit["forecast_date"] as? String,
                  let t = try? line(tid, context) else { continue }
            try payBill(rec, occ: occ, day: t.actualDate ?? t.forecastDate ?? occ, amount: t.amount, ref: t.bankRef,
                        raw: bankText(of: t), how: "auto", context)
            try dropLinks(line: t.id, context)
            context.delete(t)
            n += 1
        }
        return n
    }

    /// `POST .../bank-unmatched/{line}/leave`: "Leave as its own line".
    func bankLeave(account id: Int?, line lineID: Int?, _ context: ModelContext) throws -> Any {
        let acc = try account(id, context)
        try unmatchedLine(acc.id, lineID, context).bankLeft = true
        return ["ok": true]
    }
}
