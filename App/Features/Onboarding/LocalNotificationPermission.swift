import Foundation
import UserNotifications

/// Whether Notification Toolkit may post its own notifications: the test
/// notification (FR-5) and snoozes coming back (FR-14).
///
/// The helpers are nonisolated and `@concurrent`, so `UNNotificationSettings`
/// (not Sendable) is read off the main actor and never crosses an isolation
/// boundary. Callers only ever get this Sendable enum back.
enum LocalNotificationPermission: Sendable, Equatable {
    case notDetermined
    case denied
    case allowed

    @concurrent
    nonisolated static func current() async -> LocalNotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return LocalNotificationPermission(settings.authorizationStatus)
    }

    /// Shows the system prompt if the user hasn't decided yet. Otherwise returns
    /// the current setting without prompting.
    @concurrent
    nonisolated static func request() async -> LocalNotificationPermission {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { return .allowed }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return LocalNotificationPermission(settings.authorizationStatus)
    }

    private init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}
