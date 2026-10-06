# TikTik: Specification

**Status:** Spec approved (Phase 2). Design system and final screens in review (Phase 3).
**Last updated:** 2026-10-03

TikTik is a native macOS menu bar app that records how you use your Mac: Active, Idle and Away time, per app, plus per-site time in Chromium browsers. It runs all the time, so it has to stay light on RAM, CPU and battery. Its interface is a native SwiftUI recreation of shadcn/ui.

The decisions below come from the Phase 1 interview. The mockups you chose from are in [`design/explorations/`](design/explorations/). The design system is in [`design/design-system.html`](design/design-system.html) and the final screens in [`design/tiktik-design.html`](design/tiktik-design.html).

---

## 1. Platform and build

| Decision | Value |
|---|---|
| UI framework | Native SwiftUI only. No Electron, Tauri or web views. |
| Minimum macOS | **14 Sonoma** (`@Observable`, `MenuBarExtra`, Swift Charts, `SMAppService`) |
| App type | Menu bar only. No Dock icon (`LSUIElement = YES`). |
| Audience | **Personal, local use only**, on your own Mac. Not distributed, no App Store. |
| Sandbox | Not sandboxed, so Chrome AppleScript works without exception entitlements. |
| Signing | Ad-hoc (`codesign --sign -`), done automatically by the build script. No Apple Developer account. |
| Project format | **Swift Package plus a single `run.sh` script.** You never need to open Xcode. |
| Dependencies | [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite) only. Fonts are bundled. |

### How you will run it (no Xcode knowledge needed)

1. **One-time setup:** install Apple's free command-line developer tools. Open Terminal and run:
   ```sh
   xcode-select --install
   ```
   Click **Install** in the dialog. This takes a few minutes.
1. **Get the code:**
   ```sh
   git clone https://github.com/sudharsan-pattabiraman/mac-app-tracker.git
   cd mac-app-tracker
   ```
2. **Build and launch:**
   ```sh
   ./run.sh
   ```
   The script compiles TikTik, packages it as `TikTik.app`, copies it to `~/Applications`, and launches it. The hourglass appears in your menu bar.
3. **To update later:** run `git pull` and then `./run.sh` again.

Known caveat of ad-hoc signing: each rebuild gives the app a new signature. macOS may then ask again for the Chrome Automation permission, and you may need to re-enable launch at login. The README will show where to fix this in System Settings if it happens.

---

## 2. Tracking model

### 2.1 States

At any moment the Mac is in exactly one state:

| State | Meaning |
|---|---|
| **Active** | Unlocked and awake, with keyboard, mouse or trackpad input within the idle threshold. Also counts as Active: the frontmost app holds a *prevent display sleep* power assertion, such as a video in Chrome, QuickTime, or a Zoom, Teams or FaceTime call. |
| **Idle** | Unlocked and awake, with no input for at least the idle threshold and no display-sleep assertion from the frontmost app. |
| **Away** | The Mac is locked or asleep, the **display is asleep** (even if not locked), the **screensaver is running**, or you've **switched to another macOS user**. Away is never counted as Idle. |
| *(untracked)* | TikTik wasn't running, tracking was paused, or an excluded app was frontmost. **Not shown anywhere** (see 2.8). |

### 2.2 Idle detection

- **Threshold:** 5 minutes by default, configurable in Settings from 1 to 30 minutes.
- **Backdating:** when the threshold is crossed, the whole no-input stretch **from the last input onward** is reclassified as Idle. The 5 minutes before detection don't count as Active.
- **Quiet time before Away:** macOS often turns the display off, locks or sleeps *before* the idle threshold (the display turns off after 2 minutes on battery by default). If Away starts after **at least 1 minute** without input (and no video or call), that quiet stretch counts as **Idle** too. Locking right after typing stays Active.
- **Source:** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .any)` for input, and `IOPMCopyAssertionsByProcess` for display-sleep assertions held by the frontmost app's PID.

### 2.3 Polling and events (battery)

- **Event-driven, free:** app switches (`NSWorkspace.didActivateApplicationNotification`), sleep and wake, screen lock and unlock (`com.apple.screenIsLocked` / `screenIsUnlocked`), display sleep and wake, screensaver start and stop, and user-session switches.
- **Adaptive idle timer:** fires every 5 s while you're active. Once input stops, it sleeps until the threshold could next be reached, then checks every 5 s. That's at most about 12 wakeups a minute, and none while Away. The timer uses a `tolerance` so macOS can coalesce wakeups.
- **Browser tab polling:** every 5 s, **only while a supported browser is frontmost** (see 2.5).

### 2.4 What gets attributed to apps

- Apps are credited with **Active time only**. Idle and Away time are never attributed to an app.
- So all app rows add up to the Active total, and app percentages are **shares of Active time**.

### 2.5 Browser domains

| Decision | Value |
|---|---|
| Browsers | **Google Chrome, Brave, Microsoft Edge and other Chromium browsers** (one shared AppleScript path). Safari, Arc and Firefox are tracked per-app only. |
| Granularity | **Registrable domain** (eTLD+1): `mail.google.com` becomes `google.com`, and `gist.github.com` becomes `github.com`. |
| Polling | Every 5 s, only while that browser is frontmost. |
| Incognito | Time still counts for the browser, but the domain is recorded as **"Private browsing"**. The real domain is never stored. |
| Permission | Each browser asks once for macOS Automation permission. If it's denied, that browser is tracked per-app only, and Settings shows the status. |
| Non-web pages | `chrome://`, new tab, `file://` and similar pages are recorded with no domain. |

