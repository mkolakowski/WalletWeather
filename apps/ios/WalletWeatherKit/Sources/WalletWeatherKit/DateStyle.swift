import Foundation

/// How the app writes a calendar day to the person (#296): the web app's
/// two ways, `short` ("Nov 12") and `iso` ("2026-11-12"). Requests and
/// storage always use `LocalDay.description` (`yyyy-MM-dd`), whatever this
/// says.
public enum DateStyle: String, Sendable, Equatable {
    case short, iso

    /// The server's `date_format` from `/api/me`: iso, or short for
    /// "short", nil and anything it adds later.
    public init(server: String?) {
        self = server == "iso" ? .iso : .short
    }
}

/// Settings → Dates & display → Date format: Follow the web app, Nov 12 or
/// 2026-11-12. The raw values are stored in the app's preferences
/// (`dates.format`).
public enum DateFormatChoice: String, CaseIterable, Identifiable, Sendable {
    case follow, short, iso

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .follow: "Follow the web app"
        case .short: "Nov 12"
        case .iso: "2026-11-12"
        }
    }

    /// What the page writes for this choice: an explicit one beats the
    /// server's; Follow the web app takes the server's `date_format`, and
    /// is short when there's none (an older server, or no server).
    public func style(server: String?) -> DateStyle {
        switch self {
        case .follow: DateStyle(server: server)
        case .short: .short
        case .iso: .iso
        }
    }

    /// The choices offered: Follow the web app only with a server.
    public static func offered(hasServer: Bool) -> [DateFormatChoice] {
        hasServer ? allCases : [.short, .iso]
    }
}

/// The style the app prints days in, set by the app when the setting or the
/// server's answer changes (as `Palette.look` is for colours); the root
/// rebuilds the pages so every date is written again.
public enum DateDisplay {
    nonisolated(unsafe) public static var style: DateStyle = .short
}

extension LocalDay {
    /// This day written for the person: "Nov 12", with the year when it
    /// isn't `today`'s ("Nov 12, 2025"), or "2026-11-12" always.
    public func display(_ style: DateStyle, today: LocalDay = .today(), locale: Locale = .current) -> String {
        switch style {
        case .iso:
            return description
        case .short:
            let format = year == today.year
                ? Date.FormatStyle().month(.abbreviated).day()
                : Date.FormatStyle().month(.abbreviated).day().year()
            return date.formatted(format.locale(locale))
        }
    }

    /// The calendar day of a moment (a sync time, a last-updated stamp),
    /// written as `short` is, in the style the app has set; the year is
    /// added when it isn't `now`'s.
    public static func display(of moment: Date, now: Date = .now, style: DateStyle = DateDisplay.style,
                               locale: Locale = .current) -> String {
        today(now: moment).display(style, today: today(now: now), locale: locale)
    }

    /// Every date shown to the person: "Nov 3", "Nov 3, 2025" or
    /// "2026-11-03", by Date format in Settings → Dates & display.
    public var short: String { display(DateDisplay.style) }
}
