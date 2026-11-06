# Windows Spider Buddy: full plan to macOS parity

> **Revision adopted by the owner (2026-11-06).** The spike in `WINDOWS_WORKLOG.md` showed that the Mac's Swift compiles
> for Windows unchanged and matches the Mac. This replaces Track B of this plan, and this table overrides what follows:
>
> | Part of this plan | Now |
> |---|---|
> | Part 2, 3: oracle, compare tools | Kept. Mostly built. RNG fixtures are no longer needed: both sides run Swift's own generator. |
> | Part 4: host | Kept, but in Swift, reusing the Mac's `AppDelegate` and `OverlayWindow` logic |
> | Part 5: pose contract | Gone: it is the same code |
> | Part 6: art port, transliterator | Gone for the spider and creatures: 768 of 770 images already match |
> | Part 7: behavior port | Gone: 8 to 14 weeks of transliteration replaced by compiling |
> | Part 8: desktop features | Windows for them only; the behavior and art already exist |
> | Part 9: sensors | Kept: new Windows code behind the same names as `SystemSense` and `Ears` |
> | Part 10: UI | Changes: a small AppKit stand-in so `Panel.swift`, `Studio.swift` etc. run unchanged, with controls drawn to look like the Mac's |
> | Part 11: habitat | Art compiles; needs a compositor behind `CALayer` |
> | Part 12: verification, release | Kept; the installer also has to bundle the Swift runtime |
>
> The C# in `src/Core`, `src/Renderer`, `src/App`, `src/Tools` is retired once each part is replaced, not before.

> **Where this stands (added 2026-11-06).** Day-to-day process is in `WINDOWS_DEV_WORKFLOW.md`, feature state in
> `WINDOWS_PARITY_STATUS.md`, history in `WINDOWS_WORKLOG.md`. Files moved since this was written: `progress.md` is now
> `docs/windows/progress-first-port.md`, and the audit and Mac handoff are in `docs/windows/`. This plan was written
> on Windows with no Mac; the Mac is now available in the same session, so Part 2 is done directly.


**Goal:** the Windows app looks and feels almost exactly like the Mac app (1.0.1): same spider, same
movement, same desktop life, same panel, Studio and habitat.

**Sources read for this plan:** `WINDOWS_PORT_SPEC.md`, `WINDOWS_PORT_AUDIT.md`, `progress.md`,
`src/App/Program.cs` (frame loop, pointer, overlay), `src/App/DesktopCapture.cs`, `src/Core/Draw.cs`
(pose contract), `src/Renderer/SpriteRaster.cs`, `src/Tools/Program.cs`, and on the Mac side
`OverlayWindow.swift`, `WindowTracker.swift`, `AppDelegate.swift` (`tick`, `show`), `Spider.swift`
(`SpiderPose`), `build.sh` and the `tools/*.sh` scripts and their Swift sources.

**How to read this:** Part 1 is the diagnosis. Part 2 is the list of things to get from the Mac.
Parts 3 to 12 are the phases, each with file-level and API-level detail. Part 13 is the schedule, risks and
first-week actions. Items marked **VERIFY** are things I inferred and did not confirm in code or on a device.

---

# Part 1. Diagnosis

## 1.1 The root cause behind the audit's ten findings

The audit lists missing layers, a slow tracker, no hit-testing, an incomplete pose, and so on. They share
one cause: **the C# core is a reimplementation from the spec's prose, not a port of the Swift.**

