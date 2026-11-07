import Foundation
import Testing
import ToolkitCore

private enum TierFixtures {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// A tracked app added `order` hours after `start`.
    static func app(_ name: String, order: Double) -> TrackedApp {
        TrackedApp(key: AppKey(appName: name), displayName: name, addedAt: start.addingTimeInterval(order * 3_600))
    }

    static let ownApp = TrackedApp(key: .ownApp, displayName: "Notification Toolkit", addedAt: start.addingTimeInterval(-3_600))
    static let mail = app("Mail", order: 1)
    static let bank = app("Bank", order: 2)
    static let chat = app("Chat", order: 3)
    static let news = app("News", order: 4)
}

@Suite("Tier")
struct TierTests {
    // MARK: TierLimits

    @Test("Tier limits")
    func limits() {
        #expect(TierLimits(for: .free) == .free)
        #expect(TierLimits(for: .pro) == .pro)
        #expect(TierLimits.free.maxApps == 3)
        #expect(TierLimits.free.maxRetention == .sevenDays)
        #expect(TierLimits.pro.maxApps == nil)
        #expect(TierLimits.pro.maxRetention == nil)
    }

    @Test("Free caps retention at 7 days", arguments: [
        (RetentionPolicy.sevenDays, RetentionPolicy.sevenDays),
        (RetentionPolicy.thirtyDays, RetentionPolicy.sevenDays),
        (RetentionPolicy.ninetyDays, RetentionPolicy.sevenDays),
        (RetentionPolicy.forever, RetentionPolicy.sevenDays),
    ])
    func freeRetention(policy: RetentionPolicy, expected: RetentionPolicy) {
        #expect(TierLimits.free.cappedRetention(policy) == expected)
    }

    @Test("Pro keeps any retention", arguments: RetentionPolicy.allCases)
    func proRetention(policy: RetentionPolicy) {
        #expect(TierLimits.pro.cappedRetention(policy) == policy)
    }

    @Test("A custom cap keeps shorter policies and caps longer ones")
    func customCap() {
        let limits = TierLimits(maxApps: nil, maxRetention: .thirtyDays)
        #expect(limits.cappedRetention(.sevenDays) == .sevenDays)
        #expect(limits.cappedRetention(.thirtyDays) == .thirtyDays)
        #expect(limits.cappedRetention(.ninetyDays) == .thirtyDays)
        #expect(limits.cappedRetention(.forever) == .thirtyDays)

        // A cap of "forever" caps nothing.
        let unlimited = TierLimits(maxApps: 3, maxRetention: .forever)
        for policy in RetentionPolicy.allCases {
            #expect(unlimited.cappedRetention(policy) == policy)
        }
    }

    // MARK: CaptureGate.appsCountingTowardLimit

    @Test("Notification Toolkit itself doesn't count toward the limit")
    func countingApps() {
        let apps = [TierFixtures.mail, TierFixtures.ownApp, TierFixtures.bank]
        #expect(CaptureGate.appsCountingTowardLimit(apps).map(\.key) == [TierFixtures.mail.key, TierFixtures.bank.key])
        #expect(CaptureGate.appsCountingTowardLimit([TierFixtures.ownApp]).isEmpty)
        #expect(CaptureGate.appsCountingTowardLimit([]).isEmpty)
        // The own-app key comes from the app name, however the shortcut spells it.
        #expect(AppKey(appName: "  notification TOOLKIT ") == .ownApp)
    }

    // MARK: CaptureGate.decide

    @Test("Pro allows every app")
    func proAllowsAll() {
        let apps = (1...10).map { TierFixtures.app("App \($0)", order: Double($0)) }
        for app in apps + [TierFixtures.app("Untracked", order: 99)] {
            #expect(CaptureGate.decide(app: app.key, tier: .pro, trackedApps: apps) == .allow)
        }
    }

    @Test("Free allows the 3 earliest-added apps and blocks the rest")
    func freeAllowsThreeEarliest() {
        // Any input order: the gate sorts by when each app was added.
        let tracked = [TierFixtures.news, TierFixtures.chat, TierFixtures.mail, TierFixtures.bank]
        #expect(CaptureGate.decide(app: TierFixtures.mail.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.bank.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.news.key, tier: .free, trackedApps: tracked) == .blockedByAppLimit)
        #expect(CaptureGate.decide(app: AppKey(appName: "Maps"), tier: .free, trackedApps: tracked) == .blockedByAppLimit)
    }

    @Test("Free lets a new app take a slot that is still open")
    func freeOpenSlot() {
        let tracked = [TierFixtures.mail, TierFixtures.bank]
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: []) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: tracked + [TierFixtures.news]) == .blockedByAppLimit)
    }

    @Test("Free frees a slot when an app is removed")
    func freeSlotAfterRemoval() {
        let tracked = [TierFixtures.mail, TierFixtures.bank, TierFixtures.chat, TierFixtures.news]
        #expect(CaptureGate.decide(app: TierFixtures.news.key, tier: .free, trackedApps: tracked) == .blockedByAppLimit)
        let withoutBank = tracked.filter { $0.key != TierFixtures.bank.key }
        #expect(CaptureGate.decide(app: TierFixtures.news.key, tier: .free, trackedApps: withoutBank) == .allow)
    }

    @Test("Apps added at the same moment are ordered by key")
    func sameAddedAt() {
        let addedAt = TierFixtures.start
        let tracked = ["Delta", "Alpha", "Charlie", "Bravo"].map {
            TrackedApp(key: AppKey(appName: $0), displayName: $0, addedAt: addedAt)
        }
        #expect(CaptureGate.decide(app: AppKey(appName: "Alpha"), tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: AppKey(appName: "Bravo"), tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: AppKey(appName: "Charlie"), tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: AppKey(appName: "Delta"), tier: .free, trackedApps: tracked) == .blockedByAppLimit)
    }

    @Test("Notification Toolkit is always allowed, on any tier", arguments: [Tier.free, Tier.pro])
    func ownAppAlwaysAllowed(tier: Tier) {
        let full = [TierFixtures.mail, TierFixtures.bank, TierFixtures.chat, TierFixtures.news]
        #expect(CaptureGate.decide(app: .ownApp, tier: tier, trackedApps: full) == .allow)
        #expect(CaptureGate.decide(app: .ownApp, tier: tier, trackedApps: full + [TierFixtures.ownApp]) == .allow)
        #expect(CaptureGate.decide(app: .ownApp, tier: tier, trackedApps: []) == .allow)
    }

    @Test("Notification Toolkit never takes one of the 3 free slots")
    func ownAppTakesNoSlot() {
        // Added first, so it would hold a slot if it counted.
        let tracked = [TierFixtures.ownApp, TierFixtures.mail, TierFixtures.bank, TierFixtures.chat, TierFixtures.news]
        #expect(CaptureGate.decide(app: TierFixtures.mail.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.bank.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: tracked) == .allow)
        #expect(CaptureGate.decide(app: TierFixtures.news.key, tier: .free, trackedApps: tracked) == .blockedByAppLimit)

        // With two other apps tracked, a new one still gets the third slot.
        let twoOthers = [TierFixtures.ownApp, TierFixtures.mail, TierFixtures.bank]
        #expect(CaptureGate.decide(app: TierFixtures.chat.key, tier: .free, trackedApps: twoOthers) == .allow)
    }
}
