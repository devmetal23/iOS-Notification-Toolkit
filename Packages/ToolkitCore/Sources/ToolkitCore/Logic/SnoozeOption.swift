import Foundation

/// Snooze durations offered on every entry (FR-14).
public enum SnoozeOption: Hashable, Sendable, Identifiable {
    case fifteenMinutes
    case oneHour
    case threeHours
    /// `morningHour` o'clock on the next calendar day. Before 4 a.m. it means
    /// this morning: someone snoozing at 1 a.m. wants it back when they wake up.
    case tomorrowMorning
    /// Never earlier than one minute from now.
    case custom(Date)

    /// The four fixed choices, in menu order. `custom` is offered separately.
    public static let presets: [SnoozeOption] = [.fifteenMinutes, .oneHour, .threeHours, .tomorrowMorning]

    /// The earliest a custom snooze can fire, so it never comes back immediately.
    private static let minimumCustomDelay: TimeInterval = 60

    /// Before this wall-clock hour, "tomorrow morning" means later today.
    private static let sameDayCutoffHour = 4

    public var id: String {
        switch self {
        case .fifteenMinutes: "15m"
        case .oneHour: "1h"
        case .threeHours: "3h"
        case .tomorrowMorning: "tomorrow"
        case .custom(let date): "custom-\(Self.wholeSecondsSince1970(date))"
        }
    }

    /// When the snoozed notification should come back. Fixed intervals are
    /// elapsed time, so "3 hours" is 3 real hours even across a DST change.
    public func fireDate(from now: Date, calendar: Calendar, morningHour: Int) -> Date {
        switch self {
        case .fifteenMinutes: now.addingTimeInterval(15 * 60)
        case .oneHour: now.addingTimeInterval(60 * 60)
        case .threeHours: now.addingTimeInterval(3 * 60 * 60)
        case .tomorrowMorning: Self.morning(after: now, calendar: calendar, hour: morningHour)
        case .custom(let date): max(date, now.addingTimeInterval(Self.minimumCustomDelay))
        }
    }

    // MARK: - Private

    private static func wholeSecondsSince1970(_ date: Date) -> Int64 {
        // `exactly:` returns nil instead of trapping on a non-finite or huge value.
        Int64(exactly: date.timeIntervalSince1970.rounded(.down)) ?? 0
    }

    /// `hour` o'clock on the next calendar day, or today when the wall clock is
    /// before `sameDayCutoffHour`. Uses the wall-clock hour rather than elapsed
    /// time since midnight, which is off by an hour on DST days.
    private static func morning(after now: Date, calendar: Calendar, hour: Int) -> Date {
        let clampedHour = min(max(hour, 0), 23)
        let startOfToday = calendar.startOfDay(for: now)
        let firstDay = calendar.component(.hour, from: now) < sameDayCutoffHour ? 0 : 1
        // The second day only matters when this morning's hour has already passed
        // (a morning hour before the cutoff), so the snooze never fires in the past.
        for dayOffset in firstDay...(firstDay + 1) {
            if let candidate = date(atHour: clampedHour, daysAfter: dayOffset, startOfToday: startOfToday, calendar: calendar),
               candidate > now {
                return candidate
            }
        }
        return now.addingTimeInterval(24 * 60 * 60)
    }

    /// Built from date components so DST days get the right wall-clock time.
    private static func date(atHour hour: Int, daysAfter dayOffset: Int, startOfToday: Date, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { return nil }
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }
}
