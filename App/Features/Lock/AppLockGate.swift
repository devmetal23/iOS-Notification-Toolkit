import Observation
import SwiftUI
import ToolkitCore
import UIKit

/// Optional Face ID lock, plus a privacy cover in the app switcher (NFR-3).
///
/// When `settings.isAppLockEnabled`, the app locks at launch and whenever it
/// returns from the background, and asks for Face ID, Touch ID or the passcode.
/// Whenever the scene isn't active, a privacy cover hides it, lock or not.
/// Both are drawn in an overlay `UIWindow` above the app, so they also hide
/// sheets and alerts. If the device can't authenticate (no passcode), it never
/// locks the user out.
struct AppLockGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        AppLockContainer(settings: model.settings, content: content)
    }
}

/// Owns the lock state for the scene. Split from `AppLockGate` so the lock state
/// can be created from the settings before the first frame.
private struct AppLockContainer<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: AppLockController
    private let content: () -> Content

    init(settings: SharedSettings, content: @escaping () -> Content) {
        // Only the first value is kept; later ones are cheap and discarded.
        _controller = State(initialValue: AppLockController(settings: settings))
        self.content = content
    }

    var body: some View {
        content()
            .accessibilityHidden(controller.isObscuring)
            .overlay {
                // Covers the content until the overlay window is up (first frames,
                // and SwiftUI previews, which get no window).
                if controller.isObscuring && !controller.hasOverlayWindow {
                    AppLockOverlayView(controller: controller)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                controller.sceneDidChange(to: phase)
            }
            .onDisappear {
                controller.removeOverlayWindow()
            }
    }
}

/// Lock and privacy-cover state for one scene.
@MainActor
@Observable
final class AppLockController {
    /// Waiting for Face ID, Touch ID or the passcode.
    private(set) var isLocked: Bool
    /// The scene isn't active (app switcher, Control Center, a system prompt).
    private(set) var isCovered = false
    private(set) var isAuthenticating = false
    private(set) var hasOverlayWindow = false

    /// Whether anything should hide the app right now.
    var isObscuring: Bool { isLocked || isCovered }

    @ObservationIgnored private let settings: SharedSettings
    @ObservationIgnored private var overlayWindow: AppLockOverlayWindow?
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var hasBeenActive = false
    @ObservationIgnored private var hasPromptedSinceLock = false
    /// Bumped on every lock, so a prompt that outlives its lock is ignored.
    @ObservationIgnored private var lockGeneration = 0

