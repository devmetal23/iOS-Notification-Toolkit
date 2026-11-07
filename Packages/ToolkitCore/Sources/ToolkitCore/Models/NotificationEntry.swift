import Foundation

/// A notification captured by Log Notification and stored on the device.
public struct NotificationEntry: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Int64

    public var id: ID
    public var appKey: AppKey
    /// The app name exactly as the shortcut passed it, for display.
    public var appName: String
    public var title: String
    public var subtitle: String
    public var body: String
    /// When the notification arrived, from the Notification variable. Falls back to capture time.
    public var receivedAt: Date
    /// When Log Notification ran.
    public var capturedAt: Date
    public var isTimeSensitive: Bool

    public init(
        id: ID,
        appKey: AppKey,
        appName: String,
        title: String,
        subtitle: String,
        body: String,
        receivedAt: Date,
        capturedAt: Date,
        isTimeSensitive: Bool
    ) {
        self.id = id
        self.appKey = appKey
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.receivedAt = receivedAt
        self.capturedAt = capturedAt
        self.isTimeSensitive = isTimeSensitive
    }
}

/// What Log Notification hands to the capture pipeline (FR-6).
public struct NewNotification: Hashable, Sendable {
    public var appName: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var receivedAt: Date
    public var isTimeSensitive: Bool

    public var appKey: AppKey { AppKey(appName: appName) }

    public init(
        appName: String,
        title: String = "",
        subtitle: String = "",
        body: String = "",
        receivedAt: Date,
        isTimeSensitive: Bool = false
    ) {
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.receivedAt = receivedAt
        self.isTimeSensitive = isTimeSensitive
    }
}

/// Stable identity for a source app. Shortcuts pass a display name, so the key
/// is that name trimmed and lowercased: "WhatsApp " and "whatsapp" are one app.
public struct AppKey: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(appName: String) {
        self.rawValue = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Notification Toolkit's own notifications (test notification, snoozes).
    public static let ownApp = AppKey(appName: "Notification Toolkit")

    public var description: String { rawValue }

    public static func < (lhs: AppKey, rhs: AppKey) -> Bool { lhs.rawValue < rhs.rawValue }
}
