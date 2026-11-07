import Foundation
import Testing
import ToolkitCore

/// "Tomorrow morning" from `now` in `timeZone`. Dates are ISO 8601 with offsets,
/// so fall-back times like the two 1:30s on 2026-11-01 are unambiguous.
struct SnoozeMorningCase: Sendable, CustomTestStringConvertible {
    let name: String
    let timeZone: String
    let now: String
    let morningHour: Int
    let expected: String

    var testDescription: String { name }
}

/// A fixed interval, which is elapsed time even across a DST change.
struct SnoozeIntervalCase: Sendable, CustomTestStringConvertible {
    let name: String
    let option: SnoozeOption
    let now: String
    let expected: String

    var testDescription: String { name }
}

private enum SnoozeFixtures {
    static func date(_ iso: String) -> Date {
        guard let parsed = ISO8601DateFormatter().date(from: iso) else {
            preconditionFailure("Bad fixture date \(iso)")
        }
        return parsed
    }

    static func calendar(_ timeZoneIdentifier: String) -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            preconditionFailure("Unknown time zone \(timeZoneIdentifier)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

@Suite("SnoozeOption")
struct SnoozeOptionTests {
    // America/New_York: clocks go forward 2026-03-08 02:00 and back 2026-11-01 02:00.
    static let morningCases: [SnoozeMorningCase] = [
        SnoozeMorningCase(name: "Evening before spring forward", timeZone: "America/New_York",
                          now: "2026-03-07T22:00:00-05:00", morningHour: 8, expected: "2026-03-08T08:00:00-04:00"),
        SnoozeMorningCase(name: "1:30 on the spring-forward day means today", timeZone: "America/New_York",
                          now: "2026-03-08T01:30:00-05:00", morningHour: 8, expected: "2026-03-08T08:00:00-04:00"),
        SnoozeMorningCase(name: "3:30 EDT on the spring-forward day means today", timeZone: "America/New_York",
                          now: "2026-03-08T03:30:00-04:00", morningHour: 8, expected: "2026-03-08T08:00:00-04:00"),
        // Only 3.5 elapsed hours after midnight, but the wall clock says 4:30.
        SnoozeMorningCase(name: "4:30 EDT on the spring-forward day means tomorrow", timeZone: "America/New_York",
                          now: "2026-03-08T04:30:00-04:00", morningHour: 8, expected: "2026-03-09T08:00:00-04:00"),
        SnoozeMorningCase(name: "Evening before fall back", timeZone: "America/New_York",
                          now: "2026-10-31T21:00:00-04:00", morningHour: 8, expected: "2026-11-01T08:00:00-05:00"),
        SnoozeMorningCase(name: "First 1:30 on the fall-back day", timeZone: "America/New_York",
                          now: "2026-11-01T01:30:00-04:00", morningHour: 8, expected: "2026-11-01T08:00:00-05:00"),
        SnoozeMorningCase(name: "Second 1:30 on the fall-back day", timeZone: "America/New_York",
                          now: "2026-11-01T01:30:00-05:00", morningHour: 8, expected: "2026-11-01T08:00:00-05:00"),
        // 4.5 elapsed hours after midnight, but the wall clock says 3:30.
        SnoozeMorningCase(name: "3:30 EST on the fall-back day means today", timeZone: "America/New_York",
                          now: "2026-11-01T03:30:00-05:00", morningHour: 8, expected: "2026-11-01T08:00:00-05:00"),
        SnoozeMorningCase(name: "4:00 on the fall-back day means tomorrow", timeZone: "America/New_York",
                          now: "2026-11-01T04:00:00-05:00", morningHour: 8, expected: "2026-11-02T08:00:00-05:00"),
        SnoozeMorningCase(name: "Midnight", timeZone: "America/New_York",
                          now: "2026-06-15T00:00:00-04:00", morningHour: 8, expected: "2026-06-15T08:00:00-04:00"),
        SnoozeMorningCase(name: "One second before 4:00", timeZone: "America/New_York",
                          now: "2026-06-15T03:59:59-04:00", morningHour: 8, expected: "2026-06-15T08:00:00-04:00"),
        SnoozeMorningCase(name: "4:00 exactly", timeZone: "America/New_York",
                          now: "2026-06-15T04:00:00-04:00", morningHour: 8, expected: "2026-06-16T08:00:00-04:00"),
        SnoozeMorningCase(name: "After the morning hour", timeZone: "America/New_York",
                          now: "2026-06-15T09:15:00-04:00", morningHour: 8, expected: "2026-06-16T08:00:00-04:00"),
        SnoozeMorningCase(name: "Morning hour from settings", timeZone: "America/New_York",
                          now: "2026-06-15T13:00:00-04:00", morningHour: 7, expected: "2026-06-16T07:00:00-04:00"),
        SnoozeMorningCase(name: "New Year's Eve", timeZone: "America/New_York",
                          now: "2026-12-31T23:30:00-05:00", morningHour: 8, expected: "2027-01-01T08:00:00-05:00"),
        SnoozeMorningCase(name: "Tokyo", timeZone: "Asia/Tokyo",
                          now: "2026-03-08T23:00:00+09:00", morningHour: 6, expected: "2026-03-09T06:00:00+09:00"),
        SnoozeMorningCase(name: "London the night clocks go forward", timeZone: "Europe/London",
                          now: "2026-03-28T20:00:00+00:00", morningHour: 10, expected: "2026-03-29T10:00:00+01:00"),
        SnoozeMorningCase(name: "Never in the past when the morning hour is before 4", timeZone: "America/New_York",
                          now: "2026-06-15T03:30:00-04:00", morningHour: 3, expected: "2026-06-16T03:00:00-04:00"),
    ]

    static let intervalCases: [SnoozeIntervalCase] = [
        SnoozeIntervalCase(name: "15 minutes", option: .fifteenMinutes,
                           now: "2026-06-15T12:00:00Z", expected: "2026-06-15T12:15:00Z"),
        SnoozeIntervalCase(name: "1 hour", option: .oneHour,
                           now: "2026-06-15T12:00:00Z", expected: "2026-06-15T13:00:00Z"),
        SnoozeIntervalCase(name: "3 hours", option: .threeHours,
                           now: "2026-06-15T12:00:00Z", expected: "2026-06-15T15:00:00Z"),
        SnoozeIntervalCase(name: "1 hour across spring forward", option: .oneHour,
                           now: "2026-03-08T01:30:00-05:00", expected: "2026-03-08T03:30:00-04:00"),
        SnoozeIntervalCase(name: "3 hours across spring forward", option: .threeHours,
                           now: "2026-03-08T00:30:00-05:00", expected: "2026-03-08T04:30:00-04:00"),
        SnoozeIntervalCase(name: "15 minutes across fall back", option: .fifteenMinutes,
                           now: "2026-11-01T01:50:00-04:00", expected: "2026-11-01T01:05:00-05:00"),
        SnoozeIntervalCase(name: "1 hour across fall back", option: .oneHour,
                           now: "2026-11-01T01:30:00-04:00", expected: "2026-11-01T01:30:00-05:00"),
        SnoozeIntervalCase(name: "3 hours across fall back", option: .threeHours,
                           now: "2026-11-01T00:30:00-04:00", expected: "2026-11-01T02:30:00-05:00"),
    ]

    @Test("Tomorrow morning uses the wall clock", arguments: SnoozeOptionTests.morningCases)
    func tomorrowMorning(_ testCase: SnoozeMorningCase) {
        let fireDate = SnoozeOption.tomorrowMorning.fireDate(
            from: SnoozeFixtures.date(testCase.now),
            calendar: SnoozeFixtures.calendar(testCase.timeZone),
            morningHour: testCase.morningHour
        )
        #expect(fireDate == SnoozeFixtures.date(testCase.expected))
    }

    @Test("Fixed intervals are elapsed time", arguments: SnoozeOptionTests.intervalCases)
    func fixedIntervals(_ testCase: SnoozeIntervalCase) {
        let fireDate = testCase.option.fireDate(
            from: SnoozeFixtures.date(testCase.now),
            calendar: SnoozeFixtures.calendar("America/New_York"),
            morningHour: 8
        )
        #expect(fireDate == SnoozeFixtures.date(testCase.expected))
    }

    @Test("Fixed intervals don't depend on the calendar")
    func intervalsIgnoreCalendar() {
        let now = SnoozeFixtures.date("2026-03-08T01:30:00-05:00")
        for identifier in ["America/New_York", "Asia/Tokyo", "UTC"] {
            let calendar = SnoozeFixtures.calendar(identifier)
            #expect(SnoozeOption.fifteenMinutes.fireDate(from: now, calendar: calendar, morningHour: 8) == now.addingTimeInterval(900))
            #expect(SnoozeOption.oneHour.fireDate(from: now, calendar: calendar, morningHour: 8) == now.addingTimeInterval(3_600))
            #expect(SnoozeOption.threeHours.fireDate(from: now, calendar: calendar, morningHour: 8) == now.addingTimeInterval(10_800))
        }
    }

    @Test("Custom dates are kept unless sooner than a minute from now")
    func customDate() {
        let now = SnoozeFixtures.date("2026-06-15T12:00:00Z")
        let calendar = SnoozeFixtures.calendar("America/New_York")
        let later = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(SnoozeOption.custom(later).fireDate(from: now, calendar: calendar, morningHour: 8) == later)
        #expect(SnoozeOption.custom(now.addingTimeInterval(60)).fireDate(from: now, calendar: calendar, morningHour: 8)
            == now.addingTimeInterval(60))
        #expect(SnoozeOption.custom(now.addingTimeInterval(30)).fireDate(from: now, calendar: calendar, morningHour: 8)
            == now.addingTimeInterval(60))
        #expect(SnoozeOption.custom(now).fireDate(from: now, calendar: calendar, morningHour: 8) == now.addingTimeInterval(60))
        #expect(SnoozeOption.custom(now.addingTimeInterval(-3_600)).fireDate(from: now, calendar: calendar, morningHour: 8)
            == now.addingTimeInterval(60))
    }

    @Test("Preset IDs and order")
    func presetIDs() {
        #expect(SnoozeOption.presets == [.fifteenMinutes, .oneHour, .threeHours, .tomorrowMorning])
        #expect(SnoozeOption.presets.map(\.id) == ["15m", "1h", "3h", "tomorrow"])
    }

    @Test("Custom IDs use whole seconds since 1970")
    func customIDs() {
        #expect(SnoozeOption.custom(Date(timeIntervalSince1970: 1_772_951_400)).id == "custom-1772951400")
        #expect(SnoozeOption.custom(Date(timeIntervalSince1970: 1_772_951_400.75)).id == "custom-1772951400")
        #expect(SnoozeOption.custom(Date(timeIntervalSince1970: 0)).id == "custom-0")
        let ids = Set((SnoozeOption.presets + [.custom(Date(timeIntervalSince1970: 1_772_951_400))]).map(\.id))
        #expect(ids.count == 5)
    }
}
