import SwiftUI
import ToolkitCore

/// Pending snoozes with cancel and reschedule (FR-15).
///
/// Soonest first. Swipe to cancel, tap to change the time. Refreshes on appear,
/// when history changes, when the app returns to the foreground, and at least
/// every minute (sooner when the next snooze is about to come back).
struct SnoozedListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var snoozes: [SnoozeRecord] = []
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var selection: SnoozeRecord?
    @State private var isShowingDialog = false
    @State private var isShowingPaywall = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Snoozed")
        }
        .task(id: model.historyRevision) { reload() }
        .task { await refreshPeriodically() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .confirmationDialog(
            "Change Snooze",
            isPresented: $isShowingDialog,
            titleVisibility: .visible,
            presenting: selection
        ) { record in
            ForEach(SnoozeOption.presets) { option in
                Button(option.displayTitle(morningHour: model.settings.morningHour)) {
                    Task { await SnoozeFlow.reschedule(record, to: option, model: model) }
                }
            }
            Button("Choose Time…") {
                SnoozeFlow.chooseCustomRescheduleTime(for: record, model: model)
            }
            Button("Cancel Snooze", role: .destructive) {
                cancel(record)
            }
            Button("Keep", role: .cancel) {}
        } message: { record in
            Text("Comes back \(SnoozeFormatting.fireTimeText(record.fireAt)).")
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var content: some View {
        let isPro = model.entitlements.isPro
        if !hasLoaded {
            Color.clear
        } else if snoozes.isEmpty && loadFailed {
            ContentUnavailableView(
                "Snoozes Aren't Available",
                systemImage: "lock",
                description: Text("Unlock your iPhone, then come back here.")
            )
        } else if snoozes.isEmpty {
            if isPro { emptyState } else { upsell }
        } else {
            List {
                if !isPro {
                    Section { upsellBanner }
                }
                Section {
                    ForEach(snoozes) { record in
                        row(for: record)
                    }
                } footer: {
                    Text("Tap a snooze to change when it comes back. Swipe to cancel it.")
                }
            }
        }
    }

    private func row(for record: SnoozeRecord) -> some View {
        Button {
            selection = record
            isShowingDialog = true
        } label: {
            SnoozedRow(record: record)
        }
        .accessibilityHint("Changes when this notification comes back.")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                cancel(record)
            } label: {
                Label("Cancel Snooze", systemImage: "bell.slash")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Snoozed", systemImage: "moon.zzz")
        } description: {
            Text("Snooze a notification from History and it waits here until it comes back.")
        }
    }

    private var upsell: some View {
        ContentUnavailableView {
            Label("Snooze with Pro", systemImage: "moon.zzz")
        } description: {
            Text("Bring a notification back in 15 minutes, an hour, tomorrow morning or at a time you choose. It waits here until then.")
        } actions: {
            Button("See Pro Options") { isShowingPaywall = true }
                .buttonStyle(.borderedProminent)
        }
    }

    /// For free users who still have snoozes from an earlier subscription.
    private var upsellBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These snoozes still come back. Upgrade to Pro to snooze more notifications or change these.")
                .font(.subheadline)
            Button("See Pro Options") { isShowingPaywall = true }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func reload() {
        do {
            let pending = try model.store()
                .pendingSnoozes(after: Date())
                .sorted { $0.fireAt < $1.fireAt }
            if pending != snoozes { snoozes = pending }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    /// Reloads every minute, or one second after the next snooze comes back if sooner.
    private func refreshPeriodically() async {
        while !Task.isCancelled {
            let untilNext = snoozes.first.map { $0.fireAt.timeIntervalSinceNow + 1 } ?? 60
            try? await Task.sleep(for: .seconds(min(60, max(1, untilNext))))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func cancel(_ record: SnoozeRecord) {
        withAnimation {
            snoozes.removeAll { $0.id == record.id }
        }
        Task {
            let cancelled = await SnoozeFlow.cancel(record, model: model)
            if !cancelled { reload() }
        }
    }
}

/// One pending snooze: app, original text and when it comes back.
private struct SnoozedRow: View {
    let record: SnoozeRecord

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let entry = record.entry
        let fireTime = SnoozeFormatting.fireTimeText(record.fireAt)
        VStack(alignment: .leading, spacing: 4) {
            headerLayout {
                Text(entry.appName)
                    .font(.subheadline.weight(.semibold))
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Label(fireTime, systemImage: "alarm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.body)
            }
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.subheadline)
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(fireTime: fireTime))
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    private func accessibilityText(fireTime: String) -> String {
        let entry = record.entry
        let comesBack = String(localized: "Comes back \(fireTime)")
        return [entry.appName, entry.title, entry.subtitle, entry.body, comesBack]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

#Preview("Free") {
    SnoozedListView()
        .environment(AppModel.preview())
}

#if DEBUG
#Preview("Pro, with snoozes") {
    SnoozedListView()
        .environment(SnoozedListPreview.modelWithSnoozes())
}

@MainActor
private enum SnoozedListPreview {
    static func modelWithSnoozes() -> AppModel {
        let model = AppModel.preview()
        model.entitlements.overrideForPreview(isPro: true)
        if let store = try? model.store(),
           let entries = try? store.entries(HistoryQuery(limit: 3)) {
            for (offset, entry) in entries.enumerated() {
                let fireAt = Date().addingTimeInterval(Double(offset + 1) * 45 * 60)
                _ = try? store.addSnooze(entryID: entry.id, fireAt: fireAt, createdAt: Date())
            }
        }
        return model
    }
}
#endif
