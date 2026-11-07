import Foundation
import Testing
import ToolkitCore

@Suite("Store: snoozes")
struct StoreSnoozeTests {
    let store: SQLiteNotificationStore
    let start = TestSupport.referenceDate

    init() throws {
        store = try SQLiteNotificationStore.inMemory()
    }

    @Test func snoozeLifecycle() throws {
        let entry = try TestSupport.insert(TestSupport.notification(body: "first", at: start), into: store)
        let other = try TestSupport.insert(TestSupport.notification(body: "second", at: start + 1), into: store)

        let late = try store.addSnooze(entryID: entry.id, fireAt: start + 3_600, createdAt: start)
        let soon = try store.addSnooze(entryID: other.id, fireAt: start + 900, createdAt: start + 1)
        #expect(late.entry == entry)
        #expect(late.fireAt == start + 3_600)
        #expect(late.createdAt == start)
        #expect(late.requestIdentifier == "snooze-\(late.id)")
        #expect(soon.id > late.id)

        // Soonest first, and strictly after the given date.
        #expect(try store.pendingSnoozes(after: start) == [soon, late])
        #expect(try store.pendingSnoozes(after: start + 900) == [late])

        let moved = try store.rescheduleSnooze(id: late.id, fireAt: start + 600)
        #expect(moved == SnoozeRecord(id: late.id, entry: entry, fireAt: start + 600, createdAt: start))
        #expect(moved.requestIdentifier == late.requestIdentifier)
        #expect(try store.pendingSnoozes(after: start) == [moved, soon])

        try store.removeSnooze(id: soon.id)
        try store.removeSnooze(id: soon.id)
        #expect(try store.pendingSnoozes(after: start) == [moved])

        // Fired means at or before the date: nothing is left in between.
        #expect(try store.removeSnoozes(firedBefore: start + 599) == 0)
        #expect(try store.removeSnoozes(firedBefore: start + 600) == 1)
        #expect(try store.pendingSnoozes(after: .distantPast).isEmpty)
    }

    @Test func missingRecordsThrowNotFound() throws {
        #expect(throws: StoreError.notFound) {
            try store.addSnooze(entryID: 42, fireAt: start, createdAt: start)
        }
        #expect(throws: StoreError.notFound) {
            try store.rescheduleSnooze(id: 42, fireAt: start)
        }
    }

    @Test func snoozesGoWithTheirEntry() throws {
        let entry = try TestSupport.insert(TestSupport.notification(at: start), into: store)
        let snooze = try store.addSnooze(entryID: entry.id, fireAt: start + 900, createdAt: start)
        _ = try store.deleteEntry(id: entry.id)

        #expect(try store.pendingSnoozes(after: .distantPast).isEmpty)
        #expect(throws: StoreError.notFound) {
            try store.rescheduleSnooze(id: snooze.id, fireAt: start + 1_800)
        }
    }
}
