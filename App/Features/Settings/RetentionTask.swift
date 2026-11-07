import BackgroundTasks
import Foundation
import ToolkitCore
import UserNotifications

/// Automatic cleanup (FR-12): runs at launch and as a background app refresh task.
///
/// Nonisolated and independent of `AppModel`, so the background task can run it
/// without the UI. `@concurrent` keeps the store work off the caller's actor.
enum RetentionTask {
    /// Must match BGTaskSchedulerPermittedIdentifiers in project.yml.
    static let identifier = "\(Bundle.main.bundleIdentifier ?? "com.devmetal23.notificationtoolkit").retention"

    /// How long until the system may run the next cleanup.
    static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// Deletes entries older than the effective retention, cancels the snoozes that
    /// went with them, and schedules the next background run.
    @concurrent
    static func run() async {
        defer { scheduleNextRun() }

        let settings = AppGroup.settings
        let now = Date()
        let result: DeletionResult
        do {
            result = try AppGroup.store().applyRetention(settings.effectiveRetention, now: now)
        } catch {
            // Most likely the store is protected until the first unlock after a
            // restart (NFR-2). The next launch or background run tries again.
            return
        }
        settings.lastRetentionRunAt = now

        let requestIDs = result.cancelledSnoozeRequestIdentifiers
        if !requestIDs.isEmpty {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: requestIDs)
            center.removeDeliveredNotifications(withIdentifiers: requestIDs)
        }
        if result.entriesDeleted > 0 {
            WidgetRefresher.reloadAll()
            HistoryChangeNotifier.post()
        }
    }

    /// Asks for the next background run about 12 hours from now. Submitting again
    /// replaces the pending request, so calling this on every run is safe.
    static func scheduleNextRun(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Unavailable in the simulator or when Background App Refresh is off.
            // Launch-time cleanup and the capture pipeline still apply retention.
        }
    }
}
