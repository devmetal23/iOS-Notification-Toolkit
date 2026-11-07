import Foundation
import Testing
import ToolkitCore

private enum GroupingFixtures {
    static func calendar(_ timeZoneIdentifier: String) -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            preconditionFailure("Unknown time zone \(timeZoneIdentifier)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(_ iso: String) -> Date {
        guard let parsed = ISO8601DateFormatter().date(from: iso) else {
            preconditionFailure("Bad fixture date \(iso)")
        }
        return parsed
    }

    static func entry(_ id: NotificationEntry.ID, _ iso: String) -> NotificationEntry {
        entry(id, at: date(iso))
    }

    static func entry(_ id: NotificationEntry.ID, at receivedAt: Date) -> NotificationEntry {
        NotificationEntry(
            id: id,
            appKey: AppKey(appName: "Messages"),
            appName: "Messages",
            title: "Message \(id)",
            subtitle: "",
            body: "",
            receivedAt: receivedAt,
            capturedAt: receivedAt,
            isTimeSensitive: false
        )
    }
}

@Suite("DayGrouping")
struct DayGroupingTests {
    let newYork = GroupingFixtures.calendar("America/New_York")

    @Test("No entries, no sections")
    func empty() {
        #expect(DayGrouping.sections(for: [], calendar: newYork).isEmpty)
    }

