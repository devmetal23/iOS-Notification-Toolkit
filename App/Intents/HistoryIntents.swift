import AppIntents
import Foundation
import ToolkitCore

// Shortcuts actions that read history (FR-20). They return notification text, so
// they require an unlocked iPhone; Log Notification doesn't, because it has to
// run while the iPhone is locked.

/// Full-text search over the stored history, newest first.
struct SearchNotificationHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Notification History"

    static let description = IntentDescription(
        "Finds saved notifications that contain the words you enter, newest first. Searches the title, subtitle and message.",
        categoryName: "History",
        searchKeywords: ["notification", "history", "search", "find"]
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Search Text", description: "Words to look for. Each word matches the start of a word.")
    var searchText: String

    @Parameter(title: "App", description: "Only include notifications from this app. Leave empty for all apps.")
    var app: String?

    @Parameter(title: "Limit", description: "The most notifications to return.", default: 20)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search notification history for \(\.$searchText)") {
            \.$app
            \.$limit
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[NotificationEntity]> {
        let query = HistoryQuery(
            filter: HistoryIntentSupport.filter(app: app),
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: HistoryIntentSupport.clamped(limit)
        )
        let entries = try AppGroup.store().entries(query)
        return .result(value: entries.map(NotificationEntity.init(entry:)))
    }
}

/// The most recent notifications, optionally from one app.
struct GetRecentNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Notifications"

    static let description = IntentDescription(
        "Gets the most recent notifications saved on this iPhone, newest first.",
        categoryName: "History",
        searchKeywords: ["notification", "history", "recent", "latest"]
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Limit", description: "The most notifications to return.", default: 10)
    var limit: Int

    @Parameter(title: "App", description: "Only include notifications from this app. Leave empty for all apps.")
    var app: String?

    @Parameter(title: "Time Sensitive Only", default: false)
    var timeSensitiveOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$limit) most recent notifications") {
            \.$app
            \.$timeSensitiveOnly
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[NotificationEntity]> {
        var filter = HistoryIntentSupport.filter(app: app)
        filter.timeSensitiveOnly = timeSensitiveOnly
        let query = HistoryQuery(filter: filter, limit: HistoryIntentSupport.clamped(limit))
        let entries = try AppGroup.store().entries(query)
        return .result(value: entries.map(NotificationEntity.init(entry:)))
    }
}

enum HistoryIntentSupport {
    static let maxResults = 200

    /// A filter for one app by name, or all apps when the name is empty.
    static func filter(app: String?) -> HistoryFilter {
        let name = app?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? .all : HistoryFilter(apps: [AppKey(appName: name)])
    }

    static func clamped(_ limit: Int) -> Int {
        min(max(limit, 1), maxResults)
    }
}
