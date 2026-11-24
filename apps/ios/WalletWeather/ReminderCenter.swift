import Observation
import UIKit
import UserNotifications
import WalletWeatherKit

/// Reminders worked out on the phone (Plans/outside-the-app.md, phase 2,
/// #319): Settings → Reminders' switches, and the local notifications they
/// schedule. What's scheduled is decided in WalletWeatherKit
/// (`ReminderPlan`); this asks iOS for permission, replaces what's
/// scheduled, and opens the right page when one is tapped.
///
/// Reminders follow the saved connection in front: switching to another
/// replaces them, signing out of it removes them, and the demo (also when the
/// lock brings it forward) leaves them as they were.
@MainActor @Observable
final class ReminderCenter {
    private(set) var settings: ReminderSettings
    /// iOS said no to notifications: the switches stay off, and the page
    /// says where to change it.
    private(set) var denied = false
    @ObservationIgnored private var state: ReminderState
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    /// The summary reminders were last worked out from, to work them out
    /// again when a switch changes.
    @ObservationIgnored private var lastSummary: ConnectionSummary?
    @ObservationIgnored private var hasFront = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = ReminderSettings.load(from: defaults)
        state = ReminderState.load(from: defaults)
        center.setNotificationCategories([UNNotificationCategory(identifier: ReminderPlan.category, actions: [],
                                                                 intentIdentifiers: [], options: [])])
        Task { await refreshPermission() }
    }

    /// Whether iOS still lets the app notify, for the page's note.
    func refreshPermission() async {
        let status = await center.notificationSettings().authorizationStatus
        denied = status == .denied
    }

    /// Changes the switches. Turning the first one on asks iOS for
    /// permission; if it's refused, nothing turns on.
    func change(_ edit: (inout ReminderSettings) -> Void) async {
        var next = settings
        edit(&next)
        if next.anyOn && !settings.anyOn {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshPermission()
            guard granted else { return }
        }
        settings = next
        settings.save(to: defaults)
        if hasFront { replan(lastSummary) }
    }

    /// Works the reminders out again from the connection in front's summary
    /// (nil: none in front, signed out, or a server set to Nothing) and
    /// replaces the bills and dips scheduled. A dip already told isn't
    /// cancelled on its way.
    func replan(_ summary: ConnectionSummary?) {
        lastSummary = summary
        hasFront = true
        let (planned, next) = ReminderPlan.make(summary, settings: settings, state: state)
        state = next
        state.save(to: defaults)
        let id = { (kind: PlannedReminder.Kind) in ReminderPlan.prefix + kind.rawValue + "." }
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            var gone = pending.filter { $0.hasPrefix(id(.bill)) }
            if !settings.balanceOn || summary == nil { gone += pending.filter { $0.hasPrefix(id(.balance)) } }
            center.removePendingNotificationRequests(withIdentifiers: gone)
            for reminder in planned { try? await center.add(Self.request(reminder)) }
        }
    }

    /// After bank sync on this iPhone: tells of new lines to match, once.
    func bankSynced(waiting: Int) {
        let (reminder, next) = ReminderPlan.bankLines(waiting, settings: settings, state: state)
        state = next
        state.save(to: defaults)
        if let reminder { Task { try? await center.add(Self.request(reminder)) } }
    }

    /// The notification for a reminder: its text has no amount, and its
    /// category opens the expanded view, which may show one.
    private static func request(_ reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = ReminderPlan.category
        content.threadIdentifier = reminder.kind.rawValue
        content.userInfo = reminder.userInfo
        let trigger: UNNotificationTrigger
        if let at = reminder.fireAt {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    /// The page a tapped reminder opens.
    static func opens(_ userInfo: [AnyHashable: Any]) -> WidgetOpen? {
        guard let kind = (userInfo["kind"] as? String).flatMap(PlannedReminder.Kind.init(rawValue:)) else { return nil }
        let connection = (userInfo["connection"] as? String).flatMap(UUID.init(uuidString:))
        let item = (userInfo["item"] as? String).flatMap { Int($0) }
        switch kind {
        case .bill: return WidgetOpen(page: .bills, connection: connection, account: nil)
        case .balance: return WidgetOpen(page: .forecast, connection: connection, account: item)
        case .bankLines: return WidgetOpen(page: .dashboard, connection: nil, account: nil)
        }
    }
}

/// Shows a reminder that arrives while the app is open, and opens its page
/// when one is tapped.
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Set by the app: where a tapped reminder goes.
    @MainActor static var open: ((WidgetOpen) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo as? [String: String] ?? [:]
        await MainActor.run {
            if let open = ReminderCenter.opens(info) { Self.open?(open) }
        }
    }
}
