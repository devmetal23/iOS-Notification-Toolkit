import Foundation
import Testing
import ToolkitCore

@Suite("Store: capture and timeline")
struct StoreEntryTests {
    let store: SQLiteNotificationStore
    let start = TestSupport.referenceDate

    init() throws {
        store = try SQLiteNotificationStore.inMemory()
    }

    // MARK: Round trip (FR-6)

    @Test func insertedEntryRoundTripsExactly() throws {
        let received = start.addingTimeInterval(0.123_456_789)
        let captured = received.addingTimeInterval(1.5)
        let notification = NewNotification(
            appName: " WhatsApp ",
            title: "Sam 👋",
            subtitle: "Family — Crème brûlée",
            body: "Line one\nLine two\u{0}after a NUL",
            receivedAt: received,
            isTimeSensitive: true
        )
        let outcome = try store.insert(notification, capturedAt: captured, dedupeWindow: CaptureService.dedupeWindow)
        guard case .inserted(let entry) = outcome else {
            Issue.record("Expected an insert, got \(outcome)")
            return
        }
        #expect(entry.appKey == AppKey(rawValue: "whatsapp"))
        #expect(entry.appName == " WhatsApp ")
        #expect(entry.title == "Sam 👋")
        #expect(entry.subtitle == "Family — Crème brûlée")
        #expect(entry.body == "Line one\nLine two\u{0}after a NUL")
        #expect(entry.receivedAt == received)
        #expect(entry.capturedAt == captured)
        #expect(entry.isTimeSensitive)

        #expect(try store.entry(id: entry.id) == entry)
        #expect(try store.entries(HistoryQuery()) == [entry])
        #expect(try store.entry(id: entry.id + 1) == nil)
    }

    @Test func emptyFieldsAreStoredAsEmptyStrings() throws {
        let entry = try TestSupport.insert(
            NewNotification(appName: "Mail", receivedAt: start),
            into: store
        )
        let stored = try #require(try store.entry(id: entry.id))
        #expect(stored.title.isEmpty && stored.subtitle.isEmpty && stored.body.isEmpty)
        #expect(stored == entry)
    }

    // MARK: Dedupe (FR-8)

    @Test func sameAppTitleAndBodyWithinAMinuteIsStoredOnce() throws {
        let first = try TestSupport.insert(TestSupport.notification(at: start), into: store)

        // Same app under a different spelling, 30 s later.
        let later = try store.insert(
            TestSupport.notification(app: "messages ", at: start + 30),
            capturedAt: start + 31,
            dedupeWindow: CaptureService.dedupeWindow
        )
        #expect(later == InsertOutcome.duplicate(of: first.id))

        // The window applies both ways: captures can arrive out of order.
        let earlier = try store.insert(
            TestSupport.notification(at: start - 59),
            capturedAt: start + 32,
            dedupeWindow: CaptureService.dedupeWindow
        )
        #expect(earlier == InsertOutcome.duplicate(of: first.id))

        // Exactly at the window's edge still counts as within it.
        let edge = try store.insert(
            TestSupport.notification(at: start + 60),
            capturedAt: start + 60,
            dedupeWindow: CaptureService.dedupeWindow
        )
        #expect(edge == InsertOutcome.duplicate(of: first.id))

        // The subtitle isn't part of the identity.
        let otherSubtitle = try store.insert(
            TestSupport.notification(subtitle: "Group", at: start + 5),
            capturedAt: start + 5,
            dedupeWindow: CaptureService.dedupeWindow
        )
        #expect(otherSubtitle == InsertOutcome.duplicate(of: first.id))

        #expect(try store.entryCount(filter: .all) == 1)
    }

    @Test func outsideTheWindowOrDifferentContentIsStored() throws {
        try TestSupport.insert(TestSupport.notification(at: start), into: store)
        let candidates = [
            TestSupport.notification(at: start + 61),
            TestSupport.notification(at: start - 61),
            TestSupport.notification(body: "See you soon!", at: start + 1),
            TestSupport.notification(title: "Ana", at: start + 1),
            TestSupport.notification(app: "Signal", at: start + 1),
        ]
        for candidate in candidates {
            let outcome = try store.insert(candidate, capturedAt: start + 2, dedupeWindow: CaptureService.dedupeWindow)
            #expect(TestSupport.isInserted(outcome), "\(candidate) should be stored")
        }
        #expect(try store.entryCount(filter: .all) == 1 + candidates.count)
    }

    @Test func zeroWindowOnlyDedupesTheSameInstant() throws {
        try TestSupport.insert(TestSupport.notification(at: start), into: store)
        let sameInstant = try store.insert(TestSupport.notification(at: start), capturedAt: start, dedupeWindow: 0)
        let oneSecondLater = try store.insert(TestSupport.notification(at: start + 1), capturedAt: start, dedupeWindow: 0)
        #expect(!TestSupport.isInserted(sameInstant))
        #expect(TestSupport.isInserted(oneSecondLater))
    }

    // MARK: Timeline and filters (FR-9)

