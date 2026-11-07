import Foundation

/// Every SQL statement `SQLiteNotificationStore` runs, in one place for review.
///
/// Dates are stored as `REAL` seconds since the reference date
/// (`Date.timeIntervalSinceReferenceDate`), which is how `Date` stores itself, so
/// they round-trip exactly and keyset cursors compare equal to stored values.
enum StoreSQL {

    // MARK: Schema

    /// Version 1. `AUTOINCREMENT` on `snoozes` keeps request identifiers from ever
    /// being reused, even after Delete All; on `entries` it keeps ids monotonic.
    static let schemaV1 = """
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_key TEXT NOT NULL,
            app_name TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            body TEXT NOT NULL,
            received_at REAL NOT NULL,
            captured_at REAL NOT NULL,
            is_time_sensitive INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX entries_by_received ON entries (received_at DESC, id DESC);
        CREATE INDEX entries_by_app ON entries (app_key, received_at);

        CREATE VIRTUAL TABLE entries_fts USING fts5 (
            title, subtitle, body,
            content = 'entries',
            content_rowid = 'id',
            tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER entries_fts_after_insert AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts (rowid, title, subtitle, body)
            VALUES (new.id, new.title, new.subtitle, new.body);
        END;
        CREATE TRIGGER entries_fts_after_delete AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts (entries_fts, rowid, title, subtitle, body)
            VALUES ('delete', old.id, old.title, old.subtitle, old.body);
        END;
        CREATE TRIGGER entries_fts_after_update AFTER UPDATE OF title, subtitle, body ON entries BEGIN
            INSERT INTO entries_fts (entries_fts, rowid, title, subtitle, body)
            VALUES ('delete', old.id, old.title, old.subtitle, old.body);
            INSERT INTO entries_fts (rowid, title, subtitle, body)
            VALUES (new.id, new.title, new.subtitle, new.body);
        END;

        CREATE TABLE apps (
            key TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            added_at REAL NOT NULL,
            catalog_id TEXT,
            first_logged_at REAL,
            last_logged_at REAL,
            blocked_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE snoozes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL REFERENCES entries (id) ON DELETE CASCADE,
            fire_at REAL NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX snoozes_by_entry ON snoozes (entry_id);
        CREATE INDEX snoozes_by_fire_at ON snoozes (fire_at);
        """

    // MARK: Entries

    /// Columns read by `SQLiteStatement.entry(startingAt:)`, in its order.
    static let entryColumns = "e.id, e.app_key, e.app_name, e.title, e.subtitle, e.body, e.received_at, e.captured_at, e.is_time_sensitive"

    /// Bindings: app key, title, body, earliest and latest `received_at`.
    static let findDuplicate = """
        SELECT id FROM entries
        WHERE app_key = ? AND title = ? AND body = ? AND received_at BETWEEN ? AND ?
        ORDER BY id
        LIMIT 1
        """

