import Foundation

/// Preferences shared through the App Group's UserDefaults, so the app, intents,
/// widgets and controls all read the same values.
public final class SharedSettings: @unchecked Sendable {
    // UserDefaults is documented as thread-safe; @unchecked covers its missing Sendable.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    enum Key {
        static let retention = "retentionPolicy"
        static let isLoggingPaused = "isLoggingPaused"
        static let isPro = "isPro"
        static let isAppLockEnabled = "isAppLockEnabled"
        static let showsTextInWidgets = "showsTextInWidgets"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastRetentionRunAt = "lastRetentionRunAt"
        static let lastWidgetReloadAt = "lastWidgetReloadAt"
        static let testNotificationExpectedUntil = "testNotificationExpectedUntil"
        static let lastTestCaptureAt = "lastTestCaptureAt"
        static let morningHour = "morningHour"
    }

    /// The retention the user picked (FR-12). Defaults to 30 days.
    public var retention: RetentionPolicy {
        get { defaults.string(forKey: Key.retention).flatMap(RetentionPolicy.init(rawValue:)) ?? .thirtyDays }
        set { defaults.set(newValue.rawValue, forKey: Key.retention) }
    }

    /// Retention actually applied: the free tier is capped at 7 days.
    public var effectiveRetention: RetentionPolicy {
        TierLimits(for: tier).cappedRetention(retention)
    }

    /// Paused from the Control Center toggle (FR-18). Captures are dropped while true.
    public var isLoggingPaused: Bool {
        get { defaults.bool(forKey: Key.isLoggingPaused) }
        set { defaults.set(newValue, forKey: Key.isLoggingPaused) }
    }

    /// Cached Pro entitlement. The app's StoreKit observer is the only writer;
    /// intents read it because they can't wait on StoreKit within 1 second (NFR-4).
    public var isPro: Bool {
        get { defaults.bool(forKey: Key.isPro) }
        set { defaults.set(newValue, forKey: Key.isPro) }
    }

    public var tier: Tier { isPro ? .pro : .free }

    /// Face ID lock (NFR-3). Off by default.
    public var isAppLockEnabled: Bool {
        get { defaults.bool(forKey: Key.isAppLockEnabled) }
        set { defaults.set(newValue, forKey: Key.isAppLockEnabled) }
    }

    /// Whether widgets show notification text. Off by default (FR-17, NFR-3).
    public var showsTextInWidgets: Bool {
        get { defaults.bool(forKey: Key.showsTextInWidgets) }
        set { defaults.set(newValue, forKey: Key.showsTextInWidgets) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var lastRetentionRunAt: Date? {
        get { defaults.object(forKey: Key.lastRetentionRunAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastRetentionRunAt) }
    }

    /// Throttles widget reloads from captures so bursts don't spend the reload budget.
    public var lastWidgetReloadAt: Date? {
        get { defaults.object(forKey: Key.lastWidgetReloadAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastWidgetReloadAt) }
    }

    /// Set when the user taps Send test notification (FR-5). Until then, captures
    /// from Notification Toolkit itself are ignored so snoozes aren't logged twice.
    public var testNotificationExpectedUntil: Date? {
        get { defaults.object(forKey: Key.testNotificationExpectedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.testNotificationExpectedUntil) }
    }

    /// When the last test notification was captured, so setup can show it worked.
    public var lastTestCaptureAt: Date? {
        get { defaults.object(forKey: Key.lastTestCaptureAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastTestCaptureAt) }
    }

    /// Hour used by "Tomorrow morning" snoozes (FR-14). Defaults to 8.
    public var morningHour: Int {
        get { (defaults.object(forKey: Key.morningHour) as? Int) ?? 8 }
        set { defaults.set(newValue, forKey: Key.morningHour) }
    }
}
