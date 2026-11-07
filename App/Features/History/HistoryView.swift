import SwiftUI
import ToolkitCore

// CONTRACT STUB — workstream W4 replaces this file.

/// Timeline grouped by day, with app/date filters and full-text search (FR-9, FR-10).
/// Opens `model.entryToOpen` when set, then clears it.
struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("History", systemImage: "clock.arrow.circlepath")
                .navigationTitle("History")
        }
    }
}
