import Foundation
import Testing
import ToolkitCore

/// Input that would be FTS5 syntax if passed through unescaped.
let storeSearchHostileInputs: [String] = [
    "\"", "\"\"", "\"\"\"", "*", "**", "-", "--", "+", "^", ":", "(", ")", "()", "{a b}", "[a]",
    "OR", "AND", "NOT", "NEAR", "NEAR(", "NEAR(a b", "NEAR(\"a\" \"b\", 3)", "a OR b", "NOT a", "a AND",
    "\"a", "a\"", "a\"b", "a*b", "*a", "a:", ":b", "col:val", "title:sam", "a^b", "'", "' OR 1=1 --", ";", "\\", "%", "_",
    "\u{0}", "\u{0}\u{0}a", "a\u{0}", "\u{1}\u{1F}\u{7F}", "\"\u{301}", "\u{301}\"", "e\u{301}", "\u{200D}", "\u{FEFF}",
    "\u{2028}", "\u{A0}", "🎉", "👨‍👩‍👧", "١٢٣", "ǅ", String(repeating: "x", count: 5_000),
    (0..<100).map { "w\($0)" }.joined(separator: " "),
]

@Suite("Store: full-text search")
struct StoreSearchTests {
    let store: SQLiteNotificationStore
    let start = TestSupport.referenceDate

    init() throws {
        store = try SQLiteNotificationStore.inMemory()
    }

    private func search(_ text: String, filter: HistoryFilter = .all) throws -> [NotificationEntry.ID] {
        try store.entries(HistoryQuery(filter: filter, searchText: text)).map(\.id)
    }

    @Test func wordsMatchAsPrefixesNewestFirst() throws {
        let code = try TestSupport.insert(TestSupport.notification(title: "Sam", body: "Your delivery code is 482913", at: start), into: store)
        let delivered = try TestSupport.insert(TestSupport.notification(title: "Ana", body: "Delivered: the parcel", at: start + 10), into: store)
        try TestSupport.insert(TestSupport.notification(title: "Bo", body: "Nothing to see", at: start + 20), into: store)

        #expect(try search("deliv") == [delivered.id, code.id])
        #expect(try search("DELIVERY") == [code.id])
        #expect(try search("4829") == [code.id])
        #expect(try search("zzz").isEmpty)
    }

    @Test func allWordsMustMatch() throws {
        let both = try TestSupport.insert(TestSupport.notification(body: "Your delivery code is 482913", at: start), into: store)
        try TestSupport.insert(TestSupport.notification(body: "Your delivery is late", at: start + 1), into: store)
        try TestSupport.insert(TestSupport.notification(body: "Your code expired", at: start + 2), into: store)

        #expect(try search("code deliv") == [both.id])
        #expect(try search("  deliv\t\ncode  ") == [both.id])
    }

    @Test func searchesTitleSubtitleAndBody() throws {
        let title = try TestSupport.insert(TestSupport.notification(title: "Quarterly report", body: "x", at: start), into: store)
        let subtitle = try TestSupport.insert(TestSupport.notification(title: "y", subtitle: "Quarterly sync", body: "z", at: start + 1), into: store)
        let body = try TestSupport.insert(TestSupport.notification(title: "w", body: "The quarterly numbers", at: start + 2), into: store)

        #expect(try search("quarter") == [body.id, subtitle.id, title.id])
    }

    @Test func diacriticsAndCaseAreIgnoredBothWays() throws {
        let accented = try TestSupport.insert(TestSupport.notification(title: "Café Crème", body: "Zürich", at: start), into: store)
        let plain = try TestSupport.insert(TestSupport.notification(title: "cafe creme", body: "zurich", at: start + 1), into: store)

        #expect(try search("cafe") == [plain.id, accented.id])
        #expect(try search("CAFÉ crè") == [plain.id, accented.id])
        #expect(try search("zürich") == [plain.id, accented.id])
        // A decomposed é (e + combining acute) matches too.
        #expect(try search("cafe\u{301}") == [plain.id, accented.id])
    }

