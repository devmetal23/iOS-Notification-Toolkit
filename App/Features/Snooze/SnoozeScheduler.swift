import Foundation
import ToolkitCore

// CONTRACT STUB — workstream W6 replaces the bodies. Keep the signatures.

/// Records snoozes in the store and schedules their local notifications (FR-14).
@MainActor
final class SnoozeScheduler {
    private let settings: SharedSettings
    private let openStore: @Sendable () throws -> any NotificationStoring

    init(settings: SharedSettings, openStore: @escaping @Sendable () throws -> any NotificationStoring) {
        self.settings = settings
        self.openStore = openStore
    }

    /// Asks for notification permission if needed, stores the snooze and schedules it.
    func snooze(_ entry: NotificationEntry, option: SnoozeOption) async throws -> SnoozeRecord {
        fatalError("W6: not implemented")
    }

    func reschedule(_ record: SnoozeRecord, option: SnoozeOption) async throws -> SnoozeRecord {
        fatalError("W6: not implemented")
    }

    func cancel(_ record: SnoozeRecord) async throws {}

    /// Removes pending local notifications, e.g. after their entries were deleted.
    func cancel(requestIdentifiers: [String]) {}

    /// Drops records whose notification has already fired.
    func removeFiredRecords() async {}
}
