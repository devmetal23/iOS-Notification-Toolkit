# Architecture

Notification Toolkit captures notifications through Shortcuts automations the user switches on. Each automation runs the app's **Log Notification** App Intent, which stores the notification in an encrypted SQLite database in the App Group container. The app, its intents and the widget extension all read that database.

```
Source app ─► Automation (one trigger per app) ─► Log Notification intent ─► CaptureService ─► SQLite + FTS5 (App Group)
                         └─► Play Sound (in the shortcut)                                          │
                                                        History · Search · Snooze · Widgets · Control ◄┘
```

## Layout

| Path | What | Builds on Linux |
| --- | --- | --- |
| `Packages/ToolkitCore` | Models, SQLite store, capture pipeline, pure logic, shared settings | Yes (`swift test`) |
| `Shared/` | App Group access and widget refresh, compiled into the app and the widget extension | No |
| `App/` | SwiftUI app and its App Intents | No |
| `Widgets/` | Home Screen widget and Control Center toggle | No |
| `SpikeHarness/` | Throwaway app for validation spikes S1–S6 | No |
| `Config/` | xcconfig, StoreKit configuration | — |
| `project.yml` | XcodeGen spec; run `xcodegen generate` to get the Xcode project | — |

## Rules every target follows

- **Privacy (NFR-1).** No networking, no analytics, no third-party dependencies. Notification text never leaves the device, and the database directory is excluded from device backups.
- **Platform.** iOS 27 deployment target, iPhone only, Swift 6 language mode with approachable concurrency (no default MainActor isolation). Views, view models and `AppModel` are `@MainActor`. Types shared with intents or widgets are `Sendable`.
- **Store access.** Always through `NotificationStoring`. In the app, `try model.store()`; in intents and widgets, `try AppGroup.store()`. Every store call is a short transaction; never hold one open across an `await`.
- **After changing history** in the app, call `model.historyDidChange()`. After a capture, call `WidgetRefresher.captureDidStore(settings:)`.
- **Deletes cancel snoozes.** Every `DeletionResult` goes to `model.snoozes.cancel(requestIdentifiers:)`.
- **Pro-only:** snooze, widgets, controls, stats, retention beyond 7 days, more than 3 apps. Check `model.entitlements.isPro` (or `settings.isPro` outside the app) and present `PaywallView()` as a sheet.
- **Navigation hooks.** `model.selectedTab` switches tabs; `model.entryToOpen` asks History to open an entry (set when a returned snooze is tapped).
- **Snoozing from a list row** uses a swipe `Button` plus a list-level `confirmationDialog` calling `SnoozeFlow`; `SnoozeMenu` is for context menus and toolbars only.
- **Notification Toolkit's own captures** (the test notification) never count as a set-up app: use `CaptureGate.appsCountingTowardLimit(_:)` when listing or counting tracked apps.
- **Strings (NFR-9).** User-facing text uses `LocalizedStringKey` in SwiftUI or `String(localized:)` elsewhere, so Xcode extracts it into `App/Resources/Localizable.xcstrings`.
- **Accessibility (NFR-8).** Dynamic Type (text styles, never fixed point sizes), a VoiceOver label on every control and icon-only button, semantic colors so dark mode works.
- **Previews.** Use `AppModel.preview()`, which has an in-memory store with sample data.
- **Lock Screen privacy (NFR-3).** Widgets hide notification text unless `settings.showsTextInWidgets` is on.

## Capture pipeline

`CaptureService.capture(_:)` in ToolkitCore runs these steps in order:

1. Logging paused (FR-18) → `.paused`.
2. A capture from Notification Toolkit itself while no test notification is expected → `.ignoredOwnNotification`. This keeps snoozes that come back from being logged twice. Send test notification (FR-5) sets `settings.testNotificationExpectedUntil`.
3. Free tier beyond 3 apps → record the blocked capture, `.blockedByAppLimit`.
4. Insert with 60-second dedupe on app, title and body (FR-8) → `.stored` or `.duplicate`.
5. At most once per 24 hours, apply `settings.effectiveRetention` (FR-12).

The Log Notification intent is a thin wrapper around it and must finish in under a second without opening the app (NFR-4).

## Database

SQLite in `AppGroup.databaseURL`, WAL mode, file protection Complete Until First User Authentication (NFR-2), directory excluded from backups. Tables: `entries`, `entries_fts` (FTS5, external content, kept in sync by triggers), `apps` (tracked apps), `snoozes`. Schema changes go through numbered migrations tracked in `PRAGMA user_version`.

## Workstreams

v1 is built in parallel workstreams against the contracts above. Files marked `CONTRACT STUB` keep their public signatures; their owner replaces the bodies.

| ID | Owns | Requirements |
| --- | --- | --- |
| W1 | `ToolkitCore/Storage`, `ToolkitCore/Capture`, their tests | FR-6, FR-8, FR-10, FR-12, FR-13, NFR-2, NFR-5, NFR-6, NFR-7 |
| W2 | `ToolkitCore/Logic` (except `Tier.swift`), their tests | FR-4, FR-9, FR-11, FR-14 |
| W3 | `SpikeHarness/`, `docs/spikes.md` | Spikes S1–S6 |
| W4 | `App/Intents`, `App/Features/History`, `App/Features/Settings`, `App/Features/Stats`, `Shared/HistoryChangeNotifier.swift` | FR-6, FR-9 to FR-13, FR-19, FR-20 |
| W5 | `App/Features/Onboarding`, `App/Features/Setup`, `App/Resources/ShortcutCatalog.json`, `docs/shortcuts.md` | FR-1 to FR-5 |
| W6 | `App/Features/Snooze`, `App/Features/Lock`, `App/Features/Paywall`, `Config/NotificationToolkit.storekit` | FR-14, FR-15, NFR-3, Monetization |
| W7 | `Widgets/`, `Shared/LoggingControl.swift`, `App/Resources/PrivacyInfo.xcprivacy`, `.github/workflows` | FR-17, FR-18, CI |
| W8 | `docs/app-store/` | App Store compliance and legal |