    @Test func timelineIsNewestFirstWithTiesByNewestID() throws {
        let middle = try TestSupport.insert(TestSupport.notification(body: "b", at: start + 100), into: store)
        let oldest = try TestSupport.insert(TestSupport.notification(body: "a", at: start), into: store)
        let newest = try TestSupport.insert(TestSupport.notification(body: "c", at: start + 200), into: store)
        let tiedLater = try TestSupport.insert(TestSupport.notification(body: "d", at: start + 100), into: store)

        #expect(try store.entries(HistoryQuery()) == [newest, tiedLater, middle, oldest])
        #expect(try store.entries(HistoryQuery(limit: 2)) == [newest, tiedLater])
        #expect(try store.entries(HistoryQuery(limit: 0)).isEmpty)
        #expect(try store.entries(HistoryQuery(limit: -1)).isEmpty)
    }

    @Test func filtersByAppDateRangeAndTimeSensitivity() throws {
        let messages1 = try TestSupport.insert(TestSupport.notification(app: "Messages", body: "1", at: start), into: store)
        let slack = try TestSupport.insert(TestSupport.notification(app: "Slack", body: "2", at: start + 10, timeSensitive: true), into: store)
        let mail = try TestSupport.insert(TestSupport.notification(app: "Mail", body: "3", at: start + 20), into: store)
        let messages2 = try TestSupport.insert(TestSupport.notification(app: "Messages", body: "4", at: start + 30), into: store)

        let messagesOnly = HistoryFilter(apps: [AppKey(appName: "Messages")])
        #expect(try store.entries(HistoryQuery(filter: messagesOnly)) == [messages2, messages1])
        #expect(try store.entryCount(filter: messagesOnly) == 2)

        let twoApps = HistoryFilter(apps: [AppKey(appName: "Messages"), AppKey(appName: "Slack")])
        #expect(try store.entries(HistoryQuery(filter: twoApps)) == [messages2, slack, messages1])

        // The range is inclusive at both ends.
        let range = HistoryFilter(dateRange: DateInterval(start: start + 10, end: start + 20))
        #expect(try store.entries(HistoryQuery(filter: range)) == [mail, slack])
        #expect(try store.entryCount(filter: range) == 2)

        let urgent = HistoryFilter(timeSensitiveOnly: true)
        #expect(try store.entries(HistoryQuery(filter: urgent)) == [slack])
        #expect(try store.entryCount(filter: urgent) == 1)

        let combined = HistoryFilter(apps: [AppKey(appName: "Messages")], dateRange: DateInterval(start: start + 5, end: start + 60))
        #expect(try store.entries(HistoryQuery(filter: combined)) == [messages2])

        let unknownApp = HistoryFilter(apps: [AppKey(appName: "Nope")])
        #expect(try store.entries(HistoryQuery(filter: unknownApp)).isEmpty)
        #expect(try store.entryCount(filter: unknownApp) == 0)
        #expect(try store.entryCount(filter: .all) == 4)
    }

    // MARK: Pagination

    @Test func keysetPagesAreStableAcrossTiesAndNewInserts() throws {
        var expected: [NotificationEntry] = []
        for index in 0..<60 {
            // Four entries share each received time, so pages split ties.
            let receivedAt = start.addingTimeInterval(Double(index / 4) * 300)
            let notification = TestSupport.notification(title: "N\(index)", body: "Body \(index)", at: receivedAt)
            expected.append(try TestSupport.insert(notification, into: store))
        }
        expected.sort { ($0.receivedAt, $0.id) > ($1.receivedAt, $1.id) }

        var collected: [NotificationEntry] = []
        var cursor: HistoryCursor?
        while true {
            let page = try store.entries(HistoryQuery(limit: 7, cursor: cursor))
            guard let last = page.last else { break }
            collected += page
            cursor = HistoryCursor(after: last)
            if collected.count == 21 {
                // A capture arriving mid-scroll lands above the pages already read.
                try TestSupport.insert(TestSupport.notification(title: "Newest", at: start + 1_000_000), into: store)
            }
        }
        #expect(collected == expected)
    }

    @Test func searchResultsPageWithTheSameCursor() throws {
        for index in 0..<30 {
            let app = index.isMultiple(of: 2) ? "Messages" : "Slack"
            try TestSupport.insert(
                TestSupport.notification(app: app, body: "Delivery update \(index)", at: start.addingTimeInterval(Double(index / 3) * 120)),
                into: store
            )
        }
        let filter = HistoryFilter(apps: [AppKey(appName: "Messages")])
        let all = try store.entries(HistoryQuery(filter: filter, searchText: "deliv", limit: 100))
        #expect(all.count == 15)

        var collected: [NotificationEntry] = []
        var cursor: HistoryCursor?
        while true {
            let page = try store.entries(HistoryQuery(filter: filter, searchText: "deliv", limit: 4, cursor: cursor))
            guard let last = page.last else { break }
            collected += page
            cursor = HistoryCursor(after: last)
        }
        #expect(collected == all)
    }
}
