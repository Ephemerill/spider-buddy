# Windows Spider Buddy — parity audit

**Date:** 5 November 2026  
**Scope:** `WINDOWS_PORT_SPEC.md`, `progress.md`, every source file in `src/` and `Sources/`, and the existing test/soak artifacts. The macOS Swift app is treated as the oracle and was not edited.

## Bottom line

This is a substantial, real port of a large portable core, with a serious headless harness and a working WinForms shell. It is **not yet a parity port of the desktop product**.

The strongest parts are the portable simulation and the test tooling: 94 C# files / 32,727 lines, 1,050 reported checks passing, a real 60 fps display ticker on short runs, 50 habitat open/close cycles, and a shell with the 12 Studio tabs, the seven-page panel, My Spiders, tray menu, settings, and update plumbing.

The largest gaps are exactly the parts that make it feel like the Mac app:

1. **One sprite overlay instead of a desktop layer stack.** Prey, toys, silk, traces, hammock, visitors, rain, box outline, and laser have core state but no desktop window or drawing path.
2. **Desktop tracking is a 1.8 Hz `GetWindowRect` poll**, not the event-driven, extended-frame, per-monitor tracker the spec asks for.
3. **The pointer is not window-hit-tested.** The overlay is permanently click-through, so clicks also reach the app underneath; scrolling is not wired to the spider at all.
4. **The pose/renderer contract is incomplete.** General occlusion, peek grip, weather/specks, web thread, ball/roll pose, name tag, and a screen-space thought bubble are missing or never reach the renderer.
5. **Native sensing is absent.** Power, weather, banners, audio/beat, lock/unlock, and full-screen cinema are implemented as portable state or settings flags, not as Windows sensors.
6. **Mac visual parity was never measured.** There is no macOS-generated PNG set, no live mixed-DPI/full-screen/audio/lock test, and no completed 30-minute 60 fps soak.
7. **The progress table overstates completion.** Several ✅ rows are contradicted by the report's own “host pending / not complete / not a pass” paragraphs and by the code.

## Source and evidence inventory

| Item | Actual |
|---|---|
| Spec | `WINDOWS_PORT_SPEC.md`, 1,827 lines |
| Progress | `progress.md`, ~56 KB |
| Windows source | 94 C# files, 32,727 lines under `src/` (including the generated habitat catalog) |
| macOS source | 57 Swift files, 73,432 lines under `Sources/` |
| Existing suite | `tools all` recorded **1050/1050** in `out/final-all-60.log` |
| Short 60 fps evidence | 10 s gate: 60.0–60.1 fps, 1.52 ms; 20 s soak: 60.0–60.1 fps, 1.57 ms |
| Full soak evidence | Pre-ticker 1800 s: ~39 fps; post-ticker 60 fps run stopped after ~13 min — **not a pass** |

I built an inventory of every source file, read the stage requirements and acceptance gates, read every host file, and followed each stage into its core and macOS oracle. This report cites exact files and line ranges. I did not treat a ✅ in `progress.md` as evidence.

**Verification limits:** no macOS-generated PNG set; no real mixed-DPI multi-monitor, full-screen video, lock/unlock, WASAPI, notification, or live input/capture environment; no production Authenticode certificate or installed-app update; no code was changed and nothing was committed.

---

## Stage matrix

Status here means **product parity**, not “the core harness has a check.”

