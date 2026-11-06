# Spider Buddy for Windows: development workflow

How the Windows version is built, tested and compared with the Mac version. Read this first in any new
session, then [WINDOWS_PARITY_STATUS.md](WINDOWS_PARITY_STATUS.md) for where things stand and the latest entry in
[WINDOWS_WORKLOG.md](WINDOWS_WORKLOG.md) for what happened last.

**The goal:** the Windows app is effectively the same as the Mac app. Physics, behavior, art and UI. The Mac app is
the reference for all of it, and a difference counts as a bug unless it is listed in
[Accepted differences](#11-accepted-differences).

---

## 1. Rules

1. **The Mac version is never changed for the sake of this work.** No edits to the Mac repo folder
   (`~/Documents/Visual Studios/Projects/spiders`), no commits to `main`, no changes to its settings or data. All
   work happens on the `windows` branch.
2. **`Sources/` on the `windows` branch is a read-only copy of the Mac code.** It only changes through the oracle
   refresh in section 6.4. Windows behavior never comes from editing it.
3. **The Mac build decides what is right.** Where the spec, the plan and the Swift disagree, the Swift wins. Where the
   Swift and the running Mac app disagree, the running app wins.
4. **A passing check is not parity.** The old 1,050-check suite passed while most of the product was missing, because
   it tested the C# against a description of itself. A feature only counts as matching at evidence level E3 or E4
   (section 8).
5. **Never loosen a tolerance to make something pass.** Record the divergence in the status file instead.
6. **Commit often, to `windows` only.** Nothing important lives only in a working tree. That is how the port went
   for months with no commit at all.
7. **The GitHub repo is public.** Signing keys, certificates, private data files and session logs never get committed.
   `build/windows/keys/windows-update-key.json` is the private update-signing key: it stays on the laptop and needs its
   own backup outside git.
8. **The laptop is shared with its owner** (section 5).

---

## 2. Where everything lives

| What | Where | Notes |
|---|---|---|
| Mac app, the real one | Mac: `~/Documents/Visual Studios/Projects/spiders` | **Do not touch.** Has uncommitted work of its own. |
| Mac dev clone | Mac: `~/Documents/Visual Studios/Projects/spider-buddy-windows` | Branch `windows`. **All editing happens here.** Oracle captures also build and run here. |
| Laptop checkout | Laptop: `C:\Users\User\Documents\Projects\spider-buddy` | Branch `windows`. Builds and runs here. Receives pushes (`receive.denyCurrentBranch=updateInstead`). Do not edit here. |
| Backup | GitHub `Ephemerill/spider-buddy`, branch `windows` | Pushed from the Mac, because the laptop's GitHub login does not work over SSH. |
| .NET SDK | Laptop: `<repo>\.tools\dotnet` | Inside the repo folder, ignored by git. The system `dotnet` has no SDK: always use this one (`lap` does). |
| Swift 6.4.2 | Laptop: `%LOCALAPPDATA%\Programs\Swift` | Installed with winget, with VS 2022 Build Tools and the Windows 11 SDK. `build-trace.ps1` sets up the environment. |

| Machine | Facts |
|---|---|
| Mac | Mac14,9 (M2 Pro), 16 GB. Xcode at `/Applications/Xcode.app`. Display 3024x1964 at 2x. |
| Laptop | `ssh laptop`. HP ZBook Firefly 14 G11, Core Ultra 7 165H, 32 GB. Windows 11 Pro build 26300. 1920x1200 at **150%** (DPI 144), 60 Hz. User `User` is an admin. |

### Files in this branch

| Path | What it is |
|---|---|
| `WINDOWS_DEV_WORKFLOW.md` | This file |
| `WINDOWS_PARITY_STATUS.md` | One table: every feature and its evidence level. The current truth. |
| `WINDOWS_WORKLOG.md` | Dated log of what was done, found and decided |
| `WINDOWS_PARITY_PLAN.md` | The phased plan and technical detail per phase |
| `WINDOWS_PORT_SPEC.md` | Long description of the Mac app, written for the first port. Useful as a map, but the Swift outranks it. |
| `docs/windows/` | Older material: audit, Mac capture guide, progress log of the first port attempt |
| `Sources/` | Mac Swift, read-only, the oracle |
| `src/` | Windows code. `SwiftShims` and `SwiftHost`: the Swift path. `Core`, `Renderer`, `App`, `Tools`: the older C# port |
| `tools/windows/dev/` | `lap`, the laptop bridge, `difftrace.py`, `paritytraces.py`, `diffimages.py` |
| `tools/windows/swift/` | `build-trace.ps1` (builds the Swift side on the laptop), `bt` (runs it from the Mac and shows the errors), `imgrun` |
| `tools/windows/` | Packaging, signing, release and the release gate |
| `tools/trace`, `rngprobe`, `imagedump`, `scrollprobe`, `capture-*.sh` | Mac-side oracle tools |
| `tests/golden/` | Scenarios and desktops shared by both sides; captured Mac results |

---

## 3. The daily loop

Edit on the Mac, build and run on the laptop, compare on both.

```bash
cd ~/Documents/Visual\ Studios/Projects/spider-buddy-windows
export PATH="$PWD/tools/windows/dev:$PATH"
```

```
1. Read the Swift for the feature (Sources/DesktopSpider/...).
2. Edit in the Mac clone.
3. lap sync-wip      copy uncommitted changes over, for quick loops
   lap build         15 s or so
   lap tools ...     headless checks, traces, renders
   lap run ...       the real app on the real desktop
   lap shot out.png  look at it
4. Compare with the Mac (section 7).
5. Record the result (section 9). Commit.
6. lap revert-wip    only if you used sync-wip: clears the copies so the push applies
   lap sync          push the commit to the laptop checkout
   git push github windows   back it up
```

`lap sync` refuses a dirty tree on purpose. If a push to the laptop is refused, its checkout has stray changes:
`lap status`, then `lap revert-wip`.

### `lap` commands

| Command | Does |
|---|---|
| `lap sync` | Push the current commit to the laptop checkout |
| `lap sync-wip` / `lap revert-wip` | Copy uncommitted changes over / throw those copies away |
| `lap status` | Laptop git state and session info |
| `lap build [Release\|Debug]` | Build tools and app on the laptop |
| `lap tools <args>` | Run the headless harness (`all`, `stage4`, ...) |
| `lap run [--env K=V]... [--log name] [--wait secs] <exe> [args]` | Start something **in the real desktop session** |
| `lap log <name> [n]` | Last lines of a bridge-run program's output |
| `lap stop` | Kill `SpiderBuddy.exe` |
| `lap shot <out.png> [x y w h]` | Screenshot the real desktop into a Mac file |
| `lap idle` | Minutes since the owner touched the laptop (`none`, `.` or a low number means in use) |
| `lap ps [file]` | Run a PowerShell script from a file or stdin on the laptop |
| `lap fetch <remote-rel> [local]` / `lap put <local> <remote-rel>` | Copy files, relative to the laptop repo |

### Building and checking the Swift side

```bash
tools/windows/swift/bt -Check                # typecheck everything: 45 s
tools/windows/swift/bt                       # Trace.exe: 4 min
tools/windows/swift/bt -NoTrace -ImageDump   # ImageDump.exe
tools/windows/swift/bt -NoTrace -SpiderHost  # the desktop host
lap run --log host --env SPIDER_HOST_LOG=1 'build\swift\SpiderHost.exe' 25    # 25 s on the real desktop, then quits
tools/windows/dev/paritytraces.py capture/traces <work-dir>                   # every trace against the Mac
tools/windows/swift/imgrun capture/images <work-dir>                          # every image against the Mac
```

The stand-in modules in `src/SwiftShims` carry Apple's names, so `Sources/` compiles unchanged. Anything needed from AppKit
or Core Graphics goes there, not into the Mac sources. The two text swaps the trace build makes (seeded `Bool.random`,
pinned hour) are the same ones `tools/trace.sh` makes on the Mac; the host build makes none.

---

## 4. Why SSH needs a bridge

SSH lands in **session 0**, which has no desktop. A GUI program started directly over SSH runs but is invisible, sees no
windows and takes no real input. So anything that needs the desktop goes through `lap run` / `lap shot`:

```
Mac --ssh--> session 0 --one-shot scheduled task (Interactive logon)--> session 1 (the real desktop)
```

`tools/windows/dev/bridge-run.ps1` registers a task, starts it under `conhost --headless` (so no console window
flashes or takes focus), and removes the task. Output goes to `%TEMP%\spider-bridge\<name>.log`.

Headless things (builds, `SpiderBuddy.Tools`, git) do not need this and run directly.

**If a screenshot fails or comes back black:** the laptop is asleep or locked. It sleeps after 25 minutes idle on power,
10 on battery. Do not change power settings. Ask the owner, or wait.

---

## 5. Sharing the laptop

The owner uses this laptop for coursework and may take over at any time.

- Check `lap idle` before anything that takes over the screen or sends input. `none`, `.` or a low number: they are
  there.
- **Fine anytime:** builds, headless tools, and running the overlay. A spider on the desktop does no harm, but stop it
  when done (`lap stop`).
- **Only when idle:** synthetic mouse or keyboard input, and tests that open, move or resize windows. Aim input at the
  app's own windows, never at another program.
- **Never:** close, move or type into the owner's apps; change system settings (display scale, power, theme,
  notifications); leave things running; reboot.
