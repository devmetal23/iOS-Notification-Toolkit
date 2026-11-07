import Foundation
import Synchronization
import ToolkitCore
import os

// Everything NT Spike writes lives in `<App Group>/Spike/`:
//   events.jsonl    one JSON object per capture (the source of truth for the spikes)
//   History.sqlite  a real SQLiteNotificationStore, so S1/S4 exercise the production store
// Both are created with Complete Until First User Authentication protection, like
// the app's database (NFR-2): readable while locked, but not before the first
// unlock after a restart.

enum SpikeError: LocalizedError {
    case missingAppGroupIdentifier
    case appGroupUnavailable(String)
    case couldNotCreateFile(String)

    var errorDescription: String? {
        switch self {
        case .missingAppGroupIdentifier:
            return "Info.plist has no AppGroupIdentifier. Regenerate the project with XcodeGen."
        case .appGroupUnavailable(let identifier):
            return "App Group \(identifier) is missing from NT Spike's entitlements."
        case .couldNotCreateFile(let path):
            return "Could not create \(path)."
        }
    }
}

/// Paths in the shared App Group container. Self-contained: the identifier comes
/// from Info.plist (`AppGroupIdentifier`, set from `APP_GROUP_ID` in Config/Base.xcconfig).
enum SpikeContainer {
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// `<App Group>/Spike/`, created on first use.
    static func directory() throws -> URL {
        guard let identifier = appGroupIdentifier else { throw SpikeError.missingAppGroupIdentifier }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SpikeError.appGroupUnavailable(identifier)
        }
        let directory = container.appending(path: "Spike", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        return directory
    }

    static func eventsURL() throws -> URL {
        try directory().appending(path: "events.jsonl", directoryHint: .notDirectory)
    }

    static func databaseURL() throws -> URL {
        try directory().appending(path: "History.sqlite", directoryHint: .notDirectory)
    }

    /// The App Group's UserDefaults. Created per call so no non-Sendable value is stored.
    static var defaults: UserDefaults? {
        appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) }
    }
}

/// Harness switches shared between the UI and the intent.
enum SpikeSettings {
    private static let reopenStoreKey = "spike.reopenStoreEachCapture"

    /// S4 fix check: when on, every capture opens the SQLite store and lets it close
    /// afterwards instead of keeping one connection open for the life of the process.
    static var reopenStoreEachCapture: Bool {
        get { SpikeContainer.defaults?.bool(forKey: reopenStoreKey) ?? false }
        set { SpikeContainer.defaults?.set(newValue, forKey: reopenStoreKey) }
    }
}

/// Counts failed writes to events.jsonl. A failed JSON line can't record itself,
/// so the failure goes to the App Group's UserDefaults and the system log instead.
enum SpikeDiagnostics {
    private static let failureCountKey = "spike.eventLogWriteFailures"
    private static let lastFailureKey = "spike.lastEventLogWriteError"
    private static let lock = Mutex(())

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NTSpike", category: "capture")

    static func recordEventLogFailure(_ error: any Error) {
        let message = String(describing: error)
        logger.error("events.jsonl write failed: \(message, privacy: .public)")
        lock.withLock { _ in
            guard let defaults = SpikeContainer.defaults else { return }
            defaults.set(defaults.integer(forKey: failureCountKey) + 1, forKey: failureCountKey)
            defaults.set(message, forKey: lastFailureKey)
        }
    }

    static var eventLogFailureCount: Int {
        SpikeContainer.defaults?.integer(forKey: failureCountKey) ?? 0
    }

    static var lastEventLogFailure: String? {
        SpikeContainer.defaults?.string(forKey: lastFailureKey)
    }

    static func reset() {
        lock.withLock { _ in
            SpikeContainer.defaults?.removeObject(forKey: failureCountKey)
            SpikeContainer.defaults?.removeObject(forKey: lastFailureKey)
        }
    }
}

/// events.jsonl: append-only JSON Lines, one `SpikeEvent` per line.
///
/// The app is one process (App Intents with `openAppWhenRun = false` run inside it,
/// launched in the background if needed), so a process-wide lock serializes
/// concurrent captures during a burst and keeps reads from seeing half a line.
enum SpikeEventLog {
    private static let lock = Mutex(())

    struct Contents: Sendable {
        var events: [SpikeEvent]
        /// Lines that did not decode, e.g. a write cut short by a crash.
        var unreadableLines: Int
    }

    static func append(_ event: SpikeEvent) throws {
        var encoded = try SpikeCoding.makeEncoder().encode(event)
        encoded.append(0x0A)
        let line = encoded
        try lock.withLock { _ in
            let url = try SpikeContainer.eventsURL()
            let path = url.path(percentEncoded: false)
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                let created = fileManager.createFile(
                    atPath: path,
                    contents: nil,
                    attributes: [.protectionKey: SpikeContainer.protection]
                )
                guard created else { throw SpikeError.couldNotCreateFile(path) }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
    }

    static func read() throws -> Contents {
        let data: Data? = try lock.withLock { _ in
            let url = try SpikeContainer.eventsURL()
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try Data(contentsOf: url)
        }
        guard let data else { return Contents(events: [], unreadableLines: 0) }

        let decoder = SpikeCoding.makeDecoder()
        var events: [SpikeEvent] = []
        var unreadable = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(SpikeEvent.self, from: Data(line)) {
                events.append(event)
            } else {
                unreadable += 1
            }
        }
        return Contents(events: events, unreadableLines: unreadable)
    }

    static func clear() throws {
        try lock.withLock { _ in
            let url = try SpikeContainer.eventsURL()
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// The real ToolkitCore store at `<App Group>/Spike/History.sqlite`.
///
/// By default one connection is opened on first use and kept for the life of the
/// process, exactly like `AppGroup.store()` in the app. That is what S4's
/// 0xdead10cc check exercises. `SpikeSettings.reopenStoreEachCapture` switches to
/// open-use-release so a fix can be confirmed without a new build.
enum SpikeStore {
    private static let cached = Mutex<SQLiteNotificationStore?>(nil)

    static func withStore<T>(_ body: (SQLiteNotificationStore) throws -> T) throws -> T {
        if SpikeSettings.reopenStoreEachCapture {
            cached.withLock { slot in slot = nil }
            // Released when this returns; SQLiteNotificationStore closes its connection on deinit.
            let store = try open()
            return try body(store)
        }
        let store = try cached.withLock { slot in
            if let existing = slot { return existing }
            let store = try open()
            slot = store
            return store
        }
        return try body(store)
    }

    private static func open() throws -> SQLiteNotificationStore {
        try SQLiteNotificationStore(url: SpikeContainer.databaseURL())
    }
}
