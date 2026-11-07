import Foundation

// CONTRACT STUB — workstream W2 replaces the bodies. Keep the public signatures.

/// Snooze durations offered on every entry (FR-14).
public enum SnoozeOption: Hashable, Sendable, Identifiable {
    case fifteenMinutes
    case oneHour
    case threeHours
    /// `morningHour` o'clock on the next calendar day.
    case tomorrowMorning
    case custom(Date)

    /// The four fixed choices, in menu order. `custom` is offered separately.
    public static let presets: [SnoozeOption] = [.fifteenMinutes, .oneHour, .threeHours, .tomorrowMorning]

    public var id: String {
        fatalError("W2: not implemented")
    }

    /// When the snoozed notification should come back.
    public func fireDate(from now: Date, calendar: Calendar, morningHour: Int) -> Date {
        fatalError("W2: not implemented")
    }
}