### 2.6 Crossing midnight

Intervals are **split at local midnight** when written, so 23:30 to 00:45 is stored as 30 min on day 1 and 45 min on day 2. Rolling views (6h, 12h, 24h) are unaffected.

### 2.7 Live RAM per app

- Shows each app's **current** memory footprint, the same `phys_footprint` figure Activity Monitor reports, read with `proc_pid_rusage`.
- Helper processes (Chrome renderers, Electron helpers and so on) are summed into their parent app by walking parent PIDs.
- Read **only while the popover is open**, refreshing every 5 s. Nothing is stored.
- Apps that aren't running show `—`. Display rules are in 5.4 (RAM column).

### 2.8 Excluded apps, pause, and untracked time

- **Excluded apps:** a list in Settings. While an excluded app is frontmost, nothing is recorded.
- **Only regular apps count** (the ones with a Dock icon). System dialogs and background agents that briefly take focus (notification and permission prompts, the keychain password dialog, menu-bar utilities, TikTik itself) are ignored, and the time stays with the app you were using.
- **Pause tracking:** 15 min, 1 hour, or until resumed. Available from Settings and the popover. The menu bar item shows a paused indicator.
- **Untracked time is hidden.** The ring shows Active + Idle + Away only (percentages are of tracked time), and charts show empty gaps.

---

## 3. Time ranges

| Tab | Window | Main view | Chart bucket (main and detail) |
|---|---|---|---|
| **6h** | rolling: the last 6 hours | Ring | 15 min |
| **12h** | rolling: the last 12 hours | Ring | 30 min |
| **24h** | rolling: the last 24 hours | Ring | 1 hour |
| **1W** | rolling: the last 7 days including today | Total line + bar chart | 1 day |
| **1M** | rolling: the last 30 days including today | Total line + bar chart | 1 day |
| **6M** | rolling: the last 182 days including today | Total line + bar chart | 1 week |

Before the ranges sits a **Now** tab, a live view rather than a range (see 5.5). The **default tab** when the popover opens is **6h**; you can change it in Settings (Now or any range).

There's no back and forward navigation; every range ends now. The range badge shows the span, e.g. `Last 24h` or `Sep 27 – Oct 3`.

---

## 4. Data and retention

| Decision | Value |
|---|---|
| Engine | **SQLite via GRDB**, WAL mode, at `~/Library/Application Support/TikTik/tiktik.sqlite` |
| Raw data | **Kept raw for the full retention period.** No roll-ups; estimated 10–30 MB at steady state. |
| Retention | **182 days.** Deletion matches the 6M view exactly. |
| Cleanup | **On launch, and once a day** (first wake after local midnight). A single indexed `DELETE`. |
| Export | **CSV only**, from Settings. You choose **Raw intervals** or **Daily totals**, plus a date range, then save through the standard dialog. |
| Clear all data | Yes. A destructive button that asks for confirmation first, and can't be undone. |
| Settings storage | `UserDefaults` |

### 4.1 Schema

As built (GRDB migration `v1`):

