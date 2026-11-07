import Foundation
import Observation
import ToolkitCore

/// Everything the Log and Tools screens show.
@MainActor
@Observable
final class SpikeModel {

    // MARK: Event log

    private(set) var log = LogSnapshot()
    private(set) var isClearing = false

    var events: [SpikeEvent] { log.events }

    var csvExport: SpikeCSVExport { SpikeCSVExport(events: log.events) }

    /// See `SpikeSettings.reopenStoreEachCapture`.
    var reopenStoreEachCapture: Bool {
        didSet { SpikeSettings.reopenStoreEachCapture = reopenStoreEachCapture }
    }

    // MARK: Test tools

    private(set) var permission: PermissionSnapshot?
    private(set) var single: ScheduledRun?
    private(set) var burst: ScheduledRun?
    var toolError: String?

    var isShowingToolError: Bool {
        get { toolError != nil }
        set { if !newValue { toolError = nil } }
    }

    /// Seconds until the single test notification. Lock within the first 10 seconds:
    /// protected data becomes unavailable about 10 seconds after locking, so the
    /// capture at 30 seconds then runs while the phone is properly locked.
    static let singleDelay: TimeInterval = 30
    /// Lead-in before the first burst notification, time to lock the phone.
    static let burstLeadIn: TimeInterval = 10

    struct ScheduledRun: Hashable, Sendable {
        var marker: String
        var firstFireDate: Date
        var count: Int
        var options: SpikeNotificationOptions

        var lastFireDate: Date { firstFireDate.addingTimeInterval(TimeInterval(count - 1)) }
    }

    init() {
        reopenStoreEachCapture = SpikeSettings.reopenStoreEachCapture
    }

    // MARK: Log actions

    func reload() async {
        log = await LogSnapshot.load()
    }

    func clear() async {
        isClearing = true
        let problem = await LogSnapshot.clearAll()
        log = await LogSnapshot.load()
        if let problem { log.loadError = problem }
        isClearing = false
    }

    // MARK: Tool actions

    func refreshPermission() async {
        permission = await NotificationPoster.permission()
    }

    func requestPermission() async {
        do {
            _ = try await NotificationPoster.requestAuthorization()
        } catch {
            toolError = "Permission request failed: \(error.localizedDescription)"
        }
        await refreshPermission()
    }

    func postSingle(options: SpikeNotificationOptions) async {
        let marker = Self.makeMarker()
        let fireDate = Date().addingTimeInterval(Self.singleDelay)
        let notification = PlannedNotification(
            identifier: "spike-single-\(marker)",
            title: "NT Spike test \(marker)",
            subtitle: options.summary,
            body: options.noBody ? "" : "Scheduled for \(fireDate.formatted(date: .omitted, time: .standard)). Lock your iPhone within 10 seconds.",
            level: options.level,
            threadIdentifier: "spike-single",
            fireDate: fireDate
        )
        do {
            try await NotificationPoster.schedule([notification])
            single = ScheduledRun(marker: marker, firstFireDate: fireDate, count: 1, options: options)
        } catch {
            toolError = "Could not schedule the notification: \(error.localizedDescription)"
        }
        await refreshPermission()
    }

    func postBurst(count: Int, options: SpikeNotificationOptions) async {
        let count = min(max(count, 1), NotificationPoster.burstLimit)
        let marker = Self.makeMarker()
        let first = Date().addingTimeInterval(Self.burstLeadIn)
        let notifications = (1...count).map { index in
            PlannedNotification(
                identifier: "spike-burst-\(marker)-\(index)",
                // A group chat keeps one title; with no body the index moves to the title.
                title: options.noBody ? "Spike group \(marker) #\(index)" : "Spike group \(marker)",
                subtitle: options.summary,
                body: options.noBody ? "" : "Message \(index) of \(count)",
                level: options.level,
                threadIdentifier: "spike-burst-\(marker)",
                fireDate: first.addingTimeInterval(TimeInterval(index - 1))
            )
        }
        do {
            try await NotificationPoster.schedule(notifications)
            burst = ScheduledRun(marker: marker, firstFireDate: first, count: count, options: options)
        } catch {
            toolError = "Could not schedule the burst: \(error.localizedDescription)"
        }
        await refreshPermission()
    }

