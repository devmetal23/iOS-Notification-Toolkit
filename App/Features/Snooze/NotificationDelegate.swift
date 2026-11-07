import Foundation
import ToolkitCore
import UserNotifications

/// Shows snoozed and test notifications while the app is open and routes taps.
///
/// Installed from `NotificationToolkitApp.init()`, before launch finishes, so a
/// tap that cold-launches the app reaches it.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Called with the entry ID when the user taps a snooze that came back.
    /// `AppModel.start()` sets it. A tap that arrives first is delivered once it's set.
    var onOpenEntry: ((NotificationEntry.ID) -> Void)? {
        didSet { deliverQueuedEntry() }
    }

    /// A tapped entry waiting for `onOpenEntry`, e.g. after a cold launch.
    private var queuedEntryID: NotificationEntry.ID?

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate
    //
    // The center may call these off the main thread, so they are nonisolated. They
    // read what they need from the non-Sendable notification objects first and
    // only hop to the main actor with Sendable values.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Only Notification Toolkit's own notifications reach this delegate:
        // snoozes coming back and the test notification.
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let entryID = SnoozeUserInfo.entryID(in: response.notification.request.content.userInfo)
        else { return }
        await open(entryID)
    }

    // MARK: - Routing

    private func open(_ entryID: NotificationEntry.ID) {
        if let onOpenEntry {
            onOpenEntry(entryID)
        } else {
            queuedEntryID = entryID
        }
    }

    private func deliverQueuedEntry() {
        guard let entryID = queuedEntryID, let onOpenEntry else { return }
        queuedEntryID = nil
        onOpenEntry(entryID)
    }
}
