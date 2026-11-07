import SwiftUI
import ToolkitCore

/// Timeline grouped by day, with app/date filters and full-text search (FR-9, FR-10).
/// Opens `model.entryToOpen` when set, then clears it.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HistoryScreen(model: model)
    }
}

private struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: HistoryViewModel
    @State private var path: [NotificationEntry] = []
    /// The row whose Snooze swipe action was tapped; drives the snooze dialog.
    @State private var snoozeTarget: NotificationEntry?
    @State private var showsCustomRange = false
    @State private var errorMessage: String?
    @State private var showsMissingEntry = false

    init(model: AppModel) {
        _viewModel = State(initialValue: HistoryViewModel(model: model))
    }

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle("History")
                .navigationDestination(for: NotificationEntry.self) { entry in
                    HistoryEntryDetailView(entry: entry)
                }
                .searchable(text: $viewModel.searchText, prompt: Text("Search Notifications"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }
                }
        }
        .task {
            await viewModel.reload(keepingLoadedCount: true)
        }
        .task {
            // Captures from Log Notification and background cleanup.
            for await _ in HistoryChangeNotifier.changes() {
                viewModel.scheduleReload(after: HistoryViewModel.changeDebounce, keepingLoadedCount: true)
            }
        }
        .onChange(of: viewModel.searchText) {
            viewModel.searchTextDidChange()
        }
        .onChange(of: viewModel.filterSelection) {
            viewModel.scheduleReload()
        }
        .onChange(of: model.historyRevision) {
            viewModel.scheduleReload(keepingLoadedCount: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.scheduleReload(keepingLoadedCount: true)
            }
        }
        .onChange(of: model.entryToOpen, initial: true) { _, id in
            if let id {
                open(id)
            }
        }
        .sheet(isPresented: $showsCustomRange) {
            HistoryCustomRangeSheet(start: viewModel.customStart, end: viewModel.customEnd) { start, end in
                viewModel.applyCustomRange(start: start, end: end)
            }
        }
        .alert("Couldn't Delete", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Notification Not Found", isPresented: $showsMissingEntry) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It may have been deleted or removed by automatic cleanup.")
        }
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(for: entry)
                    }
                } header: {
                    HistoryDayHeader(day: section.day)
                }
            }
            if viewModel.hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Loading more notifications")
                    // Re-runs after each page, in case the new rows didn't fill the screen.
                    .task(id: viewModel.entries.last?.id) {
                        await viewModel.loadMore()
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.reload(keepingLoadedCount: true)
        }
        .overlay {
            if viewModel.entries.isEmpty {
                emptyState
            }
        }
        .confirmationDialog(
            "Snooze",
            isPresented: isShowingSnoozeDialog,
            titleVisibility: .visible,
            presenting: snoozeTarget
        ) { entry in
            ForEach(SnoozeOption.presets) { option in
                Button(option.displayTitle(morningHour: model.settings.morningHour)) {
                    Task { await SnoozeFlow.choose(option, for: entry, model: model) }
                }
            }
            Button("Choose Time…") {
                SnoozeFlow.chooseCustomTime(for: entry, model: model)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Get “\(entry.title.isEmpty ? entry.appName : entry.title)” again later as a notification.")
        }
    }

    private func row(for entry: NotificationEntry) -> some View {
        NavigationLink(value: entry) {
            HistoryEntryRow(entry: entry)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(entry)
            }
            Button("Snooze", systemImage: "moon.zzz") {
                snoozeTarget = entry
            }
            .tint(.indigo)
        }
        .contextMenu {
            SnoozeMenu(entry: entry)
            Button("Copy Text", systemImage: "doc.on.doc") {
                HistoryPasteboard.copy(entry.historyFullText)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(entry)
            }
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
        case .failed(let failure):
            failedState(failure)
        case .loaded:
            if viewModel.isSearching {
                if viewModel.isFiltering {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing matches “\(viewModel.displayedSearchText)” with the current filters.")
                    } actions: {
                        Button("Clear Filters") { viewModel.clearFilters() }
                    }
                } else {
                    ContentUnavailableView.search(text: viewModel.displayedSearchText)
                }
            } else if viewModel.isFiltering {
                ContentUnavailableView {
                    Label("No Matching Notifications", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No notifications match the app and date you picked.")
                } actions: {
                    Button("Clear Filters") { viewModel.clearFilters() }
                }
            } else if viewModel.filterApps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps Set Up", systemImage: "app.badge")
                } description: {
                    Text("Turn on an automation for each app whose notifications you want to keep. New notifications from those apps will appear here.")
                } actions: {
                    Button("Set Up Apps") { model.selectedTab = .setup }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("No Notifications Yet", systemImage: "tray")
                } description: {
                    Text("Notifications from the apps you set up will appear here as they arrive.")
                }
            }
        }
    }

    @ViewBuilder
    private func failedState(_ failure: HistoryLoadFailure) -> some View {
        switch failure {
        case .protectedDataUnavailable:
            ContentUnavailableView {
                Label("History Is Locked", systemImage: "lock")
            } description: {
                Text("Your history is protected until you unlock your iPhone for the first time after it restarts.")
            } actions: {
                Button("Try Again") { tryAgain() }
            }
        case .other:
            ContentUnavailableView {
                Label("Couldn't Load History", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Something went wrong while reading your history.")
            } actions: {
                Button("Try Again") { tryAgain() }
            }
        }
    }

    // MARK: Filters

    private var filterMenu: some View {
        Menu {
            Picker(selection: $viewModel.appFilter) {
                Text("All Apps").tag(AppKey?.none)
                ForEach(viewModel.filterApps) { app in
                    Text(app.displayName).tag(AppKey?.some(app.key))
                }
                if let selected = viewModel.appFilter,
                   !viewModel.filterApps.contains(where: { $0.key == selected }) {
                    // An app that's no longer set up but is still selected.
                    Text(viewModel.appFilterName ?? selected.rawValue).tag(AppKey?.some(selected))
                }
            } label: {
                Label("App", systemImage: "app")
            }
            .pickerStyle(.menu)

            Picker(selection: $viewModel.dateRange) {
                ForEach(HistoryDateRange.presets) { range in
                    Text(range.title).tag(range)
                }
                if viewModel.dateRange == .custom {
                    Text(customRangeTitle).tag(HistoryDateRange.custom)
                }
            } label: {
                Label("Date", systemImage: "calendar")
            }
            .pickerStyle(.menu)

            Button("Custom Range…", systemImage: "calendar.badge.clock") {
                showsCustomRange = true
            }

            if viewModel.isFiltering {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    viewModel.clearFilters()
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: viewModel.isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue(viewModel.isFiltering ? Text("Filters on") : Text("Filters off"))
    }

    private var customRangeTitle: String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let start = min(viewModel.customStart, viewModel.customEnd).formatted(style)
        let end = max(viewModel.customStart, viewModel.customEnd).formatted(style)
        return start == end ? start : String(localized: "\(start) – \(end)")
    }

    // MARK: Actions

    private func delete(_ entry: NotificationEntry) {
        Task {
            if let error = await viewModel.delete(entry) {
                errorMessage = HistoryErrorText.message(for: error)
            }
        }
    }

    private func tryAgain() {
        Task { await viewModel.reload() }
    }

    /// Shows an entry requested from elsewhere, e.g. a snooze that came back.
    private func open(_ id: NotificationEntry.ID) {
        model.entryToOpen = nil
        do {
            if let entry = try model.store().entry(id: id) {
                path = [entry]
            } else {
                showsMissingEntry = true
            }
        } catch {
            showsMissingEntry = true
        }
    }

    private var isShowingSnoozeDialog: Binding<Bool> {
        Binding(
            get: { snoozeTarget != nil },
            set: { if !$0 { snoozeTarget = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

/// "Today", "Yesterday", or the weekday and date.
private struct HistoryDayHeader: View {
    let day: Date

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        Group {
            if calendar.isDateInToday(day) {
                Text("Today")
            } else if calendar.isDateInYesterday(day) {
                Text("Yesterday")
            } else if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
                Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
            } else {
                Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    HistoryView()
        .environment(AppModel.preview())
}
