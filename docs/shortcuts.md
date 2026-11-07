# Shared shortcuts and the catalog

How to author the shared shortcuts behind Setup › Add Apps (FR-2) and the base shortcut behind Test Capture (FR-5), and how to keep `App/Resources/ShortcutCatalog.json` in step with them.

The app can't create automations. Everything it offers is a shared iCloud shortcut that contains a "When I receive a notification from [app]" automation, which arrives on the user's iPhone switched off. The user switches it on. Each automation calls **Log Notification** (App, Title, Subtitle, Message, Date, Time Sensitive).

## What to author

| Shortcut | Trigger | Log Notification › App | Catalog entry |
| --- | --- | --- | --- |
| Base shortcut | When I receive a notification from **Notification Toolkit** | `Notification Toolkit` | `"id": "base"`, `"isBaseShortcut": true` |
| One per catalog app | When I receive a notification from **that app** | The entry's `displayName`, exactly | One entry per app |
| Banking (generic) | When I receive a notification from (no app chosen, or any bank app as a stand-in) | `Banking` | `"requiresAppSelection": true` |

The App text matters: the app keys history and tracked apps by it (trimmed, case-insensitive). If the shortcut passes `Whatsapp Messenger` but the catalog says `WhatsApp`, Health Check shows WhatsApp as never logging and History shows a second app.

## Recipe: author one shortcut

Do this on an iPhone running the current iOS 27 build, signed in to iCloud, with a development or TestFlight build of Notification Toolkit installed (so Log Notification is available) and the target app installed (so the trigger can name it).

1. In Shortcuts, create the shortcut and name it plainly, e.g. `Log WhatsApp Notifications`.
2. Add the automation: **When I receive a notification from** → the app. Leave the title, subtitle and message filters empty.
3. Add **Log Notification** and fill it in:

   | Field | Value |
   | --- | --- |
   | App | Typed text: the catalog `displayName` |
   | Title | Notification › Title |
   | Subtitle | Notification › Subtitle |
   | Message | Notification › Message |
   | Date | Notification › Date |
   | Time Sensitive | Notification › Is Time Sensitive |

4. Choose **Run Immediately** and turn **Notify When Run** off.
5. Run it once by sending yourself a notification from that app. Check it appears in History under the right name.
6. Share → **Copy iCloud Link**. Paste the link into the entry's `shortcutURL`.

Record the exact labels you saw (they change between betas) in `docs/spikes.md` under S5 and S6, and update the in-app wording if they differ. The labels are quoted in:

- `App/Features/Setup/SwitchOnSheet.swift` (switching a shared automation on)
- `App/Features/Setup/GuidedSetupView.swift` (steps and field mapping for other apps)
- `App/Features/Setup/HealthCheckView.swift` (troubleshooting tips)
- `App/Features/Setup/TestCaptureView.swift` (hints when the test isn't logged)

## Catalog fields

`ShortcutCatalog.json` holds `schemaVersion` (1) and `entries`. Entries keep their file order within each category, so keep the most popular apps first.

| Field | Required | Rules |
| --- | --- | --- |
| `id` | Yes | Lowercase slug, unique, never reused for another app. Stored on each tracked app as `catalogID`. |
| `displayName` | Yes | Plain text, exactly the App value the shortcut passes. No logos, emoji or "official". |
| `category` | Yes | `messaging`, `email`, `work`, `social`, `shoppingAndRides`, `finance`, or `toolkit` (base shortcut only). |
| `shortcutURL` | Yes | The iCloud link. Placeholder until published: `https://www.icloud.com/shortcuts/REPLACE-<id>`. |
| `symbol` | Yes | A generic SF Symbol available on iOS 27. Never one that imitates the app's logo. |
| `keywords` | No | Extra search words, such as a former name. Never shown. |
| `isBaseShortcut` | No | `true` on exactly one entry, whose `displayName` is `Notification Toolkit`. |
| `requiresAppSelection` | No | `true` when the trigger can't name one app, so the switch-on sheet asks the user to choose theirs. |

While a link is still a `REPLACE-` placeholder, Add records the app but doesn't open anything, and the switch-on sheet says the link isn't published yet.

### Check the file

Run from the repository root. It fails on placeholders, so run it before every release build.

```sh
python3 - App/Resources/ShortcutCatalog.json <<'EOF'
import json, re, sys
entries = json.load(open(sys.argv[1]))["entries"]
categories = {"messaging", "email", "work", "social", "shoppingAndRides", "finance", "toolkit"}
problems = []
ids = [e["id"] for e in entries]
if len(ids) != len(set(ids)): problems.append("duplicate ids")
names = [e["displayName"].strip().lower() for e in entries]
if len(names) != len(set(names)): problems.append("duplicate displayNames")
base = [e for e in entries if e.get("isBaseShortcut")]
if len(base) != 1 or base[0]["displayName"] != "Notification Toolkit": problems.append("need exactly one base shortcut named Notification Toolkit")
for e in entries:
    if e["category"] not in categories: problems.append(f"{e['id']}: unknown category")
    if not re.fullmatch(r"[a-z0-9-]+", e["id"]): problems.append(f"{e['id']}: id must be a lowercase slug")
    if not e["shortcutURL"].startswith("https://www.icloud.com/shortcuts/"): problems.append(f"{e['id']}: not an iCloud shortcut link")
    if "/REPLACE-" in e["shortcutURL"]: problems.append(f"{e['id']}: placeholder link")
print("\n".join(problems) or "OK")
sys.exit(1 if problems else 0)
EOF
```

## Test on a second device (spike S5)

Shared links behave differently on the device that made them. For every new or changed link:

1. On a second iPhone on iOS 27, signed in to a different Apple Account, install Notification Toolkit and the target app.
2. In Setup › Add Apps, tap Add for the app. Shortcuts should open the shared shortcut.
3. Add it. Confirm the automation arrives switched off and still names the app.
4. Follow the in-app switch-on steps exactly as written. Fix the wording if any step doesn't match.
5. Send a real notification from the app. Confirm it appears in History and Health Check shows it as logging.
6. Repeat once on a device without the target app installed, and note what happens to the trigger.

For the base shortcut, run Setup › Test Capture instead of step 5.

## Every June beta

Shortcuts changes at WWDC. When the first iOS beta ships each June:

- Install every catalog link on a device running the beta and repeat the second-device test for the base shortcut and two or three popular apps.
- Re-check the labels quoted in the files listed above, and the Notification variable's details (S6).
- Re-author and re-link any shortcut that no longer imports cleanly. Keep the `id`.

## Trademarks and App Review

- Name apps in plain text only: `WhatsApp`, `Microsoft Teams`. No logos, icons, brand colors or lookalike symbols. For example, avoid a paper plane, a phone in a speech bubble, a camera outline or a hash sign.
- Don't suggest a partnership or endorsement: no "official", "for WhatsApp" or "WhatsApp integration".
- Never mention Android, Pixel or other platforms anywhere in the app or the catalog (guideline 2.3.10).
- Keep the description of capture honest (guideline 2.3): it runs through Shortcuts automations the user switches on, only for apps they set up, from setup onward. Never imply the app reads notifications by itself.

## Optional onboarding video

Onboarding and Setup › How It Works show a short clip if `App/Resources/HowItWorks.mp4` exists; without it the slot is hidden. Use a portrait (9:16) screen recording under 30 seconds of switching on an automation and seeing a notification appear in History. It doesn't autoplay; the user taps play. Burn in captions so it works with the sound off.
