import AppIntents

/// App Shortcuts for Siri and Spotlight (FR-20). Every phrase names the app.
struct NotificationToolkitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRecentNotificationsIntent(),
            phrases: [
                "Get recent notifications from \(.applicationName)",
                "Show my notification history in \(.applicationName)",
            ],
            shortTitle: "Recent Notifications",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: SearchNotificationHistoryIntent(),
            phrases: [
                "Search my notifications in \(.applicationName)",
            ],
            shortTitle: "Search Notifications",
            systemImageName: "magnifyingglass"
        )
    }
}