| Stage | What the spec asks for | Windows evidence | Verdict |
|---|---|---|---|
| 0 | Decisions, platform boundaries | Core/host split is real; spec decisions recorded | ✅ architecture |
| 1 | Foundations, math, springs, rope, storage, clock | Core checks; real display ticker | ✅ core |
| 2 | Desktop windows become walkable surfaces | `DesktopCapture` polls every 0.55 s; `GetWindowRect`; hardcoded DPI/radius; no WinEvent hooks; page-film cinema only | ❌ product |
| 3 | Draw the spider | Detailed Skia renderer, but one sprite; name tag suppressed; thought text clipped by sprite bitmap | 🟡 partial |
| 4 | Modes, gait, legs, turning | 84 checks; progress admits slide tolerance was relaxed from 0.05 to 0.25 and exact/visual parity is not established | 🟡 partial |
| 5 | Pointer: touch, drag, throw, scroll, watch | Global mouse works, but window is always click-through; no scroll; `ClickToPickUp` not honored by host path; report itself says **“Stage 5 is NOT complete”**, and lists landing, bounces, and actual rescue catches as **not implemented** | ❌ |
| 6 | Brain, moods, repertoire | Core brain covers a subset; no autonomous hammock/web/rappel/swing/leap/bed behavior; 22 checks, self-commanded | 🟡 partial |
| 7 | Air, jumps, throws, landing, coverage | Core checks; no silk/window layer; coverage and rescue visuals incomplete | 🟡 partial |
| 8 | Silk, rappel, climb, swing, mantle, hammock | Core silk state exists; no silk window, no thread in the pose, dangling legs not updated, hammock not drawn | ❌ product |
| 9 | Peek-a-boo | `HiddenBy` is only the peek rect and the renderer ignores it; `PeekGrip` is ignored | ❌ product |
| 10 | Prey, feeding, wildlife | Prey core can be released; no prey window; Mac film comparison not run | ❌ product |
| 11 | Toys and laser | Toy state exists; no toy/laser window; native input pending | ❌ product |
| 12 | Traces | Trace core exists; no trace window; progress says host drawing pending | ❌ product |
| 13 | Memory/growing up | Memory logic exists; host save/places and 60 s autosave pending | 🟡 partial |
| 14 | Sensing the machine | Portable state only; no power, weather, banner, WASAPI, or session sensors; `ClockHz` unused | ❌ product |
| 15 | Box, visitors, thoughts | Core box/visitors; no drawn box, no visitor bodies, no desktop visitor window; native shell pending | ❌ product |
| 16 | Shell, panel, Studio, welcome, entrance | Real shell: 7 panel pages, 12 Studio tabs, My Spiders, tray, welcome, entrance; option grids use labels not thumbnails; live parity unverified | 🟡 partial |
| 17 | Habitat | 62 checks, 50 cycles, 60 s storm at 30 fps; item art is generic polygons; 30-minute evidence is a headless simulation | 🟡 partial |
| 18 | Talking, web pages, extension | Optional; phrase engine rather than a model; extension matrix unverified | 🟡 optional |
| 19 | Packaging/update/bug report | Plumbing exists; no production Authenticode or real installed-app update; bug report not live-fired | 🟡 partial |
| 20 | Test/verification harness | 1050 checks, useful artifacts; no Mac PNG diff; release gate passed a 39 fps run; no full 30-minute 60 fps pass | 🟡 evidence gap |

---

## F1 — One overlay is carrying a multi-window product (S1)

**Windows:** `src/App` has forms for the panel, Studio, welcome, chat, bug report, habitat, and one `SpiderOverlay` (`src/App/Program.cs:1837`). There is no `PreyWindow`, `SilkWindow`, `TraceWindow`, `HammockWindow`, `BoxWindow`, `LaserWindow`, or visitor window class. `Program.Draw` only calls `_overlay.Draw` (`src/App/Program.cs:1625-1650`), and `SpiderOverlay.Draw` draws only the sprite bitmap plus the first-entrance line (`src/App/Program.cs:1906-1934`).

**macOS:** `AppDelegate.swift:9-48` creates separate overlay windows for the spider, silk, hammock, prey, traces, laser, box outline, and rain; `AppDelegate.swift:876-915` sets them up. `SpiderRenderer.swift:343-367` draws peek grip dots, clips by `hiddenBy`, draws the emote, and draws the name tag. Visitors have their own windows in `AppDelegate.swift:1284-1320`.

