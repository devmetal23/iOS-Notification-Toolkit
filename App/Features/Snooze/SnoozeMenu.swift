import SwiftUI
import ToolkitCore

/// "Snooze" menu with the presets and a custom time (FR-14), for a row's
/// `.contextMenu` and the entry detail toolbar. Not for `.swipeActions`, where
/// menus aren't reliable: rows use a button plus `SnoozeFlow` instead.
///
/// Every item goes through `SnoozeFlow`, which handles Pro gating, permission
/// errors and confirmation.
struct SnoozeMenu: View {
    let entry: NotificationEntry

    @Environment(AppModel.self) private var model

    init(entry: NotificationEntry) {
        self.entry = entry
    }

    var body: some View {
        Menu("Snooze", systemImage: "moon.zzz") {
            ForEach(SnoozeOption.presets) { option in
                Button(option.displayTitle(morningHour: model.settings.morningHour)) {
                    Task { await SnoozeFlow.choose(option, for: entry, model: model) }
                }
            }
            Divider()
            Button("Choose Time…", systemImage: "calendar") {
                SnoozeFlow.chooseCustomTime(for: entry, model: model)
            }
        }
    }
}

#Preview {
    NavigationStack {
        List {
            Text("Touch and hold for the snooze menu")
                .contextMenu {
                    SnoozeMenu(entry: .snoozeMenuPreview)
                }
        }
        .navigationTitle("Snooze Menu")
        .toolbar {
            SnoozeMenu(entry: .snoozeMenuPreview)
        }
    }
    .environment(AppModel.preview())
}

private extension NotificationEntry {
    static let snoozeMenuPreview = NotificationEntry(
        id: 1,
        appKey: AppKey(appName: "Slack"),
        appName: "Slack",
        title: "#launch",
        subtitle: "",
        body: "Build 214 is on TestFlight",
        receivedAt: Date(),
        capturedAt: Date(),
        isTimeSensitive: false
    )
}
