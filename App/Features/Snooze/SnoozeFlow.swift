import Accessibility
import SwiftUI
import ToolkitCore
import UIKit

/// Starts a snooze from anywhere in the app: Pro gating (paywall), notification
/// permission errors, the custom-time picker, and confirmation (FR-14). Presents
/// its own UI, so callers such as a list-level `confirmationDialog` only pick.
///
/// Follow-up UI is presented from the top view controller with UIKit
/// (`ModalPresenter`), because SwiftUI sheets attached inside menus and dialogs
/// are lost when those dismiss.
@MainActor
enum SnoozeFlow {
    /// Snoozes with `option`, or presents the paywall when the user isn't Pro.
    /// Buying Pro from that paywall carries on with the snooze.
    static func choose(_ option: SnoozeOption, for entry: NotificationEntry, model: AppModel) async {
        guard model.entitlements.isPro else {
            await presentPaywall(model: model) {
                Task { await SnoozeFlow.choose(option, for: entry, model: model) }
            }
            return
        }
        do {
            let record = try await model.snoozes.snooze(entry, option: option)
            model.historyDidChange()
            confirm(SnoozeFormatting.confirmation(for: record.fireAt))
        } catch {
            await presentError(error, title: String(localized: "Couldn't Snooze"))
        }
    }

    /// Presents the custom date picker, or the paywall when the user isn't Pro.
    static func chooseCustomTime(for entry: NotificationEntry, model: AppModel) {
        Task {
            guard model.entitlements.isPro else {
                await presentPaywall(model: model) {
                    SnoozeFlow.chooseCustomTime(for: entry, model: model)
                }
                return
            }
            await presentTimePicker(
                title: String(localized: "Snooze Until"),
                confirmTitle: String(localized: "Snooze"),
                initialDate: nil
            ) { date in
                Task { await SnoozeFlow.choose(.custom(date), for: entry, model: model) }
            }
        }
    }

    /// Moves a pending snooze (FR-15), or presents the paywall when the user isn't Pro.
    static func reschedule(_ record: SnoozeRecord, to option: SnoozeOption, model: AppModel) async {
        guard model.entitlements.isPro else {
            await presentPaywall(model: model) {
                Task { await SnoozeFlow.reschedule(record, to: option, model: model) }
            }
            return
        }
        do {
            let updated = try await model.snoozes.reschedule(record, option: option)
            model.historyDidChange()
            confirm(SnoozeFormatting.confirmation(for: updated.fireAt))
        } catch {
            await presentError(error, title: String(localized: "Couldn't Change Snooze"))
            // The snooze may have fired or been deleted meanwhile; let lists reload.
            model.historyDidChange()
        }
    }

    /// Presents the date picker for moving a pending snooze.
    static func chooseCustomRescheduleTime(for record: SnoozeRecord, model: AppModel) {
        Task {
            guard model.entitlements.isPro else {
                await presentPaywall(model: model) {
                    SnoozeFlow.chooseCustomRescheduleTime(for: record, model: model)
                }
                return
            }
            await presentTimePicker(
                title: String(localized: "Change Snooze"),
                confirmTitle: String(localized: "Save"),
                initialDate: record.fireAt
            ) { date in
                Task { await SnoozeFlow.reschedule(record, to: .custom(date), model: model) }
            }
        }
    }

    /// Cancels a pending snooze. Free users can always cancel.
    /// Returns false when it failed (an alert was shown).
    @discardableResult
    static func cancel(_ record: SnoozeRecord, model: AppModel) async -> Bool {
        do {
            try await model.snoozes.cancel(record)
            model.historyDidChange()
            confirm(String(localized: "Snooze cancelled"))
            return true
        } catch {
            await presentError(error, title: String(localized: "Couldn't Cancel Snooze"))
            model.historyDidChange()
            return false
        }
    }

    // MARK: - Presentation

    private static func presentPaywall(model: AppModel, onUnlock: @escaping @MainActor @Sendable () -> Void) async {
        let box = PresentedControllerBox()
        let paywall = PaywallView(onClose: {
            let unlocked = model.entitlements.isPro
            box.dismiss {
                if unlocked { onUnlock() }
            }
        })
        .environment(model)
        let host = UIHostingController(rootView: paywall)
        box.controller = host
        await ModalPresenter.present(host)
    }

    private static func presentTimePicker(
        title: String,
        confirmTitle: String,
        initialDate: Date?,
        onPick: @escaping @MainActor @Sendable (Date) -> Void
    ) async {
        let box = PresentedControllerBox()
        let picker = SnoozeTimePicker(
            title: title,
            confirmTitle: confirmTitle,
            initialDate: initialDate,
            onCancel: { box.dismiss() },
            onConfirm: { date in
                box.dismiss { onPick(date) }
            }
        )
        let host = UIHostingController(rootView: picker)
        host.sheetPresentationController?.prefersGrabberVisible = true
        box.controller = host
        await ModalPresenter.present(host)
    }

    private static func presentError(_ error: any Error, title: String) async {
        if case SnoozeError.notificationsDenied = error {
            let openSettings = UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            let notNow = UIAlertAction(title: String(localized: "Not Now"), style: .cancel)
            await ModalPresenter.presentAlert(
                title: String(localized: "Turn On Notifications"),
                message: String(localized: "Snoozed notifications come back as notifications from Notification Toolkit. Allow notifications in Settings to use snooze."),
                actions: [notNow, openSettings],
                preferred: openSettings
            )
            return
        }
        await ModalPresenter.presentAlert(title: title, message: message(for: error))
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case SnoozeError.timeInPast:
            String(localized: "That time has already passed. Choose a later time.")
        case StoreError.unavailable:
            String(localized: "Your history stays locked until you unlock your iPhone. Unlock it and try again.")
        case StoreError.notFound:
            String(localized: "This notification or snooze no longer exists.")
        default:
            String(localized: "Something went wrong. Try again.")
        }
    }

    /// A light haptic plus a VoiceOver announcement.
    private static func confirm(_ message: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            // Let VoiceOver finish announcing the dismissed menu or dialog first.
            try? await Task.sleep(for: .milliseconds(500))
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
