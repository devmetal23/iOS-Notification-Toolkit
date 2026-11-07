import SwiftUI
import ToolkitCore

@main
struct NotificationToolkitApp: App {
    @State private var model = AppModel.live()

    init() {
        NotificationDelegate.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .backgroundTask(.appRefresh(RetentionTask.identifier)) {
            await RetentionTask.run()
        }
    }
}