**Consequence:** `Program.Feed`, `InviteVisitor`, `BuildHammock`, and `KeepInBox` mutate real core state (`src/App/Program.cs:943`, `1024`, `1038`, `1058`), but the product has no path to show prey, toys, silk, hammock, traces, visitors, rain, box outline, or laser. Several ✅ stage rows are testing state that the desktop never renders.

This is the single largest product gap.

## F2 — Desktop sensing is stale and geometrically wrong (S1)

`Program.Frame` rebuilds the map only when `now - _lastCapture > 0.55` (`src/App/Program.cs:1523`): about 1.8 Hz, not the spec's 30 Hz moving / 10 Hz still tracker, and with no `SetWinEventHook`.

`DesktopCapture` has the following concrete limitations:

- `GetWindowRect` for the frame (`src/App/DesktopCapture.cs:85`), not `DWMWA_EXTENDED_FRAME_BOUNDS`; Windows 10/11 invisible resize borders are included.
- `Dpi = 96` on every screen (`src/App/DesktopCapture.cs:51`), not per-monitor DPI.
- `CornerRadius = 12` for every window (`src/App/DesktopCapture.cs:101`), not the actual DWM radius; the spec's own corner tests use 8 and 26.
- A cloaked-window check exists (`DwmGetWindowAttribute` at line 74), but there is no `LWA_ALPHA`/layered-alpha check, no shell-owner filtering, and no pop-up/banner detection.
- `Signature` only hashes id, frame, depth, and maximized (`src/App/DesktopCapture.cs:111-115`); title/content/alpha/full-screen changes are invisible.
- No full-screen “fills the display” detection and no cinema map clipping. `Program.LayoutMap` adds only page-film screens to `CinemaScreens` (`src/App/Program.cs:1370`); the portable `EnterCinema` path is called only by test tools.
- No window event subscription at all.

The spec asks for extended frame bounds, per-monitor DPI, real corner radius, alpha/ignored windows, full-screen detection, banner events, and moving-window tracking. The Mac `WindowTracker`/`SurfaceMap` uses event hooks and `map.occluders`; Windows uses a 0.55 s static poll.

**Visible effects:** the spider can walk on stale rectangles for up to 0.55 s, sit on invisible window borders, use the wrong corner on Windows 11, treat a hidden/translucent window as solid, and miss cinema/banner transitions entirely.

## F3 — Pointer interaction is global and click-through, not hit-tested (S1)

`SpiderOverlay.CreateParams` always sets `WS_EX_TRANSPARENT` (`src/App/Program.cs:1892`). There is no hit-test window, no `WM_NCHITTEST`, and no per-tick “wants mouse” toggle. The Mac does exactly that: `OverlayWindow.swift:423` starts click-through, `OverlayWindow.swift:732` can become interactive, and `AppDelegate.swift:1018-1033` switches `ignoresMouseEvents` based on `spider.hitTest`/bubble/prey hits.

The Windows host does read global buttons with `GetAsyncKeyState` (`src/App/Program.cs:1545-1546`), so poke/grab can happen — but **every click also goes to the application underneath**. That is not pass-through everywhere except the spider; it is double delivery on the spider. Right-clicks can also open the app-under context menu as well as the spider menu.

The host path also differs from its own core hit test:

- `over` is a distance check at `(GrabRadius + 8) * Scale` (`src/App/Program.cs:1544`), not `Spider.HitTest` (`src/Core/Spider.cs:510`), which enforces `ClickToPickUp` and excludes `Mode.Clinging`.
- With **Click to Pick Up off**, `_pressed` is still true and the `else if (_pressed) _spider.Poke()` branch (`src/App/Program.cs:1560`) still reacts. The spec says the spider ignores the pointer when that option is off.
- The host branch does not check `Mode.Clinging`; a click during clinging can begin a grab that the spec says must pass through.
- The cinema guard only wraps `BeginGrab`; the fall-through `Poke` path has no host-level cinema guard.
- `SpiderPointerInput` implements the reference's click/flick/cancel rules (`src/Core/SpiderPointerInput.cs`) but is not referenced from `src/App`; the host uses a second, weaker implementation.

