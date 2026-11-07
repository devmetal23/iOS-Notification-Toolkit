import Foundation
import Synchronization
import ToolkitCore

/// The App Group container shared by the app, its intents and the widget extension.
/// Compiled into every target that reads or writes history.
enum AppGroup {
    /// Set per build in Config/Base.xcconfig and written to each target's Info.plist.
    static let identifier: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
        ?? "group.com.devmetal23.notificationtoolkit"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            preconditionFailure("App Group \(identifier) is missing from this target's entitlements")
        }
        return url
    }

    static var databaseURL: URL {
        containerURL.appending(path: "Library/Application Support/NotificationToolkit/History.sqlite")
    }

    static let settings: SharedSettings = {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            preconditionFailure("App Group \(identifier) is missing from this target's entitlements")
        }
        return SharedSettings(defaults: defaults)
    }()

    private static let cachedStore = Mutex<SQLiteNotificationStore?>(nil)

    /// The shared store, opened on first use and reused after that.
    /// Throws before the first unlock after a restart (NFR-2); call again later.
    static func store() throws -> SQLiteNotificationStore {
        try cachedStore.withLock { slot in
            if let existing = slot { return existing }
            let store = try SQLiteNotificationStore(url: databaseURL)
            slot = store
            return store
        }
    }
}
