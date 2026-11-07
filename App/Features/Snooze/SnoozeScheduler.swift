import Foundation
import ToolkitCore
import UserNotifications

/// Records snoozes in the store and schedules their local notifications (FR-14).
///
/// Pro gating and all UI live in `SnoozeFlow`; this type only does the work.
@MainActor
final class SnoozeScheduler {
    /// A snooze must come back at least this many seconds from now.
    static let minimumLeadTime: TimeInterval = 5

    private let settings: SharedSettings
    private let openStore: @Sendable () throws -> any NotificationStoring

    init(settings: SharedSettings, openStore: @escaping @Sendable () throws -> any NotificationStoring) {
        self.settings = settings
        self.openStore = openStore
    }

    /// Asks for notification permission if needed, stores the snooze and schedules it.
    ///
    /// An entry has at most one pending snooze: snoozing it again moves that snooze.
    /// - Throws: `SnoozeError.notificationsDenied`, `SnoozeError.timeInPast`, a
    ///   `StoreError`, or the error from scheduling the notification.
    func snooze(_ entry: NotificationEntry, option: SnoozeOption) async throws -> SnoozeRecord {
        try await ensureAuthorized()
        let now = Date()
        let fireAt = try fireDate(for: option, now: now)
        let store = try openStore()

        if let existing = try store.pendingSnoozes(after: now).first(where: { $0.entry.id == entry.id }) {
            return try await move(existing, to: fireAt, in: store)
        }

        let record = try store.addSnooze(entryID: entry.id, fireAt: fireAt, createdAt: now)
        do {
            try await SnoozeNotifications.schedule(SnoozeNotificationPayload(record: record))
        } catch {
            // Never leave a record behind that has no notification to bring it back.
            try? store.removeSnooze(id: record.id)
            throw error
        }
        return record
    }

    /// Moves a pending snooze to a new time.
    func reschedule(_ record: SnoozeRecord, option: SnoozeOption) async throws -> SnoozeRecord {
        try await ensureAuthorized()
        let fireAt = try fireDate(for: option, now: Date())
        return try await move(record, to: fireAt, in: openStore())
    }

    /// Deletes the snooze and removes its notification, pending or delivered.
    func cancel(_ record: SnoozeRecord) async throws {
        do {
            try openStore().removeSnooze(id: record.id)
        } catch StoreError.notFound {
            // Already fired and cleaned up; its notification may still be pending or delivered.
        }
        cancel(requestIdentifiers: [record.requestIdentifier])
    }

    /// Removes pending local notifications, e.g. after their entries were deleted.
    /// Also removes them from Notification Center if they were already delivered.
    func cancel(requestIdentifiers: [String]) {
        SnoozeNotifications.removePending(requestIdentifiers)
        SnoozeNotifications.removeDelivered(requestIdentifiers)
    }

    /// Drops records whose notification has already fired, re-schedules future
    /// records that lost their pending request, and removes pending snooze
    /// requests that no longer have a record.
    func removeFiredRecords() async {
        // Read the pending requests before the records: a snooze added in between
        // then has its record read but not its request, so it is re-scheduled
        // (harmless) instead of being taken for an orphan and removed.
        let pendingIdentifiers = await SnoozeNotifications.pendingRequestIdentifiers()
        let now = Date()
        let upcoming: [SnoozeRecord]
        do {
            let store = try openStore()
            try store.removeSnoozes(firedBefore: now)
            upcoming = try store.pendingSnoozes(after: now)
        } catch {
            // The store is unreadable before the first unlock after a restart; retry next launch.
            return
        }

        let expected = Set(upcoming.map(\.requestIdentifier))
        let orphans = pendingIdentifiers.filter {
            SnoozeUserInfo.isSnoozeRequestIdentifier($0) && !expected.contains($0)
        }
        SnoozeNotifications.removePending(Array(orphans))

        for record in upcoming where !pendingIdentifiers.contains(record.requestIdentifier) {
            try? await SnoozeNotifications.schedule(SnoozeNotificationPayload(record: record))
        }
    }

    // MARK: - Private

    private func move(_ record: SnoozeRecord, to fireAt: Date, in store: any NotificationStoring) async throws -> SnoozeRecord {
        let updated = try store.rescheduleSnooze(id: record.id, fireAt: fireAt)
        do {
            // Same identifier, so this replaces the pending request.
            try await SnoozeNotifications.schedule(SnoozeNotificationPayload(record: updated))
        } catch {
            // The old request is still pending; put the record back to match it.
            _ = try? store.rescheduleSnooze(id: record.id, fireAt: record.fireAt)
            throw error
        }
        return updated
    }

