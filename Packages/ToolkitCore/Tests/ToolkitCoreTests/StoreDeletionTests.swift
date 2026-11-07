import Foundation
import Testing
import ToolkitCore

@Suite("Store: deleting and retention")
struct StoreDeletionTests {
    let store: SQLiteNotificationStore
    let start = TestSupport.referenceDate
    let day = TestSupport.day

    init() throws {
        store = try SQLiteNotificationStore.inMemory()
    }

    private func allIDs() throws -> Set<NotificationEntry.ID> {
        Set(try store.entries(HistoryQuery(limit: 1_000)).map(\.id))
    }

    // MARK: Deleting (FR-13)

    @Test func deletingOneEntryReturnsItsSnoozes() throws {
        let target = try TestSupport.insert(TestSupport.notification(body: "target", at: start), into: store)
        let other = try TestSupport.insert(TestSupport.notification(body: "other", at: start + 1), into: store)
        let first = try store.addSnooze(entryID: target.id, fireAt: start + 900, createdAt: start)
        let second = try store.addSnooze(entryID: target.id, fireAt: start + 3_600, createdAt: start)
        let untouched = try store.addSnooze(entryID: other.id, fireAt: start + 900, createdAt: start)

        let result = try store.deleteEntry(id: target.id)

        #expect(result == DeletionResult(
            entriesDeleted: 1,
            cancelledSnoozeRequestIdentifiers: [first.requestIdentifier, second.requestIdentifier]
        ))
        #expect(try store.entry(id: target.id) == nil)
        #expect(try store.pendingSnoozes(after: .distantPast) == [untouched])
        // Deleting it again is a no-op, not an error.
        #expect(try store.deleteEntry(id: target.id) == DeletionResult())
    }

    @Test func deletingAnAppsEntriesLeavesOtherApps() throws {
        let messages = try TestSupport.insert(TestSupport.notification(app: "Messages", body: "a", at: start), into: store)
        try TestSupport.insert(TestSupport.notification(app: "Messages", body: "b", at: start + 1), into: store)
        let slack = try TestSupport.insert(TestSupport.notification(app: "Slack", body: "c", at: start + 2), into: store)
        let messagesSnooze = try store.addSnooze(entryID: messages.id, fireAt: start + 900, createdAt: start)
        let slackSnooze = try store.addSnooze(entryID: slack.id, fireAt: start + 900, createdAt: start)

        let result = try store.deleteEntries(app: AppKey(appName: "Messages"))

        #expect(result == DeletionResult(entriesDeleted: 2, cancelledSnoozeRequestIdentifiers: [messagesSnooze.requestIdentifier]))
        #expect(try allIDs() == Set([slack.id]))
        #expect(try store.pendingSnoozes(after: .distantPast) == [slackSnooze])
        // The app stays set up; only its history is gone.
        #expect(try store.trackedApps().map(\.key).contains(AppKey(appName: "Messages")))
    }

    @Test func deletingAllKeepsTrackedAppsAndNeverReusesIDs() throws {
        let one = try TestSupport.insert(TestSupport.notification(app: "Messages", body: "a", at: start), into: store)
        let two = try TestSupport.insert(TestSupport.notification(app: "Slack", body: "b", at: start + 1), into: store)
        let firstSnooze = try store.addSnooze(entryID: one.id, fireAt: start + 900, createdAt: start)
        let secondSnooze = try store.addSnooze(entryID: two.id, fireAt: start + 900, createdAt: start)

        let result = try store.deleteAll()

        #expect(result == DeletionResult(
            entriesDeleted: 2,
            cancelledSnoozeRequestIdentifiers: [firstSnooze.requestIdentifier, secondSnooze.requestIdentifier]
        ))
        #expect(try store.entryCount(filter: .all) == 0)
        #expect(try store.pendingSnoozes(after: .distantPast).isEmpty)
        #expect(try store.trackedApps().count == 2)
        #expect(try store.entries(HistoryQuery(searchText: "a")).isEmpty)

        // A pending notification request named after an old snooze must never be
        // mistaken for a new one.
        let entry = try TestSupport.insert(TestSupport.notification(body: "after", at: start + 2), into: store)
        let snooze = try store.addSnooze(entryID: entry.id, fireAt: start + 900, createdAt: start)
        #expect(entry.id > two.id)
        #expect(snooze.id > secondSnooze.id)
        #expect(try store.deleteAll() == DeletionResult(entriesDeleted: 1, cancelledSnoozeRequestIdentifiers: [snooze.requestIdentifier]))
        #expect(try store.deleteAll() == DeletionResult())
    }

    // MARK: Retention (FR-12)

    @Test func retentionKeepsEntriesWithPendingSnoozesUntilTheyFire() throws {
        let now = start
        let old = try TestSupport.insert(TestSupport.notification(body: "old", at: now - 10 * day), into: store)
        let oldPending = try TestSupport.insert(TestSupport.notification(body: "old pending", at: now - 10 * day), into: store)
        let oldFired = try TestSupport.insert(TestSupport.notification(body: "old fired", at: now - 10 * day), into: store)
        let atCutoff = try TestSupport.insert(TestSupport.notification(body: "at cutoff", at: now - 7 * day), into: store)
        let recent = try TestSupport.insert(TestSupport.notification(body: "recent", at: now - day), into: store)
        let pending = try store.addSnooze(entryID: oldPending.id, fireAt: now + 3_600, createdAt: now - day)
        let fired = try store.addSnooze(entryID: oldFired.id, fireAt: now - 3_600, createdAt: now - day)

        let result = try store.applyRetention(.sevenDays, now: now)

        #expect(result == DeletionResult(entriesDeleted: 2, cancelledSnoozeRequestIdentifiers: [fired.requestIdentifier]))
        #expect(try allIDs() == Set([oldPending.id, atCutoff.id, recent.id]))
        #expect(try store.entry(id: old.id) == nil)

        // Two hours later the snooze has fired, so its entry expires with the next
        // run, as does the entry that was exactly at the earlier cutoff.
        let later = try store.applyRetention(.sevenDays, now: now + 7_200)
        #expect(later == DeletionResult(entriesDeleted: 2, cancelledSnoozeRequestIdentifiers: [pending.requestIdentifier]))
        #expect(try allIDs() == Set([recent.id]))
        #expect(try store.entries(HistoryQuery(searchText: "old")).isEmpty)
    }

    @Test(arguments: [RetentionPolicy.sevenDays, .thirtyDays, .ninetyDays])
    func retentionDeletesOnlyEntriesPastThePolicy(_ policy: RetentionPolicy) throws {
        let days = try #require(policy.days)
        let now = start
        try TestSupport.insert(TestSupport.notification(body: "expired", at: now - Double(days) * day - 1), into: store)
        let kept = try TestSupport.insert(TestSupport.notification(body: "kept", at: now - Double(days) * day + 1), into: store)

        let result = try store.applyRetention(policy, now: now)

        #expect(result.entriesDeleted == 1)
        #expect(try allIDs() == Set([kept.id]))
    }

    @Test func foreverRetentionDeletesNothing() throws {
        try TestSupport.insert(TestSupport.notification(body: "ancient", at: start - 3_650 * day), into: store)
        #expect(try store.applyRetention(.forever, now: start) == DeletionResult())
        #expect(try store.entryCount(filter: .all) == 1)
    }
}
