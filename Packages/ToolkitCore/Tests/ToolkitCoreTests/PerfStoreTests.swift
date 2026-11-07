import Foundation
import Testing
import ToolkitCore

/// NFR-5 (search under 300 ms at 50,000 entries on an iPhone 11) and NFR-6
/// (under 100 MB at 50,000 entries). The time bounds here are deliberately loose,
/// a guard against regressions such as a query plan that runs FTS once per row,
/// not a device measurement. Set SKIP_PERF_TESTS=1 to skip locally.
@Suite("Store performance", .serialized)
struct PerfStoreTests {
    let entryCount = 50_000
    /// One notification every two minutes: 720 a day, about 70 days in all.
    let spacing: TimeInterval = 120

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SKIP_PERF_TESTS"] == nil))
    func fiftyThousandEntriesStaySmallAndSearchFast() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeDirectory(directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        let store = try SQLiteNotificationStore(url: url)
        let clock = ContinuousClock()
        let start = TestSupport.referenceDate

        var random = TestSupport.SeededGenerator(seed: 2026)
        let vocabulary = perfVocabulary(using: &random)
        var notifications: [NewNotification] = []
        notifications.reserveCapacity(entryCount)
        for index in 0..<entryCount {
            let app = perfApps[Int.random(in: 0..<perfApps.count, using: &random)]
            let titleLength = Int.random(in: 1...4, using: &random)
            let title = perfWords(titleLength, from: vocabulary, using: &random)
            let subtitle = index % 3 == 0 ? perfWords(2, from: vocabulary, using: &random) : ""
            let bodyLength = Int.random(in: 6...30, using: &random)
            var body = perfWords(bodyLength, from: vocabulary, using: &random)
            if index % 10 == 0 { body += " https://example.com/track/\(index)" }
            if index % 10 == 5 { body += " Your code is \(100_000 + index)" }
            notifications.append(NewNotification(
                appName: app,
                title: title,
                subtitle: subtitle,
                body: body,
                receivedAt: start.addingTimeInterval(Double(index) * spacing),
                isTimeSensitive: index % 20 == 0
            ))
        }

        // Each insert is its own transaction, as captures are.
        let insertDuration = try clock.measure {
            for notification in notifications {
                _ = try store.insert(notification, capturedAt: notification.receivedAt, dedupeWindow: CaptureService.dedupeWindow)
            }
        }
        #expect(try store.entryCount(filter: .all) == entryCount)

        let bytes = TestSupport.databaseSize(at: url)
        #expect(bytes < 100_000_000, "The database and its WAL take \(bytes) bytes")

        let messages = HistoryFilter(apps: [AppKey(appName: "Messages")])
        let lastMonth = DateInterval(
            start: start.addingTimeInterval(Double(entryCount) * spacing - 30 * TestSupport.day),
            end: start.addingTimeInterval(Double(entryCount) * spacing)
        )
        let searches: [(text: String, filter: HistoryFilter)] = [
            ("the", .all),
            ("a", .all),
            ("code deliv", .all),
            ("you order today", .all),
            (vocabulary[vocabulary.count / 2], .all),
            ("zzzzzz", .all),
            ("the", messages),
            ("a", messages),
            ("a", HistoryFilter(dateRange: lastMonth)),
        ]
        let limit = Duration.seconds(1)
        var report: [String] = []
        for search in searches {
            var results: [NotificationEntry] = []
            let elapsed = try clock.measure {
                results = try store.entries(HistoryQuery(filter: search.filter, searchText: search.text, limit: 100))
            }
            let newestFirst = results.sorted(by: { ($0.receivedAt, $0.id) > ($1.receivedAt, $1.id) })
            #expect(elapsed < limit, "Searching \"\(search.text)\" took \(elapsed)")
            #expect(results.count <= 100)
            #expect(results == newestFirst)
            report.append("\"\(search.text)\" \(results.count) in \(elapsed)")
        }
        #expect(try store.entries(HistoryQuery(searchText: "the", limit: 100)).count == 100)
        let messagesResults = try store.entries(HistoryQuery(filter: messages, searchText: "the", limit: 100))
        let onlyMessages = messagesResults.allSatisfy({ $0.appKey == AppKey(appName: "Messages") })
        #expect(!messagesResults.isEmpty && onlyMessages)

        // Timeline pages, from the top and from deep in history.
        var page: [NotificationEntry] = []
        let firstPage = try clock.measure { page = try store.entries(HistoryQuery(limit: 100)) }
        let middleDate = start.addingTimeInterval(Double(entryCount / 2) * spacing)
        let atMiddle = try store.entries(HistoryQuery(filter: HistoryFilter(dateRange: DateInterval(start: middleDate, end: middleDate))))
        let middle = try #require(atMiddle.first)
        let deepPage = try clock.measure { page = try store.entries(HistoryQuery(limit: 100, cursor: HistoryCursor(after: middle))) }
        let allOlder = page.allSatisfy({ $0.receivedAt < middle.receivedAt })
        #expect(firstPage < limit && deepPage < limit)
        #expect(page.count == 100 && allOlder)

        // A month of stats for the widget and the stats screen.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var counts: [DailyAppCount] = []
        let lastEntry = start.addingTimeInterval(Double(entryCount - 1) * spacing)
        let stats = try clock.measure {
            counts = try store.dailyCounts(in: DateInterval(start: lastEntry - 30 * TestSupport.day, end: lastEntry), calendar: calendar)
        }
        let total = counts.reduce(0, { $0 + $1.count })
        #expect(stats < limit)
        #expect(total == 30 * 720 + 1)

        print("""
            PerfStoreTests: \(entryCount) inserts in \(insertDuration), \(bytes / 1_000_000) MB; \
            timeline \(firstPage), deep page \(deepPage), 30-day counts \(stats); \
            searches: \(report.joined(separator: "; "))
            """)
    }
}

