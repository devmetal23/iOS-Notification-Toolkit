import Foundation
import LocalAuthentication

/// Device authentication for the optional app lock (NFR-3).
///
/// Uses `.deviceOwnerAuthentication`: Face ID, Touch ID or Optic ID, falling back
/// to the device passcode.
enum AppLock {
    enum Outcome: Hashable, Sendable {
        case success
        /// Wrong face, finger or passcode.
        case failed
        /// The user, the app or the system cancelled the prompt.
        case cancelled
        /// No biometrics and no passcode: the app must not lock the user out.
        case unavailable
    }

    /// Whether the device has Face ID, Touch ID or a passcode to lock with.
    /// Settings disables the lock toggle when false.
    @MainActor static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// SF Symbol for the unlock button: the device's biometry, or a lock for passcode only.
    @MainActor static var unlockSymbolName: String {
        let context = LAContext()
        // `biometryType` is only set after a canEvaluatePolicy call.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }

    /// Asks for Face ID, Touch ID or the passcode. True only on success.
    /// Use it to confirm before turning the lock on.
    static func authenticate(reason: String) async -> Bool {
        await evaluate(reason: reason) == .success
    }

    /// Asks for Face ID, Touch ID or the passcode.
    ///
    /// The `LAContext` is created, used and released inside this one function, so it
    /// never crosses an isolation boundary or outlives its prompt.
    @concurrent
    static func evaluate(reason: String) async -> Outcome {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return .unavailable
        }
        do {
            let succeeded = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return succeeded ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .notInteractive, .userFallback:
                return .cancelled
            case .passcodeNotSet:
                // Only a missing passcode means there is truly no way in. Biometry
                // errors stay `.failed`: the passcode can still unlock.
                return .unavailable
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
