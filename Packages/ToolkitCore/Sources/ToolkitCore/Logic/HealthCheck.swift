import Foundation

/// Flags set-up apps whose automation may be off (FR-4).
public enum HealthCheck {
    public static let silenceThreshold: TimeInterval = 7 * 24 * 60 * 60

    public enum Status: Hashable, Sendable {
        /// Logged within the threshold.
        case healthy
        /// Added but nothing logged yet. `overdue` once the threshold has passed since it was added.
        case awaitingFirstCapture(overdue: Bool)
        /// Nothing logged for at least the threshold.
        case silent(since: Date)
    }

    public struct AppHealth: Hashable, Sendable, Identifiable {
        public var app: TrackedApp
        public var status: Status

        public var id: AppKey { app.key }

        /// Silent, or still waiting for a first capture after the threshold.
        public var needsAttention: Bool {
            switch status {
            case .healthy: false
            case .awaitingFirstCapture(let overdue): overdue
            case .silent: true
            }
        }

        public init(app: TrackedApp, status: Status) {
            self.app = app
            self.status = status
        }
    }

    /// One result per app: apps needing attention first, then by display name
    /// (case-insensitive), then by key so the order is stable.
    public static func evaluate(_ apps: [TrackedApp], now: Date, threshold: TimeInterval = silenceThreshold) -> [AppHealth] {
        apps
            .map { AppHealth(app: $0, status: status(of: $0, now: now, threshold: threshold)) }
            .sorted(by: isOrderedBefore)
    }

    // MARK: - Private

    private static func status(of app: TrackedApp, now: Date, threshold: TimeInterval) -> Status {
        guard let lastLoggedAt = app.lastLoggedAt else {
            return .awaitingFirstCapture(overdue: now.timeIntervalSince(app.addedAt) >= threshold)
        }
        return now.timeIntervalSince(lastLoggedAt) >= threshold ? .silent(since: lastLoggedAt) : .healthy
    }

    private static func isOrderedBefore(_ lhs: AppHealth, _ rhs: AppHealth) -> Bool {
        if lhs.needsAttention != rhs.needsAttention {
            return lhs.needsAttention
        }
        let lhsName = lhs.app.displayName.lowercased()
        let rhsName = rhs.app.displayName.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.app.key < rhs.app.key
    }
}
