# Validation spikes S1–S6

Notification Toolkit depends on one iOS 27 feature it does not control: the Shortcuts personal-automation trigger **"When I receive a notification from [app]"**. These spikes check on real iPhones that the trigger, and our Log Notification intent behind it, behave the way the product needs. Run them before building UI.

**S1 decides whether the product works at all. If S1 fails, stop and rethink.**

| Spike | Question | If it fails |
| --- | --- | --- |
| [S1 Coverage](#s1-coverage) | Does the trigger fire locked, during a Focus, for quiet and summary deliveries, and with no body text? | Locked or Focus: stop and rethink. Others: document the gap in the product. |
| [S2 Scale](#s2-scale) | Is there an "any app" option? How many app triggers fit in one shortcut before setup is unwieldy? | One automation per app, guided setup; Gate 3 at risk. |
| [S3 Sounds](#s3-sounds) | Does Play Sound run promptly on a locked phone, loud enough to replace the app's sound? | No per-app sounds in v1. |
| [S4 Bursts](#s4-bursts) | How fast and how often can Log Notification run, e.g. 30 messages in a busy group chat? | Store or intent changes; warn about busy chats. |
| [S5 Sharing](#s5-sharing) | Does a shared shortcut keep its app trigger on another iPhone, including one without the app? | No prebuilt shortcut links; setup by hand. |
| [S6 Fields](#s6-fields) | Exactly what does the Notification variable expose? | Changes Log Notification's parameters; missing text means stop. |

Recommended order: S1, S6, S4, S3, S2, S5. Release gates are at the [end](#release-gates).

---

## The harness: NT Spike

`SpikeHarness/` builds a throwaway app called **NT Spike** (bundle ID `<prefix>.notificationtoolkit.spike`). It shares only ToolkitCore and the App Group with Notification Toolkit and can be installed next to it.

Build: `xcodegen generate`, then run the **SpikeHarness** scheme on an iPhone with iOS 27. Use a phone with a passcode set; without one, "locked" can't be measured.

### Log Spike Notification

NT Spike's only App Intent, the stand-in for Log Notification. It runs in the background without opening NT Spike (`openAppWhenRun = false`), shows nothing, and on every run:

1. reads `UIApplication.shared.isProtectedDataAvailable` and the app state on the main actor,
2. inserts a row into a real `SQLiteNotificationStore` at `<App Group>/Spike/History.sqlite`, with dedupe off (`dedupeWindow: 0`),
3. appends one JSON line to `<App Group>/Spike/events.jsonl`.

Both files use Complete Until First User Authentication protection, like the app's database. Each write has its own error handling, so one failing never skips the other. A failed JSON line is counted in the App Group's UserDefaults and shown under **Problems** on the Log tab.

Parameters, all optional. In the JSON a parameter the shortcut left empty is absent; empty text is `""`.

| Parameter | JSON key | Fill it with |
| --- | --- | --- |
| App | `app` | The Notification variable's app, or the app name typed as text |
| Title | `title` | Notification › Title |
| Subtitle | `subtitle` | Notification › Subtitle |
| Body | `body` | Notification › Message (or Body) |
| Date | `date` | Notification › Date |
| Time Sensitive | `isTimeSensitive` | Notification › Is Time Sensitive |
| Raw | `raw` | The whole Notification variable, no property chosen (S6) |

Recorded with every capture:

| JSON key / CSV column | Meaning |
| --- | --- |
| `capturedAt` / `captured_at` | When the intent started running |
| `delay_s` (CSV only) | `captured_at` minus the notification's `date` |
| `protectedDataAvailable`, `locked` | See below. **Locked = protected data unavailable** |
| `applicationState` | `active`, `inactive` or `background` |
| `durationMs` | Start of `perform()` until just before the JSON line is written (main-actor hop plus SQLite insert) |
| `mainActorMs`, `sqliteMs` | The two parts of `durationMs` |
| `processID`, `processLaunchedAt`, `secondsSinceProcessLaunch` | The process that ran the intent, from the kernel's start time |
| `captureIndexInProcess`, `cold_launch` | 1 = first capture in a new process, i.e. iOS launched NT Spike to run the intent |
| `sqliteSucceeded`, `sqliteEntryID`, `sqliteError` | Result of the SQLite insert |

**What "Locked" means.** `isProtectedDataAvailable` is the only reliable "phone is locked" signal an app has. With a passcode it turns **false about 10 seconds after the phone locks** and **true again at unlock**. A capture in the first ~10 seconds after locking therefore shows as Unlocked even though the screen is off. That is why every locked test below says to lock within the first 10 seconds of the 30-second countdown: the notification then arrives about 20 seconds after locking, well inside the locked state. Before the first unlock after a restart, protected files can't be opened at all, so nothing can be recorded (S1.15).

### Screens

- **Log:** every capture, newest first: app, text, capture time and notification time with the delay, run time, cold or warm launch, Locked or Unlocked, SQLite result. Tap a row for every field, including Raw. Above the list: totals (captured while locked, cold launches, processes, SQLite rows compared with JSON lines, failures, median and max run time and delay), per-app counts and per-hour counts. **Export CSV** shares a `.csv` file (oldest first). **Clear Log** deletes `events.jsonl` and every entry in the spike's SQLite store.
- **Tools:**
  - **Notification Permission:** current settings, Request Permission, Open Notification Settings.
  - **Notification Options:** interruption level (Active, Passive, Time-sensitive) and No body text. They apply to both tests.
  - **Post Notification in 30 s:** a visible countdown from 30 to 1. Lock while it shows 30–21.
  - **Post Burst:** N notifications (default 30, max 60) one second apart, after a 10-second lead-in to lock the phone.
  - **Cancel Pending Notifications.**
  - **Reopen store for each capture:** S4 only (see there).

Every test notification carries a four-character **marker** (title `NT Spike test 7F3A`, or `Spike group 7F3A` for bursts) so captures can be matched to what was posted. The subtitle says which options were used.

### Privacy

Captures from real apps contain your messages. **Never share a CSV that includes real-app captures.** Share counts and spot-check results instead, or delete the `title`, `subtitle`, `body` and `raw` columns first. Captures of NT Spike's own test notifications are fine to share.

---

## Common setup (once per tester and phone)

Labels marked **[confirm]** are our best guess at iOS 27 wording. Write the real label in the results.

1. **Phone.** iOS 27, note the build (Settings › General › About). Passcode and Face ID or Touch ID on. No Focus active, Low Power Mode off. Note Settings › Notifications › Show Previews (default When Unlocked).
2. **Install NT Spike** from Xcode and open it once, so Shortcuts lists its action.
3. **Permission.** Tools › Request Permission › Allow. In Settings › Notifications › NT Spike: Allow Notifications, Lock Screen, Notification Center and Banners on, Sounds on, Time Sensitive Notifications on [confirm].
4. **Base automation "A-NTSpike":**
   1. Shortcuts › Automation › **+** / New Automation [confirm].
   2. Trigger **Notification** / "When I receive a notification from" [confirm]. App › Choose › **NT Spike**. Leave the title, subtitle and message filters empty [confirm filter labels].
   3. **Run Immediately** [confirm], and turn **Notify When Run** off [confirm]. Next.
   4. New Blank Automation [confirm] › Add Action › search **Log Spike Notification**.
   5. Fill each parameter: tap it, choose the **Notification** variable [confirm name], then tap the variable to pick a property [confirm]. Use the table under [Log Spike Notification](#log-spike-notification). If the variable has no app property, type `NT Spike` as text in App. For Raw, insert the variable and pick no property.
   6. Done. Check the automation is switched on.
5. **Smoke test.** Phone unlocked, Tools › Post Notification in 30 s, go to the Home Screen. After the banner, open NT Spike › Log. Expect one event: Unlocked, SQLite OK, app and text filled in. If nothing appears, check the automation is on and set to Run Immediately.
6. **Before each spike:** Log › Clear Log. **After each spike:** Log › Export CSV, named `S<n>-<tester>-<iPhone model>-<yyyymmdd>.csv` (see [Privacy](#privacy)).

Terms used below. A **trial** is one posted notification. **Fired** means an event with the trial's marker is in the Log. **Locked** means the event shows the Locked badge. **Lock** means press the side button once and don't touch the phone until 10 seconds after the notification is due.

---

## S1 Coverage

**Goal.** Find out whether the trigger runs Log Spike Notification for every way iOS delivers a notification, above all with the phone locked and during a Focus (Gate 1).

**Extra setup.**
- **Automation "A-Messages":** same as A-NTSpike with trigger app **Messages**; App from the variable or typed `Messages`. Needs a second phone to send messages to this one.
- **Focus:** Settings › Focus › Do Not Disturb [confirm]. Allowed apps: not NT Spike, not Messages. Time Sensitive Notifications: on [confirm].
- **Scheduled Summary:** Settings › Notifications › Scheduled Summary [confirm] on, NT Spike included, next summary at least one hour away.
- **Deliver Quietly:** on an NT Spike notification in Notification Center, swipe left › Options › Deliver Quietly [confirm]. Undo it after S1.10.

**Procedure.** Three trials per case. For harness cases: set the options on Tools, tap Post Notification in 30 s, and lock while the countdown shows 30–21 unless the case says otherwise. Unlock 10 seconds after the notification is due and check the Log.

| Case | Condition | How | Expect in Log | Kind |
| --- | --- | --- | --- | --- |
| S1.1 | Unlocked, NT Spike in front | Post, stay in NT Spike | Unlocked, state `active` | Core |
| S1.2 | Unlocked, Home Screen | Post, go Home | Unlocked, state `background` | Core |
| S1.3 | Just locked | Post, lock when the countdown shows 5 | **Unlocked**: confirms the ~10 s window. Note it | Check |
| S1.4 | Locked | Post (Active), lock | Locked | **Gate 1** |
| S1.5 | Locked a long time | Leave the phone locked and idle 60 min, then the second phone sends a message | Locked, cold launch likely | **Gate 1** |
| S1.6 | Focus, active | Do Not Disturb on, post (Active), lock | Locked. Note whether the banner was silenced | **Gate 1** |
| S1.7 | Focus, time-sensitive | Do Not Disturb on, post (Time-sensitive), lock | Locked, Time Sensitive true | **Gate 1** |
| S1.8 | Focus, real app | Do Not Disturb on, phone locked, second phone sends a message | Locked, app Messages | **Gate 1** |
| S1.9 | Passive | Post (Passive), lock | Fired? | Quiet |
| S1.10 | Deliver Quietly | NT Spike set to Deliver Quietly, post (Active), lock | Fired? | Quiet |
| S1.11 | Scheduled Summary | NT Spike in the summary, post, lock, then wait for the summary | Fired at arrival, at summary delivery, or never? Compare capture time and notification date | Summary |
| S1.12 | No body | Post (Active, No body text), lock | Fired? Body "Not passed" or "(empty text)"? | No body |
| S1.13 | No body, Focus | Do Not Disturb on, post (Active, No body text), lock | Fired? | No body |
| S1.14 | Previews hidden | Show Previews: Never [confirm], post, lock | Fired? Are Title and Body filled? Restore the setting after | Check |
| S1.15 | Before first unlock | Restart, don't unlock, second phone sends a message, wait 2 min, unlock | Expect no event: files can't open before the first unlock. Note Problems | Check |
| S1.16 | Low Power Mode | Low Power Mode on, post, lock | Fired? Delay? | Check |
| S1.17 | Third-party app | Automation for an app such as WhatsApp; locked; second phone sends a message | Locked, same as S1.8 | Core |

**Record** per case: fired n/3; Locked n/3 (locked cases); median and max delay; max run time; SQLite failures; whether the banner and sound appeared; which fields were empty.

**Pass.** Every Core and Gate 1 case fires 3/3 on at least two iPhone models; every locked trial shows Locked; no SQLite or events.jsonl failures; every delay under 60 s. Quiet, Summary, No body and Check cases have no pass mark: each answer becomes product behavior or copy.

**What failure means.**
- **S1.4–S1.8 fail: stop and rethink.** A history that misses locked or Focus notifications isn't the product. Don't start UI work.
- S1.1–S1.2 or S1.17 fail: same, unless the cause is clearly NT Spike's own notifications (then repeat with real apps only).
- S1.9 or S1.10 don't fire: quiet apps aren't logged. Onboarding and the health check (FR-4) must warn about Deliver Quietly.
- S1.11 fires only at summary time: store the notification's date, not the capture time (already the plan). Never fires: warn against summaries.
- S1.12 or S1.13 don't fire: title-only notifications are lost; document it. Fire with empty body: History must show title-only entries.
- S1.14 has no text: setup must ask users to set Show Previews to Always, or entries will be blank.

**Results.**

| Date | Tester | iPhone | iOS build | Case | Fired /3 | Locked /3 | Median delay s | Max delay s | Max run ms | SQLite fails | Notes, real labels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | S1.1 | | | | | | | |
| | | | | S1.4 | | | | | | | |
| | | | | … | | | | | | | |

---

## S2 Scale

**Goal.** Find out whether one automation can cover all apps, and if not, how many app triggers one shortcut can hold before setup becomes unwieldy.

**Setup.** A-NTSpike, a stopwatch, and five or more apps that send notifications (or can be made to).

**Procedure.**
1. **Any app.** New automation › Notification trigger › open the app picker. Write down every option shown (e.g. "Any App" [confirm], multi-select, "Choose") and take a screenshot. If an any-app option exists, give it Log Spike Notification with App from the variable, then send notifications from NT Spike, Messages and one other app. Record whether each fires and whether App names the right source.
2. **Several apps in one shortcut.** Starting from A-NTSpike, add apps to its trigger, or add more triggers [confirm "Add Trigger"], until it covers 5, then 10, then 20 apps. For each addition, time from opening the automation to Done and count taps. Note when the editor slows, needs scrolling, or refuses more.
3. **Routing.** With 5 apps in one shortcut, trigger notifications from 3 of them. Does App (from the variable) name each one correctly? If the variable has no app property, record that one multi-app shortcut can't tell apps apart.
4. **Automation count.** Create single-app automations until there are 25 or iOS shows a limit. Record any limit message.

**Record.** Any-app option (yes/no, exact label); seconds and taps per added app; most app triggers in one shortcut; whether App identifies the source; any limit.

**Pass.** Either an any-app option fires for every app and names it, or adding an app takes at most 30 s and 10 taps and one shortcut holds at least 10 app triggers that all fire and are told apart.

**What failure means.** Setup is per app and is the main cost of the product. Onboarding (W5) needs one guided automation per app, Gate 3 is at risk, and the free tier's 3-app limit becomes a natural stopping point. If the variable has no app property, every automation must type the app name as text, so the shortcut catalog must prefill it.

**Results.**

| Date | Tester | iPhone | iOS build | Any-app option | Apps in one shortcut | s per app | Taps per app | App identified | Limit hit | Notes, real labels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | | | |

---

## S3 Sounds

**Goal.** Find out whether a Play Sound action in the automation can replace an app's notification sound: starting promptly on a locked phone, and as loud as a normal notification. Per-app sounds ship only if S3 passes.

**Setup.**
- Duplicate A-NTSpike as **A-Sound**: **Play Sound** [confirm action name] with a short sound file (about 1 s), then Log Spike Notification. Turn A-NTSpike off so only one automation runs.
- Settings › Notifications › NT Spike › Sounds **off**, so the only sound is the one Play Sound makes. A real setup does the same for the source app.
- Ringer on, volume 50% (note how it was set), no headphones, Focus off.
- A second phone recording video at 60 fps or more, to time the banner against the sound. A sound-level meter at 30 cm (e.g. the Apple Watch Noise app).

**Procedure.**
1. **Baseline:** NT Spike Sounds on, A-Sound off. 5 locked trials. Measure the system sound's level.
2. **Replacement:** Sounds off, A-Sound on with Play Sound first. 10 locked trials. From the video, time the screen lighting up with the banner to the first sound. Measure the level.
3. **Order:** Log Spike Notification first, then Play Sound. 5 locked trials. Compare latency and the Log's delay.
4. **Conditions,** 3 locked trials each: Silent mode on; Do Not Disturb on; music playing (does it duck, pause or mix?); Bluetooth headphones connected (where does it play?); phone locked and idle for 30 minutes first.
5. **Passive** notification with A-Sound: does the "quiet" notification now make a sound?

**Record** per trial: latency in seconds, level in dB, played yes/no, any visible Shortcuts banner or indicator, the Log's delay and run time.

**Pass.** In at least 9 of 10 locked trials the sound starts within 2 s of the banner; the level is within 6 dB of the system sound at the same volume; no visible "automation running" UI; nothing plays in Silent mode or in a Focus that silences the source app.

**What failure means.** Drop per-app sounds from v1: no sound picker, no Play Sound in the catalog's shortcuts. History is unaffected. Re-test on the next iOS release.

**Results.**

| Date | Tester | iPhone | iOS build | Step / condition | Trials | Played | Median latency s | Max latency s | dB system | dB Play Sound | Visible UI | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | | | | | |

---

## S4 Bursts

**Goal.** Find out how fast and how often Log Notification can run: whether a burst loses captures, how long each run takes, and whether the store's open connection gets NT Spike killed while suspended (`0xdead10cc`).

**Setup.** A-NTSpike on. Tools › **Reopen store for each capture off** (the production behavior: one SQLite connection kept open for the life of the process). Clear Log.

**Procedure.**
1. **Burst of 30:** Tools › Notifications 30 › Post Burst. Lock during the 10-second lead-in. Wait 60 s after the last one is due, unlock, check the Log. Three runs.
2. **Burst of 60** (the most iOS keeps pending): two runs.
3. **Unlocked:** one burst of 30 with the phone unlocked on the Home Screen.
4. **Real group chat:** receiver locked, A-Messages on. One or two other phones send 30 messages to a group conversation within about a minute. Count the notifications that reached Notification Center (the denominator; Messages may combine some) and the captures.
5. **0xdead10cc check:** after step 1, leave the phone **locked and untouched for 5 minutes**. Unlock, go to **Settings › Privacy & Security › Analytics & Improvements › Analytics Data** and look for entries starting with `SpikeHarness` (the executable's name; the app shows as NT Spike) from the last 10 minutes. Open each and search for `0xdead10cc`. With a Mac, Xcode › Devices and Simulators › View Device Logs shows the same. Repeat after steps 2 and 4.
6. **If a 0xdead10cc report appears:** turn **Reopen store for each capture on**, repeat steps 1 and 5 twice, and record whether the crash stops and how run time changes.

**Record** per run: notifications sent; captures with the marker; missing; duplicates (same message number twice); SQLite and events.jsonl failures; median and max run time; median and max delay; first-to-last capture spread; processes and cold launches (Log summary); 0xdead10cc yes/no with the report's file name.

**Pass.** 30/30 and 60/60 in every run; no duplicates; no failures; max run time under 1 s (NFR-4); max delay at most 10 s; no 0xdead10cc report; in the real chat, every notification that reached Notification Center was captured.

**What failure means.**
- **0xdead10cc report: the store must close its connection after each capture.** W1 changes `SQLiteNotificationStore`, and `AppGroup.store()` stops caching an open connection, or closes it when idle. Confirm the fix with the toggle in step 6.
- Missing captures: Shortcuts throttles automations. The product must say busy chats may be incomplete. More than 10% loss puts Gate 2 at risk.
- Run time of 1 s or more: optimize Log Notification (W4, W1), e.g. defer retention to the app, keep work off the main actor.
- Duplicates: the trigger can fire twice for one notification, so FR-8's dedupe must catch it.

**Results.**

| Date | Tester | iPhone | iOS build | Step | Store mode | Sent | Captured | Missing | Dupes | Failures | Median / max run ms | Median / max delay s | Processes | 0xdead10cc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | 1 | cached | 30 | | | | | | | | |

---

## S5 Sharing

**Goal.** Find out whether a shortcut shared from one iPhone keeps its notification trigger on another, including one without the app. Shared shortcuts can include automations that arrive switched off, so also record how many taps it takes to switch them on.

**Setup.** Phone A with NT Spike, A-NTSpike and A-Messages. Phone B on a different Apple Account, in three states:
- **B1:** NT Spike installed and opened once.
- **B2:** NT Spike not installed.
- **B3:** an automation for an app B doesn't have (e.g. a WhatsApp automation shared to a phone without WhatsApp).

**Procedure.**
1. On A, share the shortcut that contains the automation: long-press › Share › Copy iCloud Link [confirm]. If iOS 27 can share an automation directly, record that path too. Send the link to B in Messages.
2. **B1:** open the link › Add Shortcut [confirm]. Record: did the automation come along; on or off; trigger app still NT Spike; filters kept; Run Immediately kept; Log Spike Notification still mapped to the Notification variable's properties. Count taps to switch it on. Post a test on B1: does it fire?
3. **B2:** open the same link. Record what Shortcuts shows for the missing action and the trigger. Then install NT Spike, open it once, and without editing the automation, post a test. Does it fire? If not, which edit fixes it?
4. **B3:** same as B2 for the missing trigger app; install the app later and test.
5. Open the link on B1 a second time. Does it add a second automation that would log everything twice?

**Record** per phone state: imported yes/no; trigger app kept; parameter mapping kept; arrives on or off; taps to switch on; fires after switching on; fires after installing the missing app; edits needed; duplicate on re-import.

**Pass.** On B1 the automation arrives with its trigger app and parameter mapping intact and fires after at most 3 taps to switch it on. On B2 it fires after installing NT Spike with no edits beyond switching it on.

**What failure means.** We can't ship prebuilt shortcuts as links. Setup (W5) must guide users to build each automation by hand, so the catalog becomes instructions rather than links, setup completion drops, and S2's time per app decides Gate 3. If only B2 fails, onboarding must have users install the app before opening any link (they already do) and re-check the automation after.

**Results.**

| Date | Tester | Phones (A → B) | iOS builds | B state | Imported | Trigger kept | Mapping kept | Arrives | Taps to enable | Fires | Fires after install | Edits needed | Notes, real labels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | B1 | | | | | | | n/a | | |
| | | | | B2 | | | | | | | | | |

---

## S6 Fields

**Goal.** Write down exactly what the Notification variable exposes, so Log Notification's parameters and `NotificationEntry` (app, title, subtitle, body, received date, time-sensitive flag) match what iOS actually passes.

**Setup.** A-NTSpike as in the common setup, with Raw filled.

**Procedure.**
1. In the automation editor, tap any Log Spike Notification field, insert the Notification variable and open its property list [confirm]. Write down every property name and type exactly as shown, with a screenshot. Look in particular for an app name or bundle ID, a thread or conversation, a category, attachments, an identifier, the interruption level.
2. Post each of these and open the event's detail (Log › tap the row):
   1. Active with body (Tools defaults). Posted: title `NT Spike test <marker>`, subtitle `Active`, body `Scheduled for <time>. …`.
   2. No body text.
   3. Time-sensitive.
   4. Passive.
   5. From the second phone, in Messages: a short text; a 2,000-character text; emoji and right-to-left text (Arabic or Hebrew); a photo with no text; a link.
   6. A message in a group conversation: where do the group name and the sender end up?
   7. Repeat 1 with Show Previews: Never [confirm] and the phone locked.
3. For each, compare the detail screen with what was posted. "Not passed" means the variable gave nothing, "(empty text)" means it gave empty text. Check Date against the posted time, Time Sensitive against the level, and how Raw formats the whole variable.

**Record** one row per property: exact label, type, example value, when it is missing or empty, and which `NotificationEntry` field it maps to. Note any truncation of the long text.

**Pass.** Title, body and a date are available for NT Spike's notifications and for Messages; Time Sensitive is true for 2.3 and false for 2.1; the app is either a property or can be typed per trigger.

**What failure means.**
- No title or body text: the history is useless. Stop, as for S1.
- No date: use the capture time (`NewNotification.receivedAt` already falls back to it), so S4's delay must stay small.
- No time-sensitive flag: drop the time-sensitive filter (`HistoryFilter.timeSensitiveOnly`) from v1.
- No app property: every automation types its app name, and multi-app shortcuts (S2) can't be used.
- Long text truncated: record the limit; the UI must not promise full text.

**Results.**

| Property (exact label) | Type | Example | Missing or empty when | Maps to | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | `appName` | |
| | | | | `title` | |
| | | | | `subtitle` | |
| | | | | `body` | |
| | | | | `receivedAt` | |
| | | | | `isTimeSensitive` | |

---

## Release gates

All three must pass before v1 ships. The spikes feed them; Gates 2 and 3 also need real-world testing.

### Gate 1: the trigger fires locked and during Focus

- **Evidence:** S1.4, S1.5, S1.6, S1.7 and S1.8 fire 3/3 on at least two iPhone models, every locked trial shows Locked, and there are no SQLite or events.jsonl failures. S6 confirms the captures contain title and body text.
- **If it fails:** stop and rethink. Don't start UI work.

### Gate 2: 10 testers, 7 days, no capture gaps

- **Setup:** 10 testers on their own iPhones with iOS 27, ideally several iPhone models. Each installs NT Spike (or the MVP build once Log Notification exists; the procedure is the same) and sets up automations for NT Spike plus 3–5 apps they get notifications from every day, such as Messages, WhatsApp, Mail, Slack and Calendar.
- **Every day:**
  1. **Heartbeat:** Tools › Post Notification in 30 s, then lock.
  2. **Spot check** in the evening: pick 10 notifications from tracked apps that arrived that day (from Notification Center, or the source apps if it was cleared) and find each one in the Log.
  3. Check the Log's **Problems** section, and Analytics Data for `0xdead10cc` (see S4).
- **A gap** is any spot-checked notification missing from the Log, a missing heartbeat capture, any SQLite or events.jsonl write failure, or a 0xdead10cc report.
- **Pass:** no gaps in all 70 tester-days.
- **Report** per tester and day: heartbeat captured, spot checks found /10, problems, crash reports. Report counts only (see [Privacy](#privacy)).

| Tester | iPhone | iOS build | Day | Heartbeat | Spot checks /10 | Problems | 0xdead10cc | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | 1 | | | | | |

### Gate 3: setup completion of at least 50%

- **Measured on the MVP's onboarding (W5),** not on NT Spike.
- **Participants:** at least 10 people new to the product, unassisted, on their own iPhones with iOS 27.
- **Completed** means at least one app's automation is switched on and the test notification (FR-5) was captured, within 15 minutes of starting.
- **Record** per participant: completed yes/no, minutes taken, and the step where they gave up.
- **Pass:** completed ÷ started ≥ 50%.
- **Watch:** S2 and S5 predict this gate. If S5 fails and S2 shows more than 60 s per app, plan extra onboarding work before measuring.

| Participant | iPhone | Completed | Minutes | Gave up at | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
