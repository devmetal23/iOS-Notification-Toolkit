import SwiftUI

/// NT Spike: a throwaway app for validation spikes S1–S6 (docs/spikes.md).
/// Self-contained: it shares only ToolkitCore and the App Group with the real app.
@main
struct SpikeHarnessApp: App {
    @State private var model = SpikeModel()

    init() {
        // Touch the launch time early. The kernel's process start time is used when
        // available; this is only the fallback's reference point.
        _ = ProcessLaunch.date
        SpikeNotificationDelegate.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            SpikeRootView()
                .environment(model)
        }
    }
}

struct SpikeRootView: View {
    var body: some View {
        TabView {
            Tab("Log", systemImage: "list.bullet.rectangle") {
                EventLogView()
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver") {
                TestToolsView()
            }
        }
    }
}
