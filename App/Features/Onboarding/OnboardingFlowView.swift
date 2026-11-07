import SwiftUI
import ToolkitCore

// CONTRACT STUB — workstream W5 replaces this file.

/// Explains Shortcuts-based capture and walks through switching automations on (FR-1).
/// Finishes with `model.selectedTab = .setup` then `model.hasCompletedOnboarding = true`.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Get started") {
            model.selectedTab = .setup
            model.hasCompletedOnboarding = true
        }
    }
}
