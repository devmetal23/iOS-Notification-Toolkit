import Foundation
import UserNotifications

/// How test notifications are delivered.
struct SpikeNotificationOptions: Hashable, Sendable {
    enum Level: String, CaseIterable, Identifiable, Hashable, Sendable {
        case active
        case passive
        case timeSensitive

        var id: Self { self }

        var label: String {
            switch self {
            case .active: return "Active"
            case .passive: return "Passive"
            case .timeSensitive: return "Time-sensitive"
            }
        }
    }

    var level: Level = .active
    /// Title and subtitle only, to check the trigger fires without message text (S1).
    var noBody = false

    var summary: String {
        noBody ? "\(level.label), no body" : level.label
    }
}

/// A local notification to schedule. Plain values, so it can cross to the helper below.
struct PlannedNotification: Sendable {
    var identifier: String
    var title: String
    var subtitle: String
    var body: String
    var level: SpikeNotificationOptions.Level
    var threadIdentifier: String
    var fireDate: Date
}

/// Notification permission and settings, as plain values for the UI.
struct PermissionSnapshot: Hashable, Sendable {
    struct Row: Hashable, Sendable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    var isAuthorized: Bool
    var isUndetermined: Bool
    var rows: [Row]
    var pendingCount: Int
}

/// UserNotifications calls. Every function runs off the main actor and creates the
/// center and its non-Sendable objects locally, returning only Sendable values.
enum NotificationPoster {
    /// iOS keeps at most 64 pending local notifications per app and drops the rest.
    static let burstLimit = 60

    @concurrent
    static func permission() async -> PermissionSnapshot {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pendingCount = await center.pendingNotificationRequests().count
        let rows: [PermissionSnapshot.Row] = [
            .init(label: "Permission", value: describe(settings.authorizationStatus)),
            .init(label: "Alerts", value: describe(settings.alertSetting)),
            .init(label: "Lock Screen", value: describe(settings.lockScreenSetting)),
            .init(label: "Notification Center", value: describe(settings.notificationCenterSetting)),
            .init(label: "Sounds", value: describe(settings.soundSetting)),
            .init(label: "Time Sensitive", value: describe(settings.timeSensitiveSetting)),
            .init(label: "Scheduled Summary", value: describe(settings.scheduledDeliverySetting)),
            .init(label: "Show Previews", value: describe(settings.showPreviewsSetting)),
        ]
        return PermissionSnapshot(
            isAuthorized: settings.authorizationStatus == .authorized,
            isUndetermined: settings.authorizationStatus == .notDetermined,
            rows: rows,
            pendingCount: pendingCount
        )
    }

    @concurrent
    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    @concurrent
    static func schedule(_ notifications: [PlannedNotification]) async throws {
        let center = UNUserNotificationCenter.current()
        for planned in notifications {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.subtitle = planned.subtitle
            content.body = planned.body
            content.sound = .default
            content.threadIdentifier = planned.threadIdentifier
            switch planned.level {
            case .active: content.interruptionLevel = .active
            case .passive: content.interruptionLevel = .passive
            case .timeSensitive: content.interruptionLevel = .timeSensitive
            }
            // Measured at add time so a long burst doesn't drift.
            let delay = max(1, planned.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)
            try await center.add(request)
        }
    }

    @concurrent
    static func cancelPending() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private static func describe(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "On"
        case .disabled: return "Off"
        case .notSupported: return "Not supported"
        @unknown default: return "Unknown"
        }
    }

    private static func describe(_ setting: UNShowPreviewsSetting) -> String {
        switch setting {
        case .always: return "Always"
        case .whenAuthenticated: return "When Unlocked"
        case .never: return "Never"
        @unknown default: return "Unknown"
        }
    }
}

/// Shows NT Spike's own notifications as banners while it is open, so a test
/// posted with the app in front behaves like one posted from the Home Screen.
@MainActor
final class SpikeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SpikeNotificationDelegate()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