    static let insertEntry = """
        INSERT INTO entries (app_key, app_name, title, subtitle, body, received_at, captured_at, is_time_sensitive)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

    static let entryByID = "SELECT \(entryColumns) FROM entries AS e WHERE e.id = ?"

    static let historySelect = "SELECT \(entryColumns) FROM entries AS e"

    /// Full-text match as a subquery, so FTS5 runs once per query whatever plan
    /// SQLite picks. With a plain join, SQLite may drive from `entries_by_app` and
    /// re-run MATCH for every row of the app: ~800 ms at 50,000 entries, against
    /// ~2 ms this way.
    static let matchCondition = "e.id IN (SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?)"

    static let countSelect = "SELECT count(*) FROM entries AS e"

    static let historyOrder = "ORDER BY e.received_at DESC, e.id DESC"

    /// A page of history: the timeline, or full-text search when `match` is set.
    static func history(
        filter: HistoryFilter,
        cursor: HistoryCursor?,
        match: String?,
        limit: Int
    ) -> (sql: String, bindings: [SQLValue]) {
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        if let match {
            conditions.append(matchCondition)
            bindings.append(.text(match))
        }
        appendConditions(for: filter, to: &conditions, bindings: &bindings)
        if let cursor {
            conditions.append("(e.received_at, e.id) < (?, ?)")
            bindings.append(.date(cursor.receivedAt))
            bindings.append(.integer(cursor.id))
        }
        let sql = historySelect + whereClause(conditions) + " " + historyOrder + " LIMIT ?"
        bindings.append(.integer(Int64(limit)))
        return (sql, bindings)
    }

    static func count(filter: HistoryFilter) -> (sql: String, bindings: [SQLValue]) {
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        appendConditions(for: filter, to: &conditions, bindings: &bindings)
        return (countSelect + whereClause(conditions), bindings)
    }

    private static func appendConditions(
        for filter: HistoryFilter,
        to conditions: inout [String],
        bindings: inout [SQLValue]
    ) {
        if !filter.apps.isEmpty {
            let keys = filter.apps.sorted()
            let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
            conditions.append("e.app_key IN (\(placeholders))")
            bindings.append(contentsOf: keys.map { SQLValue.text($0.rawValue) })
        }
        if let range = filter.dateRange {
            conditions.append("e.received_at >= ? AND e.received_at <= ?")
            bindings.append(.date(range.start))
            bindings.append(.date(range.end))
        }
        if filter.timeSensitiveOnly {
            conditions.append("e.is_time_sensitive = 1")
        }
    }

    private static func whereClause(_ conditions: [String]) -> String {
        conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
    }

    // MARK: Full-text search

    /// Turns what the user typed into an FTS5 query: each word matches as a prefix
    /// and all words must match. Every word is quoted, so operators and syntax
    /// characters (`"`, `*`, `-`, `:`, `^`, `(`, `OR`, `NEAR`) are searched as text
    /// and can never make the query invalid. Whitespace and control characters
    /// (including NUL) separate words. Returns nil when there is nothing to search.
    ///
    /// Works on Unicode scalars rather than Characters so a `"` followed by a
    /// combining mark is still escaped. A word with no searchable characters
    /// (only punctuation or emoji) becomes an empty phrase, which FTS5 ignores next
    /// to other words and which matches nothing on its own.
    static func matchExpression(for searchText: String) -> String? {
        var words: [String] = []
        var word = ""
        for scalar in searchText.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
            } else if scalar == "\"" {
                word += "\"\""
            } else {
                word.unicodeScalars.append(scalar)
            }
        }
        if !word.isEmpty {
            words.append(word)
        }
        guard !words.isEmpty else { return nil }
        return words.prefix(maxSearchWords).map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// Words beyond this are ignored; nobody types more, and it bounds query cost.
    static let maxSearchWords = 32

    // MARK: Tracked apps

    static let trackedAppColumns = """
        a.key, a.display_name, a.added_at, a.catalog_id, a.first_logged_at, a.last_logged_at, a.blocked_count,
        (SELECT count(*) FROM entries AS c WHERE c.app_key = a.key)
        """

    static let trackedApps = "SELECT \(trackedAppColumns) FROM apps AS a ORDER BY a.added_at, a.key"

    static let trackedAppByKey = "SELECT \(trackedAppColumns) FROM apps AS a WHERE a.key = ?"

    /// Registers the app on its first capture and records when it last logged.
    /// Bindings: key, display name, capture time.
    static let upsertAppOnCapture = """
        INSERT INTO apps (key, display_name, added_at, first_logged_at, last_logged_at)
        VALUES (?1, ?2, ?3, ?3, ?3)
        ON CONFLICT (key) DO UPDATE SET
            first_logged_at = coalesce(first_logged_at, excluded.first_logged_at),
            last_logged_at = max(coalesce(last_logged_at, excluded.last_logged_at), excluded.last_logged_at)
        """

    /// Bindings: key, display name, added at, catalog id.
    static let registerApp = """
        INSERT INTO apps (key, display_name, added_at, catalog_id)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (key) DO NOTHING
        """

    /// Bindings: key, display name, time.
    static let recordBlockedCapture = """
        INSERT INTO apps (key, display_name, added_at, blocked_count)
        VALUES (?, ?, ?, 1)
        ON CONFLICT (key) DO UPDATE SET blocked_count = blocked_count + 1
        """

    static let removeApp = "DELETE FROM apps WHERE key = ?"

    static let appDisplayNames = "SELECT key, display_name FROM apps"

    // MARK: Deleting

    static let snoozesOfEntry = "SELECT id FROM snoozes WHERE entry_id = ? ORDER BY id"

    static let deleteEntry = "DELETE FROM entries WHERE id = ?"

    static let snoozesOfApp = """
        SELECT s.id FROM snoozes AS s JOIN entries AS e ON e.id = s.entry_id
        WHERE e.app_key = ?
        ORDER BY s.id
        """

    static let deleteEntriesOfApp = "DELETE FROM entries WHERE app_key = ?"

    static let allSnoozeIDs = "SELECT id FROM snoozes ORDER BY id"

    static let deleteAllSnoozes = "DELETE FROM snoozes"

    static let deleteAllEntries = "DELETE FROM entries"

    // MARK: Retention

    /// Snoozes removed along with expired entries (all of them already fired).
    /// Bindings: ?1 cutoff, ?2 now.
    static let snoozesOfExpiredEntries = """
        SELECT s.id FROM snoozes AS s JOIN entries AS e ON e.id = s.entry_id
        WHERE e.received_at < ?1
          AND NOT EXISTS (SELECT 1 FROM snoozes AS p WHERE p.entry_id = e.id AND p.fire_at > ?2)
        ORDER BY s.id
        """

    /// Entries received before the cutoff, except those with a snooze still pending.
    /// Bindings: ?1 cutoff, ?2 now.
    static let deleteExpiredEntries = """
        DELETE FROM entries
        WHERE received_at < ?1
          AND NOT EXISTS (SELECT 1 FROM snoozes AS p WHERE p.entry_id = entries.id AND p.fire_at > ?2)
        """

    // MARK: Stats

    /// Bindings: interval start, interval end (inclusive).
    static let entriesForDailyCounts = """
        SELECT app_key, app_name, received_at FROM entries
        WHERE received_at >= ? AND received_at <= ?
        ORDER BY received_at
        """

    // MARK: Snoozes

    /// Entry columns first (0–8), then the snooze's id, fire time and creation time (9–11).
    static let snoozeSelect = """
        SELECT \(entryColumns), s.id, s.fire_at, s.created_at
        FROM snoozes AS s JOIN entries AS e ON e.id = s.entry_id
        """

    static let snoozeByID = snoozeSelect + " WHERE s.id = ?"

    static let pendingSnoozes = snoozeSelect + " WHERE s.fire_at > ? ORDER BY s.fire_at, s.id"

    static let insertSnooze = "INSERT INTO snoozes (entry_id, fire_at, created_at) VALUES (?, ?, ?)"

    static let rescheduleSnooze = "UPDATE snoozes SET fire_at = ? WHERE id = ?"

    static let removeSnooze = "DELETE FROM snoozes WHERE id = ?"

    static let removeFiredSnoozes = "DELETE FROM snoozes WHERE fire_at <= ?"
}
