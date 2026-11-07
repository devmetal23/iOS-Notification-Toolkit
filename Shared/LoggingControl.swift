import AppIntents
import Foundation
import ToolkitCore
import WidgetKit

/// Identifies the Control Center logging toggle (FR-18), so the app and the
/// intent can reload just that control.
enum LoggingControlKind {
    static let kind = "com.devmetal23.notificationtoolkit.widgets.logging"
}

/// Pauses or resumes logging from the Control Center toggle (FR-18). Pro only.
///
/// Compiled into the app and the widget extension, so the control works whichever
/// process the system runs it in. It only touches App Group defaults, which keeps it
/// well inside the time a control action gets. `openAppWhenRun` keeps its default
/// (false) for every tier: App Intents reads it as static metadata, so it can't
/// depend on the cached entitlement.
struct SetLoggingActiveIntent: SetValueIntent {
    static var title: LocalizedStringResource { "Set Notification Logging" }

    static var description: IntentDescription {
        IntentDescription("Pauses or resumes saving notifications to your history. Requires Pro.")
    }

    /// Only the control uses this intent; Shortcuts users have their own automations.
    static var isDiscoverable: Bool { false }

    /// True when logging is active, false when it is paused.
    @Parameter(title: "Logging Active")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let settings = AppGroup.settings
        if settings.isPro {
            settings.isLoggingPaused = !value
            // Widgets show a paused badge, so reload them along with the control.
            WidgetRefresher.reloadAll()
        } else {
            // Free tier: leave the setting alone and let the control snap back to
            // its "Requires Pro" state.
            ControlCenter.shared.reloadControls(ofKind: LoggingControlKind.kind)
        }
        return .result()
    }
}
