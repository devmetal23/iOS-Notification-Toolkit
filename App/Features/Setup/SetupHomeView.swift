import SwiftUI
import ToolkitCore

/// The Setup tab (FR-2 to FR-5): a summary of set-up apps, then the catalog,
/// the guided flow for other apps, Health Check, Test Capture and How It Works.
struct SetupHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [SetupRoute] = []
    @State private var report = SetupReport()
    @State private var hasLoaded = false
    @State private var lastTestCaptureAt: Date?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if hasLoaded {
                    Section {
                        SetupSummary(
                            report: report,
                            isPro: model.entitlements.isPro,
                            lastTestCaptureAt: lastTestCaptureAt,
                            addApps: { path.append(.catalog) }
                        )
                    }
                }

                Section("Set Up Apps") {
                    NavigationLink(value: SetupRoute.catalog) {
                        SetupMenuLabel("Add Apps", detail: "Popular apps, ready to switch on", symbol: "square.grid.2x2")
                    }
                    NavigationLink(value: SetupRoute.otherApps) {
                        SetupMenuLabel("Other Apps", detail: "Set up any app by hand", symbol: "plus.square.dashed")
                    }
                }

                Section("Check") {
                    NavigationLink(value: SetupRoute.healthCheck) {
                        SetupMenuLabel("Health Check", detail: "When each app last logged", symbol: "stethoscope")
                    }
                    .badge(report.attentionCount)
                    NavigationLink(value: SetupRoute.testCapture) {
                        SetupMenuLabel("Test Capture", detail: "Send a test notification and watch it log", symbol: "checkmark.seal")
                    }
                }

                Section {
                    NavigationLink(value: SetupRoute.howItWorks) {
                        SetupMenuLabel("How It Works", detail: "Shortcuts automations and your privacy", symbol: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Setup")
            .navigationDestination(for: SetupRoute.self) { route in
                switch route {
                case .catalog: CatalogView()
                case .otherApps: GuidedSetupView()
                case .healthCheck: HealthCheckView()
                case .testCapture: TestCaptureView()
                case .howItWorks: HowItWorksView()
                }
            }
            .task(id: model.setupReloadKey(scenePhase)) { reload() }
        }
    }

    private func reload() {
        report = (try? model.setupReport()) ?? SetupReport()
        lastTestCaptureAt = model.settings.lastTestCaptureAt
        hasLoaded = true
    }
}

private struct SetupSummary: View {
    let report: SetupReport
    let isPro: Bool
    let lastTestCaptureAt: Date?
    let addApps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if report.appCount == 0 {
                Label("No apps set up yet", systemImage: "tray")
                    .font(.headline)
                Text("Nothing is logged until you set up an app. Add apps, then switch on their automations in Shortcuts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Add Your First Apps", action: addApps)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                Text("Want to see it work first? Try Test Capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if isPro {
                    Text("^[\(report.appCount) app](inflect: true) set up")
                        .font(.headline)
                } else {
                    Text("\(report.appCount) of \(TierLimits.free.maxApps ?? 0) apps set up on Free")
                        .font(.headline)
                }
                if report.attentionCount > 0 {
                    Label {
                        Text("^[\(report.attentionCount) app](inflect: true) to check in Health Check")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                } else {
                    Label {
                        Text("Nothing needs attention")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.subheadline)
                }
            }

            if report.isLoggingPaused {
                Label {
                    Text("Logging is paused from Control Center")
                } icon: {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                }
                .font(.subheadline)
            }

            if let lastTestCaptureAt {
                Text("Capture last tested \(lastTestCaptureAt, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SetupMenuLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

#Preview {
    SetupHomeView()
        .environment(AppModel.preview())
}