- Long CPU work runs at low priority.
- If they take over mid-test, stop and carry on with something headless.

---

## 6. The oracle: recording what the Mac does

The oracle is the Mac code at a pinned version, run by tools that record what it does.

**Pinned version:** `Sources` tree `7c878d73`, which is v1.0.1 (commit `e0717d1` on `main`). The owner's Mac working tree
also has about 4,000 uncommitted lines, the new leg system v2 behind a Studio toggle that is off by default. That is a
later step, recorded in the status file.

### 6.1 Running captures

Captures run in the Mac dev clone, never in the real Mac repo. The tools compile a subset of `Sources/` into small
binaries under `build/`, which is ignored on this branch.

```bash
./tools/capture-all.sh capture                       # everything (hours)
STEPS="manifest rng images traces" SEEDS="1" KIN_SEEDS="1" SCALES="0.95" ./tools/capture-all.sh capture-quick
```

- Always `SWIFT_DETERMINISTIC_HASHING=1` (the scripts set it) or runs are not repeatable.
- **Never run `tools/art.sh`:** it overwrites `Resources/`.
- Results go to `tests/golden/mac/` when they are worth keeping, with `MANIFEST.json` saying which Swift made them.
- Bulky results and all video stay out of git (see section 9.3).

### 6.2 Running the real Mac app without touching the owner's spider

