import Foundation
import Testing
import ToolkitCore

@Suite("Store: daily counts")
struct StoreStatsTests {
    @Test func countsAreBucketedByDayInTheCalendarsTimeZone() throws {
        let store = try SQLiteNotificationStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        // Los Angeles switches to daylight time on 8 March 2026, a 23-hour day. A
        // fixed UTC-8 offset (if the time zone database is missing) still tests
        // that the calendar's zone, not UTC, decides the day.
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -8 * 3_600)!

        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)))
        }

        let samples: [(app: String, date: Date)] = try [
            ("Messages", date(6, 12)), // before the interval
            ("Messages", date(7, 23, 30)), // 07:30 UTC on the 8th
            ("Messages", date(8, 0, 30)),
            ("Messages", date(8, 3, 30)),
            ("Slack", date(8, 12)),
            ("Slack", date(9, 0)), // first instant of the 9th
            ("Slack", date(10, 0)), // after the interval
        ]
        for (index, sample) in samples.enumerated() {
            try TestSupport.insert(TestSupport.notification(app: sample.app, body: "n\(index)", at: sample.date), into: store)
        }
        let interval = try DateInterval(start: date(7, 0), end: date(9, 23, 59))

        let counts = try store.dailyCounts(in: interval, calendar: calendar)

        let messages = AppKey(appName: "Messages")
        let slack = AppKey(appName: "Slack")
        let day7 = try calendar.startOfDay(for: date(7, 12))
        let day8 = try calendar.startOfDay(for: date(8, 12))
        let day9 = try calendar.startOfDay(for: date(9, 12))
        let midnight7 = try date(7, 0)
        let midnight9 = try date(9, 0)
        #expect(day7 == midnight7 && day9 == midnight9)
        #expect(counts == [
            DailyAppCount(day: day7, appKey: messages, appName: "Messages", count: 1),
            DailyAppCount(day: day8, appKey: messages, appName: "Messages", count: 2),
            DailyAppCount(day: day8, appKey: slack, appName: "Slack", count: 1),
            DailyAppCount(day: day9, appKey: slack, appName: "Slack", count: 1),
        ])
    }

    @Test func countsUseTheTrackedNameOrTheLatestEntryName() throws {
        let store = try SQLiteNotificationStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = TestSupport.referenceDate
        try store.registerApp(displayName: "WhatsApp", catalogID: "whatsapp", at: start)
        try TestSupport.insert(TestSupport.notification(app: "whatsapp", body: "1", at: start), into: store)
        try TestSupport.insert(TestSupport.notification(app: "slack", body: "2", at: start), into: store)
        try TestSupport.insert(TestSupport.notification(app: "Slack", body: "3", at: start + 1), into: store)
        try store.removeApp(AppKey(appName: "Slack"))

        let counts = try store.dailyCounts(in: DateInterval(start: start - 60, duration: 120), calendar: calendar)

        #expect(counts.map(\.appName) == ["Slack", "WhatsApp"])
        #expect(counts.map(\.count) == [2, 1])
        #expect(try store.dailyCounts(in: DateInterval(start: start + 60, duration: 60), calendar: calendar).isEmpty)
    }
}
