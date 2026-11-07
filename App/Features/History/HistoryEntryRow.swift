import SwiftUI
import ToolkitCore

/// One notification in the timeline: app, time, title and two lines of the message.
struct HistoryEntryRow: View {
    let entry: NotificationEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    /// App name and time side by side, stacked at accessibility text sizes.
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if entry.isTimeSensitive {
                    TimeSensitiveMarker()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.receivedAt, format: .dateTime.hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// One VoiceOver label for the whole row.
    private var accessibilityDescription: String {
        var parts = [entry.appName]
        if entry.isTimeSensitive {
            parts.append(String(localized: "Time Sensitive"))
        }
        parts += [entry.title, entry.subtitle, entry.body].filter { !$0.isEmpty }
        parts.append(entry.receivedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }
}

/// Marks a Time Sensitive notification. Decorative inside a row, whose label says it.
struct TimeSensitiveMarker: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Time Sensitive")
    }
}

#Preview {
    List {
        HistoryEntryRow(entry: .historyPreview)
        HistoryEntryRow(entry: .historyPreviewTimeSensitive)
    }
}

extension NotificationEntry {
    /// Sample entries for History previews that don't need a store.
    static let historyPreview = NotificationEntry(
        id: 1,
        appKey: AppKey(appName: "Messages"),
        appName: "Messages",
        title: "Sam",
        subtitle: "",
        body: "Your delivery code is 482913. Call 800-555-0100 or visit https://example.com/track/123 for help.",
        receivedAt: Date.now.addingTimeInterval(-120),
        capturedAt: Date.now.addingTimeInterval(-118),
        isTimeSensitive: false
    )

    static let historyPreviewTimeSensitive = NotificationEntry(
        id: 2,
        appKey: AppKey(appName: "Bank"),
        appName: "Bank",
        title: "Card alert",
        subtitle: "Debit card ending 1234",
        body: "A $42.10 charge at Corner Cafe. Call 800-555-0100 if this wasn't you.",
        receivedAt: Date.now.addingTimeInterval(-7_200),
        capturedAt: Date.now.addingTimeInterval(-7_198),
        isTimeSensitive: true
    )
}
