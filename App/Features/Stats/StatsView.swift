import Charts
import SwiftUI
import ToolkitCore

/// Which apps notify the most, by day and by week (FR-19). Pro only; free users
/// see what it offers and an upgrade button.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsPaywall = false

    var body: some View {
        Group {
            if model.entitlements.isPro {
                StatsContentView()
            } else {
                ContentUnavailableView {
                    Label("Stats Are Part of Pro", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("See which apps notify you most, day by day and week by week, and which are the noisiest today.")
                } actions: {
                    Button("Upgrade to Pro") { showsPaywall = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
                .environment(model)
        }
    }
}

/// Loads the counts off the main actor and reloads when history changes.
private struct StatsContentView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: StatsSummary?
    @State private var failure: HistoryLoadFailure?

    var body: some View {
        Group {
            if let summary {
                StatsSummaryView(summary: summary)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't Load Stats", systemImage: "exclamationmark.triangle")
                } description: {
                    switch failure {
                    case .protectedDataUnavailable:
                        Text("Your history is protected until you unlock your iPhone for the first time after it restarts.")
                    case .other:
                        Text("Something went wrong while reading your history.")
                    }
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: model.historyRevision) {
            await load()
        }
    }

    private func load() async {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let interval = StatsSummary.interval(now: now, calendar: calendar)
        do {
            let store = try model.store()
            summary = try await HistoryStoreAccess.perform(on: store) { store in
                let counts = try store.dailyCounts(in: interval, calendar: calendar)
                return StatsSummary(counts: counts, now: now, calendar: calendar)
            }
            failure = nil
        } catch {
            failure = HistoryLoadFailure(error)
        }
    }
}

/// The charts and lists for a loaded summary.
struct StatsSummaryView: View {
    enum Span: Hashable {
        case days, weeks
    }

    let summary: StatsSummary

    @State private var span: Span = .days
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 240

    /// Fixed hue order, never cycled. Checked for color-blind separation between
    /// neighbors in light and dark mode; "Other" is always gray.
    private static let palette: [Color] = [.blue, .green, .purple, .orange, .teal, .pink]

    private var period: StatsSummary.Period {
        span == .days ? summary.days : summary.weeks
    }

    private var periodTitle: LocalizedStringKey {
        span == .days ? "Last 7 Days" : "Last 8 Weeks"
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $span) {
                    Text("7 Days").tag(Span.days)
                    Text("8 Weeks").tag(Span.weeks)
                }
                .pickerStyle(.segmented)

                if period.total == 0 {
                    Text("No notifications were saved in this period.")
                        .foregroundStyle(.secondary)
                } else {
                    chart
                        .frame(height: chartHeight)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("Notifications per App")
            } footer: {
                if period.total > 0 {
                    Text("\(period.total) notifications in total.")
                }
            }

            if !period.apps.isEmpty {
                // The chart's data as a table, for VoiceOver and exact numbers.
                Section {
                    ForEach(period.apps) { app in
                        countRow(name: app.appName, count: app.count)
                    }
                } header: {
                    Text(periodTitle)
                }
            }

            Section {
                if summary.today.isEmpty {
                    Text("Nothing saved yet today.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.today.prefix(10)) { app in
                        countRow(name: app.appName, count: app.count)
                    }
                }
            } header: {
                Text("Noisiest Apps Today")
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch span {
        case .days:
            Chart(period.bars) { bar in
                BarMark(
                    x: .value("Day", bar.start, unit: .day),
                    y: .value("Notifications", bar.count)
                )
                .foregroundStyle(by: .value("App", bar.series))
                .accessibilityLabel(Text(bar.series))
                .accessibilityValue(Text("\(bar.count) notifications on \(bar.start.formatted(.dateTime.weekday(.wide).month().day()))"))
            }
            .chartXScale(domain: period.domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .modifier(StatsChartStyle(series: summary.series, hasOther: summary.hasOtherSeries, palette: Self.palette))
        case .weeks:
            Chart(period.bars) { bar in
                BarMark(
                    x: .value("Week", bar.start, unit: .weekOfYear),
                    y: .value("Notifications", bar.count)
                )
                .foregroundStyle(by: .value("App", bar.series))
                .accessibilityLabel(Text(bar.series))
                .accessibilityValue(Text("\(bar.count) notifications in the week of \(bar.start.formatted(.dateTime.month().day()))"))
            }
            .chartXScale(domain: period.domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .modifier(StatsChartStyle(series: summary.series, hasOther: summary.hasOtherSeries, palette: Self.palette))
        }
    }

    private func countRow(name: String, count: Int) -> some View {
        LabeledContent {
            Text(count, format: .number)
                .monospacedDigit()
        } label: {
            Text(name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(count) notifications"))
    }
}

/// Colors that follow the app, not its rank, plus a legend under the chart.
private struct StatsChartStyle: ViewModifier {
    let series: [String]
    let hasOther: Bool
    let palette: [Color]

    func body(content: Content) -> some View {
        content
            .chartForegroundStyleScale(domain: series, range: colors)
            .chartLegend(position: .bottom, alignment: .leading)
    }

    private var colors: [Color] {
        series.indices.map { index in
            if hasOther && index == series.count - 1 { return Color.gray }
            return palette[index % palette.count]
        }
    }
}

#Preview("Pro") {
    NavigationStack {
        StatsSummaryView(summary: .preview())
            .navigationTitle("Stats")
    }
}

#Preview("Free") {
    NavigationStack {
        StatsView()
    }
    .environment(AppModel.preview())
}