```sql
CREATE TABLE app (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  bundle_id  TEXT NOT NULL UNIQUE,     -- e.g. com.google.Chrome
  name       TEXT NOT NULL             -- display name, refreshed on each sighting
);

CREATE TABLE domain (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL UNIQUE      -- registrable domain, or the sentinel "Private browsing"
);

CREATE TABLE interval (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  start_at   REAL NOT NULL,            -- Unix seconds (UTC), fractional
  end_at     REAL NOT NULL,            -- Unix seconds (UTC); never crosses local midnight
  day        INTEGER NOT NULL,         -- local day key, yyyymmdd (retention and daily totals)
  state      INTEGER NOT NULL,         -- 0 active, 1 idle, 2 away
  app_id     INTEGER REFERENCES app(id),     -- set only when state = active
  domain_id  INTEGER REFERENCES domain(id)   -- set only for supported browsers
);
CREATE INDEX interval_day      ON interval(day);
CREATE INDEX interval_start    ON interval(start_at);
CREATE INDEX interval_app_day  ON interval(app_id, day);

-- At most one row: the interval in progress, checkpointed every 60 s.
CREATE TABLE open_interval (
  id         INTEGER PRIMARY KEY,
  start_at   REAL NOT NULL,
  end_at     REAL NOT NULL,
  state      INTEGER NOT NULL,
  app_id     INTEGER,
  domain_id  INTEGER
);
```

- The current (open) interval is kept in memory and written to `interval` when the state, app or domain changes, or when TikTik quits.
- Every 60 s it's **checkpointed** into `open_interval`. If TikTik didn't quit cleanly (crash, force quit), the next launch turns the checkpoint into a real row, so a crash loses at most one minute.
- Range queries clip intervals to the window boundaries, so a session that started before "6h ago" counts only its in-window part. 1W, 1M and 6M read per-day totals grouped by `day`.

---

## 5. Visual design (shadcn/ui in SwiftUI)

### 5.1 Tokens

A single `Theme.swift` holds every token in light and dark variants and follows the system appearance automatically. Components never hardcode colors or sizes.

| Decision | Value |
|---|---|
| Reference | **shadcn v4** (OKLCH values, converted to sRGB for SwiftUI) |
| Base color | **Zinc** |
| Accent | **None (monochrome).** `primary` is near-black in light mode and near-white in dark mode. |
| Color for meaning | Active, Idle and Away use **three tones of the primary color**: 100%, 45% and 14% mixed toward the background (dark-mode Away is 26%, so it stays visible on dark cards). `destructive` red appears only on destructive actions. |
| Radius | **10 pt** (`--radius`). `sm` 6 (badges, icon tiles), `md` 8 (buttons, selects, tab pill), `lg` 10 (cards, tab track), `xl` 14 (popover frame), `full` (switches, bars). |
| Font | **JetBrains Mono everywhere** (OFL licence, bundled, about 300 KB), with tabular figures for all numbers. |

Full reference with live specimens: [`design/design-system.html`](design/design-system.html).

**Colors** (shadcn v4 zinc, converted exactly from OKLCH to sRGB):

| Token | Light | Dark |
|---|---|---|
| `background` | `#FFFFFF` | `#09090B` |
| `foreground` | `#09090B` | `#FAFAFA` |
| `card` | `#FFFFFF` | `#18181B` |
| `primary` | `#18181B` | `#E4E4E7` |
| `primaryForeground` | `#FAFAFA` | `#18181B` |
| `secondary` | `#F4F4F5` | `#27272A` |
| `muted` | `#F4F4F5` | `#27272A` |
| `mutedForeground` | `#71717B` | `#9F9FA9` |
| `accent` | `#F4F4F5` | `#27272A` |
| `border` | `#E4E4E7` | `#FFFFFF1A` |
| `destructive` | `#E7000B` | `#FF6467` |
| `ring` | `#9F9FA9` | `#71717B` |
| `stateActive` | `#18181B` | `#E4E4E7` |
| `stateIdle` | `#8D8D8F` | `#606063` |
| `stateAway` | `#DADADB` | `#38383B` |

`border` in dark mode is white at 10% opacity. Progress tracks are `primary` at 18% opacity.

**Type scale** (points · weight):

| Role | Spec | Used for |
|---|---|---|
| `caption` | 10 · 500 · +0.05em · uppercase | column headers |
| `label` | 11 · 400 · mutedForeground | labels, legends, hints |
| `bodySm` | 12 · 400 | table numbers, controls |
| `body` | 13 · 400 | default text |
| `bodyStrong` | 13 · 500 | app names, setting names |
| `title` | 14 · 600 | popover title |
| `heading` | 15 · 600 | app name in detail |
| `display` | 17 · 600 · −0.01em | welcome title |
| `hero` | 30 · 600 · −0.02em · tabular | Now timer |

