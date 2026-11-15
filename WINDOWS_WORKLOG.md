# Windows port work log

Newest first. What was done, the evidence, decisions and why, what is next.

## 2026-11-06: Reorganized around the Mac being available

**Starting point.** A C# port from a prose spec, 1,050 passing self-checks, no Mac comparison ever run, and all of it
untracked in git on the laptop.

**Done**
- Committed the whole port to a new `windows` branch and pushed it to GitHub (`e30fec9`, `9dff43a`). Mac build products
  no longer tracked on this branch. The imported conversation log and signing keys are excluded because the repo is public.
- Set up the Mac dev clone at `~/Documents/Visual Studios/Projects/spider-buddy-windows`, and git sync with the laptop.
- Wrote `lap` and the bridge. SSH is session 0 with no desktop, so GUI runs go through a one-shot interactive scheduled task
  under a headless conhost. Verified with real screenshots.
- Baseline: Release build 15 s, `tools all` 1050/1050 in 8 s.
- Wrote the workflow doc, status table and this log. Moved older docs to `docs/windows/`.

**Decisions**
- Oracle is v1.0.1 (`Sources` tree `7c878d73`). Leg system v2 comes later. (Owner.)
- Branch in the same repo, pushed. (Owner.)
- Laptop is available for development; the owner sometimes needs it for class. Back off when in use. (Owner.)
- Oracle runs of the real Mac app use a separate bundle id, because `capture-app.sh` rewrites the settings that hold the
  owner's real spider.

**Next:** see the status file.

## 2026-11-06: Spike: the unchanged Mac Swift core runs on Windows

**Question.** The plan's diagnosis is that the C# was never a port of the Swift, and its fix is to transliterate about 60k lines by hand. `Spider.swift` turned out to have only 3 AppKit references. Can the Mac's Swift just be compiled for Windows?

**Result: yes, and it matches the Mac almost exactly.**
- Installed Swift 6.4.2 with VS 2022 Build Tools and the Windows 11 SDK on the laptop.
- Wrote stand-in modules (`src/SwiftShims/`): `CoreGraphics`, `QuartzCore`, `AppKit`, `Accelerate`. About 1,200 lines. `Sources/` unchanged: the build makes only the same two swaps `tools/trace.sh` makes on the Mac (seeded `Bool.random`, pinned hour).
- `Spider.swift` and the 23 other core files compile and link; 240 s per optimized build, 45 s to typecheck.
- **66 of 66 captured Mac scenarios match, x86-64 Windows against arm64 Mac: worst position error 1.82e-12 units**, against a tolerance of 0.02. Includes walks, corners, the 8 hunts, rappel, climb, swing, hammock, peek-a-boo, pointer play and 37 activities. Table in `tests/parity/parity-traces.md`.
- Checked the checker: wrong scenario fails, a different hunt fails, and a 0.03 error injected on one frame is caught at that frame.
- Compiler differences do not matter: `-O` against `-Onone` differs by at most 5e-15.

**Fixed in the Mac capture tools:** `tools/trace.sh` needed `SpiderLibrary` in its file list. `rngprobe`, `imagedump`, `trace` otherwise built and ran first time, and the same seed gives byte-identical traces.

**Not yet shown:** drawing, the host, the UI. The C# code is still in place. Retiring anything is the owner's call.

## 2026-11-06: Spike: the art draws the same

- `CGContext` now draws through Skia (`src/SwiftShims/CoreGraphics/SkiaBackend.swift`, bound to `libSkiaSharp.dll` by name at run time).
- The Mac's `tools/imagedump` runs on Windows from the same source. Its 770 images are every Studio option at two sizes plus 60 whole poses.
- **768 of 770 pass** the image test against the Mac (SSIM at least 0.985, mean error at most 3/255). Median SSIM 0.9995, median error 0.15/255. The 2 misses are the text inside thought bubbles, a font difference.

**Found by the diff:**
- `CGColor(red:green:blue:)` and calibrated `NSColor` on the Mac are Generic RGB at gamma 1.8, and Core Graphics converts them to sRGB. Before handling this, 620 of 770 passed and bodies looked subtly off. The matrix comes from Apple's own profile and agrees with `CGColor.converted(to:)` within 0.0002. Gradients made from raw device components stay unconverted, also matching the Mac.
- `sk_matrix44` is laid out by columns.