| | macOS (Swift) | Windows (C#) | Windows share |
|---|---|---|---|
| Behavior: `Spider`, `Prey`, `Toys`, `Traces`, `Memory`, `Visitors`, `Surfaces`, `SystemSense`, `Weather` | about 27,800 lines | about 7,400 lines (`Spider*.cs`, `Activities.cs`, `Surface*.cs`) | about 27% |
| Drawing: `SpiderRenderer`, `Skin`, `Habitat{Art,Items,NatureArt,HomeArt,PieceArt,Atmosphere,Weather}` | about 12,200 lines | about 2,200 lines (`src/Renderer`) | about 18% |
| `Spider.swift` alone | 20,442 lines | `Spider.cs` is 517 lines, with the rest spread over about 20 files | n/a |

The spec said "port the Swift algorithms rather than rewrite" (Appendix D, risk 1: *feel drift*). That did
not happen. The C# tests were written from the same prose, so 1,050 green checks prove the C# matches the
spec's description, not that it matches the Mac.

## 1.2 Two tracks

- **Track A, host:** layers, tracker, hit-testing, sensors, shell. New Windows-only code. Mostly
  well specified.
- **Track B, fidelity:** behavior and art. The fix is *transliteration from the Swift plus differential
  tests against recorded Mac output*, not more writing from prose.

Track B needs an **oracle** (recorded Mac output) before it can be judged. That is Part 2 and Phase 0.

## 1.3 Findings I confirmed in the code (not only in the audit)

| Claim | Where |
|---|---|
| Map rebuilt only every 0.55 s | `Program.cs:1523` |
| `GetWindowRect`, no extended-frame bounds | `DesktopCapture.cs:85` |
| Overlay permanently click-through | `Program.cs:1892` (`WS_EX_TRANSPARENT` always set) |
| Name tag forced off in raster path | `SpriteRaster.cs:44, 67` (`drawNameTag: false`) |
| `HiddenBy` / `PeekGrip` never read by the renderer | no match in `src/Renderer` |
| Pointer is a global `GetAsyncKeyState` poll with a distance test, not `Spider.HitTest` | `Program.cs:1544-1561` |
| Sprite re-rendered **every frame**, no shape-change gating | `Program.cs:1649` (`SpriteRaster.Render` each call to `Draw`) |
| Per-frame copy chain: Skia bitmap, row-by-row `Marshal.Copy` into a `System.Drawing.Bitmap`, `DrawImageUnscaled`, `GetHbitmap`, `UpdateLayeredWindow`, `DeleteObject` | `Program.cs:1906-1972` |
| `SpiderPose` has no `web`, `webPoints`, `thread`, `threadFrom`, `threadVia`, `silkAttach` | `Draw.cs:131-184`; the Swift pose has all of them (`Spider.swift:111-190`) |

New findings beyond the audit:

1. **No redraw gating.** The Mac re-rasterises only when the shape changed (`SpiderView.shapeDelta`
   `< 0.04`) and otherwise holds the picture up to 0.5 s (1/30 s with an animated coat or falling drips).
   Windows rasterises and pushes a bitmap every frame. This is a CPU and battery cost, and the Mac gets the
   "standing is free" behavior from it.
2. **Scroll is not a global event on the Mac.** `OverlayWindow.swift:323` handles `scrollWheel` on the
   spider's own view, which only receives events while the pointer is over the spider (hit-test decides).
   The only global scroll monitor (`AppDelegate.swift:1813`) feeds the web-page climber. The earlier
   draft of this plan proposed a global `WH_MOUSE_LL` hook for spider scroll orders; that was wrong and
   is corrected in Phase 1.4.
3. **A layered window with per-pixel alpha already passes clicks through its fully transparent pixels.**
   That interacts with hit-testing and needs an explicit fix (Phase 1.4, "alpha-1 hit disc").
4. **The Mac's tools do not run the app; they link a subset of its Swift sources into small binaries**
   (`tools/sim.sh` compiles `Math`, `Surfaces`, `WindowTracker`, `Spider`, `Beat`, `Memory`,
   `SpiderRenderer` and so on with `tools/sim/main.swift`). That makes a trace exporter cheap (Part 2).
5. **Seeded runs on the Mac already exist** (`tools/legs/Seeded.swift`, `LC_SEED`, SplitMix64). Frame-exact
   cross-platform comparison therefore needs the C# core to use the *same generator and the same
   draw-to-number mappings* (Phase 0.3).

---

# Part 2. What to get from the Mac

Everything here is a one-time capture, committed under `tests/golden/mac/` with a `MANIFEST.json`
recording: Swift git commit hash, `VERSION`, macOS version, machine model, display size and scale, date,
and the exact command and env vars for each file. If you change the Swift later, re-capture and bump the
manifest. Plan for about half a day of Mac time for A to D, and a few hours of screen recording for E.

## 2.0 Mac prerequisites

- Xcode (full app, not just Command Line Tools; `build.sh` prefers `/Applications/Xcode.app`).
- This repo checked out at the commit you want as the oracle. Record it: `git rev-parse HEAD`.
- A **fixed display setup** for the screenshots: note the resolution and scale (for example 1512x982 at
  2x). The synthetic-desktop tools read `NSScreen.main`, so their output depends on the screen. For
  reproducibility, pin the screen size by editing the tools to use fixed rectangles (see 2.2). Otherwise
  every golden is only valid for that one Mac.
- `SWIFT_DETERMINISTIC_HASHING=1` exported for every run that matters. Swift seeds `Set` and `Dictionary`
  hashing per process, so iteration order changes between runs unless this is set. The spec flags this
  (Appendix A, "Per-process hash seed").

## 2.1 Already-existing tools: run these and keep the output

All build scripts live in `tools/`. Run each from the repo root. Keep the PNG/text output.

| # | Command | What it gives | Windows use |
|---|---|---|---|
| A1 | `./tools/preview.sh out/mac-contact.png` | Contact sheet of every size, body shape, coat, hat | Image diff for the spider renderer (Phase 3) |
| A2 | `./tools/preview.sh` then run `build/Preview --single` and `--cliptest` (see `tools/main.swift:61, 70`) | Single large pose and the **draw-radius clip test** numbers | Draw-radius gate |
| A3 | `./tools/gallery.sh out/mac-studio.png 96 12` (args: output, cell size, wrap; see `tools/gallery/main.swift:6-43`) | Every Studio option rendered, plus random designs | Studio thumbnails and per-option diff |
| A4 | `./tools/gallery.sh out/mac-studio-192.png 192 8` | Same at 2x for pixel-level compare | Same |
| A5 | `./tools/film.sh out/film-walk.png` | Default film: walk cycle on each screen edge (`film/main.swift:15-22`) | Gait look |
| A6 | `./tools/film.sh out/film-cycle.png --cycle` | One gait cycle, 9 columns at 260 px | Gait look, close-up |
| A7 | `./tools/film.sh out/film-desk.png --desk` | **Actual size on a mock desktop, every edge kind** ("the most useful single view") | Primary visual A/B |
| A8 | `... --hang`, `--swing`, `--hammock`, `--jump`, `--jump --under`, `--drop`, `--peekaboo`, `--thoughts` | One PNG each | Silk, hammock, air, peek-a-boo, thought art |
| A9 | `... --hunt cricket`, `--hunt worm`, `--hunt fly` (and the other five kinds if the tool accepts them; **VERIFY** the list in `film/main.swift:645`) | Hunt films | Prey art and hunt timing |
| A10 | `... --dance`, `--dance-session` | Dance moves | Music behavior |
| A11 | `... --seq a:2,b,c:1.6` and `--strip corner`, `--strip turn`, `--strip peek` | Hand-off, turn, corner, peek strips | Gait hand-off |
| A12 | `./tools/walk.sh strip`, `trace`, `stats`, `why` (see `tools/walk.sh` header) | Walking measurements: bone stretch, reach, planted-foot slip, pops, cadence | The **numeric targets** for the gait |
| A13 | `./tools/legs.sh all` and `./tools/legs.sh flat` | Leg quality text report over many worlds | Leg targets (stretch, slip, pops) |
| A14 | `./tools/jerk.sh` | Jerk detector report (flags per minute by activity pair) | Jerk targets |
| A15 | `./tools/smooth.sh` | Smoothness report | Targets |
| A16 | `./tools/sim.sh > out/mac-sim.txt` | 240-simulated-second headless run summary: state percentages, transitions per second, `[ok]/[FAIL]` list | Behavior mix target (percent of time per activity) |
| A17 | `./tools/bench.sh > out/mac-bench.txt` | Per-frame render and update timings | Perf target |
| A18 | `./tools/perch.sh sheet out/mac-perch-sheet.png` | Every habitat item kind, painted, with its shape | Habitat item art diff (Phase 9) |
| A19 | `./tools/perch.sh world <preset> out/mac-world-<preset>.png` for **each preset** (list them from `Habitat.swift`; **VERIFY** the preset names) | Each habitat world | Habitat world diff |
| A20 | `./tools/perch.sh pieces out/mac-pieces.png` | Every structure piece with ports | Structure art |
| A21 | `./tools/perch.sh build out/mac-build` | Built structures (writes `prefix_*.png`) | Structure art |
| A22 | `./tools/perch.sh nature`, `curious`, `places`, `ecology`, `nav`, `air`, each saved to text | Habitat behavior reports | Habitat targets |
| A23 | `./tools/pages.sh` | What a picture of a web page would be climbed as | Page reader parity |
| A24 | `./tools/beat.sh` and `./tools/ears.sh` | Beat tracker output on synth/loops/mixes and tap status | Beat tracker parity (also see 2.5) |
| A25 | `./tools/art.sh` | App icon and menu-bar icon renderings | Tray icon diff |

Notes:

- Tools that print `[ok]/[FAIL]` should be run **three times** to separate base-rate flakes from failures;
  save all three. The spec says some (for example the mosquito catch) are known slow-hunt flakes.
- Where a tool reads `NSScreen.main`, record the resolution in the manifest.

## 2.2 New Swift tools to write on the Mac (small, I will provide the code)

These do not exist and are what makes frame-level comparison possible. Each is a new directory under
`tools/` plus a `.sh` in the style of the existing ones (compile the same Swift subset as `sim.sh`).

**T1. `tools/trace` (the pose trace exporter).** The most important new tool.

- Builds against the same source subset as `sim.sh`, with the `Seeded.swift` shadowing from
  `tools/legs/Seeded.swift` so every random draw comes from SplitMix64 seeded by `LC_SEED`.
- Fixed, screen-independent desktop (no `NSScreen.main`): a 1920x1080 screen at origin (0,0) with the same
  three windows and 40-unit taskbar-equivalent as the Windows `Synth.cs`. If the Mac side has a menu bar
  in `map.rebuild`, set it to 0 and use `map.debugRebuild(screen:menuBarHeight:windows:)` as `film` does
  (`film/main.swift:9`).
- Per frame, at a fixed `dt = 1/60`, calls `spider.setCursor(...)`, `spider.update(dt:)`, then
  `spider.pose()`, and writes **one JSON object per line** (JSON Lines) with:
  - `t`, `frame`, `debugState` (`Spider.debugState`, `Spider.swift:19714`), `pos`, and every field of
    `SpiderPose` (`Spider.swift:111-190`): `heading, facing, spin, ball, grounded, silkAttach, scale,
    stretch, fatten, look, blink, happy, startled, sleep, abdomenSway, emote, emoteT, emoteClock, thought,
    web, webPoints, thread, threadFrom, threadVia, time, grabbed, nameTag, odometer, bodyPitch,
    bodyShift, chew, headTilt, headCock, wink, palpNear, palpFar, headTurn, abdomenTilt, hiddenBy,
    peekGrip, wet, snow, dust, chill, specks`, and all eight `legs` (`hip, knee, foot, lift`).
  - Print doubles with `%.9g` or the shortest round-trip form, not a rounded form.
  - Mode and anchor (`loopId, segIdx, t, dir`) if they are accessible; **VERIFY** the property names
    (`Spider.swift` is 20k lines; the exporter author must find them).
- Scenario selection by name on the command line; scenarios in 2.3.
- Also writes a `header` line: Swift commit, seed, scenario, scale, dt, desktop description, cursor script id.

**T2. `tools/rngprobe` (random-number fixtures).** Writes, for seeds 1, 2, 3, 42, 12345, the first 1,000
outputs of: `next()` raw `UInt64`; `Double.random(in: 0...1, using:)`; `Double.random(in: 0..<1, using:)`;
`CGFloat.random(in: a...b)`; `Int.random(in: 0...9, using:)`; `Int.random(in: 0..<7, using:)`;
`Bool.random(using:)`; the result of `[0,1,2,3,4,5,6,7].shuffled(using:)`; `randomElement(using:)` over a 10-element
array. This pins the exact stdlib mapping so the C# `Rng` can reproduce it (Phase 0.3). Without it,
"frame-exact" is impossible and everything falls back to statistics.

**T3. `tools/imagedump`.** Renders a list of named inputs to individual PNGs (not a contact sheet) so the
image diff can compare cell by cell: every hat, accessory, pattern, eye style, brow, fang, coat, body shape,
leg style at scale 0.95 (and 0.62 and 1.55 for a subset), plus every emote and every thought kind, plus the
weather coat states (wet, snow, dust, chill), plus the ball pose, plus hanging/dangling poses, plus peek-a-boo
with a hiddenBy rect. The existing `gallery` and `preview` produce sheets; individual PNGs avoid cropping
by layout. Resolution: render at 2x (the Windows renderer's sprite is 1x in logical units; compare after
downscaling the Mac image with a box filter, and also compare at 2x by rendering Windows at 2x).

**T4. `tools/layout`.** Dumps the **geometry of the UI**, not pixels: for the panel, Studio tabs, welcome,
chat pill and bug-report window, every control's frame, font name, size, weight, color and corner radius, in
JSON. This is easier and more precise than comparing screenshots by eye. It requires hooking the
`Panel.swift`/`Studio.swift` view builders; if that is too invasive, skip T4 and rely on screenshots (2.4).

## 2.3 Scenarios the trace exporter must support

Each scenario has an id, a setup, a cursor script, a duration, optional scripted commands, and a seed list.
Run each for **seeds 1, 2, 3, 42** at **scales 0.62, 0.78, 0.95, 1.2, 1.55** (the five sizes).

| id | Setup | Cursor script | Commands | Seconds | Compare |
|---|---|---|---|---|---|
| `flat-walk` | Spider on a window top, `Activity.walk` forced, no brain | none (parked far away) | walk right, then left | 12 | exact |
| `corner-round` | Walk around a window's top-right corner, then down the side | none | walk | 10 | exact |
| `underside` | Walk onto the underside (ceiling) of a window | none | walk | 10 | exact |
| `handoff` | Window edge to screen rim | none | `--seq` equivalent | 8 | exact |
| `turn` | Walk, reverse, front view | none | reverse x3 | 8 | exact |
| `stop-start` | Walk, stand, walk | none | scripted | 8 | exact |
| `carried` | A window dragged under the spider | none | window path script | 6 | exact |
| `grab-throw` | Grab at t=1 s, hold 1 s, throw at v=(900,600) | scripted pointer | `beginGrab`, `moveGrab`, `endGrab` | 8 | exact |
| `soft-toss` | Release at v=(120,60) so it rescues itself | scripted | | 8 | exact |
| `jump` | `--jump` equivalent, and `--under` | none | leap to a spot | 6 | exact |
| `rappel` | Scroll-down order | none | `scroll(-8,...)` | 10 | exact |
| `climb` | Hang then scroll-up order | none | | 10 | exact |
| `swing` | `--swing` | none | | 10 | exact |
| `hammock` | `--hammock`: build, nap, wake | none | | 60 | free-run 10 s exact, rest statistical |
| `peek` | `--peekaboo` | none | `startPeekaboo` | 10 | exact |
| `hunt-cricket`, `hunt-worm`, `hunt-fly` | release prey | none | | 20 | exact for 6 s, then statistical |
| `toy-ball`, `toy-feather`, `toy-bell`, `toy-bug`, `laser` | toy in play | scripted | | 20 | statistical |
| `pointer-watch` | Standing; pointer sweeps across, hovers overhead | circular sweep | | 20 | exact (5.5 targets: head error about 0.05 rad, 0 flips on hover) |
| `pointer-whip`, `pointer-stroke`, `pointer-fidget` | Pointer events (5.5) | scripted | | 15 | exact for first 3 s |
| `dance` | Fake 120 BPM beat | none | `music = fake` | 20 | exact |
| `cinema` | `Cinema` state set | none | | 15 | exact |
| `box` | Confine box | none | | 20 | statistical |
| `free-4min` | The full `sim.sh` free-run, liveliness 3.0 | cursor script from `sim/main.swift:41-46` | none | 240 | statistical: state percentages and transitions per second |

The cursor script for `free-4min` is the existing one: `cx = midX + cos(0.23 t)·500`, `cy = midY + sin(0.17 t)·320`.

**Exact** means frame-by-frame within the tolerances in 3.4. **Statistical** means compare rates over seeds
(see 3.5).

## 2.4 Screenshots of the real app (needs the actual app running, not the tools)

The app has built-in screenshot hooks; set the env var, launch, it writes the PNG and quits. Use
`SPIDER_*` hooks listed here (names from `AppDelegate.swift`; the exact output path semantics are in the
source near each, **VERIFY** before running):

| Env var | Output | Windows use |
|---|---|---|
| `SPIDER_PANEL_SHOT` | The panel, all seven pages | Panel pixel/layout compare |
| `SPIDER_STUDIO_SHOT` (also `_VOICE`, `_CUSTOM`) | Studio tabs (12 tabs; run once per tab or check if the hook loops) | Studio compare |
| `SPIDER_WELCOME_SHOT`, `SPIDER_WELCOME_FLOW` | Welcome tour pages | Welcome compare |
| `SPIDER_BUG_SHOT` | Bug report window | |
| `SPIDER_HABITAT_SHOT`, `SPIDER_HABITAT_SHOT_ONLY` | Habitat window screenshots | Habitat compare |
| `SPIDER_WEATHER_SHOT` with `SPIDER_WEATHER_KINDS` and `SPIDER_WEATHER_BIOMES` | Weather in each biome/kind | Habitat weather diff (Phase 9) |
| `SPIDER_PAGE_SHOT` | Page-climbing debug picture | |

Take these **at both appearances** (light and dark) if the app follows system appearance. **VERIFY** whether
it does; if the UI is custom-colored and ignores appearance, one set is enough.

Also take plain macOS screenshots of: the menu-bar icon in normal and hidden (dimmed) states at 1x and 2x;
the menu (right-click menu on the spider, and the menu-bar menu) opened; the panel popover anchored under the
icon; the first-entrance sequence frame by frame (use screen recording, below).

## 2.5 Screen recordings (feel, not pixels)

Record at 60 fps (QuickTime does 60 on supported Macs; or `screencapture -V` / OBS). Each clip 15 to 60 s,
real app, real windows, normal display. These are the "owner judges what is drawn" references and also how a
human compares speed, timing and personality. Keep the file names stable.

1. Idle for 3 minutes on a busy desktop (the spider's normal life).
2. Walking along a window top, around a corner, under a window, across to another window.
3. Dragging a window while the spider stands on it, then resizing it, then minimizing it, then closing it.
4. Another window covering the spider (peek-a-boo and being covered).
5. Grab, carry, flick-throw to the screen edge, soft toss and rescue.
6. Click, double-click, right-click, hover (name tag), stroke the pointer, whip the pointer, fidget (pounce/cling).
7. Scroll over the spider (rappel), scroll up (climb), swing.
8. Hammock: build, nap, wake, wipe the pointer across it.
9. Feed each of the 8 prey kinds from the Feed menu and watch the hunt; wildlife wandering in.
10. Toys: ball, feather, bell, wind-up bug, laser.
11. Traces on (strands, little webs, meal leftovers) for 2 minutes; Tidy Up.
12. Visitors on: arrival, hello, tag, leave; Dismiss.
13. Draw a box (the dimmed screen and drag), spider inside the box.
14. Full-screen video (cinema manners), charger plug/unplug, Low Power on/off, a notification banner, volume change.
15. Music playing (a steady 120 BPM track and a speech podcast): dance start, cooldown.
16. Rain on the screen (`SPIDER_RAIN=1`) and the 3.5 s rain thought.
17. Lock and unlock the screen (spider sleeps, greets).
18. First entrance (delete settings first or set `SPIDER_ENTRANCE_TEST`), plus the whole welcome tour.
19. Habitat: open, every one of the world presets, close; weather kinds; decorate mode; tour; My Habitats.
20. Talking: chat open, a few replies, thought bubble click. (If Apple Intelligence is available.)
21. Menu bar interactions: every menu item toggled once, with a visible effect where there is one.

For each clip, note the Mac's display scale, the spider scale setting, and the build.

## 2.6 Timing and performance numbers from the real app

Run the real app with each of these set and capture the printed output for 60 s while the spider is
(a) idle, (b) walking, (c) hunting with prey on, (d) the habitat with a storm:

- `SPIDER_FRAMES=1` (per-second frame meter) and `SPIDER_TIMING=1` (per-phase ms), `SPIDER_STATS=1`
  (`AppDelegate.swift:148`), `SPIDER_OPEN_TIMING=1` (panel/Studio/habitat open times).
- Activity Monitor CPU% for the app in the same four situations (screenshot or `top -pid`), and resident
  memory. The spec targets are about 15% active and 4% resting; get the real numbers.

## 2.7 Data files for compatibility testing

So Windows can load what the Mac saves (the spec says `.spiderhabitat` is the same JSON):

- A real settings export. On the Mac: `defaults export com.gabriel.desktopspider -` (the bundle id is in
  `build.sh`; `spiders.app` uses the same id) saved to `settings.plist`. Convert to JSON. **Note:** the
  `defaults` CLI can read the wrong store for ad-hoc builds (spec Appendix A); also copy the actual plist from
  `~/Library/Preferences/`.
- 5 to 10 saved spiders from `Spiders/*.json` (different hats, coats, personalities, names).
- 3 saved habitats (`Habitats/*.json` or `.spiderhabitat`), including one with decorations, one with a
  built structure, one empty.
- A real `memory` blob and a `habitatKnowledge` blob from a spider that has played for a while.
- The exact JSON of one default `SpiderDesign` (from `SpiderDesign.swift`, a serialization dump).

## 2.8 Audio for the beat tracker

Copy the audio inputs that `tools/beat/main.swift` uses, and its outputs (BPM, phase, confidence) per file:
synthetic clicks at 90/118/128/150 BPM, a few music loops, a 3-minute mix, speech. Without the audio the
Windows beat tracker can only be tested against itself. **VERIFY** which files the tool reads (look at the
arguments in `tools/beat/main.swift`; it is 535 lines).

## 2.9 Fonts and metrics

Not a capture; a decision. The Mac UI uses SF Pro (and Menlo in tools). Windows cannot ship SF Pro (license).
Decide on Segoe UI Variable (Windows 11) with Segoe UI fallback, and from the layout dump (T4) or the Swift
source record each text style's point size and weight so the Windows sizes can be matched visually.

## 2.10 Checklist you can print

- [ ] Oracle commit hash recorded; `SWIFT_DETERMINISTIC_HASHING=1` exported.
- [ ] A1 to A25 outputs saved under `tests/golden/mac/tools/`.
- [ ] T1 trace exporter written; all scenarios x seeds x scales exported (about 20 scenarios x 4 seeds x 5 scales; start with seed 1, scale 0.95 and add the rest once the diff works).
- [ ] T2 RNG fixtures exported.
- [ ] T3 individual PNGs exported.
- [ ] T4 layout dump exported (or skipped, with screenshots instead).
- [ ] Section 2.4 screenshots (light and dark if applicable).
- [ ] Section 2.5 recordings (21 clips).
- [ ] Section 2.6 perf numbers.
- [ ] Section 2.7 data files.
- [ ] Section 2.8 audio.
- [ ] `MANIFEST.json` filled.

---

# Part 3. Phase 0: the oracle and honest gates (1 to 2 weeks)

Do this before anything else. Everything after it is judged here.

## 3.1 Repo layout for fixtures

```
tests/golden/mac/
  MANIFEST.json
  tools/           A1..A25 outputs
  traces/<scenario>/<seed>-<scale>.jsonl
  rng/seed-<n>.json
  images/<name>.png        T3 output
  screenshots/<ui-name>-<light|dark>.png
  video/                   (kept out of git, listed in the manifest; git-lfs or a release asset)
  data/                    section 2.7
  audio/                   section 2.8
tests/golden/win/          Windows-rendered outputs, regenerated by the tools; diffs written here
```

Keep video out of the repo (size). Use Git LFS for PNGs over about 1 MB if the set grows.

## 3.2 Windows tools to add (`src/Tools`)

Add subcommands in `src/Tools/Program.cs` next to `stage1...stage20`:

- `parity trace <scenario> [--seed n] [--scale s] [--out file]`: run the C# core on the same synthetic
  desktop and write the same JSONL as T1.
- `parity diff-trace <macFile> <winFile>`: per-frame comparison with the report in 3.4.
- `parity diff-image <macPng> <winPng>`: per-image metrics in 3.6, plus a side-by-side and a diff PNG in
  `tests/golden/win/diff/`.
- `parity all`: runs everything in the manifest and prints a table (pass/fail/waived), exits non-zero on
  failures. Wire it into `release-gate.ps1`.

Keep the core free of OS calls as it is now (spec rule 1.1). The scenarios belong in `src/Tools`, not in the core.

## 3.3 Making random numbers comparable

The Mac sim uses the global generator unless `Seeded.swift` shadows it. Plan:

1. Add `SplitMix64` to `src/Core/Springs.cs` next to `Rng` (the existing one is xoshiro128++), selectable
   by a constructor flag. Production keeps whichever is current; the parity tools use SplitMix64.
2. Implement each Swift stdlib mapping *as the fixtures show*. Do not assume. Likely candidates (to be
   checked against the T2 output, **VERIFY**): `Double.random(in:)` builds a double from random bits and scales
   into the range; `Int.random(in:)` uses an unbiased multiply-and-reject method (Lemire); `Bool.random`
   uses a bit of `next()`; `shuffled()` is Fisher-Yates from the end using `Int.random(in: 0...i)`.
3. Unit-test against the 1,000-value fixtures for each seed. Zero tolerance for integers; 1 ulp for doubles.
4. **The order and number of random calls must match the Swift exactly.** This is the hidden requirement
   of frame-exact comparison and it is why Phase 4 must transliterate rather than restructure. Any extra or
   missing draw shifts every later decision. When a trace diverges at a decision frame, the first suspect is
   the draw order.
5. `SWIFT_DETERMINISTIC_HASHING=1` on the Mac side handles hash order; on the C# side use ordered
   collections wherever the Swift iterates a `Dictionary` or `Set` (and find those in the Swift: the
   spider's `[String: Int]` counters in `sim` are only for printing, but any iteration that drives behavior
   matters). Add a Swift grep for `for .* in .*\[.*:.*\]`/`.keys`/`.values` over dictionaries to build the list.

## 3.4 Trace comparison method and tolerances

Floating point will not match bit for bit across Apple libm and the Windows CRT for `sin`, `cos`, `atan2`,
`exp`, `pow`. `+ - * / sqrt` match exactly under IEEE double, so most of the kinematics will agree to the last
bits for a while, and then trig differences of about 1 ulp can grow through springs and the gait. Therefore:

- **Exact scenarios:** compare frame by frame for the first N frames (N = scenario length, 5 to 12 s). Targets:
  - position, hip, knee, foot: absolute error `<= 0.02` units (spec target for planted feet was `0.05`)
  - heading, pitch, tilt, spin, and other angles: `<= 0.002` rad
  - scalars 0 to 1 (blink, happy, startled, sleep): `<= 0.005`
  - discrete fields (`mode`, `activity`, `emote`, `facing` sign, leg count): **equal**
  The tool reports the first frame that fails, the field, and both values, then continues and counts total
  failing frames. Early failures matter more than late ones.
- **Early-divergence spike (do this first, in the first week):** run `flat-walk` and measure how fast the
  trace error grows. If trig-only drift stays below the tolerances for 12 s, exact comparison is viable. If
  not, choose between (a) replacing `Math.Sin/Cos/Atan2/Exp/Pow` in the core with a **fixed software
  implementation** and doing the same on the Swift side through a shim in the tool build (heavy but
  deterministic), or (b) accepting tolerance windows of 0.1 to 0.3 units and shorter scenarios. Decide on data.
- **Resynchronisation:** where exact comparison fails but behavior is correct, add a mode that, at chosen
  frames, overwrites the C# *kinematic* state with the Mac's recorded pose (position, heading, feet) and
  continues. This isolates "does this section do the right thing next" from "did drift accumulate". It only
  works for kinematic scenarios and needs state-injection hooks on `Spider` behind a test-only interface.
- **Statistical scenarios:** see 3.5.

## 3.5 Statistical comparison for the brain

For anything driven by weighted random choices (the free-run, hunts, toys):

- Run **8 seeds** (the spec says 4 to 8) per scenario on both sides.
- Compare: percent of time in each `debugState` prefix (as `sim.sh` prints), transitions per second,
  distribution of activity durations (median, 10th, 90th percentile), counts of notable events per simulated
  minute (leaps, rappels, swings, hammock builds, hunts, dances, peeks, sleeps).
- Pass if every metric is within `max(2 absolute percentage points, 25% relative)` of the Mac's, and the same
  set of activities occurs at least once in a 240 s run at liveliness 3.0 (this catches the missing
  repertoire: the C# brain does not currently pick leap, rappel, swing, hammock, nap, mend, explore, bounce).
- Show a table in the report with both columns so a human can see which activity is missing.

## 3.6 Image comparison method

Skia and Core Graphics both anti-alias, but the results differ slightly in edge coverage, gamma, stroke joins
and gradient dithering. Do not require pixel equality.

For each named image (T3):

1. Load Mac PNG (2x) and Windows PNG rendered at 2x with the same size, same background (render on
   transparent, composite both over mid gray `#808080` before compare).
2. Compute: mean absolute error per channel, 99th percentile error, SSIM (window 7), and a count of pixels
   whose error exceeds 64/255.
3. **Pass:** SSIM `>= 0.985`, mean error `<= 3/255`, and pixels over 64 `<= 0.4%` of non-transparent pixels.
   Tune on a handful of images known to look identical to the eye, then freeze the thresholds.
4. Always write a three-panel (Mac, Windows, amplified difference) PNG for human review of fails, with the
   differing region boxed.
5. Exclude text: CoreText and DirectWrite differ. Compare text by layout (bounding boxes) only.

## 3.7 Gates that currently lie

Fix these in Phase 0; they need no Mac.

- `tools/windows/release-gate.ps1`: add hard failures for mean fps `< 58` over the last 80% of the run, CPU
  above target, working-set growth above 5 MB per 10 minutes, and any `FRAME_STALL > 100 ms`. Right now it
  prints `RELEASE GATE PASSED` for a 39 fps run.
- Restore the Stage 4 planted-foot slide tolerance from 0.25 to 0.05 (`src/Tools/Stage4.cs`), then fix what
  fails (it was relaxed in the imported session, `progress.md:424`).
- Rewrite the `progress.md` table with two columns: **core checks pass** and **matches Mac (parity run)**.
  Move every "host pending" caveat into the status cell itself so a reader cannot see ✅ next to "NOT complete".
- Add a `tests/PARITY_STATUS.md` that `parity all` regenerates, listing each scenario and image with last
  result, so progress is visible without running anything.

## 3.8 Phase 0 exit

`parity all` runs end to end. It fails, and the failures match the audit (missing hiding, missing hats,
missing behaviors). That failure list is the working backlog for the later phases.

---

# Part 4. Phase 1: desktop host (4 to 6 weeks)

Closes F1, F2, F3. All in `src/App`.

## 4.1 Replace the per-frame bitmap pipeline with a proper layer window

**Current** (`Program.cs:1906-1972`): per frame, Skia bitmap, copy to a GDI+ `Bitmap`, `DrawImageUnscaled`,
`GetHbitmap`, `UpdateLayeredWindow`, delete. About four copies and an HBITMAP allocation per frame.

**Target `LayerWindow` base class** (new file `src/App/Layers/LayerWindow.cs`):

```csharp
abstract class LayerWindow : IDisposable
{
    protected IntPtr Hwnd;              // created via CreateWindowEx (no WinForms Form needed)
    IntPtr _dc, _dib, _oldBmp;          // persistent memory DC and DIB section
    IntPtr _bits;                       // pointer to the DIB pixels (BGRA premultiplied, top-down)
    int _w, _h;                         // current backing size
    public SKBitmap Pixels;             // SKBitmap.InstallPixels over _bits: Skia draws straight in
    public void EnsureSize(int w, int h);              // reallocate only when larger or much smaller
    public void Present(Rectangle screenRect);         // UpdateLayeredWindow with ULW_ALPHA
    public void Move(int x, int y);                    // cheap move: UpdateLayeredWindow(hwnd, null, ref pt, null, null, null, 0, null, 0) or SetWindowPos NOSIZE|NOZORDER|NOACTIVATE
    public void SetClickThrough(bool on);              // toggles WS_EX_TRANSPARENT with SetWindowLongPtr; no-op if unchanged
    public void SetVisible(bool v);                    // ShowWindow SW_SHOWNA / SW_HIDE, never SW_SHOW (no activation)
}
```

Details:

- Create with `CreateWindowEx(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
  [| WS_EX_TRANSPARENT], "SpiderLayer", null, WS_POPUP, ...)` on the UI thread with its own tiny `WndProc`
  (register one window class). Skip WinForms `Form` for layers: a `Form` brings paint, focus and DPI messages
  nobody wants. Handle `WM_NCHITTEST`, `WM_MOUSEACTIVATE` (return `MA_NOACTIVATE`), `WM_LBUTTONDOWN` and so on,
  `WM_DPICHANGED` (ignore, we size ourselves), `WM_DISPLAYCHANGE`.
- `CreateDIBSection` with a `BITMAPINFOHEADER` of `biWidth = w`, `biHeight = -h` (top-down), 32 bpp,
  `BI_RGB`. Select into a persistent memory DC. `SKBitmap.InstallPixels(new SKImageInfo(w, h, Bgra8888,
  Premul, sRGB), _bits, w * 4)` gives Skia direct access, so **there is no copy**. Premultiplied BGRA is exactly
  what `ULW_ALPHA` with `AC_SRC_ALPHA` expects. Keep the `SkiaDraw` y-flip as it is in `SpriteRaster.Render`.
- `UpdateLayeredWindow(hwnd, screenDC, &dstPoint, &size, memDC, &srcPoint, 0, &blend, ULW_ALPHA)` with
  `BlendOp = AC_SRC_OVER (0)`, `SourceConstantAlpha = 255`, `AlphaFormat = AC_SRC_ALPHA (1)`. Pass a
  `RECT` for the dirty area through `UPDATELAYEREDWINDOWINFO`/`UpdateLayeredWindowIndirect` with `prcDirty` so
  DWM only recomposes what changed. Cache `GetDC(null)` for the lifetime (do not Get/Release per frame).
- **Move without redraw:** when the shape is unchanged and only position changed, do not re-render; call
  the cheap move. This mirrors the Mac ("position changes are free").
- **Sizes and clearing:** the sprite window is `spriteSide + 68` square where
  `spriteSide = max(100, round(144·scale))` (`SpriteRaster.SpriteSide`, spec 3.1). Recenter the window on the
  spider only when it drifts `68/2 - 4 = 30` units from center (spec), not every frame. The current
  `SpritePad = 6` code does not do this. Clear the DIB with `memset` to zero (transparent) before each
  render instead of drawing a transparent fill through Skia.
- **Z-order:** every layer `HWND_TOPMOST`. Order within the topmost band: use `SetWindowPos(hwnd,
  hwndInsertAfter, ... SWP_NOACTIVATE)` once at creation and again only if a menu or another topmost app
  steals position. Contract: traces below spider, hammock above spider, bubble layer above everything we own.
  Re-assert order on `EVENT_SYSTEM_FOREGROUND`, not every frame, because `SetWindowPos` churn causes flicker.
- **Over the Start menu and taskbar:** the spec requires menus/Start to stay above or never lose clicks
  (3.1). Layered topmost windows can sit above the taskbar and Start. **VERIFY** on Windows 11 builds you
  support; the fix if the overlay covers Start is to drop below by using the `WS_EX_TOPMOST` band but not
  `HWND_TOPMOST` insertion above `Shell_TrayWnd` (put the layer just under the taskbar). Test with Start,
  Search, Quick Settings, Task View, and Alt-Tab.
- **All virtual desktops:** `IVirtualDesktopManager::MoveWindowToDesktop` only moves to a given desktop; to
  appear on all desktops use the (undocumented) `IVirtualDesktopPinnedApps` or pin through the shell.
  The spec says `WS_EX_TOOLWINDOW` overlays show on all desktops only if pinned (2.8). **VERIFY** empirically;
  fallback: listen for `EVENT_SYSTEM_DESKTOPSWITCH` and call `MoveWindowToDesktop` for each layer.
- **Full-screen apps (not exclusive):** a borderless full-screen window makes `SHQueryUserNotificationState`
  return `QUNS_BUSY` or `QUNS_RUNNING_D3D_FULL_SCREEN`; topmost windows still show over borderless windows
  (good for cinema, where the spider lies in the corner), but not over exclusive-mode D3D (cannot be helped).

## 4.2 The layers (each a `LayerWindow` subclass)

Build in this order (each is testable alone via an env-var test hook in the spirit of the Mac's):

1. `SpriteLayer`: the spider. Window size and recenter rule above. Replaces `SpiderOverlay`.
2. `BubbleLayer`: **new** (fixes the clipped text bubble and the missing name tag). Screen-space, sized to the
   union of {thought bubble rect, name tag rect}, drawn separately from the sprite, hidden when empty.
   `thoughtBubbleRect(pose)` already exists in the Swift (spec 3.7); its width runs to `190·scale` from
   `pos.x + 16`, which is wider than the 144-unit sprite (the audit's F4 clipping finding).
3. `SilkLayer`: one per display (or one bounding box over active silk). Shown only while a thread is out
   (spec 3.1). Dragline, swing line, held threads, rope (`SilkRope` has 15 points per rope).
4. `HammockLayer`: small window around the sling, **above** the sprite. Port `HammockView` (`OverlayWindow.swift:
   452-646`, about 200 lines of strand drawing: `tornAt`, `noise`, `strandPoint`, `strandPath`).
5. `PreyLayer` (creatures, toys, laser dot, hand toy): screen-sized but bounded to the union of drawn items.
   Takes the mouse only when the pointer is over a creature or toy and not over the spider
   (`wantsPreyMouse`, `AppDelegate.swift:1017-1024`).
6. `TraceLayer`: under the spider; strands, little webs, leftovers.
7. `HandCatcherLayer`: pointer-sized window that rides under the pointer while a toy is in hand, swallows the
   click that deploys it, and hides over the spider (`HandCatchView`, `OverlayWindow.swift:863`).
8. `BoxDrawLayer`: per screen, above everything, takes the mouse, dims the desktop, drag-to-draw
   (`BoxDrawView`, `OverlayWindow.swift:647-742`; its window level is `popUpMenu + 1`, `ignoresMouseEvents =
   false`). `BoxOutlineView` (743) is the dashed outline that stays afterward.
9. `RainLayer`: faint streaks (`RainView`, 764-837). Use a prebuilt streak bitmap and N moving copies, not
   per-frame path strokes.
10. `VisitorLayer` x up to 5: one `SpriteLayer`-style window each, with its own hit-test flip.

**Dirty-rect rule for screen-sized layers:** never allocate a DIB the size of the virtual desktop. Allocate
for the bounding box of what is drawn this frame (plus margin), reallocating on growth with hysteresis
(grow immediately, shrink only after 2 s of being much smaller). Hide (do not just clear) when nothing is drawn.
The Mac measured 26% CPU for a full-screen transparent window; Windows will be worse.

**Multi-monitor and mixed DPI for layers:** each layer window is positioned in **physical pixels**
(the process is PerMonitorV2, `app.manifest`; confirm `ApplicationHighDpiMode` in the csproj and the
manifest agree). A window that spans monitors with different DPI is drawn by DWM scaled, which blurs it;
therefore clip a layer's rectangle to one monitor and, where an item spans a border (a thread crossing two
monitors, a toy mid-flight), split into one window per monitor. The sprite window is small and may straddle a
border for a few frames; accept the blur or split by clip-to-monitor with two sprite windows during the
crossing (preferred; do this only if the straddle is visibly bad).

## 4.3 Redraw gating (port `shapeDelta`)

Port `SpiderView.shapeDelta` (`OverlayWindow.swift:211-248`) to C# **line for line**, and the rule from
`SpriteShower.put` (`OverlayWindow.swift:58-93`):

```
hold = (pose.outfit.isAnimated || !pose.specks.isEmpty) ? 1/30 : 0.5   // seconds
skip redraw if: drawn != null && now - drawnAt < hold
                && drawn.outfit == pose.outfit && shapeDelta(drawn, pose) < 0.04
else: render
```

`shapeDelta` includes `hiddenBy` equality, `specks.count`, heading weighted 45, wet/snow/dust/chill 60,
stretch/fatten 40, look 7, blink/happy 9, startled 7, abdomenSway 14, head tilt/cock 45, wink 9, palps 6,
headTurn 40, abdomenTilt 45, bodyPitch 45, bodyShift length, spin 30, chew/grabbed/sleep 9, nameTag 12,
`silkAttach` length, `facing`/`grounded` +1 on change, emote timing 40/20, and per-leg `foot` + 0.6 x `knee`
distances; the total is multiplied by `scale`. Copy it from the Swift; do not retune. The C# `SpiderPose`
needs the fields it reads (`silkAttach`, `outfit`, etc.).

Rasterise **off the UI thread** (serial queue, newest pose wins, spec 3.3). The UI thread applies "where the
window is, what it shows, and its silk" together when the picture is ready. A pose never goes up without its own
picture. Implement as: `Channel<PoseSnapshot>` with capacity 1 drop-oldest; worker renders into one of two
DIBs (double buffer); UI thread swaps with `Present`.

## 4.4 Pointer and hit-testing

**Replace** the global poll in `Program.UpdateMouse` (`Program.cs:1540-1616`) with window-driven input.

Per tick (same place the Mac does it, `AppDelegate.swift:1007-1033` at the top of the tick and again at the
end):

```
cursor = GetCursorPos -> world
wantsMouse = interactive && ( spider.IsHeld || (!inHabitat && (spider.HitTest(cursor) || BubbleUnder(cursor))) )
sprite.SetClickThrough(!wantsMouse)
for v in visitors: v.window.SetClickThrough(!(interactive && (v.spider.IsHeld || v.spider.HitTest(cursor))))
preyWindow.SetClickThrough(!( interactive && preyShown && (preyHeld || (!wantsMouse && (PreyHit(cursor) != null || ToyHit(cursor) != null))) ))
```

- Evaluate **twice per tick** like the Mac (top and end), because a stale answer is "a spider you cannot
  pick up" (spec 3.1).
- `Spider.HitTest` (`src/Core/Spider.cs:510`) already implements `grabRadius = 30·scale`, Click-to-Pick-Up off
  means always false, and `Mode.Clinging` means false. Use it. Delete the duplicate `over` test at
  `Program.cs:1544`.
- **Alpha-1 hit disc.** A `WS_EX_LAYERED` window using `ULW_ALPHA` is hit-transparent where alpha is 0, even
  without `WS_EX_TRANSPARENT`. The grab radius is a disc around the body and a spider's pixels are thin, so a
  click inside the disc but on empty pixels would fall through to the app below. Fix: whenever
  `wantsMouse` is true, paint a disc of radius `grabRadius` with premultiplied pixel `0x01000000`
  (alpha 1, color 0; invisible) *under* the sprite in the DIB before drawing. Also cover the bubble rect.
  **VERIFY** that alpha 1 is enough on your Windows build; if not, handle `WM_NCHITTEST` and return `HTCLIENT`
  for the disc and `HTTRANSPARENT` outside it (needs `WS_EX_TRANSPARENT` off).
- Messages the sprite window handles: `WM_LBUTTONDOWN` (then `SetCapture`), `WM_MOUSEMOVE`, `WM_LBUTTONUP`
  (`ReleaseCapture`), `WM_LBUTTONDBLCLK` (needs `CS_DBLCLKS` on the class), `WM_RBUTTONDOWN`,
  `WM_MOUSEWHEEL`, `WM_CAPTURECHANGED` (maps to the "capture loss safely releases" rule in
  `SpiderPointerInput`).
- Route everything through `SpiderPointerInput` (`src/Core/SpiderPointerInput.cs`), which already has the
  click rule (<4 units and <0.35 s), flick estimation (8 samples, 0.22 s and 0.04 s windows, 0.008 s denominator
  floor) and cancel rules. The host's own copy at `Program.cs:1563-1588` (0.12 s window, 30 units/s) is a
  weaker second implementation and goes away. Check `SpiderPointerInput` against the Swift
  `mouseDown/mouseDragged/mouseUp` (`OverlayWindow.swift:271-325`) line by line while wiring it.
- **Scroll:** `WM_MOUSEWHEEL` on the sprite window only (Mac parity: `scrollWheel` on the spider view).
  Convert `WHEEL_DELTA` (120 = one notch) to the core's `scroll(dy, precise, startsGesture)`: wheel mice are
  `precise = false` (threshold 0.5 "lines", one notch = 1 line, so a notch is an order), precision touchpads
  send many small deltas (`precise = true`, threshold 4 "points"; scale each delta by `120/WHEEL_DELTA` in
  points; **VERIFY** the scale against a Mac trackpad swipe, which usually sends about 20 to 60 points per
  swipe). `startsGesture` on Windows: there is no gesture phase for wheels; treat a gap `>0.35 s` as a new
  gesture (the core already has that rule). Direction: Mac "scroll down" is `scrollingDeltaY < 0` with
  natural scrolling; Windows wheel-forward (up) is positive `delta`. **Check the sign against what the Mac's
  `obey(up:)` expects, and test with both natural scrolling settings.**
- The global scroll hook (`PageInputHook`) stays for the page climber only.
- Right-click on the spider opens only the spider menu: the click is consumed because the window is not
  transparent at that moment. Remove the `_menu.Show` branch from the poll path.
- Cinema guard: every pointer path checks `Spider.Cinema` (spec: ignores the pointer in cinema), not just
  `BeginGrab`.
- Esc during hand-toy: `RegisterHotKey(hwnd, id, 0, VK_ESCAPE)` registered only while a toy is on the pointer,
  unregistered on put-away.
- Hover name tag: 0.7 s rest (`Pointer.cs`), now visible because the BubbleLayer draws the name.

## 4.5 Event-driven window tracker

Replace `DesktopCapture.cs` (118 lines, polled) with `WindowTracker` (new file `src/App/WindowTracker.cs`):

- **Hook thread:** a dedicated thread with a message loop (`GetMessage`/`DispatchMessage`) calling
  `SetWinEventHook(min, max, IntPtr.Zero, proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS?)`.
  Do **not** skip our own process: the Studio and the habitat are furniture (spec 2.1). Register separate
  hooks for: `EVENT_OBJECT_LOCATIONCHANGE (0x800B)`, `EVENT_OBJECT_CREATE (0x8000)`, `DESTROY (0x8001)`,
  `SHOW (0x8002)`, `HIDE (0x8003)`, `CLOAKED (0x8017)`, `UNCLOAKED (0x8018)`, `EVENT_SYSTEM_FOREGROUND
  (0x0003)`, `MINIMIZESTART (0x0016)`, `MINIMIZEEND (0x0017)`, `MOVESIZESTART (0x000A)`, `MOVESIZEEND (0x000B)`.
  Filter in the callback: `idObject == OBJID_WINDOW (0)` and `idChild == CHILDID_SELF`; ignore child windows.
  `LOCATIONCHANGE` also fires for the caret and cursor (`OBJID_CARET`, `OBJID_CURSOR`): the filter drops them.
- The callback only sets a `dirty` flag and records the HWND; it does no heavy work.
- **Snapshot timer** on the same thread: 30 Hz while any window is moving (`MOVESIZESTART` to `MOVESIZEEND`,
  or a `LOCATIONCHANGE` seen in the last 150 ms), otherwise 10 Hz sanity poll (spec 2.1). On each snapshot,
  if `dirty` or sanity tick: `EnumWindows`, build the list, compare to the last list, and if changed, post to
  the UI thread (`SynchronizationContext.Post`). The UI thread's tick takes the **latest** list and calls
  `SurfaceMap.Rebuild`. Do not rebuild inside the hook.
- **Per-window data** (all via DWM, no title):
  - visible: `IsWindowVisible && !IsIconic`
  - cloaked: `DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED = 14, &int)` must be 0
  - rect: `DWMWA_EXTENDED_FRAME_BOUNDS = 9` (a `RECT` in physical pixels); fallback `GetWindowRect` only if
    the call fails
  - style: `GetWindowLongPtr(GWL_STYLE)` and `GWL_EXSTYLE`; skip `WS_EX_TOOLWINDOW` (except ours) and
    `WS_EX_NOACTIVATE` shell surfaces; skip `WS_CHILD`; skip `WS_EX_TRANSPARENT | WS_EX_LAYERED` windows
    that are ours
  - alpha: if `WS_EX_LAYERED`, `GetLayeredWindowAttributes(hwnd, &key, &alpha, &flags)` with `LWA_ALPHA` and
    `alpha/255 < 0.35` means skip. (DWM-composited acrylic transparency cannot be read this way; accept.)
  - owner: `GetWindowThreadProcessId` then `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` and
    `QueryFullProcessImageName`; cache by PID. Ignore list: `explorer.exe` windows with class
    `Progman`, `WorkerW`, `Shell_TrayWnd`, `Shell_SecondaryTrayWnd`, `NotifyIconOverflowWindow`; processes
    `SearchHost.exe`, `StartMenuExperienceHost.exe`, `ShellExperienceHost.exe`, `TextInputHost.exe`,
    `LockApp.exe`, `dwm.exe`, `ApplicationFrameHost.exe` frames that are cloaked, and our own process except
    the Studio and Habitat windows (tag those with a window property `SetProp(hwnd, "SpiderFurniture", 1)`).
  - size: width `> 130` and height `> 90` in **logical units** (use the monitor's DPI to convert, so a 150%
    monitor does not shrink the threshold)
  - up to **28** windows, front to back (the order `EnumWindows` returns is already top to bottom
    z-order, so depth = index)
- **Corner radius.** `DWMWA_WINDOW_CORNER_PREFERENCE = 33` returns the *preference* (default, none, round,
  small round), not a radius. Map: default on Windows 11 means rounded about 8 px at 100% DPI (scaled by
  DPI), `DWMWCP_DONOTROUND` means 0, `DWMWCP_ROUNDSMALL` means about 4 px. A maximized window and a window
  on Windows 10 is 0. A window snapped to an edge may be square on those sides on Windows 11. **VERIFY by
  measurement:** write a probe that captures one window's corner with `PrintWindow` into a bitmap, finds the
  first non-transparent pixel per row from the corner, and fits the radius; run it for a Notepad, a File
  Explorer, an Edge, a Settings (WinUI), a maximized and a snapped window on your Windows 11 build. Hard-code
  the table (per class/exstyle) from the measurements rather than guessing. Clamp to `min(w/2, h/2)`.
- **Minimize:** on `MINIMIZESTART` remove the window from the list immediately and hold it out until
  `MINIMIZEEND`; on `EVENT_OBJECT_HIDE`/`CLOAKED` also remove at once. Mac's hold-out rule: stay dropped until
  it leaves the list or sits still 0.6 s (`WindowTracker.swift:168`); mirror that for restore animations.
- **Monitors:** `EnumDisplayMonitors` + `GetMonitorInfo` (rcMonitor, rcWork) + `GetDpiForMonitor
  (MDT_EFFECTIVE_DPI)`. Rebuild on `WM_DISPLAYCHANGE` and `EVENT_SYSTEM_DESKTOPSWITCH`. The y-up world: the
  existing code uses `y_up = virtualBottom - y_down` (`Program.PointerWorld`); keep one conversion function
  for the whole app (and its inverse) in `src/App/Coords.cs`, covered by a unit test with a negative-origin
  monitor layout.
- **Taskbar:** `SHAppBarMessage(ABM_GETTASKBARPOS)` for the primary and each secondary bar (and
  `ABM_GETSTATE` for autohide). The map treats the **work area** as the screen (spec 2.8), so the floor sits
  on the taskbar; for an autohiding bar the work area already covers it. Taskbar at left/right/top: the
  spider's rim follows rcWork; confirm the generated `DockStrip` is not double counting.
- **Full-screen / cinema:** per monitor, a window is full-screen when its extended frame equals `rcMonitor`
  within 2 units and it has no `WS_CAPTION`/`WS_THICKFRAME`, or `SHQueryUserNotificationState` is
  `QUNS_RUNNING_D3D_FULL_SCREEN`/`QUNS_BUSY`/`QUNS_PRESENTATION_MODE` and the foreground window is on that
  monitor. A *maximized* front window fills the work area within `maximizedSlack = 24` and is the front
  window on its screen (spec 14.1). Apply the 4-poll hysteresis (`Stage 2.7`).
- **Banners (toasts):** this needs a probe, because shell class names vary by build. Write `tools/windows/
  toast-probe.ps1` (or a hidden `--probe-toast` mode): subscribes to `EVENT_OBJECT_SHOW`/`CREATE` for all
  windows, and logs `class, exstyle, process, size, monitor` for each new top-level window; trigger a real
  toast (a PowerShell `BurntToast` or a `New-BurntToastNotification`, or the `Windows.UI.Notifications` API)
  and read the log. Expect the Win11 toast host to be `ShellExperienceHost.exe` (or
  `Windows.UI.Core.CoreWindow`) near the bottom-right of the work area. Encode what you see as a
  `ToastWatcher` that raises `OnBanner(screen)` only for new windows after startup. Never read text; do not
  use `UserNotificationListener`.
- **Signature for change detection:** include id, frame, depth, maximized, alpha-bucket, cloaked, full-screen
  state, and monitor id (the current one omits alpha, fullscreen and monitor, `DesktopCapture.cs:111-115`).
- **Acceptance:** drag a window. The spider on it follows within the same frame (16 ms), with no 0.55 s lag
  and no 7 px floating gap (compare to the invisible-border gap). Minimize a window under the spider: it falls
  or relocates at once. `SPIDER_MINIMIZE_TEST` equivalent passes.

## 4.6 Main loop

- Keep `DisplayTicker` (`DwmFlush`) at 60 Hz (it holds 60.0 to 60.1 fps in the existing runs). Add the 30 Hz
  Low Power path using `SpiderSensing.ClockHz`: skip every other tick.
- Port the **calm throttle** from `AppDelegate.tick` (`:1056-1060`): when nothing is visibly changing, skip
  frames, but still update hit-testing and the cursor every tick. `Clock.cs` already has a calm throttle; make
  sure the host consults it, because the current `Program.Frame` always runs `Update` and `Draw`.
- Frame order (mirror `AppDelegate.tick`, `:996-1131`): housekeeping beats (memory save every 3600 ticks,
  knowledge save at offset 1800), pageWatch, hit-test flip, visitors' hit-test flip, prey hit-test flip,
  hand-toy calm cancel, dt clamp `1/240...1/20`, toy update, cursor and visitor cursors, weather, music beat,
  hammock wipe, `spider.update`, pose, `updateVisitors`, hammock, carrying, tank entry, wildlife, prey,
  traces, hand, surroundings, hit-test flip again. Keep the same order in one `Frame()`.
- Host writes the **autosave every 60 s** (`tickCount % 3600`; memory) and **knowledge at +30 s** (audit gap).
- Everything the frame changes should be presented once at the end of the frame (the Mac wraps the frame in
  one `CATransaction`). On Windows: collect "present requests" from all layers during the frame and flush them
  together at the end, so a spider and its thread never appear one frame apart. Use `DwmFlush` timing so the
  presents land in one composition.

## 4.7 Phase 1 acceptance (live, on a two-monitor mixed-DPI setup)

- Spider is grabbable only inside its grab disc; a click one pixel outside reaches the app underneath;
  a click inside does **not** reach the app underneath.
- Click to Pick Up off: nothing is intercepted, anywhere.
- No visible lag behind a dragged window; no floating gap above a Windows 11 window.
- The Start menu and taskbar flyouts work normally with the overlay running.
- The name tag appears after 0.7 s of hover. A long thought bubble is not clipped.
- Standing spider: CPU in Task Manager below 1% (redraw gating working). Walking: below the spec's 15%.
- 60 fps with all layers present (prey, traces, silk, hammock) using `SPIDER_FRAMES`.

---

# Part 5. Phase 2: pose and renderer contract (2 to 3 weeks, parallel with Phase 1)

Reference: `Spider.swift` MARKs *Pose out* (line 22605), *Peek-a-boo* (4695), and
`Spider.swift:20335-20343` for the occluder logic; `SpiderRenderer.swift:343-367` for the draw order.

## 5.1 `SpiderPose` completeness

Add to `src/Core/Draw.cs` (`SpiderPose`), matching `Spider.swift:111-190`:
`silkAttach (V2)`, `web (anchor, alpha, slack)?`, `webPoints (List<V2>)`, `thread (a, b, tail, alpha)?`,
`threadFrom (V2?)`, `threadVia (V2?)`, `outfit (SpiderLook)`, and check the rest of the Swift struct (it
continues past line 190: confirm `hiddenBy`, `peekGrip`, `specks`, `wet`, `snow`, `dust`, `chill`, `chew`,
`headTurn` and any field the Swift has that the C# does not). Do a mechanical diff: extract the field list from
both and make the C# a superset.

## 5.2 `BuildPose` (currently `Spider.cs:434-496`)

- **`HiddenBy`:** port the occluder intersection (`Spider.swift:20335-20343`): for the loop the spider
  stands on, take every window **in front of** it (depth smaller) and add that window's rect (expanded by
  nothing; check the Swift for slack) if it intersects the sprite rect. The screen rim, taskbar and menu-bar
  analogues never occlude (spec 3.1; "however far a window reaches toward the edge"). The C# `SurfaceMap`
  already has an `occluders` concept (Stage 2 "Occlusion (11 checks)"); expose it to the pose.
- **`PeekGrip`:** currently two points are added only while peeking; verify the positions against Swift.
- **Weather fields:** `Wet`, `Snow`, `Dust`, `Chill`, `Specks`, `Surroundings`: port `Spider.swift` *Weather*
  MARK (line 3572) into a `SpiderWeather` partial and call it from `Update` and `BuildPose`. Specks are
  particles in world space with life and splash; determinism "by seed so they do not shimmer".
- **`Ball`, `Spin`:** assign from the roll activity (`Activity.Roll`) and add `Posture.For` branches for `Roll`
  and `Hop` (the audit notes the switch in `Activities.cs:90-140` has no such branches). Remove the dead
  expression `u < 0.45 ? 1 : 1` in `DoubleTake`.
- **Dangling and hammock legs:** `Update` currently calls `UpdateLegs` only in `Mode.Attached`
  (`Spider.cs:229`). Port the *Legs* MARK (line 17062) for dangling (four silk-holding legs and four hanging
  legs, spec 8.2) and hammock (tucked). Check `legMode` handling in the Swift.
- **`thread`/`webPoints`/`threadFrom`/`threadVia`:** produced in the Swift `Silk line` and `On a line` MARKs
  (10598, 21740). Needed so the SilkLayer can draw the thread and the sprite can draw the held stretch between
  the far legs and the body.

## 5.3 Renderer changes (`src/Renderer/SpiderRenderer.cs`)

Match `SpiderRenderer.swift` draw order (`:343-367`):

1. **`hiddenBy`:** build a path with the sprite rect plus each hiding rect (converted to body-local sprite
   space), `clip` with **even-odd**, so the covered parts are cut out. Draw the body inside this clip. Use
   `IDraw.ClipEvenOdd` (the shim already lists even-odd clip in the verbs). Verify that Skia's clip is
   anti-aliased the same way as CoreGraphics' (CG clips with AA by default; set `SKClipOperation` AA on).
2. **`peekGrip`:** drawn after the clip is released (the grip feet ignore the clip): two dots at the given
   points (radius and color from the Swift).
3. **Emote** drawn after the body in screen space, **not** in the sprite bitmap. Move `DrawNameTag` and the
   thought/emote text bubble to the `BubbleLayer` (4.2). The renderer exposes `DrawBubble(IDraw g, pose, ...)`
   and `DrawNameTag(...)` that the layer calls; `SpriteRaster` keeps `drawNameTag: false`, now on purpose.
4. **Weather coat and specks:** `drawWetCoat`, `drawSnowCap`, `drawDust`, `drawSpecks` (spec 3.8), with a
   darker glossy coat when wet, bead drops, snow cap sliding off when it moves, sand in fur, a bluish chill
   tinge, plus the fog dew drops.
5. **Ball pose** (egg 20x17, spec Appendix C).
6. **Thread stretch** held between far legs and body (`pose.thread`), and `threadFrom/threadVia` silk coming
   out of the spinnerets.

## 5.4 Phase 2 gate

`parity diff-trace` for `peek`, `rappel`, `climb`, `hammock`, `hunt-*` (pose fields now present) and
`parity diff-image` for peek-a-boo, hanging, ball, wet, snow, dust, chill. Contact-sheet cliptest still
passes (`drawRadius 72`).

---

# Part 6. Phase 3: art parity (6 to 10 weeks, parallel)

## 6.1 Transliteration tool (spend the first 2 to 3 days here)

Goal: convert Swift drawing functions to C# against the existing `IDraw` shim. The shim mirrors Core Graphics
(`Draw.cs`), so the translation is mostly renames.

Create `tools/transliterate/` (a small console project in the solution, or a Python script run on the dev
machine; use UTF-8 explicitly, `progress.md:375` records a file-truncation accident from a Python helper that
failed on a console codec):

1. **Input:** a Swift file and a list of function names (or a line range), as in the spec's Appendix F maps.
2. **Rules** (a table, one regex or small parser each, applied in order):
   - `ctx.setFillColor(red: r, green: g, blue: b, alpha: a)` or `setFillColor(CGColor(...))` becomes
     `g.SetFillColor(new Rgba(r,g,b,a))`; the same for stroke, line width, line cap/join/miter.
   - `ctx.move(to: CGPoint(x: a, y: b))` becomes `g.MoveTo(a, b)`; `addLine`, `addQuadCurve`, `addCurve`, `addArc`,
     `closeSubpath`, `addEllipse`, `addRect`, `addLines`, `addPath`.
   - `fillPath`, `strokePath`, `drawPath(using:)`, `fillEllipse(in:)`, `strokeEllipse(in:)`, `fill`, `stroke`.
   - `saveGState`/`restoreGState`, `translateBy`, `rotate(by:)`, `scaleBy`, `concatenate`.
   - `clip()`, `clip(using: .evenOdd)`, `beginTransparencyLayer`, `endTransparencyLayer`, `setAlpha`,
     `setBlendMode`, `setShadow`, `drawLinearGradient`, `drawRadialGradient`.
   - Types: `CGFloat` to `double`, `CGPoint` to `V2`, `CGRect` to `Rect`, `CGSize` to `V2`, `CGColor` to `Rgba`,
     `[T]` to `List<T>`, `.zero` to `V2.Zero`, `pow`/`sin`/`cos` to `Math.*`, `max/min` to `Math.Max/Min`,
     `abs` to `Math.Abs`, `.pi` to `Math.PI`.
   - Syntax: `let` to `var`/typed, `func f(_ a: T, b: U) -> R` to `static R F(T a, U b)`, `for i in 0..<n`
     to `for (int i = 0; i < n; i++)`, `switch x { case .a: ... }` to `switch`, string interpolation to `$"..."`,
     optional chaining `?.` and `if let` to a manual form.
3. **Output:** a `.cs` file with every unconverted construct replaced by `/* TODO(swift line N): <text> */`
   so a human fixes only those. Do not try to be 100%; aim for 80 to 90%.
4. **Do not generate at build time.** The output is reviewed and committed; the Swift file and line range
   go into a header comment (`// Ported from SpiderRenderer.swift:1234-1456 at <commit>`).
5. **Prove it on one item** (a hat such as `Bucket`) end to end, including the diff-image, before using it on
   anything else.

Checks on shim fidelity before relying on it (run once, small image tests):

- `addArc` direction and `clockwise` semantics (Core Graphics arc is clockwise in a flipped context; the
  Skia shim does the y-flip at the boundary).
- `setLineCap`/`Join`/miter limit defaults.
- Gradient extents (`CGGradientDrawingOptions.drawsBeforeStartLocation/AfterEndLocation`) vs Skia tile mode.
- `setShadow` blur radius semantics (CG blur is not Skia sigma; blur = 2 x sigma, **VERIFY**).
- Transparency layers (group opacity) map to `SaveLayer`.
- Even-odd fill and clip.

## 6.2 Missing Studio art

Counts from the audit (Studio exposes 38 hats, 30 accessories, 20 patterns; the renderer has cases for 24, 20,
10). Port in this order; each lands with its `parity diff-image` entry green.

1. **Patterns (9):** Skull, Moon, Flower, Leopard, Speckle, Marble, Zigzag, Diamonds, Rings. Today they all
   fall through to one central spot (`SpiderRenderer.cs:552`). Patterns must stay inside the abdomen
   (existing Stage 3 check) and ride the body-local transform.
2. **Hats (13):** Bucket, Viking, Tiara, Pirate, Mushroom, Sombrero, Mortarboard, Sailor, Jester, Ushanka,
   Sweatband, FlowerCrown, LittleBird. Fall through at `SpiderRenderer.cs:1260`. `HatStyle` already contains
   all 38 names (`SpiderDesign.cs:31-35`). Note `Hat is None or Crown or Halo or PartyHat or Tiara`
   special handling at `SpiderDesign.cs:289`; check what that does for the missing ones.
3. **Accessories (9):** Beard, FlowerLei, Headphones, Tutu, Backpack, Satchel, Bindle, Jetpack, Balloon.
   Fall through at `SpiderRenderer.cs:1448`.
4. **Audit the rest:** for the 24 hats, 20 accessories and 10 patterns that already have a case, compare against
   T3 images. The audit counted cases, not fidelity.
5. **Face and body:** 6 eye styles, brows, fangs, 6 body shapes, fluff, coats, living coats, gradients, custom
   colors, `Skin.swift` (810 lines): all through the image diff.
6. **Animated hats and extras:** propeller (driven by `odometer`), balloon sway, flowers, bird (LittleBird
   animates?), jetpack flame (**VERIFY** which are animated in the Swift).
7. **Leg styles and the optional leg systems** behind toggles (spec 4.8, the "Legs" Studio tab and the
   `legLayersByDepth` setting): confirm these behave per Swift.

For each: read the Swift function, run the transliterator, fix TODOs, render with `parity diff-image`, iterate
until it passes, then check at scales 0.62, 0.95 and 1.55.

## 6.3 Studio thumbnails

Option grids currently use text labels (`progress.md:584`). Replace with rendered thumbnails:

- A `ThumbnailCache` renders each option once with the real renderer at the Mac gallery's cell size
  (`tools/gallery/main.swift:7`: default 96 px) at the current display scale, on a background thread, and
  caches to `%LOCALAPPDATA%\SpiderBuddy\Thumbs\<hash of design-relevant fields + renderer version>.png`.
  Invalidate on renderer version change (a constant in `SpiderRenderer`).
- Grids are virtualised (draw only visible cells) so the 38-hat grid opens in under 100 ms from cache.
- Cell look (selection ring, hover, spacing) comes from the Mac screenshots (2.4).

## 6.4 Phase 3 gate

All T3 images pass `diff-image`; the gallery sheet diff passes; the contact sheet passes; the cliptest passes.

---

# Part 7. Phase 4: behavior port (8 to 14 weeks, the biggest block)

Rule: **transliterate, do not redesign.** The Swift `Spider.swift` is the algorithm. Keep constant names,
order of operations, order of random draws, and clamp values. Restructure only after the diff passes.

## 7.1 Working method per section

1. Read the Swift section end to end. List every `private var` it uses and every function it calls.
2. List the C# equivalent for each (`grep` the C# for the same constant, or note it as missing).
3. Write the C# so each Swift statement has a corresponding C# statement. Keep the Swift comments (the
   owner wrote reasons into them; they explain the feel) and record `// Swift:<line>` markers every ~20 lines.
4. Run the section's scenarios through `parity diff-trace`. Fix the first divergence, rerun. Repeat.
5. Record in `progress.md`: Swift line range ported, scenarios green, remaining diffs.
6. Do **not** relax a tolerance to make it pass; open an issue with the divergence instead.

## 7.2 Order and content (Swift MARK map from spec Appendix F)

| # | Swift section (MARK, approx. lines) | Windows target | Specific things to verify |
|---|---|---|---|
| 1 | *Walking*, *Natural walk*, *Refined walk*, *Legs* (17062 to 21740) | `SpiderMove.cs`, `SpiderRig.cs`, `Spider.cs` | tetrapod phase table (0.09/0.56/0.03/0.50/0.59/0.06/0.53/0.00), stride 28, duty 0.34, `footJolt` 26000, reach limit 1.25, hand-off 0.26 s, corner foothold behavior, stance compensation in world space, `legLength` = thigh + shin. Targets from A12/A13. |
| 2 | *Attached*, *Posture* (11522 to 12732) | `Spider.cs`, `Activities.cs` | the full posture table (speed, lift, pitch, crouch, wag, lid, bob) per activity with per-bout variation; spec 4.3 |
| 3 | *External input*, *Frame update* (1421 to 2388+) | `Spider.cs` | frame order, dt clamps (`<=1/30` in the spider), spring order |
| 4 | *Pointer as prey*, *Rescue* (2791, 8858) | `SpiderPointer.cs`, `SpiderAir.cs` | landing, bounces (restitution `lerp(0.28, 0.72, bounciness)`), actual rescue catches (listed as not implemented), web-active slingshot, held-line constraint, cursor hunt stalking/pouncing/clinging, `clingShake` |
| 5 | *Left to itself*, *Body language*, *Decisions* (12732 to 14127) | `SpiderBrain.cs` | the full priority list of spec 6.2 and weighted draw of 6.3. Missing: cinema, homing/hammock, laser, visitor tag, meal carrying, web job, music, tank errand, weather, fright, inquiry, bed-on-window; autonomous leap, rappel, swing, build/finish hammock, nap, mend, explore, bounce. Wire the Hammock and Nap habit weights. Decision interval 1.0 to 3.4 s divided by liveliness. |
| 6 | *Jumping*, *Airborne* (14127 to 14925) | `SpiderAir.cs` | jump arc planning, `maxJumpSpeed 1250`, gravity -1950, air drag `exp(-0.22 dt)`, landing absorb 0.35, land hold 0.5, covered-escape |
| 7 | *Silk line*, *Dangling*, *On a line*, *Over the top* (10598, 14925, 15290, 21740) | `SpiderSilk.cs`, `SilkRope.cs` | rappel, hang rules (spec 8.2), climb rules (8.4), mantle (8.5), scroll orders (8.6), swing (8.7) |
| 8 | *Hammock* (16209) | `Spider.cs` (new partial) | sag 0.42/0.66/0.50/0.34, strands 7/9/6/6, give 10/16/8/12, drape 2.4 s, wall anchor 0.62 down; legs tucked; door seat |
| 9 | *Peek-a-boo* (4695) | `SpiderPeek.cs` | already exists; verify |
| 10 | *Food*, *Toys*, *Traces* (8917, 9547, 10212) with `Prey.swift` (2028), `Toys.swift` (960), `Traces.swift` (1436) | `SpiderPrey.cs`, `SpiderToys.cs`, `SpiderTraces.cs` | all 8 creatures; hunt (watch, approach, stalk, ambush/pounce, carry, eat); toy line-tow; little web building; per-strand rope |
| 11 | *Thoughts* (3240) | `SpiderTalk.cs` etc. | thought table, timing, suppression in cinema |
| 12 | *Weather* (3572), `Memory.swift` (472), `SystemSense.swift` (324) | `SpiderMemory.cs`, `SpiderSensing.cs` | reactions only; sensors are Phase 7 |

Row 1 is the highest-impact piece for "feel". Do it first, and do it before art, because every film strip
depends on it.

## 7.3 Specific audit items to close in this phase

- Stage 5 gaps (`progress.md:402, 416`): landing, bounces, rescue catches, continuous head/body follow,
  stroke/whip/fidget reactions, cursor hunt/cling.
- Stage 6: replace the 22 self-commanded checks with parity runs (`free-4min`).
- Stage 8: dangling and hammock legs (also Phase 2).
- Stage 13: favorite-place pull, `moodGlow`/`moodShaken` weighting in carriages, every habit lean applied in
  weighted draws (`progress.md:497-499`).
- Stage 12: full `SilkRope` sag per strand, little-web build sequence, flies stuck in silk, toys towed on a line.
- Stage 15: clip the surface map to the box, hanging line in an empty box, visitor bodies that walk, play
  tag and leave by leaping, full visitor look generator.

## 7.4 Per-section exit

The section's scenarios in `parity all` are green (exact where marked exact, statistical elsewhere).
`progress.md` updated. No tolerance changed.

---

# Part 8. Phase 5: desktop features that need a window (3 to 5 weeks, after Phase 1 and the matching Phase 4 row)

Each feature = layer (Part 4.2) + behavior (Part 7) + art + hit-testing + film/screenshot comparison.

| Feature | Layer | Art to port | Hit-test |
|---|---|---|---|
| Prey | `PreyLayer` | 8 creature drawings from `Prey.swift`; signature motions | creature under pointer, drag, feed menu |
| Wildlife | `PreyLayer` | same | entrances at screen side/crack, ant lines, night/rain odds |
| Toys | `PreyLayer` + `HandCatcherLayer` | ball, feather, bell, wind-up bug from `Toys.swift` | pick, place, throw (2700 cap), Esc hotkey |
| Laser | `PreyLayer` | `LaserView` (`OverlayWindow.swift:838`) | follows pointer |
| Silk | `SilkLayer` | dragline, swing line, held threads; rope edge | none |
| Hammock | `HammockLayer` | port `HammockView` strand drawing | wipe-with-pointer tears it |
| Traces | `TraceLayer` | strands, little webs, meals (`Traces.swift`) | none; Tidy Up |
| Visitors | `VisitorLayer` x5 | visitor look generator | per-visitor hit-test flip |
| Box | `BoxDrawLayer`, outline | `BoxDrawView`, `BoxOutlineView` | takes mouse while drawing |
| Rain | `RainLayer` | `RainView` streak bitmap | none |

Also here:

- **Autosave** every 3600 ticks (memory) and the knowledge save at 1800 offset.
- **Rain/showRain:** the setting exists and writes; nothing reads it today (audit F9).
- **Memory host use:** use favorite places in the brain (Phase 4 row 5).

Acceptance: for each feature, a screen recording on Windows next to the Mac clip (2.5) with the same scenario;
the owner judges. `SPIDER_*_TEST` equivalents added for each (Part 11.3).

---

# Part 9. Phase 6 (renumbered 7 below): native sensors (2 to 3 weeks, after 4.5)

All opt-in, off the UI thread, no content read. Spec 14.

| Sensor | Windows API | Core call | Test |
|---|---|---|---|
| Battery Saver | `PowerRegisterForEffectivePowerModeNotifications` (`EFFECTIVE_POWER_MODE_BATTERY_SAVER` / `EfficiencyMode`; **VERIFY** the enum names on your SDK) | `SetLowPower(bool)` | toggle Battery Saver |
| Charger plug/unplug | `RegisterPowerSettingNotification(GUID_ACDC_POWER_SOURCE)` and `GetSystemPowerStatus.ACLineStatus`; only the **moment** (not at launch) | `PlugIn()` | plug/unplug (or the Mac-style `SPIDER_*` fake) |
| Weather | `HttpClient` to Open-Meteo every 20 min and once at start; IP-based location (any no-key geolocation HTTPS endpoint; use one stable one and cache the result); `current=precipitation,weather_code,wind_speed_10m,is_day,temperature_2m` | `SetWeather(code, wind, isDay, temp)` | `SPIDER_RAIN=1` |
| Volume | `IAudioEndpointVolume.RegisterControlChangeNotify` (CoreAudio COM via CsWin32/NAudio) | `OnCommotion(louder/quieter)` | change volume |
| Brightness | WMI `WmiMonitorBrightness` / `WmiMonitorBrightnessEvent` (internal displays only) | `OnCommotion(brighter/dimmer)` | change brightness |
| Banner | `ToastWatcher` (4.5) | `OnBanner(screen)` | real toast |
| Lock/unlock | `WTSRegisterSessionNotification` (`WTS_SESSION_LOCK`/`UNLOCK`) | `SetLocked(bool)` | Win+L |
| Cinema | 4.5 full-screen detection | `EnterCinema(screen)` | full-screen video |
| Music | WASAPI loopback + session enumeration | `SetMusic(beat)` | see below |
| User idle | `GetLastInputInfo` | `UserIdleFor` (wildlife gate, sleep, "company"/"alone" memory) | wait |

Also: the host never feeds `Night`, `Raining`, `UserIdleFor` into the core today (`progress.md:455-457`). Add
`Night` from local time (the Mac rule is in `Prey.swift`/`SystemSense.swift`; copy it).

**Music pipeline** (spec 14.5; the Mac `Ears.swift` 372 lines and `Beat.swift` 555 lines):

1. `Ears`: once per second, check whether another process is **actually playing** using
   `IAudioSessionManager2.GetSessionEnumerator` and `IAudioMeterInformation` peak or `AudioSessionState ==
   Active` on the default render device, excluding our own process. Open a loopback capture
   (`IAudioClient.Initialize` with `AUDCLNT_SHAREMODE_SHARED | AUDCLNT_STREAMFLAGS_LOOPBACK`) only while
   something plays; close 12 s after silence; reopen a silent capture every 10 s while apps play. Windows needs
   no permission prompt for loopback. Status values: unsupported/off/quiet/listening/hearing(bpm)/deaf for the panel.
2. Convert to mono float at the analysis rate used by the Mac (**VERIFY** in `Beat.swift`; the spec says log-band
   spectral flux at **100 fps**), 44.1 or 48 kHz hop accordingly.
3. `Beat.cs`: port `Beat.swift` line for line with an FFT (KissFFT port or `MathNet.Numerics`/`pffft` P/Invoke;
   prefer a small self-contained radix-2 so the core stays dependency-free). Pieces: log-band spectral flux,
   tempo by autocorrelation comb over {1,2,3,4,8 beats} with a log-normal prior centered on 118 BPM, phase
   comb on full and low-band onsets, PLL clock nudged into line (never jumps), output
   `MusicBeat{bpm, phase, confidence, energy, bar}`. Gotchas from the spec: simple-ratio tempo flips are the
   same pulse; the first frame after silence must not count as an onset; speech never runs more than about
   6 s "playing" so a 3 s steady gate (`musicSteady`) applies; `displayLead` about 35 ms (tune on Windows; the
   Mac measured 26 ms tap-to-air on laptop speakers). `SPIDER_BEAT_LAG=ms` for tuning.
4. Test with the Mac's audio (2.8) and expected BPM outputs.

Panel status lines read back real state, replacing the permanent "No music detected".

---

# Part 10. Phase 7: shell and UI fidelity (3 to 4 weeks, parallel)

The shell works. The gap is look and feel. Compare against the Mac screenshots (2.4) and layout dump (T4).

- **Panel** (7 pages, 600x650): pixel-compare each page; match spacing, section header style, control
  heights, slider look, corner radii, shadows, colors. Fonts: Segoe UI Variable, sizes from the dump.
  Keep first-open under 100 ms (currently 9.8 ms).
- **Tray popover:** the Mac uses an `NSPopover` from the menu-bar icon. On Windows show the same panel in a
  custom borderless window anchored above the notification area icon (`Shell_NotifyIconGetRect`), with a
  similar open animation (a 120 ms fade and 6 px rise; read the Mac's animation from the recording), dismissed
  on deactivate. Also the tray right-click menu with the same item order and names.
- **Studio** (12 tabs): the two-row custom tab strip exists. Match grid cells (Part 6.3), the live preview
  stage, the Surprise/Start Over buttons, the personality sliders and their labels.
- **My Spiders:** card list look.
- **Welcome tour** (920x600, six house rules) and **first entrance** timing (phases stir, peek, look, shy, drop,
  hello) against recording 18.
- **Chat pill** and **bug report** window.
- **Dark mode:** if the Mac follows system appearance (2.4), follow `AppsUseLightTheme` and respond to
  `WM_SETTINGCHANGE` ("ImmersiveColorSet"). Title bars via `DWMWA_USE_IMMERSIVE_DARK_MODE`.
- **High-DPI:** custom-drawn controls must scale; test at 100%, 125%, 150%, 200%.
- **Accessibility:** keyboard navigation and Narrator names are not in the Mac spec; add reasonable defaults but
  do not let them change the look.

---

# Part 11. Phase 8: habitat art and 60 fps (6 to 10 weeks)

The simulation is real. The paint and the frame rate are not.

## 11.1 Art port

| Swift file | Lines | What |
|---|---|---|
| `HabitatItems.swift` | 891 | per-kind item painting (a log, lantern, fireplace, door all differ) |
| `HabitatArt.swift` | 1,392 | furniture and decor art |
| `HabitatNatureArt.swift` | 1,377 | plants, rocks, water |
| `HabitatHomeArt.swift` | 1,009 | home furniture |
| `HabitatPieceArt.swift` | 555 | structure pieces |
| `HabitatAtmosphere.swift` | 593 | light, sky, fog |
| `HabitatWeather.swift` | 1,698 | rain, snow, lightning, wind particles |
| `Weather.swift` | 768 | desktop-side weather types |

About 7,500 lines. Use the transliterator, then diff against `perch.sh sheet`, `pieces`, `build`, and each world
(A18 to A21). The current `HabitatWindow.DrawItem` (`HabitatWindow.cs:1412-1445`) fills `HabitatGeometry` visual
polygons; replace with a per-kind painter dispatch that mirrors `HabitatItems`. Keep the geometry (it is
the collision source) and paint over it.

## 11.2 Particles and weather

Custom particle system (rain, snow, fireflies, leaves, dust). Spec 17b traps apply (the Mac used
`CAEmitterLayer`). Pre-render the particle sprite once; draw N instances per frame; cap counts to the
Mac's; deterministic by seed.

## 11.3 60 fps and cost

- Change the repaint timer from `Interval = 33` (`HabitatWindow.cs:99`) to the display ticker (60 fps).
- Cache static layers (backdrop gradient, sun/stars, far scenery) as bitmaps redrawn only when the camera
  or time-of-day bucket changes; draw only dynamic items and creatures per frame.
- Use GPU-backed Skia (`SKGLControl`/`GRContext` via ANGLE, or `SkiaSharp.Views.Desktop` GL) if CPU painting
  cannot hit 25% in a storm (the spec target). The GPU frame capture noted at `progress.md:601` suggests a
  GPU path exists; confirm what it is.
- Measure with the Mac numbers (2.6) as the target, not the spec's guess.

## 11.4 Gate

World images (A19), item sheet (A18), pieces (A20), weather shots (2.4) pass image diff; 30-minute **GUI**
habitat soak at 60 fps below the CPU target; the 50 open/close cycles still pass.

---

# Part 12. Phase 9: verification and release (2 to 3 weeks, gates all the way)

## 12.1 Gates (hard, in `release-gate.ps1` and `parity all`)

| Gate | Pass |
|---|---|
| `tools all` | 100% (existing 1050 plus new parity checks) |
| `parity all` | every exact scenario green; every statistical metric inside band; every image passes |
| Desktop soak, 30 min, real app | mean fps >= 58; CPU: <= 15% active average, <= 4% resting (use the Mac's measured numbers if they differ); working set growth < 5 MB / 10 min; no stall > 100 ms |
| Habitat soak, 30 min, GUI | fps >= 58 in calm; storm <= 25% CPU; no growth |
| Jerk detector, live host | < 2 flags/min per activity pair (the spec's number), run on the **real host**, not just headless |
| Draw-radius cliptest | every pose inside 72 |
| Multi-monitor mixed DPI | spider walks across, scale transitions on landing only, no blur, hit-test correct on both |
| Full-screen video | cinema within 4 polls, release after; with a game in borderless mode |
| Lock/unlock | sleeps, greets; never left asleep |
| Start/taskbar/Task View/Alt-Tab with overlay | never lose a click |
| Virtual desktops | overlay on all |
| Install/uninstall/update | existing `test-install.ps1` plus a real appcast round trip |
| Extension | Chrome and Edge matrix with the real extension |

## 12.2 Human review

Side-by-side videos for the 21 clips (2.5) with Windows next to the Mac. The owner signs each off. The spec's
rule applies: metrics passed rounds that still looked wrong; judge the drawn output.

## 12.3 Release

Production Authenticode (EV certificate or Azure Trusted Signing); the existing `release.ps1 -Publish` flow;
installed-app update test against the real feed; keep the private update key backed up
(`build/windows/keys/`, flagged in `progress.md`).

---

# Part 13. Schedule, risks, first week

## 13.1 Dependency graph

```
Phase 0 oracle ──┬─ Phase 1 host ──┬─ Phase 5 windows features ─┐
                 │                 └─ Phase 7 sensors            │
                 ├─ Phase 2 pose ──────────────────────────────┤
                 ├─ Phase 3 art (needs 6.1 tool) ───────────────┼─ Phase 8 shell ─ Phase 9
                 ├─ Phase 4 behavior ──────────────────────────┤
                 └─ Phase 8 habitat art (needs 6.1 tool) ───────┘
```

Phase numbering note: the document sections are Parts 3 to 12; "Phase 5 windows features" is Part 8,
"Phase 7 sensors" is Part 9, "Phase 8 shell" is Part 10, habitat art is Part 11, verification is Part 12.

## 13.2 Effort (one developer, calendar weeks)

| Part | Work | Weeks |
|---|---|---|
| 3 | Oracle | 1 to 2 |
| 4 | Host | 4 to 6 |
| 5 | Pose and renderer contract | 2 to 3 |
| 6 | Art | 6 to 10 |
| 7 | Behavior port | 8 to 14 |
| 8 | Window features | 3 to 5 |
| 9 | Sensors | 2 to 3 |
| 10 | Shell and UI | 3 to 4 |
| 11 | Habitat art | 6 to 10 |
| 12 | Verification and release | 2 to 3 |

Serial total 37 to 60 weeks (about 9 to 14 months). With three parallel streams (host+sensors+shell,
behavior, art+habitat) about 5 to 7 months. These are estimates; the first two weeks (Phase 0 and the spike
in 3.4) will tell you which half of the range you are in.

## 13.3 Faster cut (8 to 10 weeks)

Phase 0, Phase 1, Phase 2, Part 6.2 items 1 to 3, Part 7 rows 1, 4, 5. Result: the spider is hit-tested,
tracks windows in real time, hides behind windows, hangs on a thread, the Studio has no fallback shapes and
the brain has the real repertoire. Prey, toys, traces, visitors, sensors and habitat art follow.

## 13.4 Risks

1. **Feel drift.** The Mac build is the oracle; do not start Part 7 before `parity diff-trace` runs.
2. **Cross-platform float drift** may defeat exact comparison early (3.4 spike). Mitigation: resync mode and
   statistical comparison.
3. **Random draw order.** Any restructuring that changes the sequence of draws breaks frame-exactness;
   transliterate, then refactor.
4. **Overlay behavior on Windows 11** (topmost vs Start, virtual desktops, alpha-0 hit-testing, mixed DPI).
   Spend two days on a throwaway prototype of 4.1 and 4.4 before building 10 layers.
5. **Art volume** (about 20k lines across spider and habitat). The transliterator is the schedule lever.
6. **Skia vs Core Graphics rendering differences** (AA, gradients, shadows, text) mean image thresholds need
   tuning on a known-good sample first; do not over-tighten.
7. **Fonts.** SF Pro cannot ship; text widths will differ slightly. Plan layouts with slack.
8. **Toast detection and cloaking quirks** vary by Windows build; keep behind a setting and probe per build.
9. **No Mac, no oracle.** Without Part 2 only code reading remains.
10. **Windows differences by design** (no notch/menu bar/widgets/Spaces) are recorded in spec 2.8; keep that
    table so they are not mistaken for gaps.

## 13.5 First week

1. Do Part 2 (Mac capture), at least the A-list, T1, T2 for one scenario (`flat-walk`, seed 1, scale 0.95).
2. Windows: write `parity trace` for `flat-walk` and the 3.4 drift spike. Decide exact vs resync.
3. Windows: fix the lying gates (3.7).
4. Windows: prototype `LayerWindow` with `CreateDIBSection` + `InstallPixels` + alpha-1 hit disc + click-through
   flip (4.1, 4.4); confirm clicks, Start menu behavior, and CPU for a standing spider.
5. Windows: write the transliterator and prove it on the Bucket hat (6.1).

## 13.6 Open decisions for you

1. **Mac availability** and who runs Part 2.
2. **Exact vs statistical comparison** for the brain (settled by the 3.4 spike).
3. **GPU vs CPU Skia** for the habitat (settled in 11.3 by measurement).
4. **Font** (Segoe UI Variable recommended).
5. **Talking spider:** keep the built-in phrase engine and label it, or integrate a model later.
6. **Dark mode:** follow Mac behavior (2.4 tells us).
