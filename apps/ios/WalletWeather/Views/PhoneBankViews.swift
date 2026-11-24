import SwiftUI
import WalletWeatherKit

// Bank sync on this iPhone, without a server (Plans/standalone.md, phase 8,
// #239; design calls settled 2026-11-22): Settings → Bank sync offers
// Connect SimpleFIN (the setup token pasted, the access address kept in the
// Keychain only), a picker for each bank account as the web app's Settings
// has, Sync now under the server's daily limit, Unmatched (N) opening the
// list with Match… and Leave, and Disconnect. A phone signed in to a server
// keeps the server's card (BankSyncCard).

/// Settings → Bank sync on a phone without a server.
struct PhoneBankCard: View {
    @Environment(AppModel.self) private var model
    @State private var connecting = false
    @State private var syncing = false
    @State private var outcome: String?
    @State private var outcomeFailed = false
    @State private var confirmDisconnect = false
    @State private var accounts: [Account] = []
    /// `WW_DEBUG_BANK=unmatched` (debug builds): opens the Unmatched list.
    @State private var unmatchedRoute: UnmatchedRoute? =
        AppModel.debugSetting("WW_DEBUG_BANK") == "unmatched" || AppModel.debugSetting("WW_DEBUG_UNMATCHED") == "1"
        ? UnmatchedRoute(accounts: nil) : nil

