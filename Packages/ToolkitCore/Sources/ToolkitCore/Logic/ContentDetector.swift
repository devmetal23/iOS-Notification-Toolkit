import Foundation

// CONTRACT STUB — workstream W2 replaces the bodies. Keep the public signatures.

/// Finds one-time codes, links and phone numbers in notification text (FR-11).
public enum ContentDetector {
    public enum Kind: Hashable, Sendable {
        /// A verification or login code, e.g. "482913" or "G-482913".
        case code
        case link
        case phoneNumber
    }

    public struct Match: Hashable, Sendable, Identifiable {
        public var kind: Kind
        /// The text as it appears in the notification.
        public var text: String
        /// Normalized value to act on: the code without spaces, the URL, or the dialable number.
        public var value: String

        public var id: String { "\(kind)-\(value)" }

        public init(kind: Kind, text: String, value: String) {
            self.kind = kind
            self.text = text
            self.value = value
        }

        /// A `tel:` or web URL for opening, nil for codes.
        public var url: URL? {
            fatalError("W2: not implemented")
        }
    }

    /// Matches in the order they appear, without duplicates.
    public static func matches(in text: String) -> [Match] {
        fatalError("W2: not implemented")
    }

    public static func matches(in entry: NotificationEntry) -> [Match] {
        matches(in: [entry.title, entry.subtitle, entry.body].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}
