import Foundation

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
        // 1. Paused from the Control Center toggle (FR-18).
        if settings.isLoggingPaused { return .paused }

        let now = self.now()
        let isTestNotification: Bool
        if notification.appKey == .ownApp {
            // 2. Notification Toolkit's own notifications are snoozes coming back,
            // already in history, unless the user just sent a test notification (FR-5).
            guard let expectedUntil = settings.testNotificationExpectedUntil, expectedUntil >= now else {
                return .ignoredOwnNotification
            }
            // The test never takes a free-tier slot, so it skips the gate.
            isTestNotification = true
        } else {
            // 3. Free tier: only the first 3 apps are logged.
            isTestNotification = false
            let tier = settings.tier
            let trackedApps: [TrackedApp]
            if TierLimits(for: tier).maxApps == nil {
                trackedApps = []
            } else {
                trackedApps = try store.trackedApps()
            }
            if CaptureGate.decide(app: notification.appKey, tier: tier, trackedApps: trackedApps) == .blockedByAppLimit {
                try store.recordBlockedCapture(notification, at: now)
                return .blockedByAppLimit
            }
        }

        // 4. Store, unless it duplicates one received within a minute (FR-8).
        let outcome = try store.insert(notification, capturedAt: now, dedupeWindow: Self.dedupeWindow)

        if isTestNotification {
            settings.lastTestCaptureAt = now
            settings.testNotificationExpectedUntil = nil
            // The insert registered Notification Toolkit as a tracked app, which it
            // never is. Best effort: the test capture itself succeeded.
            try? store.removeApp(.ownApp)
        }

        // 5. Cleanup piggybacks on captures (FR-12).
        applyRetentionIfDue(now: now)

        switch outcome {
        case .inserted(let entry):
            return .stored(entry)
        case .duplicate:
            return .duplicate
        }
    }

    /// Applies the effective retention when it last ran at least `retentionInterval`
    /// ago, never ran, or ran "in the future" (the clock was changed). A failure is
    /// swallowed so it never fails the capture, and retried on the next capture.
    /// Retention only deletes entries without a pending snooze, so the snoozes it
    /// removes have all fired and there are no requests to cancel here.
    private func applyRetentionIfDue(now: Date) {
        if let lastRun = settings.lastRetentionRunAt,
           lastRun <= now,
           now.timeIntervalSince(lastRun) < Self.retentionInterval {
            return
        }
        do {
            _ = try store.applyRetention(settings.effectiveRetention, now: now)
            settings.lastRetentionRunAt = now
        } catch {
            // Leave lastRetentionRunAt unchanged so the next capture tries again.
        }
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
