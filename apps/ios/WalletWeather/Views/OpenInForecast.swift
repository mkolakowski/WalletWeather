import SwiftUI
import WalletWeatherKit

// An account opens in Forecast wherever it's shown (duo-more phase 2, #305):
// one route for the Dashboard, Net worth, the Calendar and Search, the one
// Search already took (#112): ask Forecast for the account, then go to its
// tab, or, when Forecast isn't in the tab bar, push it on the page's own stack.

extension EnvironmentValues {
    /// Opens an account in Forecast, on its To confirm list when asked. A no-op
    /// outside a page that has `.opensForecast()`.
    @Entry var openInForecast: @MainActor (_ account: Int, _ toConfirm: Bool) -> Void = { _, _ in }
}

extension View {
    /// Gives the page `\.openInForecast`, and a place to push Forecast when
    /// it isn't in the tab bar. Goes on the page's content, inside its stack.
    func opensForecast() -> some View { modifier(OpensForecast()) }
}

private struct OpensForecast: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openPlace) private var openPlace
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .environment(\.openInForecast) { account, toConfirm in
                model.forecastRequest = account
                model.forecastToConfirm = toConfirm
                if settings.tabs.contains(.forecast) {
                    openPlace(.forecast)
                } else {
                    pushed = true
                }
            }
            .navigationDestination(isPresented: $pushed) { TabPage.forecast.view(embedded: true) }
    }
}

/// A "Forecast ›" hint at the end of a row that opens an account in Forecast.
struct ForecastHint: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("Forecast")
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// A button that opens an account in Forecast (or its To confirm list).
/// A view of its own so it reads `\.openInForecast` from the page's
/// `.opensForecast()`, which the page itself can't.
struct OpenInForecastButton<Label: View>: View {
    @Environment(\.openInForecast) private var open
    let account: Int
    var toConfirm = false
    @ViewBuilder let label: Label

    var body: some View {
        Button { open(account, toConfirm) } label: { label }
    }
}
