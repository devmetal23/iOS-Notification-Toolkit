import AppIntents
import SwiftUI
import ToolkitCore
import WidgetKit

/// Control Center, Lock Screen and Action button toggle that pauses and resumes
/// logging (FR-18). Free users see "Requires Pro" and tapping it changes nothing.
struct LoggingControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LoggingControlKind.kind, provider: LoggingControlProvider()) { state in
            ControlWidgetToggle(
                "Notification Logging",
                isOn: state.isToggleOn,
                action: SetLoggingActiveIntent()
            ) { isOn in
                Label {
                    Text(state.valueTitle(isOn: isOn))
                } icon: {
                    Image(systemName: state.valueSymbol(isOn: isOn))
                }
            }
        }
        .displayName("Notification Logging")
        .description("Pause or resume saving notifications to your history. Requires Pro.")
    }
}

/// What the control shows, read from App Group settings.
struct LoggingControlState: Hashable, Sendable {
    /// Logging is on (not paused).
    var isActive: Bool
    var isPro: Bool

    /// Free users always see the toggle off, since pausing is a Pro feature.
    var isToggleOn: Bool { isPro && isActive }

    func valueTitle(isOn: Bool) -> LocalizedStringResource {
        if !isPro { return "Requires Pro" }
        if isOn { return "Logging" }
        return "Paused"
    }

    func valueSymbol(isOn: Bool) -> String {
        if !isPro { return "lock" }
        return isOn ? "bell" : "bell.slash"
    }

    static func current(settings: SharedSettings = AppGroup.settings) -> LoggingControlState {
        LoggingControlState(isActive: !settings.isLoggingPaused, isPro: settings.isPro)
    }
}

struct LoggingControlProvider: ControlValueProvider {
    /// Shown in the controls gallery: what a Pro user gets.
    var previewValue: LoggingControlState {
        LoggingControlState(isActive: true, isPro: true)
    }

    func currentValue() async throws -> LoggingControlState {
        .current()
    }
}
