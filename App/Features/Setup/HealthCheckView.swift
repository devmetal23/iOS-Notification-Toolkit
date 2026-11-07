import SwiftUI
import ToolkitCore

/// Every set-up app with when it last logged (FR-4). Apps quiet for 7 days or
/// more are flagged with troubleshooting tips; free-tier apps past the limit
/// offer Upgrade. Swipe to stop tracking an app.
struct HealthCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var report = SetupReport()
    @State private var hasLoaded = false
    @State private var appToRemove: TrackedApp?
    @State private var showsRemoveDialog = false
    @State private var showsPaywall = false
    @State private var showsError = false
    @State private var errorText = ""

    var body: some View {
        List {
            if report.isLoggingPaused {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Logging is paused")
                                .font(.headline)
                            Text("Nothing is saved until you resume it from Control Center.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !report.needingAttention.isEmpty {
                Section("Needs Attention") {
                    rows(report.needingAttention)
                }
            }

            if !report.working.isEmpty {
                Section("Set Up") {
                    rows(report.working)
                }
            }

            if !report.needingAttention.isEmpty {
                Section {
                    NumberedSteps(steps: Self.tips)
                    Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                        openURL(ShortcutsAppLink.url)
                    }
                    NavigationLink(value: SetupRoute.testCapture) {
                        Label("Run Test Capture", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("If an App Goes Quiet")
                }
            }
        }
        .overlay {
            if hasLoaded && report.health.isEmpty {
                ContentUnavailableView {
                    Label("No Apps Set Up", systemImage: "stethoscope")
                } description: {
                    Text("Apps you set up appear here with when each one last logged a notification.")
                } actions: {
                    NavigationLink("Add Apps", value: SetupRoute.catalog)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Health Check")
        .task(id: model.setupReloadKey(scenePhase)) { reload() }
        .confirmationDialog(
            "Stop Tracking This App?",
            isPresented: $showsRemoveDialog,
            titleVisibility: .visible,
            presenting: appToRemove
        ) { app in
            Button("Stop Tracking \(app.displayName)", role: .destructive) {
                stopTracking(app)
            }
            Button("Open Shortcuts") {
                openURL(ShortcutsAppLink.url)
            }
        } message: { app in
            Text("Also switch off or delete its automation in Shortcuts, or the next \(app.displayName) notification adds it back. Notifications already saved stay in History.")
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .setupErrorAlert(isPresented: $showsError, message: errorText)
    }

    private func rows(_ items: [HealthCheck.AppHealth]) -> some View {
        ForEach(items) { item in
            AppHealthRow(
                health: item,
                isOverLimit: report.overLimit.contains(item.id),
                showsBlockedCount: !model.entitlements.isPro,
                upgrade: { showsPaywall = true }
            )
            // Swipe actions are also offered to VoiceOver as actions.
            .swipeActions(edge: .trailing) {
                Button("Stop Tracking", systemImage: "minus.circle") {
                    appToRemove = item.app
                    showsRemoveDialog = true
                }
                .tint(.red)
            }
        }
    }

    private func reload() {
        defer { hasLoaded = true }
        do {
            report = try model.setupReport()
        } catch {
            report = SetupReport()
            errorText = SetupErrorMessage.text(for: error)
            showsError = true
        }
    }

    private func stopTracking(_ app: TrackedApp) {
        do {
            try model.stopTracking(app.key)
            reload()
        } catch {
            errorText = SetupErrorMessage.text(for: error)
            showsError = true
        }
    }

    private static let tips = [
        SetupStep(
            symbol: "switch.2",
            title: "Check the automation is on",
            detail: "In Shortcuts, tap Automation. Automations from shared shortcuts arrive switched off."
        ),
        SetupStep(
            symbol: "bolt.circle",
            title: "Choose Run Immediately",
            detail: "If the automation asks before running, nothing is logged until you tap."
        ),
        SetupStep(
            symbol: "character.cursor.ibeam",
            title: "Check the App field",
            detail: "In Log Notification, App should be the app's name, typed exactly as it appears here."
        ),
        SetupStep(
            symbol: "bell.badge",
            title: "Check the app's notifications",
            detail: "In Settings › Notifications, make sure the app is allowed to send notifications."
        ),
        SetupStep(
            symbol: "moon.zzz",
            title: "Some apps are just quiet",
            detail: "If the app hasn't sent anything in a while, there's nothing to fix."
        ),
    ]
}

private struct AppHealthRow: View {
    let health: HealthCheck.AppHealth
    let isOverLimit: Bool
    let showsBlockedCount: Bool
    let upgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(health.app.displayName)
                .font(.headline)
            lastLogged
                .font(.subheadline)
                .foregroundStyle(.secondary)
            status
                .font(.subheadline)
            if isOverLimit || (showsBlockedCount && health.app.blockedCount > 0) {
                limitNotice
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var lastLogged: some View {
        if let lastLoggedAt = health.app.lastLoggedAt {
            Text("Last logged \(lastLoggedAt, format: .relative(presentation: .named))")
        } else {
            Text("Nothing logged yet. Added \(health.app.addedAt, format: .relative(presentation: .named)).")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch health.status {
        case .healthy:
            statusLabel("Logging", symbol: "checkmark.circle.fill", color: .green)
        case .awaitingFirstCapture(overdue: false):
            statusLabel("Waiting for its first notification", symbol: "clock", color: .secondary)
        case .awaitingFirstCapture(overdue: true):
            statusLabel("Nothing logged in the week since you added it", symbol: "exclamationmark.triangle.fill", color: .orange)
        case .silent:
            statusLabel("Quiet for 7 days or more", symbol: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    private func statusLabel(_ title: LocalizedStringKey, symbol: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }

    private var limitNotice: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if isOverLimit {
                    Text("Not being saved: Free includes 3 apps.")
                }
                if health.app.blockedCount > 0 {
                    Text("^[\(health.app.blockedCount) notification](inflect: true) not saved")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Upgrade", action: upgrade)
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    NavigationStack {
        HealthCheckView()
    }
    .environment(AppModel.preview())
}
