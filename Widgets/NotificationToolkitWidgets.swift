import SwiftUI
import WidgetKit

/// Everything the widget extension offers: the Today widget (FR-17) and the
/// Control Center logging toggle (FR-18). Both are Pro features.
@main
struct NotificationToolkitWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LoggingControlWidget()
    }
}
