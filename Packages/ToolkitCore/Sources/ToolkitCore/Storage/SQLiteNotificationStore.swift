import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// SQLite + FTS5 implementation of `NotificationStoring` (NFR-6).
///
/// Each store owns one connection, opened with `SQLITE_OPEN_NOMUTEX` and used
/// only under the store's lock. Every method runs in one short transaction
/// (`BEGIN IMMEDIATE` for writes) and finalizes its statements before returning,
/// so no SQLite lock is held between calls. The app, its intents and the widget
/// extension may open the same file at once: WAL lets readers run alongside the
/// single writer, and the busy timeout waits out another process's write (NFR-7).
public final class SQLiteNotificationStore: NotificationStoring, @unchecked Sendable {

    public struct Options: Hashable, Sendable {
        /// Open without write access, e.g. from the widget extension.
        public var readOnly: Bool

        public init(readOnly: Bool = false) {
            self.readOnly = readOnly
        }
    }

    /// How long a call waits for another connection's write before failing.
    static let busyTimeoutMilliseconds: Int32 = 5_000

    private enum Location {
        case file(URL)
        case memory
    }

    private let location: Location
    private let options: Options
    private let lock = NSLock()
    /// Guarded by `lock`. Nil after `closeConnection()` until the next call reopens it.
    private var database: SQLiteDatabase?

    /// Opens or creates the database at `url` and runs pending migrations.
    /// On iOS the file is created with Complete Until First User Authentication
    /// protection (NFR-2), in a directory excluded from backups.
    public init(url: URL, options: Options = .init()) throws {
        self.location = .file(url)
        self.options = options
        self.database = try SQLiteNotificationStore.openDatabase(at: .file(url), options: options)
    }

    private init(inMemoryWith options: Options) throws {
        self.location = .memory
        self.options = options
        self.database = try SQLiteNotificationStore.openDatabase(at: .memory, options: options)
    }

    /// A private in-memory database, for tests and SwiftUI previews.
    public static func inMemory() throws -> SQLiteNotificationStore {
        try SQLiteNotificationStore(inMemoryWith: Options())
    }

    /// Closes the database connection and its file handles; the next call on this
    /// store reopens it. Optional: between calls the connection holds no
    /// transaction or statement. Useful where a process is done with the store for
    /// a while, such as a widget extension after building its timeline.
    /// Has no effect on an in-memory store, whose data lives in its connection.
    public func closeConnection() {
        lock.lock()
        defer { lock.unlock() }
        if case .file = location {
            database = nil
        }
    }

    // MARK: Capture (FR-6, FR-8)

    public func insert(_ notification: NewNotification, capturedAt: Date, dedupeWindow: TimeInterval) throws -> InsertOutcome {
        let key = notification.appKey
        let window = dedupeWindow.isFinite ? max(0, dedupeWindow) : 0
        let app: [SQLValue] = [.text(key.rawValue), .text(Self.displayName(notification.appName)), .date(capturedAt)]
        return try write { (db: SQLiteDatabase) throws -> InsertOutcome in
            let duplicate = try db.queryFirst(StoreSQL.findDuplicate, [
                .text(key.rawValue),
                .text(notification.title),
                .text(notification.body),
                .date(notification.receivedAt.addingTimeInterval(-window)),
                .date(notification.receivedAt.addingTimeInterval(window)),
            ], row: { $0.int64(0) })
            if let duplicate {
                // The automation still ran, so the app counts as logging (FR-4).
                try db.run(StoreSQL.upsertAppOnCapture, app)
                return .duplicate(of: duplicate)
            }
            try db.run(StoreSQL.insertEntry, [
                .text(key.rawValue),
                .text(notification.appName),
                .text(notification.title),
                .text(notification.subtitle),
                .text(notification.body),
                .date(notification.receivedAt),
                .date(capturedAt),
                .integer(notification.isTimeSensitive ? 1 : 0),
            ])
            // Read before the app upsert, which may insert a row of its own.
            let id = db.lastInsertRowID
            try db.run(StoreSQL.upsertAppOnCapture, app)
            return .inserted(NotificationEntry(
                id: id,
                appKey: key,
                appName: notification.appName,
                title: notification.title,
                subtitle: notification.subtitle,
                body: notification.body,
                receivedAt: notification.receivedAt,
                capturedAt: capturedAt,
                isTimeSensitive: notification.isTimeSensitive
            ))
        }
    }

    // MARK: Reading (FR-9, FR-10)

