import SwiftUI

/// Every recorded field of one capture. For S6, shows exactly what Shortcuts passed:
/// "not passed" for a parameter left empty, "(empty text)" for "".
struct EventDetailView: View {
    let event: SpikeEvent

    var body: some View {
        List {
            Section("Parameters") {
                row("App", event.app)
                row("Title", event.title)
                row("Subtitle", event.subtitle)
                row("Body", event.body)
                row("Date", event.date.map { $0.formatted(SpikeTimeFormat.precise) + " " + $0.formatted(date: .abbreviated, time: .omitted) })
                row("Time Sensitive", event.isTimeSensitive.map { $0 ? "Yes" : "No" })
            }
            Section {
                if let raw = event.raw {
                    Text(raw.isEmpty ? "(empty text)" : raw)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                } else {
                    Text("Not passed")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Raw")
            } footer: {
                Text("S6: the whole Notification variable as Shortcuts turns it into text.")
            }
            Section("Capture") {
                row("Captured", event.capturedAt.formatted(SpikeTimeFormat.precise) + " " + event.capturedAt.formatted(date: .abbreviated, time: .omitted))
                row("Delay", event.delaySeconds.map { $0.formatted(.number.precision(.fractionLength(3))) + " s" })
                row("Protected data", event.protectedDataAvailable ? "Available (unlocked)" : "Unavailable (locked)")
                row("App state", event.applicationState)
                row("Run time", event.durationMs.formatted(.number.precision(.fractionLength(1))) + " ms")
                row("Main actor wait", event.mainActorMs.formatted(.number.precision(.fractionLength(1))) + " ms")
                row("SQLite time", event.sqliteMs.formatted(.number.precision(.fractionLength(1))) + " ms")
            }
            Section("Process") {
                row("Process ID", String(event.processID))
                row("Launched", event.processLaunchedAt.formatted(SpikeTimeFormat.precise))
                row("Since launch", event.secondsSinceProcessLaunch.formatted(.number.precision(.fractionLength(3))) + " s")
                row("Capture in process", String(event.captureIndexInProcess))
            }
            Section("SQLite") {
                row("Result", event.sqliteSucceeded ? "Stored" : "Failed")
                row("Entry ID", event.sqliteEntryID.map { String($0) })
                if let error = event.sqliteError {
                    row("Error", error)
                }
            }
            Section("Event") {
                row("ID", event.id.uuidString)
            }
        }
        .navigationTitle(event.displayApp)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent {
            if let value {
                Text(value.isEmpty ? "(empty text)" : value)
                    .textSelection(.enabled)
            } else {
                Text("Not passed")
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text(label)
        }
    }
}
