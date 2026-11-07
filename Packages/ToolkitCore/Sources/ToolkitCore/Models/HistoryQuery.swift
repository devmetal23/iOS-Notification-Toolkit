import Foundation

/// Narrows history by app, date and flags (FR-9). An empty filter matches everything.
public struct HistoryFilter: Hashable, Sendable {
    /// Apps to include. Empty means all apps.
    public var apps: Set<AppKey>
    /// Inclusive range on `receivedAt`. Nil means all time.
    public var dateRange: DateInterval?
    public var timeSensitiveOnly: Bool

    public init(apps: Set<AppKey> = [], dateRange: DateInterval? = nil, timeSensitiveOnly: Bool = false) {
        self.apps = apps
        self.dateRange = dateRange
        self.timeSensitiveOnly = timeSensitiveOnly
    }

    public static let all = HistoryFilter()
}

/// One page of history, newest first. A non-empty `searchText` runs full-text
/// search over title, subtitle and body (FR-10); otherwise it is the timeline.
public struct HistoryQuery: Hashable, Sendable {
    public var filter: HistoryFilter
    /// Words the user typed. Each word matches as a prefix; all words must match.
    public var searchText: String
    public var limit: Int
    /// Keyset pagination: return only entries older than this one.
    public var cursor: HistoryCursor?

    public init(filter: HistoryFilter = .all, searchText: String = "", limit: Int = 100, cursor: HistoryCursor? = nil) {
        self.filter = filter
        self.searchText = searchText
        self.limit = limit
        self.cursor = cursor
    }
}

/// Position after the last entry of a page. Order is (receivedAt DESC, id DESC).
public struct HistoryCursor: Hashable, Sendable {
    public var receivedAt: Date
    public var id: NotificationEntry.ID

    public init(receivedAt: Date, id: NotificationEntry.ID) {
        self.receivedAt = receivedAt
        self.id = id
    }

    public init(after entry: NotificationEntry) {
        self.init(receivedAt: entry.receivedAt, id: entry.id)
    }
}
