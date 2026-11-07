import Foundation

/// A snoozed entry waiting to come back as a local notification (FR-14, FR-15).
public struct SnoozeRecord: Identifiable, Hashable, Sendable {
    public typealias ID = Int64

    public var id: ID
    public var entry: NotificationEntry
    public var fireAt: Date
    public var createdAt: Date

    public init(id: ID, entry: NotificationEntry, fireAt: Date, createdAt: Date) {
        self.id = id
        self.entry = entry
        self.fireAt = fireAt
        self.createdAt = createdAt
    }

    /// Identifier of the pending UNNotificationRequest for this snooze.
    public var requestIdentifier: String { Self.requestIdentifier(for: id) }

    public static func requestIdentifier(for id: ID) -> String { "snooze-\(id)" }
}