**Open:** the name tag and bubble text. The Mac uses Helvetica Neue Medium, Windows has no such face, and Arial has no medium weight, so text renders too light. Needs a decision on a font to bundle.

## 2026-11-06: Full trace comparison, and a false failure run down

**Result:** all five sizes and seeds 1, 2, 3, 42: **183 of 183** scenarios pass, worst position error 1.12e-6 units. Free runs, liveliness 3, 240 s, seeds 1 to 8: **8 of 8 frame-exact**, 14,400 frames each, every state name equal. The plan expected to need statistical comparison for these. It does not.

**The false failure:** the first full run gave 180/183, with `climb` on 3 seeds differing in its last 10 frames while the body stayed identical. Leg 2 stepped on the Mac and leg 7 on Windows. The steps that found it:
1. Suspected an unseeded `randomElement()`. Wrong: the Mac agreed with itself 5 for 5, and a probe gave the same random stream on both.
2. Windows disagreed with itself between runs, and the probe showed why: **the Windows Swift runtime ignores `SWIFT_DETERMINISTIC_HASHING`**, so Set and Dictionary order changes each launch.

The fix is `CGPinHashingForTests()`, which sets the runtime's `_swift_stdlib_Hashing_parameters` directly, in the test tools only. Hash values and Set order then match the Mac's exactly. The real app is unaffected: on the Mac too, that order varies from launch to launch.

**Why it matters:** Set and Dictionary order does affect which leg moves, on both platforms. Any test run on Windows that does not pin hashing is not repeatable.

## 2026-11-06: Host: 60 fps, silk, and the taskbar

- **60.0 fps, from about 44.** `RunLoop.main.run(mode:before:)` blocks about 10 ms per call on Windows, even with a deadline in the past. The frame loop now works as the Mac's does: the main thread stays in the run loop, and a thread waiting on `DwmFlush` queues each tick. Spider update is about 0.1 ms and draw plus present about 1.3 ms, with no redraw gating yet.
- **Silk thread** has its own window under the spider, using the Mac's `silkPath`. Only the box around the thread is cleared or shown.
- **The floor was on top of the taskbar icons.** Reporting the taskbar as the gap between `frame` and `visibleFrame` made the Mac's Dock logic treat it as a short centered strip. The work area is now the screen, as spec 2.8 says, and the floor sits on the taskbar across the full width.
- The owner has been picking up and throwing the spider on the real desktop during these runs: `held` and `thrown` states in the host log, ending in normal landings.

## 2026-11-06: Decision: the Swift route

The owner chose the Swift route. `Sources/` compiled against stand-in modules replaces the C# core and renderer; the UI will come from `Panel.swift`, `Studio.swift` and the rest running against a small AppKit stand-in. The C# stays until each part is replaced.

## 2026-11-06: Whole-app build started (stopped mid-way: laptop going to sleep)

**State: work in progress. `src/SwiftShims/AppKit` does not compile yet**, so `build-trace.ps1` and `build-app.ps1` fail until it does. The last good binaries are still in `build\swift` on the laptop (`SpiderHost.exe`, `Trace.exe`, `ImageDump.exe`).

**Written, none of it run yet:**
- `tools/windows/swift/build-app.ps1`, `ba`, `errs`: build everything in `Sources/`. Copies each file and mechanically rewrites `@objc` and `#selector` (no Objective-C runtime); `src/SwiftWin/` replaces Mac-service files by name (`Ears`, `SystemSense`, `Updater`, `PageBridge`, all stubs for now).
- `QuartzCore`: real layer tree, compositing through Core Graphics, animations evaluated at draw time. Emitters hold state only; no particle simulation yet.
- `AppKit`: `Layout` (anchors and a Cassowary solver), `View`, `Window` (Win32, layered or titled), `App` (display beat, input pump, screens, window list), `Text`, `Graphics`, `Controls`, `Menu` (native menus, tray, popover, alerts, panels, clipboard).

**Next:**
1. Fix the current error: `App.swift:291`, the `EnumWindows` callback captures context. Then `tools/windows/swift/ba -Check -Opt -Onone` and `tools/windows/swift/errs`, repeating until the whole app typechecks.
2. Rerun `paritytraces.py` and `imgrun` after the shim changes: they must stay at 183/183, 8/8 and 768/770. The new `CGColor`, `CGContext` and `NSColor` paths are all shared with them.
3. Run the real app: `main.swift` and `AppDelegate` on the desktop, with silk, prey, traces and hammock through the Mac's own code.
4. Panel first, side by side with the Mac.

