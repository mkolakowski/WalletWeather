import SwiftUI
import WalletWeatherKit

/// Email alerts on Settings → Bank sync, under the bank cards
/// (Plans/bank-alert-emails.md, phase 6, #211; decided 2026-11-24): the
/// mailbox's state in plain words and Check now, hidden for a read-only
/// sign-in. Connecting a mailbox and teaching senders stay in the web app. A
/// server without email alerts' status (older than 1.74.0) shows nothing; the
/// demo shows a sample and doesn't check.
struct MailAlertsCard: View {
    @Environment(AppModel.self) private var model
    private enum Load { case loading, none, failed(String), shown(MailStatus) }
    @State private var load = Load.loading
    @State private var checking = false
    /// What the last Check now said, or why it didn't work.
    @State private var outcome: String?
    @State private var outcomeFailed = false

    var body: some View {
        Group {
            switch load {
            case .none:
                EmptyView()
            case .loading:
                section { HStack(spacing: 8) { ProgressView(); Text("Checking email alerts…").foregroundStyle(.secondary) } }
            case let .failed(message):
                section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { Task { await refresh() } }.buttonStyle(.glass)
                }
            case let .shown(status):
                section { shown(status) }
            }
        }
        .task(id: model.generation) { await refresh() }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Email alerts")
            VStack(alignment: .leading, spacing: 8, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func shown(_ status: MailStatus) -> some View {
        let summary = status.summary(when: { KeptBar.when($0) })
        Label {
            Text(summary.headline).font(.subheadline.weight(.semibold))
        } icon: {
            switch summary.tone {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
            case .neutral: Image(systemName: "envelope")
            }
        }
        ForEach(summary.lines, id: \.self) { line in
            Text(line).font(.footnote).foregroundStyle(.secondary)
        }
        if let next = summary.next {
            Text(next).font(.footnote).foregroundStyle(.secondary)
        }
        if model.me?.isReadOnly != true, summary.canCheck {
            Button { Task { await checkNow() } } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView() }
                    Text("Check now").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .disabled(checking)
        }
        if let outcome {
            Text(outcome).font(.footnote).foregroundStyle(outcomeFailed ? Palette.bad : .secondary)
        }
    }

    private func refresh() async {
        guard let client = model.client, !model.isLocal else {
            load = .none
            return
        }
        do {
            load = try await client.mailStatus().map(Load.shown) ?? .none
        } catch {
            load = .failed(AppModel.describe(error))
        }
    }

    private func checkNow() async {
        outcome = nil
        if model.isDemo {
            outcome = "The demo can't check a mailbox: it saves nothing."
            outcomeFailed = false
            return
        }
        guard let client = model.client else { return }
        checking = true
        defer { checking = false }
        do {
            let result = try await client.checkMailNow()
            outcome = "Checked: \(result.said)"
            outcomeFailed = false
        } catch {
            // The server's own words say what went wrong (a check running, the mailbox's sign-in ended).
            if case let .server(_, detail) = error { outcome = detail } else { outcome = AppModel.describe(error) }
            outcomeFailed = true
        }
        await refresh()
    }
}
