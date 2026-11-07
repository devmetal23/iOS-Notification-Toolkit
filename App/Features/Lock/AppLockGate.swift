import SwiftUI
import ToolkitCore

// CONTRACT STUB — workstream W6 replaces this file. Keep the initializer.

/// Optional Face ID lock, plus a privacy cover in the app switcher (NFR-3).
struct AppLockGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}
