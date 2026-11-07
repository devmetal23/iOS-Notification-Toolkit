import SwiftUI
import UIKit

/// Posts NT Spike's own notifications so the automation on NT Spike fires on cue.
struct TestToolsView: View {
    @Environment(SpikeModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var options = SpikeNotificationOptions()
    @State private var burstSize = 30

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                setupSection
                permissionSection
                optionsSection
                singleSection
                burstSection
                Section {
                    Button("Cancel Pending Notifications", role: .destructive) {
                        Task { await model.cancelPending() }
                    }
                } footer: {
                    Text("Pending: \(model.permission?.pendingCount ?? 0). iOS keeps at most 64 per app.")
                }
                Section {
                    Toggle("Reopen store for each capture", isOn: $model.reopenStoreEachCapture)
                    LabeledContent("App Group", value: SpikeContainer.appGroupIdentifier ?? "Missing from Info.plist")
                    LabeledContent("Files", value: "Spike/events.jsonl, Spike/History.sqlite")
                } header: {
                    Text("Store")
                } footer: {
                    Text("Off: one SQLite connection stays open for the life of the process, like the real app. Turn on only to check whether closing it after each capture removes 0xdead10cc crashes (S4).")
                }
            }
            .navigationTitle("Test Tools")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.refreshPermission()
            }
            .alert("Something Went Wrong", isPresented: $model.isShowingToolError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.toolError ?? "")
            }
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("NT Spike records only what a Shortcuts automation hands it, so first add an automation for NT Spike itself:")
                Text("1. Shortcuts › Automation › New Automation, choose the Notification trigger (\u{201C}When I receive a notification from\u{201D}) and pick NT Spike. Leave the title, subtitle and message filters empty.")
                Text("2. Choose Run Immediately and turn off Notify When Run.")
                Text("3. Add Log Spike Notification. Fill App, Title, Subtitle, Body, Date and Time Sensitive from the Notification variable; if it has no app field, type NT Spike for App. Put the whole Notification variable, with no field chosen, in Raw.")
                Text("4. Post a test below and check the Log tab.")
            }
            .font(.callout)
        } header: {
            Text("Before You Test")
        } footer: {
            Text("Open NT Spike once after installing so Shortcuts lists its action. iOS 27 labels may differ slightly; docs/spikes.md has the full steps.")
        }
    }

    private var permissionSection: some View {
        Section("Notification Permission") {
            if let permission = model.permission {
                ForEach(permission.rows) { row in
                    LabeledContent(row.label, value: row.value)
                }
                if permission.isUndetermined {
                    Button("Request Permission") {
                        Task { await model.requestPermission() }
                    }
                } else if !permission.isAuthorized {
                    Label("Notifications are off for NT Spike, so tests won't show.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                ProgressView()
            }
            Button("Open Notification Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("Interruption level", selection: $options.level) {
                ForEach(SpikeNotificationOptions.Level.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            Toggle("No body text", isOn: $options.noBody)
        } header: {
            Text("Notification Options")
        } footer: {
            Text("Used by both tests. Time-sensitive needs Time Sensitive Notifications on for NT Spike. Passive arrives silently without lighting the screen.")
        }
    }

    private var singleSection: some View {
        Section {
            Button("Post Notification in 30 s") {
                Task { await model.postSingle(options: options) }
            }
            if let run = model.single {
                CountdownView(run: run)
            }
        } header: {
            Text("Single Test (S1, S3, S6)")
        } footer: {
            Text("Lock the phone within the first 10 seconds. Protected data becomes unavailable about 10 seconds after locking, so the capture at 30 seconds runs while the phone is properly locked.")
        }
    }

    private var burstSection: some View {
        Section {
            Stepper("Notifications: \(burstSize)", value: $burstSize, in: 1...NotificationPoster.burstLimit)
            Button("Post Burst") {
                Task { await model.postBurst(count: burstSize, options: options) }
            }
            if let run = model.burst {
                BurstProgressView(run: run)
            }
        } header: {
            Text("Burst (S4)")
        } footer: {
            Text("The first arrives \(Int(SpikeModel.burstLeadIn)) seconds after you tap, then one per second, like a busy group chat. Lock the phone during the lead-in.")
        }
    }
}

/// 30 → 1, then the time it was posted.
struct CountdownView: View {
    let run: SpikeModel.ScheduledRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = Int(ceil(run.firstFireDate.timeIntervalSince(context.date)))
            if remaining > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(remaining, format: .number)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(remaining > 20 ? "Lock your iPhone now." : "Keep it locked.")
                        .foregroundStyle(remaining > 20 ? Color.orange : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(remaining) seconds until test \(run.marker)")
            } else {
                Label("Test \(run.marker) posted at \(run.firstFireDate, format: SpikeTimeFormat.precise)", systemImage: "bell.badge")
            }
        }
    }
}

struct BurstProgressView: View {
    let run: SpikeModel.ScheduledRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let untilFirst = run.firstFireDate.timeIntervalSince(context.date)
            if untilFirst > 0 {
                Label("Burst \(run.marker): first in \(Int(ceil(untilFirst))) s. Lock now.", systemImage: "timer")
            } else if context.date < run.lastFireDate {
                let posted = min(run.count, Int(-untilFirst) + 1)
                Label("Burst \(run.marker): \(posted) of \(run.count) posted", systemImage: "bell.and.waves.left.and.right")
            } else {
                Label("Burst \(run.marker): all \(run.count) posted by \(run.lastFireDate, format: SpikeTimeFormat.precise)", systemImage: "checkmark.circle")
            }
        }
    }
}
