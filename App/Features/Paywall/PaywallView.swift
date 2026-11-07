import StoreKit
import SwiftUI
import ToolkitCore

/// Pro upgrade: yearly with a 7-day trial, or lifetime. Presented as a sheet.
///
/// Plain terms: both prices are shown in full, the trial says what it renews at,
/// Close is always available, and there are no timers or pre-ticked choices.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchaseAction

    private let onClose: (@MainActor @Sendable () -> Void)?

    @State private var loadState = LoadState.loading
    @State private var isTrialEligible = false
    @State private var busyAction: BusyAction?
    @State private var alert: PaywallAlert?
    @State private var isShowingAlert = false

    /// For `.sheet` presentation; closes with `\.dismiss`.
    init() {
        onClose = nil
    }

    /// For UIKit presentation (`SnoozeFlow`), where `\.dismiss` can't close the
    /// hosting controller. Called on Close and after a successful purchase or restore.
    init(onClose: @escaping @MainActor @Sendable () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if model.entitlements.isPro {
                        proActive
                    } else {
                        benefits
                        plans
                        footer
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { close() }
                }
            }
        }
        .interactiveDismissDisabled(busyAction != nil)
        .task { await loadProducts() }
        .alert(
            alert?.title ?? "",
            isPresented: $isShowingAlert,
            presenting: alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Notification Toolkit Pro")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Every app, all of your history, and snooze.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            BenefitRow(
                symbol: "square.stack.3d.up",
                title: "Unlimited apps",
                detail: "Log notifications from every app you set up, not just 3."
            )
            BenefitRow(
                symbol: "clock.arrow.circlepath",
                title: "Keep history longer",
                detail: "Keep 30 days, 90 days or everything, instead of 7 days."
            )
            BenefitRow(
                symbol: "moon.zzz",
                title: "Snooze",
                detail: "Bring a notification back in 15 minutes, an hour, tomorrow morning or at a time you choose."
            )
            BenefitRow(
                symbol: "square.grid.2x2",
                title: "Widgets and Control Center",
                detail: "See recent notifications on your Home Screen and pause logging from Control Center."
            )
            BenefitRow(
                symbol: "chart.bar",
                title: "Stats",
                detail: "See which apps notify you most, and when."
            )
            Text("Free includes 3 apps, 7 days of history and search.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plans: some View {
        switch loadState {
        case .loading:
            ProgressView("Loading Pro options…")
                .frame(maxWidth: .infinity)
                .padding()
        case .failed:
            VStack(spacing: 12) {
                Text("Pro options aren't available right now. Check your internet connection and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await loadProducts() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        case .loaded:
            VStack(spacing: 16) {
                if let yearly = model.entitlements.product(for: ProProducts.yearly) {
                    yearlyPlan(yearly)
                }
                if let lifetime = model.entitlements.product(for: ProProducts.lifetime) {
                    lifetimePlan(lifetime)
                }
            }
        }
    }

    private func yearlyPlan(_ product: Product) -> some View {
        let renewal = PaywallFormatting.renewalPrice(for: product)
        let trial = isTrialEligible ? PaywallFormatting.freeTrialLength(for: product) : nil
        return PlanCard(title: "Yearly", price: renewal) {
            if let trial {
                Text("Free for \(trial), then \(renewal). Cancel anytime.")
            } else {
                Text("Renews automatically. Cancel anytime.")
            }
        } button: {
            purchaseButton(for: product) {
                if trial != nil {
                    Text("Start Free Trial")
                } else {
                    Text("Subscribe")
                }
            }
        }
    }

    private func lifetimePlan(_ product: Product) -> some View {
        PlanCard(title: "Lifetime", price: String(localized: "\(product.displayPrice) once")) {
            Text("Pay once and keep Pro for good. No subscription.")
        } button: {
            purchaseButton(for: product) {
                Text("Buy Lifetime")
            }
        }
    }

    private func purchaseButton<ButtonLabel: View>(
        for product: Product,
        @ViewBuilder label: () -> ButtonLabel
    ) -> some View {
        Button {
            buy(product)
        } label: {
            ZStack {
                label().opacity(busyAction == .purchase(product.id) ? 0 : 1)
                if busyAction == .purchase(product.id) {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(busyAction != nil)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Text("Payment is charged to your Apple Account. The yearly plan renews automatically unless you cancel at least 24 hours before the free trial or the current year ends. You can manage or cancel it anytime in your Apple Account settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                restore()
            } label: {
                if busyAction == .restore {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(busyAction != nil)
            ViewThatFits {
                HStack(spacing: 20) { legalLinks }
                VStack(spacing: 12) { legalLinks }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var legalLinks: some View {
        Link("Terms of Use", destination: ProProducts.legal.termsOfUse)
        Link("Privacy Policy", destination: ProProducts.legal.privacyPolicy)
    }

    private var proActive: some View {
        VStack(spacing: 16) {
            Label("You have Pro", systemImage: "checkmark.seal.fill")
                .font(.headline)
            if model.entitlements.activeProductID == ProProducts.lifetime {
                Text("Your lifetime purchase is active. Thank you for supporting Notification Toolkit.")
            } else {
                Text("Your yearly plan is active. Thank you for supporting Notification Toolkit.")
            }
            Button("Done") { close() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func loadProducts() async {
        if model.entitlements.products.isEmpty {
            loadState = .loading
        }
        do {
            let products = try await model.entitlements.loadProducts()
            if let subscription = products.first(where: { $0.id == ProProducts.yearly })?.subscription {
                isTrialEligible = await subscription.isEligibleForIntroOffer
            }
            loadState = products.isEmpty ? .failed : .loaded
        } catch {
            loadState = .failed
        }
    }

    private func buy(_ product: Product) {
        guard busyAction == nil else { return }
        busyAction = .purchase(product.id)
        Task {
            defer { busyAction = nil }
            do {
                switch try await model.entitlements.purchase(product, using: purchaseAction) {
                case .purchased:
                    close()
                case .pending:
                    show(.pending)
                case .cancelled:
                    break
                }
            } catch StoreKitError.userCancelled {
                // Not an error.
            } catch {
                show(.failed(error.localizedDescription))
            }
        }
    }

    private func restore() {
        guard busyAction == nil else { return }
        busyAction = .restore
        Task {
            defer { busyAction = nil }
            do {
                if try await model.entitlements.restore() {
                    close()
                } else {
                    show(.nothingToRestore)
                }
            } catch StoreKitError.userCancelled {
                // Not an error.
            } catch {
                show(.failed(error.localizedDescription))
            }
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func show(_ newAlert: PaywallAlert) {
        alert = newAlert
        isShowingAlert = true
    }
}

// MARK: - Supporting types

private enum LoadState: Hashable {
    case loading, loaded, failed
}

private enum BusyAction: Hashable {
    case purchase(String)
    case restore
}

private enum PaywallAlert: Hashable {
    case pending
    case nothingToRestore
    case failed(String)

    var title: String {
        switch self {
        case .pending: String(localized: "Purchase Pending")
        case .nothingToRestore: String(localized: "Nothing to Restore")
        case .failed: String(localized: "Purchase Failed")
        }
    }

    var message: String {
        switch self {
        case .pending:
            String(localized: "Your purchase is waiting for approval. Pro turns on as soon as it's approved.")
        case .nothingToRestore:
            String(localized: "No Pro purchase was found for this Apple Account.")
        case .failed(let description):
            description
        }
    }
}

private struct BenefitRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlanCard<Detail: View, PurchaseButton: View>: View {
    let title: LocalizedStringKey
    let price: String
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let button: () -> PurchaseButton

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(price)
                    .font(.title3.weight(.semibold))
                detail()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            button()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

/// Price and trial wording from StoreKit's localized values.
private enum PaywallFormatting {
    /// "$19.99 per year".
    static func renewalPrice(for product: Product) -> String {
        let price = product.displayPrice
        guard let period = product.subscription?.subscriptionPeriod else { return price }
        let count = period.value
        switch period.unit {
        case .day:
            return count == 1 ? String(localized: "\(price) per day") : String(localized: "\(price) every \(count) days")
        case .week:
            return count == 1 ? String(localized: "\(price) per week") : String(localized: "\(price) every \(count) weeks")
        case .month:
            return count == 1 ? String(localized: "\(price) per month") : String(localized: "\(price) every \(count) months")
        case .year:
            return count == 1 ? String(localized: "\(price) per year") : String(localized: "\(price) every \(count) years")
        @unknown default:
            return price
        }
    }

    /// "7 days" for a free-trial introductory offer, nil when there isn't one.
    static func freeTrialLength(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return nil
        }
        let count = offer.period.value * max(offer.periodCount, 1)
        switch offer.period.unit {
        case .day: return String(localized: "\(count) days")
        case .week: return String(localized: "\(count * 7) days")
        case .month: return String(localized: "\(count) months")
        case .year: return String(localized: "\(count) years")
        @unknown default: return nil
        }
    }
}

#Preview("Free") {
    PaywallView()
        .environment(AppModel.preview())
}

#if DEBUG
#Preview("Already Pro") {
    PaywallView()
        .environment(PaywallPreview.proModel())
}

@MainActor
private enum PaywallPreview {
    static func proModel() -> AppModel {
        let model = AppModel.preview()
        model.entitlements.overrideForPreview(isPro: true)
        return model
    }
}
#endif
