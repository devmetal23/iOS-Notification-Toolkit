import SwiftUI
import ToolkitCore

/// Shown after Add (FR-2): shared shortcuts bring their automation in switched
/// off, so this walks the user through turning it on in Shortcuts.
struct SwitchOnSheet: View {
    let entry: ShortcutCatalogEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(introduction)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !entry.isPublished {
                    Section {
                        Label("This shortcut's link hasn't been published yet, so Shortcuts wasn't opened.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Maintainers: replace the placeholder link in ShortcutCatalog.json. See docs/shortcuts.md.")
                    }
                }

                Section("In Shortcuts") {
                    NumberedSteps(steps: steps)
                }

                Section {
                    Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                        openURL(ShortcutsAppLink.url)
                    }
                    if entry.isPublished {
                        Button("Get the Shortcut Again", systemImage: "arrow.down.circle") {
                            openURL(entry.shortcutURL)
                        }
                    }
                } footer: {
                    Text("Logging starts once the automation is on. Notifications that arrived earlier can't be added.")
                }
            }
            .navigationTitle("Now Switch It On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var introduction: LocalizedStringResource {
        if entry.isBaseShortcut {
            "The base shortcut's automation logs Notification Toolkit's own test notification. It arrives switched off: turn it on so Test Capture can work."
        } else if entry.requiresAppSelection {
            "Automations in shared shortcuts arrive switched off. Choose your app and turn this one on, and its notifications are logged from then on."
        } else {
            "Automations in shared shortcuts arrive switched off. Turn this one on, and \(entry.displayName) notifications are logged from then on."
        }
    }

    private var steps: [SetupStep] {
        var steps = [
            SetupStep(
                symbol: "arrow.down.circle",
                title: "Add the shortcut",
                detail: "If Shortcuts asks, tap Add Shortcut."
            ),
            SetupStep(
                symbol: "arrow.up.forward.app",
                title: "Tap Automation",
                detail: "It's at the bottom of the Shortcuts app."
            ),
            SetupStep(
                symbol: "bell.badge",
                title: "Tap the new automation",
                detail: "It starts with “When I receive a notification from”."
            ),
        ]
        if entry.requiresAppSelection {
            steps.append(SetupStep(
                symbol: "hand.tap",
                title: "Choose your app",
                detail: "Tap the app in the trigger and pick the one to log, such as your bank's app."
            ))
        }
        steps.append(SetupStep(
            symbol: "switch.2",
            title: "Switch it on",
            detail: "Choose Run Immediately, so it runs every time without asking you."
        ))
        steps.append(SetupStep(
            symbol: "checkmark.circle",
            title: "Tap Done",
            detail: nil
        ))
        return steps
    }
}

#Preview {
    Text("Catalog")
        .sheet(isPresented: .constant(true)) {
            SwitchOnSheet(entry: ShortcutCatalogEntry(
                id: "whatsapp",
                displayName: "WhatsApp",
                category: .messaging,
                shortcutURL: URL(string: "https://www.icloud.com/shortcuts/REPLACE-whatsapp")!,
                symbol: "bubble.left.and.bubble.right"
            ))
        }
}
