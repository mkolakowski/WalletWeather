import SwiftUI
import WalletWeatherKit

/// The Important notice, shown once at first sign-in as the web app shows it.
/// The wording is decided (docs/dev/decisions/legal-risk.md) and matches the
/// web app's `#noticeText` and the README's Disclaimer: change all of them
/// together.
struct NoticeView: View {
    @Environment(AppModel.self) private var model
    @State private var saving = false
    @State private var error: String?

    static let paragraphs: [LocalizedStringKey] = [
        "WalletWeather is a planning tool. Its forecasts are estimates calculated from data you enter and may be inaccurate or incomplete.",
        "WalletWeather does not provide financial, tax, legal or investment advice. You are solely responsible for decisions you make using it.",
        "The software is provided \"as is\", without warranty of any kind, and its authors accept no liability for losses arising from its use. See the [MIT licence](https://github.com/mkolakowski/WalletWeather/blob/main/LICENSE).",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Important notice").font(.title2.bold())
                ForEach(Self.paragraphs.indices, id: \.self) { i in
                    Text(Self.paragraphs[i])
                }
                if let error {
                    Text(error).foregroundStyle(Palette.bad).font(.callout)
                }
                Button {
                    Task { await agree() }
                } label: {
                    HStack {
                        if saving { ProgressView() }
                        Text("I understand and agree").frame(maxWidth: .infinity)
                    }
                    .font(.headline).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(saving)
                Button("Sign out") { Task { await model.signOutEndingToken() } }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.glass)
            }
            .card()
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(PageBackground().ignoresSafeArea())
    }

    private func agree() async {
        saving = true
        defer { saving = false }
        do {
            try await model.acknowledgeNotice()
        } catch {
            self.error = "Couldn't save that. \(error.message)"
        }
    }
}
