import SwiftUI
import ToolkitCore

/// Ready-made shared shortcuts for popular apps, searchable and grouped by
/// category (FR-2). Add opens the shortcut in Shortcuts, records the app and
/// shows how to switch its automation on.
struct CatalogView: View {
    var catalog: ShortcutCatalog = .bundled

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var query = ""
    @State private var setUpKeys: Set<AppKey> = []
    @State private var setUpCount = 0
    @State private var switchOnEntry: ShortcutCatalogEntry?
    @State private var showsPaywall = false
    /// Added once the paywall closes, if the user upgraded.
    @State private var entryAwaitingPro: ShortcutCatalogEntry?
    @State private var showsError = false
    @State private var errorText = ""

    var body: some View {
        let groups = catalog.groups(matching: query)
        List {
            if query.isEmpty {
                Section {
                    Text("Each app comes as a shared shortcut with its automation ready. Tap Add, add the shortcut in Shortcuts, then switch its automation on.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !model.entitlements.isPro {
                        FreeTierRow(setUpCount: setUpCount) {
                            entryAwaitingPro = nil
                            showsPaywall = true
                        }
                    }
                }
            }

            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        CatalogRow(
                            entry: entry,
                            isSetUp: setUpKeys.contains(entry.appKey),
                            add: { add(entry) },
                            getAgain: { openShortcut(entry) }
                        )
                    }
                } header: {
                    Text(group.category.title)
                }
            }

            Section {
                NavigationLink(value: SetupRoute.otherApps) {
                    Label("Set Up Another App", systemImage: "plus.square.dashed")
                }
            } footer: {
                Text("Any app that sends notifications can be set up by hand.")
            }
        }
        .navigationTitle("Add Apps")
        .searchable(text: $query, prompt: "Search apps")
        .task(id: model.setupReloadKey(scenePhase)) { reload() }
        .sheet(item: $switchOnEntry) { entry in
            SwitchOnSheet(entry: entry)
        }
        .sheet(isPresented: $showsPaywall, onDismiss: addAfterUpgrade) {
            PaywallView()
        }
        .setupErrorAlert(isPresented: $showsError, message: errorText)
    }

    private func reload() {
        do {
            let apps = try model.setUpApps()
            setUpKeys = Set(apps.map(\.key))
            setUpCount = apps.count
        } catch {
            // Rows fall back to Add; registering again is harmless.
            setUpKeys = []
            setUpCount = 0
        }
    }

    private func add(_ entry: ShortcutCatalogEntry) {
        do {
            if try model.needsProToAdd(displayName: entry.displayName) {
                entryAwaitingPro = entry
                showsPaywall = true
                return
            }
            try model.registerSetUpApp(displayName: entry.displayName, catalogID: entry.id)
            reload()
            openShortcut(entry)
        } catch {
            errorText = SetupErrorMessage.text(for: error)
            showsError = true
        }
    }

    /// Opens the shared shortcut and shows how to switch its automation on.
    private func openShortcut(_ entry: ShortcutCatalogEntry) {
        if entry.isPublished {
            openURL(entry.shortcutURL)
        }
        switchOnEntry = entry
    }

    private func addAfterUpgrade() {
        guard let entry = entryAwaitingPro else { return }
        entryAwaitingPro = nil
        if model.entitlements.isPro {
            add(entry)
        }
    }
}

private struct CatalogRow: View {
    let entry: ShortcutCatalogEntry
    let isSetUp: Bool
    let add: () -> Void
    let getAgain: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconWidth = 28.0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(entry.displayName)
            Spacer(minLength: 8)
            if isSetUp {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add", action: add)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Add \(entry.displayName)"))
            }
        }
        .contextMenu {
            if isSetUp {
                Button("Get the Shortcut Again", systemImage: "arrow.down.circle", action: getAgain)
            }
        }
        .accessibilityActions {
            if isSetUp {
                Button("Get the Shortcut Again", action: getAgain)
            }
        }
    }
}

/// "2 of 3 apps set up on Free" with an Upgrade button.
private struct FreeTierRow: View {
    let setUpCount: Int
    let upgrade: () -> Void

    var body: some View {
        HStack {
            Text("\(setUpCount) of \(TierLimits.free.maxApps ?? 0) apps set up on Free")
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("Upgrade", action: upgrade)
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    NavigationStack {
        CatalogView()
    }
    .environment(AppModel.preview())
}
