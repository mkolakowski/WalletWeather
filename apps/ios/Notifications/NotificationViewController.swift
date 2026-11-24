import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI
import WalletWeatherKit

// A reminder's expanded view (Plans/outside-the-app.md, phase 2, #319). The
// reminder's own text never carries an amount; pressing and holding it shows
// this view, which reads the amount from the summary the app keeps for the
// widgets. While the phone is locked the summary can't be read, and while the
// app's lock is on amounts stay hidden, so either way the amount shows as
// •••• (decided 2026-11-23, docs/dev/decisions/ios-review.md).

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<ReminderDetailView>?

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        let detail = ReminderDetail.decide(info, read: { SummaryStore.shared?.read($0) ?? .missing },
                                           lockOn: OutsideSettings.shared.lockOn)
        let view = ReminderDetailView(detail: detail)
        if let host {
            host.rootView = view
            return
        }
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
        preferredContentSize = CGSize(width: self.view.bounds.width, height: 88)
    }
}

/// The amount a reminder is about, or •••• when it mustn't show.
struct ReminderDetailView: View {
    let detail: ReminderDetail

    private func day(_ day: LocalDay?) -> String {
        day.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch detail {
            case let .bill(name, amount, due):
                Text(name).font(.headline)
                HStack {
                    Text(amount).font(.title2.weight(.semibold)).monospacedDigit().privacySensitive()
                    Spacer()
                    Text("Due \(day(due))").foregroundStyle(.secondary)
                }
            case let .balance(account, low, date):
                Text(account).font(.headline)
                HStack {
                    Text(low).font(.title2.weight(.semibold)).monospacedDigit().privacySensitive()
                    Spacer()
                    Text("Forecast low, \(day(date))").foregroundStyle(.secondary)
                }
            case .none:
                Text("Open WalletWeather to see more.").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