    public func entries(_ query: HistoryQuery) throws -> [NotificationEntry] {
        guard query.limit > 0 else { return [] }
        let (sql, bindings) = StoreSQL.history(
            filter: query.filter,
            cursor: query.cursor,
            match: StoreSQL.matchExpression(for: query.searchText),
            limit: query.limit
        )
        return try withDatabase { (db: SQLiteDatabase) throws -> [NotificationEntry] in
            try db.query(sql, bindings, row: { $0.entry() })
        }
    }

    public func entry(id: NotificationEntry.ID) throws -> NotificationEntry? {
        try withDatabase { (db: SQLiteDatabase) throws -> NotificationEntry? in
            try db.queryFirst(StoreSQL.entryByID, [.integer(id)], row: { $0.entry() })
        }
    }

    public func entryCount(filter: HistoryFilter) throws -> Int {
        let (sql, bindings) = StoreSQL.count(filter: filter)
        return try withDatabase { (db: SQLiteDatabase) throws -> Int in
            let count = try db.queryFirst(sql, bindings, row: { $0.int64(0) })
            return Int(count ?? 0)
        }
    }

    // MARK: Tracked apps (FR-2, FR-3, FR-4)

    public func trackedApps() throws -> [TrackedApp] {
        try withDatabase { (db: SQLiteDatabase) throws -> [TrackedApp] in
            try db.query(StoreSQL.trackedApps, row: { $0.trackedApp() })
        }
    }

    @discardableResult
    public func registerApp(displayName: String, catalogID: String?, at date: Date) throws -> TrackedApp {
        let key = AppKey(appName: displayName)
        return try write { (db: SQLiteDatabase) throws -> TrackedApp in
            try db.run(StoreSQL.registerApp, [
                .text(key.rawValue),
                .text(Self.displayName(displayName)),
                .date(date),
                .optionalText(catalogID),
            ])
            guard let app = try db.queryFirst(StoreSQL.trackedAppByKey, [.text(key.rawValue)], row: { $0.trackedApp() }) else {
                throw StoreError.notFound
            }
            return app
        }
    }

    public func removeApp(_ key: AppKey) throws {
        try write { (db: SQLiteDatabase) throws -> Void in
            try db.run(StoreSQL.removeApp, [.text(key.rawValue)])
        }
    }

    public func recordBlockedCapture(_ notification: NewNotification, at date: Date) throws {
        try write { (db: SQLiteDatabase) throws -> Void in
            try db.run(StoreSQL.recordBlockedCapture, [
                .text(notification.appKey.rawValue),
                .text(Self.displayName(notification.appName)),
                .date(date),
            ])
        }
    }

    // MARK: Deleting (FR-13)

    public func deleteEntry(id: NotificationEntry.ID) throws -> DeletionResult {
        try write { (db: SQLiteDatabase) throws -> DeletionResult in
            try Self.runDelete(in: db, snoozes: StoreSQL.snoozesOfEntry, entries: StoreSQL.deleteEntry, [.integer(id)])
        }
    }

    public func deleteEntries(app: AppKey) throws -> DeletionResult {
        try write { (db: SQLiteDatabase) throws -> DeletionResult in
            try Self.runDelete(in: db, snoozes: StoreSQL.snoozesOfApp, entries: StoreSQL.deleteEntriesOfApp, [.text(app.rawValue)])
        }
    }

    public func deleteAll() throws -> DeletionResult {
        try write { (db: SQLiteDatabase) throws -> DeletionResult in
            let snoozeIDs = try db.query(StoreSQL.allSnoozeIDs, row: { $0.int64(0) })
            try db.run(StoreSQL.deleteAllSnoozes)
            try db.run(StoreSQL.deleteAllEntries)
            return DeletionResult(
                entriesDeleted: db.changes,
                cancelledSnoozeRequestIdentifiers: snoozeIDs.map(SnoozeRecord.requestIdentifier(for:))
            )
        }
    }

    // MARK: Retention (FR-12)

    public func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> DeletionResult {
        guard let cutoff = policy.cutoff(now: now) else { return DeletionResult() }
        return try write { (db: SQLiteDatabase) throws -> DeletionResult in
            try Self.runDelete(
                in: db,
                snoozes: StoreSQL.snoozesOfExpiredEntries,
                entries: StoreSQL.deleteExpiredEntries,
                [.date(cutoff), .date(now)]
            )
        }
    }

    // MARK: Stats (FR-17, FR-19)

