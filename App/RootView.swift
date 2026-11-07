import SwiftUI
import ToolkitCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AppLockGate {
            if model.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        .task { await model.start() }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Snoozed", systemImage: "moon.zzz", value: AppTab.snoozed) {
                SnoozedListView()
            }
            Tab("Setup", systemImage: "square.stack.3d.up", value: AppTab.setup) {
                SetupHomeView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview())
}
