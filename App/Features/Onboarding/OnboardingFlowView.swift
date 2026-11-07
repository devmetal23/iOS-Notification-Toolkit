import SwiftUI
import ToolkitCore

/// First run (FR-1): what the app does and the privacy promise, how capture
/// works, notification permission (skippable), then off to Setup.
/// Finishes with `model.selectedTab = .setup`, then `model.hasCompletedOnboarding = true`.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model

    @State private var page = OnboardingPage.welcome
    @State private var permission: LocalNotificationPermission?
    @State private var isRequestingPermission = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(OnboardingPage.welcome)
                captureFlowPage.tag(OnboardingPage.howCaptureWorks)
                notificationsPage.tag(OnboardingPage.notifications)
                firstAppsPage.tag(OnboardingPage.firstApps)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .task {
            permission = await LocalNotificationPermission.current()
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPageView(
            symbol: "clock.arrow.circlepath",
            title: "Notification Toolkit",
            message: "A searchable history of notifications from the apps you choose."
        ) {
            ForEach(CaptureExplanation.privacyPoints) { ExplanationPointRow(point: $0) }
        }
    }

    private var captureFlowPage: some View {
        OnboardingPageView(
            symbol: "switch.2",
            title: "How Capture Works",
            message: "Notification Toolkit can't read notifications on its own. Instead, a Shortcuts automation you switch on passes each notification from an app you choose to Notification Toolkit."
        ) {
            HowItWorksVideoSlot()
            ForEach(CaptureExplanation.capturePoints) { ExplanationPointRow(point: $0) }
        }
    }

    private var notificationsPage: some View {
        OnboardingPageView(
            symbol: "bell.badge",
            title: "Allow Notifications?",
            message: "Notification Toolkit sends its own notifications for two things. You can skip this and decide later."
        ) {
            ExplanationPointRow(point: ExplanationPoint(
                symbol: "checkmark.seal",
                title: "Test notification",
                detail: "Check that capture is working, any time, from Setup."
            ))
            ExplanationPointRow(point: ExplanationPoint(
                symbol: "moon.zzz",
                title: "Snoozes",
                detail: "A notification you snooze comes back at the time you pick."
            ))
            switch permission {
            case .allowed:
                Label("Notifications are on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Notifications are off. You can turn them on later in Settings.", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            case .notDetermined, nil:
                EmptyView()
            }
        }
    }

    private var firstAppsPage: some View {
        OnboardingPageView(
            symbol: "square.grid.2x2",
            title: "Add Your First Apps",
            message: "Your history starts empty and fills as notifications arrive from apps you set up. Pick apps from the catalog, or set up any other app by hand."
        ) {
            ExplanationPointRow(point: ExplanationPoint(
                symbol: "checkmark.seal",
                title: "See it work first",
                detail: "Test Capture in Setup sends a test notification and shows it being logged."
            ))
            if !model.entitlements.isPro {
                ExplanationPointRow(point: ExplanationPoint(
                    symbol: "info.circle",
                    title: "Free includes 3 apps",
                    detail: "And 7 days of history. Pro removes both limits."
                ))
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            OnboardingPageIndicator(current: page)

            switch page {
            case .welcome, .howCaptureWorks:
                primaryButton("Continue", action: advance)
            case .notifications:
                if permission == nil || permission == .notDetermined {
                    primaryButton("Allow Notifications") {
                        Task { await requestPermission() }
                    }
                    .disabled(isRequestingPermission)
                    Button("Not Now", action: advance)
                        .disabled(isRequestingPermission)
                } else {
                    primaryButton("Continue", action: advance)
                }
            case .firstApps:
                primaryButton("Add Your First Apps", action: finish)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: Actions

    private func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        withAnimation {
            page = next
        }
    }

    private func requestPermission() async {
        isRequestingPermission = true
        permission = await LocalNotificationPermission.request()
        isRequestingPermission = false
        advance()
    }

    private func finish() {
        model.selectedTab = .setup
        model.hasCompletedOnboarding = true
    }
}

enum OnboardingPage: Int, CaseIterable, Hashable {
    case welcome
    case howCaptureWorks
    case notifications
    case firstApps
}

/// A scrollable page: hero symbol, title, message, then the page's points.
private struct OnboardingPageView<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct OnboardingPageIndicator: View {
    let current: OnboardingPage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases, id: \.self) { page in
                Circle()
                    .fill(page == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current.rawValue + 1) of \(OnboardingPage.allCases.count)"))
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppModel.preview())
}