    func cancelPending() async {
        await NotificationPoster.cancelPending()
        single = nil
        burst = nil
        await refreshPermission()
    }

    /// Four characters that tie a test notification to its captures in the log.
    private static func makeMarker() -> String {
        String(UUID().uuidString.prefix(4))
    }
}

// MARK: - Loading the log

struct AppCount: Hashable, Sendable, Identifiable {
    var app: String
    var count: Int
    var id: String { app }
}

struct HourCount: Hashable, Sendable, Identifiable {
    var hourStart: Date
    var count: Int
    var id: Date { hourStart }
}

struct LogSummary: Hashable, Sendable {
    var total = 0
    var locked = 0
    var coldLaunches = 0
    var processes = 0
    var sqliteFailures = 0
    var medianDurationMs: Double?
    var maxDurationMs: Double?
    var medianDelaySeconds: Double?
    var maxDelaySeconds: Double?
}

/// The event log read from disk, with counts worked out off the main actor.
struct LogSnapshot: Sendable {
    /// Newest first.
    var events: [SpikeEvent] = []
    var summary = LogSummary()
    /// Most events first.
    var appCounts: [AppCount] = []
    /// Newest hour first, local time.
    var hourCounts: [HourCount] = []
    var unreadableLines = 0
    var loadError: String?
    /// Rows in the spike's SQLite store, to compare with the JSON line count.
    var sqliteRowCount: Int?
    var sqliteError: String?
    var eventLogWriteFailures = 0
    var lastEventLogWriteFailure: String?

    @concurrent
    static func load() async -> LogSnapshot {
        var snapshot = LogSnapshot()
        do {
            let contents = try SpikeEventLog.read()
            snapshot.events = contents.events.sorted { $0.capturedAt > $1.capturedAt }
            snapshot.unreadableLines = contents.unreadableLines
        } catch {
            snapshot.loadError = error.localizedDescription
        }
        do {
            snapshot.sqliteRowCount = try SpikeStore.withStore { try $0.entryCount(filter: .all) }
        } catch {
            snapshot.sqliteError = String(describing: error)
        }
        snapshot.eventLogWriteFailures = SpikeDiagnostics.eventLogFailureCount
        snapshot.lastEventLogWriteFailure = SpikeDiagnostics.lastEventLogFailure

        let events = snapshot.events
        snapshot.summary = LogSummary(
            total: events.count,
            locked: events.filter { $0.isLocked }.count,
            coldLaunches: events.filter { $0.isColdLaunch }.count,
            processes: Set(events.map { "\($0.processID)@\($0.processLaunchedAt.timeIntervalSince1970)" }).count,
            sqliteFailures: events.filter { !$0.sqliteSucceeded }.count,
            medianDurationMs: median(events.map { $0.durationMs }),
            maxDurationMs: events.map { $0.durationMs }.max(),
            medianDelaySeconds: median(events.compactMap { $0.delaySeconds }),
            maxDelaySeconds: events.compactMap { $0.delaySeconds }.max()
        )
        snapshot.appCounts = Dictionary(grouping: events) { $0.displayApp }
            .map { AppCount(app: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.app < $1.app }
        let calendar = Calendar.current
        snapshot.hourCounts = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .hour, for: event.capturedAt)?.start ?? event.capturedAt
        }
        .map { HourCount(hourStart: $0.key, count: $0.value.count) }
        .sorted { $0.hourStart > $1.hourStart }
        return snapshot
    }

    /// Deletes events.jsonl and every entry in the spike's store. Returns what failed, if anything.
    @concurrent
    static func clearAll() async -> String? {
        var problems: [String] = []
        do {
            try SpikeEventLog.clear()
        } catch {
            problems.append("Event log: \(error.localizedDescription)")
        }
        do {
            _ = try SpikeStore.withStore { try $0.deleteAll() }
        } catch {
            problems.append("SQLite: \(String(describing: error))")
        }
        SpikeDiagnostics.reset()
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
