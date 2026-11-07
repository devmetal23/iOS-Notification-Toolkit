import Foundation
import Observation
import ToolkitCore

/// Loads the timeline and search results page by page (FR-9, FR-10).
///
/// Queries run off the main actor. Each reload bumps `generation`, so results that
/// arrive after a newer query started are dropped instead of overwriting it.
@MainActor
@Observable
final class HistoryViewModel {
    enum Phase: Hashable {
        case loading
        case loaded
        case failed(HistoryLoadFailure)
    }

    static let pageSize = 50
    static let searchDebounce: Duration = .milliseconds(200)
    /// Coalesces bursts of captures arriving from Log Notification.
    static let changeDebounce: Duration = .milliseconds(300)

    let model: AppModel

    private(set) var phase: Phase = .loading
    private(set) var entries: [NotificationEntry] = []
    private(set) var sections: [DaySection] = []
    private(set) var hasMore = false
    /// Set-up apps offered by the app filter, without Notification Toolkit itself.
    private(set) var filterApps: [TrackedApp] = []
    /// The search text the results on screen were found with.
    private(set) var displayedSearchText = ""

    var searchText = ""
    var appFilter: AppKey?
    var dateRange: HistoryDateRange = .allTime
    var customStart: Date
    var customEnd: Date

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var isLoadingMore = false
    /// The first-page query behind `entries`, reused for later pages.
    @ObservationIgnored private var loadedQuery: HistoryQuery?
    private let calendar = Calendar.autoupdatingCurrent

    init(model: AppModel) {
        self.model = model
        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        customEnd = today
        customStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -6, to: today) ?? today
    }

    // MARK: State for the view

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !displayedSearchText.isEmpty }

    var isFiltering: Bool { appFilter != nil || dateRange != .allTime }

    var filterSelection: HistoryFilterSelection {
        HistoryFilterSelection(app: appFilter, dateRange: dateRange, customStart: customStart, customEnd: customEnd)
    }

    /// The selected app's name, for the filter menu.
    var appFilterName: String? {
        guard let appFilter else { return nil }
        return filterApps.first { $0.key == appFilter }?.displayName
            ?? entries.first { $0.appKey == appFilter }?.appName
            ?? appFilter.rawValue
    }

    func clearFilters() {
        appFilter = nil
        dateRange = .allTime
    }

    func applyCustomRange(start: Date, end: Date) {
        customStart = start
        customEnd = end
        dateRange = .custom
    }

    // MARK: Loading

    /// Call when the search field changes. Waits for a pause in typing.
    func searchTextDidChange() {
        let text = trimmedSearchText
        if let loadedQuery, loadedQuery.searchText == text, loadedQuery.filter == currentFilter() {
            // Back to what's on screen (or only whitespace changed): drop any pending search.
            pendingReload?.cancel()
            pendingReload = nil
            return
        }
        scheduleReload(after: text.isEmpty ? .zero : Self.searchDebounce)
    }

    /// Reloads after `delay`, replacing any reload still waiting.
    /// - Parameter keepingLoadedCount: reload as many entries as are on screen, so a
    ///   refresh doesn't drop pages the user scrolled through.
    func scheduleReload(after delay: Duration = .zero, keepingLoadedCount: Bool = false) {
        pendingReload?.cancel()
        pendingReload = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
            }
            await reload(keepingLoadedCount: keepingLoadedCount)
        }
    }

    func reload(keepingLoadedCount: Bool = false) async {
        generation += 1
        let requestID = generation
        let filter = currentFilter()
        let text = trimmedSearchText
        var limit = Self.pageSize
        if keepingLoadedCount, let loadedQuery, loadedQuery.filter == filter, loadedQuery.searchText == text {
            limit = max(Self.pageSize, entries.count)
        }
        let query = HistoryQuery(filter: filter, searchText: text, limit: limit)
        if entries.isEmpty, phase != .loaded {
            phase = .loading
        }

        do {
            let store = try model.store()
            let result = try await HistoryStoreAccess.perform(on: store) { store in
                try FirstPage(entries: store.entries(query), trackedApps: store.trackedApps())
            }
            guard requestID == generation else { return }
            let page = result.entries
            filterApps = CaptureGate.appsCountingTowardLimit(result.trackedApps).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            entries = page
            hasMore = page.count == query.limit
            loadedQuery = query
            displayedSearchText = text
            sections = DayGrouping.sections(for: page, calendar: calendar)
            phase = .loaded
        } catch {
            guard requestID == generation else { return }
            phase = .failed(HistoryLoadFailure(error))
        }
    }

    /// Loads the next page. Call when the end of the list comes into view.
    func loadMore() async {
        guard hasMore, !isLoadingMore, let loadedQuery, let last = entries.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let requestID = generation
        var next = loadedQuery
        next.limit = Self.pageSize
        next.cursor = HistoryCursor(after: last)
        let query = next

        do {
            let store = try model.store()
            let page = try await HistoryStoreAccess.perform(on: store) { store in
                try store.entries(query)
            }
            guard requestID == generation else { return }
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: page.filter { !known.contains($0.id) })
            hasMore = page.count == query.limit
            sections = DayGrouping.sections(for: entries, calendar: calendar)
        } catch {
            guard requestID == generation else { return }
            // Stop paging; pull to refresh tries again.
            hasMore = false
        }
    }

    // MARK: Deleting

    /// Removes the row right away, then deletes it from the store. Returns the
    /// error to show if the delete failed, after restoring the list.
    func delete(_ entry: NotificationEntry) async -> (any Error)? {
        removeLocally(entry.id)
        do {
            try await HistoryDeletion.deleteEntry(entry.id, model: model)
            return nil
        } catch {
            await reload(keepingLoadedCount: true)
            return error
        }
    }

    private func removeLocally(_ id: NotificationEntry.ID) {
        entries.removeAll { $0.id == id }
        sections = DayGrouping.sections(for: entries, calendar: calendar)
    }

    private struct FirstPage: Sendable {
        var entries: [NotificationEntry]
        var trackedApps: [TrackedApp]
    }

    private func currentFilter(now: Date = .now) -> HistoryFilter {
        var apps: Set<AppKey> = []
        if let appFilter { apps.insert(appFilter) }
        return HistoryFilter(
            apps: apps,
            dateRange: dateRange.interval(now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
        )
    }
}
