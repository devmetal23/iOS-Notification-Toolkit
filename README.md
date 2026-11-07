# Notification Toolkit

A searchable, on-device history of your iPhone notifications, plus snooze and per-app alert sounds.

Notification Toolkit runs on iOS 27's Shortcuts notification trigger ("When I receive a notification from [app]"). Each automation the user switches on hands the notification to the app's **Log Notification** App Intent, which saves it to an encrypted store on the device. Nothing leaves the phone.

- Requirements spec: [Notification Toolkit Requirements](https://claude.ai/artifact/8qL6t3P3nnd2vp1i53PTyX)
- Architecture and workstreams: [docs/architecture.md](docs/architecture.md)
- Validation spikes: [docs/spikes.md](docs/spikes.md)
- Platform: iOS 27 and later, iPhone only for v1

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Create `Config/Local.local.xcconfig` (gitignored) with your team and, if needed, your own bundle ID prefix:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BUNDLE_ID_PREFIX = com.yourcompany
   ```
2. Generate the project and open it:
   ```sh
   brew install xcodegen
   xcodegen generate
   open NotificationToolkit.xcodeproj
   ```
3. Run the `NotificationToolkit` scheme on a device running iOS 27. Its run action uses `Config/NotificationToolkit.storekit` for local purchase testing.

The `.xcodeproj`, Info.plist files and entitlements are generated from `project.yml`; edit that file, not the generated ones.

## Test

The storage and logic layer is a plain Swift package that builds on macOS and Linux:

```sh
swift test --package-path Packages/ToolkitCore
```

## Status

Pre-v1. Validation spikes S1–S6 must pass on a real iPhone before the MVP ships; build and run the `SpikeHarness` scheme for them.
