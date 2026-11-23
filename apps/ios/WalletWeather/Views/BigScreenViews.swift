import SwiftUI
import WalletWeatherKit

// The Duo's big screen (Plans/ios-app.md, phase 4, #90).

// MARK: - To confirm

/// A line still to confirm, made for ticking off with your bank's app open
/// beside WalletWeather: Paid as planned in one tap, or the amount it really
/// came to and Paid; Edit opens it in the editor (#157), and it swipes like
/// any other line.
struct ConfirmRow: View {
    let line: ForecastLine
    let onEdit: () -> Void
    let onConfirm: (String?) async -> Void

    @State private var amount = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.description).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(line.plannedAmount.formatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(line.plannedAmount.isNegative ? Palette.bad : Palette.good)
            }
            HStack {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Edit", systemImage: "pencil", action: onEdit)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(line.description)")
            }
            HStack(spacing: 8) {
                Button {
                    Task { await run(nil) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Paid as planned")
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.good)
                Spacer(minLength: 4)
                TextField(amountString(abs(line.plannedAmount.amount)), text: $amount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
                    .frame(minWidth: 56, maxWidth: 96)
                    .accessibilityLabel("Different amount for \(line.description)")
                Button("Paid") { Task { await run(amount) } }
                    .buttonStyle(.glass)
                    .disabled(parseAmount(amount) == nil)
                    .accessibilityLabel("Paid at the amount typed")
            }
            .disabled(saving)
        }
        .card()
    }

    private var subtitle: String {
        let due = line.plannedDate.map { "Due \($0.short)" } ?? ""
        return [due, line.category].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func run(_ typed: String?) async {
        saving = true
        await onConfirm(typed)
        saving = false
        amount = ""
    }
}

// MARK: - A second window

/// "Open in new window" in a page's menu, where the phone can show two
/// WalletWeather windows side by side (the Duo's inner screen). The new
/// window opens on this page and then goes its own way.
struct NewWindowItem: ToolbarContent {
    let place: RootView.Place
    /// Offered whatever the width here: Settings' pane is set to a compact
    /// width inside a wide window (#295).
    var wideWindow = false
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some ToolbarContent {
        if supportsMultipleWindows && (sizeClass == .regular || wideWindow) {
            ToolbarItem(placement: .secondaryAction) {
                Button("Open in new window", systemImage: "macwindow.badge.plus") { openWindow(value: place) }
            }
        }
    }
}

// MARK: - Compare

/// Two accounts, or one account in two months, side by side on the open
/// Duo, one in each half: each side picks its account and month, and the
/// lines line up by day of the month, so both sides scroll together. Nothing
/// sits on the fold between them: half open like a book, the gap is the
/// fold's band (#304). Read-only: a line is changed in Forecast.
struct CompareView: View {
    struct Side: Equatable {
        var accountId: Int
        var month: YearMonth
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    @State var left: Side
    @State var right: Side
    @State private var leftMonth: Loadable<ForecastMonth> = .loading
    @State private var rightMonth: Loadable<ForecastMonth> = .loading
    @State private var kept = KeptTracker()

    var body: some View {
        NavigationStack {
            content
                .keptBar(kept)
                .background(PageBackground().ignoresSafeArea())
                .navigationTitle("Compare")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: left) { leftMonth = await load(left) }
        .task(id: right) { rightMonth = await load(right) }
    }

    @ViewBuilder
    private var content: some View {
        switch (leftMonth, rightMonth) {
        case (.failed(let error), _), (_, .failed(let error)):
            ProblemView(error: error) { Task { leftMonth = await load(left); rightMonth = await load(right) } }
        case (.loaded(let l), .loaded(let r)):
            // The two sides scroll together in every pose, so they share one
            // scroll view rather than `FoldLayout`'s two panes; they take its
            // arithmetic (#304): lying flat (or half open like a laptop) two
            // equal columns 56 points apart, half open like a book one column
            // either side of the fold's band.
            FoldReader { size, band in
                let panes = FoldPanes.layout(size: size, band: band.isUpright ? band : .flat)
                let leftWidth = max(0, panes.leading.width - panes.leadingEdges.leading - panes.leadingEdges.trailing)
                let rightWidth = max(0, panes.trailing.width - panes.trailingEdges.leading - panes.trailingEdges.trailing)
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: panes.gap) {
                            SideHeader(accounts: accounts, side: $left, data: l).frame(width: leftWidth)
                            SideHeader(accounts: accounts, side: $right, data: r).frame(width: rightWidth)
                        }
                        LazyVStack(spacing: 8) {
                            ForEach(Compare.days(left: l.rows, right: r.rows)) { day in
                                HStack(alignment: .top, spacing: panes.gap) {
                                    dayColumn(day.day, lines: day.left, month: l, side: left).frame(width: leftWidth)
                                    dayColumn(day.day, lines: day.right, month: r, side: right).frame(width: rightWidth)
                                }
                                .fixedSize(horizontal: false, vertical: true)  // both cells as tall as the taller
                            }
                        }
                    }
                    .padding(.leading, panes.leadingEdges.leading).padding(.trailing, panes.trailingEdges.trailing)
                    .padding(.bottom, 24)
                }
            }
        default:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One side's lines on a day, and its balance after them; an empty day
    /// keeps its place so the two sides stay level.
    private func dayColumn(_ day: Int, lines: [ForecastLine], month data: ForecastMonth, side: Side) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(side.month.day(day)?.short ?? "\(day)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let balance = Compare.balance(through: day, in: data)
                Text(balance.formatted).font(.caption.monospacedDigit()).foregroundStyle(Palette.amount(balance.isNegative))
            }
            if lines.isEmpty {
                Text("Nothing").font(.footnote).foregroundStyle(.tertiary)
            }
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    PaidMark(line: line, today: .today()).font(.caption)
                    Text(line.description).font(.footnote).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(line.amount.formatted).font(.footnote.monospacedDigit())
                        .foregroundStyle(line.amount.isNegative ? Palette.bad : Palette.good)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.row ?? Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func load(_ side: Side) async -> Loadable<ForecastMonth> {
        guard let client = model.client(kept) else { return .loading }
        do {
            return .loaded(try await client.forecast(account: side.accountId, month: side.month))
        } catch {
            return .failed(error)
        }
    }
}

/// A side's account and month, and its balances.
private struct SideHeader: View {
    let accounts: [Account]
    @Binding var side: CompareView.Side
    let data: ForecastMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Picker("Account", selection: $side.accountId) {
                    ForEach(accounts) { Text($0.name).tag($0.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(accounts.first { $0.id == side.accountId }?.name ?? "").font(.headline)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            MonthBar(month: side.month, font: .subheadline.weight(.semibold),
                     onMove: { side.month = $0 < 0 ? side.month.previous : side.month.next },
                     onPick: { side.month = $0 })
            HStack {
                figure("Starts", data.openingBalance)
                figure("Forecast end", data.forecastEndingBalance)
            }
        }
        .card()
    }

    private func figure(_ label: String, _ value: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(label)
            Text(value.formatted).font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