    init(settings: SharedSettings) {
        self.settings = settings
        // Cheap on purpose: SwiftUI may create and discard several of these.
        // Whether the device can authenticate is checked when the prompt is due.
        self.isLocked = settings.isAppLockEnabled
    }

    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            isSceneActive = true
            hasBeenActive = true
            isCovered = false
        case .background:
            isSceneActive = false
            isCovered = true
            if settings.isAppLockEnabled { lock() }
        case .inactive:
            isSceneActive = false
            // A cold launch passes through inactive before the app is ever shown;
            // don't flash the cover then.
            isCovered = hasBeenActive
        @unknown default:
            isSceneActive = false
            isCovered = hasBeenActive
        }
        installOverlayWindowIfNeeded()
        updateOverlayWindow()
        promptIfNeeded()
    }

    /// The Unlock button on the lock screen.
    func unlockTapped() {
        guard isLocked, !isAuthenticating else { return }
        Task { await authenticate() }
    }

    func removeOverlayWindow() {
        guard let overlayWindow else { return }
        setAppWindowsAccessibilityHidden(false, in: overlayWindow.windowScene)
        overlayWindow.isHidden = true
        overlayWindow.rootViewController = nil
        self.overlayWindow = nil
        hasOverlayWindow = false
    }

    // MARK: - Locking

    private func lock() {
        lockGeneration += 1
        hasPromptedSinceLock = false
        if !isLocked {
            isLocked = true
            // Hide the keyboard: its window sits above the overlay.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// Prompts once per lock, and only while the scene is active: the prompt
    /// itself makes the scene inactive, and a failed or cancelled prompt must not
    /// immediately reappear.
    private func promptIfNeeded() {
        guard isLocked, isSceneActive, !isAuthenticating, !hasPromptedSinceLock else { return }
        hasPromptedSinceLock = true
        Task { await authenticate() }
    }

    private func authenticate() async {
        guard AppLock.isAvailable else {
            // No Face ID, Touch ID or passcode any more: never lock the user out.
            unlock()
            return
        }
        let generation = lockGeneration
        isAuthenticating = true
        let outcome = await AppLock.evaluate(
            reason: String(localized: "Unlock Notification Toolkit to see your notification history.")
        )
        isAuthenticating = false
        guard generation == lockGeneration else {
            // The app went to the background and locked again during the prompt.
            promptIfNeeded()
            return
        }
        switch outcome {
        case .success, .unavailable:
            unlock()
        case .failed, .cancelled:
            // Stay locked; the lock screen's Unlock button tries again.
            break
        }
    }

    private func unlock() {
        guard isLocked else { return }
        isLocked = false
        updateOverlayWindow()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    // MARK: - Overlay window

    private func installOverlayWindowIfNeeded() {
        guard overlayWindow == nil, !Self.isRunningForPreviews,
              let scene = ModalPresenter.activeWindowScene()
        else { return }
        let window = AppLockOverlayWindow(windowScene: scene)
        // Above the app's own sheets and alerts. Never made key, so the app keeps
        // keyboard focus and `ModalPresenter` keeps presenting from the app window.
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: AppLockOverlayView(controller: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = true
        overlayWindow = window
        hasOverlayWindow = true
    }

    private func updateOverlayWindow() {
        guard let overlayWindow else { return }
        let show = isObscuring
        if overlayWindow.isHidden == show {
            overlayWindow.isHidden = !show
        }
        setAppWindowsAccessibilityHidden(show, in: overlayWindow.windowScene)
    }

    /// Keeps VoiceOver out of the app (sheets included) while it is hidden.
    private func setAppWindowsAccessibilityHidden(_ hidden: Bool, in scene: UIWindowScene?) {
        guard let scene else { return }
        for window in scene.windows where !(window is AppLockOverlayWindow) {
            window.accessibilityElementsHidden = hidden
        }
    }

    private static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// The window that holds the lock screen and privacy cover above the app.
final class AppLockOverlayWindow: UIWindow {}

/// The lock screen, or a plain privacy cover when the app is only inactive.
struct AppLockOverlayView: View {
    let controller: AppLockController

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            if controller.isLocked {
                lockScreen
            } else {
                Image(systemName: "bell.badge")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Notification Toolkit Is Locked")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Your notification history stays private until you unlock.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                controller.unlockTapped()
            } label: {
                Label("Unlock", systemImage: AppLock.unlockSymbolName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(controller.isAuthenticating)
            .padding(.top, 8)
        }
        .padding(32)
    }
}

#Preview("Gate") {
    AppLockGate {
        Text("App content")
    }
    .environment(AppModel.preview())
}

#Preview("Lock screen") {
    AppLockOverlayView(controller: AppLockControllerPreview.locked())
}

#Preview("Privacy cover") {
    AppLockOverlayView(controller: AppLockControllerPreview.unlocked())
}

@MainActor
private enum AppLockControllerPreview {
    static func locked() -> AppLockController {
        let settings = SharedSettings(defaults: UserDefaults(suiteName: "lock-preview-\(UUID().uuidString)")!)
        settings.isAppLockEnabled = true
        return AppLockController(settings: settings)
    }

    static func unlocked() -> AppLockController {
        AppLockController(settings: SharedSettings(defaults: UserDefaults(suiteName: "lock-preview-\(UUID().uuidString)")!))
    }
}
