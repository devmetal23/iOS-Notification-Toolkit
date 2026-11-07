import SwiftUI

/// Picks a custom snooze time (FR-14). `SnoozeFlow` presents it with UIKit.
struct SnoozeTimePicker: View {
    let title: String
    let confirmTitle: String
    let minimumDate: Date
    let onCancel: @MainActor @Sendable () -> Void
    let onConfirm: @MainActor @Sendable (Date) -> Void

    @State private var date: Date

    init(
        title: String,
        confirmTitle: String,
        initialDate: Date?,
        now: Date = Date(),
        onCancel: @escaping @MainActor @Sendable () -> Void,
        onConfirm: @escaping @MainActor @Sendable (Date) -> Void
    ) {
        let minimum = Self.earliestDate(after: now)
        self.title = title
        self.confirmTitle = confirmTitle
        self.minimumDate = minimum
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        let suggested = initialDate ?? Self.wholeMinute(now.addingTimeInterval(60 * 60))
        _date = State(initialValue: max(suggested, minimum))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Snooze until",
                        selection: $date,
                        in: minimumDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("Comes back \(SnoozeFormatting.fireTimeText(date)).")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { onConfirm(Self.wholeMinute(date)) }
                }
            }
        }
    }

    /// The earliest time offered: a whole minute at least 90 seconds from now.
    static func earliestDate(after now: Date) -> Date {
        wholeMinute(now.addingTimeInterval(120))
    }

    /// Drops seconds, so a custom snooze fires on the minute the user picked.
    static func wholeMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }
}

#Preview {
    SnoozeTimePicker(
        title: "Snooze Until",
        confirmTitle: "Snooze",
        initialDate: nil,
        onCancel: {},
        onConfirm: { _ in }
    )
}