The app's screenshot hooks need the real app, and the app reads its settings from `com.gabriel.desktopspider`, which holds
the owner's spider. **Do not run `tools/capture-app.sh` as written:** it exports and rewrites those settings and
restores them afterwards, so a crash in the middle would lose them. Also, the `defaults` command is known to read the
wrong store for these builds.

Instead the oracle app is built from this clone with **its own bundle id** (`com.gabriel.desktopspider.oracle`), so it has
its own settings and support folder and cannot see the real ones. Its windows do appear on the Mac's screen while
hooks run, so these runs wait until the Mac is not in active use or are short.

### 6.3 What is captured

`MAC_HANDOFF.md` (in `docs/windows/`) lists every item. In short: pose traces, RNG fixtures, per-option images,
film strips, numeric reports, UI screenshots, recordings for feel, perf numbers, data files.

### 6.4 Refreshing the oracle

Only when the owner says the Mac version has moved on. Never merge `main` into `windows`.

```bash
git fetch github
git checkout <ref> -- Sources          # also Resources, Extension if they changed
git diff --cached --stat               # this is the list of things to port
```

Update the pinned version here, re-capture, and add a status row for each changed feature.

---

## 7. Comparing the two

The Mac and laptop are both available in one session, so comparison is direct. In order of strength:

### 7.1 Pose traces: is the motion the same?

Both sides run the same scenario (`tests/golden/scenarios/*.json`) on the same synthetic desktop
(`tests/golden/desktops/desk-a.json`) with the same seed at a fixed 1/60 s step, writing one JSON line per frame with
every pose field.

| Scenario type | Passes when |
|---|---|
| Exact | Every frame: positions and joints within 0.02 units, angles within 0.002 rad, 0-to-1 scalars within 0.005, discrete fields equal |
| Statistical | Over 8 seeds: every activity's share of time within 2 points or 25%, and the same set of activities occurs. Not needed while the Swift core is shared: even free runs match frame by frame. |

The first failing frame and field is what to fix. Early failures matter more than late ones.

### 7.2 Image diffs: is the art the same?

Same input on both sides, rendered at the same size, composited over `#808080`. Pass: SSIM at least 0.985, mean error at
most 3/255, under 0.4% of pixels off by more than 64/255. Text is compared by layout, not pixels. Failures
produce a three-panel picture (Mac, Windows, amplified difference) for looking at.

### 7.3 UI: does it look the same?

**Look at both.** Capture the Mac UI with the oracle app's hooks, capture Windows with `lap shot`, and put them side by
side at the same logical size. Mac screens are 2x and the laptop is 1.5x, so compare in logical points: Mac pixels / 2 =
Windows pixels / 1.5. For every screen check control sizes, spacing, fonts, colors, corner radii, shadows, wording,
order, and every state (hover, pressed, selected, disabled).

### 7.4 Live side by side: does it feel the same?

