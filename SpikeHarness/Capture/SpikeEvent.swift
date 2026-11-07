import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One run of Log Spike Notification, as written to events.jsonl.
///
/// Parameters are kept exactly as Shortcuts passed them: `nil` (key absent in the
/// JSON) means the shortcut left the parameter empty, `""` means it passed empty text.
/// That difference matters for S6.
struct SpikeEvent: Codable, Hashable, Identifiable, Sendable {
    var id: UUID

    /// When Log Spike Notification started running.
    var capturedAt: Date

    // MARK: Parameters

    var app: String?
    var title: String?
    var subtitle: String?
    var body: String?
    /// The Notification variable's date, if the shortcut passed it.
    var date: Date?
    var isTimeSensitive: Bool?
    /// S6: the whole Notification variable, coerced to text by Shortcuts.
    var raw: String?

    // MARK: Device and process state when the intent started

    /// `UIApplication.shared.isProtectedDataAvailable`, read on the main actor.
    /// With a passcode set it turns false about 10 seconds after the phone locks and
    /// true again at unlock, so a capture in the first ~10 s after locking still
    /// reads true. False proves the capture ran while the phone was locked.
    var protectedDataAvailable: Bool
    /// `UIApplication.shared.applicationState`: active, inactive or background.
    var applicationState: String
    var processID: Int32
    var processLaunchedAt: Date
    /// Seconds from process start to this capture. Small values with
    /// `captureIndexInProcess == 1` mean the system launched NT Spike to run the intent.
    var secondsSinceProcessLaunch: Double
    /// 1 for the first capture in this process, 2 for the next, and so on.
    var captureIndexInProcess: Int

    // MARK: Timing

    /// From the start of `perform()` until just before this line was written:
    /// the main-actor hop plus the SQLite insert. The JSON append itself is not included.
    var durationMs: Double
    /// Time spent waiting for the main actor to read the protected-data state.
    var mainActorMs: Double
    /// Opening (if needed) and inserting into the SQLite store.
    var sqliteMs: Double

    // MARK: SQLite result

    var sqliteSucceeded: Bool
    var sqliteEntryID: Int64?
    /// The thrown error, or a note such as "duplicate of 12".
    var sqliteError: String?

    /// Capture time minus the notification's own date, in seconds.
    var delaySeconds: Double? {
        date.map { capturedAt.timeIntervalSince($0) }
    }

    var isLocked: Bool { !protectedDataAvailable }

    var isColdLaunch: Bool { captureIndexInProcess == 1 }

    var displayApp: String {
        guard let app, !app.isEmpty else { return "(no app)" }
        return app
    }

    /// Title, subtitle and body joined for a list row.
    var displayText: String {
        [title, subtitle, body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }
}

/// JSON coding for events.jsonl. Timestamps are ISO 8601 in UTC with milliseconds,
/// so captures one second apart in a burst stay distinguishable.
/// Encoders and decoders are made per use: they are not Sendable.
enum SpikeCoding {
    static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(SpikeCoding.timestamp))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            return try Date(text, strategy: SpikeCoding.timestamp)
        }
        return decoder
    }
}

/// CSV export of the event log, oldest first.
enum SpikeCSV {
    static let columns = [
        "captured_at", "notification_date", "delay_s", "app", "title", "subtitle", "body",
        "is_time_sensitive", "protected_data_available", "locked", "app_state",
        "duration_ms", "main_actor_ms", "sqlite_ms",
        "seconds_since_launch", "capture_index_in_process", "cold_launch", "pid", "process_launched_at",
        "sqlite_ok", "sqlite_entry_id", "sqlite_error", "raw", "event_id",
    ]

    static func make(_ events: [SpikeEvent]) -> String {
        // Local time with offset, so a spreadsheet reads the tester's clock.
        let time = Date.ISO8601FormatStyle(
            timeZoneSeparator: .colon,
            includingFractionalSeconds: true,
            timeZone: .current
        )
        var lines = [columns.joined(separator: ",")]
        for event in events.sorted(by: { $0.capturedAt < $1.capturedAt }) {
            let fields: [String] = [
                event.capturedAt.formatted(time),
                event.date?.formatted(time) ?? "",
                event.delaySeconds.map { String(format: "%.3f", $0) } ?? "",
                text(event.app),
                text(event.title),
                text(event.subtitle),
                text(event.body),
                event.isTimeSensitive.map { String($0) } ?? "",
                String(event.protectedDataAvailable),
                String(event.isLocked),
                event.applicationState,
                String(format: "%.1f", event.durationMs),
                String(format: "%.1f", event.mainActorMs),
                String(format: "%.1f", event.sqliteMs),
                String(format: "%.3f", event.secondsSinceProcessLaunch),
                String(event.captureIndexInProcess),
                String(event.isColdLaunch),
                String(event.processID),
                event.processLaunchedAt.formatted(time),
                String(event.sqliteSucceeded),
                event.sqliteEntryID.map { String($0) } ?? "",
                text(event.sqliteError),
                text(event.raw),
                event.id.uuidString,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Free text from notifications. A leading = + - @ would run as a formula in a
    /// spreadsheet, so it gets an apostrophe in front.
    private static func text(_ value: String?) -> String {
        guard let value, let first = value.first else { return "" }
        return "=+-@".contains(first) ? "'" + value : value
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// What the Export CSV share sheet sends: a .csv file written when the user shares.
struct SpikeCSVExport: Transferable, Sendable {
    let events: [SpikeEvent]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmm"
            let stamp = formatter.string(from: Date())
            let url = FileManager.default.temporaryDirectory
                .appending(path: "NT-Spike-events-\(stamp).csv", directoryHint: .notDirectory)
            try SpikeCSV.make(export.events).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
