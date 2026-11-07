import Foundation

// CONTRACT STUB — workstream W6 replaces this file. Keep `isAvailable`.

/// Device authentication for the optional app lock (NFR-3).
enum AppLock {
    /// Whether the device has Face ID, Touch ID or a passcode to lock with.
    /// Settings disables the lock toggle when false.
    @MainActor static var isAvailable: Bool { false }
}
