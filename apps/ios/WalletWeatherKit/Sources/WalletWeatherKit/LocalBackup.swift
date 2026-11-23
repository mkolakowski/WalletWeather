import Foundation
import SwiftData

/// Moving between a server and the iPhone (Plans/standalone.md, phase 5,
/// #236): the household as the server's backup (`export_user` in
/// apps/server/app/backup.py, version 5), and a server's backup made into
/// the household (`import_user`, replacing what's on the phone, as decided
/// 2026-11-18).
///
/// Accounts, categories, bills and income with their skipped dates and
/// bank-match settings, lines, transfers, and since phone-tags phase 1
/// (#250) tags and tag rules move both ways, and since phase 8 (#239) each
/// line's bank ref and match. A server's email-alert links and its bank
/// connection aren't kept on the phone, so they're left behind on the way
/// in; the phone's own SimpleFIN connection stays in its Keychain, never in
/// a backup.
extension LocalServer {
    public static let backupVersion = 5

    public struct ImportSummary: Equatable, Sendable {
        public let accounts, recurring, transactions, transfers: Int
    }

    // MARK: - Out

    /// The household as a backup, in the server's format.
    public func backupPayload(now: Date = .now) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        let accounts = try ordered(LocalAccount.self, context, added: \.added, id: \.id)
        let categories = try ordered(LocalCategory.self, context, added: \.added, id: \.id)
        let recs = try ordered(LocalRecurring.self, context, added: \.added, id: \.id)
        let lines = try ordered(LocalTransaction.self, context, added: \.added, id: \.id)
        let transfers = try ordered(LocalTransfer.self, context, added: \.added, id: \.id)
        let skips = try context.fetch(FetchDescriptor<LocalSkip>())
        let tags = try context.fetch(FetchDescriptor<LocalTag>())
            .sorted { $0.name.unicodeScalars.lexicographicallyPrecedes($1.name.unicodeScalars) }
        let tagName = Dictionary(tags.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var lineTags: [Int: [String]] = [:], billTags: [Int: [String]] = [:]
        for link in try context.fetch(FetchDescriptor<LocalTagLink>()) {
            guard let name = tagName[link.tagID] else { continue }
            if let t = link.transactionID { lineTags[t, default: []].append(name) }
            if let r = link.recurringID { billTags[r, default: []].append(name) }
        }
        let rules = try ordered(LocalTagRule.self, context, added: \.added, id: \.id)
        let categoryName = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let recByID = Dictionary(recs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let accountIndex = Dictionary(accounts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let transferIndex = Dictionary(transfers.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        func null(_ value: Any?) -> Any { value ?? NSNull() }

        let accountsOut: [[String: Any]] = accounts.map { account in
            [
                "name": account.name,
                "starting_balance": account.startingBalance,
                "starting_date": account.startingDate,
                "created_at": Self.isoTime(account.added),
                "recurring": recs.filter { $0.accountID == account.id }.map { r in
                    [
                        "description": r.name, "amount": r.amount, "frequency": r.frequency,
                        "day_of_month": null(r.dayOfMonth), "anchor_date": null(r.anchorDate), "end_date": null(r.endDate),
                        "active": r.active, "category_name": null(r.categoryID.flatMap { categoryName[$0] }),
                        "notes": null(r.notes), "tags": (billTags[r.id] ?? []).sorted(), "match_days": r.matchDays,
                        "match_percent": r.matchPercent, "match_text": null(r.matchText),
                        "skipped_dates": skips.filter { $0.recurringID == r.id }.map(\.date).sorted(),
                    ] as [String: Any]
                },
                "transactions": lines.filter { $0.accountID == account.id }.map { t in
                    var line: [String: Any] = [
                        "description": t.name, "amount": t.amount, "forecast_date": null(t.forecastDate),
                        "actual_date": null(t.actualDate), "forecast_amount": null(t.forecastAmount),
                        "is_actual": t.isActual, "recurring_description": null(t.recurringID.flatMap { recByID[$0]?.name }),
                        "category_name": null(t.categoryID.flatMap { categoryName[$0] }), "notes": null(t.notes),
                        "tags": (lineTags[t.id] ?? []).sorted(), "bank_ref": null(t.bankRef), "mail_ref": NSNull(),
                        "bank_match": null(t.bankMatch), "bank_text": null(t.bankText), "bank_left": t.bankLeft,
                    ]
                    if let tid = t.transferID, let index = transferIndex[tid] { line["transfer"] = index }
                    return line
                },
            ]
        }
        let transfersOut: [[String: Any]] = transfers.compactMap { tr in
            guard let from = accountIndex[tr.fromAccountID], let to = accountIndex[tr.toAccountID] else { return nil }
            return ["from_account": from, "to_account": to, "transfer_date": tr.date, "amount": tr.amount,
                    "description": tr.name, "notes": null(tr.notes)]
        }
        return [
            "version": Self.backupVersion,
            "exported_at": Self.isoTime(now),
            "user": ["email": NSNull(), "name": NSNull()],
            "categories": categories.map { ["name": $0.name, "color": null($0.color)] },
            "tags": tags.map { ["name": $0.name, "color": null($0.color)] },
            "tag_rules": rules.compactMap { r -> [String: Any]? in
                guard let tag = tagName[r.tagID] else { return nil }
                return ["name": null(r.name), "description_pattern": r.pattern,
                        "category_name": null(r.categoryID.flatMap { categoryName[$0] }), "tag_name": tag, "active": r.active]
            },
            "accounts": accountsOut,
            "transfers": transfersOut,
        ]
    }

    /// "2026-11-18T23:40:32.123456Z", as the server writes times.
    static func isoTime(_ date: Date) -> String {
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return date.formatted(format).replacingOccurrences(of: "Z", with: "000Z")
    }

    // MARK: - In

    /// Replaces the household with a backup's, as the server's "replace"
    /// import does, with the server's checks: a bad date or amount refuses
    /// the whole file and changes nothing.
    @discardableResult
    public func importBackup(_ payload: [String: Any]) throws -> ImportSummary {
        guard let accounts = payload["accounts"] as? [Any] else {
            throw Problem.invalid("Not a valid backup file (missing 'accounts').")
        }
        guard let version = BackupFile.int(payload["version"]) ?? (payload["version"] as? String).flatMap(Int.init),
              version <= Self.backupVersion else {
            throw Problem.invalid("This backup was made by a newer version of WalletWeather. Update the app, then try again.")
        }
        _ = version
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for row in try context.fetch(FetchDescriptor<LocalAccount>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalCategory>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalRecurring>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalSkip>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalTransaction>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalTransfer>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalTag>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalTagLink>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<LocalTagRule>()) { context.delete(row) }

        // Rows keep the file's order: each is "added" a moment after the last.
        let start = Date.now
        var step = 0.0
        func next() -> Date { step += 1; return start.addingTimeInterval(step / 1_000_000) }

        var categoryByName: [String: LocalCategory] = [:]
        for case let c as [String: Any] in payload["categories"] as? [Any] ?? [] {
            let name = Self.text(c["name"], 80).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, categoryByName[name] == nil else { continue }
            let category = LocalCategory(name: name, color: Self.color(c["color"]))
            category.added = next()
            context.insert(category)
            categoryByName[name] = category
        }
        func categoryID(_ value: Any?) -> Int? {
            guard let name = value as? String, !name.isEmpty else { return nil }
            return categoryByName[name]?.id
        }

        // Tags by name; one used but not listed is made without a colour
        // (the server's get_tag).
        var tagByName: [String: LocalTag] = [:]
        func tagID(_ value: Any?, color: Any? = nil) -> Int? {
            let name = String(Self.text(value, 1000).trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.tagNameMax))
            guard !name.isEmpty else { return nil }
            if let found = tagByName[name] { return found.id }
            let tag = LocalTag(name: name, color: Self.color(color))
            tag.added = next()
            context.insert(tag)
            tagByName[name] = tag
            return tag.id
        }
        for case let tg as [String: Any] in payload["tags"] as? [Any] ?? [] { _ = tagID(tg["name"], color: tg["color"]) }
        var seenRules = Set<String>()
        for case let rd as [String: Any] in payload["tag_rules"] as? [Any] ?? [] {
            let pattern = String(Self.text(rd["description_pattern"], 1000).trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().prefix(120))
            guard !pattern.isEmpty, let tag = tagID(rd["tag_name"]) else { continue }
            let category = categoryID(rd["category_name"])
            guard seenRules.insert("\(pattern)\u{0}\(tag)\u{0}\(category ?? 0)").inserted else { continue }
            let rule = LocalTagRule(name: Self.text(rd["name"], 80).nilIfEmpty, pattern: pattern, categoryID: category,
                                    tagID: tag, active: rd.keys.contains("active") ? Self.truthy(rd["active"]) : true)
            rule.added = next()
            context.insert(rule)
        }
        func link(_ names: Any?, line: Int? = nil, bill: Int? = nil) {
            var done = Set<Int>()
            for name in names as? [Any] ?? [] {
                guard let id = tagID(name), done.insert(id).inserted else { continue }
                context.insert(LocalTagLink(tagID: id, transactionID: line, recurringID: bill))
            }
        }

        var counts = (accounts: 0, recurring: 0, transactions: 0, transfers: 0)
        var accountByIndex: [Int: LocalAccount] = [:]
        var legsByTransfer: [Int: [LocalTransaction]] = [:]
        for (index, item) in accounts.enumerated() {
            guard let a = item as? [String: Any] else { throw Problem.invalid("Each account must be an object") }
            guard let startingDate = try Self.day(a["starting_date"]) ?? (a.keys.contains("starting_date") ? LocalDay.today().description : nil) else {
                throw Problem.invalid("An account has no starting_date.")
            }
            let account = LocalAccount(name: Self.text(a["name"] ?? "Imported account", 120),
                                       startingBalance: try Self.amount(a["starting_balance"] ?? 0),
                                       startingDate: startingDate)
            account.added = next()
            context.insert(account)
            accountByIndex[index] = account
            counts.accounts += 1

            var recByName: [String: LocalRecurring] = [:]
            for case let r as [String: Any] in a["recurring"] as? [Any] ?? [] {
                let rec = LocalRecurring(accountID: account.id)
                rec.frequency = String(Self.text(Self.truthy(r["frequency"]) ? r["frequency"] : "monthly_day", 20))
                rec.dayOfMonth = BackupFile.int(r["day_of_month"]).flatMap { (1...31).contains($0) ? $0 : nil }
                rec.anchorDate = try Self.day(r["anchor_date"])
                rec.endDate = try Self.day(r["end_date"])
                rec.active = r.keys.contains("active") ? Self.truthy(r["active"]) : true
                rec.categoryID = categoryID(r["category_name"])
                rec.name = Self.text(r["description"] ?? "", 500)
                rec.amount = try Self.amount(r["amount"] ?? 0)
                rec.notes = Self.text(r["notes"], 256).nilIfEmpty
                rec.matchDays = BackupFile.int(r["match_days"]).flatMap { (0...31).contains($0) ? $0 : nil } ?? 5
                rec.matchPercent = BackupFile.int(r["match_percent"]).flatMap { (0...100).contains($0) ? $0 : nil } ?? 10
                rec.matchText = Self.text(r["match_text"], 120).nilIfEmpty
                rec.added = next()
                context.insert(rec)
                var skipped = Set<String>()
                for value in r["skipped_dates"] as? [Any] ?? [] {
                    if let day = try Self.day(value) { skipped.insert(day) }
                }
                for day in skipped.sorted() { context.insert(LocalSkip(recurringID: rec.id, date: day)) }
                link(r["tags"], bill: rec.id)
                recByName[rec.name] = rec
                counts.recurring += 1
            }

            for case let t as [String: Any] in a["transactions"] as? [Any] ?? [] {
                let line = LocalTransaction(accountID: account.id)
                line.forecastDate = try Self.day(t["forecast_date"])
                line.actualDate = try Self.day(t["actual_date"])
                line.isActual = Self.truthy(t["is_actual"])
                line.categoryID = categoryID(t["category_name"])
                line.name = Self.text(t["description"] ?? "", 500)
                line.amount = try Self.amount(t["amount"] ?? 0)
                line.notes = Self.text(t["notes"], 256).nilIfEmpty
                if let planned = t["forecast_amount"], !(planned is NSNull) { line.forecastAmount = try Self.amount(planned) }
                if let name = t["recurring_description"] as? String, !name.isEmpty { line.recurringID = recByName[name]?.id }
                // Bank sync's ref and match (#239), as backup.py reads them: a
                // line a server brought in isn't brought in again by the phone.
                if let ref = t["bank_ref"] as? String, ref.count == 64, ref.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
                    line.bankRef = ref
                    if let how = t["bank_match"] as? String, how == "auto" || how == "hand" {
                        line.bankMatch = how
                        line.bankText = Self.text(t["bank_text"], 500).nilIfEmpty
                    }
                    line.bankLeft = t["bank_left"] as? Bool == true
                }
                line.added = next()
                context.insert(line)
                link(t["tags"], line: line.id)
                counts.transactions += 1
                if let index = BackupFile.int(t["transfer"]), index >= 0 { legsByTransfer[index, default: []].append(line) }
            }
        }

        for (index, item) in (payload["transfers"] as? [Any] ?? []).enumerated() {
            guard let tr = item as? [String: Any],
                  let from = BackupFile.int(tr["from_account"]).flatMap({ accountByIndex[$0] }),
                  let to = BackupFile.int(tr["to_account"]).flatMap({ accountByIndex[$0] }), from.id != to.id else { continue }
            let legs = (legsByTransfer[index] ?? []).filter { $0.accountID == from.id || $0.accountID == to.id }
            guard !legs.isEmpty, let day = try? Self.day(tr["transfer_date"]),
                  let amount = try? Self.amount(tr["amount"] ?? 0), amount > 0 else { continue }
            let typed = Self.text(Self.truthy(tr["description"]) ? tr["description"] : "Transfer", 120)
            let transfer = LocalTransfer(fromAccountID: from.id, toAccountID: to.id, amount: amount, date: day,
                                         name: typed.isEmpty ? "Transfer" : typed,
                                         notes: Self.text(tr["notes"], 256).nilIfEmpty)
            transfer.added = next()
            context.insert(transfer)
            for leg in legs { leg.transferID = transfer.id }
            counts.transfers += 1
        }
        markChanged(context)
        try context.save()
        return ImportSummary(accounts: counts.accounts, recurring: counts.recurring,
                             transactions: counts.transactions, transfers: counts.transfers)
    }

    // MARK: The server's readers (backup.py)

    /// `_text`: the value as text, cut to `limit` code points.
    static func text(_ value: Any?, _ limit: Int) -> String {
        let string: String
        switch value {
        case nil, is NSNull: string = ""
        case let text as String: string = text
        case let number as NSNumber where BackupFile.isBool(number): string = number.boolValue ? "True" : "False"
        case let number as NSNumber: string = number.stringValue
        default: string = "\(value!)"
        }
        return String(String.UnicodeScalarView(string.unicodeScalars.prefix(limit)))
    }

    /// `_amount`: a finite number of a size money comes in.
    static func amount(_ value: Any) throws -> Double {
        let number: Double?
        switch value {
        case let n as NSNumber where !BackupFile.isBool(n): number = n.doubleValue
        case let s as String: number = Decimal(string: s.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")).map { NSDecimalNumber(decimal: $0).doubleValue }
        default: number = nil
        }
        guard let number, number.isFinite, abs(number) <= 1e12 else { throw Problem.invalid("Not an amount: \(value)") }
        return number
    }

    /// `_parse_date`: nothing for an empty value, else a date or a refusal.
    static func day(_ value: Any?) throws -> String? {
        guard truthy(value) else { return nil }
        guard let text = value as? String, let parsed = LocalDay(text) else { throw Problem.invalid("Not a date: \(value!)") }
        return parsed.description
    }

    /// `_color`: a hex colour, or none.
    static func color(_ value: Any?) -> String? {
        guard let text = value as? String, text.wholeMatch(of: /#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?/) != nil else { return nil }
        return text
    }

    /// Python's truthiness, for `bool(x)` and `x or default`.
    static func truthy(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: false
        case let text as String: !text.isEmpty
        case let number as NSNumber: number.doubleValue != 0
        case let list as [Any]: !list.isEmpty
        case let dict as [String: Any]: !dict.isEmpty
        default: true
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