**Scrolling is absent from the desktop host.** `Spider.Scroll` exists and `ScrollOrdered` is subscribed (`src/App/Program.cs:363`), but no host code calls `Scroll`; there is no `MouseWheel` handler in `Program`. `PageInputHook` is page scrolling, not spider scrolling. The spec's one-swipe-one-order path is therefore test-only.

`SetCursor` is called every frame, but `Spider.SetCursor` early-returns on the same point (`src/Core/SpiderPointer.cs:202-210`), so the parked-pointer behavior is not broken by that call. The larger pointer problem is pass-through/hit-test, not cursor freshness.

## F4 — The pose and renderer contracts are incomplete (S1/S2)

`Spider.BuildPose` (`src/Core/Spider.cs:434-496`) sets the body fields, legs, emote/thought, name opacity, and then only:

```csharp
if (Peek != PeekPhase.None)
{
    if (_peekHidden) pose.HiddenBy.Add(PeekRect);
    pose.PeekGrip.Add(...);
    pose.PeekGrip.Add(...);
}
```

There is no general occlusion list from `map.occluders`, unlike Mac `Spider.swift:20335-20343`, which intersects the sprite with every window in front of the loop. There is no `Wet`, `Snow`, `Dust`, `Chill`, `Specks`, or `Surroundings` assignment even though `SpiderPose` has those fields (`src/Core/Draw.cs:178-184`). There is no `Ball` or `Spin` assignment; `Activity.Roll` exists in the brain (`src/Core/SpiderBrain.cs:228`) and `SpiderPose.Ball` exists (`src/Core/Draw.cs:137`), but the pose never fills it. `SpiderPose` has no web/thread field at all.

The Windows renderer does not consume `HiddenBy` or `PeekGrip`; neither name appears in `src/Renderer/SpiderRenderer.cs`. The Mac renderer does both (`SpiderRenderer.swift:343-367`), and it draws the name tag. Windows deliberately disables the name tag in the raster path (`src/Renderer/SpriteRaster.cs:44`) and has no second layer to draw it.

Dangling and hammock poses are also not built:

- `Spider.Update` calls `UpdateDangling` in `Mode.Dangling` (`src/Core/Spider.cs:215`) but only calls `UpdateLegs` for `Mode.Attached` (`src/Core/Spider.cs:229`). The legs rendered on a thread are the last attached-gait legs, not the spec's four silk-holding legs + four hanging legs.
- `UpdateHammock` (`src/Core/Spider.cs:221`) moves `Pos` to the bed but does not tuck the legs; `BuildPose` still uses the walking gait. The hammock art itself has no window.
- `Posture.For` has no `Roll` or `Hop` branch (the switch in `src/Core/Activities.cs:90-140` has `Spin` and many others, then `default`), and `DoubleTake` contains the dead `u < 0.45 ? 1 : 1` expression.

**Thought bubble clipping:** `SpriteRaster` allocates `max(100, 144·scale)` pixels (`src/Renderer/SpriteRaster.cs:15-20`). Text bubbles are laid out at `pos.x + 16` with width up to `190 * scale` (`src/Renderer/SpiderRenderer.cs:1724-1757`). At scale 1 that is a right edge near 206 in a 144-pixel bitmap, so long text is clipped. There is no separate bubble window/bitmap. Icon bubbles can fit; text bubbles generally cannot. This is a visible regression against the Mac's screen-space bubble.

## F5 — Native sensing is a portable model with no Windows sensors (S1)

`SpiderSensing` defines cinema, low power, charger, weather, banners, commotion, music, and lock/unlock state (`src/Core/SpiderSensing.cs`). The only callers of the state-changing methods are test tools:

