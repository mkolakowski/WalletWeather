import SwiftUI
import WalletWeatherKit
import WidgetKit

// The widgets (Plans/outside-the-app.md, phase 1, #318). Each names its
// connection, opens the page it shows when tapped, and goes on the Home
// Screen (small, medium; the small one in StandBy too) and the Lock Screen
// (rectangular, inline, circular). The kinds are stable: never rename them.

@main
struct WalletWeatherWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        NextBillsWidget()
        ToConfirmWidget()
    }
}

private let families: [WidgetFamily] = [
    .systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular,
]

struct BalanceWidget: Widget {
    static let kind = "net.iptater.walletweather.balance"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: BalanceConfiguration.self, provider: BalanceProvider()) { entry in
            BalanceView(entry: entry)
        }
        .configurationDisplayName("Balance")
        .description("One account's balance and the month's low.")
        .supportedFamilies(families)
    }
}

struct NextBillsWidget: Widget {
    static let kind = "net.iptater.walletweather.next-bills"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ConnectionConfiguration.self, provider: ConnectionProvider()) { entry in
            NextBillsView(entry: entry)
        }
        .configurationDisplayName("Next bills")
        .description("The next three bills, with their dates and amounts.")
        .supportedFamilies(families)
    }
}

struct ToConfirmWidget: Widget {
    static let kind = "net.iptater.walletweather.to-confirm"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ConnectionConfiguration.self, provider: ConnectionProvider()) { entry in
            ToConfirmView(entry: entry)
        }
        .configurationDisplayName("To confirm")
        .description("How many lines wait to be confirmed.")
        .supportedFamilies(families)
    }
}