## 2026-11-14: The whole app builds; first launch crashes at start

**Done**
- Fixed the `EnumWindows` capture error, then worked through the rest: **the whole Mac app now typechecks and links
  for Windows** (`SpiderBuddy.exe`, `553e669`). `-continue-building-after-errors` in `build-app.ps1 -Check` lists every
  file's errors in one pass (134 at the start of the round, 0 at the end).
- Windows equivalents written for the macOS services the app calls: Carbon hot keys on `RegisterHotKey`; lock, unlock,
  sleep, wake and display sleep from WTS session and power notices; idle time from `GetLastInputInfo`; window pictures
  through GDI (`BitBlt` without `CAPTUREBLT` gives what is under our layered windows) and `PrintWindow`; the desktop
  picture and its placement; CPU clocks; machine facts for the bug report; run-loop observers for `Perf.swift`.
- Quartz: layer timing (`speed`, `timeOffset`, `beginTime`, `convertTime`; a stopped layer no longer forces redraws),
  animation phase (`timeOffset`), motion along a keyframe `path`, additive transforms, `NSValue(caTransform3D:)`.
- AppKit: KVO for a window's first responder, real `UTType` conformance table, `NSText` delegates as AppKit has them,
  `sizeThatFits`, `NSRect.fill()` with copy compositing, `NSBezierPath.reversed`, drag-destination hooks, and more.
- `makeImage()` on a little-endian premultiplied-first context now returns RGBA (it returned BGRA labelled RGBA).
- `build-app.ps1 -Debug -Out build\swift-app`: CodeView debug info, PDB and linker map, in a folder apart from the
  trace tools. `SPIDER_CRASH_STACK=1` writes the faulting stack as module offsets to `%TEMP%\spider-crash.txt`.

**Evidence:** traces still 183/183 (worst 1.12e-6). Images still 768/770 against `capture-quick/images-notext` with
`ID_NO_TEXT=1`. (`capture/images` is empty on the Mac; the workflow doc and `imgrun` were pointing at it.)

**Open: the app crashes at launch,** before `NSApplication.shared` finishes initializing (the crash-stack marker is
never written). Release build: "Index out of range"; debug build: access violation in swiftCore. Swift's own
backtracer cannot read our PDBs and crashes itself; `SWIFT_BACKTRACE=enable=no` is not honored. lldb through the
bridge did not start.

**Stopped:** the laptop went offline mid-build (no ping, SSH timed out).

**Next:**
1. Rebuild `-Debug -Out build\swift-app`, run with `SPIDER_CRASH_STACK=1`, read `%TEMP%\spider-crash.txt`. If the
   marker is missing, the fault is before `CrashStack.install()`: move the install to the first line of the shim's
   static init, or symbolize the raw swiftCore offset against the map with `llvm-symbolizer`.
2. Get to a running app on the desktop: spider, tray icon, menu.
3. Panel first, side by side with the Mac.
4. Known gaps found while porting, each visible in the UI: `NSWindow.nextEvent(matching:)` returns nil (drag loops in
   the habitat), `segmentDistribution` is not used by layout, emitters have no particles, field editors are a stub,
   drops are not wired to `WM_DROPFILES`, the Windows updater is a stub.

## 2026-11-15: The Mac app runs on Windows; the welcome window matches the Mac

**The launch "crash" in debug builds** was the build: `/DEBUG` turns on incremental linking, which pads Swift's
metadata sections, and the runtime then reads garbage on its first conformance lookup. `-Debug` builds link with
`/INCREMENTAL:NO`. The release build's own crash was real: `NSSegmentedControl` sized its arrays in `didSet`, which does
not run in a class's own initializers.

**Then a hang: Auto Layout.** The panel is 340 views and 3,330 constraints. The stand-in's solver pivoted on the most
negative coefficient (which cycles on these degenerate systems), kept positions window-wide (so a long stack's rows filled
in with every view before it), and hashed every cell. Now: positions relative to the superview with constraints written
over each item's path to the root (shared ancestors cancel), sorted-array rows with an id-indexed tableau and column
index, Dantzig pivots with Bland's rule during degenerate runs, and a per-root cache of recent answers. A fresh solve of
the panel went from minutes to 0.13-0.4 s, and an unchanged one takes 10 ms.

