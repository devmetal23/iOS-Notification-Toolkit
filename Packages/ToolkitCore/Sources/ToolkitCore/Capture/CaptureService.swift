import Foundation

// CONTRACT STUB — workstream W1 replaces the body of `capture(_:)`. Keep the public signatures.

/// The whole capture pipeline behind Log Notification (FR-6), kept out of the
/// intent so it runs and is tested on any platform.
///
/// Order: paused? → own-app echo? → tier gate → dedupe + insert → opportunistic
/// retention (at most once every 24 hours).
public struct CaptureService: Sendable {
    public static let dedupeWindow: TimeInterval = 60
    /// How long after Send test notification a capture from this app counts as the test.
    public static let testNotificationWindow: TimeInterval = 5 * 60
    public static let retentionInterval: TimeInterval = 24 * 60 * 60

    private let store: any NotificationStoring
    private let settings: SharedSettings
    private let now: @Sendable () -> Date

    public init(store: any NotificationStoring, settings: SharedSettings, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.settings = settings
        self.now = now
    }

    public func capture(_ notification: NewNotification) throws -> CaptureOutcome {
        fatalError("W1: not implemented")
    }
}

public enum CaptureOutcome: Hashable, Sendable {
    case stored(NotificationEntry)
    case duplicate
    /// Logging is paused from the Control Center toggle (FR-18).
    case paused
    /// A notification from Notification Toolkit itself (a snooze coming back)
    /// while no test notification was expected.
    case ignoredOwnNotification
    /// Free tier, and this app is beyond the 3-app limit.
    case blockedByAppLimit
}
