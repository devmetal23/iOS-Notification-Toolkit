import SwiftUI
import ToolkitCore

/// Screens pushed from the Setup tab.
enum SetupRoute: Hashable {
    case catalog
    case otherApps
    case healthCheck
    case testCapture
    case howItWorks
}

/// The Shortcuts app. Apple documents no link straight to its Automation tab,
/// so instructions always say "tap Automation".
enum ShortcutsAppLink {
    static let url = URL(string: "shortcuts://")!
}

// MARK: - Set-up apps

extension AppModel {
    /// Apps the user has set up, oldest first. Leaves out Notification Toolkit
    /// itself: its test notification never shows up as an app or uses a slot.
    func setUpApps() throws -> [TrackedApp] {
        CaptureGate.appsCountingTowardLimit(try store().trackedApps())
    }

    /// True when the free tier stops the user adding `displayName`: not Pro,
    /// already at the app limit, and that app isn't set up yet.
    func needsProToAdd(displayName: String) throws -> Bool {
        guard !entitlements.isPro, let maxApps = TierLimits.free.maxApps else { return false }
        let key = AppKey(appName: displayName)
        guard key != .ownApp else { return false }
        let apps = try setUpApps()
        return !apps.contains { $0.key == key } && apps.count >= maxApps
    }

    /// Records an app set up from the catalog (`catalogID`) or the guided flow (nil).
    @discardableResult
    func registerSetUpApp(displayName: String, catalogID: String?, at date: Date = Date()) throws -> TrackedApp {
        let app = try store().registerApp(displayName: displayName, catalogID: catalogID, at: date)
        historyDidChange()
        return app
    }

    /// Stops tracking an app. Its saved notifications stay in History.
    func stopTracking(_ key: AppKey) throws {
        try store().removeApp(key)
        historyDidChange()
    }

    /// Health of every set-up app (FR-4), plus what the free tier is blocking.
    func setupReport(now: Date = Date()) throws -> SetupReport {
        let apps = try setUpApps()
        let tier: Tier = entitlements.isPro ? .pro : .free
        let overLimit = apps
            .filter { CaptureGate.decide(app: $0.key, tier: tier, trackedApps: apps) == .blockedByAppLimit }
            .map(\.key)
        return SetupReport(
            health: HealthCheck.evaluate(apps, now: now),
            overLimit: Set(overLimit),
            isLoggingPaused: settings.isLoggingPaused
        )
    }

    /// Setup screens reload with `.task(id:)` on this: after any history change,
    /// when Pro status changes, and when the app comes back from Shortcuts.
    func setupReloadKey(_ scenePhase: ScenePhase) -> SetupReloadKey {
        SetupReloadKey(revision: historyRevision, isPro: entitlements.isPro, isActive: scenePhase == .active)
    }
}

struct SetupReloadKey: Hashable {
    var revision: Int
    var isPro: Bool
    var isActive: Bool
}

struct SetupReport: Equatable {
    /// Needing attention first, then by name.
    var health: [HealthCheck.AppHealth] = []
    /// Free tier only: apps past the app limit, whose notifications aren't saved.
    var overLimit: Set<AppKey> = []
    var isLoggingPaused = false

    var appCount: Int { health.count }

    func needsAttention(_ item: HealthCheck.AppHealth) -> Bool {
        item.needsAttention || overLimit.contains(item.id)
    }

    var needingAttention: [HealthCheck.AppHealth] { health.filter { needsAttention($0) } }
    var working: [HealthCheck.AppHealth] { health.filter { !needsAttention($0) } }
    var attentionCount: Int { needingAttention.count }
}

enum SetupErrorMessage {
    static func text(for error: any Error) -> String {
        if let error = error as? StoreError, error == .unavailable {
            return String(localized: "Your history is locked until you unlock this iPhone. Unlock it and try again.")
        }
        return String(localized: "Your setup couldn't be updated. Try again.")
    }
}

extension View {
    func setupErrorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        alert("Something Went Wrong", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

// MARK: - Numbered steps

// Shortcuts labels quoted in steps ("Automation", "When I receive a notification from",
// "Run Immediately", "Notify When Run") follow the iOS 27 betas. They must be confirmed
// on a device (spikes S5, S6) and re-checked every June beta: see docs/shortcuts.md.

struct SetupStep {
    var symbol: String
    var title: LocalizedStringResource
    var detail: LocalizedStringResource?
}

/// One numbered instruction with an SF Symbol, read by VoiceOver as "Step 2, …".
struct NumberedStepRow: View {
    let number: Int
    let step: SetupStep

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize = 28.0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.tint)
                .frame(minWidth: badgeSize, minHeight: badgeSize)
                .background {
                    Circle().fill(.tint).opacity(0.15)
                }
                .accessibilityLabel(Text("Step \(number)"))
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(step.title)
                        .font(.headline)
                } icon: {
                    Image(systemName: step.symbol)
                        .foregroundStyle(.tint)
                }
                if let detail = step.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Numbered rows for a list of steps, starting at 1.
struct NumberedSteps: View {
    let steps: [SetupStep]

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            NumberedStepRow(number: index + 1, step: step)
        }
    }
}

#Preview("Steps") {
    List {
        NumberedSteps(steps: [
            SetupStep(symbol: "arrow.up.forward.app", title: "Open Shortcuts", detail: "Then tap Automation."),
            SetupStep(symbol: "switch.2", title: "Switch it on", detail: nil),
        ])
    }
}