**Comparing with the Mac.** `tools/oracle-app.sh` builds the Mac app from this clone with its own bundle id
(`com.gabriel.desktopspider.oracle`) and the Windows stand-in `Updater.swift` in place of Sparkle, so it cannot touch the
owner's spider. `tools/windows/swift/welcome-diff` runs the Mac's own `SPIDER_WELCOME_SHOT` hook on both and puts the
pages side by side. `tools/controls` is a control gallery compiled against real AppKit on the Mac and against the
stand-in on Windows. Every change below was measured from real AppKit on the Mac (probes kept under `tools/`), not taken
from memory:
- `NSStackView`'s own constraints and priorities, read from AppKit's `constraints`: hugging 249.99998, first edge 750,
  spacing 749.99, far edge at the hugging priority, alignment 260, cross-axis edges hugging each view. Wrapping labels
  want their whole text on one line. (Before: labels collapsed to zero width, and spare room stretched rows.)
- System colours for macOS 27 (`tools/windows/swift/probe-colors`); window background is now 30 in dark and white in
  light.
- Text: Segoe UI drawn with SF Pro's metrics (ascender 0.96680, descender 0.21094) and AppKit's label line heights
  (measured table), and stretched per size and weight to SF Pro's widths, measured over 400 of the app's strings
  (`tools/fontwidth`): widths now match within 0.1% at every size, so wrap points and line counts match the Mac.
  Translucent text colours drawn as macOS renders them (1 - (1 - a)^2, measured).
- Controls as macOS 27 draws them: sizes and padding per control size, translucent fills, capsule large and default
  buttons in the system's glass blue, pill switches and slider knobs, fields, pop-ups, progress bars, segmented controls.
- A view's appearance follows its window's; `draw(_:)` runs in the view's appearance.

**Evidence:** welcome pages 1-3 side by side (`welcome-diff`): same layout, wrap points, colours and controls. Control
gallery: every control's height matches; widths differ only where the Mac's `fittingSize` adds room. Traces 183/183 (worst
1.12e-6) and images 768/770 after all of it: no regression. Titled windows get Windows' dark title bar when their
appearance is dark, as Mac title bars follow it.

**Not done, and why:**
- **SF Symbols** (about 70 in the app) cannot ship on Windows: Apple licenses them for Apple platforms only. The
  stand-in's hand-drawn substitutes are wrong for many. Needs the owner's choice of a replacement set.
- The Mac's control gallery runs inactive (a process started from a shell cannot become the active app), so active
  colours were taken from the oracle's welcome pages instead.
- Glyph shapes are Segoe's (accepted difference); only their metrics follow SF Pro.

**Next:** symbols (after the owner decides); the taskbar shows a generic icon, not the app's; then the Panel itself, side by side, and the tray menu; then the spider on
the desktop with the real app's windows.

## 2026-11-15 (later): SF Symbols replaced by Fluent System Icons

The owner chose Microsoft's Fluent System Icons (MIT) to stand in for SF Symbols, which Apple licenses for Apple
platforms only. Every string in `Sources/` that AppKit accepts as a symbol name was collected (117 in use) and mapped in
`tools/symbols/fluent-map.txt`; a contact sheet of SF next to Fluent was used to pick replacements for the weak first
matches (U-turn arrows, dice, eyes, layers, tray, square.slash and others).

`tools/symbols/run.sh` fetches the pinned `@fluentui/svg-icons` 1.1.346 (checked by SHA-256) and, on the Mac, measures
each SF Symbol under every configuration the app asks for (the plain image and the 15 point-size/weight pairs in
`Sources/`): image size, and where its ink sits. Per weight it also finds how far to thicken the Fluent outline so it
carries as much ink as the SF Symbol (bisection on coverage at 16 pt). Outlines are written as absolute M/L/Q/C/Z
commands (arcs turned into curves), so `SymbolData.swift` needs no SVG parser on Windows. The stand-in draws the Fluent
design (16, 20 or 24) closest to one device pixel per unit, fitted into the SF Symbol's ink rectangle.
`THIRD_PARTY_NOTICES.md` carries Microsoft's licence and the installer ships it.

**Evidence:** the Panel's seven pages side by side (`tools/windows/swift/shot-diff SPIDER_PANEL_SHOT`): icons sit and
size as on the Mac. Traces 183/183 (worst 1.12e-6), images 768/770: unchanged.

