import Foundation
import ToolkitCore

// CONTRACT STUB — workstream W6 replaces the bodies. Keep the signatures.

/// Starts a snooze from anywhere in the app: Pro gating (paywall), notification
/// permission errors, the custom-time picker, and confirmation (FR-14). Presents
/// its own UI, so callers such as a list-level `confirmationDialog` only pick.
@MainActor
enum SnoozeFlow {
    /// Snoozes with `option`, or presents the paywall when the user isn't Pro.
    static func choose(_ option: SnoozeOption, for entry: NotificationEntry, model: AppModel) async {}

    /// Presents the custom date picker, or the paywall when the user isn't Pro.
    static func chooseCustomTime(for entry: NotificationEntry, model: AppModel) {}
}
