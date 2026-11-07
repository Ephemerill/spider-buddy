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
