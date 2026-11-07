import SwiftUI
import ToolkitCore

/// One notification in full, with actions for codes, links and phone numbers
/// (FR-11), snooze, and delete (FR-13).
struct HistoryEntryDetailView: View {
    let entry: NotificationEntry

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var matches: [ContentDetector.Match] = []
    @State private var copiedID: String?
    @State private var appEntryCount: Int?
    @State private var confirmsDeleteAllFromApp = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private static let copiedTextID = "full-text"

    var body: some View {
        List {
            Section {
                content
            }

            if !matches.isEmpty {
                Section("Actions") {
                    ForEach(matches) { match in
                        actionRow(for: match)
                    }
                }
            }

            Section {
                let copied = copiedID == Self.copiedTextID
                let copyTitle: LocalizedStringKey = copied ? "Copied" : "Copy Text"
                Button {
                    copy(entry.historyFullText, id: Self.copiedTextID)
                } label: {
                    Label(copyTitle, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(entry.historyFullText.isEmpty)
            }

            Section {
                Button("Delete Notification", systemImage: "trash", role: .destructive) {
                    deleteEntry()
                }
                Button("Delete All from \(entry.appName)…", systemImage: "trash.slash", role: .destructive) {
                    prepareDeleteAllFromApp()
                }
            }
            .disabled(isDeleting)
        }
        .navigationTitle(entry.appName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SnoozeMenu(entry: entry)
            }
        }
        .task(id: entry.id) {
            matches = ContentDetector.matches(in: entry)
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copiedID = nil }
        }
        .sensoryFeedback(.success, trigger: copiedID) { _, new in new != nil }
        .confirmationDialog(
            deleteAllTitle,
            isPresented: $confirmsDeleteAllFromApp,
            titleVisibility: .visible
        ) {
            Button("Delete All from \(entry.appName)", role: .destructive) {
                deleteAllFromApp()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Pending snoozes for these notifications are cancelled.")
        }
        .alert("Couldn't Delete", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if entry.isTimeSensitive {
                    Label {
                        Text("Time Sensitive")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
            }
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.headline)
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.body)
            }

            Text(entry.receivedAt, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionRow(for match: ContentDetector.Match) -> some View {
        switch match.kind {
        case .code:
            Button {
                copy(match.value, id: match.id)
            } label: {
                actionLabel(
                    title: copiedID == match.id ? "Copied" : "Copy Code",
                    detail: match.text,
                    systemImage: copiedID == match.id ? "checkmark" : "number",
                    monospaced: true
                )
            }
            .accessibilityHint("Copies the code to this iPhone's clipboard only.")
        case .link:
            if let url = match.url {
                Button {
                    openURL(url)
                } label: {
                    actionLabel(title: "Open Link", detail: match.text, systemImage: "safari")
                }
            }
        case .phoneNumber:
            if let url = match.url {
                Button {
                    openURL(url)
                } label: {
                    actionLabel(title: "Call", detail: match.text, systemImage: "phone")
                }
            }
        }
    }

    private func actionLabel(
        title: LocalizedStringKey,
        detail: String,
        systemImage: String,
        monospaced: Bool = false
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(monospaced ? .subheadline.monospaced() : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    // MARK: Actions

    private func copy(_ text: String, id: String) {
        HistoryPasteboard.copy(text)
        copiedID = id
    }

    private func deleteEntry() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await HistoryDeletion.deleteEntry(entry.id, model: model)
                dismiss()
            } catch {
                errorMessage = HistoryErrorText.message(for: error)
            }
        }
    }

    private func prepareDeleteAllFromApp() {
        let filter = HistoryFilter(apps: [entry.appKey])
        appEntryCount = try? model.store().entryCount(filter: filter)
        confirmsDeleteAllFromApp = true
    }

    private func deleteAllFromApp() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await HistoryDeletion.deleteEntries(from: entry.appKey, model: model)
                dismiss()
            } catch {
                errorMessage = HistoryErrorText.message(for: error)
            }
        }
    }

    private var deleteAllTitle: Text {
        if let appEntryCount {
            Text("Delete all \(appEntryCount) notifications from \(entry.appName)?")
        } else {
            Text("Delete all notifications from \(entry.appName)?")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#Preview {
    NavigationStack {
        HistoryEntryDetailView(entry: .historyPreview)
    }
    .environment(AppModel.preview())
}