    private var bank: PhoneBank { model.phoneBank }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bank.connected {
                connected
            } else {
                Label {
                    Text("No bank connected").font(.subheadline.weight(.semibold))
                } icon: { Image(systemName: "building.columns") }
                Text("Bring your bank's posted lines in through SimpleFIN Bridge: make a setup token at bridge.simplefin.org, then paste it here. The connection is kept in this iPhone's Keychain only. It syncs at most once a day, when you open the app or when iOS gives it time in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { connecting = true } label: {
                    Label("Connect SimpleFIN", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            if let outcome {
                Text(outcome).font(.footnote).foregroundStyle(outcomeFailed ? Palette.bad : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $connecting) {
            ConnectSimpleFINSheet { said in outcome = said; outcomeFailed = false }
        }
        .confirmationDialog("Disconnect SimpleFIN from this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                bank.disconnect()
                model.scheduleBankRefresh()
                outcome = "Disconnected. The lines already brought in stay."
                outcomeFailed = false
            }
        } message: {
            Text("Nothing syncs until you connect again with a new setup token. The lines already brought in stay. To stop SimpleFIN's side too, disable the token at SimpleFIN Bridge.")
        }
        .task(id: model.generation) {
            accounts = (try? await model.client?.accounts()) ?? []
            bank.recount()
        }
        .unmatchedList($unmatchedRoute)
    }

    @ViewBuilder
    private var connected: some View {
        let state = bank.state
        HStack(alignment: .firstTextBaseline) {
            Text(bankName(state)).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text("SimpleFIN").font(.caption).foregroundStyle(.secondary)
        }
        summary(state)
        if state.bankAccounts.isEmpty {
            Text("SimpleFIN listed no bank accounts yet. Sync now lists them again.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Divider()
            ForEach(state.bankAccounts) { bankAccount in
                accountRow(bankAccount, link: state.link(for: bankAccount.id))
            }
        }
        if state.unmatched > 0 {
            Divider()
            Button { unmatchedRoute = UnmatchedRoute(accounts: nil) } label: {
                HStack {
                    Text("Unmatched (\(state.unmatched))")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        let wait = bank.waitSeconds()
        Button { Task { await syncNow() } } label: {
            HStack(spacing: 8) {
                if syncing { ProgressView() }
                Text("Sync now").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glass)
        .disabled(syncing || wait > 0 || state.links.isEmpty)
        if wait > 0 {
            Text(PhoneBank.waitText(wait)).font(.footnote).foregroundStyle(Palette.warn)
        } else if state.links.isEmpty {
            Text("Match a bank account to one of your accounts to sync it.").font(.footnote).foregroundStyle(.secondary)
        }
        Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            .font(.footnote)
            .disabled(syncing)
    }

    private func bankName(_ state: PhoneBankState) -> String {
        var orgs: [String] = []
        for a in state.bankAccounts where !a.org.isEmpty && !orgs.contains(a.org) { orgs.append(a.org) }
        return orgs.isEmpty ? "SimpleFIN" : orgs.joined(separator: ", ")
    }

    @ViewBuilder
    private func summary(_ state: PhoneBankState) -> some View {
        let (tone, headline, detail): (BankSyncSummary.Tone, String, String?) = {
            if state.needsReconnect {
                return (.warning, "Needs connecting again", "SimpleFIN no longer accepts this connection. Disconnect, then connect again with a new token.")
            }
            guard let last = state.lastSyncAt else { return (.neutral, "Connected", "Not synced yet.") }
            if state.lastSyncOk == false {
                return (.warning, "Last sync failed", "\(KeptBar.when(last)): \(state.lastSyncStatus ?? "SimpleFIN didn't answer.")")
            }
            return (.ok, "Synced \(KeptBar.when(last))", state.lastSyncStatus)
        }()
        Label {
            Text(headline).font(.subheadline.weight(.semibold))
        } icon: {
            switch tone {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
            case .neutral: Image(systemName: "building.columns")
            }
        }
        if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        if let next = bank.nextSyncAt() {
            Text(next > .now ? "Syncs by itself again about \(KeptBar.when(next))." : "The next sync by itself is due now.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// A bank account: which of the phone's accounts it fills, and from when.
    private func accountRow(_ bankAccount: SimpleFIN.Account, link: PhoneBankState.Link?) -> some View {
        let today = LocalDay.today()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bankAccount.name)
                    if !bankAccount.org.isEmpty { Text(bankAccount.org).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Picker("Your account for \(bankAccount.name)", selection: Binding(
                    get: { link?.account },
                    set: { bank.link(bankAccount.id, to: $0, start: link?.startDate) }
                )) {
                    Text("Leave out").tag(Int?.none)
                    ForEach(accounts) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .labelsHidden()
            }
            if let link {
                DatePicker("Bring in from", selection: Binding(
                    get: { link.startDate.date },
                    set: { bank.link(bankAccount.id, to: link.account, start: LocalDay.today(now: $0)) }
                ), in: today.adding(days: -SimpleFIN.maxDaysPerRequest).date...today.date, displayedComponents: .date)
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    private func syncNow() async {
        syncing = true
        outcome = nil
        defer { syncing = false }
        do {
            let result = try await bank.sync()
            outcome = "Synced: \(bank.state.lastSyncStatus ?? "done")."
            outcomeFailed = false
            if result.added + result.matched > 0 { model.reload() }
        } catch {
            outcome = error.message
            outcomeFailed = true
        }
        model.scheduleBankRefresh()
    }
}

/// Connect SimpleFIN: the setup token pasted, claimed as the server does.
private struct ConnectSimpleFINSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let done: (String) -> Void
    @State private var token = ""
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Setup token", text: $token, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("At bridge.simplefin.org, connect your bank and make a new setup token, then paste it here. A token works once: this iPhone swaps it for a connection kept in its Keychain only, never in iCloud or a backup.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Palette.bad) }
                }
            }
            .navigationTitle("Connect SimpleFIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Connect") { Task { await connect() } }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func connect() async {
        working = true
        problem = nil
        defer { working = false }
        do {
            try await model.phoneBank.connect(token: token)
            let n = model.phoneBank.state.bankAccounts.count
            done(n == 0 ? "Connected." : "Connected. Pick which of your accounts each bank account fills, then Sync now.")
            dismiss()
        } catch {
            problem = error.message
        }
    }
}

// MARK: - The Unmatched list

/// The Unmatched list to show: for these accounts, or nil for the household
/// on this iPhone's.
struct UnmatchedRoute: Hashable { let accounts: [Int]? }

extension View {
    /// Shows the Unmatched list for `route`: pushed on a navigation stack, or,
    /// in the wide Settings window's pane (`settingsIsWide`, whose size class
    /// is forced to compact), over the whole window with its regular width back,
    /// so its two panes show (#306).
    func unmatchedList(_ route: Binding<UnmatchedRoute?>) -> some View {
        modifier(UnmatchedPresenter(route: route))
    }
}

private struct UnmatchedPresenter: ViewModifier {
    @Environment(\.settingsIsWide) private var wide
    @Binding var route: UnmatchedRoute?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: Binding(get: { wide ? nil : route }, set: { route = $0 })) {
                UnmatchedListView(accounts: $0.accounts)
            }
            .fullScreenCover(item: Binding(get: { wide ? route : nil }, set: { route = $0 })) { route in
                NavigationStack {
                    UnmatchedListView(accounts: route.accounts)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
                }
                .environment(\.horizontalSizeClass, .regular)
            }
    }
}

private struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Done") { dismiss() } }
}

extension UnmatchedRoute: Identifiable {
    var id: String { accounts?.map(String.init).joined(separator: ",") ?? "phone" }
}

/// Bank lines that paid no planned line, newest first, with Match… and
/// Leave, as the web app's Unmatched list. `accounts` names the accounts to
/// list (a connection's, or one shared account, from Settings → Bank sync
/// with a server); nil lists every account the household on this iPhone
/// matched. Open (a regular width), the list is one pane and the tapped
/// line's choices the other, on `FoldLayout`; closed, the choices are a sheet.
/// A read-only sign-in sees them and can't change anything (#306).
struct UnmatchedListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    var accounts: [Int]?
    @State private var groups: [(account: Account, lines: [BankUnmatched.Line])] = []
    @State private var loaded = false
    @State private var problem: String?
    @State private var matching: Matching?
    @State private var note: String?

    struct Matching: Identifiable {
        let account: Int
        let line: BankUnmatched.Line
        var id: Int { line.id }
    }

    private var canWrite: Bool { model.me?.isReadOnly != true }

    var body: some View {
        Group {
            if sizeClass == .regular {
                FoldLayout { edges in
                    ScrollView { page(edges: edges, selected: matching?.id) }
                } trailing: { edges in
                    if let matching {
                        MatchChoices(account: matching.account, line: matching.line, canWrite: canWrite,
                                     onClose: { self.matching = nil }, done: finished)
                            .id("\(matching.account)/\(matching.id)")
                            .padding(.leading, edges.leading).padding(.trailing, edges.trailing)
                    } else {
                        Text("Pick a line to see what it could pay.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.leading, edges.leading).padding(.trailing, edges.trailing)
                    }
                }
            } else {
                ScrollView { page(edges: .plain, selected: nil) }
            }
        }
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Unmatched")
        .task(id: "\(model.generation)/\(accounts?.map(String.init).joined(separator: ",") ?? "phone")") { await load() }
        .sheet(item: Binding(get: { sizeClass == .regular ? nil : matching }, set: { matching = $0 })) { m in
            MatchSheet(account: m.account, line: m.line, canWrite: canWrite, done: finished)
        }
    }

    /// A match or a leave went through: say so, and ask again.
    private func finished(_ said: String) {
        note = said
        matching = nil
        Task { await load() }
        model.reload()
    }

    private func page(edges: FoldPanes.Edges, selected: Int?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lines from your bank that paid no planned line. Match one to the bill or line it paid, or leave it as its own line.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            if !canWrite {
                Text("This iPhone signed in with a read-only token, so Match and Leave are off.")
                    .font(.footnote).foregroundStyle(Palette.warn).padding(.horizontal, 4)
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            if let problem {
                Text(problem).foregroundStyle(Palette.bad).card()
            } else if loaded && groups.isEmpty {
                Text("Nothing to match.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            ForEach(groups, id: \.account.id) { group in
                Text(group.account.name).font(.headline).padding(.horizontal, 4).padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { Divider() }
                        row(line, account: group.account.id, selected: selected == line.id)
                    }
                }
                .card()
            }
        }
        .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
    }

    private func row(_ line: BankUnmatched.Line, account: Int, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.description).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 8)
                Text(line.amount.formatted).font(.subheadline.monospacedDigit())
                    .foregroundStyle(line.amount.isNegative ? Palette.bad : Palette.good)
            }
            Text(line.date.short).font(.footnote).foregroundStyle(.secondary)
            if let notes = line.notes, !notes.isEmpty, notes != line.description {
                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                Button("Match…") { matching = Matching(account: account, line: line) }
                    .buttonStyle(.glass)
                Button("Leave") { Task { await leave(line, account: account) } }
                    .buttonStyle(.glass)
                    .disabled(!canWrite)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, selected ? 8 : 0)
        .background(selected ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if sizeClass == .regular { matching = Matching(account: account, line: line) } }
    }

    private func load() async {
        guard let client = model.client else { return }
        let wanted = accounts.map(Set.init) ?? Set(model.phoneBank.state.links.map(\.account))
        do {
            let all = try await client.accounts().filter { wanted.contains($0.id) }
            // The order asked for, else the accounts' own.
            let ordered = accounts.map { ids in ids.compactMap { id in all.first { $0.id == id } } } ?? all
            var found: [(Account, [BankUnmatched.Line])] = []
            for account in ordered {
                let list = try await client.bankUnmatched(account: account.id)
                if !list.lines.isEmpty { found.append((account, list.lines)) }
            }
            groups = found.map { (account: $0.0, lines: $0.1) }
            problem = nil
        } catch {
            problem = AppModel.describe(error)
        }
        loaded = true
        if accounts == nil { model.phoneBank.recount() }
    }

    private func leave(_ line: BankUnmatched.Line, account: Int) async {
        guard let client = model.client else { return }
        do {
            try await client.bankLeave(account: account, line: line.id)
            if matching?.id == line.id { matching = nil }
            note = "Left \(line.description) as its own line."
            await load()
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

/// Match…, closed: the choices in a sheet.
private struct MatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: Int
    let line: BankUnmatched.Line
    let canWrite: Bool
    let done: (String) -> Void

    var body: some View {
        NavigationStack {
            MatchChoices(account: account, line: line, canWrite: canWrite, onClose: nil) { said in
                done(said)
                dismiss()
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

/// What a bank line could pay: the line on top and a card for each bill or
/// planned line, saying how the bank's line compares, with Pay this, "Always
/// match" its name and Leave. A sheet holds it closed, and the second pane
/// of the open Duo (`onClose` then adds Close at the top).
private struct MatchChoices: View {
    @Environment(AppModel.self) private var model
    let account: Int
    let line: BankUnmatched.Line
    let canWrite: Bool
    let onClose: (() -> Void)?
    let done: (String) -> Void
    @State private var candidates: BankCandidates?
    @State private var problem: String?
    @State private var remember = true
    @State private var showAll = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let onClose {
                    HStack {
                        Text("Match").font(.headline)
                        Spacer()
                        Button("Close", action: onClose)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.description).font(.headline)
                        Spacer(minLength: 8)
                        Text(line.amount.formatted).font(.headline.monospacedDigit())
                            .foregroundStyle(line.amount.isNegative ? Palette.bad : Palette.good)
                    }
                    Text(line.date.short).font(.subheadline).foregroundStyle(.secondary)
                    if let text = candidates?.line.bankText {
                        Text(text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .card()
                if !canWrite {
                    Text("This iPhone signed in with a read-only token, so Pay this and Leave are off.")
                        .font(.footnote).foregroundStyle(Palette.warn)
                }
                if let problem { Text(problem).foregroundStyle(Palette.bad) }
                if let candidates {
                    choices(candidates)
                } else if problem == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Button { Task { await leave() } } label: {
                    Text("Leave as its own line").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(working || !canWrite)
            }
            .padding(.horizontal, onClose == nil ? 16 : 0).padding(.vertical, 16)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func choices(_ c: BankCandidates) -> some View {
        // Those within the bill's own bank-match days, unless none are.
        let anyNear = c.choices.contains { $0.withinDays }
        let shown = c.choices.filter { showAll || !anyNear || $0.withinDays }
        if c.choices.isEmpty {
            Text("No planned lines within 60 days of this one.").foregroundStyle(.secondary)
        } else {
            if c.choices.contains(where: { $0.recurringId != nil }) {
                Toggle("Always match “\(c.line.learnName)”", isOn: $remember)
                    .font(.footnote)
                    .disabled(!canWrite)
            }
            ForEach(shown) { choice in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choice.description).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(choice.amount.formatted).font(.subheadline.monospacedDigit())
                    }
                    Text("Planned \(choice.forecastDate.short) · \(words(choice))")
                        .font(.footnote).foregroundStyle(choice.sameDirection ? Color.secondary : Palette.warn)
                    Button { Task { await pay(choice) } } label: {
                        Text("Pay this").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(working || !canWrite)
                }
                .card()
            }
            let hidden = c.choices.count - shown.count
            if hidden > 0 {
                Button("Show \(hidden) more") { showAll = true }.font(.footnote)
            }
        }
    }

    /// How the bank's line compares, as the web app says it (_matchWords).
    private func words(_ d: BankCandidates.Choice) -> String {
        let amount: String
        if !d.sameDirection {
            amount = line.amount.isNegative ? "money out, not in" : "money in, not out"
        } else if d.amountDiff == .zero {
            amount = "same amount"
        } else {
            let bigger = abs(line.amount.amount) > abs(d.amount.amount)
            amount = "\(Money(abs(d.amountDiff.amount)).formatted) \(bigger ? "more" : "less")"
        }
        let n = abs(d.daysAfter)
        let days = n == 0 ? "same day" : "\(n) day\(n == 1 ? "" : "s") \(d.daysAfter < 0 ? "earlier" : "later")"
        return "\(amount) · \(days)"
    }

    private func load() async {
        guard let client = model.client else { return }
        do { candidates = try await client.bankCandidates(account: account, line: line.id) } catch { problem = AppModel.describe(error) }
    }

    private func pay(_ choice: BankCandidates.Choice) async {
        guard let client = model.client else { return }
        working = true
        defer { working = false }
        do {
            let result = try await client.bankMatch(account: account, line: line.id, to: choice,
                                                    remember: remember && choice.recurringId != nil)
            var said = "\(line.description) paid \(choice.description) (\(choice.forecastDate.short))"
            if result.alsoMatched > 0 {
                said += ", and \(result.alsoMatched) more line\(result.alsoMatched == 1 ? "" : "s") like it matched"
            }
            done(said + ".")
        } catch {
            problem = AppModel.describe(error)
        }
    }

    private func leave() async {
        guard let client = model.client else { return }
        working = true
        defer { working = false }
        do {
            try await client.bankLeave(account: account, line: line.id)
            done("Left \(line.description) as its own line.")
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

/// The Unmatched pill on a Forecast row, as the web app's.
struct UnmatchedPill: View {
    var body: some View {
        Text("Unmatched").font(.caption.weight(.semibold))
            .foregroundStyle(Palette.warn)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Palette.warn, lineWidth: 1))
            .accessibilityLabel("Unmatched: a line from your bank that paid no planned line yet")
    }
}
