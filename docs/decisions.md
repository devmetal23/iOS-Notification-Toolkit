# Decisions

Product and engineering decisions made while building v1, newest first. The [requirements spec](https://claude.ai/artifact/8qL6t3P3nnd2vp1i53PTyX) is the source for everything not listed here.

| Date | Decision | Why |
| --- | --- | --- |
| 2026-11-07 | No setup telemetry in v1. Setup completion is measured with TestFlight testers and the in-app health check. | The spec's two setup metrics need data from users' phones, which would break "no server" and the "Data Not Collected" privacy label. |
| 2026-11-07 | Keep bundle ID prefix `com.devmetal23` and the App Store name "Notification Toolkit". | Product IDs and the App Group derive from the prefix, and it's hard to change once App Store Connect products exist. |
| 2026-11-07 | CI runs on pull requests, pushes to `main` and manual runs only. | GitHub Actions minutes are limited; macOS minutes bill at 10x. |
| 2026-09-28 | Notification history is excluded from iCloud and computer backups. | Keeps "notification content never leaves your iPhone" literally true. History doesn't move to a new phone; the privacy policy says so. |
| 2026-09-28 | Pro launches with both products: $19.99/year with a 7-day free trial, and $39.99 lifetime. Revisit after 60 days of conversion data. | No server costs make a lifetime option safe; data will show which to keep. |
| 2026-09-28 | CI builds the core package on Linux and the app on macOS. | No local Xcode in cloud sessions; CI is the compile check. |
| 2026-09-28 | v1 builds every Must and Should, plus the cheap Coulds (stats, Shortcuts actions), with a spike harness first. Per-app sounds (FR-16) wait for spike S3. | Code is cheap to write; the spikes still gate shipping. |
| 2026-09-28 | Notification Toolkit's own notifications are captured only while a test notification is expected, and never count as a set-up app. | Snoozes coming back must not be logged twice, and the test must not use a free-tier slot. |
| 2026-09-28 | The Control Center toggle shows "Requires Pro" for free users and ignores their taps. | App Intents reads `openAppWhenRun` as static metadata, so it can't vary by tier. |
