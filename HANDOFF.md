# TikTik: Handoff for the next session

**Date:** 2026-10-04 · **Branch:** `claude/funny-albattani-n7p4d6`
**Read first:** [SPEC.md](SPEC.md) (approved) · [PLAN.md](PLAN.md) (approved) · [design/design-system.html](design/design-system.html) and [design/tiktik-design.html](design/tiktik-design.html) (approved designs)

## Working agreement with the user

- The user builds and tests on their Mac **only at the end**, and reports compile errors then. The next session should **keep building to completion**, keep the code correct, then package it.
- GitHub pushes from the cloud session fail with **403** (the Claude GitHub App isn't connected). Every commit so far is local only. Deliver code as a zip via SendUserFile (see "Packaging" below), and tell the user to reconnect at https://claude.ai/connect-github.
- The user is not familiar with Xcode. Everything runs through `./run.sh` (Command Line Tools only).

## Status by milestone

| Milestone | Status |
|---|---|
| M0 Skeleton (Package.swift, run.sh, panel, fonts) | ✅ done, **user confirmed it runs** |
| M1 Design system + all screens with `--sample-data` | ✅ written. Not compiled on a Mac yet (user tests at the end) |
| M2 Tracking engine (core) | ✅ done + **compiled and tested on Linux** |
| M3 Store + queries (GRDB) | ✅ done + **compiled and tested on Linux** |
| M5 Domain parsing (Public Suffix List) | ✅ done + tested. Browser AppleScript probe written (macOS-only, unverified) |
| M2/M3 macOS glue (monitors, Tracker, RealUsageProvider) | 🟡 **written, NOT wired into AppController yet** |
| M6 Settings wiring, login item, pause, excluded apps | ❌ todo (see below) |
| M7 Export CSV, Clear all, retention | 🟡 store side done + tested; UI wiring todo |
| M8 Review, docs, packaging | ❌ todo |

**Linux checks: 185 passing** (`TikTikChecks`). They cover the engine, day splitting, buckets, aggregation, the SQLite store, queries, CSV and the PSL.

## Module layout (as built)

- `Sources/TikTikCore`: Foundation only, compiled and tested on Linux.
  - `Engine/`: `TrackerTypes`, `TrackerEngine`, `DaySplitter`
  - `Query/`: `TimeTab`, `BucketLayout`, `Aggregator`
  - `Model/UsageModels`
  - `Format/`: `DurationFormat`, `MemoryFormat`
  - `Domains/PublicSuffixList`
- `Sources/TikTikStore`: GRDB, compiled and tested on Linux.
  - `TrackerStore`: schema v1; append, reclassify, checkpoint, recover, rollup, retention, deleteAll, fileSize
  - `UsageQueries`: summary, detail, recentStretches, activeToday
  - `CSVExporter`
- `Sources/TikTik`: the macOS app, **never compiled**.
  - `App/`: `TikTikApp` (@main), `AppController`, `StatusItemController`, `PopoverPanel`
  - `Theme/`, `Components/` (TK*), `Features/` (PopoverRoot, Now, Range, Detail, Settings, Welcome, MenuBar), `Debug/` (SampleData, DesignReview)
  - `State/`:
    - `Preferences`
    - `AppState` (has `actions: AppActions`)
    - `AppActions`, `UsageProvider` (+ `EmptyUsageProvider`)
    - `Tracker` (new): owns the engine, store, monitors, 60 s checkpoint and daily retention
    - `RealUsageProvider` (new)
  - `Platform/` (new): `ProcessTree` (libproc, responsible pid), `Monitors` (FrontmostAppMonitor, SessionMonitor, InputIdleMonitor, PowerAssertionProbe), `MemorySampler`, `LoginItem` (SMAppService), `BrowserMonitor` (NSAppleScript on main, 1 s timeout; AEDeterminePermissionToAutomateTarget off main)
  - `Resources/`: JetBrains Mono TTFs + OFL, `public_suffix_list.dat` (copied into the .app by run.sh)
- `Checks/`: `Harness`, `main`, `EngineChecks`, `QueryChecks`, `DomainChecks` (plain executable, no XCTest)

Notable design facts (beyond SPEC):
- **Schema columns** are `start_at` / `end_at` (REAL, Unix seconds) plus `day` (yyyymmdd local). There's also an `open_interval` checkpoint table.
- **Late idle detection** emits `.reclassifyAsIdle(range)`, which `Tracker.persist` applies **after** appending pending records.
- **Day tabs (1W/1M/6M)** use the daily rollup as synthetic intervals at each day's midnight. Hour tabs use raw rows.
- **The live open interval** is never in the database while running (it's checkpointed to `open_interval` only for crash recovery). Queries add it via the `live:` parameter.

## Remaining work (in order)

1. **Rewrite `App/AppController.swift`**:
   - Non-sample mode: `TrackerStore(path: TrackerStore.defaultPath())` → `Tracker(store:config:websiteTracking:)` → `tracker.start()`, provider = `RealUsageProvider(tracker:)`. On store open failure, log it and fall back to `EmptyUsageProvider`.
   - Sample mode: keep `SampleUsageProvider` and the design review, and don't start the tracker.
   - `TrackerConfig(idleThreshold: prefs.idleMinutes*60, excludedBundleIDs: Set(prefs.excludedBundleIDs))`.
   - Preferences sink → `tracker.apply(config:websiteTracking:)`. Also `LoginItem.set(prefs.launchAtLogin)`, but **only if `hasCompletedWelcome`**. At launch, when welcome is done, set `prefs.launchAtLogin = LoginItem.isEnabled`.
   - Pause: in `observeState`, track the previous `state.pause`; on change call `tracker.setPaused(pause != nil)`. Timed expiry already happens in `tick()`.
   - `tracker.onLiveChange` → `refreshMenuBar()`, plus `state.reload()` if the panel is visible. `tracker.onDataChange` (every minute) → same.
   - Menu bar `isIdle: tracker?.engine.open.state == .idle`.
   - Popover open: `tracker.memory.start()`, with `memory.onUpdate = { state.reload() }` (gives the 5 s live refresh). Popover close: `memory.stop()`. Add an `onClose` to `StatusItemController` (call it from `panel.onDismiss`).
   - Set `state.actions`:
     - `requestBrowserAccess` → `tracker.browser.requestAccessForRunningBrowsers()`
     - `browserAccessSummary` → `tracker.browser.accessSummary()`; `tracker.browser.onAccessChange` → `state.reload()`
     - `storageSummary` → "182 days kept · \(MB) MB" from `store.fileSize()`
     - `exportCSV(kind, days)` → window = startOfDay − (days−1) … now; `CSVExporter(store:calendar:).export(kind == .raw ? .raw : .daily, window:)`; then `NSSavePanel` (`allowedContentTypes = [.commaSeparatedText]`, `NSApp.activate`) and write UTF-8
     - `clearAllData` → `NSAlert` (critical style, "Clear all data" with `hasDestructiveAction = true`, Cancel) → `store.deleteAll()` → `state.reload()`
     - `canManageData = true`
   - Welcome Continue → `prefs.hasCompletedWelcome = true`, `LoginItem.set(prefs.launchAtLogin)`, close.
   - `AppDelegate.applicationWillTerminate` → `controller.tracker?.shutdown()`.
2. **`Features/Settings/SettingsView.swift`**:
   - Read `state.actions`.
   - Browser permissions row: text `actions.browserAccessSummary()`; button "Allow…" → `actions.requestBrowserAccess()`, plus a secondary path to open Automation settings.
   - Export button → `NativeMenu` with Daily/Raw × last 7/30/182 days → `actions.exportCSV`.
   - Clear… → `actions.clearAllData()`.
   - Enable both only when `actions.canManageData`.
   - Storage text → `actions.storageSummary()`.
3. **`Features/Welcome/WelcomeView.swift`**: "Allow…" → `state.actions.requestBrowserAccess()`. WelcomeView needs `.environment(appState)` added where it's shown in AppController.
4. **`--dump`**: in `TikTikMain.main()` before the NSApplication setup, if the arguments contain `--dump`, open the store and print today's intervals (`queries`/`store.intervals(overlapping: today)`) as text, then `exit(0)`. Add `./run.sh dump`, which runs `~/Applications/TikTik.app/Contents/MacOS/TikTik --dump` directly.
5. **Full review of all macOS-only code** (it can't be compiled here):
   - Swift 5 language mode; macOS 14 APIs only.
   - Watch for: actor isolation of closures (`MainActor.assumeIsolated` inside notification/timer blocks), memberwise-init access with private properties, `@Observable` + `didSet` (avoid), generic static stored properties (not allowed), missing imports (`import TikTikStore` where store types are used; `UniformTypeIdentifiers` for `.commaSeparatedText`).
   - Also check: `PopoverRoot` badge/sizes against the mockups, and `TKBarChart` (Swift Charts `chartOverlay`/`plotFrame`, categorical x).
6. **Docs**:
   - SPEC 4.1 schema: `start_at`/`end_at` REAL + `day`, plus `open_interval`.
   - README: milestone table, `./run.sh dump`, and the note that pause doesn't persist across relaunch.
   - PLAN: the new `TikTikStore` target.
7. **Commit**, run the Linux checks, **package the zip and SendUserFile it**, and give the user test instructions (`./run.sh`, `./run.sh --sample-data`, `./run.sh test` should print all checks passing, ~185+).

## How to compile and test on Linux (rebuild in a new session)

The scratchpad is session-specific, so recreate the toolchain:

```sh
S=<scratchpad>; mkdir -p $S/swiftdeb && cd $S/swiftdeb
U=http://archive.ubuntu.com/ubuntu/pool
curl -sSO $U/universe/s/swiftlang/swiftlang_6.0.3-2build1_amd64.deb
curl -sSO $U/universe/s/swiftlang/libswiftlang_6.0.3-2build1_amd64.deb
curl -sSO $U/main/libx/libxml2/libxml2-16_2.15.2+dfsg-0.1ubuntu0.2_amd64.deb
mkdir root extra && dpkg -x swiftlang_*.deb root && dpkg -x libswiftlang_*.deb root && dpkg -x libxml2-16_*.deb extra
export PATH=$S/swiftdeb/root/usr/libexec/swift/bin:$PATH
export LD_LIBRARY_PATH=$S/swiftdeb/extra/usr/lib/x86_64-linux-gnu
apt-get install -y libsqlite3-dev
git clone --depth 1 --branch v6.29.3 https://github.com/groue/GRDB.swift.git $S/grdb
```

Then build a Linux harness package at `$S/linuxpkg`:
- Symlink `Sources/TikTikCore`, `Sources/TikTikStore`, `Checks` and `Sources/TikTik/Resources` from the repo.
- Add a C target `SQLiteStubs` that defines no-op `sqlite3_snapshot_get/open/free/cmp`. Ubuntu's SQLite lacks `SQLITE_ENABLE_SNAPSHOT`; this shim is for Linux tests only, never shipped.
- Write a Package.swift with GRDB as `.package(path: $S/grdb)` and `TikTikChecks` depending on `["TikTikCore", "TikTikStore", "SQLiteStubs"]`.
- Run `swift build && swift run TikTikChecks`.

The macOS app target (AppKit/SwiftUI) **cannot** be compiled on Linux. Syntax-check it with tree-sitter (`pip install tree-sitter tree-sitter-swift`) and review it by hand.

## Packaging

```sh
cd /home/user/mac-app-tracker
python3 - <<'EOF'
import zipfile, os, subprocess
files = subprocess.check_output(['git','ls-files'], text=True).split()
with zipfile.ZipFile('TikTik-M8.zip','w',zipfile.ZIP_DEFLATED) as z:
    for f in files:
        i = zipfile.ZipInfo.from_file(f, arcname='mac-app-tracker/'+f)
        i.external_attr = (0o100000 | (0o755 if f=='run.sh' else 0o644)) << 16
        i.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(i, open(f,'rb').read())
EOF
```

Commit messages end with the session's Co-Authored-By/Claude-Session lines. Don't put model names in the repo.