Run the real app on both machines and do the same thing on each: drag a window with the spider on it, throw it, feed
it, scroll over it. Record both when it matters. Metrics have passed before on things that still looked wrong (this
project's history has many such rounds), so **the owner's eye on the real drawn output is the final check** for motion
and feel. Their judgement is on what is drawn, for example leg crossings as they appear on screen, not a measure of them.

### 7.5 Numeric reports

`walk.sh`, `legs.sh`, `jerk.sh`, `smooth.sh`, `sim.sh`, `bench.sh` on the Mac give targets: planted-foot slip, bone stretch,
jerk flags per minute, behavior mix, frame cost.

---

## 8. What "matches" means

Each feature in the status file has one level. Only E3 and E4 count as parity.

| Level | Meaning |
|---|---|
| E0 | Not there, or fallback only |
| E1 | Exists and works by itself; never compared |
| E2 | Compared with the Mac; known differences listed |
| E3 | Measured equal: trace or image diff passes against the oracle, or for UI, a side-by-side with no differences left |
| E4 | E3, plus live on the real desktop on both machines and looked at; the owner has signed off where the feature is about feel |

Moving a feature up requires naming the evidence (trace file, image, screenshot pair, recording).

---

## 9. Records

### 9.1 What goes where

| Record | Update when | Contents |
|---|---|---|
| `WINDOWS_PARITY_STATUS.md` | Any feature changes level | The table. Short. No history. |
| `WINDOWS_WORKLOG.md` | End of each work block, and any decision or surprise | Date, what was done, evidence, decisions and why, what is next |
| This file | The way of working changes | Keep it true: if a command stops working, fix it here the same day |
| `WINDOWS_PARITY_PLAN.md` | The plan itself changes | Note it in the work log too |
| Mac memory folder | Facts a future session needs that the repo does not hold | The session's own memory |

### 9.2 Commits

- Small, one purpose each, on `windows`. Say what changed and what evidence it has.
- Commit messages end with the attribution line given in the session.
- Author: Gabriel Losh, with the GitHub noreply address (the repo is public).
- Push to GitHub at the end of each block: `git push github windows`.

### 9.3 Big files

`out/`, `build/`, `.tools/`, `capture*/` are ignored. Goldens under `tests/golden/mac/`: commit text fixtures and small
images when the total stays reasonable. Traces and video stay outside git: compress them and keep them in a folder listed
in `tests/golden/mac/MANIFEST.json`.

---

## 10. Traps that have already cost time

| Trap | What to do |
|---|---|
| PowerShell through `-Command -` on stdin breaks multi-line syntax silently | Use `lap ps`, which uploads a file |
| `%CD%` in one cmd line expands before `cd` runs | Use absolute paths |
| `ssh://laptop/C:/...` git URLs fail, and cmd mangles git's quotes | Remote is `laptop:C:/...` with `remote.laptop.uploadpack` and `receivepack` set to `powershell -NoProfile -Command git upload-pack` / `receive-pack`. A fresh clone needs those set again. |
| Pushing to GitHub from the laptop hangs on a login prompt over SSH | Push from the Mac |
| VBScript launchers do nothing on build 26300 | `conhost --headless` |
| A GUI started directly over SSH is invisible | `lap run` |
| macOS `tar` adds `._*` files that break Swift builds on the laptop | `COPYFILE_DISABLE=1 tar --no-mac-metadata` (`lap sync-wip` does this) |
| A git commit message with `-m` or a here-string through PowerShell | Write the message to a file, use `-F` |
| `defaults` reads the wrong settings store for these Mac builds | Do not use it; the oracle app has its own bundle id |
| `tools/art.sh` rewrites `Resources/` | Never run it |
| The trace tool reading the hour of day | `TR_HOUR` pins it; a warning prints if a read was missed |
| `SWIFT_DETERMINISTIC_HASHING` does nothing on Windows | Test tools call `CGPinHashingForTests()` first thing. Without it, traces vary from run to run. |
| Tools listing their Swift files explicitly | A new Swift file must be added to each tool's list |
| PowerShell splats a one-item list as characters: `@files` | Wrap it: `@(Get-ChildItem ...)` |
| Swift's `CGColor(red:...)` looks like sRGB and is not | It is Generic RGB at gamma 1.8. See `Color.swift`. Bodies look subtly wrong if this is skipped. |
| Swift sees `TrackPopupMenu`'s result as a `BOOL` | The chosen command cannot be read back; give it a window message instead when a menu has several items |

---

## 11. Accepted differences

Only things that cannot be the same, or that the owner has agreed. Anything else is a bug.

| Mac | Windows | Why |
|---|---|---|
| SF Pro | Segoe UI Variable, sizes and weights matched | SF Pro cannot be shipped on Windows |
| Menu bar and its icon | System tray icon, same menu | No menu bar |
| Menu bar height, notch, Dock | Work area and taskbar | Platform (spec section 2.8) |
| Desktop widgets as furniture | None | No equivalent |
| Sparkle updates | The app's own signed updater | Platform |
| Apple Intelligence chat | To be decided by the owner | No equivalent on Windows |

---

## 12. Starting a new session

1. Read this file, the status file, and the last work log entry.
2. `git -C ~/Documents/Visual\ Studios/Projects/spider-buddy-windows status`, then `lap status` and `lap idle`.
3. Pick the next item from the status file.
4. Before stopping: commit, sync, push to GitHub, update status and work log, `lap stop`.
