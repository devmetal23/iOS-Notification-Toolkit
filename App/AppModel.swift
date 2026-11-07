import Foundation
import Observation
import ToolkitCore

enum AppTab: Hashable {
    case history, snoozed, setup, settings
}

/// App-wide state and services, injected with `.environment(model)`.
///
/// Kept cheap to create: the system may launch the app in the background just to
/// run Log Notification, and that path must finish in under a second (NFR-4).
@MainActor
@Observable
final class AppModel {
    let settings: SharedSettings
    let snoozes: SnoozeScheduler
    let entitlements: EntitlementManager

    /// Bumped after any change to stored history so views reload.
    private(set) var historyRevision = 0

    /// The selected main tab, so flows like onboarding can send the user somewhere.
    var selectedTab: AppTab = .history

    /// An entry to show in History, set when the user taps a snooze that came back.
    /// `HistoryView` opens its detail and clears this.
    var entryToOpen: NotificationEntry.ID?

    var hasCompletedOnboarding: Bool {
        didSet { settings.hasCompletedOnboarding = hasCompletedOnboarding }
    }

    @ObservationIgnored private let openStore: @Sendable () throws -> any NotificationStoring

    init(settings: SharedSettings, openStore: @escaping @Sendable () throws -> any NotificationStoring) {
        self.settings = settings
        self.openStore = openStore
        self.hasCompletedOnboarding = settings.hasCompletedOnboarding
        self.snoozes = SnoozeScheduler(settings: settings, openStore: openStore)
        self.entitlements = EntitlementManager(settings: settings)
    }

    /// The shared store. Throws only before the first unlock after a restart.
    func store() throws -> any NotificationStoring {
        try openStore()
    }

    /// Call after deleting, snoozing or otherwise changing history from the app.
    func historyDidChange() {
        historyRevision += 1
        WidgetRefresher.reloadAll()
    }

    /// Runs once the UI is up: snooze tap routing, entitlement listener, retention,
    /// snooze cleanup.
    func start() async {
        // First, so a tap that cold-launched the app is delivered right away.
        NotificationDelegate.shared.onOpenEntry = { [weak self] id in
            self?.selectedTab = .history
            self?.entryToOpen = id
        }
        await entitlements.start()
        await RetentionTask.run()
        await snoozes.removeFiredRecords()
        historyRevision += 1
    }

    static func live() -> AppModel {
        AppModel(settings: AppGroup.settings, openStore: { try AppGroup.store() })
    }

    /// An in-memory store with sample data for SwiftUI previews.
    static func preview() -> AppModel {
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)")!
        let settings = SharedSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        let store = try! SQLiteNotificationStore.inMemory()
        PreviewData.populate(store)
        return AppModel(settings: settings, openStore: { store })
    }
}
