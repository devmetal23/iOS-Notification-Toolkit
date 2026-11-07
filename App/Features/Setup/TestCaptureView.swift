import SwiftUI
import ToolkitCore
import UIKit
import UserNotifications

/// Send test notification (FR-5): Notification Toolkit posts a notification to
/// itself, the base shortcut's automation hands it to Log Notification, and the
/// screen watches for the capture. Lets users, and App Review, see capture work
/// before setting up any other app.
struct TestCaptureView: View {
    var catalog: ShortcutCatalog = .bundled

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var runner = TestCaptureRunner()
    @State private var switchOnEntry: ShortcutCatalogEntry?
    @State private var lastTestCaptureAt: Date?

    var body: some View {
        List {
            Section {
                Text("Test Capture checks the whole chain: Notification Toolkit sends itself a notification, the base shortcut's automation passes it to Log Notification, and it's saved to History.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let base = catalog.baseShortcut {
                Section {
                    Text("The base shortcut has an automation for Notification Toolkit itself. It's what this test uses, and it never counts toward your apps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(baseShortcutButtonTitle, systemImage: "arrow.down.circle") {
                        if base.isPublished {
                            openURL(base.shortcutURL)
                        }
                        switchOnEntry = base
                    }
                } header: {
                    Text("Step 1: Base Shortcut")
                }
            }

            Section {
                Button("Send Test Notification", systemImage: "paperplane") {
                    runner.start(model: model)
                }
                .disabled(runner.isRunning)
                TestCaptureStatus(
                    phase: runner.phase,
                    openSettings: openNotificationSettings,
                    openShortcuts: { openURL(ShortcutsAppLink.url) },
                    showHistory: { model.selectedTab = .history }
                )
            } header: {
                Text("Step 2: Send a Test")
            } footer: {
                Text("The notification arrives about 3 seconds after you tap.")
            }

            if let lastTestCaptureAt, !runner.isRunning {
                Section {
                    LabeledContent("Last successful test") {
                        Text(lastTestCaptureAt, format: .relative(presentation: .named))
                    }
                }
            }
        }
        .navigationTitle("Test Capture")
        .task(id: model.setupReloadKey(scenePhase)) {
            lastTestCaptureAt = model.settings.lastTestCaptureAt
        }
        .sheet(item: $switchOnEntry) { entry in
            SwitchOnSheet(entry: entry)
        }
    }

    private var baseShortcutButtonTitle: LocalizedStringKey {
        lastTestCaptureAt == nil ? "Get the Base Shortcut" : "Get the Base Shortcut Again"
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}

/// Runs one test: arms the capture window, checks permission, posts the
/// notification and polls `settings.lastTestCaptureAt` about once a second.
@MainActor
@Observable
final class TestCaptureRunner {
    enum Phase: Equatable {
        case idle
        case preparing
        /// Permission was denied; the capture window has been cleared.
        case notificationsOff
        case waiting(showsHint: Bool)
        case captured(Date)
        case timedOut
        case failed
    }

    static let postDelay: TimeInterval = 3
    static let pollDuration: TimeInterval = 60
    /// When to suggest checking the base shortcut's automation.
    static let hintDelay: TimeInterval = 30

    private(set) var phase = Phase.idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .preparing, .waiting: true
        default: false
        }
    }

    /// Keeps running if the user leaves the screen, so a capture that lands
    /// while they look at History still refreshes it.
    func start(model: AppModel) {
        task?.cancel()
        task = Task { await run(model: model) }
    }

    private func run(model: AppModel) async {
        let settings = model.settings
        let startedAt = Date()
        // Armed first, so the capture pipeline treats the next notification from
        // Notification Toolkit as the test rather than an echo (CaptureService step 2).
        settings.testNotificationExpectedUntil = startedAt.addingTimeInterval(CaptureService.testNotificationWindow)
        phase = .preparing

        var permission = await LocalNotificationPermission.current()
        if permission == .notDetermined {
            permission = await LocalNotificationPermission.request()
        }
        guard permission == .allowed else {
            settings.testNotificationExpectedUntil = nil
            phase = .notificationsOff
            return
        }

        do {
            try await TestCaptureNotification.schedule(after: Self.postDelay)
        } catch {
            settings.testNotificationExpectedUntil = nil
            phase = .failed
            return
        }

        phase = .waiting(showsHint: false)
        // Wall-clock deadlines, so time spent in the background counts.
        let pollStart = Date()
        while Date().timeIntervalSince(pollStart) < Self.pollDuration {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return // Cancelled by a new run.
            }
            if let capturedAt = Self.testCaptureTime(since: startedAt, model: model) {
                // Disarm early, so a snooze coming back isn't logged as a test.
                settings.testNotificationExpectedUntil = nil
                settings.lastTestCaptureAt = capturedAt
                phase = .captured(capturedAt)
                model.historyDidChange()
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Captured. Capture is working."))
                return
            }
            if phase == .waiting(showsHint: false), Date().timeIntervalSince(pollStart) >= Self.hintDelay {
                phase = .waiting(showsHint: true)
            }
        }
        phase = .timedOut
        UIAccessibility.post(notification: .announcement, argument: String(localized: "The test notification wasn't logged."))
    }

    /// When the test notification was logged, if it was at or after `start`. Also
    /// looks for Notification Toolkit's own entry in the store, so the test works
    /// whether or not the capture path updates `lastTestCaptureAt`.
    private static func testCaptureTime(since start: Date, model: AppModel) -> Date? {
        if let capturedAt = model.settings.lastTestCaptureAt, capturedAt >= start {
            return capturedAt
        }
        let query = HistoryQuery(filter: HistoryFilter(apps: [.ownApp]), limit: 1)
        guard let entry = try? model.store().entries(query).first, entry.capturedAt >= start else {
            return nil
        }
        return entry.capturedAt
    }
}

/// The local notification Test Capture posts. NotificationDelegate can match
/// `requestIdentifier` to show it as a banner while the app is open.
enum TestCaptureNotification {
    static let requestIdentifier = "notification-toolkit.test-capture"
    static let userInfoKind = "testCapture"

    @concurrent
    nonisolated static func schedule(after delay: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Test Notification")
        content.body = String(localized: "If this appears in History, capture is working.")
        content.sound = .default
        content.userInfo = ["kind": userInfoKind]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
}

private struct TestCaptureStatus: View {
    let phase: TestCaptureRunner.Phase
    let openSettings: () -> Void
    let openShortcuts: () -> Void
    let showHistory: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .preparing:
            progress("Getting ready…")

        case .notificationsOff:
            VStack(alignment: .leading, spacing: 8) {
                Label("Notifications Are Off", systemImage: "bell.slash.fill")
                    .font(.headline)
                Text("Test Capture needs to send a notification. Turn on notifications for Notification Toolkit in Settings, then try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

        case .waiting(let showsHint):
            progress("Waiting for the test notification to be logged…")
            if showsHint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Still waiting? In Shortcuts, tap Automation and make sure the base shortcut's Notification Toolkit automation is switched on and set to Run Immediately.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Shortcuts", action: openShortcuts)
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }

        case .captured:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Captured — capture is working")
                        .font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button("Show in History", action: showHistory)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

        case .timedOut:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Nothing was logged")
                        .font(.headline)
                } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                }
                Text("Check that the base shortcut's Notification Toolkit automation is switched on and set to Run Immediately, and that logging isn't paused. Then try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Shortcuts", action: openShortcuts)
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

        case .failed:
            Label("The test notification couldn't be sent. Try again.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func progress(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TestCaptureView()
    }
    .environment(AppModel.preview())
}
