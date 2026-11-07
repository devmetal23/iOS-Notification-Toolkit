import Foundation
import Testing
import ToolkitCore

private enum HealthFixtures {
    static let now = Date(timeIntervalSince1970: 1_780_000_000)
    static let day: TimeInterval = 24 * 60 * 60
    static let threshold = HealthCheck.silenceThreshold

    static func app(
        _ name: String,
        addedDaysAgo: Double = 30,
        lastLoggedSecondsAgo: TimeInterval? = nil
    ) -> TrackedApp {
        TrackedApp(
            key: AppKey(appName: name),
            displayName: name,
            addedAt: now.addingTimeInterval(-addedDaysAgo * day),
            lastLoggedAt: lastLoggedSecondsAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    static func status(of app: TrackedApp, threshold: TimeInterval = HealthCheck.silenceThreshold) -> HealthCheck.Status? {
        HealthCheck.evaluate([app], now: now, threshold: threshold).first?.status
    }
}

@Suite("HealthCheck")
struct HealthCheckTests {
    @Test("The default threshold is 7 days")
    func defaultThreshold() {
        #expect(HealthCheck.silenceThreshold == 7 * 24 * 60 * 60)
    }

    @Test("Logged within the threshold is healthy")
    func healthy() {
        let app = HealthFixtures.app("Mail", lastLoggedSecondsAgo: HealthFixtures.threshold - 1)
        #expect(HealthFixtures.status(of: app) == .healthy)
        #expect(HealthFixtures.status(of: HealthFixtures.app("Mail", lastLoggedSecondsAgo: 0)) == .healthy)
    }

    @Test("Silent once the threshold has passed since the last capture")
    func silent() {
        let atThreshold = HealthFixtures.app("Mail", lastLoggedSecondsAgo: HealthFixtures.threshold)
        let lastLoggedAt = HealthFixtures.now.addingTimeInterval(-HealthFixtures.threshold)
        #expect(HealthFixtures.status(of: atThreshold) == .silent(since: lastLoggedAt))

        let longAgo = HealthFixtures.app("Mail", addedDaysAgo: 400, lastLoggedSecondsAgo: 90 * HealthFixtures.day)
        #expect(HealthFixtures.status(of: longAgo) == .silent(since: HealthFixtures.now.addingTimeInterval(-90 * HealthFixtures.day)))
    }

    @Test("Waiting for a first capture becomes overdue at the threshold")
    func awaitingFirstCapture() {
        let justAdded = HealthFixtures.app("Bank", addedDaysAgo: 0)
        #expect(HealthFixtures.status(of: justAdded) == .awaitingFirstCapture(overdue: false))

        let almost = HealthFixtures.app("Bank", addedDaysAgo: 7 - 1.0 / 86_400)
        #expect(HealthFixtures.status(of: almost) == .awaitingFirstCapture(overdue: false))

        let atThreshold = HealthFixtures.app("Bank", addedDaysAgo: 7)
        #expect(HealthFixtures.status(of: atThreshold) == .awaitingFirstCapture(overdue: true))
    }

    @Test("A capture newer than now (clock change) is healthy")
    func futureCapture() {
        let app = HealthFixtures.app("Mail", lastLoggedSecondsAgo: -3_600)
        #expect(HealthFixtures.status(of: app) == .healthy)
    }

    @Test("Uses the threshold it is given")
    func customThreshold() {
        let app = HealthFixtures.app("Mail", addedDaysAgo: 2, lastLoggedSecondsAgo: 2 * HealthFixtures.day)
        #expect(HealthFixtures.status(of: app, threshold: HealthFixtures.day) == .silent(since: HealthFixtures.now.addingTimeInterval(-2 * HealthFixtures.day)))
        #expect(HealthFixtures.status(of: app, threshold: 3 * HealthFixtures.day) == .healthy)

        let neverLogged = HealthFixtures.app("Bank", addedDaysAgo: 2)
        #expect(HealthFixtures.status(of: neverLogged, threshold: HealthFixtures.day) == .awaitingFirstCapture(overdue: true))
    }

    @Test("Needs attention when silent or overdue", arguments: [
        (HealthCheck.Status.healthy, false),
        (HealthCheck.Status.awaitingFirstCapture(overdue: false), false),
        (HealthCheck.Status.awaitingFirstCapture(overdue: true), true),
        (HealthCheck.Status.silent(since: Date(timeIntervalSince1970: 0)), true),
    ])
    func needsAttention(status: HealthCheck.Status, expected: Bool) {
        let health = HealthCheck.AppHealth(app: HealthFixtures.app("Mail"), status: status)
        #expect(health.needsAttention == expected)
    }

    @Test("Apps needing attention come first, then by name, then by key")
    func ordering() {
        let healthyZoom = HealthFixtures.app("Zoom", lastLoggedSecondsAgo: 60)
        let healthyBank = HealthFixtures.app("bank", lastLoggedSecondsAgo: 60)
        let silentMail = HealthFixtures.app("Mail", lastLoggedSecondsAgo: 30 * HealthFixtures.day)
        let overdueAcme = HealthFixtures.app("acme", addedDaysAgo: 10)
        let waitingBeta = HealthFixtures.app("Beta", addedDaysAgo: 1)
        // Same display name, different keys: the key breaks the tie.
        let twinB = TrackedApp(key: AppKey(rawValue: "twin-b"), displayName: "Twin", addedAt: HealthFixtures.now, lastLoggedAt: HealthFixtures.now)
        let twinA = TrackedApp(key: AppKey(rawValue: "twin-a"), displayName: "Twin", addedAt: HealthFixtures.now, lastLoggedAt: HealthFixtures.now)

        let input = [healthyZoom, twinB, silentMail, healthyBank, waitingBeta, twinA, overdueAcme]
        let result = HealthCheck.evaluate(input, now: HealthFixtures.now)

        #expect(result.map(\.app.displayName) == ["acme", "Mail", "bank", "Beta", "Twin", "Twin", "Zoom"])
        #expect(result.map(\.id) == [overdueAcme, silentMail, healthyBank, waitingBeta, twinA, twinB, healthyZoom].map(\.key))
        #expect(result.map(\.needsAttention) == [true, true, false, false, false, false, false])
        // The order doesn't depend on the input order.
        #expect(HealthCheck.evaluate(input.reversed(), now: HealthFixtures.now) == result)
    }

    @Test("One result per app; none for no apps")
    func counts() {
        #expect(HealthCheck.evaluate([], now: HealthFixtures.now).isEmpty)
        let apps = (1...5).map { HealthFixtures.app("App \($0)", lastLoggedSecondsAgo: Double($0) * HealthFixtures.day * 2) }
        let result = HealthCheck.evaluate(apps, now: HealthFixtures.now)
        #expect(result.count == 5)
        #expect(Set(result.map(\.id)) == Set(apps.map(\.key)))
    }
}
