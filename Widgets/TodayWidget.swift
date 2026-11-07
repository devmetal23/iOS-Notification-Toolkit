import SwiftUI
import ToolkitCore
import WidgetKit

/// Home Screen and StandBy widget with today's count per app and the latest
/// entries (FR-17). Pro only. Notification text is hidden unless the user turns
/// on Show text in widgets, and is privacy-sensitive even then (NFR-3).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetKind.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Notifications")
        .description("Today's count per app and your latest notifications. Text stays hidden unless you turn it on in Settings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .snapshot(let snapshot):
            switch family {
            case .systemSmall:
                SmallTodayView(snapshot: snapshot)
            case .systemMedium:
                MediumTodayView(snapshot: snapshot, now: entry.date)
            default:
                LargeTodayView(snapshot: snapshot, now: entry.date)
            }
        case .requiresPro:
            RequiresProView()
        case .unavailable:
            UnavailableView()
        }
    }
}

// MARK: - Sizes

private struct SmallTodayView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(isLoggingPaused: snapshot.isLoggingPaused)
            Spacer(minLength: 0)
            Text(snapshot.total, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .accessibilityLabel(Text("\(snapshot.total) notifications today"))
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            if let top = snapshot.apps.first {
                AppCountRow(app: top)
            } else {
                EmptyLine("Nothing logged today")
            }
        }
    }
}

private struct MediumTodayView: View {
    let snapshot: TodaySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderWithTotal(snapshot: snapshot)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if snapshot.apps.isEmpty {
                        EmptyLine("Nothing logged today")
                    } else {
                        ForEach(snapshot.apps.prefix(3)) { app in
                            AppCountRow(app: app)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    if snapshot.latest.isEmpty {
                        EmptyLine("No notifications yet")
                    } else {
                        ForEach(snapshot.latest.prefix(2)) { item in
                            LatestRow(item: item, showsText: snapshot.showsText, now: now)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LargeTodayView: View {
    let snapshot: TodaySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HeaderWithTotal(snapshot: snapshot)
                .padding(.bottom, 2)

            SectionTitle("Top Apps")
            if snapshot.apps.isEmpty {
                EmptyLine("Nothing logged today")
            } else {
                ForEach(snapshot.apps.prefix(3)) { app in
                    AppCountRow(app: app)
                }
            }

            Divider()
                .padding(.vertical, 2)

            SectionTitle("Latest")
            if snapshot.latest.isEmpty {
                EmptyLine("No notifications yet")
            } else {
                // Rows with text take two lines, so show one fewer to fit.
                ForEach(snapshot.latest.prefix(snapshot.showsText ? TodayLoader.latestLimit - 1 : TodayLoader.latestLimit)) { item in
                    LatestRow(item: item, showsText: snapshot.showsText, now: now)
                }
            }

            Spacer(minLength: 0)

            if !snapshot.showsText, !snapshot.latest.isEmpty {
                Text("Notification text is hidden. You can show it in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - States

private struct RequiresProView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .widgetAccentable()
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("Widgets are part of Pro — open the app to upgrade")
                .font(.subheadline)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when history can't be read yet, without suggesting anything is wrong.
private struct UnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(isLoggingPaused: false)
            Spacer(minLength: 0)
            Text(verbatim: "—")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Your history will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

private struct WidgetHeader: View {
    let isLoggingPaused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.tint)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text("Notifications")
                .lineLimit(1)
            if isLoggingPaused {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Logging paused"))
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Header plus today's total on the right, for medium and large.
private struct HeaderWithTotal: View {
    let snapshot: TodaySnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            WidgetHeader(isLoggingPaused: snapshot.isLoggingPaused)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.total, format: .number)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .widgetAccentable()
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(snapshot.total) notifications today"))
        }
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EmptyLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

private struct AppCountRow: View {
    let app: TodaySnapshot.AppCount

    var body: some View {
        HStack(spacing: 4) {
            Text(app.appName)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(app.count, format: .number)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(app.appName))
        .accessibilityValue(Text("\(app.count) notifications today"))
    }
}

/// One recent entry: app and time always; text only when the user opted in.
private struct LatestRow: View {
    let item: TodaySnapshot.Item
    let showsText: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(item.appName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                receivedText
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.caption)

            if showsText, !item.text.isEmpty {
                Text(item.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Time for today's entries; weekday and time for older ones.
    private var receivedText: Text {
        if Calendar.current.isDate(item.receivedAt, inSameDayAs: now) {
            Text(item.receivedAt, style: .time)
        } else {
            Text(item.receivedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, content: .snapshot(.sample()))
    TodayEntry(date: .now, content: .requiresPro)
    TodayEntry(date: .now, content: .unavailable)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, content: .snapshot(.sample()))
    TodayEntry(date: .now, content: .snapshot(.previewWithText()))
}

#Preview("Large", as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, content: .snapshot(.sample()))
    TodayEntry(date: .now, content: .snapshot(.previewWithText()))
    TodayEntry(date: .now, content: .snapshot(.sample().startingNewDay()))
}

private extension TodaySnapshot {
    /// Sample with text shown and logging paused, for previews only.
    static func previewWithText() -> TodaySnapshot {
        var snapshot = sample()
        let texts = ["Sam: See you at 7?", "Your order has shipped", "Dinner moved to 8", "Standup in 10 minutes", "Receipt for your purchase"]
        for index in snapshot.latest.indices {
            snapshot.latest[index].text = texts[index % texts.count]
        }
        snapshot.showsText = true
        snapshot.isLoggingPaused = true
        return snapshot
    }
}
