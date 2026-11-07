import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// SQLite's `SQLITE_TRANSIENT`, which Swift can't import from its C macro: SQLite
/// copies bound text before the bind call returns. Computed, so there is no
/// global stored state for Swift 6 to check.
private var sqliteTransient: sqlite3_destructor_type {
    unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
}

/// A value bound to a statement parameter.
enum SQLValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    /// Dates are stored as seconds since the reference date, `Date`'s own
    /// representation, so they round-trip exactly.
    static func date(_ date: Date) -> SQLValue {
        .real(date.timeIntervalSinceReferenceDate)
    }

    static func optionalText(_ text: String?) -> SQLValue {
        guard let text else { return .null }
        return .text(text)
    }
}

/// One SQLite connection.
///
/// Not thread-safe: `SQLiteNotificationStore` serializes every use behind its
/// lock (the connection is opened with `SQLITE_OPEN_NOMUTEX`). Statements are
/// prepared and finalized inside a single call, and transactions commit or roll
/// back before `transaction(_:)` returns, so no SQLite lock outlives a call.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Opens a connection with extended result codes and a busy timeout.
    static func open(path: String, flags: Int32, busyTimeoutMilliseconds: Int32) throws -> SQLiteDatabase {
        var pointer: OpaquePointer?
        let code = sqlite3_open_v2(path, &pointer, flags, nil)
        guard let pointer else {
            // SQLite couldn't allocate a connection at all.
            throw StoreError(sqliteCode: code, message: "Unable to allocate a database connection")
        }
        // From here the connection is closed in deinit if anything fails.
        let database = SQLiteDatabase(handle: pointer)
        guard code == SQLITE_OK else {
            throw database.failure(code)
        }
        sqlite3_extended_result_codes(pointer, 1)
        sqlite3_busy_timeout(pointer, busyTimeoutMilliseconds)
        return database
    }

    // MARK: Running SQL

    /// Runs one or more statements that take no parameters, ignoring any rows.
    func execute(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw failure(code)
        }
    }

    /// Runs one statement to completion, ignoring any rows.
    func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        try withStatement(sql, bindings) { (statement: SQLiteStatement) throws -> Void in
            while try statement.step() {}
        }
    }

    /// Every row of one statement, decoded by `row`.
    func query<T>(_ sql: String, _ bindings: [SQLValue] = [], row: (SQLiteStatement) throws -> T) throws -> [T] {
        try withStatement(sql, bindings) { (statement: SQLiteStatement) throws -> [T] in
            var rows: [T] = []
            while try statement.step() {
                rows.append(try row(statement))
            }
            return rows
        }
    }

    /// The first row of one statement, decoded by `row`, or nil when there is none.
    func queryFirst<T>(_ sql: String, _ bindings: [SQLValue] = [], row: (SQLiteStatement) throws -> T) throws -> T? {
        try withStatement(sql, bindings) { (statement: SQLiteStatement) throws -> T? in
            guard try statement.step() else { return nil }
            return try row(statement)
        }
    }

    /// Prepares `sql`, binds `bindings` to its parameters in order (`?` or `?NNN`
    /// numbered from 1), runs `body` and finalizes the statement whatever happens.
    private func withStatement<T>(_ sql: String, _ bindings: [SQLValue], _ body: (SQLiteStatement) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &pointer, nil)
        guard code == SQLITE_OK else {
            throw failure(code)
        }
        guard let pointer else {
            throw StoreError.sqlite(code: SQLITE_MISUSE, message: "Empty SQL statement")
        }
        defer { sqlite3_finalize(pointer) }
        let statement = SQLiteStatement(handle: pointer, database: self)
        try statement.bind(bindings)
        return try body(statement)
    }

    // MARK: Transactions

    /// Runs `body` in a `BEGIN IMMEDIATE` transaction: the write lock is taken up
    /// front (waiting up to the busy timeout for another process's write), so the
    /// transaction never has to upgrade from a read lock and fail with SQLITE_BUSY
    /// halfway. Commits on success, rolls back on any error.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            // SQLite may already have rolled back (e.g. after an I/O error).
            if sqlite3_get_autocommit(handle) == 0 {
                sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            }
            throw error
        }
    }

    // MARK: Connection state

    /// The rowid of the last row inserted by an INSERT statement on this connection
    /// (not by a trigger it fired).
    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    /// Rows changed by the most recent INSERT, UPDATE or DELETE statement, not
    /// counting rows changed by triggers or foreign key actions.
    var changes: Int {
        Int(sqlite3_changes(handle))
    }

    func userVersion() throws -> Int {
        let version = try queryFirst("PRAGMA user_version", row: { $0.int64(0) })
        return Int(version ?? 0)
    }

    /// The error for a failed call on this connection.
    fileprivate func failure(_ code: Int32) -> StoreError {
        StoreError(sqliteCode: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// A prepared statement, valid only inside the closure it was passed to.
struct SQLiteStatement {
    fileprivate let handle: OpaquePointer
    fileprivate let database: SQLiteDatabase

    fileprivate func bind(_ values: [SQLValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .integer(let integer):
                code = sqlite3_bind_int64(handle, index, integer)
            case .real(let real):
                code = sqlite3_bind_double(handle, index, real)
            case .text(let text):
                code = Self.bindText(text, to: handle, at: index)
            case .null:
                code = sqlite3_bind_null(handle, index)
            }
            guard code == SQLITE_OK else {
                throw database.failure(code)
            }
        }
    }

    /// Binds the string's UTF-8 bytes with an explicit length, so text containing
    /// NUL is stored whole, and the empty string is bound as '' rather than NULL.
    private static func bindText(_ text: String, to handle: OpaquePointer, at index: Int32) -> Int32 {
        var text = text
        return text.withUTF8 { (bytes: UnsafeBufferPointer<UInt8>) -> Int32 in
            guard let base = bytes.baseAddress, !bytes.isEmpty else {
                return sqlite3_bind_text(handle, index, "", 0, sqliteTransient)
            }
            return base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { (characters: UnsafePointer<CChar>) -> Int32 in
                sqlite3_bind_text64(handle, index, characters, UInt64(bytes.count), sqliteTransient, UInt8(SQLITE_UTF8))
            }
        }
    }

    /// Advances to the next row. Returns false once the statement has finished.
    fileprivate func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw database.failure(code)
        }
    }

    // MARK: Columns of the current row (0-based)

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    func bool(_ column: Int32) -> Bool {
        int64(column) != 0
    }

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    /// Text read with its byte length, so embedded NUL characters survive.
    func string(_ column: Int32) -> String {
        guard let text = sqlite3_column_text(handle, column) else { return "" }
        let count = Int(sqlite3_column_bytes(handle, column))
        return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
    }

    func optionalString(_ column: Int32) -> String? {
        isNull(column) ? nil : string(column)
    }

    func date(_ column: Int32) -> Date {
        Date(timeIntervalSinceReferenceDate: double(column))
    }

    func optionalDate(_ column: Int32) -> Date? {
        isNull(column) ? nil : date(column)
    }
}

extension StoreError {
    /// Maps an SQLite result code. Failures to open or read the file, such as
    /// before the first unlock after a restart (NFR-2), are `.unavailable`:
    /// the caller should try again later.
    init(sqliteCode code: Int32, message: String) {
        switch code & 0xFF {
        case SQLITE_CANTOPEN, SQLITE_IOERR, SQLITE_AUTH, SQLITE_PERM:
            self = .unavailable
        default:
            self = .sqlite(code: code, message: message)
        }
    }
}
