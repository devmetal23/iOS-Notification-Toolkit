import Foundation

/// How long history is kept before automatic cleanup (FR-12).
public enum RetentionPolicy: String, CaseIterable, Codable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case forever

    public var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .forever: nil
        }
    }

    /// Entries received before this date are expired. Nil when nothing expires.
    public func cutoff(now: Date) -> Date? {
        days.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }
}
