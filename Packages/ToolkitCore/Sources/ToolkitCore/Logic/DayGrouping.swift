import Foundation

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
    ///
    /// Days are `calendar.startOfDay(for: receivedAt)`, so they follow the
    /// calendar's time zone, including 23- and 25-hour DST days. Entries keep
    /// their input order within a section. Each day gets exactly one section even
    /// if the input is not strictly ordered, so section IDs stay unique.
    public static func sections(for entries: [NotificationEntry], calendar: Calendar) -> [DaySection] {
        var sections: [DaySection] = []
        var sectionIndexByDay: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.receivedAt)
            if let index = sectionIndexByDay[day] {
                sections[index].entries.append(entry)
            } else {
                sectionIndexByDay[day] = sections.count
                sections.append(DaySection(day: day, entries: [entry]))
            }
        }
        return sections.sorted { $0.day > $1.day }
    }
}