private let perfApps = [
    "Messages", "WhatsApp", "Slack", "Mail", "Bank", "Calendar", "Instagram", "Uber", "Amazon", "Teams",
    "Signal", "Telegram", "Discord", "Gmail", "Outlook", "Twitter", "Reddit", "Venmo", "PayPal", "Notion",
]

/// Frequent words, so common searches match thousands of entries.
private let perfCommonWords = [
    "the", "you", "your", "a", "is", "to", "and", "new", "message", "from", "code", "order", "delivery",
    "today", "meeting", "reminder", "payment", "update", "photo", "liked", "commented", "sent", "call", "missed", "ready",
]

/// 5,000 made-up words, so the index has a realistic number of distinct terms.
private func perfVocabulary(using random: inout TestSupport.SeededGenerator) -> [String] {
    let syllables = ["ka", "lo", "mi", "ne", "ro", "su", "ta", "vi", "ze", "po", "an", "el", "is", "or", "un", "qu", "bra", "chi", "dre", "fla"]
    var words = Set<String>()
    while words.count < 5_000 {
        var word = ""
        for _ in 0..<Int.random(in: 1...4, using: &random) {
            word += syllables[Int.random(in: 0..<syllables.count, using: &random)]
        }
        words.insert(word)
    }
    return words.sorted()
}

/// About a third common words, the rest from the vocabulary.
private func perfWords(_ count: Int, from vocabulary: [String], using random: inout TestSupport.SeededGenerator) -> String {
    var words: [String] = []
    words.reserveCapacity(count)
    for _ in 0..<count {
        if Int.random(in: 0..<100, using: &random) < 35 {
            words.append(perfCommonWords[Int.random(in: 0..<perfCommonWords.count, using: &random)])
        } else {
            words.append(vocabulary[Int.random(in: 0..<vocabulary.count, using: &random)])
        }
    }
    return words.joined(separator: " ")
}
