import Foundation

/// The Pro products (Monetization), defined once for the app.
/// `Config/NotificationToolkit.storekit` declares the same IDs for local testing.
enum ProProducts {
    /// Auto-renewable subscription in group "Pro": $19.99 a year with a 7-day free trial.
    static let yearly = "com.devmetal23.notificationtoolkit.pro.yearly"

    /// Non-consumable: $39.99 once.
    static let lifetime = "com.devmetal23.notificationtoolkit.pro.lifetime"

    /// Every product that grants Pro, in paywall order.
    static let all: [String] = [yearly, lifetime]

    /// Legal pages linked from the paywall.
    /// PLACEHOLDERS: replace with the published pages before App Store submission.
    static let legal = LegalLinks(
        termsOfUse: URL(string: "https://example.com/notification-toolkit/terms")!,
        privacyPolicy: URL(string: "https://example.com/notification-toolkit/privacy")!
    )

    struct LegalLinks: Hashable, Sendable {
        var termsOfUse: URL
        var privacyPolicy: URL
    }
}
