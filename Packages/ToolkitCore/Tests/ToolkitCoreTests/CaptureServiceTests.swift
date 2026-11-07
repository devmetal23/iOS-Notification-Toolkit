import Foundation
import Testing
import ToolkitCore

@Suite("Capture pipeline")
struct CaptureServiceTests {
    let store: SQLiteNotificationStore
    let settings: SharedSettings
    let clock: TestSupport.Clock
    let service: CaptureService
    let day = TestSupport.day

    init() throws {
        let store = try SQLiteNotificationStore.inMemory()
        let settings = TestSupport.makeSettings()
        let clock = TestSupport.Clock()
        self.store = store
        self.settings = settings
        self.clock = clock
        self.service = CaptureService(store: store, settings: settings, now: { clock.now })
    }

    private func ownNotification(body: String = "Test notification") -> NewNotification {
        TestSupport.notification(app: "Notification Toolkit", title: "Notification Toolkit", body: body, at: clock.now)
    }

    // MARK: Storing (FR-6, FR-8)

    @Test func storesANotification() throws {
        let notification = TestSupport.notification(app: "Messages", body: "Hello", at: clock.now - 5)

        let outcome = try service.capture(notification)

        guard case .stored(let entry) = outcome else {
            Issue.record("Expected .stored, got \(outcome)")
            return
        }
        #expect(entry.appKey == AppKey(appName: "Messages"))
        #expect(entry.receivedAt == clock.now - 5)
        #expect(entry.capturedAt == clock.now)
        #expect(try store.entry(id: entry.id) == entry)
        #expect(try store.trackedApps().map(\.key) == [AppKey(appName: "Messages")])
    }

    @Test func aRepeatWithinAMinuteIsADuplicate() throws {
        let notification = TestSupport.notification(body: "Hello", at: clock.now)
        let first = try service.capture(notification)
        clock.advance(by: 20)
        var repeated = notification
        repeated.receivedAt = clock.now

        #expect(try service.capture(repeated) == CaptureOutcome.duplicate)
        if case .stored = first {} else { Issue.record("Expected the first capture to be stored, got \(first)") }
        #expect(try store.entryCount(filter: .all) == 1)
    }

    // MARK: Paused (FR-18)

    @Test func pausedLoggingDropsEverything() throws {
        settings.isLoggingPaused = true
        settings.testNotificationExpectedUntil = clock.now + 60

        #expect(try service.capture(TestSupport.notification(at: clock.now)) == CaptureOutcome.paused)
        #expect(try service.capture(ownNotification()) == CaptureOutcome.paused)
        #expect(try store.entryCount(filter: .all) == 0)
        #expect(try store.trackedApps().isEmpty)
        #expect(settings.lastRetentionRunAt == nil)
    }

    // MARK: Own notifications (FR-5)

    @Test func ownNotificationsAreIgnoredUnlessATestIsExpected() throws {
        #expect(try service.capture(ownNotification()) == CaptureOutcome.ignoredOwnNotification)

        // An expectation that has run out doesn't count either.
        settings.testNotificationExpectedUntil = clock.now - 1
        #expect(try service.capture(ownNotification(body: "Snoozed")) == CaptureOutcome.ignoredOwnNotification)

        #expect(try store.entryCount(filter: .all) == 0)
        #expect(try store.trackedApps().isEmpty)
        #expect(settings.lastTestCaptureAt == nil)
    }

    @Test func expectedTestNotificationIsStoredButNotTracked() throws {
        settings.testNotificationExpectedUntil = clock.now + CaptureService.testNotificationWindow
        clock.advance(by: 10)

        let outcome = try service.capture(ownNotification())

        guard case .stored(let entry) = outcome else {
            Issue.record("Expected .stored, got \(outcome)")
            return
        }
        #expect(entry.appKey == AppKey.ownApp)
        #expect(settings.lastTestCaptureAt == clock.now)
        #expect(settings.testNotificationExpectedUntil == nil)
        #expect(try store.trackedApps().isEmpty)
        #expect(try store.entry(id: entry.id) == entry)

        // Only the one test: the next own notification is a snooze coming back.
        clock.advance(by: 10)
        #expect(try service.capture(ownNotification(body: "Snoozed")) == CaptureOutcome.ignoredOwnNotification)
    }

