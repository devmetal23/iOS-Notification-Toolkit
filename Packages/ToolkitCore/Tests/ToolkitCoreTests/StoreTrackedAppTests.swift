import Foundation
import Testing
import ToolkitCore

@Suite("Store: tracked apps")
struct StoreTrackedAppTests {
    let store: SQLiteNotificationStore
    let start = TestSupport.referenceDate

    init() throws {
        store = try SQLiteNotificationStore.inMemory()
    }

    private func app(_ name: String) throws -> TrackedApp? {
        try store.trackedApps().first { $0.key == AppKey(appName: name) }
    }

    @Test func registeringIsIdempotent() throws {
        let first = try store.registerApp(displayName: "WhatsApp", catalogID: "whatsapp", at: start)
        #expect(first == TrackedApp(key: AppKey(appName: "WhatsApp"), displayName: "WhatsApp", addedAt: start, catalogID: "whatsapp"))

        let again = try store.registerApp(displayName: " whatsapp ", catalogID: nil, at: start + 100)
        #expect(again == first)
        #expect(try store.trackedApps() == [first])
    }

    @Test func capturesRegisterTheAppAndRecordLogging() throws {
        try TestSupport.insert(TestSupport.notification(app: " Messages ", body: "1", at: start), into: store, capturedAt: start + 1)
        try TestSupport.insert(TestSupport.notification(app: "Slack", body: "2", at: start + 10), into: store)
        try TestSupport.insert(TestSupport.notification(app: "Messages", body: "3", at: start + 20), into: store, capturedAt: start + 25)
        // A duplicate still shows the automation is running.
        let duplicate = try store.insert(
            TestSupport.notification(app: "Messages", body: "3", at: start + 30),
            capturedAt: start + 40,
            dedupeWindow: CaptureService.dedupeWindow
        )
        #expect(!TestSupport.isInserted(duplicate))
        // A late capture of an old notification doesn't move the last-logged time back.
        try TestSupport.insert(TestSupport.notification(app: "Messages", body: "4", at: start - 500), into: store, capturedAt: start + 35)

        let apps = try store.trackedApps()
        #expect(apps.map(\.key) == [AppKey(appName: "Messages"), AppKey(appName: "Slack")])
        let messages = try #require(apps.first)
        #expect(messages.displayName == "Messages")
        #expect(messages.addedAt == start + 1)
        #expect(messages.catalogID == nil)
        #expect(messages.firstLoggedAt == start + 1)
        #expect(messages.lastLoggedAt == start + 40)
        #expect(messages.entryCount == 3)
        #expect(messages.blockedCount == 0)
        #expect(apps.last?.entryCount == 1)
    }

    @Test func registeredAppKeepsItsCatalogDetailsWhenFirstCaptured() throws {
        try store.registerApp(displayName: "Bank", catalogID: "bank", at: start)
        let before = try #require(try app("Bank"))
        #expect(before.firstLoggedAt == nil && before.lastLoggedAt == nil && before.entryCount == 0)

        try TestSupport.insert(TestSupport.notification(app: "bank", body: "Card alert", at: start + 60), into: store)

        let after = try #require(try app("Bank"))
        #expect(after.addedAt == start)
        #expect(after.catalogID == "bank")
        #expect(after.displayName == "Bank")
        #expect(after.firstLoggedAt == start + 60)
        #expect(after.lastLoggedAt == start + 60)
        #expect(after.entryCount == 1)
    }

    @Test func removingAnAppKeepsItsEntries() throws {
        let entry = try TestSupport.insert(TestSupport.notification(app: "Slack", at: start), into: store)
        try store.removeApp(AppKey(appName: "Slack"))
        // Removing an app that isn't tracked is a no-op.
        try store.removeApp(AppKey(appName: "Nope"))

        #expect(try store.trackedApps().isEmpty)
        #expect(try store.entry(id: entry.id) == entry)
    }

    @Test func blockedCapturesAreCountedAndRegisterTheApp() throws {
        try store.recordBlockedCapture(TestSupport.notification(app: "Discord", at: start), at: start + 5)
        try store.recordBlockedCapture(TestSupport.notification(app: "discord", at: start + 1), at: start + 9)

        let discord = try #require(try app("Discord"))
        #expect(discord.blockedCount == 2)
        #expect(discord.addedAt == start + 5)
        #expect(discord.entryCount == 0)
        #expect(discord.firstLoggedAt == nil)
        #expect(try store.entryCount(filter: .all) == 0)
    }

    @Test func trackedAppsAreOldestAddedFirst() throws {
        try store.registerApp(displayName: "Zulu", catalogID: nil, at: start)
        try store.registerApp(displayName: "Bravo", catalogID: nil, at: start + 20)
        try store.registerApp(displayName: "Alpha", catalogID: nil, at: start + 10)
        try store.registerApp(displayName: "Charlie", catalogID: nil, at: start + 10)

        #expect(try store.trackedApps().map(\.displayName) == ["Zulu", "Alpha", "Charlie", "Bravo"])
    }
}
