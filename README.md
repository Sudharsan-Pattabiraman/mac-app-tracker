# TikTik

A native macOS menu bar app that tracks how you use your Mac: Active, Idle and Away time, per app, with per-site time for Chrome and other Chromium browsers. Built in SwiftUI with a shadcn/ui look. Everything stays on your Mac.

- **What it does and why:** [SPEC.md](SPEC.md)
- **How it's built:** [PLAN.md](PLAN.md)
- **What it looks like:** [design/](design/) (open `design/tiktik-design.html` in a browser)

> **Status:** feature-complete, waiting for its first full build and test on a Mac (milestone **M8**). See [Milestones](#milestones).

## Install and run

You don't need Xcode. You only need Apple's free Command Line Tools.

1. **Install the Command Line Tools** (one time). Open **Terminal** and run:
   ```sh
   xcode-select --install
   ```
   Click **Install** in the dialog and wait for it to finish. If it says they're already installed, you're set.

2. **Get the code:**
   ```sh
   git clone https://github.com/sudharsan-pattabiraman/mac-app-tracker.git
   cd mac-app-tracker
   git checkout claude/zen-curie-nejlat
   ```
   (The last line is needed only while TikTik is in development on that branch.)

3. **Build and launch:**
   ```sh
   ./run.sh
   ```
   The first build downloads one dependency and takes a few minutes. When it's done, an **hourglass** appears in your menu bar. Click it to open TikTik.

   On the first run the script creates a code-signing certificate called **"TikTik Local"** in your login keychain. It keeps macOS permissions (Chrome access, launch at login) working across updates. macOS may ask whether `codesign` can use the key: enter your login password and click **Always Allow**.

### Updating

```sh
cd mac-app-tracker
git pull
./run.sh
```

### Other commands

| Command | What it does |
|---|---|
| `./run.sh --sample-data` | Launches with example data and a **Design review** window to flip through every screen |
| `./run.sh test` | Runs the core logic checks (should end with "All … checks passed") |
| `./run.sh dump` | Prints today's recorded intervals and totals, to check tracking by hand |
| `./run.sh build` | Builds `build/TikTik.app` without installing it |
| `./run.sh logs` | Streams TikTik's log messages (Ctrl-C to stop) |
| `./run.sh uninstall` | Quits TikTik and removes it from `~/Applications` (keeps your data) |

## Good to know

- **Your data** lives in `~/Library/Application Support/TikTik/tiktik.sqlite`, on this Mac only. TikTik keeps 182 days and cleans up older days daily. **Settings → Export CSV** saves raw intervals or daily totals; **Settings → Clear all data** deletes everything (it asks first).
- **Pause doesn't survive a restart.** If you quit TikTik (or restart the Mac) while paused, it starts tracking again on the next launch.
- **Website tracking** works in Chrome, Brave, Edge, Chromium and Vivaldi. macOS asks once per browser for permission; the browser has to be running when TikTik asks. You can change it later in **System Settings → Privacy & Security → Automation**.
- **Excluded apps** (Settings) are never recorded; time in them isn't counted at all.

## Troubleshooting

- **"Swift isn't installed"** → run `xcode-select --install`, then `./run.sh` again.
- **Build errors** → copy the full Terminal output and send it to me.
- **Numbers look wrong** → run `./run.sh dump` and send me the output, together with what you were doing at the time.
- **No website time for Chrome** → open **System Settings → Privacy & Security → Automation**, find TikTik and turn on your browser.
- **No hourglass in the menu bar** → on a MacBook with a notch, menu bar icons can be hidden behind it. Quit some other menu bar apps, or hold ⌘ and drag icons to make room.
- **Remove the signing certificate** → open **Keychain Access**, search for "TikTik Local", and delete it.

## Milestones

| | Milestone | Status |
|---|---|---|
| M0 | Skeleton runs on your Mac | done |
| M1 | Design system in SwiftUI | written, needs your check (`./run.sh --sample-data`) |
| M2 | Tracking engine | done, checks passing |
| M3 | Real data in the popover | written, needs your check |
| M4 | Now tab + app detail | written, needs your check |
| M5 | Chrome domains | written, needs your check |
| M6 | Settings, welcome, menu bar, pause | written, needs your check |
| M7 | Data management (export, clear, retention) | written, needs your check |
| M8 | Performance + polish | **next: first full build on your Mac** |

## Credits

JetBrains Mono font, © The JetBrains Mono Project Authors, [SIL Open Font License 1.1](Sources/TikTik/Resources/Fonts/OFL.txt).