    @Test func punctuationInsideWordsIsSearchedAsText() throws {
        let link = try TestSupport.insert(
            TestSupport.notification(body: "Track it: https://example.com/track/123", at: start),
            into: store
        )
        let quoted = try TestSupport.insert(
            TestSupport.notification(title: "He said \"hi\"", body: "NEAR(x) col:val -minus", at: start + 1),
            into: store
        )
        #expect(try search("example.com/tr") == [link.id])
        #expect(try search("\"hi\"") == [quoted.id])
        #expect(try search("NEAR(x)") == [quoted.id])
        #expect(try search("col:val") == [quoted.id])
        #expect(try search("-minus") == [quoted.id])
    }

    @Test func blankSearchIsTheTimeline() throws {
        let first = try TestSupport.insert(TestSupport.notification(body: "one", at: start), into: store)
        let second = try TestSupport.insert(TestSupport.notification(body: "two", at: start + 1), into: store)

        for blank in ["", " ", "\t\n", "\u{0}", "\u{0} \u{1}"] {
            #expect(try search(blank) == [second.id, first.id])
        }
    }

    @Test func wordsWithNothingSearchableMatchNothingAlone() throws {
        let entry = try TestSupport.insert(TestSupport.notification(body: "Party tonight 🎉", at: start), into: store)
        // Emoji and punctuation aren't indexed: alone they find nothing, and next
        // to real words they're ignored.
        #expect(try search("🎉").isEmpty)
        #expect(try search("--").isEmpty)
        #expect(try search("party 🎉") == [entry.id])
        #expect(try search("party -") == [entry.id])
    }

    @Test func textAfterANulCharacterIsSearchable() throws {
        let entry = try TestSupport.insert(TestSupport.notification(body: "before\u{0}after", at: start), into: store)
        #expect(try search("after") == [entry.id])
        #expect(try search("before\u{0}after") == [entry.id])
    }

    @Test func searchCombinesWithFilters() throws {
        let messages = try TestSupport.insert(TestSupport.notification(app: "Messages", body: "Delivery today", at: start), into: store)
        let slack = try TestSupport.insert(TestSupport.notification(app: "Slack", body: "Delivery tomorrow", at: start + 100, timeSensitive: true), into: store)

        #expect(try search("deliv", filter: HistoryFilter(apps: [AppKey(appName: "Slack")])) == [slack.id])
        #expect(try search("deliv", filter: HistoryFilter(dateRange: DateInterval(start: start - 1, end: start + 1))) == [messages.id])
        #expect(try search("deliv", filter: HistoryFilter(timeSensitiveOnly: true)) == [slack.id])
        #expect(try search("today", filter: HistoryFilter(apps: [AppKey(appName: "Slack")])).isEmpty)
    }

    @Test(arguments: storeSearchHostileInputs)
    func hostileSearchTextNeverThrows(_ text: String) throws {
        let entry = try TestSupport.insert(TestSupport.notification(body: "plain words here", at: start), into: store)
        _ = try store.entries(HistoryQuery(searchText: text))
        _ = try store.entries(HistoryQuery(filter: HistoryFilter(apps: [AppKey(appName: "Messages")]), searchText: text))
        // Hostile input next to a real word still finds it, unless it adds a word
        // with searchable characters that the entry lacks.
        let combined = try store.entries(HistoryQuery(searchText: "plain " + text)).map(\.id)
        #expect(combined.isEmpty || combined == [entry.id])
    }

    @Test func deletedEntriesLeaveTheIndex() throws {
        let kept = try TestSupport.insert(TestSupport.notification(body: "alpha shared", at: start), into: store)
        let removed = try TestSupport.insert(TestSupport.notification(body: "beta shared", at: start + 1), into: store)
        _ = try store.deleteEntry(id: removed.id)

        #expect(try search("beta").isEmpty)
        #expect(try search("shared") == [kept.id])
    }
}
