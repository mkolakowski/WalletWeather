import SwiftUI
import UniformTypeIdentifiers
import WalletWeatherKit

/// Import a CSV (Plans/standalone.md, phase 9, #243): a bank's CSV export
/// picked in the Files app, read by the shared core (on the phone, or the
/// server's same code), previewed, then imported as paid lines. From
/// Settings (asks which account) and Forecast's + menu (that account), on
/// the phone with no server and with one (decided 2026-11-20). The columns
/// and signs chosen are remembered per account for the next file with the
/// same headings.
extension View {
    func csvImporter(isPresented: Binding<Bool>, account: Int?, onImported: @escaping () async -> Void) -> some View {
        modifier(CSVImporter(isPresented: isPresented, account: account, onImported: onImported))
    }
}

/// A picked file's text.
struct CSVFile: Identifiable {
    let id = UUID()
    let name: String
    let text: String

    /// UTF-8 (a byte order mark dropped, as a browser drops it for the web
    /// app), else Latin-1, which any bytes are.
    static func read(_ data: Data, name: String) -> CSVFile? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) else { return nil }
        return CSVFile(name: name, text: text)
    }
}

private struct CSVImporter: ViewModifier {
    @Binding var isPresented: Bool
    let account: Int?
    let onImported: () async -> Void
    @State private var file: CSVFile?
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case let .success(url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url), let read = CSVFile.read(data, name: url.lastPathComponent) else {
                        problem = "That file couldn't be read."
                        return
                    }
                    file = read
                case let .failure(error):
                    problem = error.localizedDescription
                }
            }
            .sheet(item: $file) { CSVImportSheet(file: $0, startAccount: account, onImported: onImported) }
            .alert("Couldn't open the file", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {  // ui-check: allow alert — a file that couldn't be opened, with no editor to show it in
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
    }
}

/// The choices kept for an account: the headings they were made for, the
/// columns, the signs and whether the first row is headings.
private struct RememberedColumns: Codable {
    let headers: [String]
    let mapping: CSVMapping
    let signs: CSVSigns
    let hasHeader: Bool

    static func key(host: String, account: Int) -> String { "csvImport.columns.\(host).\(account)" }

    static func load(host: String, account: Int) -> RememberedColumns? {
        UserDefaults.standard.data(forKey: key(host: host, account: account))
            .flatMap { try? JSONDecoder().decode(RememberedColumns.self, from: $0) }
    }

    func save(host: String, account: Int) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(host: host, account: account)) }
    }
}

