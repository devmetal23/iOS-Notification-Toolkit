import SwiftUI
import ToolkitCore

/// Deletes history by app or all at once (FR-13).
struct ManageHistoryView: View {
    @Environment(AppModel.self) private var model

    @State private var apps: [TrackedApp] = []
    @State private var totalCount = 0
    @State private var loadFailure: HistoryLoadFailure?
    @State private var hasLoaded = false
    @State private var appToDelete: TrackedApp?
    @State private var confirmsDeleteAll = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let loadFailure {
                failureRow(loadFailure)
            } else {
                appsSection
                deleteAllSection
            }
        }
        .navigationTitle("Manage History")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if !hasLoaded {
                ProgressView()
            }
        }
        .disabled(isDeleting)
        .task(id: model.historyRevision) {
            await load()
        }
        .confirmationDialog(
            deleteAppTitle,
            isPresented: isConfirmingAppDelete,
            titleVisibility: .visible,
            presenting: appToDelete
        ) { app in
            Button("Delete All from \(app.displayName)", role: .destructive) {
                delete { try await HistoryDeletion.deleteEntries(from: app.key, model: model) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone. The automation keeps saving new notifications from this app.")
        }
        .confirmationDialog(
            "Delete All History?",
            isPresented: $confirmsDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All \(totalCount) Notifications", role: .destructive) {
                delete { try await HistoryDeletion.deleteAll(model: model) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every notification saved on this iPhone is deleted and pending snoozes are cancelled. This can't be undone.")
        }
        .alert("Couldn't Delete", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var appsSection: some View {
        Section {
            if hasLoaded, apps.isEmpty {
                Text("No apps are set up yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(apps) { app in
                Button {
                    appToDelete = app
                } label: {
                    LabeledContent {
                        Text(app.entryCount, format: .number)
                            .monospacedDigit()
                    } label: {
                        Text(app.displayName)
                            .foregroundStyle(Color.primary)
                    }
                }
                .disabled(app.entryCount == 0)
                .accessibilityLabel(Text("\(app.displayName), \(app.entryCount) notifications"))
                .accessibilityHint(Text("Deletes all notifications from \(app.displayName)."))
            }
        } header: {
            Text("Delete by App")
        } footer: {
            Text("Tap an app to delete every notification saved from it.")
        }
    }

    private var deleteAllSection: some View {
        Section {
            Button("Delete All History", systemImage: "trash", role: .destructive) {
                confirmsDeleteAll = true
            }
            .disabled(totalCount == 0)
        } footer: {
            Text("\(totalCount) notifications are saved on this iPhone.")
        }
    }

    private func failureRow(_ failure: HistoryLoadFailure) -> some View {
        Section {
            switch failure {
            case .protectedDataUnavailable:
                Text("Your history is protected until you unlock your iPhone for the first time after it restarts.")
            case .other:
                Text("Something went wrong while reading your history.")
            }
            Button("Try Again") {
                Task { await load() }
            }
        }
    }

    // MARK: Loading and deleting

    private func load() async {
        do {
            let store = try model.store()
            let snapshot = try await HistoryStoreAccess.perform(on: store) { store in
                let apps = try store.trackedApps()
                let totalCount = try store.entryCount(filter: .all)
                return ManageHistorySnapshot(
                    apps: CaptureGate.appsCountingTowardLimit(apps),
                    totalCount: totalCount
                )
            }
            apps = snapshot.apps.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            totalCount = snapshot.totalCount
            loadFailure = nil
        } catch {
            loadFailure = HistoryLoadFailure(error)
        }
        hasLoaded = true
    }

    private func delete(_ work: @escaping @MainActor () async throws -> Int) {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                _ = try await work()
                // historyDidChange() bumps historyRevision, which reloads this list.
            } catch {
                errorMessage = HistoryErrorText.message(for: error)
            }
        }
    }

    private var deleteAppTitle: Text {
        if let appToDelete {
            Text("Delete all \(appToDelete.entryCount) notifications from \(appToDelete.displayName)?")
        } else {
            Text("Delete notifications?")
        }
    }

    private var isConfirmingAppDelete: Binding<Bool> {
        Binding(
            get: { appToDelete != nil },
            set: { if !$0 { appToDelete = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct ManageHistorySnapshot: Sendable {
    var apps: [TrackedApp]
    var totalCount: Int
}

#Preview {
    NavigationStack {
        ManageHistoryView()
    }
    .environment(AppModel.preview())
}
