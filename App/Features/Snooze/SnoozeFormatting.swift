import Foundation
import ToolkitCore

extension SnoozeOption {
    /// The one title for this option in every snooze menu and dialog, e.g.
    /// "15 Minutes" or "Tomorrow, 8:00 AM". Pass `settings.morningHour`.
    func displayTitle(morningHour: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .fifteenMinutes:
            return String(localized: "15 Minutes")
        case .oneHour:
            return String(localized: "1 Hour")
        case .threeHours:
            return String(localized: "3 Hours")
        case .tomorrowMorning:
            let date = fireDate(from: now, calendar: calendar, morningHour: morningHour)
            let time = date.formatted(date: .omitted, time: .shortened)
            return String(localized: "Tomorrow, \(time)")
        case .custom(let date):
            return SnoozeFormatting.fireTimeText(date, now: now, calendar: calendar)
        }
    }
}

/// User-facing text for snooze times (FR-14, FR-15).
enum SnoozeFormatting {
    /// When a snooze comes back, compactly: "3:15 PM", "Tomorrow, 8:00 AM" or
    /// "Mon, Nov 9, 8:00 AM".
    static func fireTimeText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if isTomorrow(date, now: now, calendar: calendar) {
            return String(localized: "Tomorrow, \(time)")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// Spoken and shown after snoozing: "Snoozed until 3:15 PM".
    static func confirmation(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Snoozed until \(time)")
        }
        if isTomorrow(date, now: now, calendar: calendar) {
            return String(localized: "Snoozed until tomorrow at \(time)")
        }
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return String(localized: "Snoozed until \(day) at \(time)")
    }

    private static func isTomorrow(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }
}
