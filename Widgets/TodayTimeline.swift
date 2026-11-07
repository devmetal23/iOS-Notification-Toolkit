import Foundation
import ToolkitCore
import WidgetKit

/// Kind string for the Today widget, kept outside the `Widget` type so
/// nonisolated code can name it.
enum TodayWidgetKind {
    static let kind = "com.devmetal23.notificationtoolkit.widgets.today"
}

/// One point on the Today widget's timeline.
struct TodayEntry: TimelineEntry, Sendable {
    enum Content: Hashable, Sendable {
        case snapshot(TodaySnapshot)
        /// Widgets are a Pro feature.
        case requiresPro
        /// The store couldn't be read, e.g. before the first unlock after a restart (NFR-2).
        case unavailable

        /// The same content once a new day starts: today's counts begin again at zero.
        func startingNewDay() -> Content {
            guard case .snapshot(let snapshot) = self else { return self }
            return .snapshot(snapshot.startingNewDay())
        }
    }

    var date: Date
    var content: Content
}

/// What the Today widget shows, read from the shared store once per timeline.
struct TodaySnapshot: Hashable, Sendable {
    struct AppCount: Hashable, Sendable, Identifiable {
        var appKey: AppKey
        var appName: String
        var count: Int

        var id: AppKey { appKey }
    }

    struct Item: Hashable, Sendable, Identifiable {
        var id: NotificationEntry.ID
        var appName: String
        var receivedAt: Date
        /// Title (or subtitle, or body when both are empty). Empty unless
        /// `showsText` is on, so hidden text never reaches the view.
        var text: String
    }

    /// Notifications logged today, all apps.
    var total: Int
    /// Today's counts, busiest app first.
    var apps: [AppCount]
    /// Newest first. Not limited to today.
    var latest: [Item]
    /// The user turned on Show text in widgets (FR-17, NFR-3).
    var showsText: Bool
    /// Logging is paused from the Control Center toggle (FR-18).
    var isLoggingPaused: Bool

    init(total: Int, apps: [AppCount], latest: [Item], showsText: Bool, isLoggingPaused: Bool) {
        self.total = total
        self.apps = apps
        self.latest = latest
        self.showsText = showsText
        self.isLoggingPaused = isLoggingPaused
    }

    /// Builds a snapshot from store results, dropping notification text unless
    /// the user opted in.
    init(counts: [DailyAppCount], latest: [NotificationEntry], showsText: Bool, isLoggingPaused: Bool) {
        var byApp: [AppKey: AppCount] = [:]
        for row in counts {
            byApp[row.appKey, default: AppCount(appKey: row.appKey, appName: row.appName, count: 0)].count += row.count
        }
        let apps = byApp.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
        let items = latest.map { entry in
            Item(
                id: entry.id,
                appName: entry.appName,
                receivedAt: entry.receivedAt,
                text: showsText ? Self.displayText(for: entry) : ""
            )
        }
        self.init(
            total: apps.reduce(0) { $0 + $1.count },
            apps: apps,
            latest: items,
            showsText: showsText,
            isLoggingPaused: isLoggingPaused
        )
    }

    func startingNewDay() -> TodaySnapshot {
        var copy = self
        copy.total = 0
        copy.apps = []
        return copy
    }

    private static func displayText(for entry: NotificationEntry) -> String {
        [entry.title, entry.subtitle, entry.body]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    /// Sample data for the widget gallery and the redacted placeholder. Text is
    /// hidden, as it is by default.
    static func sample(now: Date = Date()) -> TodaySnapshot {
        let messages = String(localized: "Messages", comment: "Sample app name in the widget gallery")
        let mail = String(localized: "Mail", comment: "Sample app name in the widget gallery")
        let calendar = String(localized: "Calendar", comment: "Sample app name in the widget gallery")
        let apps = [
            AppCount(appKey: AppKey(appName: messages), appName: messages, count: 12),
            AppCount(appKey: AppKey(appName: mail), appName: mail, count: 7),
            AppCount(appKey: AppKey(appName: calendar), appName: calendar, count: 3),
        ]
        let latest = [
            Item(id: 5, appName: messages, receivedAt: now.addingTimeInterval(-4 * 60), text: ""),
            Item(id: 4, appName: mail, receivedAt: now.addingTimeInterval(-26 * 60), text: ""),
            Item(id: 3, appName: messages, receivedAt: now.addingTimeInterval(-58 * 60), text: ""),
            Item(id: 2, appName: calendar, receivedAt: now.addingTimeInterval(-95 * 60), text: ""),
            Item(id: 1, appName: mail, receivedAt: now.addingTimeInterval(-160 * 60), text: ""),
        ]
        return TodaySnapshot(
            total: apps.reduce(0) { $0 + $1.count },
            apps: apps,
            latest: latest,
            showsText: false,
            isLoggingPaused: false
        )
    }
}

/// Reads the Today widget's content from App Group settings and the shared store.
enum TodayLoader {
    /// Enough for the large widget; smaller sizes show fewer.
    static let latestLimit = 5
    /// Longest gap between timeline reloads. Captures also reload, throttled
    /// by `WidgetRefresher`.
    static let refreshInterval: TimeInterval = 15 * 60

    static func load(now: Date, calendar: Calendar) -> TodayEntry.Content {
        let settings = AppGroup.settings
        // Don't open the store at all for free users.
        guard settings.isPro else { return .requiresPro }
        do {
            let store = try AppGroup.store()
            let today = DateInterval(start: calendar.startOfDay(for: now), end: nextMidnight(after: now, calendar: calendar))
            let counts = try store.dailyCounts(in: today, calendar: calendar)
            let latest = try store.entries(HistoryQuery(limit: latestLimit))
            return .snapshot(TodaySnapshot(
                counts: counts,
                latest: latest,
                showsText: settings.showsTextInWidgets,
                isLoggingPaused: settings.isLoggingPaused
            ))
        } catch {
            return .unavailable
        }
    }

    static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(24 * 60 * 60)
    }

    /// A timeline with the current content now and today's counts reset at
    /// midnight. Reloads after 15 minutes, or at midnight if that comes first.
    static func timeline(now: Date, calendar: Calendar) -> Timeline<TodayEntry> {
        let content = load(now: now, calendar: calendar)
        let midnight = nextMidnight(after: now, calendar: calendar)
        let entries = [
            TodayEntry(date: now, content: content),
            TodayEntry(date: midnight, content: content.startingNewDay()),
        ]
        let reloadAt = min(now.addingTimeInterval(refreshInterval), midnight)
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), content: .snapshot(.sample()))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        // The gallery shows what Pro looks like, even before upgrading.
        let content: TodayEntry.Content = context.isPreview
            ? .snapshot(.sample(now: now))
            : TodayLoader.load(now: now, calendar: .current)
        completion(TodayEntry(date: now, content: content))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(TodayLoader.timeline(now: Date(), calendar: .current))
    }
}
