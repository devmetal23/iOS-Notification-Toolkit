import SwiftUI
import ToolkitCore

// CONTRACT STUB — workstream W6 replaces this file. Keep the initializer.

/// "Snooze" menu with the presets and a custom time (FR-14), for a row's
/// `.contextMenu` and the entry detail toolbar. Not for `.swipeActions`, where
/// menus aren't reliable: rows use a button plus `SnoozeFlow` instead.
struct SnoozeMenu: View {
    let entry: NotificationEntry

    var body: some View {
        Menu("Snooze", systemImage: "moon.zzz") {}
    }
}
