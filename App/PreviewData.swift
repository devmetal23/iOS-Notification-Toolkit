import Foundation
import ToolkitCore

/// Sample history for SwiftUI previews. Never used in release paths.
enum PreviewData {
    static func populate(_ store: any NotificationStoring, now: Date = Date()) {
        let samples: [(String, String, String, TimeInterval)] = [
            ("Messages", "Sam", "Your delivery code is 482913", -120),
            ("Slack", "#launch", "Build 214 is on TestFlight", -1_800),
            ("Bank", "Card alert", "A $42.10 charge at Corner Cafe. Call 800-555-0100 if this wasn't you.", -7_200),
            ("Mail", "Receipt", "Your order ships tomorrow: https://example.com/track/123", -90_000),
        ]
        for (app, title, body, offset) in samples {
            let date = now.addingTimeInterval(offset)
            _ = try? store.insert(
                NewNotification(appName: app, title: title, body: body, receivedAt: date),
                capturedAt: date,
                dedupeWindow: CaptureService.dedupeWindow
            )
        }
    }
}
