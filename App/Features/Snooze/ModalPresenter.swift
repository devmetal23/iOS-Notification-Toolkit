import UIKit

/// Presents follow-up UI (paywall, date picker, alerts) from the top view
/// controller with UIKit.
///
/// SwiftUI sheets attached inside a `Menu`, context menu or `confirmationDialog`
/// are lost when that menu or dialog dismisses, so flows that start there present
/// through this instead.
@MainActor
enum ModalPresenter {
    /// The foreground window scene. The app supports a single scene.
    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// The front-most view controller of the app's normal-level window (not the
    /// app lock overlay, which sits above it), ignoring anything being dismissed.
    static func topViewController() -> UIViewController? {
        guard let scene = activeWindowScene() else { return nil }
        let appWindows = scene.windows.filter { $0.windowLevel == .normal }
        let window = appWindows.first { $0.isKeyWindow } ?? appWindows.first { !$0.isHidden }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Presents `controller` once any menu, dialog or sheet that is still
    /// animating away has finished, so UIKit doesn't drop the presentation.
    static func present(_ controller: UIViewController) async {
        for _ in 0..<30 {
            guard let host = topViewController() else { return }
            let isBusy = host.presentedViewController != nil
                || host.isBeingPresented
                || host.isBeingDismissed
                || host.transitionCoordinator != nil
            if !isBusy {
                host.present(controller, animated: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        topViewController()?.present(controller, animated: true)
    }

    /// Presents an alert. With no actions it gets a single OK button.
    static func presentAlert(
        title: String,
        message: String,
        actions: [UIAlertAction] = [],
        preferred: UIAlertAction? = nil
    ) async {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if actions.isEmpty {
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        }
        for action in actions {
            alert.addAction(action)
        }
        alert.preferredAction = preferred
        await present(alert)
    }
}

/// Weakly holds a controller presented with `ModalPresenter`, so its SwiftUI
/// content can dismiss it (`\.dismiss` can't close a UIKit presentation).
@MainActor
final class PresentedControllerBox {
    weak var controller: UIViewController?

    func dismiss(then completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let controller, controller.presentingViewController != nil else {
            completion?()
            return
        }
        controller.dismiss(animated: true) {
            completion?()
        }
    }
}
