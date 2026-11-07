import Foundation

// CONTRACT STUB — workstream W1 replaces the bodies. Keep the public signatures.

/// SQLite + FTS5 implementation of `NotificationStoring` (NFR-6).
public final class SQLiteNotificationStore: NotificationStoring, @unchecked Sendable {

    public struct Options: Hashable, Sendable {
        /// Open without write access, e.g. from the widget extension.
        public var readOnly: Bool

        public init(readOnly: Bool = false) {
            self.readOnly = readOnly
        }
    }

    /// Opens or creates the database at `url` and runs pending migrations.
    /// On iOS the file is created with Complete Until First User Authentication
    /// protection (NFR-2), in a directory excluded from backups.
    public init(url: URL, options: Options = .init()) throws {
        fatalError("W1: not implemented")
    }

    /// A private in-memory database, for tests and SwiftUI previews.
    public static func inMemory() throws -> SQLiteNotificationStore {
        fatalError("W1: not implemented")
    }

    public func insert(_ notification: NewNotification, capturedAt: Date, dedupeWindow: TimeInterval) throws -> InsertOutcome { fatalError("W1") }
    public func entries(_ query: HistoryQuery) throws -> [NotificationEntry] { fatalError("W1") }
    public func entry(id: NotificationEntry.ID) throws -> NotificationEntry? { fatalError("W1") }
    public func entryCount(filter: HistoryFilter) throws -> Int { fatalError("W1") }
    public func trackedApps() throws -> [TrackedApp] { fatalError("W1") }
    @discardableResult
    public func registerApp(displayName: String, catalogID: String?, at date: Date) throws -> TrackedApp { fatalError("W1") }
    public func removeApp(_ key: AppKey) throws { fatalError("W1") }
    public func recordBlockedCapture(_ notification: NewNotification, at date: Date) throws { fatalError("W1") }
    public func deleteEntry(id: NotificationEntry.ID) throws -> DeletionResult { fatalError("W1") }
    public func deleteEntries(app: AppKey) throws -> DeletionResult { fatalError("W1") }
    public func deleteAll() throws -> DeletionResult { fatalError("W1") }
    public func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> DeletionResult { fatalError("W1") }
    public func dailyCounts(in interval: DateInterval, calendar: Calendar) throws -> [DailyAppCount] { fatalError("W1") }
    public func addSnooze(entryID: NotificationEntry.ID, fireAt: Date, createdAt: Date) throws -> SnoozeRecord { fatalError("W1") }
    public func pendingSnoozes(after date: Date) throws -> [SnoozeRecord] { fatalError("W1") }
    public func rescheduleSnooze(id: SnoozeRecord.ID, fireAt: Date) throws -> SnoozeRecord { fatalError("W1") }
    public func removeSnooze(id: SnoozeRecord.ID) throws { fatalError("W1") }
    @discardableResult
    public func removeSnoozes(firedBefore date: Date) throws -> Int { fatalError("W1") }
}