**Spacing scale** (4 pt based): `0.5`=2 · `1`=4 · `1.5`=6 · `2`=8 · `2.5`=10 · `3`=12 · `3.5`=14 · `4`=16 · `5`=20 · `6`=24. Card padding is 12 × 14, popover padding 14, and the gap between controls 8.

**Component sizes:** buttons 30 pt high (sm 26, icon 26 × 26) · select 28 · switch 32 × 18 · tab pill 4 pt vertical padding · progress 6 pt (app rows) or 4 pt (domains) · focus ring 2 pt with 2 pt offset in `ring`.

### 5.2 Components

These are standalone SwiftUI views that use only theme tokens: `Card` (header, content, footer), `Tabs`, `Button` (default, secondary, outline, ghost and destructive variants), `Badge`, `Progress`, `Separator`, `Tooltip`, `Switch`, `Select`, plus a `Ring` and shadcn-style chart styling (muted dashed gridlines, minimal axes, hover tooltips).

### 5.3 Popover

- **Size:** fixed **380 × 560 pt**, with **comfortable** density (rows about 44 pt). The app list scrolls inside the fixed frame.
- **Layout, top to bottom:**
  1. Header: hourglass glyph + **TikTik** (`title`) on the left, range badge on the right (e.g. `Last 6h`, `Sep 27 – Oct 3`, or `Now · 14:07`)
  2. Tabs: `• Now  6h  12h  24h  1W  1M  6M` (seven tabs; the dot marks Now as live). Opens on the default tab (6h unless changed).
  3. Summary:
     - 6h, 12h and 24h: a **Ring** card showing Active, Idle and Away, with the center showing Active %
     - 1W, 1M and 6M: a **one-line legend** of the totals plus an **active-time bar chart**
  4. App list
  5. Footer: **three outline icon buttons, right-aligned: pause, settings, quit.** No status text.
     - Pause opens a small menu (15 min · 1 hour · Until resumed). While paused the icon becomes play (resume).
     - Settings opens the Settings page.
     - Quit (power icon) quits immediately, without confirmation.
