import Foundation

public enum Tier: String, Hashable, Sendable {
    case free
    case pro
}

/// What each tier includes (Monetization: Free = 3 apps, 7-day history, search).
public struct TierLimits: Hashable, Sendable {
    /// Nil means unlimited.
    public var maxApps: Int?
    /// Longest retention allowed. Nil means any.
    public var maxRetention: RetentionPolicy?

    public static let free = TierLimits(maxApps: 3, maxRetention: .sevenDays)
    public static let pro = TierLimits(maxApps: nil, maxRetention: nil)

    public init(maxApps: Int?, maxRetention: RetentionPolicy?) {
        self.maxApps = maxApps
        self.maxRetention = maxRetention
    }

    public init(for tier: Tier) {
        self = tier == .pro ? .pro : .free
    }

    public func cappedRetention(_ policy: RetentionPolicy) -> RetentionPolicy {
        guard let maxRetention, let maxDays = maxRetention.days else { return policy }
        guard let days = policy.days else { return maxRetention }
        return days > maxDays ? maxRetention : policy
    }
}

/// Decides whether a capture from an app is allowed under the user's tier.
/// On the free tier the 3 earliest-added tracked apps are allowed; any other
/// app's captures are blocked (and counted, so the app can offer Pro).
/// Notification Toolkit itself (the test notification) never takes a slot.
public enum CaptureGate {
    public enum Decision: Hashable, Sendable {
        case allow
        case blockedByAppLimit
    }

    /// The tracked apps that use up free-tier slots: all but Notification Toolkit itself.
    public static func appsCountingTowardLimit(_ trackedApps: [TrackedApp]) -> [TrackedApp] {
        trackedApps.filter { $0.key != .ownApp }
    }

    /// - Parameter trackedApps: all tracked apps, in any order.
    public static func decide(app: AppKey, tier: Tier, trackedApps: [TrackedApp]) -> Decision {
        guard app != .ownApp, let maxApps = TierLimits(for: tier).maxApps else { return .allow }
        let counted = appsCountingTowardLimit(trackedApps)
        let allowed = counted
            .sorted { ($0.addedAt, $0.key) < ($1.addedAt, $1.key) }
            .prefix(maxApps)
            .map(\.key)
        if allowed.contains(app) { return .allow }
        // An untracked app takes a free slot if one is left.
        let isTracked = counted.contains { $0.key == app }
        return !isTracked && counted.count < maxApps ? .allow : .blockedByAppLimit
    }
}