- `SetWeather`, `SetLowPower`, `PlugIn`, `OnBanner`, `OnCommotion`, `SetMusic`, `SetLocked`, `EnterCinema` are called from `src/Tools/Stage14.cs` / `Stage20.cs`, not from `src/App`.
- `ShowRain` is written by the panel and settings (`src/App/PanelForm.cs:408`, `src/App/Program.cs:446`) but no renderer reads it.
- `ClockHz` is defined as 30/60 (`src/Core/SpiderSensing.cs:20`) but the host `DisplayTicker` always uses `DwmFlush`; there is no 30 Hz low-power path.
- `MusicPlaying` can only be set by tests; the panel therefore normally says “No music detected.”
- `BannerCount` is never incremented in the host; there is no toast/banner watcher.
- `LowPowerOverride` is set by the panel (`src/App/PanelForm.cs:402`), but the host does not call `SetLowPower`; `feelPower` is stored but never read.
- There is no WASAPI loopback or beat tracker, no Open-Meteo lookup, no power broadcast, no volume/brightness callback, and no session-lock event.
- `Cinema` is not entered from Windows full-screen detection; only the page-film code adds `CinemaScreens` to the desktop map.

The Stage 14 row is ✅, but the progress text itself says the native capture is “Stage 16 work” (`progress.md:501-510`). This is not a subtle gap: all of the machine-awareness behavior is absent in the shipped product.

## F6 — The brain is a smaller repertoire, and hammock/web behaviors are menu-only (S2)

`SpiderBrain.Think` (`src/Core/SpiderBrain.cs:106-152`) has only a subset of spec 6.2's priority list. It handles box return, sleep, pointer approach, quarry, toy, peek-a-boo, then attention/leisure. It has no priority for cinema, homing/hammock, laser, visitor tag, meal carrying, web job, music, tank errand, weather, fright, inquiry, or bed-on-a-window. It also has no `BuildHammock`, `NapInHammock`, `DropOnWeb`, `StartSwing`, or `Rappel` action in `PickLeisure` (`src/Core/SpiderBrain.cs:186-233`). `Hammock` and `Nap` habit weights are exposed in the Studio, but the brain never uses them; hammock construction is only reachable from host UI (tray/panel), never from the autonomous brain.

The spec's 6.3 out-and-about set includes autonomous leap, rappel, swing, build hammock, nap, mend, finish hammock, explore, bounce, and web jobs. Those are absent from the weighted draw. The 22 Stage 6 checks are therefore checks of a smaller system, not of the specified repertoire.

This compounds F1: even when a behavior exists in core, the host often has no visual path for it. The result is a spider with a convincing walk and gestures, but not the full Mac “living on the desktop” behavior.

## F7 — Customization is data-rich but art-poor (S2)

The Studio exposes 38 hats, 30 accessories, and 20 patterns. The renderer has detailed cases for 24 hats, 20 accessories, and 10 patterns.

- **13 hats have no case:** Bucket, Viking, Tiara, Pirate, Mushroom, Sombrero, Mortarboard, Sailor, Jester, Ushanka, Sweatband, FlowerCrown, LittleBird. They fall through to the generic shape at `src/Renderer/SpiderRenderer.cs:1260`.
- **9 accessories have no case:** Beard, FlowerLei, Headphones, Tutu, Backpack, Satchel, Bindle, Jetpack, Balloon. They fall through at `src/Renderer/SpiderRenderer.cs:1448`.
- **9 patterns have no case:** Skull, Moon, Flower, Leopard, Speckle, Marble, Zigzag, Diamonds, Rings. They fall through to a single generic central spot at `src/Renderer/SpiderRenderer.cs:552`.
- The Studio option grids use labels rather than raster thumbnails; the progress report admits this (`progress.md:584`).

This is not a small cosmetic gap: the Studio is the product's customization surface, and roughly a third of the hats, nearly a third of the accessories, and nearly half of the markings do not render as designed. The Mac renderer is the oracle; these fallback shapes are not parity.