    @Test func testNotificationIsStoredWhenTheFreeTierIsFull() throws {
        for app in ["One", "Two", "Three"] {
            _ = try service.capture(TestSupport.notification(app: app, at: clock.now))
            clock.advance(by: 1)
        }
        settings.testNotificationExpectedUntil = clock.now + CaptureService.testNotificationWindow

        let test = try service.capture(ownNotification())
        if case .stored = test {} else {
            Issue.record("The test notification should not take or need a free-tier slot, got \(test)")
        }
        #expect(try service.capture(TestSupport.notification(app: "Four", at: clock.now)) == CaptureOutcome.blockedByAppLimit)
        #expect(try store.trackedApps().map(\.displayName) == ["One", "Two", "Three", "Four"])
    }

    // MARK: Free tier (Monetization)

    @Test func freeTierLogsOnlyTheFirstThreeApps() throws {
        for app in ["One", "Two", "Three"] {
            let outcome = try service.capture(TestSupport.notification(app: app, at: clock.now))
            if case .stored = outcome {} else { Issue.record("\(app) should be stored, got \(outcome)") }
            clock.advance(by: 1)
        }

        #expect(try service.capture(TestSupport.notification(app: "Four", body: "a", at: clock.now)) == CaptureOutcome.blockedByAppLimit)
        clock.advance(by: 1)
        #expect(try service.capture(TestSupport.notification(app: "four", body: "b", at: clock.now)) == CaptureOutcome.blockedByAppLimit)

        let tracked = try store.trackedApps()
        let four = try #require(tracked.first(where: { $0.key == AppKey(appName: "Four") }))
        #expect(four.blockedCount == 2)
        #expect(four.entryCount == 0)
        #expect(try store.entryCount(filter: HistoryFilter(apps: [AppKey(appName: "Four")])) == 0)

        // The first three keep logging.
        let outcome = try service.capture(TestSupport.notification(app: "Two", body: "again", at: clock.now))
        if case .stored = outcome {} else { Issue.record("Two should still be stored, got \(outcome)") }

        // Pro lifts the limit.
        settings.isPro = true
        let pro = try service.capture(TestSupport.notification(app: "Four", body: "c", at: clock.now))
        if case .stored = pro {} else { Issue.record("Pro should store every app, got \(pro)") }
    }

    // MARK: Retention (FR-12)

    private func expiredCount() throws -> Int {
        let cutoff = clock.now - 8 * day
        return try store.entryCount(filter: HistoryFilter(dateRange: DateInterval(start: .distantPast, end: cutoff)))
    }

    @Test func retentionRunsAtMostOncePerDay() throws {
        let firstRun = clock.now
        // Free tier: 30 days is capped to 7.
        settings.retention = .thirtyDays
        try TestSupport.insert(TestSupport.notification(body: "old 1", at: firstRun - 10 * day), into: store)

        _ = try service.capture(TestSupport.notification(body: "new 1", at: clock.now))
        #expect(settings.lastRetentionRunAt == firstRun)
        #expect(try expiredCount() == 0)

        // An hour later another expired entry is left for the next run.
        try TestSupport.insert(TestSupport.notification(body: "old 2", at: firstRun - 10 * day), into: store)
        clock.advance(by: 3_600)
        _ = try service.capture(TestSupport.notification(body: "new 2", at: clock.now))
        #expect(settings.lastRetentionRunAt == firstRun)
        #expect(try expiredCount() == 1)

        // 24 hours after the last run, it runs again.
        clock.set(firstRun + CaptureService.retentionInterval)
        _ = try service.capture(TestSupport.notification(body: "new 3", at: clock.now))
        #expect(settings.lastRetentionRunAt == clock.now)
        #expect(try expiredCount() == 0)
        #expect(try store.entryCount(filter: .all) == 3)
    }

