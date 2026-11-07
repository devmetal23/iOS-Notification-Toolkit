import SwiftUI

/// One point in an explanation: a symbol, a short title and a sentence.
struct ExplanationPoint: Identifiable, Sendable {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var id: String { symbol }
}

/// What onboarding (FR-1) and Setup › How It Works say about capture and privacy.
///
/// Keep this honest for App Review guideline 2.3: the app never reads
/// notifications itself. Capture happens only through Shortcuts automations the
/// user switches on, only for apps they set up, and only from setup onward.
enum CaptureExplanation {
    static let capturePoints: [ExplanationPoint] = [
        ExplanationPoint(
            symbol: "hand.tap",
            title: "Only apps you choose",
            detail: "Each automation covers one app. Apps you don't set up are never logged."
        ),
        ExplanationPoint(
            symbol: "switch.2",
            title: "You switch them on",
            detail: "Automations from shared shortcuts arrive switched off. You turn each one on in the Shortcuts app."
        ),
        ExplanationPoint(
            symbol: "calendar.badge.clock",
            title: "From setup onward",
            detail: "Notifications that arrived before you set up an app can't be added."
        ),
    ]

    static let privacyPoints: [ExplanationPoint] = [
        ExplanationPoint(
            symbol: "iphone",
            title: "Stays on this iPhone",
            detail: "Your history is saved only on this iPhone. Nothing is uploaded, and there are no accounts or analytics."
        ),
        ExplanationPoint(
            symbol: "icloud.slash",
            title: "Left out of backups",
            detail: "History isn't included in iCloud or computer backups, so it won't move to a new iPhone."
        ),
    ]
}

struct ExplanationPointRow: View {
    let point: ExplanationPoint

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(.headline)
                Text(point.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: point.symbol)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        ForEach(CaptureExplanation.capturePoints) { ExplanationPointRow(point: $0) }
        ForEach(CaptureExplanation.privacyPoints) { ExplanationPointRow(point: $0) }
    }
}