struct CSVImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: CSVFile
    let startAccount: Int?
    let onImported: () async -> Void

    @State private var accounts: [Account] = []
    @State private var categories: [TransactionCategory] = []
    @State private var accountId: Int?
    @State private var body_ = CSVImportBody(csvText: "")
    @State private var preview: CSVPreview?
    @State private var loading = false
    @State private var importing = false
    @State private var problem: String?
    @State private var done: CSVImportResult?
    /// Bumped by each change, so only the latest preview lands.
    @State private var asked = 0
    @State private var showColumns = false

    private var host: String { model.connection?.host ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("File", value: file.name)
                    Picker("Account", selection: $accountId) {
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("First row is column names", isOn: $body_.hasHeader)
                    Picker("Amounts", selection: $body_.signs) {
                        ForEach(CSVSigns.allCases) { Text($0.title).tag($0) }
                    }
                }
                if let problem { Section { Text(problem).foregroundStyle(Palette.bad) } }
                if loading && preview == nil {
                    Section { HStack(spacing: 8) { ProgressView(); Text("Reading the file…").foregroundStyle(.secondary) } }
                }
                if let preview { summary(preview); columns(preview); options; rows(preview) }
            }
            .navigationTitle("Import a CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await commit() } }
                        .prominentButton()
                        .disabled(importing || loading || accountId == nil || (preview?.rowCount ?? 0) == 0)
                }
            }
            .disabled(importing)
            .task { await start() }
            .onChange(of: accountId) { old, new in if old != nil, new != nil { remember(reset: true) } }
            .onChange(of: body_.hasHeader) { Task { await refresh() } }
            .onChange(of: body_.signs) { Task { await refresh() } }
            .alert("Imported", isPresented: Binding(get: { done != nil }, set: { if !$0 { finish() } })) {  // ui-check: allow alert — the import's result, acknowledged before the sheet closes
                Button("OK", role: .cancel) { finish() }
            } message: { Text(done.map(Self.describe) ?? "") }
        }
    }

    // MARK: Sections

    private func columns(_ preview: CSVPreview) -> some View {
        Section {
            DisclosureGroup("Columns", isExpanded: Binding(get: { showColumns || !found(preview) }, set: { showColumns = $0 })) {
                columnPickers(preview)
            }
        } footer: {
            Text(found(preview) ? "Worked out from the column names, or kept from the last file for this account."
                                : "The date or amount column wasn't found. Choose them here.")
        }
    }

    /// The date and the money columns are set.
    private func found(_ preview: CSVPreview) -> Bool {
        let mapping = body_.mapping ?? preview.mapping
        let money = body_.signs == .debitCredit ? (mapping.debit != nil || mapping.credit != nil) : mapping.amount != nil
        return mapping.date != nil && money
    }

    @ViewBuilder
    private func columnPickers(_ preview: CSVPreview) -> some View {
            ForEach(fields) { field in
                Picker(field.title, selection: Binding(get: { body_.mapping?[field] ?? preview.mapping[field] },
                                                       set: { setColumn(field, $0, from: preview) })) {
                    Text("None").tag(Int?.none)
                    ForEach(preview.headers.indices, id: \.self) { i in
                        Text(columnName(preview.headers[i], i)).tag(Optional(i))
                    }
                }
            }
    }

    private var fields: [CSVMapping.Field] {
        let money: [CSVMapping.Field] = body_.signs == .debitCredit ? [.debit, .credit] : [.amount]
        return [.date, .description] + money + [.category, .notes, .frequency, .endDate, .recurringGroup]
    }

    private func columnName(_ header: String, _ i: Int) -> String {
        let name = header.trimmingCharacters(in: .whitespaces)
        return body_.hasHeader && !name.isEmpty ? name : "Column \(i + 1)"
    }

    private func summary(_ preview: CSVPreview) -> some View {
        let adding = preview.rowCount - (body_.skipDuplicates ? preview.duplicateCount : 0)
        return Section {
            LabeledContent("Lines to add", value: "\(adding)")
            if preview.duplicateCount > 0 {
                LabeledContent("Already here", value: "\(preview.duplicateCount)")
            }
            if preview.recurringCount > 0 {
                LabeledContent("Repeating", value: "\(preview.recurringCount)")
            }
            if preview.skippedCount > 0 {
                LabeledContent("Left out", value: "\(preview.skippedCount)")
            }
        } footer: {
            Text("Each row lands as a paid line on its date. A line with the same date, amount and description as one already on the account counts as already here.")
        }
    }

    private var options: some View {
        Section {
            Picker("Category if none matches", selection: $body_.defaultCategoryId) {
                Text("None").tag(Int?.none)
                ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
            }
            Toggle("Leave out lines already here", isOn: $body_.skipDuplicates)
        }
    }

    private func rows(_ preview: CSVPreview) -> some View {
        Group {
            Section {
                ForEach(preview.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.description).lineLimit(1)
                            Spacer()
                            Text(row.amount.formatted).monospacedDigit()
                                .foregroundStyle(row.duplicate && body_.skipDuplicates ? Color.secondary : Palette.amount(row.amount.isNegative))
                        }
                        HStack(spacing: 6) {
                            Text(row.date.short)
                            if row.duplicate { Text("· already here") }
                            if let template = row.recurringTemplate {
                                Text(template == "existing" ? "· joins its bill" : "· makes a bill")
                            }
                            if let name = row.categoryName { Text("· \(name)\(row.categoryMatched ? "" : " (no such category)")") }
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .opacity(row.duplicate && body_.skipDuplicates ? 0.5 : 1)
                }
            } header: {
                Text(preview.rowCount > preview.rows.count ? "The first \(preview.rows.count) of \(preview.rowCount)" : "Rows")
            }
            if !preview.skipped.isEmpty {
                Section("Left out") {
                    ForEach(preview.skipped) { skip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skip.row.joined(separator: ", ")).lineLimit(1)
                            Text("Row \(skip.rowIndex + 1): \(skip.reason)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Work

    private func start() async {
        body_.csvText = file.text
        guard let client = model.client else { return }
        // Which accounts can be changed depends on who's signed in.
        if model.me == nil { await model.refreshMe() }
        do {
            async let found = client.accounts()
            async let cats = client.categories()
            accounts = try await found.filter(model.canEdit)
            categories = (try? await cats) ?? []
        } catch {
            problem = AppModel.describe(error)
            return
        }
        if accounts.isEmpty {
            problem = "There's no account here you can change. Add an account first."
            return
        }
        accountId = startAccount.flatMap { id in accounts.contains { $0.id == id } ? id : nil }
            ?? accounts.first?.id
        remember(reset: false)
    }

    /// Takes the account's kept choices, or works the columns out.
    private func remember(reset: Bool) {
        if let accountId, let kept = RememberedColumns.load(host: host, account: accountId) {
            body_.mapping = kept.mapping
            body_.signs = kept.signs
            body_.hasHeader = kept.hasHeader
            Task { await refresh(keptHeaders: kept.headers) }
        } else {
            if reset { body_.mapping = nil }
            Task { await refresh() }
        }
    }

    private func setColumn(_ field: CSVMapping.Field, _ column: Int?, from preview: CSVPreview) {
        var mapping = body_.mapping ?? preview.mapping
        mapping[field] = column
        body_.mapping = mapping
        Task { await refresh() }
    }

    /// Reads the file again with the choices made. Kept columns made for
    /// other headings are dropped for the ones worked out.
    private func refresh(keptHeaders: [String]? = nil) async {
        guard let client = model.client, let account = accountId ?? accounts.first?.id else { return }
        asked += 1
        let mine = asked
        loading = true
        defer { if mine == asked { loading = false } }
        do {
            var answer = try await client.previewImport(body_, account: account)
            if let keptHeaders, keptHeaders != answer.headers {
                body_.mapping = nil
                answer = try await client.previewImport(body_, account: account)
            }
            guard mine == asked else { return }
            preview = answer
            if body_.mapping == nil { body_.mapping = answer.mapping }
            problem = nil
        } catch {
            guard mine == asked else { return }
            preview = nil
            problem = AppModel.describe(error)
        }
    }

    private func commit() async {
        guard let client = model.client, let accountId, let preview else { return }
        importing = true
        defer { importing = false }
        var body = body_
        if body.mapping == nil { body.mapping = preview.mapping }
        do {
            done = try await client.commitImport(body, account: accountId)
            RememberedColumns(headers: preview.headers, mapping: body.mapping ?? preview.mapping,
                              signs: body.signs, hasHeader: body.hasHeader).save(host: host, account: accountId)
        } catch {
            problem = AppModel.describe(error)
        }
    }

    private func finish() {
        done = nil
        dismiss()
        Task { await onImported() }
    }

    static func describe(_ result: CSVImportResult) -> String {
        var parts = ["\(result.inserted) line\(result.inserted == 1 ? "" : "s") added"]
        if result.duplicatesSkipped > 0 { parts.append("\(result.duplicatesSkipped) already here, left out") }
        if result.recurringCreated > 0 { parts.append("\(result.recurringCreated) new bill\(result.recurringCreated == 1 ? "" : "s") from repeating rows") }
        return parts.joined(separator: ", ") + "."
    }
}
