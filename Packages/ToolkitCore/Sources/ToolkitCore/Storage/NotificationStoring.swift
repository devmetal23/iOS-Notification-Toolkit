import Foundation

/// The on-device notification store shared by the app, its intents and widgets.
///
/// Every method is synchronous, thread-safe and runs in its own short transaction,
/// so no lock is held between calls (iOS kills suspended processes that hold file
/// locks in a shared container). Implementations must be safe to open from several
/// processes at once: the app, the intents and the widget extension.
public protocol NotificationStoring: AnyObject, Sendable {

    // MARK: Capture (FR-6, FR-8)

    /// Stores a notification unless one with the same app, title and body was
    /// received within `dedupeWindow` seconds of it (FR-8). Also registers the app
    /// as tracked on its first capture and updates its last-logged time, in the
    /// same transaction.
    func insert(_ notification: NewNotification, capturedAt: Date, dedupeWindow: TimeInterval) throws -> InsertOutcome

    // MARK: Reading (FR-9, FR-10)

    /// A page of history, newest first. See `HistoryQuery`.
    func entries(_ query: HistoryQuery) throws -> [NotificationEntry]

    func entry(id: NotificationEntry.ID) throws -> NotificationEntry?

    /// Count of entries matching a filter, ignoring search text and paging.
    func entryCount(filter: HistoryFilter) throws -> Int

    // MARK: Tracked apps (FR-2, FR-3, FR-4)

    /// All tracked apps, oldest `addedAt` first.
    func trackedApps() throws -> [TrackedApp]

    /// Records an app the user set up from the catalog or guided flow, before its
    /// first capture. Returns the existing app unchanged if it is already tracked.
    @discardableResult
    func registerApp(displayName: String, catalogID: String?, at date: Date) throws -> TrackedApp

    /// Stops tracking an app. Its stored entries stay until deleted or expired.
    func removeApp(_ key: AppKey) throws

    /// Counts a capture dropped by the free-tier limit, registering the app if new.
    func recordBlockedCapture(_ notification: NewNotification, at date: Date) throws

    // MARK: Deleting (FR-13)

    func deleteEntry(id: NotificationEntry.ID) throws -> DeletionResult
    func deleteEntries(app: AppKey) throws -> DeletionResult
    /// Deletes every entry and snooze. Tracked apps stay so the health check still works.
    func deleteAll() throws -> DeletionResult

    // MARK: Retention (FR-12)

    /// Deletes entries received before the policy's cutoff. Entries with a snooze
    /// still pending at `now` are kept until it fires.
    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> DeletionResult

    // MARK: Stats (FR-17, FR-19)

    /// Per-app counts for each day in `interval` that has entries, bucketed by `calendar`.
    func dailyCounts(in interval: DateInterval, calendar: Calendar) throws -> [DailyAppCount]

    // MARK: Snooze (FR-14, FR-15)

    func addSnooze(entryID: NotificationEntry.ID, fireAt: Date, createdAt: Date) throws -> SnoozeRecord
    /// Snoozes that fire after `date`, soonest first.
    func pendingSnoozes(after date: Date) throws -> [SnoozeRecord]
    func rescheduleSnooze(id: SnoozeRecord.ID, fireAt: Date) throws -> SnoozeRecord
    func removeSnooze(id: SnoozeRecord.ID) throws
    /// Removes records whose fire time has passed. Returns how many were removed.
    @discardableResult
    func removeSnoozes(firedBefore date: Date) throws -> Int
}

public enum InsertOutcome: Hashable, Sendable {
    case inserted(NotificationEntry)
    case duplicate(of: NotificationEntry.ID)
}

/// What a delete removed. Callers cancel the listed pending local notifications.
public struct DeletionResult: Hashable, Sendable {
    public var entriesDeleted: Int
    /// `SnoozeRecord.requestIdentifier`s whose snoozes were removed with their entries.
    public var cancelledSnoozeRequestIdentifiers: [String]

    public init(entriesDeleted: Int = 0, cancelledSnoozeRequestIdentifiers: [String] = []) {
        self.entriesDeleted = entriesDeleted
        self.cancelledSnoozeRequestIdentifiers = cancelledSnoozeRequestIdentifiers
    }
}

public enum StoreError: Error, Hashable, Sendable {
    /// SQLite returned an error. `code` is the extended result code.
    case sqlite(code: Int32, message: String)
    /// The database file is unreadable, e.g. before the first unlock after a restart.
    case unavailable
    case notFound
    case migrationFailed(version: Int)
}
