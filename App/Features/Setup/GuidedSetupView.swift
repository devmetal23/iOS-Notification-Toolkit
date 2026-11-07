import SwiftUI
import ToolkitCore

/// Set up any app that isn't in the catalog (FR-3): numbered steps for adding
/// its notification trigger with Log Notification, then "Which app did you add?".
///
/// The Shortcuts labels quoted here follow the iOS 27 betas and still need
/// confirming on a device (spikes S5, S6). Re-check them every June beta; see
/// docs/shortcuts.md.
struct GuidedSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var appName = ""
    @State private var outcome: Outcome?
    @State private var showsPaywall = false
    @State private var showsError = false
    @State private var errorText = ""
    @FocusState private var isNameFocused: Bool

    private enum Outcome: Equatable {
        case added(String)
        case alreadySetUp(String)
        case ownApp
    }

    var body: some View {
        List {
            Section {
                Text("Any app that sends notifications can be logged. In Shortcuts, add an automation for it like the ones in the base shortcut, then tell Notification Toolkit which app you added.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                NumberedSteps(steps: Self.steps)
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    openURL(ShortcutsAppLink.url)
                }
            } header: {
                Text("In Shortcuts")
            }

            Section {
                ForEach(Array(Self.fieldMappings.enumerated()), id: \.offset) { _, mapping in
                    LabeledContent {
                        Text(mapping.source)
                    } label: {
                        Text(mapping.field)
                            .bold()
                    }
                }
            } header: {
                Text("Log Notification Fields")
            } footer: {
                Text("For each field except App, tap it and choose the matching detail of the Notification variable.")
            }

            Section {
                TextField("App name", text: $appName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit(add)
                Button("Add App", systemImage: "plus.circle", action: add)
                    .disabled(trimmedName.isEmpty)
            } header: {
                Text("Which App Did You Add?")
            } footer: {
                if model.entitlements.isPro {
                    Text("Type the name exactly as you typed it in the App field.")
                } else {
                    Text("Type the name exactly as you typed it in the App field. Free includes 3 apps.")
                }
            }

            if let outcome {
                Section {
                    outcomeView(outcome)
                }
            }
        }
        .navigationTitle("Other Apps")
        .sheet(isPresented: $showsPaywall, onDismiss: addAfterUpgrade) {
            PaywallView()
        }
        .setupErrorAlert(isPresented: $showsError, message: errorText)
    }

    @ViewBuilder
    private func outcomeView(_ outcome: Outcome) -> some View {
        switch outcome {
        case .added(let name):
            Label {
                Text("\(name) is set up. Its next notification will appear in History.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .alreadySetUp(let name):
            Label {
                Text("\(name) is already set up.")
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        case .ownApp:
            Label {
                Text("Notification Toolkit is covered by the base shortcut. Get it from Test Capture.")
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedName: String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        let key = AppKey(appName: name)
        guard key != .ownApp else {
            outcome = .ownApp
            return
        }
        do {
            if try model.setUpApps().contains(where: { $0.key == key }) {
                outcome = .alreadySetUp(name)
                return
            }
            if try model.needsProToAdd(displayName: name) {
                showsPaywall = true
                return
            }
            try model.registerSetUpApp(displayName: name, catalogID: nil)
            outcome = .added(name)
            appName = ""
            isNameFocused = false
        } catch {
            errorText = SetupErrorMessage.text(for: error)
            showsError = true
        }
    }

    private func addAfterUpgrade() {
        if model.entitlements.isPro, !trimmedName.isEmpty {
            add()
        }
    }

    // MARK: Content

    private static let steps = [
        SetupStep(
            symbol: "arrow.up.forward.app",
            title: "Open Shortcuts and tap Automation",
            detail: nil
        ),
        SetupStep(
            symbol: "plus.circle",
            title: "Create a new automation",
            detail: "Tap the + button."
        ),
        SetupStep(
            symbol: "bell.badge",
            title: "Choose “When I receive a notification from”",
            detail: "Pick the app. Leave the title, subtitle and message filters empty to log all of its notifications."
        ),
        SetupStep(
            symbol: "text.badge.plus",
            title: "Add the Log Notification action",
            detail: "Start a new blank automation, tap Add Action, and search for Log Notification."
        ),
        SetupStep(
            symbol: "list.bullet.rectangle",
            title: "Fill in its fields",
            detail: "Type the app's name in App, exactly. Fill the other fields from the Notification variable, as listed below."
        ),
        SetupStep(
            symbol: "bolt.circle",
            title: "Choose Run Immediately",
            detail: "So it runs every time without asking. If you see Notify When Run, turn it off."
        ),
        SetupStep(
            symbol: "checkmark.circle",
            title: "Tap Done",
            detail: "Repeat these steps for each app you want to keep."
        ),
    ]

    private struct FieldMapping {
        let field: LocalizedStringResource
        let source: LocalizedStringResource
    }

    // Field names are Log Notification's parameter titles; sources are the
    // Notification variable's details. Both need confirming on iOS 27 (S6).
    private static let fieldMappings = [
        FieldMapping(field: "App", source: "Type the app's name"),
        FieldMapping(field: "Title", source: "Notification › Title"),
        FieldMapping(field: "Subtitle", source: "Notification › Subtitle"),
        FieldMapping(field: "Message", source: "Notification › Message"),
        FieldMapping(field: "Date", source: "Notification › Date"),
        FieldMapping(field: "Time Sensitive", source: "Notification › Is Time Sensitive"),
    ]
}

#Preview {
    NavigationStack {
        GuidedSetupView()
    }
    .environment(AppModel.preview())
}
