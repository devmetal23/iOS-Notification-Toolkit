import Foundation
import ToolkitCore

/// Shared helpers for the store, capture and performance tests. Everything is
/// namespaced here so it can't collide with helpers in other test files.
enum TestSupport {
    /// A fixed instant (May 2026) that test dates are built from.
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static let day: TimeInterval = 24 * 60 * 60

    /// Settings backed by a new, empty defaults suite, so tests never share state.
    static func makeSettings() -> SharedSettings {
        SharedSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    static func notification(
        app: String = "Messages",
        title: String = "Sam",
        subtitle: String = "",
        body: String = "See you soon",
        at receivedAt: Date = referenceDate,
        timeSensitive: Bool = false
    ) -> NewNotification {
        NewNotification(
            appName: app,
            title: title,
            subtitle: subtitle,
            body: body,
            receivedAt: receivedAt,
            isTimeSensitive: timeSensitive
        )
    }

    /// Inserts with the production dedupe window and returns the stored entry,
    /// failing if the store reported a duplicate.
    @discardableResult
    static func insert(
        _ notification: NewNotification,
        into store: any NotificationStoring,
        capturedAt: Date? = nil
    ) throws -> NotificationEntry {
        let outcome = try store.insert(
            notification,
            capturedAt: capturedAt ?? notification.receivedAt,
            dedupeWindow: CaptureService.dedupeWindow
        )
        guard case .inserted(let entry) = outcome else {
            throw Failure("Expected an insert, got \(outcome)")
        }
        return entry
    }

    static func isInserted(_ outcome: InsertOutcome) -> Bool {
        if case .inserted = outcome { return true }
        return false
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String

        init(_ description: String) {
            self.description = description
        }
    }

    // MARK: Files

    /// A new, empty directory. Remove it with `removeDirectory(_:)`.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolkitCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Combined size of the database file and its WAL and shm files.
    static func databaseSize(at url: URL) -> Int64 {
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path + suffix)
            if let size = attributes?[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    // MARK: Time and randomness

    /// A settable clock to inject as `CaptureService(now:)`.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date = TestSupport.referenceDate) {
            self.date = date
        }

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return date
        }

        func set(_ newDate: Date) {
            lock.lock()
            date = newDate
            lock.unlock()
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            date = date.addingTimeInterval(interval)
            lock.unlock()
        }
    }

    /// SplitMix64, so generated test data is the same on every run and platform.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }
}
