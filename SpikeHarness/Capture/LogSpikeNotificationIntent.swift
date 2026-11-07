import AppIntents
import Foundation

/// NT Spike's stand-in for Log Notification, for spikes S1–S6 (docs/spikes.md).
///
/// A tester adds it to a "When I receive a notification from …" automation and maps
/// the Notification variable's fields onto these parameters. It runs in the
/// background without opening NT Spike, shows nothing and returns nothing, and
/// writes one line to `<App Group>/Spike/events.jsonl` plus one row to the real
/// SQLite store at `<App Group>/Spike/History.sqlite`.
struct LogSpikeNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Spike Notification"
    static let description = IntentDescription(
        "Records a notification for the NT Spike validation spikes. Runs in the background without opening NT Spike."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "App",
        description: "The app the notification came from: the Notification variable's app if it has one, otherwise the app name typed as text."
    )
    var app: String?

    @Parameter(title: "Title")
    var notificationTitle: String?

    @Parameter(title: "Subtitle")
    var subtitle: String?

    @Parameter(title: "Body", description: "The notification's message text.")
    var body: String?

    @Parameter(title: "Date", description: "When the notification arrived, from the Notification variable.")
    var date: Date?

    @Parameter(title: "Time Sensitive")
    var isTimeSensitive: Bool?

    @Parameter(title: "Raw", description: "For S6: the whole Notification variable, with no property chosen.")
    var raw: String?

    func perform() async throws -> some IntentResult {
        let start = ContinuousClock.now
        let capturedAt = Date()
        let input = SpikeCaptureInput(
            app: app,
            title: notificationTitle,
            subtitle: subtitle,
            body: body,
            date: date,
            isTimeSensitive: isTimeSensitive,
            raw: raw
        )
        await SpikeRecorder.record(input, startedAt: start, capturedAt: capturedAt)
        return .result()
    }
}
