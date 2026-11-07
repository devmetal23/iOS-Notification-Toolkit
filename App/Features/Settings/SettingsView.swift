import SwiftUI
import ToolkitCore

/// Retention, delete, pause, app lock, widget privacy, Pro status (FR-12, FR-13, NFR-3).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    // Mirrors of SharedSettings, which isn't observable. Reloaded on appear and when
    // the app becomes active, since the Control Center toggle can change pause.
    @State private var retention: RetentionPolicy = .thirtyDays
    @State private var isLoggingPaused = false
    @State private var isAppLockEnabled = false
    @State private var showsTextInWidgets = false

    @State private var pendingRetention: PendingRetention?
    @State private var isApplyingRetention = false
    @State private var showsPaywall = false

    private var isPro: Bool { model.entitlements.isPro }

    /// The retention cleanup actually applies: the free tier is capped at 7 days.
    private var effectiveRetention: RetentionPolicy {
        TierLimits(for: isPro ? .pro : .free).cappedRetention(retention)
    }

    var body: some View {
        NavigationStack {
            Form {
                historySection
                loggingSection
                privacySection
                proSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadSettings)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadSettings() }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
                    .environment(model)
            }
            .confirmationDialog(
                "Delete Older Notifications?",
                isPresented: isConfirmingRetention,
                titleVisibility: .visible,
                presenting: pendingRetention
            ) { pending in
                Button("Delete Notifications Older Than \(pending.days) Days", role: .destructive) {
                    apply(pending.policy, cleanUpNow: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                if let count = pending.expiringCount {
                    Text("\(count) notifications older than \(pending.days) days will be deleted now. This can't be undone.")
                } else {
                    Text("Notifications older than \(pending.days) days will be deleted now. This can't be undone.")
                }
            }
        }
    }

    // MARK: Sections

    private var historySection: some View {
        Section {
            ForEach(RetentionPolicy.allCases, id: \.self) { policy in
                retentionRow(policy)
            }
            NavigationLink {
                ManageHistoryView()
            } label: {
                Label("Manage History", systemImage: "tray.full")
            }
        } header: {
            Text("Keep History")
        } footer: {
            if isPro {
                Text("Older notifications are deleted automatically. Notifications you snoozed are kept until they come back.")
            } else {
                Text("The free version keeps 7 days of history. Upgrade to Pro to keep it longer.")
            }
        }
    }

    private func retentionRow(_ policy: RetentionPolicy) -> some View {
        let isLocked = !isPro && TierLimits.free.cappedRetention(policy) != policy
        let isSelected = policy == effectiveRetention
        return Button {
            select(policy)
        } label: {
            HStack {
                Text(policy.settingsTitle)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isLocked {
                    SettingsProBadge()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isApplyingRetention)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isLocked ? Text("Requires Pro. Opens the upgrade screen.") : Text(verbatim: ""))
    }

    private var loggingSection: some View {
        Section {
            Toggle(isOn: loggingPausedBinding) {
                Label("Pause Logging", systemImage: "pause.circle")
            }
        } footer: {
            Text("While logging is paused, new notifications aren't saved. Your automations keep running. You can also pause from Control Center.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: appLockBinding) {
                Label("Require Face ID", systemImage: "faceid")
            }
            .disabled(!AppLock.isAvailable)

            Toggle(isOn: widgetTextBinding) {
                Label("Show Notification Text in Widgets", systemImage: "text.below.photo")
            }
        } header: {
            Text("Privacy")
        } footer: {
            if AppLock.isAvailable {
                Text("Face ID is required to open Notification Toolkit. Widgets show only app names and counts unless you allow notification text.")
            } else {
                Text("To lock Notification Toolkit, set up Face ID or a passcode in the Settings app. Widgets show only app names and counts unless you allow notification text.")
            }
        }
    }

    private var proSection: some View {
        Section {
            if isPro {
                LabeledContent {
                    Text("Active")
                } label: {
                    Label("Notification Toolkit Pro", systemImage: "checkmark.seal.fill")
                }
            } else {
                LabeledContent {
                    Text("Free")
                } label: {
                    Label("Plan", systemImage: "person.crop.circle")
                }
                Button {
                    showsPaywall = true
                } label: {
                    Label("Upgrade to Pro", systemImage: "sparkles")
                }
            }
            NavigationLink {
                StatsView()
            } label: {
                HStack {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                    if !isPro {
                        Spacer()
                        SettingsProBadge()
                    }
                }
            }
        } header: {
            Text("Pro")
        } footer: {
            if !isPro {
                Text("Pro adds unlimited apps, longer history, snooze, widgets and stats.")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Notification content never leaves your iPhone. It's stored only on this device, left out of backups, and the app has no account, analytics or tracking.")
                .font(.callout)
            LabeledContent("Version", value: Self.versionText)
        }
    }

    // MARK: Retention

    private func select(_ policy: RetentionPolicy) {
        guard policy != effectiveRetention else { return }
        guard isPro || TierLimits.free.cappedRetention(policy) == policy else {
            showsPaywall = true
            return
        }
        guard Self.isShorter(policy, than: effectiveRetention) else {
            apply(policy, cleanUpNow: false)
            return
        }
        let count = expiringCount(for: policy)
        if count == 0 {
            apply(policy, cleanUpNow: true)
        } else {
            pendingRetention = PendingRetention(policy: policy, expiringCount: count)
        }
    }

    private func apply(_ policy: RetentionPolicy, cleanUpNow: Bool) {
        model.settings.retention = policy
        retention = policy
        guard cleanUpNow else { return }
        isApplyingRetention = true
        Task {
            await RetentionTask.run()
            isApplyingRetention = false
            model.historyDidChange()
        }
    }

    /// Entries older than the policy's cutoff, or nil if the store can't be read.
    /// Entries with a pending snooze are kept, so this can slightly overcount.
    private func expiringCount(for policy: RetentionPolicy) -> Int? {
        guard let cutoff = policy.cutoff(now: Date()) else { return 0 }
        let filter = HistoryFilter(dateRange: DateInterval(start: .distantPast, end: cutoff))
        return try? model.store().entryCount(filter: filter)
    }

    private static func isShorter(_ policy: RetentionPolicy, than other: RetentionPolicy) -> Bool {
        (policy.days ?? .max) < (other.days ?? .max)
    }

    // MARK: Settings mirrors

    private func loadSettings() {
        let settings = model.settings
        retention = settings.retention
        isLoggingPaused = settings.isLoggingPaused
        isAppLockEnabled = settings.isAppLockEnabled
        showsTextInWidgets = settings.showsTextInWidgets
    }

    private var loggingPausedBinding: Binding<Bool> {
        Binding(
            get: { isLoggingPaused },
            set: { newValue in
                isLoggingPaused = newValue
                model.settings.isLoggingPaused = newValue
                WidgetRefresher.reloadAll()
            }
        )
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { isAppLockEnabled },
            set: { newValue in
                isAppLockEnabled = newValue
                model.settings.isAppLockEnabled = newValue
            }
        )
    }

    private var widgetTextBinding: Binding<Bool> {
        Binding(
            get: { showsTextInWidgets },
            set: { newValue in
                showsTextInWidgets = newValue
                model.settings.showsTextInWidgets = newValue
                WidgetRefresher.reloadAll()
            }
        )
    }

    private var isConfirmingRetention: Binding<Bool> {
        Binding(
            get: { pendingRetention != nil },
            set: { if !$0 { pendingRetention = nil } }
        )
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}

/// A shorter retention waiting for the user to confirm its cleanup.
private struct PendingRetention {
    var policy: RetentionPolicy
    /// Nil when the store couldn't be counted.
    var expiringCount: Int?

    var days: Int { policy.days ?? 0 }
}

/// Marks a choice that needs Pro.
struct SettingsProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Requires Pro")
    }
}

private extension RetentionPolicy {
    var settingsTitle: LocalizedStringKey {
        switch self {
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        case .ninetyDays: "90 Days"
        case .forever: "Forever"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.preview())
}