    @Test func retentionRunsWhenTheLastRunIsInTheFuture() throws {
        settings.lastRetentionRunAt = clock.now + 2 * day
        try TestSupport.insert(TestSupport.notification(body: "old", at: clock.now - 10 * day), into: store)

        _ = try service.capture(TestSupport.notification(body: "new", at: clock.now))

        #expect(settings.lastRetentionRunAt == clock.now)
        #expect(try expiredCount() == 0)
    }

    @Test func retentionKeepsHistoryForProUsersWhoChoseLonger() throws {
        settings.isPro = true
        settings.retention = .ninetyDays
        try TestSupport.insert(TestSupport.notification(body: "old", at: clock.now - 10 * day), into: store)

        _ = try service.capture(TestSupport.notification(body: "new", at: clock.now))

        #expect(settings.lastRetentionRunAt == clock.now)
        #expect(try expiredCount() == 1)
    }

    @Test func retentionFailureDoesNotFailTheCapture() throws {
        let failing = RetentionFailingStore(base: store)
        let clock = self.clock
        let service = CaptureService(store: failing, settings: settings, now: { clock.now })

        let outcome = try service.capture(TestSupport.notification(body: "new", at: clock.now))

        if case .stored = outcome {} else { Issue.record("Expected .stored, got \(outcome)") }
        // Not recorded as run, so the next capture tries again.
        #expect(settings.lastRetentionRunAt == nil)
    }

    @Test func ignoredCapturesDontRunRetention() throws {
        _ = try service.capture(ownNotification())
        #expect(settings.lastRetentionRunAt == nil)
    }
}

/// Forwards to a real store but fails every retention run.
private final class RetentionFailingStore: NotificationStoring {
    let base: SQLiteNotificationStore

    init(base: SQLiteNotificationStore) {
        self.base = base
    }

    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> DeletionResult {
        throw StoreError.unavailable
    }

    func insert(_ notification: NewNotification, capturedAt: Date, dedupeWindow: TimeInterval) throws -> InsertOutcome {
        try base.insert(notification, capturedAt: capturedAt, dedupeWindow: dedupeWindow)
    }

    func entries(_ query: HistoryQuery) throws -> [NotificationEntry] { try base.entries(query) }
    func entry(id: NotificationEntry.ID) throws -> NotificationEntry? { try base.entry(id: id) }
    func entryCount(filter: HistoryFilter) throws -> Int { try base.entryCount(filter: filter) }
    func trackedApps() throws -> [TrackedApp] { try base.trackedApps() }

    @discardableResult
    func registerApp(displayName: String, catalogID: String?, at date: Date) throws -> TrackedApp {
        try base.registerApp(displayName: displayName, catalogID: catalogID, at: date)
    }

    func removeApp(_ key: AppKey) throws { try base.removeApp(key) }
    func recordBlockedCapture(_ notification: NewNotification, at date: Date) throws {
        try base.recordBlockedCapture(notification, at: date)
    }

    func deleteEntry(id: NotificationEntry.ID) throws -> DeletionResult { try base.deleteEntry(id: id) }
    func deleteEntries(app: AppKey) throws -> DeletionResult { try base.deleteEntries(app: app) }
    func deleteAll() throws -> DeletionResult { try base.deleteAll() }

    func dailyCounts(in interval: DateInterval, calendar: Calendar) throws -> [DailyAppCount] {
        try base.dailyCounts(in: interval, calendar: calendar)
    }

    func addSnooze(entryID: NotificationEntry.ID, fireAt: Date, createdAt: Date) throws -> SnoozeRecord {
        try base.addSnooze(entryID: entryID, fireAt: fireAt, createdAt: createdAt)
    }

    func pendingSnoozes(after date: Date) throws -> [SnoozeRecord] { try base.pendingSnoozes(after: date) }
    func rescheduleSnooze(id: SnoozeRecord.ID, fireAt: Date) throws -> SnoozeRecord {
        try base.rescheduleSnooze(id: id, fireAt: fireAt)
    }

    func removeSnooze(id: SnoozeRecord.ID) throws { try base.removeSnooze(id: id) }

    @discardableResult
    func removeSnoozes(firedBefore date: Date) throws -> Int { try base.removeSnoozes(firedBefore: date) }
}
