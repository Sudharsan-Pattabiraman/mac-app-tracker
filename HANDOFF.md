# TikTik: Handoff for the next session

**Date:** 2026-10-04 · **Branch:** `claude/zen-curie-nejlat` (pushed to GitHub; pushing works now)
**Read first:** [SPEC.md](SPEC.md) (approved) · [PLAN.md](PLAN.md) (approved) · [design/design-system.html](design/design-system.html) and [design/tiktik-design.html](design/tiktik-design.html) (approved designs)

## Working agreement with the user

- The user builds and tests on their Mac **only at the end**, and reports compile errors then.
- The user is not familiar with Xcode. Everything runs through `./run.sh` (Command Line Tools only).
- Commit and push to the session's branch; also send a zip (see "Packaging") so the user has the files directly.

## Status

All milestones are **written**. `TikTikCore` + `TikTikStore` compile and pass **197 checks** on Linux. The macOS app target
(`Sources/TikTik`) has **never been compiled**; it was reviewed by hand and syntax-checked with tree-sitter.

Done in the 2026-10-04 session:
- `AppController` wires the real `Tracker` (falls back to `EmptyUsageProvider` if the database can't open), preferences →
  `tracker.apply`, login item (only after welcome), pause → `tracker.setPaused`, live/minute refresh, RAM sampling while
  the popover is open, and `AppActions` (browser access, storage text, CSV export via NSSavePanel, Clear all via NSAlert).
- `StatusItemController.runModal` lowers the status-bar-level popover under dialogs; `onClose` stops RAM sampling.
- `Tracker.deleteAllData()` also drops the interval in progress.
- Settings: browser access summary + "Allow…" menu, Export menu (Daily/Raw × 7/30/182 days), storage size, Clear…,
  1-hour pause shows correctly, excluded-app names. Welcome "Allow…" asks running browsers.
- `--dump` / `./run.sh dump`; `applicationWillTerminate` saves the open interval.
- Docs: SPEC 4.1 schema as built, PLAN layout, README.

## Next

1. The user's first full build on a Mac (`./run.sh`). Fix whatever compile errors they paste, keeping fixes minimal.
2. Then their M1–M8 checks (PLAN §4), including `./run.sh --sample-data`, `./run.sh test`, `./run.sh dump`,
   Activity Monitor budget (SPEC 6).

## Notable design facts (beyond SPEC)

- **Late idle detection** emits `.reclassifyAsIdle(range)`, which `Tracker.persist` applies **after** appending pending records.
- **Day tabs (1W/1M/6M)** use the daily rollup as synthetic intervals at each day's midnight. Hour tabs use raw rows.
- **The live open interval** is never in the database while running (only checkpointed to `open_interval` for crash
  recovery). Queries add it via the `live:` parameter. CSV export covers saved rows only.
- **Pause** isn't persisted across relaunch (documented in README).

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
