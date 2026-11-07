import Foundation
import ToolkitCore

/// Per-app notification counts for the Stats screen (FR-19), built from the store's
/// daily counts: the last 7 days by day, the last 8 weeks by week, and today.
struct StatsSummary: Hashable, Sendable {
    /// Notifications from one series (an app, or "Other") in one day or week.
    struct Bar: Identifiable, Hashable, Sendable {
        var start: Date
        var series: String
        var count: Int

        var id: String { "\(start.timeIntervalSinceReferenceDate)|\(series)" }
    }

    struct AppCount: Identifiable, Hashable, Sendable {
        var appKey: AppKey
        var appName: String
        var count: Int

        var id: AppKey { appKey }
    }

    struct Period: Hashable, Sendable {
        /// Ordered by start, then by `StatsSummary.series`, so stacks match the legend.
        var bars: [Bar]
        /// From the start of the first bucket to the end of the last.
        var domain: ClosedRange<Date>
        var total: Int
        /// Every app with its total in this period, most first.
        var apps: [AppCount]
    }

    static let dayCount = 7
    static let weekCount = 8
    /// Apps charted by name; the rest are folded into "Other".
    static let maxNamedSeries = 5

    var days: Period
    var weeks: Period
    /// Apps that notified today, most first.
    var today: [AppCount]
    /// Series names in legend order: the busiest apps over 8 weeks, then "Other".
    /// Shared by both charts, so an app keeps its color when switching periods.
    var series: [String]
    /// Whether `series` ends with the "Other" group.
    var hasOtherSeries: Bool

    /// The range to ask the store for: whole days from the first of 8 weeks
    /// through the end of today.
    static func interval(now: Date, calendar: Calendar) -> DateInterval {
        let bounds = Bounds(now: now, calendar: calendar)
        return DateInterval(start: bounds.firstWeek, end: bounds.tomorrow)
    }

    init(counts: [DailyAppCount], now: Date, calendar: Calendar) {
        let bounds = Bounds(now: now, calendar: calendar)
        let inRange = counts
            .filter { $0.day >= bounds.firstWeek && $0.day < bounds.tomorrow }
            .sorted { $0.day < $1.day }

        // The most recent name wins, in case an app's name changed.
        var names: [AppKey: String] = [:]
        var totals: [AppKey: Int] = [:]
        for count in inRange {
            names[count.appKey] = count.appName
            totals[count.appKey, default: 0] += count.count
        }

        let ranked = totals.keys.sorted { lhs, rhs in
            let left = totals[lhs] ?? 0
            let right = totals[rhs] ?? 0
            return left != right ? left > right : lhs < rhs
        }
        // Folding a single app into "Other" would hide its name for nothing.
        let namedCount = ranked.count > Self.maxNamedSeries + 1 ? Self.maxNamedSeries : ranked.count
        let named = Array(ranked.prefix(namedCount))
        let otherName = String(localized: "Other", comment: "Stats chart series that groups the less busy apps")
        var seriesName: [AppKey: String] = [:]
        for key in ranked {
            seriesName[key] = named.contains(key) ? (names[key] ?? key.rawValue) : otherName
        }
        let hasOther = ranked.count > namedCount
        let allSeries = named.map { names[$0] ?? $0.rawValue } + (hasOther ? [otherName] : [])
        hasOtherSeries = hasOther
        series = allSeries

        var seriesOrder: [String: Int] = [:]
        for (index, name) in allSeries.enumerated() where seriesOrder[name] == nil {
            seriesOrder[name] = index
        }

        func period(from start: Date, to end: Date, bucket: (Date) -> Date) -> Period {
            var buckets: [BucketKey: Int] = [:]
            var appTotals: [AppKey: Int] = [:]
            for count in inRange where count.day >= start && count.day < end {
                let key = BucketKey(start: bucket(count.day), series: seriesName[count.appKey] ?? otherName)
                buckets[key, default: 0] += count.count
                appTotals[count.appKey, default: 0] += count.count
            }
            let bars = buckets
                .map { Bar(start: $0.key.start, series: $0.key.series, count: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return (seriesOrder[lhs.series] ?? .max) < (seriesOrder[rhs.series] ?? .max)
                }
            let apps = appTotals
                .map { AppCount(appKey: $0.key, appName: names[$0.key] ?? $0.key.rawValue, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.appKey < $1.appKey }
            return Period(
                bars: bars,
                domain: start...max(start, end),
                total: appTotals.values.reduce(0, +),
                apps: apps
            )
        }

        days = period(from: bounds.firstDay, to: bounds.tomorrow) { calendar.startOfDay(for: $0) }
        weeks = period(from: bounds.firstWeek, to: bounds.endOfWeek) { day in
            calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        }
        today = period(from: bounds.startOfToday, to: bounds.tomorrow) { $0 }.apps
    }

    private struct BucketKey: Hashable {
        var start: Date
        var series: String
    }

    /// Day and week boundaries around `now`.
    private struct Bounds {
        var startOfToday: Date
        var tomorrow: Date
        var firstDay: Date
        var firstWeek: Date
        var endOfWeek: Date

        init(now: Date, calendar: Calendar) {
            startOfToday = calendar.startOfDay(for: now)
            tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            firstDay = calendar.date(byAdding: .day, value: -(StatsSummary.dayCount - 1), to: startOfToday) ?? startOfToday
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
                ?? DateInterval(start: startOfToday, end: tomorrow)
            firstWeek = calendar.date(byAdding: .weekOfYear, value: -(StatsSummary.weekCount - 1), to: thisWeek.start)
                ?? thisWeek.start
            endOfWeek = thisWeek.end
        }
    }
}

extension StatsSummary {
    /// Sample stats for previews, so the charts render without a store.
    static func preview(now: Date = .now, calendar: Calendar = .current) -> StatsSummary {
        let apps: [(String, Int)] = [
            ("Messages", 14), ("Slack", 22), ("Mail", 9), ("Bank", 2),
            ("Calendar", 4), ("News", 6), ("Weather", 1), ("Photos", 3),
        ]
        let startOfToday = calendar.startOfDay(for: now)
        var counts: [DailyAppCount] = []
        for offset in 0..<56 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            for (index, (name, base)) in apps.enumerated() {
                let count = max(0, base + (offset * 7 + index * 3) % 9 - 4)
                if count > 0 {
                    counts.append(DailyAppCount(day: day, appKey: AppKey(appName: name), appName: name, count: count))
                }
            }
        }
        return StatsSummary(counts: counts, now: now, calendar: calendar)
    }
}