- **Paused state:**
  - A dashed **banner** under the tabs: "Tracking paused · Resumes at 14:52 · 45m left", with a **Resume** button ("Until you resume" when there's no end time).
  - The rest of the view stays usable.
- **Empty states:**
  - **First launch:** "Tracking has started". Your first minutes appear shortly.
  - **Range with nothing recorded:** "Nothing recorded in the last 6 hours". TikTik wasn't running or was paused.
  - **Range longer than history:** not empty. The existing days are shown, plus a one-line note: "History starts Oct 1 · earlier weeks have no data".
  - **Chrome access denied:** in app detail, the domains card shows a `No access` badge, explains that only app time is recorded, and has an **Open System Settings** button.

### 5.4 App list

![App list in light and dark mode](design/screenshots/main-24h-light.png)

The list is a small table with a header row and these columns:

| Column | Width | Content |
|---|---|---|
| *(icon)* | 20 pt | real app icon |
| **App** | flexible | app name, truncated with an ellipsis (`Google Chrome` fits in full) |
| **Time** | 50 pt, right-aligned | Active time in the range |
| **RAM** | 52 pt, right-aligned | live memory footprint (see 2.7) |
| **%** | 30 pt, right-aligned, muted | share of Active time. Always the last column. |
| *(chevron)* | 8 pt | `›`, meaning the row opens app detail |

- Under the text line, a **progress bar** spans App to % with length equal to the app's **share of total Active time**.
- **RAM display:**
  - Below 1 GB it shows as `612 MB`; from 1 GB as `2.1 GB` (one decimal).
  - Apps that aren't running show `—`.
  - **Heavy apps (2 GB or more) are drawn in bold foreground ink.** Everything else is muted. No color is used.
  - Refreshes every 5 s while the popover is open.
- **Sorting:**
  - Defaults to **Time, descending**.
  - Clicking the **Time** or **RAM** header re-sorts by that column. `↓` and foreground ink mark the active column.
  - Sorting by RAM puts apps that aren't running last.
  - The sort resets to Time each time the popover opens.
- **Header:** small uppercase muted labels (`APP · TIME · RAM · %`). It stays pinned while the rows scroll.
- **Which apps:** **all** apps used in the range. Nothing is grouped into "Other".
- **Clickable:** opens the app detail page (5.6).
- **Duration format:** `2h 14m`. Minutes are zero-padded when hours are present (`6h 06m`). Values stay in hours past 24h (`38h 12m`). Under a minute shows `<1m`; nothing at all shows `0m`.

### 5.5 Now tab

<img src="design/screenshots/now-chrome-light.png" width="300"> <img src="design/screenshots/now-idle-dark.png" width="300">

A live view of what you're doing, as the first tab:

- **Current app card:**
  - **The frontmost app.** This is never TikTik itself; when the popover takes focus, Now shows the last other app.
  - **A state badge**, Active or Idle.
  - **A large live timer for the current stretch**, e.g. `6m 41s since 14:01`.
    - It ticks every second, but only while the popover is open.
    - When Idle, it counts idle time ("idle since 14:01").
  - **The current site** and time on it, for Chromium browsers.
  - **Today in this app** (since local midnight) and **RAM now**.
- **Recent card:** today's most recent stretches, newest first: start time, icon, app (or a muted "Idle" row) and duration. It fills the remaining height and scrolls.
- **Stretch / session rule:** a stretch ends when you **switch to another app** or on an **Idle or Away gap of 2 min or more**. The same rule defines *Sessions* in app detail (5.6).
  - **Brief visits don't count as a switch.** Less than 30 s in other apps before coming back (a quick ⌘-Tab glance, a system dialog) keeps the stretch going, and the visit gets no Recent row of its own. Its time still counts for that app in every total.
- **Cost:** reads in-memory tracker state only. No new storage, no schema change, no extra permission.

### 5.6 App detail (inside the popover)

- **Back** button and range badge, plus app icon, name, active total and % of Active time.
- Range tabs (6h–6M only, no Now), sharing the same selection as the main view.
- **Usage chart:** active time per bucket, using the buckets in section 3, with hover tooltips.
- **Stats card:** Sessions, Longest session, First and last used, RAM now.
- **Top domains** (Chromium browsers only): registrable domains with duration, % of the browser's time and a bar. "Private browsing" appears as its own row.

### 5.7 Menu bar item

- **The user picks one of six styles**, on the welcome screen and later in Settings:

  | | Style |
  |---|---|
  | **A** | Icon + time **(default)** |
  | B | Icon only |
  | C | Text only |
  | D | Progress ring |
  | E | Ring + time |
  | F | Time + state dot (solid while Active, faded while Idle) |

- The time shown is **Active time since local midnight today**. It updates at most once a minute.
- **Daily goal** for the ring styles (D, E): **8h** by default, editable in Settings. The ring stays full beyond the goal.
- **While paused**, the item shows a pause glyph plus the time left, e.g. `⏸ 45m` (or `⏸ paused` when it's until resumed), whatever style is selected.

### 5.8 Welcome screen (first launch only)

A small window, shown once:

1. Title and a one-line explanation ("Everything stays on this Mac").
2. **Menu bar style picker:** six tiles with live previews, A preselected.
3. **Website tracking in Chrome:** explains the Automation prompt, with an **Allow…** button that triggers it.
4. **Launch at login** switch, **on** by default. Registration (and the macOS "Login Item Added" notice) happens on **Continue**, and only if the switch is on.
4. **Continue** button.

### 5.9 Settings (inside the popover)

A Settings page in the popover, opened from the gear, with **Back**. Grouped cards:

- **General:** Launch at login · **Default tab** (Now, 6h–6M; default 6h) · Menu bar style · Daily goal
- **Tracking:** Idle after (1–30 min) · Website tracking on/off · Browser permissions status · **Excluded apps** · **Pause tracking**
- **Data:** Export CSV… · Storage info (days kept, size) · **Clear all data…** (destructive)
- **About:** version · Quit TikTik

---

### 5.10 Screenshots

All screens are rendered from [`design/tiktik-design.html`](design/tiktik-design.html) at real size (2× PNGs) with example data. To regenerate them after a design change, re-render that page. These are the final Phase 3 designs.

| Screen | Light | Dark |
|---|---|---|
| Now · in Xcode | <img src="design/screenshots/now-xcode-light.png" width="260"> | <img src="design/screenshots/now-xcode-dark.png" width="260"> |
| Now · in Chrome | <img src="design/screenshots/now-chrome-light.png" width="260"> | <img src="design/screenshots/now-chrome-dark.png" width="260"> |
| Now · idle | <img src="design/screenshots/now-idle-light.png" width="260"> | <img src="design/screenshots/now-idle-dark.png" width="260"> |
| Main · 6h (default) | <img src="design/screenshots/main-6h-light.png" width="260"> | <img src="design/screenshots/main-6h-dark.png" width="260"> |
| Main · 12h | <img src="design/screenshots/main-12h-light.png" width="260"> | <img src="design/screenshots/main-12h-dark.png" width="260"> |
| Main · 24h | <img src="design/screenshots/main-24h-light.png" width="260"> | <img src="design/screenshots/main-24h-dark.png" width="260"> |
| Main · 1W | <img src="design/screenshots/main-1w-light.png" width="260"> | <img src="design/screenshots/main-1w-dark.png" width="260"> |
| Main · 1M | <img src="design/screenshots/main-1m-light.png" width="260"> | <img src="design/screenshots/main-1m-dark.png" width="260"> |
| Main · 6M | <img src="design/screenshots/main-6m-light.png" width="260"> | <img src="design/screenshots/main-6m-dark.png" width="260"> |
| App list sorted by RAM | <img src="design/screenshots/main-sorted-ram-light.png" width="260"> | <img src="design/screenshots/main-sorted-ram-dark.png" width="260"> |
| App detail · Xcode | <img src="design/screenshots/detail-xcode-light.png" width="260"> | <img src="design/screenshots/detail-xcode-dark.png" width="260"> |
| App detail · Chrome (domains) | <img src="design/screenshots/detail-chrome-light.png" width="260"> | <img src="design/screenshots/detail-chrome-dark.png" width="260"> |
| Settings (full height) | <img src="design/screenshots/settings-light.png" width="260"> | <img src="design/screenshots/settings-dark.png" width="260"> |
| Paused | <img src="design/screenshots/paused-light.png" width="260"> | <img src="design/screenshots/paused-dark.png" width="260"> |
| Empty · first launch | <img src="design/screenshots/empty-first-light.png" width="260"> | <img src="design/screenshots/empty-first-dark.png" width="260"> |
| Empty · nothing in range | <img src="design/screenshots/empty-range-light.png" width="260"> | <img src="design/screenshots/empty-range-dark.png" width="260"> |
| Partial history (6M) | <img src="design/screenshots/partial-history-light.png" width="260"> | <img src="design/screenshots/partial-history-dark.png" width="260"> |
| Chrome access denied | <img src="design/screenshots/chrome-denied-light.png" width="260"> | <img src="design/screenshots/chrome-denied-dark.png" width="260"> |
| Welcome window | <img src="design/screenshots/welcome-light.png" width="360"> | <img src="design/screenshots/welcome-dark.png" width="360"> |
| Paused · menu bar | <img src="design/screenshots/paused-menubar-light.png" width="360"> | <img src="design/screenshots/paused-menubar-dark.png" width="360"> |
| Menu bar styles | <img src="design/screenshots/menubar-light.png" width="360"> | <img src="design/screenshots/menubar-dark.png" width="360"> |

---

## 6. Performance budget (targets to verify in Phase 5)

| Metric | Target |
|---|---|
| RAM, popover closed | under 40 MB |
| RAM, popover open | under 80 MB |
| CPU, idle in background | about 0% (wakeups only on timers and events, as in 2.3) |
| Energy | "Low" in Activity Monitor's Energy tab |
| Database size after 6 months | under 50 MB |

---

## 7. Privacy

- All data stays local in one SQLite file. Nothing goes over the network; the app makes no network requests at all.
- No window titles, no full URLs, no keystrokes. Only the frontmost app, a registrable domain for Chromium browsers, and timestamps.
- Incognito domains are never stored. Excluded apps are never recorded.

---

## 8. Out of scope (for now)

Safari, Arc and Firefox domain tracking · window titles · navigating back to past periods · cloud sync · notifications or limits · JSON export · App Store or notarized distribution.

---

## 9. Open items

None. All design questions were resolved in Phase 3:

| Item | Decision |
|---|---|
| Popover header | Hourglass glyph + "TikTik", with the range badge on the right |
| Footer | Icon buttons only: pause, settings, quit (immediate) |
| Paused state | Dashed banner with Resume in the popover; `⏸ 45m` countdown in the menu bar |
| Empty states | The four designs in 5.3 |
| Spacing and type | The scales in 5.1 |
| Session definition | Ends on an app switch (visits under 30 s don't count) or Idle/Away of 2 min or more (5.5) |
