import Foundation

// CONTRACT STUB — workstream W2 replaces the bodies. Keep the public signatures.

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

        public var needsAttention: Bool {
            fatalError("W2: not implemented")
        }

        public init(app: TrackedApp, status: Status) {
            self.app = app
            self.status = status
        }
    }

    /// One result per app: apps needing attention first, then by display name.
    public static func evaluate(_ apps: [TrackedApp], now: Date, threshold: TimeInterval = silenceThreshold) -> [AppHealth] {
        fatalError("W2: not implemented")
    }
}
