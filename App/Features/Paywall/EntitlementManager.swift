import Foundation
import Observation
import StoreKit
import SwiftUI
import ToolkitCore

/// StoreKit 2 entitlement state. Mirrors `isPro` into SharedSettings so intents
/// and widgets can read it without StoreKit.
@MainActor
@Observable
final class EntitlementManager {
    enum PurchaseOutcome: Hashable, Sendable {
        case purchased
        /// Waiting for approval, e.g. Ask to Buy. `Transaction.updates` delivers it later.
        case pending
        case cancelled
    }

    @ObservationIgnored private let settings: SharedSettings
    private(set) var isPro: Bool

    /// The product granting Pro, when known. Lifetime wins over the subscription.
    private(set) var activeProductID: String?

    /// Pro products in `ProProducts.all` order, once `loadProducts()` has succeeded.
    private(set) var products: [Product] = []

    /// Listens to `Transaction.updates` for the app's lifetime. Never cancelled:
    /// the manager lives as long as `AppModel`, and the loop holds it weakly.
    @ObservationIgnored private var updatesListener: Task<Void, Never>?
    /// Bumped by every refresh, so a slower, older refresh can't overwrite a newer one.
    @ObservationIgnored private var refreshGeneration = 0

    init(settings: SharedSettings) {
        self.settings = settings
        self.isPro = settings.isPro
    }

    /// Refreshes current entitlements and starts listening for transaction updates.
    /// Safe to call again; the listener starts only once.
    func start() async {
        if updatesListener == nil {
            updatesListener = Task { [weak self] in
                for await update in StoreKit.Transaction.updates {
                    guard let self else { return }
                    await self.handle(update)
                }
            }
        }
        await refreshEntitlements()
        await finishUnfinishedTransactions()
    }

    /// Re-reads `Transaction.currentEntitlements`: verified, not revoked, not expired
    /// (a subscription in its billing grace period still counts).
    func refreshEntitlements() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let now = Date()
        var grantingProductID: String?

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProProducts.all.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded
            else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                guard await Self.isInGracePeriod(transaction) else { continue }
            }
            if grantingProductID != ProProducts.lifetime {
                grantingProductID = transaction.productID
            }
        }

        guard generation == refreshGeneration else { return }
        apply(grantingProductID: grantingProductID)
    }

    // MARK: - Products

    /// Loads the Pro products from the App Store, or returns them if already loaded.
    @discardableResult
    func loadProducts() async throws -> [Product] {
        if products.count == ProProducts.all.count { return products }
        let loaded = try await Product.products(for: ProProducts.all)
        let ordered = ProProducts.all.compactMap { id in loaded.first { $0.id == id } }
        products = ordered
        return ordered
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        try await process(product.purchase())
    }

    /// Prefer this from SwiftUI: `@Environment(\.purchase)` attaches the payment
    /// sheet to the view's scene.
    func purchase(_ product: Product, using purchaseAction: PurchaseAction) async throws -> PurchaseOutcome {
        try await process(purchaseAction(product))
    }

    /// Syncs purchases with the App Store, which may ask the user to sign in, then
    /// re-reads entitlements. Returns whether the user is Pro afterwards.
    @discardableResult
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshEntitlements()
        return isPro
    }

    // MARK: - Private

    private func process(_ result: Product.PurchaseResult) async throws -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await refreshEntitlements()
                if !isPro, ProProducts.all.contains(transaction.productID), transaction.revocationDate == nil {
                    // currentEntitlements can trail a purchase that just completed.
                    apply(grantingProductID: transaction.productID)
                }
                await transaction.finish()
                return .purchased
            case .unverified(_, let error):
                throw error
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    private func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        await refreshEntitlements()
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
    }

    /// Finishes transactions left open by a crash or an earlier launch. Entitlement
    /// comes from `currentEntitlements`, so finishing them never loses Pro.
    private func finishUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    private func apply(grantingProductID: String?) {
        let newValue = grantingProductID != nil
        let changed = newValue != isPro || newValue != settings.isPro
        if activeProductID != grantingProductID { activeProductID = grantingProductID }
        if isPro != newValue { isPro = newValue }
        settings.isPro = newValue
        if changed { WidgetRefresher.reloadAll() }
    }

    private static func isInGracePeriod(_ transaction: StoreKit.Transaction) async -> Bool {
        guard transaction.productType == .autoRenewable else { return false }
        return await transaction.subscriptionStatus?.state == .inGracePeriod
    }
}

#if DEBUG
extension EntitlementManager {
    /// SwiftUI previews only: shows Pro or free UI without StoreKit or touching settings.
    func overrideForPreview(isPro: Bool) {
        self.isPro = isPro
        activeProductID = isPro ? ProProducts.yearly : nil
    }
}
#endif
