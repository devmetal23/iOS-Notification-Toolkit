import Foundation
import ToolkitCore
import WidgetKit

/// Keeps widgets current without spending their daily reload budget on bursts.
enum WidgetRefresher {
    /// Minimum gap between reloads triggered by captures.
    static let captureReloadInterval: TimeInterval = 5 * 60

    /// Call after Log Notification stores an entry. Reloads at most every 5 minutes;
    /// the widget's own timeline refresh picks up anything in between.
    static func captureDidStore(settings: SharedSettings, now: Date = Date()) {
        if let last = settings.lastWidgetReloadAt, now.timeIntervalSince(last) < captureReloadInterval {
            return
        }
        settings.lastWidgetReloadAt = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Call after a change the user just made: deletes, pause toggle, widget privacy setting.
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
