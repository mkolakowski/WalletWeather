import Foundation

/// The moment the app shows things as of: the real time, always, except in a
/// Debug launch with `WW_DEBUG_TODAY=2026-11-15T10:00` (#352), which pins it
/// so that two sets of pictures taken on different days differ only where
/// the app does. Whatever is shown to a person as "today", "now" or "2 h
/// ago" reads `Date.appNow`; whatever is stored, sent or scheduled keeps the
/// real clock.
extension Date {
    /// Read once, from the launch settings, and never in a Release build.
    public static let pinnedNow: Date? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["WW_DEBUG_TODAY"].flatMap { pinned(from: $0) }
        #else
        return nil
        #endif
    }()

    public static var appNow: Date { pinnedNow ?? Date() }

    /// `2026-11-15` (at noon) or `2026-11-15T10:00`, in the phone's time zone.
    public static func pinned(from text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "T", maxSplits: 1)
        let day = parts.first.map { $0.split(separator: "-").compactMap { Int($0) } } ?? []
        let time = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [12, 0]
        guard day.count == 3, time.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1]))
    }
}