    @Test("Newest day first, entries in input order")
    func groupsByDay() {
        let entries = [
            GroupingFixtures.entry(6, "2026-06-16T09:00:00-04:00"),
            GroupingFixtures.entry(5, "2026-06-16T00:00:00-04:00"),
            GroupingFixtures.entry(4, "2026-06-15T23:59:59-04:00"),
            GroupingFixtures.entry(3, "2026-06-15T08:00:00-04:00"),
            GroupingFixtures.entry(2, "2026-06-13T12:00:00-04:00"),
            GroupingFixtures.entry(1, "2026-06-13T12:00:00-04:00"),
        ]
        let sections = DayGrouping.sections(for: entries, calendar: newYork)
        #expect(sections.map(\.day) == [
            GroupingFixtures.date("2026-06-16T00:00:00-04:00"),
            GroupingFixtures.date("2026-06-15T00:00:00-04:00"),
            GroupingFixtures.date("2026-06-13T00:00:00-04:00"),
        ])
        #expect(sections.map { $0.entries.map(\.id) } == [[6, 5], [4, 3], [2, 1]])
        #expect(sections.map(\.id) == sections.map(\.day))
        #expect(sections.flatMap(\.entries) == entries)
    }

    @Test("Days follow the calendar's time zone")
    func timeZone() {
        let entries = [
            GroupingFixtures.entry(3, "2026-06-16T03:00:00Z"), // Jun 15 23:00 New York, Jun 16 12:00 Tokyo
            GroupingFixtures.entry(2, "2026-06-15T20:00:00Z"), // Jun 15 16:00 New York, Jun 16 05:00 Tokyo
            GroupingFixtures.entry(1, "2026-06-15T14:00:00Z"), // Jun 15 10:00 New York, Jun 15 23:00 Tokyo
        ]
        let inNewYork = DayGrouping.sections(for: entries, calendar: newYork)
        #expect(inNewYork.map(\.day) == [GroupingFixtures.date("2026-06-15T00:00:00-04:00")])
        #expect(inNewYork.map { $0.entries.map(\.id) } == [[3, 2, 1]])

        let inTokyo = DayGrouping.sections(for: entries, calendar: GroupingFixtures.calendar("Asia/Tokyo"))
        #expect(inTokyo.map(\.day) == [
            GroupingFixtures.date("2026-06-16T00:00:00+09:00"),
            GroupingFixtures.date("2026-06-15T00:00:00+09:00"),
        ])
        #expect(inTokyo.map { $0.entries.map(\.id) } == [[3, 2], [1]])
    }

    @Test("The 23-hour spring-forward day is one section")
    func springForward() {
        let entries = [
            GroupingFixtures.entry(5, "2026-03-08T23:30:00-04:00"),
            GroupingFixtures.entry(4, "2026-03-08T03:00:00-04:00"),
            GroupingFixtures.entry(3, "2026-03-08T01:59:00-05:00"),
            GroupingFixtures.entry(2, "2026-03-08T00:00:00-05:00"),
            GroupingFixtures.entry(1, "2026-03-07T23:59:00-05:00"),
        ]
        let sections = DayGrouping.sections(for: entries, calendar: newYork)
        #expect(sections.map(\.day) == [
            GroupingFixtures.date("2026-03-08T00:00:00-05:00"),
            GroupingFixtures.date("2026-03-07T00:00:00-05:00"),
        ])
        #expect(sections.map { $0.entries.map(\.id) } == [[5, 4, 3, 2], [1]])
    }

    @Test("The 25-hour fall-back day is one section")
    func fallBack() {
        let entries = [
            GroupingFixtures.entry(6, "2026-11-02T00:00:00-05:00"),
            GroupingFixtures.entry(5, "2026-11-01T23:30:00-05:00"),
            GroupingFixtures.entry(4, "2026-11-01T01:30:00-05:00"), // second 1:30
            GroupingFixtures.entry(3, "2026-11-01T01:30:00-04:00"), // first 1:30
            GroupingFixtures.entry(2, "2026-11-01T00:00:00-04:00"),
            GroupingFixtures.entry(1, "2026-10-31T23:59:59-04:00"),
        ]
        let sections = DayGrouping.sections(for: entries, calendar: newYork)
        #expect(sections.map(\.day) == [
            GroupingFixtures.date("2026-11-02T00:00:00-05:00"),
            GroupingFixtures.date("2026-11-01T00:00:00-04:00"),
            GroupingFixtures.date("2026-10-31T00:00:00-04:00"),
        ])
        #expect(sections.map { $0.entries.map(\.id) } == [[6], [5, 4, 3, 2], [1]])
    }

    @Test("Appending a later page and regrouping matches one big page")
    func paging() throws {
        // Every 5 hours back from Nov 2 across the fall-back day: 20 entries over 4 days.
        let newest = GroupingFixtures.date("2026-11-02T22:00:00-05:00")
        let all = (0..<20).map { index in
            GroupingFixtures.entry(NotificationEntry.ID(100 - index), at: newest.addingTimeInterval(-Double(index) * 5 * 60 * 60))
        }
        let whole = DayGrouping.sections(for: all, calendar: newYork)
        #expect(whole.map { $0.entries.count } == [5, 5, 5, 5])

        for split in 0...all.count {
            let firstPage = Array(all[..<split])
            let laterPage = Array(all[split...])
            let partial = DayGrouping.sections(for: firstPage, calendar: newYork)
            let regrouped = DayGrouping.sections(for: partial.flatMap(\.entries) + laterPage, calendar: newYork)
            #expect(regrouped == whole, "split at \(split)")

            // The first page's sections are the start of the full list: only its
            // last section may still be missing entries.
            try #require(partial.count <= whole.count, "split at \(split)")
            for (index, section) in partial.enumerated() {
                #expect(section.day == whole[index].day)
                if index < partial.count - 1 {
                    #expect(section == whole[index], "split at \(split)")
                } else {
                    #expect(Array(whole[index].entries.prefix(section.entries.count)) == section.entries, "split at \(split)")
                }
            }
        }
    }

    @Test("Each section's day is the start of its entries' day")
    func dayIsStartOfDay() {
        let newest = GroupingFixtures.date("2026-03-09T12:00:00-04:00")
        let entries = (0..<30).map { index in
            GroupingFixtures.entry(NotificationEntry.ID(30 - index), at: newest.addingTimeInterval(-Double(index) * 3 * 60 * 60))
        }
        let sections = DayGrouping.sections(for: entries, calendar: newYork)
        for section in sections {
            for entry in section.entries {
                #expect(newYork.startOfDay(for: entry.receivedAt) == section.day)
            }
        }
        #expect(Set(sections.map(\.id)).count == sections.count)
        #expect(sections.map(\.day) == sections.map(\.day).sorted(by: >))
    }

    @Test("Out-of-order input still gets one section per day")
    func outOfOrder() {
        let entries = [
            GroupingFixtures.entry(3, "2026-06-15T20:00:00-04:00"),
            GroupingFixtures.entry(9, "2026-06-16T08:00:00-04:00"),
            GroupingFixtures.entry(1, "2026-06-15T07:00:00-04:00"),
        ]
        let sections = DayGrouping.sections(for: entries, calendar: newYork)
        #expect(sections.map(\.day) == [
            GroupingFixtures.date("2026-06-16T00:00:00-04:00"),
            GroupingFixtures.date("2026-06-15T00:00:00-04:00"),
        ])
        #expect(sections.map { $0.entries.map(\.id) } == [[9], [3, 1]])
    }
}
