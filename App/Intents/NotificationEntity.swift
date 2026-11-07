import AppIntents
import Foundation
import ToolkitCore

/// A stored notification, as Shortcuts sees it (FR-20).
struct NotificationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Notification",
            numericFormat: "\(placeholder: .int) notifications"
        )
    }

    static let defaultQuery = NotificationEntityQuery()

    /// The entry's row ID as a string.
    let id: String

    @Property(title: "App")
    var appName: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Subtitle")
    var subtitle: String

    @Property(title: "Message")
    var message: String

    @Property(title: "Date")
    var receivedAt: Date

    @Property(title: "Time Sensitive")
    var isTimeSensitive: Bool

    init(entry: NotificationEntry) {
        id = String(entry.id)
        appName = entry.appName
        title = entry.title
        subtitle = entry.subtitle
        message = entry.body
        receivedAt = entry.receivedAt
        isTimeSensitive = entry.isTimeSensitive
    }

    var displayRepresentation: DisplayRepresentation {
        let headline = title.isEmpty ? appName : title
        let detail = message.isEmpty ? appName : message
        return DisplayRepresentation(
            title: "\(headline)",
            subtitle: "\(detail)",
            image: DisplayRepresentation.Image(systemName: "bell")
        )
    }
}

/// Looks up notifications by ID, suggests recent ones, and searches by text.
struct NotificationEntityQuery: EntityStringQuery {
    static let suggestionLimit = 20

    func entities(for identifiers: [NotificationEntity.ID]) async throws -> [NotificationEntity] {
        let store = try AppGroup.store()
        return try identifiers.compactMap { identifier in
            guard let id = NotificationEntry.ID(identifier) else { return nil }
            return try store.entry(id: id).map(NotificationEntity.init(entry:))
        }
    }

    func entities(matching string: String) async throws -> [NotificationEntity] {
        let query = HistoryQuery(searchText: string, limit: Self.suggestionLimit)
        return try AppGroup.store().entries(query).map(NotificationEntity.init(entry:))
    }

    func suggestedEntities() async throws -> [NotificationEntity] {
        let query = HistoryQuery(limit: Self.suggestionLimit)
        return try AppGroup.store().entries(query).map(NotificationEntity.init(entry:))
    }
}
