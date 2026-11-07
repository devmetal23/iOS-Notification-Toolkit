# App Review notes: Notification Toolkit 1.0

Paste the block below into App Store Connect > App Review Information > Notes. The field allows 4,000 characters. Check the count with `python3 docs/app-store/check-listing.py`.

Before pasting:

- Replace `[BASE SHORTCUT URL]` and `[DEMO VIDEO URL]` and rerun the script.
- Check every screen and button name against the build you submit.
- Set "Sign-in required" to No. The app has no accounts.
- Attach both in-app purchases to this version (see "Testing Pro" below).

## App Review notes (2,967 / 4,000)

```text
WHAT THE APP DOES
Notification Toolkit keeps a searchable history of notifications on the iPhone and lets the user snooze them. It works through the iOS 27 Shortcuts trigger "When I receive a notification from", set to one app per automation. The user adds a ready-made shortcut from the in-app catalog, or follows a guided setup, and turns its automation on in Shortcuts. The automation passes each notification to the app's Log Notification action, which saves it on the device.
The app never reads notifications on its own. It captures only apps the user sets up, from setup onward. No account or sign-in is needed. Nothing leaves the device.

WHY THE APP LOOKS EMPTY AT FIRST
On a fresh install, History is empty. The app has no access to notifications until a Shortcuts automation is on, and it can't import notifications from before setup. This is expected. The steps below fill it in under two minutes.

SEE CAPTURE WORK IN UNDER TWO MINUTES
1. Open Notification Toolkit and allow notifications when asked. Send test notification and snooze need this.
2. On the same iPhone, open this link and tap Add Shortcut: [BASE SHORTCUT URL]
   This base shortcut logs notifications from Notification Toolkit itself, so no other app is needed.
3. Open Shortcuts, tap Automation, and turn on "When I receive a notification from Notification Toolkit". If Shortcuts asks how to run it, choose to run it immediately.
4. Go back to Notification Toolkit, open Setup, and tap Send test notification.
5. Open History. The test notification is at the top of today. Search for "test" to find it again.
The setup health check now shows capture as working.

DEMO VIDEO
[DEMO VIDEO URL]
It shows the steps above on an iPhone with iOS 27, then search, a detected code and link, and a snoozed notification coming back.

TESTING PRO
Pro adds unlimited apps and retention, snooze, the Home Screen widget, the Control Center toggle and per-app stats. Two in-app purchases are attached to this version:
- Notification Toolkit Pro (Yearly): auto-renewable subscription, $19.99 per year, 7-day free trial
- Notification Toolkit Pro (Lifetime): non-consumable, $39.99
Tap any Pro feature, such as Snooze, to open the purchase screen. It shows the price, length, trial, Terms of Use and Privacy Policy, and has Restore Purchases. Purchases during review use the sandbox, so there is no charge.
To try snooze after buying: in History, open the test notification, tap Snooze, and choose 15 minutes or a custom time. It moves to the Snoozed list and comes back as a notification at that time.

OTHER NOTES
- The free version allows 3 apps and 7 days of history, with search.
- Notification history is excluded from iCloud and computer backups on purpose, so it stays on this device.
- Privacy label: Data Not Collected. There is no server, analytics, advertising or third-party SDK.
- The app uses only Apple's built-in encryption. ITSAppUsesNonExemptEncryption is NO.
- Face ID lock is optional.
```

## For the team: recording the demo video

- Record on a physical iPhone with iOS 27, using screen recording. Aim for 90 seconds to 2 minutes.
- Start from a fresh install so the empty History shows.
- Follow steps 1 to 5 above. Then search, open a notification with a detected code and link, buy Pro with a sandbox account, snooze for a short custom time, show the Snoozed list, and show it coming back.
- Use demo data only. Don't show real messages, contacts or third-party app icons.
- Host it at a link that plays without sign-in and stays up until review is done. Put that link in `[DEMO VIDEO URL]`.

## For the team: testing Pro before submission

Test both products in all three places before you submit.

| Where | How | Check |
| --- | --- | --- |
| Xcode, StoreKit configuration file | Add both products with the same IDs, prices, durations and trial as App Store Connect. Run from Xcode. | Purchase, trial start, renewal, cancel, refund, restore, Pro features unlock and lock |
| Device, sandbox | Sign in with a Sandbox Apple Account on the test iPhone. | Real App Store Connect products load. Renewals are shortened in sandbox, so a year passes in minutes. |
| TestFlight | Install the review build. Purchases use the sandbox and cost nothing. | The build you submit unlocks Pro and restores it |

Also confirm:

- Both products are "Ready to Submit" and attached to version 1.0. First-time in-app purchases go to review with an app version.
- The purchase screen shows the product title, length, price, trial terms, and links to Terms of Use and the Privacy Policy (Guideline 3.1.2).
- Restore Purchases works for both products after deleting and reinstalling the app.