## F8 — The habitat is a real simulation with generic art at 30 fps (S2)

`src/App/HabitatWindow.cs` is a real window with a 50-cycle open/close pass and 62 checks. But:

- The repaint timer is `Interval = 33` (`src/App/HabitatWindow.cs:99`): 30 fps in the habitat, not 60.
- `DrawItem` takes `HabitatGeometry.For(item).Visual`, fills the polygons, draws an outline, and adds a shifted highlight every third shape (`src/App/HabitatWindow.cs:1412-1445`). It does not have per-kind item art. A log, a lantern, a fireplace, and a door are all polygon fills from their collision/visual geometry.
- `DrawBackdrop` is a biome gradient plus a sun/stars/rainbow (`src/App/HabitatWindow.cs:1343-1371`); `DrawScenery` is 18 tree strokes for forest/jungle/meadow, a sea strip for beach, and 12 crystals for cave (`src/App/HabitatWindow.cs:1374-1400`). The Mac habitat has `HabitatHomeArt` (1,009 lines), `HabitatNatureArt` (1,377), `HabitatPieceArt` (555), `HabitatAtmosphere` (593), and `HabitatWeather` (1,698), plus the spec's ~5.7k lines of item/weather art.
- The Stage 17 evidence is a 60-second storm soak at 24.0% CPU / 30 fps (`progress.md:602`). Stage 20 describes the 30-minute habitat check as the headless `stage20 perch --habitat-seconds=1800` simulation; no 30-minute GUI habitat soak at the spec's ≤25% storm target is reported.

The habitat is not a stub, but its look is a geometric approximation, and its performance target is measured on a different clock than the desktop overlay.

## F9 — Desktop features that exist only as state (S1/S2)

These are reachable from the host menu/panel but have no desktop representation:

- **Prey:** `Feed` calls `ReleasePrey`; no prey window, no creature drawing, no prey hit/drag path.
- **Toys/laser:** `PanelForm` has toy buttons (`src/App/PanelForm.cs:381-392`), but no toy window, no laser dot, no hand-toy rendering.
- **Silk:** `DropOnWeb`, `StartSwing`, `ObeyScroll`, and `WebActive` exist in `src/Core/SpiderSilk.cs`; the only desktop line is the first-entrance line. No thread is drawn while hanging; no rope edge is drawn.
- **Hammock:** `BuildHammock`/`NapInHammock` exist; no hammock window or pose; the spider is not curled in it.
- **Traces:** `SpiderTraces` state exists; no trace window; no little webs, meals, or strands on the desktop.
- **Visitors:** `InviteVisitor` spawns a visitor `Spider`; no visitor window, no second sprite, no tag/dance/leave visuals.
- **Box:** `KeepInBox` calls `SpiderBox` but there is no dimmed desktop, drag-to-draw rectangle, dashed outline, or redraw UI; `Program.cs:1058` just confines around the current position.
- **Rain:** `ShowRain` is a setting/panel flag; there is no rain layer.
- **Laser/box draw:** no `LaserWindow`/`BoxDrawWindow` classes.
- **Memory:** `SaveAll` is event-driven; the spec's 60-second autosave is not present (`progress.md:498` still lists it as host work), and host favorite-place use is pending.
- **Chat/name:** `BubbleAt` can open chat from the invisible bubble, but the bubble is clipped by the sprite; the name tag is never drawn.

## F10 — The evidence does not support “parity” (S1 as an audit finding)

The suite is real. The problem is what it establishes.

