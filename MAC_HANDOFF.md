# Mac handoff: everything to capture on the Mac and bring to the Windows port

This is the step-by-step list of what to get from a Mac, how to get it, what each thing is for, and how to
bring it over. It goes with `WINDOWS_PARITY_PLAN.md` (which says what the Windows side does with it).

**Why this is needed.** The Windows spider is judged against the Mac spider. Without recorded Mac output, "looks and
feels the same" can only be argued from reading code. With it, the Windows build can be checked frame by frame
(poses), pixel by pixel (art), and by eye (recordings).

**Time.** About 1 hour of your attention and 2 to 4 hours of machine time for Parts 1 to 3 (mostly unattended),
about 2 hours for the recordings (Part 4), 30 minutes for Parts 5 to 8.

**What was written without a compiler.** The tools below (`tools/trace`, `tools/rngprobe`, `tools/imagedump`,
`tools/scrollprobe`, `tools/capture-all.sh`, `tools/capture-app.sh`) were written on Windows, against the Swift
sources, with no Swift compiler available. I checked every API they call against the source, but expect a compile
error or two the first time. Paste the compiler's message and it will be fixed quickly. See Part 10 for the likely ones.

---

## Part 0. How the pieces fit

```
Mac                                              Windows
-----------------------------------------------  ------------------------------------
tests/golden/scenarios/*.json   (shared)    ───►  the same files drive the C# tool
tests/golden/desktops/desk-a.json (shared)  ───►  the same desktop
tools/trace  → traces/*.jsonl  (poses)       ───►  compared frame by frame
tools/rngprobe → rng.json                    ───►  C# random generator must match
tools/imagedump → images/*.png + *.pose.json ───►  compared pixel by pixel
existing tools → film / gallery / reports    ───►  visual reference + numeric targets
app hooks → panel, Studio, welcome PNGs      ───►  UI compared
screen recordings                            ───►  feel judged by eye
perf numbers, data files, audio, probes      ───►  targets and compatibility tests
```

The scenario and desktop files live in the repo already (created on Windows, in `tests/golden/`). The Mac reads
them; it does not need to author anything.

---

## Part 1. Set up the Mac (15 minutes)

1. **Mac requirements.** A Mac you can use interactively (the tools open AppKit and read the main screen), with
   **full Xcode** installed (not only Command Line Tools). `build.sh` prefers `/Applications/Xcode.app`. Run
   `xcodebuild -version` and `xcrun swiftc --version` to check. About 5 GB free disk.
2. **Get this repo onto the Mac, including the files made on Windows.** On Windows, commit and push:
   `tools/trace*`, `tools/rngprobe*`, `tools/imagedump*`, `tools/scrollprobe*`, `tools/capture-*.sh`,
   `tests/golden/`, and the two `*.md` files. (Or copy the folder over by any means.) Then on the Mac use a
   **fresh clone** so the build outputs (some `build/*` files are tracked by git) do not dirty your working copy:
   ```
   git clone <your repo url> spider-buddy-oracle
   cd spider-buddy-oracle
   chmod +x tools/*.sh build.sh run.sh
   ```
3. **Pin the oracle.** The oracle is the `Sources/` folder. Record its identity (the capture script also does this):
   ```
   git rev-parse HEAD
   git rev-parse HEAD:Sources        # a hash of just the Swift sources
   cat VERSION
   ```
   The Windows work has not edited `Sources/`, so the `Sources` hash should equal the one at commit `e0717d1` or
   the release you consider the reference. If you have uncommitted Swift changes on your Mac, commit them first;
   the capture must match a known state.
4. **Quiet the machine for the run.** Plug in the charger, disable sleep (`caffeinate -dimsu &` in a spare
   Terminal tab), close other apps, quit Spider Buddy if it is running (`killall DesktopSpider`). Do not use the
   mouse during Part 2 beyond starting it (the tools are headless, but some open AppKit).
5. **Display.** Note the main display's resolution and "Looks like" scale (System Settings → Displays). The tools
   that read `NSScreen.main` (preview, film, gallery, sim) depend on it. The new trace tool does not (it uses
   `desk-a.json`). The capture script records the display in `MANIFEST.json`.
6. **Locale/time.** Leave as is; the trace tool pins the hour (`TR_HOUR`, default 14).

---

## Part 2. The scripted capture (one command, mostly unattended)

```
cd spider-buddy-oracle
./tools/capture-all.sh capture 2>&1 | tee capture-run.txt
```

**Quick first pass** (about 20 minutes, to find compile problems early):
```
STEPS="manifest rng images traces" SEEDS="1" KIN_SEEDS="1" SCALES="0.95" ./tools/capture-all.sh capture-quick
```

**What it runs** (in order; a failing step is recorded in `capture/STATUS.tsv` and the run continues):

