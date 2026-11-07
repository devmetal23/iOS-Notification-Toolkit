# App Store listing: Notification Toolkit 1.0

English (U.S.) only at launch. iPhone only, iOS 27 or later.

Each field below is the exact text to paste into App Store Connect. The counts are characters as App Store Connect counts them, newlines included. Check them with:

```sh
python3 docs/app-store/check-listing.py
```

The script fails if a count is wrong, a field is over its limit, a field has non-ASCII characters, or the copy uses a banned term. Rerun it after any edit and after replacing the URL placeholders.

Rules this copy follows:

- It describes only what ships in 1.0. Per-app sounds are not mentioned.
- It says capture covers only apps the user sets up in Shortcuts, from setup onward.
- It names no other platform and no third-party app or brand.
- Pro features are marked "(Pro)" (Guideline 2.3.2).

## Name (20 / 30)

```text
Notification Toolkit
```

## Subtitle (29 / 30)

```text
Notification history & snooze
```

## Promotional text (161 / 170)

```text
Find a notification after you clear it. Set up the apps you choose in Shortcuts, and their new notifications are saved on your iPhone to search. Pro adds snooze.
```

## Description (2,890 / 4,000)

Replace `[TERMS URL]` and `[PRIVACY POLICY URL]` with the live pages, then rerun the script.

```text
Notification Toolkit keeps a searchable history of notifications from the apps you choose, stored on your iPhone. Find a code, link or message after you clear it, and snooze a notification so it comes back later.

HOW IT WORKS
Notification Toolkit works with the iOS 27 Shortcuts trigger "When I receive a notification from", which runs when an app you pick sends a notification.
1. In Notification Toolkit, add a ready-made shortcut for an app from the catalog, or follow the guided setup.
2. In Shortcuts, turn on the automation.
3. From then on, each notification from that app goes to the Log Notification action and is saved on your iPhone.

Notification Toolkit only captures apps you set up, starting from when you set them up. It can't read notifications on its own, and it can't show notifications that arrived before setup.

HISTORY
- Timeline grouped by day, with app and date filters
- Full-text search
- Copy codes, open links and call phone numbers found in a notification
- Keep history for 7 days, or with Pro for 30 days, 90 days or forever
- Delete one notification, everything from one app, or all history
- Per-app stats (Pro)

SNOOZE (PRO)
- Snooze a notification for 15 minutes, 1 hour, 3 hours, until tomorrow morning, or a custom time
- It comes back as a notification from Notification Toolkit
- See what's waiting in the Snoozed list

SETUP AND CONTROLS
- Setup health check shows whether capture is working
- Send test notification to confirm it
- Home Screen widget, with notification text hidden by default (Pro)
- Control Center toggle to pause capture (Pro)
- Shortcuts actions to search your history
- Optional Face ID lock

PRIVACY
- Your history stays on your iPhone. There is no account and no server.
- No analytics, no ads and no third-party SDKs.
- History is protected by iOS Data Protection.
- History is left out of iCloud and computer backups, so it doesn't move to a new iPhone.

FREE AND PRO
Free: up to 3 apps, 7 days of history, and search.
Pro: unlimited apps, history kept as long as you choose, snooze, the widget, the Control Center toggle, and per-app stats.

Notification Toolkit Pro (Yearly): $19.99 per year, with a 7-day free trial for eligible new subscribers.
Notification Toolkit Pro (Lifetime): $39.99, one-time purchase.

Prices are in U.S. dollars and may differ in other countries. Payment is charged to your Apple Account when you confirm the purchase. With the free trial, you're charged when the trial ends unless you cancel at least 24 hours before then. The yearly subscription renews automatically unless you turn off auto-renew at least 24 hours before the end of the current year. Renewal is charged within the 24 hours before the year ends. To manage or cancel, open Settings, tap your name, then tap Subscriptions.

Requires iOS 27 or later. iPhone only.

Terms of Use: [TERMS URL]
Privacy Policy: [PRIVACY POLICY URL]
```

## Keywords (99 / 100)

Comma-separated, no spaces. It skips words already in the name and subtitle (notification, toolkit, history, snooze), which the App Store indexes anyway. It has no app names, brand names or other companies' trademarks.

```text
alerts,log,archive,search,cleared,missed,reminder,later,widget,codes,otp,lock,screen,privacy,banner
```

## What's New in version 1.0 (222 / 4,000)

App Store Connect may not show this field for an app's first version. If it doesn't, keep this text for the 1.0.1 notes or the launch post.

```text
First release. Save notifications from the apps you set up in Shortcuts, then filter, search and delete them on your iPhone. Pro adds snooze, longer history, a Home Screen widget, a Control Center toggle and per-app stats.
```

## Support and marketing URLs

| Field | Value |
| --- | --- |
| Privacy Policy URL (required) | `[PRIVACY POLICY URL]`, hosting `privacy-policy.md` |
| Support URL (required) | `[SUPPORT URL]`, a page with `[CONTACT EMAIL]` |
| License Agreement | Leave blank to use Apple's Standard EULA (see `terms-of-use.md`) |
| Copyright | `2026 [DEVELOPER NAME]` |

## Screenshots

Upload 6.9-inch iPhone screenshots, portrait, 1320 x 2868 px. App Store Connect scales them for smaller iPhones. Use 8 screenshots in this order. Captions are 40 characters or fewer so they stay legible at small sizes.

| # | Screen to capture | Caption | Chars |
| --- | --- | --- | --- |
| 1 | History timeline for today, grouped by day, with an app filter visible | Save notifications from apps you choose | 39 |
| 2 | Search results for a word, matches highlighted | Find any saved notification | 27 |
| 3 | A notification's detail with a detected code, link and phone number and their Copy, Open and Call buttons | Copy codes, open links, call numbers | 36 |
| 4 | Snooze options: 15 min, 1 h, 3 h, tomorrow morning, custom | Snooze it for later with Pro | 28 |
| 5 | Setup catalog, with app names in plain text and the add-shortcut button | Set up each app in Shortcuts | 28 |
| 6 | Setup health check after Send test notification, showing capture working | Check that capture is working | 29 |
| 7 | Home Screen widget with text hidden, beside the Control Center pause toggle | Widget and pause toggle with Pro | 32 |
| 8 | Settings with retention choices and the delete options | Stays on your iPhone. No account. | 33 |

Rules for every screenshot:

- Use demo data only: made-up app names, senders and messages. No real people's data.
- Show no third-party app icons or logos. App names appear as plain text only. If the app shows icons in a view, use a demo mode that hides them.
- Use no brand terms from other companies, including Google feature names such as "Now Playing".
- Show only iPhone. No other phones, operating systems or platforms in images or device frames.
- Show only 1.0 features. Nothing about per-app sounds.
- Use a clean status bar.