- `tools all` records **1050/1050** (`out/final-all-60.log`). That is a genuine pass of the current harness.
- The 10 s gate and 20 s soak are genuinely 60.0–60.1 fps.
- The pre-ticker 1800 s desktop run was **~39 fps** (`progress.md:739-740`) and still printed `RELEASE GATE PASSED` (`progress.md:746`). The release gate does not enforce the 60 fps target.
- The post-ticker 60 fps run was stopped after ~13 minutes (`progress.md:742-743`); the report explicitly says it is **not** a completed 30-minute pass (`progress.md:772-774`).
- The Stage 4 caution says the slide tolerance was relaxed from 0.05 to 0.25 (`progress.md:424`), and exact world-fixed feet/perceptual invisibility remain unaudited.
- Stage 5's own section says **“Stage 5 is NOT complete”** (`progress.md:419`) while the table marks it ✅ with 95 checks; the same section says landing, bounces, and actual rescue catches are **not implemented** (`progress.md:402`) and still open (`progress.md:416`).
- Stage 10 says the Mac film comparison was not run; Stage 12 says host drawing pending; Stage 13 says host save/places pending; Stage 14 says native capture pending; Stage 15 says native shell pending; Stage 16 admits labels not thumbnails; Stage 20's 30-minute habitat check is a headless sim; Stage 20 says no macOS PNG diff and no full 30-minute 60 fps pass.
- The progress report's own summary says the counts are “not proof of full feature parity” because some harnesses command the behavior they check (`progress.md:48-49`).

So the right reading is: **the core is tested; the product is not proven.** A 1050-check green suite and a one-overlay sprite demo can coexist with missing prey, silk, traces, visitors, native sensing, and click pass-through, which is exactly what this codebase shows.

## What is genuinely good

- The core/host split is real and keeps Win32 out of the simulation.
- 94 C# source files / 32.7k lines are a serious implementation, not a mock.
- The 60 fps `DwmFlush` ticker is a meaningful fix; short runs really hold 60.0–60.1 fps.
- The 1,050-check harness found and fixed real defects (foot world positions, planted-foot conversion, stale feet, corner mapping).
- The shell is real: tray, seven-page panel, 12-tab Studio, My Spiders with save/copy/delete, welcome, entrance, persistence, update service, bug-report form.
- The habitat has a real world, 50 open/close cycles, 62 checks, and a 60-second storm sample.
- The project has not overfit by deleting the Mac source; `Sources/` is the oracle.

## Highest-leverage repair order

1. **Build the desktop layer stack** (or a single full-screen layered compositor with per-layer bitmaps): silk/thread, prey/toys, traces, hammock, visitors, rain, box outline, laser, name tag, and screen-space thought bubble. This closes F1 and most of F4/F9 at once.
2. **Replace the desktop poll with an event-driven tracker** and extended frame bounds, actual DPI, actual corner radius, alpha/ignored-window filtering, full-screen/cinema, and banner events. This closes F2/F5's input side.
3. **Make the overlay hit-tested:** toggle `WS_EX_TRANSPARENT` or use `WM_NCHITTEST`, consume clicks only over the spider/bubble, wire `MouseWheel` through `Spider.Scroll`, and use `Spider.HitTest`/`SpiderPointerInput` rather than the duplicate global path. This closes F3.
4. **Complete the pose contract:** `HiddenBy` from occluders, `PeekGrip`, web/thread, wet/snow/dust/specks, ball/spin, dangling/hammock legs, and a separate name/bubble canvas. This closes F4 and makes Stages 8/9 visible.
5. **Feed native sensors** (power, weather, music/beat, banners, lock/unlock, full-screen) and make the panel switches read back real state. This closes F5.
6. **Make the visual/perf gates honest:** macOS PNG/film A/B, real mixed-DPI/full-screen/lock, and a full 30-minute 60 fps soak with a gate that fails below 60. This closes F10.

## Verification statement

I did not change any code, Swift or C#. This audit is based on source inspection and the existing artifacts. The existing harness passes are reported as harness passes, not as parity. The most important limitation is the absence of a macOS-generated visual set and a real Windows sensor/input environment; several findings above are therefore code-level certainties (missing windows, missing calls, missing fields), while visual severity is judged from the code and the Mac oracle.