    private func fireDate(for option: SnoozeOption, now: Date) throws -> Date {
        let date = option.fireDate(from: now, calendar: .current, morningHour: settings.morningHour)
        guard date.timeIntervalSince(now) >= Self.minimumLeadTime else {
            throw SnoozeError.timeInPast
        }
        return date
    }

    private func ensureAuthorized() async throws {
        switch await SnoozeNotifications.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = (try? await SnoozeNotifications.requestAuthorization()) ?? false
            if !granted { throw SnoozeError.notificationsDenied }
        case .denied:
            throw SnoozeError.notificationsDenied
        @unknown default:
            // Let scheduling decide rather than block on a status we don't know.
            return
        }
    }
}

/// Why a snooze couldn't be set.
enum SnoozeError: LocalizedError, Hashable {
    /// Notification permission is off, so the snooze could never come back.
    /// Offer `UIApplication.openSettingsURLString`.
    case notificationsDenied
    /// The chosen time has already passed.
    case timeInPast

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            String(localized: "Notifications are turned off for Notification Toolkit.")
        case .timeInPast:
            String(localized: "That time has already passed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notificationsDenied:
            String(localized: "Allow notifications in Settings so snoozed notifications can come back.")
        case .timeInPast:
            String(localized: "Choose a later time.")
        }
    }
}

/// Keys in a snooze notification's `userInfo`, read by `NotificationDelegate`.
enum SnoozeUserInfo {
    static let entryIDKey = "entryID"
    static let snoozeIDKey = "snoozeID"

    /// The entry a delivered snooze belongs to, if the notification is a snooze.
    static func entryID(in userInfo: [AnyHashable: Any]) -> NotificationEntry.ID? {
        switch userInfo[entryIDKey] {
        case let number as NSNumber: number.int64Value
        case let text as String: NotificationEntry.ID(text)
        default: nil
        }
    }

    /// Whether `identifier` has the `SnoozeRecord.requestIdentifier` format.
    static func isSnoozeRequestIdentifier(_ identifier: String) -> Bool {
        guard let dash = identifier.lastIndex(of: "-"),
              let id = SnoozeRecord.ID(identifier[identifier.index(after: dash)...])
        else { return false }
        return SnoozeRecord.requestIdentifier(for: id) == identifier
    }
}

/// Everything needed to schedule one snooze notification, as Sendable values.
struct SnoozeNotificationPayload: Sendable, Hashable {
    var requestIdentifier: String
    var title: String
    var subtitle: String
    var body: String
    var threadIdentifier: String
    var entryID: NotificationEntry.ID
    var snoozeID: SnoozeRecord.ID
    var fireAt: Date

    /// The original notification's app name and text (FR-14): the title, or the app
    /// name when there is none; the app name as subtitle unless it is already the
    /// title; the original subtitle (if any) and body as the body.
    init(record: SnoozeRecord) {
        let entry = record.entry
        let appName = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shownTitle = title.isEmpty ? appName : title

        requestIdentifier = record.requestIdentifier
        self.title = shownTitle
        subtitle = AppKey(appName: shownTitle) == entry.appKey ? "" : appName
        body = [entry.subtitle, entry.body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        threadIdentifier = "snooze.\(entry.appKey.rawValue)"
        entryID = entry.id
        snoozeID = record.id
        fireAt = record.fireAt
    }
}

/// `UNUserNotificationCenter` calls for snoozes.
///
/// The async ones are `@concurrent` and take and return only Sendable values, so
/// non-Sendable results such as `UNNotificationSettings` and `UNNotificationRequest`
/// never cross from the center into main-actor code.
enum SnoozeNotifications {
    @concurrent
    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    @concurrent
    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Adds the request, replacing any pending one with the same identifier.
    @concurrent
    static func schedule(_ payload: SnoozeNotificationPayload) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.sound = .default
        content.threadIdentifier = payload.threadIdentifier
        content.userInfo = [
            SnoozeUserInfo.entryIDKey: payload.entryID,
            SnoozeUserInfo.snoozeIDKey: payload.snoozeID,
        ]

        // Pinned to the current calendar and time zone, so the snooze fires at the
        // stored `fireAt` instant even if the user changes time zone meanwhile.
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: payload.fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: payload.requestIdentifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    @concurrent
    static func pendingRequestIdentifiers() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.map { $0.identifier })
    }

    static func removePending(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func removeDelivered(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
