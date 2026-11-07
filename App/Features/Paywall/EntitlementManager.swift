import Foundation
import Observation
import ToolkitCore

// CONTRACT STUB — workstream W6 replaces the bodies. Keep the signatures.

/// StoreKit 2 entitlement state. Mirrors `isPro` into SharedSettings so intents
/// and widgets can read it without StoreKit.
@MainActor
@Observable
final class EntitlementManager {
    @ObservationIgnored private let settings: SharedSettings
    private(set) var isPro: Bool

    init(settings: SharedSettings) {
        self.settings = settings
        self.isPro = settings.isPro
    }

    /// Refreshes current entitlements and starts listening for transaction updates.
    func start() async {}
}
