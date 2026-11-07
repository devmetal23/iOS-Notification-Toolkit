import Foundation
import ToolkitCore
import UserNotifications

// CONTRACT STUB — workstream W6 replaces this file. Keep `shared`, `install()` and `onOpenEntry`.

/// Shows snoozed and test notifications while the app is open and routes taps.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Called with the entry ID when the user taps a snooze that came back.
    /// `AppModel.start()` sets it. A tap that arrives first is delivered once it's set.
    var onOpenEntry: ((NotificationEntry.ID) -> Void)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }
}
