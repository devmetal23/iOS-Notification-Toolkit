import Foundation

/// Numbered schema migrations, tracked in `PRAGMA user_version`.
enum Schema {
    /// Migration `n` (counting from 1) brings the database to version `n`.
    /// Append new migrations; never edit a shipped one.
    static let migrations: [String] = [
        StoreSQL.schemaV1,
    ]

    static var latestVersion: Int { migrations.count }

    /// Brings the database up to `latestVersion`. Safe to run from several
    /// processes at once: the version is checked again under the write lock.
    /// A database from a newer build (a higher version) is left as it is.
    static func migrate(_ database: SQLiteDatabase, readOnly: Bool) throws {
        // Fast path for every open after the first: one PRAGMA read.
        if try database.userVersion() >= latestVersion { return }
        // A read-only connection can't migrate; the app will on its next launch.
        guard !readOnly else { throw StoreError.unavailable }

        try database.transaction { () throws -> Void in
            // Another process may have migrated while this one waited for the lock.
            let current = try database.userVersion()
            guard current < latestVersion else { return }
            for version in (current + 1)...latestVersion {
                do {
                    try database.execute(migrations[version - 1])
                } catch StoreError.unavailable {
                    throw StoreError.unavailable
                } catch {
                    throw StoreError.migrationFailed(version: version)
                }
            }
            try database.execute("PRAGMA user_version = \(latestVersion)")
        }
    }
}
