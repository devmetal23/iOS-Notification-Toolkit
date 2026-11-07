import Foundation
import Testing
import ToolkitCore

@Suite("Store: file-backed database")
struct StoreFileTests {
    let start = TestSupport.referenceDate

    @Test func reopeningKeepsEverythingAndCreatesTheDirectory() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("Library/Application Support/NotificationToolkit/History.sqlite")

        let entry: NotificationEntry
        let snooze: SnoozeRecord
        let app: TrackedApp
        do {
            let store = try SQLiteNotificationStore(url: url)
            entry = try TestSupport.insert(TestSupport.notification(body: "Unforgettable", at: start), into: store)
            snooze = try store.addSnooze(entryID: entry.id, fireAt: start + 900, createdAt: start)
            app = try store.registerApp(displayName: "Bank", catalogID: "bank", at: start)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reopened = try SQLiteNotificationStore(url: url)
        #expect(try reopened.entry(id: entry.id) == entry)
        #expect(try reopened.pendingSnoozes(after: start) == [snooze])
        #expect(try reopened.trackedApps().contains(app))
        #expect(try reopened.entries(HistoryQuery(searchText: "unforget")).map(\.id) == [entry.id])

        // Opening an up-to-date database again doesn't rerun migrations.
        let third = try SQLiteNotificationStore(url: url)
        #expect(try third.entryCount(filter: .all) == 1)
    }

    @Test func connectionsSeeEachOthersWrites() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        let app = try SQLiteNotificationStore(url: url)
        let intent = try SQLiteNotificationStore(url: url)

        let entry = try TestSupport.insert(TestSupport.notification(at: start), into: intent)
        #expect(try app.entries(HistoryQuery()) == [entry])

        _ = try app.deleteAll()
        #expect(try intent.entryCount(filter: .all) == 0)
    }

    @Test func readOnlyStoreReadsButCannotWrite() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        let first: NotificationEntry
        do {
            let writer = try SQLiteNotificationStore(url: url)
            first = try TestSupport.insert(TestSupport.notification(body: "one", at: start), into: writer)
        }

        // Opened after the writer closed, when the WAL and shm files are gone.
        let reader = try SQLiteNotificationStore(url: url, options: .init(readOnly: true))
        #expect(try reader.entries(HistoryQuery()) == [first])
        #expect(throws: StoreError.self) {
            try reader.insert(TestSupport.notification(body: "two", at: start + 1), capturedAt: start, dedupeWindow: 60)
        }

        let writer = try SQLiteNotificationStore(url: url)
        let second = try TestSupport.insert(TestSupport.notification(body: "three", at: start + 2), into: writer)
        #expect(try reader.entries(HistoryQuery()) == [second, first])
    }

    @Test func readOnlyStoreWithoutADatabaseIsUnavailable() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("Missing/History.sqlite")

        #expect(throws: StoreError.unavailable) {
            try SQLiteNotificationStore(url: url, options: .init(readOnly: true))
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unusableLocationIsUnavailable() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        // The database's folder would have to be created where a file already is.
        let blocker = directory.appendingPathComponent("blocker")
        try Data("not a folder".utf8).write(to: blocker)

        #expect(throws: StoreError.unavailable) {
            try SQLiteNotificationStore(url: blocker.appendingPathComponent("History.sqlite"))
        }
    }

    @Test func fileThatIsNotADatabaseThrows() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        try Data(String(repeating: "This is not an SQLite database. ", count: 64).utf8).write(to: url)

        #expect(throws: StoreError.self) {
            try SQLiteNotificationStore(url: url)
        }
    }

    @Test func closedConnectionReopensOnTheNextCall() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let store = try SQLiteNotificationStore(url: directory.appendingPathComponent("History.sqlite"))
        let entry = try TestSupport.insert(TestSupport.notification(body: "one", at: start), into: store)

        store.closeConnection()
        #expect(try store.entry(id: entry.id) == entry)

        store.closeConnection()
        store.closeConnection()
        try TestSupport.insert(TestSupport.notification(body: "two", at: start + 1), into: store)
        #expect(try store.entryCount(filter: .all) == 2)
    }

    @Test func inMemoryStoresAreSeparateAndSurviveClosing() throws {
        let first = try SQLiteNotificationStore.inMemory()
        let second = try SQLiteNotificationStore.inMemory()
        let entry = try TestSupport.insert(TestSupport.notification(at: start), into: first)

        first.closeConnection()

        #expect(try first.entries(HistoryQuery()) == [entry])
        #expect(try second.entries(HistoryQuery()).isEmpty)
    }

    /// Several threads on one store, and two stores on one file standing in for the
    /// app and an intent running in different processes.
    @Test func concurrentInsertsAreAllStored() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        let stores = try [SQLiteNotificationStore(url: url), SQLiteNotificationStore(url: url)]
        let start = self.start
        let workers = 8
        let insertsPerWorker = 40

        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0..<workers {
                let store = stores[worker % stores.count]
                group.addTask {
                    for index in 0..<insertsPerWorker {
                        let notification = TestSupport.notification(
                            app: "App \(worker % 4)",
                            body: "worker \(worker) item \(index)",
                            at: start.addingTimeInterval(Double(index))
                        )
                        let outcome = try store.insert(notification, capturedAt: start, dedupeWindow: CaptureService.dedupeWindow)
                        guard TestSupport.isInserted(outcome) else {
                            throw TestSupport.Failure("Unexpected duplicate: \(notification)")
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(try stores[0].entryCount(filter: .all) == workers * insertsPerWorker)
        #expect(try stores[1].trackedApps().map(\.entryCount) == Array(repeating: workers * insertsPerWorker / 4, count: 4))
        // Every row reached the full-text index too.
        #expect(try stores[1].entries(HistoryQuery(searchText: "item", limit: 1_000)).count == workers * insertsPerWorker)
    }
}
