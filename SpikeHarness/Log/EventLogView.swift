import SwiftUI

/// Every Log Spike Notification run, newest first, with per-app and per-hour counts.
struct EventLogView: View {
    @Environment(SpikeModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                problemsSection
                summarySection
                if !model.log.appCounts.isEmpty {
                    Section("Per app") {
                        ForEach(model.log.appCounts) { row in
                            LabeledContent(row.app, value: row.count, format: .number)
                        }
                    }
                }
                if !model.log.hourCounts.isEmpty {
                    Section("Per hour") {
                        ForEach(model.log.hourCounts) { row in
                            LabeledContent {
                                Text(row.count, format: .number)
                            } label: {
                                Text(row.hourStart, format: .dateTime.month(.abbreviated).day().hour())
                            }
                        }
                    }
                }
                eventsSection
            }
            .navigationTitle("Spike Log")
            .navigationDestination(for: SpikeEvent.self) { event in
                EventDetailView(event: event)
            }
            .refreshable {
                await model.reload()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: model.csvExport, preview: SharePreview("NT Spike events")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.events.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                    }
                    .disabled(model.isClearing)
                }
            }
            .confirmationDialog("Clear the spike log?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear Log", role: .destructive) {
                    Task { await model.clear() }
                }
            } message: {
                Text("Deletes events.jsonl and every entry in the spike's SQLite store. Export the CSV first if you still need it.")
            }
            // Re-read every few seconds while the app is in front, so a burst shows up live.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await model.reload()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    @ViewBuilder
    private var problemsSection: some View {
        let log = model.log
        if log.loadError != nil || log.sqliteError != nil || log.eventLogWriteFailures > 0 || log.unreadableLines > 0 {
            Section("Problems") {
                if let error = log.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
                if let error = log.sqliteError {
                    Label("SQLite: \(error)", systemImage: "cylinder.split.1x2")
                }
                if log.eventLogWriteFailures > 0 {
                    Label(
                        "events.jsonl write failures: \(log.eventLogWriteFailures). Last: \(log.lastEventLogWriteFailure ?? "unknown")",
                        systemImage: "doc.badge.ellipsis"
                    )
                }
                if log.unreadableLines > 0 {
                    Label("Unreadable lines in events.jsonl: \(log.unreadableLines)", systemImage: "doc.questionmark")
                }
            }
            .foregroundStyle(.red)
        }
    }

    private var summarySection: some View {
        let summary = model.log.summary
        return Section {
            LabeledContent("Events", value: summary.total, format: .number)
            LabeledContent("Captured while locked", value: summary.locked, format: .number)
            LabeledContent("Cold launches", value: summary.coldLaunches, format: .number)
            LabeledContent("Processes", value: summary.processes, format: .number)
            LabeledContent("SQLite rows") {
                if let rows = model.log.sqliteRowCount {
                    Text(rows, format: .number)
                        .foregroundStyle(rows == summary.total ? Color.secondary : Color.red)
                } else {
                    Text("Unavailable")
                }
            }
            LabeledContent("SQLite failures", value: summary.sqliteFailures, format: .number)
            if let median = summary.medianDurationMs, let longest = summary.maxDurationMs {
                LabeledContent("Run time, median / max") {
                    Text("\(median, format: .number.precision(.fractionLength(0))) / \(longest, format: .number.precision(.fractionLength(0))) ms")
                }
            }
            if let median = summary.medianDelaySeconds, let longest = summary.maxDelaySeconds {
                LabeledContent("Delay, median / max") {
                    Text("\(median, format: .number.precision(.fractionLength(1))) / \(longest, format: .number.precision(.fractionLength(1))) s")
                }
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Locked means isProtectedDataAvailable was false. With a passcode it turns false about 10 seconds after the phone locks and true at unlock, so a capture in the first 10 seconds after locking shows as unlocked. Delay is capture time minus the notification's date. A cold launch is the first capture in a new NT Spike process.")
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        Section("Events, newest first") {
            if model.events.isEmpty {
                ContentUnavailableView(
                    "No Captures Yet",
                    systemImage: "bell.slash",
                    description: Text("Set up the automation described on the Tools tab, then post a test notification.")
                )
            } else {
                ForEach(model.events) { event in
                    NavigationLink(value: event) {
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: SpikeEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.displayApp)
                    .font(.headline)
                Spacer()
                LockBadge(isLocked: event.isLocked)
            }
            if !event.displayText.isEmpty {
                Text(event.displayText)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            Group {
                Text("Captured \(event.capturedAt, format: SpikeTimeFormat.precise)")
                if let date = event.date, let delay = event.delaySeconds {
                    Text("Notification \(date, format: SpikeTimeFormat.precise) · delay \(delay, format: .number.precision(.fractionLength(1))) s")
                } else {
                    Text("No notification date passed")
                }
                Text(runLine)
            }
            .font(.caption)
            .foregroundStyle(event.sqliteSucceeded ? Color.secondary : Color.red)
        }
        .padding(.vertical, 2)
    }

    private var runLine: String {
        let duration = event.durationMs.formatted(.number.precision(.fractionLength(0)))
        let launch = event.isColdLaunch ? "cold launch" : "warm, capture \(event.captureIndexInProcess)"
        let sqlite = event.sqliteSucceeded ? "SQLite OK" : "SQLite failed"
        return "Ran \(duration) ms · \(launch) · \(sqlite)"
    }
}

struct LockBadge: View {
    let isLocked: Bool

    var body: some View {
        Label(isLocked ? "Locked" : "Unlocked", systemImage: isLocked ? "lock.fill" : "lock.open")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isLocked ? Color.orange : Color.secondary)
            .accessibilityLabel(isLocked ? "Captured while locked" : "Captured while unlocked")
    }
}

enum SpikeTimeFormat {
    /// 14:03:05.123 in the tester's locale.
    static var precise: Date.FormatStyle {
        .dateTime.hour().minute().second().secondFraction(.fractional(3))
    }
}
