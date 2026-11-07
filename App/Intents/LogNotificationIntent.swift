import AppIntents
import Foundation
import ToolkitCore

/// Saves one notification to the on-device history (FR-6).
///
/// Runs from the user's "When I receive a notification" automations, usually while
/// the iPhone is locked, so it must finish in under a second without opening the
/// app (NFR-4). It deliberately touches nothing but the App Group store and
/// settings: no `AppModel`, SwiftUI or StoreKit, and no dialogs.
struct LogNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Notification"

    static let description = IntentDescription(
        "Saves a notification to your history on this iPhone. Use it in a “When I receive a notification” automation and pass in the notification's app, title, message and date. Runs in the background without opening Notification Toolkit.",
        categoryName: "History",
        searchKeywords: ["notification", "history", "log", "save", "automation"]
    )

    static let openAppWhenRun = false

    /// Stored as the app's name and key, so it isn't localized: changing the
    /// device language must not split one app's history in two.
    static let unknownAppName = "Unknown App"

    @Parameter(
        title: "App",
        description: "The app that sent the notification. Pass the notification's App."
    )
    var app: String

    @Parameter(title: "Title", description: "The notification's title.")
    var notificationTitle: String?

    @Parameter(title: "Subtitle", description: "The notification's subtitle, if it has one.")
    var subtitle: String?

    @Parameter(title: "Message", description: "The notification's body text.")
    var message: String?

    @Parameter(
        title: "Date",
        description: "When the notification arrived. Leave empty to use the current time."
    )
    var date: Date?

    @Parameter(
        title: "Time Sensitive",
        description: "Whether the notification was marked Time Sensitive.",
        default: false
    )
    var isTimeSensitive: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Log notification from \(\.$app) with title \(\.$notificationTitle) and message \(\.$message)") {
            \.$subtitle
            \.$date
            \.$isTimeSensitive
        }
    }

    func perform() async throws -> some IntentResult {
        let notification = makeNotification(now: Date())
        let settings = AppGroup.settings

        let store: SQLiteNotificationStore
        do {
            store = try AppGroup.store()
        } catch StoreError.unavailable {
            throw LogNotificationError.protectedDataUnavailable
        }

        // Paused, duplicate, own-app echo and over-the-limit captures are expected
        // outcomes, not failures, so the automation never shows an error for them.
        let outcome = try CaptureService(store: store, settings: settings).capture(notification)
        if case .stored = outcome {
            WidgetRefresher.captureDidStore(settings: settings)
            HistoryChangeNotifier.post()
        }
        return .result()
    }

    private func makeNotification(now: Date) -> NewNotification {
        let appName = app.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewNotification(
            appName: appName.isEmpty ? Self.unknownAppName : appName,
            title: notificationTitle ?? "",
            subtitle: subtitle ?? "",
            body: message ?? "",
            receivedAt: date ?? now,
            isTimeSensitive: isTimeSensitive
        )
    }
}

enum LogNotificationError: Error, CustomLocalizedStringResourceConvertible {
    /// The database is encrypted until the first unlock after a restart (NFR-2).
    case protectedDataUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .protectedDataUnavailable:
            "Notification Toolkit can't save notifications until you unlock your iPhone for the first time after it restarts."
        }
    }
}