    public func dailyCounts(in interval: DateInterval, calendar: Calendar) throws -> [DailyAppCount] {
        typealias Row = (key: AppKey, name: String, receivedAt: Date)
        let (rows, displayNames) = try withDatabase { (db: SQLiteDatabase) throws -> ([Row], [String: String]) in
            let rows = try db.query(
                StoreSQL.entriesForDailyCounts,
                [.date(interval.start), .date(interval.end)],
                row: { (row: SQLiteStatement) -> Row in (AppKey(rawValue: row.string(0)), row.string(1), row.date(2)) }
            )
            let names = try db.query(StoreSQL.appDisplayNames, row: { (row: SQLiteStatement) -> (String, String) in
                (row.string(0), row.string(1))
            })
            return (rows, Dictionary(names, uniquingKeysWith: { first, _ in first }))
        }

        struct Bucket: Hashable {
            var day: Date
            var app: AppKey
        }
        var counts: [Bucket: Int] = [:]
        var latestNames: [AppKey: String] = [:]
        // Rows come oldest first, so most share the previous row's day: look the day
        // up in the calendar only when a row falls outside it.
        var currentDay: DateInterval?
        for row in rows {
            let day: DateInterval
            if let currentDay, row.receivedAt >= currentDay.start, row.receivedAt < currentDay.end {
                day = currentDay
            } else {
                day = calendar.dateInterval(of: .day, for: row.receivedAt)
                    ?? DateInterval(start: calendar.startOfDay(for: row.receivedAt), duration: 0)
                currentDay = day
            }
            counts[Bucket(day: day.start, app: row.key), default: 0] += 1
            latestNames[row.key] = row.name
        }
        return counts
            .map { (element: (key: Bucket, value: Int)) -> DailyAppCount in
                let app = element.key.app
                return DailyAppCount(
                    day: element.key.day,
                    appKey: app,
                    appName: displayNames[app.rawValue] ?? latestNames[app] ?? app.rawValue,
                    count: element.value
                )
            }
            .sorted { ($0.day, $0.appKey) < ($1.day, $1.appKey) }
    }

    // MARK: Snooze (FR-14, FR-15)

    public func addSnooze(entryID: NotificationEntry.ID, fireAt: Date, createdAt: Date) throws -> SnoozeRecord {
        try write { (db: SQLiteDatabase) throws -> SnoozeRecord in
            guard let entry = try db.queryFirst(StoreSQL.entryByID, [.integer(entryID)], row: { $0.entry() }) else {
                throw StoreError.notFound
            }
            try db.run(StoreSQL.insertSnooze, [.integer(entryID), .date(fireAt), .date(createdAt)])
            return SnoozeRecord(id: db.lastInsertRowID, entry: entry, fireAt: fireAt, createdAt: createdAt)
        }
    }

    public func pendingSnoozes(after date: Date) throws -> [SnoozeRecord] {
        try withDatabase { (db: SQLiteDatabase) throws -> [SnoozeRecord] in
            try db.query(StoreSQL.pendingSnoozes, [.date(date)], row: { $0.snoozeRecord() })
        }
    }

    /// Keeps the record's id, so its `requestIdentifier` stays the same.
    public func rescheduleSnooze(id: SnoozeRecord.ID, fireAt: Date) throws -> SnoozeRecord {
        try write { (db: SQLiteDatabase) throws -> SnoozeRecord in
            try db.run(StoreSQL.rescheduleSnooze, [.date(fireAt), .integer(id)])
            guard db.changes > 0,
                  let record = try db.queryFirst(StoreSQL.snoozeByID, [.integer(id)], row: { $0.snoozeRecord() })
            else {
                throw StoreError.notFound
            }
            return record
        }
    }

    public func removeSnooze(id: SnoozeRecord.ID) throws {
        try write { (db: SQLiteDatabase) throws -> Void in
            try db.run(StoreSQL.removeSnooze, [.integer(id)])
        }
    }

    /// Removes records whose fire time is at or before `date`, the complement of
    /// `pendingSnoozes(after:)`.
    @discardableResult
    public func removeSnoozes(firedBefore date: Date) throws -> Int {
        try write { (db: SQLiteDatabase) throws -> Int in
            try db.run(StoreSQL.removeFiredSnoozes, [.date(date)])
            return db.changes
        }
    }

    // MARK: Connection

