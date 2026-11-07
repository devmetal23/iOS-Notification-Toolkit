import SwiftUI
import ToolkitCore

/// Setup › How It Works: the onboarding explanation, available any time.
struct HowItWorksView: View {
    var body: some View {
        List {
            if HowItWorksVideo.url != nil {
                Section {
                    HowItWorksVideoSlot()
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Text("Notification Toolkit can't read notifications on its own. Instead, a Shortcuts automation you switch on passes each notification from an app you choose to Notification Toolkit's Log Notification action, which saves it on this iPhone.")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(CaptureExplanation.capturePoints) { ExplanationPointRow(point: $0) }
            } header: {
                Text("How Capture Works")
            }

            Section("Your Privacy") {
                ForEach(CaptureExplanation.privacyPoints) { ExplanationPointRow(point: $0) }
            }

            Section("Good to Know") {
                ExplanationPointRow(point: ExplanationPoint(
                    symbol: "square.stack.3d.up",
                    title: "One automation per app",
                    detail: "Popular apps come ready-made in Add Apps. Any other app can be set up by hand in Other Apps."
                ))
                ExplanationPointRow(point: ExplanationPoint(
                    symbol: "stethoscope",
                    title: "Health Check",
                    detail: "Shows when each app last logged, and flags any that have gone quiet for a week."
                ))
                ExplanationPointRow(point: ExplanationPoint(
                    symbol: "pause.circle",
                    title: "Pausing",
                    detail: "While logging is paused from Control Center, nothing is saved."
                ))
            }
        }
        .navigationTitle("How It Works")
    }
}

#Preview {
    NavigationStack {
        HowItWorksView()
    }
}