**Seen on the Panel, not icons (next):** the header spider is drawn black (template image not tinted), section titles and
secondary text are dimmer, the selected tab's highlight is shorter, the Pause switch shows on where the Mac shows off,
and "Caffeinated" is cut off in its segment.

## 2026-11-15 (later still): The Panel against the Mac, and AppKit's rules behind the gaps

A workflow compared the Panel's seven pages with the Mac's (one agent per page, a merge, then a root cause per issue
measured on real AppKit, each checked by a skeptic): 33 issues, 13 diagnosed and confirmed. A second workflow reviewed
the fixes by area and confirmed 19 defects in them, all fixed. What AppKit does, measured on macOS 27 with probes, and
what the stand-in now does the same way:

- **Alignment rectangles.** Constraints act on a view's alignment rectangle, not its frame. A label's frame reaches 2
  points past its text on each side; a symbol image view or image-only button lines up the symbol's baseline-to-cap
  rectangle (now measured per symbol and configuration by `tools/symbols`); a borderless button with its image above a
  title lines up the image's top. Baselines too are measured from the alignment rectangle.
- **Priorities are strictly ranked.** No number of constraints at 249.99998 outweighs one at 250. The solver's objective
  is now one row per priority level, minimised in order (lexicographic simplex, as Cassowary describes); before, close
  priorities were weighed as near-equal numbers and outvoted by count, which narrowed the welcome's bullet rows.
- **Text fields:** AppKit's hugging and compression by kind (label 251 across; field 250 across and 750 down; wrapping
  and attributed labels 250 and 250); bezel and border flags coupled; widths to a half point; and the no-orphan line
  break (a word is pushed down so the last line is never one word; plain string drawing doesn't).
- **Text ink.** macOS dilates glyphs when it draws text (about 0.31 px a side for light text, 0.1 for dark, whatever the
  alpha), except in button titles and segment labels on macOS 27; label text and tinted stock buttons get the 1-(1-a)^2
  boost, checkboxes, segments, button subclasses and drawn strings don't. Ink now matches within 1-6% for labels, titles
  and buttons.
- **Popover vibrancy.** In a popover, secondary, tertiary, quaternary and disabled colours become opaque greys added
  plus-lighter by text fields, image views and borderless buttons; the filter stays when a view leaves the popover
  (which is why the Mac's panel pictures show that text brighter). Light mode keeps the plain colours (Skia has no
  plus-darker).
- **Controls:** the segmented control's padding, water-filled `.fillEqually` widths and centred overflow; the slider's
  per-size knob and bar, see-through knob and clamped value; the switch's off track (grey 90 at 52%) and disabled look
  (half the track, the knob unchanged); a button's 2-point image gap measured from the alignment width; disabled
  borderless buttons at half their tint; template images (bitmaps and drawn) tinted as masks; images drawn with
  lockFocus (the welcome's menu-bar icons were drawn at the view's corner instead).
- **Harness.** `shot-diff` starts both apps as already welcomed (`-welcomed YES`): a pending welcome pauses the spider,
  which was the only reason the Pause switch differed.

**Evidence:** Panel pages and welcome pages side by side (`shot-diff`); text ink per element against the Mac; layout
solves still 0.3 s at most. Traces 183/183 (worst 1.12e-6), images 768/770: unchanged.

**Not done:** the "Dance to Music" row is off and disabled because the audio service is still the Windows stub (sensors
phase). Live popover colours are modelled from AppKit's values but not compared live on screen.

**Second inventory (55 agents over the three welcome pages and seven Panel pages):** 37 smaller differences, of which:
- **The Mac's captures are Display P3**; Windows' are sRGB. Saturated colours read off them were off: the glass accent
  is sRGB (7, 123, 255), not (54, 121, 247). `shot-diff` now converts the Mac's pictures to sRGB before pairing them.
- **Glyph dilation by context** (ink measured against the Mac): full for labels, drawn strings and stock buttons, half
  for segment labels, a third for text composited plus-lighter, none for button subclasses that draw themselves. Ink
  per element is now within 0.89-1.09 of the Mac's, most within 6%.
- **No-orphan line breaks apply to two-line paragraphs only** (measured, 2 to 6 lines): longer ones keep the orphan.
- **Switch:** the off track in dark is white at 9.5% over its background, and the knob casts a faint shadow.
- Fluent's people and laptop icons are narrower than SF's in the same box (shape, accepted).
