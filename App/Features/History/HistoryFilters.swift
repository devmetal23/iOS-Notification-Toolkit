import SwiftUI
import ToolkitCore

/// Date ranges offered by the timeline's filter menu (FR-9).
enum HistoryDateRange: Hashable, CaseIterable, Identifiable {
    case allTime
    case today
    case last7Days
    case last30Days
    case custom

    var id: Self { self }

    /// The choices listed directly in the menu; `custom` has its own button.
    static let presets: [HistoryDateRange] = [.allTime, .today, .last7Days, .last30Days]

    var title: LocalizedStringKey {
        switch self {
        case .allTime: "All Time"
        case .today: "Today"
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .custom: "Custom Range"
        }
    }

    /// The `receivedAt` range to show, or nil for all time. Ranges cover whole
    /// calendar days, ending with today.
    func interval(now: Date, calendar: Calendar, customStart: Date, customEnd: Date) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .allTime:
            return nil
        case .today:
            return Self.days(from: startOfToday, through: startOfToday, calendar: calendar)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return Self.days(from: start, through: startOfToday, calendar: calendar)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return Self.days(from: start, through: startOfToday, calendar: calendar)
        case .custom:
            return Self.days(
                from: min(customStart, customEnd),
                through: max(customStart, customEnd),
                calendar: calendar
            )
        }
    }

    /// From the start of `first`'s day to the last instant of `last`'s day.
    private static func days(from first: Date, through last: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: last)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let end = max(start, nextDay.addingTimeInterval(-0.001))
        return DateInterval(start: start, end: end)
    }
}

/// Everything the filter menu controls, compared to decide when to reload.
struct HistoryFilterSelection: Hashable {
    var app: AppKey?
    var dateRange: HistoryDateRange
    var customStart: Date
    var customEnd: Date
}

/// Picks the first and last day of a custom date range.
struct HistoryCustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    private let onApply: (Date, Date) -> Void

    init(start: Date, end: Date, onApply: @escaping (Date, Date) -> Void) {
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, in: ...Date.now, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start...max(start, Date.now), displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(start, max(start, end))
                        dismiss()
                    }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Custom range") {
    HistoryCustomRangeSheet(
        start: Date.now.addingTimeInterval(-6 * 86_400),
        end: Date.now,
        onApply: { _, _ in }
    )
}