| Step | Command it runs | Produces (under `capture/`) |
|---|---|---|
| `manifest` | git, `sw_vers`, `system_profiler`, `xcrun swiftc --version` | `MANIFEST.json` |
| `rng` | `tools/rngprobe.sh` | `rng/rng.json` |
| `images` | `tools/imagedump.sh` | `images/thumbs/<row>/NN-<case>-<side>.png` (Studio options), `images/poses/*.png` + `*.pose.json`, `images/index.json` |
| `tools` | the existing tools (below) | `tools/*` |
| `traces` | `tools/trace.sh` on the scenarios | `traces/<scenario>.s<seed>.<scale>.jsonl` |
| `free` | `tools/trace.sh` on `free-240`, seeds 1 to 8 | `free/free-240.s<seed>.jsonl` |

**The `tools` step in detail** (each is an existing script; the capture script runs it with fixed arguments):

| Output name | Source command | What it is for |
|---|---|---|
| `tools/contact.png`, `single.png`, `cliptest.txt` | `tools/preview.sh`, `build/Preview --single`, `--cliptest` | contact sheet of every size, body, coat, hat; one large pose; the **draw-radius** number the sprite size comes from |
| `tools/studio-96.png`, `-192`, `-288` | `build/Gallery out [cell] [wrap]` | every Studio option, labelled, three sizes |
| `tools/film-edges.png` | `tools/film.sh` | the walk on each screen edge |
| `tools/film-cycle.png` | `film --cycle` | one gait cycle, large |
| `tools/film-desk.png` | `film --desk` | **actual size on a mock desktop, every edge kind**: the most useful single view |
| `film-hang`, `swing`, `hammock`, `jump`, `jump-under`, `drop`, `peekaboo`, `thoughts` | `film --hang` etc. | silk, hammock, air, peek-a-boo, thought art |
| `film-hunt-cricket`, `-worm`, `-fly` | `film --hunt cricket|worm|fly` | hunts (the film tool supports only these three; the others come from the traces) |
| `film-dance`, `film-dance-session` | `film --dance`, `--dance-session` | dance moves (`DANCE_BPM=120`) |
| `film-seq`, `film-strip-corner`, `-turn`, `-peek` | `film --seq ...`, `--strip corner|turn|peek` | hand-off, corner, turn, peek strips |
| `film-strip-<activity>` (33 of them) | `film --strip <activity> 2` | each activity as a strip |
| `walk-strip`, `walk-trace`, `walk-stats.txt`, `walk-why.txt` | `tools/walk.sh strip|trace|stats|why` | **numeric targets for the gait** (bone stretch, reach, planted-foot slip, pops, cadence) |
| `legs-flat.txt`, `legs-flat-dump.txt`, `legs-all.txt` | `tools/legs.sh flat|all` (`LC_DUMP`, `LC_SEEDS=12`) | leg quality, and a per-frame joint dump of flat window tops that the Windows legs must reproduce |
| `jerk.txt` | `tools/jerk.sh 600 4` | jerk flags per minute by activity pair (the spec's "under 2 a minute") |
| `smooth.txt` | `tools/smooth.sh all` | smoothness: hand-offs, sweeps, gaze, slide, icewalk |
| `sim-1.txt`, `-2`, `-3` | `tools/sim.sh` | the 240 s headless run: state percentages, transitions per second, `[ok]/[FAIL]`. Run three times because some checks are flaky |
| `bench.txt` | `tools/bench.sh` | cost of one rendered frame |
| `perch-sheet.png`, `perch-world-<preset>.png` (9), `perch-pieces.png`, `perch-build_*.png` | `tools/perch.sh sheet|world|pieces|build` | every habitat item with its shape, every ready-made world, structure pieces |
| `perch-nature/curious/places/ecology/nav/chains/air.txt` | `tools/perch.sh <mode>` | habitat behavior reports |
| `beat-synth/change/mixes/loops.txt` | `tools/beat.sh <mode>` | beat tracker accuracy on made-up patterns, tempo changes, mixes, Apple Loops |
| `ears.txt` | `tools/ears.sh` (15 s) | which apps the tap sees playing |
| `art/` | `build/Painter` | app icon and dmg background previews (see warning below) |

**Warning: do not run `tools/art.sh`.** It overwrites `Resources/AppIcon.icns` and `Resources/dmg-background.tiff`.
The capture script builds and runs the painter directly and writes previews only.

**The trace scenarios** (`tests/golden/scenarios/`, 31 files; all use `tests/golden/desktops/desk-a.json`, a
1920x1080 screen with three windows, no menu bar, no dock):

| Scenario | What happens | Seeds x sizes | Compared |
|---|---|---|---|
| `flat-walk` | walks right along a window top, no pauses, 12 s | 2 x 5 sizes | exact |
| `window-lap` | around the Notes window: corner, side, underside, far side, 40 s | 2 x 5 | exact |
| `turn-around` | walk, turn (through the front view), walk, turn, walk | 2 x 5 | exact |
| `stop-start` | walk, look, walk, rest, walk | 2 x 5 | exact |
| `carried` | the window is dragged under it and back | 2 x 5 | exact |
| `grab-throw` | grabbed, dragged, thrown at (900, 600) | 4 | exact first seconds |
| `soft-toss` | released slowly at (120, 60): rescue line | 4 | exact first seconds |
| `hang-swing`, `hang-still` | hangs and swings; line paid out and hauled in | 4 | exact |
| `jump` | leaps from one window to another | 4 | exact |
| `rappel`, `rappel-sign-flipped`, `climb` | scroll orders; **tells us the scroll sign** | 4 | exact; the sign pair is a calibration |
| `peekaboo` | hides behind a window edge and peeks | 4 | exact first seconds |
| `hammock` | builds a hammock, naps (60 s) | 4 | exact 10 s, then statistical |
| `hunt-<kind>` (8 kinds) | prey released; watch, stalk, pounce, carry, eat | 4 | exact 6 s, then statistical |
| `pointer-watch`, `pointer-overhead` | head and body follow the pointer; hover overhead | 4 | exact |
| `pointer-whip`, `pointer-stroke`, `pointer-fidget` | hop; stroke; stalk, pounce, cling | 4 | exact first seconds |
| `cinema` | the screen becomes a cinema: floor and ceiling only | 4 | exact |
| `activity` (37 names via `TR_ACT`) | each activity on a window top, 5 s | 1 | exact |
| `free-240` | the full free run, liveliness 3, a wandering pointer | 8, state only | statistical |

**Expected size and time.** Traces about 400 MB raw (about 50 MB zipped); images about 30 MB; tools output about
100 MB. Time: build steps about 15 minutes in total; trace runs are fast (a 12 s scenario takes a second or two);
`smooth all`, `walk stats` and `perch air` are the slow tools (minutes each). Total 1 to 3 hours.

**Two sanity checks the script already does**
- `traces/flat-walk.s1.0.95.Onone.jsonl` is the same scenario built without optimization. **Compare it to the normal
  one** (`cmp capture/traces/flat-walk.s1.0.95.Onone.jsonl capture/traces/flat-walk.s1.0.95.jsonl`). If they differ,
  the compiler fused arithmetic and the Windows tolerances need to be looser; tell me.
- **Determinism.** The same seed must give the same file every time. To prove it, run
  `LC_SEED=1 TR_SKIP_BUILD=1 ./tools/trace.sh tests/golden/scenarios/hunt-cricket.json a.jsonl` twice (to `a.jsonl` and
  `b.jsonl`) and `cmp a.jsonl b.jsonl`. If they differ, something is still reading the clock or hashing in a
  different order; tell me which scenario.

**If a step fails.** Look in `capture/capture.log` for the compiler or runtime message and in `STATUS.tsv` for
which step. Fix or skip (`STEPS=...`) and re-run; the script overwrites files, it does not append.

---

## Part 3. Screenshots from the real app (30 minutes)

```
./build.sh                      # makes spiders.app (fetches Sparkle the first time: needs the network)
./tools/capture-app.sh capture/app
PANEL_LIGHT=1 ./tools/capture-app.sh capture/app     # (optional) adds the light panel
```

It runs the app's own test hooks (they open a window, write pictures, quit). Your settings are backed up first
(`~/Desktop/spider-prefs-backup.plist`) and restored when it finishes; it runs the app against empty spider and
habitat libraries so the pictures are repeatable.

| Hook (env var) | Writes | For |
|---|---|---|
| `SPIDER_PANEL_SHOT=dir` | `panel0.png` to `panel6.png`, **dark** (the hook hard-codes `dark: true`) | panel pages (7) |
| same, light | via `PANEL_LIGHT=1` | panel in light mode |
| `SPIDER_STUDIO_SHOT=dir` | `studio_tab0.png` to `studio_tab11.png` | the 12 Studio tabs |
| `SPIDER_STUDIO_SHOT_CUSTOM=1` | same, hand-shaping sliders shown | Body tab with sliders |
| `SPIDER_STUDIO_SHOT_VOICE=pictures|phrases|intelligence` | Thoughts tab in each mode | Thoughts tab |
| `SPIDER_WELCOME_SHOT=dir` | `welcome1.png`... | welcome tour pages |
| `SPIDER_BUG_SHOT=dir` | `bug_form.png`, `bug_peek.png` | bug report |
| `SPIDER_HABITAT_SHOT=dir` | habitat pictures (`runHabitatShots`) | habitat window |
| `SPIDER_WEATHER_SHOT=dir` (+ `_KINDS`, `_BIOMES`) | the tank in every weather and biome | habitat weather art |
| `SPIDER_HABITAT_TOUR=dir` | both tours step by step, the weather panel, My Habitats | habitat UI |
| `SPIDER_ENTRANCE_TEST=8` | text: the spider's position every quarter second | **first-entrance path numbers** |
| `SPIDER_FRAMES=1 SPIDER_TIMING=1 SPIDER_STATS=1` | text: fps, per-phase ms, update/apply times (30 s idle) | performance targets |
| `SPIDER_OPEN_TIMING=1` | text: how long the panel, Studio and habitat take to open | open-time targets |

Notes:
- The settings domain is the bundle id `com.gabriel.desktopspider` (from `build.sh`); `spiders.app` and "Spider Buddy"
  share it.
- If the welcome window gets in the way, `welcomed` must be true; the script sets it.
- Check the pictures afterwards: `ls capture/app/*/` should show about 7 panel, 12 studio (+12 custom, +36 voice),
  welcome pages, bug, habitat, weather and tour pictures. Empty folders mean that hook did not run: see
  `capture/app/capture-app.log`.

**Optional behavioral logs** (each prints `[ok]/[FAIL]` lines describing what the real app does; the Windows
port ports these test hooks later): `SPIDER_TRACE_TEST`, `SPIDER_TOY_TEST`, `SPIDER_VISITORS_TEST`,
`SPIDER_WIDGET_TEST`, `SPIDER_WILD_TEST`, `SPIDER_MINIMIZE_TEST`, `SPIDER_SPIDERS_TEST`, `SPIDER_LOCK_TEST`,
`SPIDER_HABITAT_TEST`. Find each one's expected value with `grep -n 'SPIDER_TOY_TEST' Sources/DesktopSpider/*.swift`,
run it as `SPIDER_TOY_TEST=1 ./spiders.app/Contents/MacOS/DesktopSpider > capture/app/toy-test.txt` (some need a
directory or a number instead of `1`), and keep the output. Low priority.

### Screenshots to take by hand (the app has no hook for these)

Use Shift-Command-4 then Space (window capture, includes shadow) or Shift-Command-5 (selection). Save as PNG.
Name them `ui-<name>.png` in `capture/app/manual/`.

| Name | What | Why |
|---|---|---|
| `ui-menubar-icon-normal`, `ui-menubar-icon-hidden`, `ui-menubar-icon-wiggle` | the menu-bar icon, spider shown, spider hidden (dimmed), and during the entrance | tray icon art, 1x and 2x (zoom in to capture it big) |
| `ui-menubar-menu` | the menu-bar icon's menu, open | tray menu item order and wording |
| `ui-context-menu` | right-click menu on the spider, open | spider menu |
| `ui-context-menu-sub-*` | each submenu opened (Behavior, Feed, Size, Energy, Toggles...) | menu structure |
| `ui-panel-popover` | the panel open under the menu-bar icon (whole screen top) | popover placement |
| `ui-thought-bubbles` | each bubble kind on screen next to the spider | bubble placement (screen space) |
| `ui-name-tag` | name tag after hovering 1 s | name tag |
| `ui-hammock-closeup`, `ui-silk-closeup` | zoomed crops of the hammock and a thread | silk drawing |
| `ui-box-dim`, `ui-box-outline` | the dimmed screen while drawing a box, and the dashed outline after | box UI |
| `ui-toys-*`, `ui-prey-*` | each toy and each of the 8 creatures on screen, zoomed | creature art |
| `ui-visitors` | visitors present | visitor look |
| `ui-rain` | rain on the screen | rain look |
| `ui-habitat-toolbar`, `ui-habitat-decorate`, `ui-habitat-myhabitats` | the habitat window's chrome | habitat UI |
| `ui-update-dialog`, `ui-about` | the update dialog and anything in the app menu | shell |

Take them at the display's native resolution (do not downscale).

---

## Part 4. Screen recordings (about 2 hours)

These carry the "feel": timing, speed, personality, what reacts to what. Metrics did not catch feel problems on
the Mac side; recordings do.

**Recorder.** OBS Studio (free) is simplest for a guaranteed rate: Settings → Video: base and output resolution =
your display's logical size (e.g. 1512x982), FPS = **60**; Output: MP4, H.264, CQP 18. Source: Display Capture.
(QuickTime/Shift-Command-5 may record at a variable rate; avoid.) Record **without** the pointer hidden (show the
pointer: it is part of the interaction). Use a normal desktop: three or four real windows open (a browser, a text
editor, a Finder window), not a clean desktop, with the Dock at the bottom.

**Spider setup for every clip** unless stated: default settings, scale "Medium" (0.95; say which you use),
Click to Pick Up on, Watch/Come to Cursor on, defaults for everything else. Run `defaults delete
com.gabriel.desktopspider` once and relaunch for a first-run-like state.

**Naming:** `capture/video/NN-name.mp4`; write one line in `capture/video/NOTES.txt` per clip: date, spider scale,
what you did, anything unusual.

| # | Clip (length) | Exactly what to do |
|---|---|---|
| 01 | `idle-life` (3 min) | Leave the mouse alone, off to the side. Do not touch anything. |
| 02 | `walk-surfaces` (60 s) | Let it walk along a window top, around a corner, down a side, under a window, onto the next window. Do nothing; if it won't, use the menu (Behavior) to nudge it. |
| 03 | `window-drag` (60 s) | With the spider on a window: drag the window slowly, then fast, resize it larger and smaller, minimize it (Genie/Scale), restore it, close it. |
| 04 | `window-cover` (45 s) | Drag another window over the one the spider is on (it hides behind it, peek-a-boo, escapes). Do it from above and from the side. |
| 05 | `grab-throw` (60 s) | Pick up, carry slowly, put down on another window; flick it hard at the screen edge; a soft toss and watch the rescue line catch. |
| 06 | `pointer-play` (90 s) | Hover until the name tag shows; single click; double-click; right-click (menu); stroke back and forth over it; whip the pointer across it; hold the pointer still overhead; fidget close by until it stalks, pounces and clings; shake it off. |
| 07 | `silk` (90 s) | Scroll down over it (rappel); scroll up (climb); wait for a swing; scroll while it swings. Note which direction you scrolled and whether "natural scrolling" is on. |
| 08 | `hammock` (3 min) | Build Hammock from the menu; watch it build, nap, wake; wipe the pointer across the hammock. |
| 09 | `prey` (4 min) | Feed one of each of the 8 creatures; let each hunt finish. Let wildlife wander in (Wildlife on) for 2 minutes. |
| 10 | `toys` (3 min) | Each toy in turn: ball, feather, bell (sounds on), wind-up bug; the laser; put each away with right-click and with Esc. |
| 11 | `traces` (3 min) | Traces on; leave it alone; then Tidy Up. |
| 12 | `visitors` (3 min) | Visitors on, invite one; watch hello, tag, leaving; Dismiss. |
| 13 | `box` (90 s) | Keep in a Box: the dim and drag; the spider inside; redraw; release. |
| 14 | `sensing` (4 min) | Play a full-screen video (cinema); plug and unplug the charger; Low Power Mode on and off; trigger a notification banner; change the volume; change the brightness. Narrate by saying the name of each aloud if you record voice, or note times in NOTES.txt. |
| 15 | `music` (3 min) | Play a steady 120 BPM song, then a speech podcast, then silence. Note times. (Audio is not recorded; only the reaction.) |
| 16 | `rain` (60 s) | `SPIDER_RAIN=1` launch: the 3.5 s rain thought and the streaks. |
| 17 | `lock-unlock` (60 s) | Lock the screen, wait, unlock: sleeps, then greets. |
| 18 | `welcome-entrance` (3 min) | Delete the settings (`defaults delete com.gabriel.desktopspider`), launch: the welcome tour, each page, then the first entrance. |
| 19 | `habitat` (6 min) | Open the habitat; each of the 9 presets in turn (Forest Floor, Jungle Canopy, Desert Scrub, Meadow, Cave, Beach, Tundra, Moonlit, Empty), 30 s each; weather kinds; Decorate mode; the tour; My Habitats; close it. |
| 20 | `talking` (2 min, only if Apple Intelligence is available) | Open the chat, a few replies, click a thought bubble. |
| 21 | `menus` (3 min) | Toggle every menu item once, with a visible effect where there is one. |
| 22 | `scroll-sign-check` (30 s) | One mouse-wheel notch down, then up, then a trackpad swipe down, up. Show whether the spider rappels on down. Do it with natural scrolling **on**, then **off**. |
| 23 | `hit-test-check` (60 s) | Put the pointer near the spider's body edge and move out in 5-pixel steps clicking; show where the pick-up stops working (the grab radius is 30 x scale). Show a click just outside reaching the window behind. |
| 24 | `display-corners` (60 s) | Zoomed-in recording of the spider walking round a window corner at 1x, to see the corner radius it follows (26 pt). |

Optional extra: a second set of 01, 02, 05 and 06 at scale "Tiny" and "Chonky" (the size extremes).

---

## Part 5. The scroll probe (5 minutes)

The Windows wheel must produce the same orders as the Mac's trackpad and wheel. This logs the actual numbers.

```
./tools/scrollprobe.sh 60 > capture/scroll-natural-on.txt
```
During the 60 s: three mouse-wheel notches **down**, three **up** (if you have a mouse), a trackpad two-finger swipe
**down**, one **up**, a slow drag. Then turn **Natural scrolling** off (System Settings → Trackpad, and Mouse) and run
again to `capture/scroll-natural-off.txt`. Turn it back on afterwards if you want it. If a global monitor prints
nothing, grant the Terminal "Input Monitoring" in System Settings → Privacy & Security and rerun.

---

## Part 6. Performance numbers from the real app (15 minutes)

`capture-app.sh` already saves a 30 s idle frame meter. Add these by hand, with the real Spider Buddy build
(`./run.sh` or the release app), each for 60 s, noting CPU% and memory from Activity Monitor (select the app,
View → Update Frequency: Very Often) or `top -pid $(pgrep DesktopSpider) -l 12 -stats pid,cpu,mem,rsize`:

| Situation | What to do | Save |
|---|---|---|
| idle, standing | spider resting on a window, pointer away | `capture/perf/idle.txt` |
| walking | walk menu or let it | `walking.txt` |
| hunting | feed a cricket | `hunting.txt` |
| silk + hammock | built hammock, hanging | `silk.txt` |
| traces + prey + toys | everything on | `busy.txt` |
| habitat calm | habitat open, clear weather | `habitat-calm.txt` |
| habitat storm | habitat open, storm weather | `habitat-storm.txt` |

Run the app with `SPIDER_FRAMES=1 SPIDER_TIMING=1 SPIDER_STATS=1 ./spiders.app/Contents/MacOS/DesktopSpider
2>&1 | tee capture/perf/<name>.txt` so the printed per-second meter and your `top` numbers are saved together.
Also write the Mac model and chip into `capture/perf/README.txt` (CPU numbers only compare on like machines).

---

## Part 7. Data files for compatibility (10 minutes)

So the Windows app can load whatever the Mac app saved. **Look through them before sending.** They contain your
spider names, habitat names and anything you typed as custom thought phrases, nothing else.

```
mkdir -p capture/data
# the app's settings (this is where the spec's Appendix B keys live; memory is in here too)
cp ~/Library/Preferences/com.gabriel.desktopspider.plist capture/data/settings.plist
plutil -convert xml1 -o capture/data/settings.xml capture/data/settings.plist
plutil -convert json -o capture/data/settings.json capture/data/settings.plist || echo "(JSON refused: binary values; the XML copy has them)"
# the saved spiders and habitats
cp -R ~/Library/Application\ Support/com.gabriel.desktopspider/Spiders capture/data/Spiders 2>/dev/null
cp -R ~/Library/Application\ Support/com.gabriel.desktopspider/Habitats capture/data/Habitats 2>/dev/null
ls ~/Library/Application\ Support/com.gabriel.desktopspider/ > capture/data/support-folder-listing.txt
```

What is wanted, so make some if you have none:
- **5 to 10 saved spiders** with different hats, coats, patterns, eyes, personalities and names (Studio → My Spiders).
- **3 saved habitats**: one with decorations, one with a built structure, one empty (Habitat → My Habitats).
- A **spider that has played for a while** (so `memory` in the settings is non-trivial: lessons, favorite places).
- If the app is the "Spider Buddy" release rather than the "spiders" test build, the same bundle id is used, so the
  paths are the same.

Also, if you have a **`.spiderhabitat`** file that was exported, include it (it should be the same JSON).

One more file: the default design as JSON. This writes it using the app's own encoder:
```
mkdir -p build/dd && cat > build/dd/main.swift <<'EOF'
import AppKit
let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try! e.encode(SpiderDesign()), encoding: .utf8)!)
EOF
xcrun swiftc -O -swift-version 5 -DSHAPED -framework AppKit -o build/DesignDump \
  Sources/DesktopSpider/{Math,Surfaces,WindowTracker,Spider,Beat,Memory,SpiderRenderer,AppIcon,SpiderDesign,Skin,Prey,Toys,Traces,Habitat,HabitatObjects,HabitatGeometry,HabitatStructures,HabitatPieces,HabitatNature,HabitatSemantics,HabitatKnowledge,HabitatPlaces,HabitatEcology,HabitatNav,Studio}.swift \
  build/dd/main.swift && ./build/DesignDump > capture/data/default-design.json
```

---

## Part 8. Audio and web pages for the other tools (15 minutes)

**Beat tracker.** `tools/beat.sh loops` reads Apple Loops from the Mac (GarageBand content). The `synth`, `change` and
`mixes` modes need no files and are already in the capture. For real-music checks:
- Pick **3 songs** of steady tempo (say about 90, 120 and 150 BPM), and **1 speech clip** (a podcast minute).
  `./tools/beat.sh file <path>...` and `./tools/beat.sh speech <clip>` print the tempo and confidence over time.
  Save the outputs: `capture/beat/file-<name>.txt`, `capture/beat/speech.txt`. Note each song's real BPM.
- **Do not put the audio files in the repo** (licensing). The Windows side can test with its own synthetic signals
  and your saved numbers; it only needs the text outputs. Optionally keep the songs on a drive for a local A/B.

**Page reader.** `tools/pages.sh see <in.png> <out.png>` shows what the spider would climb on a picture of a web page.
- Take **5 screenshots of real web pages** (a news site, a search results page, a long article, a dashboard, a photo
  grid) at the full window size, as PNG.
- Run `./tools/pages.sh see page1.png capture/pages/page1-ledges.png` for each, and `./tools/pages.sh time page1.png`.
- Keep **both** the input screenshots (they are just screenshots of public pages; blank any personal content) and the
  outputs. The Windows page reader is tested against the same pictures.

---

## Part 9. UI measurements (optional, 30 minutes, high value if you can)

For the panel, Studio and welcome to match, exact sizes and fonts beat eyeballing screenshots. The Swift source
already contains them (frames, font sizes and weights in `Panel.swift`, `Studio.swift`, `Onboarding.swift`,
`ChatPanel.swift`, `BugReport.swift`); I can read those directly, so **this part is only needed for anything computed at
runtime** (auto-layout text widths, system colors). Two cheap captures:

1. **Fonts used:** `grep -ho 'systemFont(ofSize: [0-9.]*, weight: \.[a-zA-Z]*)\|monospacedSystemFont([^)]*)\|NSFont(name: "[^"]*"' Sources/DesktopSpider/*.swift | sort | uniq -c | sort -rn > capture/ui-fonts.txt`
2. **System colors used:** `grep -ho 'NSColor\.[a-zA-Z]*' Sources/DesktopSpider/*.swift | sort | uniq -c | sort -rn > capture/ui-colors.txt`.
   Also, with both appearances, take a plain screenshot of a patch of `NSColor.windowBackgroundColor`, `controlBackgroundColor`,
   `labelColor` etc. if the source uses them (they differ between light and dark).

Also note: **does the app follow the system's light/dark setting, or force one?** Open the panel with the system in
light and in dark and say which (one sentence in `capture/NOTES.txt`). The panel hook hard-codes dark, which suggests
the panel is dark regardless; confirm.

---

## Part 10. If the new tools do not compile

Likely issues, and what to do. Send me the exact message; most are one-line fixes.

| Symptom | Likely cause | Fix |
|---|---|---|
| `Spider` has no member `debugX` | I used the name in `Spider.swift:19495-19810`; it may be `private` or renamed | send the error; I will adjust the command |
| `'release' is inaccessible` / unused result warning | signature differs from `release(_ kind:at:in:)` | check `Spider.swift:8904` |
| `ambiguous use of 'random'` in the rngprobe | the shadows in `tools/legs/Seeded.swift` clash with the standard library for a call I wrote | send the message; the fix is to call the shadow another way (`tools/legs` itself builds, so the pattern works there) |
| `value of type 'SpiderPose' has no member 'x'` in imagedump | a pose field I set does not exist under that name (`palpNear`, `headCock`, ...) | the list is `Spider.swift:111-215`; delete that line or rename |
| `cannot find 'traceHour'` | the sed in `trace.sh` replaced the hour read but `Hour.swift` was not linked | it is in the compile line; check the file exists |
| `warning: a calendar-hour read was not replaced` | Spider.swift changed its hour call | grep `Calendar.current` in `Sources/` and update the `sed` in `tools/trace.sh` |
| a film mode prints usage and quits | argument order differs | read the top of `tools/film/main.swift` |
| `error: no such module 'AVFoundation'` for beat | missing framework flag | `tools/beat.sh` already links it; run through the script |
| `defaults import` complains in capture-app | `Desktop` path or no plist existed | harmless if you had no settings; otherwise restore manually |

When a tool fails, `capture-all.sh` carries on; you can still ship everything else and the fixed tool later.

---

## Part 11. Bringing it over

1. **Check what you have.**
   ```
   column -t -s "$(printf '\t')" capture/STATUS.tsv | grep -v ' ok '      # anything FAILED?
   find capture -type f | wc -l ; du -sh capture capture/app capture/video 2>/dev/null
   ```
2. **Fill in `capture/NOTES.txt`**: who ran it, the Mac model/chip, macOS version, display, natural scrolling state,
   appearance, spider scale used for recordings, anything that went wrong or surprised you.
3. **Zip it** (keeps Mac metadata out of it):
   ```
   ditto -c -k --norsrc --keepParent capture capture-pose-and-images.zip          # without video
   ditto -c -k --norsrc --keepParent capture/video capture-video.zip              # videos separately
   shasum -a 256 capture-*.zip > capture-checksums.txt
   ```
   Expected: the first zip 100 to 300 MB, videos 1 to 4 GB.
4. **Transfer** by any means you like (iCloud Drive, a cloud drive link, AirDrop to a Windows machine via a drive, USB
   stick). **Do not commit video to git.** Commit the rest only if it is under about 300 MB, or use Git LFS for PNGs
   and put traces in a release asset instead.
5. **On Windows**, unzip so the layout is:
   ```
   tests/golden/mac/
     MANIFEST.json
     STATUS.tsv  NOTES.txt  capture-checksums.txt
     tools/        rng/        images/        traces/        free/
     app/          data/       perf/          pages/         beat/
     scroll-natural-on.txt     scroll-natural-off.txt
   (video/ stays outside the repo: put it anywhere and list its path in NOTES.txt)
   ```
   Verify the checksum: `Get-FileHash -Algorithm SHA256 capture-pose-and-images.zip` against the file.
6. **Tell me** it is there, plus anything from `NOTES.txt` that matters. First thing I do with it: run the 3.4 drift
   spike in the plan (`flat-walk` from both sides), which decides how strict the comparisons can be.

---

## Part 12. What the Windows side does with each item

| You bring | It becomes |
|---|---|
| `rng/rng.json` | unit tests for the C# SplitMix64 and each draw mapping (integers exact, doubles to the last bit) |
| `traces/*.jsonl` | `parity diff-trace`: first diverging frame, field and size, per scenario; the backlog for the behavior port |
| `free/*.jsonl` | the statistical comparison: activity percentages and transitions per second |
| `images/**` | `parity diff-image` for every hat, accessory, pattern, eye, coat, emote, thought, weather and pose; the art backlog |
| `tools/*.png` | visual references for the human review of each phase |
| `tools/walk-*.txt`, `legs-*.txt`, `jerk.txt`, `smooth.txt` | numeric acceptance targets for gait, legs and smoothness |
| `tools/sim-*.txt` | the behavior mix the brain must reproduce (and which checks are flaky) |
| `tools/cliptest.txt` | the draw-radius target |
| `tools/perch-*` | habitat art and behavior references |
| `tools/beat-*.txt`, `beat/*.txt` | beat tracker accuracy targets |
| `app/panel*`, `studio*`, `welcome*`, `bug*`, `habitat*`, `weather*` | the UI pixel and layout comparison |
| `app/entrance/*.txt` | the first-entrance timing and path |
| `app/frames-idle.txt`, `perf/*` | the frame and CPU targets |
| `video/*.mp4` | side-by-side review, and the source of truth for feel |
| `scroll-*.txt` + `rappel*` traces | the wheel-to-order mapping and sign |
| `data/*` | load-compatibility tests (a Mac-saved spider and habitat must open on Windows) |
| `pages/*` | the page reader tests |
| `MANIFEST.json` | provenance: every comparison cites the Swift tree hash it was made against |

---

## Part 13. Master checklist

Setup
- [ ] Mac with full Xcode; fresh clone; `chmod +x tools/*.sh build.sh`
- [ ] New tools and `tests/golden/` present in the clone (committed on Windows and pushed, or copied)
- [ ] Charger in, sleep off, Spider Buddy quit; display and scroll settings noted

Scripted (Part 2)
- [ ] `./tools/capture-all.sh capture` finished; `STATUS.tsv` has no unexplained FAILED
- [ ] `capture/MANIFEST.json` filled in (commit hash, Sources tree hash, macOS, display)
- [ ] `capture/rng/rng.json` exists and is large (5 seeds)
- [ ] `capture/images/index.json` lists thumbs (Studio options) and poses
- [ ] `capture/traces/` has the flat-walk five sizes, the lap, the hunts, the activities
- [ ] `flat-walk ... Onone` compared with the optimized one (identical?)
- [ ] `capture/free/` has 8 seeds
- [ ] `capture/tools/` has film, gallery, walk, legs, jerk, smooth, sim x3, bench, perch, beat, cliptest
- [ ] `Resources/` untouched (`git status Resources Sources` is clean)

App (Part 3)
- [ ] `./build.sh` built; `capture-app.sh` ran; panel (dark), 12 Studio tabs, welcome, bug, habitat, weather, tour pictures
- [ ] (optional) light panel via `PANEL_LIGHT=1`
- [ ] `entrance-positions.txt`, `frames-idle.txt`, `open-timing.txt`
- [ ] settings restored (your own spider is back to how it was)
- [ ] manual screenshots in `app/manual/`

Recordings (Part 4)
- [ ] clips 01 to 24, or at least 01, 02, 03, 04, 05, 06, 07, 08, 09, 14, 18, 19, 22
- [ ] `video/NOTES.txt` with times and settings

Numbers and files (Parts 5 to 9)
- [ ] scroll probe, natural on and off
- [ ] perf numbers (7 situations) with the Mac model
- [ ] data files: settings plist, 5+ spiders, 3 habitats, default design JSON
- [ ] beat outputs for 3 songs and speech; 5 page screenshots with outputs
- [ ] font and color greps; note on light/dark

Delivery (Part 11)
- [ ] `NOTES.txt` written; zips made; checksums made; sent; unzipped to `tests/golden/mac/` on Windows

**If you only have an hour:** Part 1, then `STEPS="manifest rng images traces" SEEDS="1 2" KIN_SEEDS="1" SCALES="0.95 0.62 1.55" ./tools/capture-all.sh capture`,
then `tools` step on its own (`STEPS="tools"`), then clips 01, 02, 05, 06 and 22. That is enough to start the comparison and settle the
big questions; the rest can follow.
