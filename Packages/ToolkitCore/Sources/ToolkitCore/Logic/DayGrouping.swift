import Foundation

// CONTRACT STUB — workstream W2 replaces the bodies. Keep the public signatures.

/// Entries from one calendar day, for the timeline's day sections (FR-9).
public struct DaySection: Hashable, Sendable, Identifiable {
    /// Start of the day.
    public var day: Date
    /// Newest first.
    public var entries: [NotificationEntry]

    public var id: Date { day }

    public init(day: Date, entries: [NotificationEntry]) {
        self.day = day
        self.entries = entries
    }
}

public enum DayGrouping {
    /// Groups newest-first entries into day sections, newest day first. Appending
    /// a later page and regrouping must yield the same sections as one big page.
    public static func sections(for entries: [NotificationEntry], calendar: Calendar) -> [DaySection] {
        fatalError("W2: not implemented")
    }
}