    /// Runs `body` with the open connection, reopening it if it was closed.
    private func withDatabase<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let connection: SQLiteDatabase
        if let database {
            connection = database
        } else {
            connection = try SQLiteNotificationStore.openDatabase(at: location, options: options)
            database = connection
        }
        do {
            return try body(connection)
        } catch StoreError.unavailable {
            // The file became unreadable; start from a fresh connection next time.
            if case .file = location {
                database = nil
            }
            throw StoreError.unavailable
        }
    }

    /// Runs `body` in one `BEGIN IMMEDIATE` transaction.
    private func write<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        try withDatabase { (db: SQLiteDatabase) throws -> T in
            try db.transaction { try body(db) }
        }
    }

    /// Selects the snoozes to report, then deletes the entries (their snoozes go
    /// with them through `ON DELETE CASCADE`, and FTS rows through the trigger).
    private static func runDelete(
        in db: SQLiteDatabase,
        snoozes snoozeSQL: String,
        entries entrySQL: String,
        _ bindings: [SQLValue]
    ) throws -> DeletionResult {
        let snoozeIDs = try db.query(snoozeSQL, bindings, row: { $0.int64(0) })
        try db.run(entrySQL, bindings)
        return DeletionResult(
            entriesDeleted: db.changes,
            cancelledSnoozeRequestIdentifiers: snoozeIDs.map(SnoozeRecord.requestIdentifier(for:))
        )
    }

    /// The app name as shown in lists: what the shortcut passed, trimmed.
    private static func displayName(_ appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Opening

    private static func openDatabase(at location: Location, options: Options) throws -> SQLiteDatabase {
        let database: SQLiteDatabase
        switch location {
        case .memory:
            database = try SQLiteDatabase.open(
                path: ":memory:",
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
                busyTimeoutMilliseconds: busyTimeoutMilliseconds
            )
        case .file(let url):
            if !options.readOnly {
                try prepareDirectory(url.deletingLastPathComponent())
            }
            var flags: Int32 = SQLITE_OPEN_NOMUTEX
            flags |= options.readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            #if os(iOS)
            // NFR-2: the database, WAL and shm files stay readable while the device is
            // locked (captures arrive then) but not before the first unlock.
            flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION
            #endif
            let path: String? = url.withUnsafeFileSystemRepresentation { representation in
                representation.map { String(cString: $0) }
            }
            guard let path else { throw StoreError.unavailable }
            database = try SQLiteDatabase.open(path: path, flags: flags, busyTimeoutMilliseconds: busyTimeoutMilliseconds)
            if !options.readOnly {
                // Persistent in the file; a no-op once set (NFR-7).
                try database.execute("PRAGMA journal_mode = WAL")
            }
        }
        // Per connection. secure_delete = FAST zeroes deleted notification text in
        // b-tree pages at no extra I/O, so deleted history doesn't linger in the file.
        try database.execute("PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON; PRAGMA secure_delete = FAST")
        try Schema.migrate(database, readOnly: options.readOnly)
        return database
    }

    /// Creates the database directory if needed. On iOS it gets Complete Until
    /// First User Authentication protection (NFR-2) and is excluded from backups,
    /// which covers the database, WAL and shm files inside it (privacy, NFR-1).
    private static func prepareDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        do {
            #if os(iOS)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            #else
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            #endif
        } catch {
            throw StoreError.unavailable
        }
        #if os(iOS)
        // Reapplied on every open, so a directory created before this code shipped, or
        // one where an earlier attempt failed, gets the attributes too. Best effort:
        // neither change should keep captures from being stored.
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excludedDirectory = directory
        try? excludedDirectory.setResourceValues(values)
        #endif
    }
}

// MARK: - Row decoding

private extension SQLiteStatement {
    /// Reads the columns of `StoreSQL.entryColumns`, starting at `first`.
    func entry(startingAt first: Int32 = 0) -> NotificationEntry {
        NotificationEntry(
            id: int64(first),
            appKey: AppKey(rawValue: string(first + 1)),
            appName: string(first + 2),
            title: string(first + 3),
            subtitle: string(first + 4),
            body: string(first + 5),
            receivedAt: date(first + 6),
            capturedAt: date(first + 7),
            isTimeSensitive: bool(first + 8)
        )
    }

    /// Reads a row of `StoreSQL.snoozeSelect`.
    func snoozeRecord() -> SnoozeRecord {
        SnoozeRecord(id: int64(9), entry: entry(), fireAt: date(10), createdAt: date(11))
    }

    /// Reads a row of `StoreSQL.trackedAppColumns`.
    func trackedApp() -> TrackedApp {
        TrackedApp(
            key: AppKey(rawValue: string(0)),
            displayName: string(1),
            addedAt: date(2),
            catalogID: optionalString(3),
            firstLoggedAt: optionalDate(4),
            lastLoggedAt: optionalDate(5),
            entryCount: Int(int64(7)),
            blockedCount: Int(int64(6))
        )
    }
}
