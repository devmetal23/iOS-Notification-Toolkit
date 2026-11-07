import Foundation

/// Notifications from one app on one day (FR-17 widget counts, FR-19 stats).
public struct DailyAppCount: Hashable, Sendable {
    /// Start of the day in the calendar the counts were bucketed with.
    public var day: Date
    public var appKey: AppKey
    public var appName: String
    public var count: Int

    public init(day: Date, appKey: AppKey, appName: String, count: Int) {
        self.day = day
        self.appKey = appKey
        self.appName = appName
        self.count = count
    }
}
